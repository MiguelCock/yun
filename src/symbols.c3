module yun::symbols;

import raylib6::rl;
import std::atomic::types;
import std::collections::list;
import std::collections::map;
import std::core::mem::alloc;
import std::io::file;
import std::math::geometry;
import std::os;
import std::thread;
import std::thread::channel;
import tree_sitter;
import yun::commands;
import yun::editor;
import yun::highlight;
import yun::keymap;
import yun::project;
import yun::theme;
import yun::ui;

enum SymbolKind : int
{
	FUNCTION,
	METHOD,
	CLASS,
	TYPE,
	ENUM,
	CONST,
	VARIABLE,
}

struct Symbol
{
	String name;
	SymbolKind kind;
	usz line;
	usz column;
}

struct CardSymbols
{
	String path;
	List{Symbol} symbols;
}

struct SymbolBatch
{
	String path;
	List{Symbol} symbols;
	uint generation;
}

struct SymbolWork
{
	Symbols* owner;
	String path;
	highlight::Language language;
	uint generation;
}

struct SymbolRef
{
	int file;
	int index;
}

struct SymbolTarget
{
	bool valid;
	String path;
	usz line;
	usz column;
}

const int MAX_SYMBOL_WORKERS = 4;
const int QUERY_MAX          = 128;
const double EDIT_DEBOUNCE   = 0.15;
const int MAX_VISIBLE_ROWS   = 14;
const float TOP_MARGIN       = 24.0f;

struct Symbols
{
	Allocator allocator;
	// index
	List{CardSymbols} files;
	HashMap{String, int} file_index;
	ThreadPool pool;
	bool pool_ready;
	UnboundedChannel{SymbolBatch}* results;
	uint generation;
	usz pending;
	usz received;
	bool scanning;
	usz known_cards;
	Atomic{bool} cancel;
	bool pending_edit;
	String pending_path;
	double pending_since;
	String root;
	// overlay
	bool open;
	char[QUERY_MAX] query;
	usz query_len;
	List{SymbolRef} matches;
	bool dirty;
	int selected;
	int scroll;
	bool consumed;
}

fn String def_query_text(highlight::Language language)
{
	switch (language)
	{
		case highlight::Language.C3:
			return "(func_definition (func_header name: (ident) @function))\n"
				"(func_declaration (func_header name: (ident) @function))\n"
				"(macro_declaration (macro_header name: (_) @function))\n"
				"(struct_declaration name: (type_ident) @type)\n"
				"(interface_declaration name: (type_ident) @type)\n"
				"(bitstruct_declaration name: (type_ident) @type)\n"
				"(typedef_declaration name: (type_ident) @type)\n"
				"(enum_declaration name: (type_ident) @enum)\n"
				"(constdef_declaration name: (type_ident) @const)";
		case highlight::Language.C:
			return "(function_definition declarator: (function_declarator declarator: (identifier) @function))\n"
				"(struct_specifier name: (type_identifier) @type)\n"
				"(enum_specifier name: (type_identifier) @enum)\n"
				"(type_definition declarator: (type_identifier) @type)\n"
				"(declaration declarator: (init_declarator declarator: (identifier) @variable))\n"
				"(declaration declarator: (identifier) @variable)";
		case highlight::Language.PYTHON:
			return "(function_definition name: (identifier) @function)\n"
				"(class_definition name: (identifier) @class)";
		case highlight::Language.JAVASCRIPT:
			return "(function_declaration name: (identifier) @function)\n"
				"(class_declaration name: (identifier) @class)\n"
				"(method_definition name: (property_identifier) @method)\n"
				"(variable_declarator name: (identifier) @variable)";
		case highlight::Language.NONE:
			return "";
	}
}

fn TSQuery* make_query(highlight::Language language, String text)
{
	if (text.len == 0) return null;
	uint offset        = 0;
	TSQueryError error = TS_QUERY_ERROR_NONE;
	TSQuery* query = tree_sitter::ts_query_new(
		highlight::grammar_language(language),
		(char*)text.ptr,
		(uint)text.len,
		&offset,
		&error
	);
	if (!query || error != TS_QUERY_ERROR_NONE) return null;
	return query;
}

fn bool kind_from_capture(String name, SymbolKind* out)
{
	if (name.compare_to("function") == 0)
	{
		*out = SymbolKind.FUNCTION;
		return true;
	}
	if (name.compare_to("method") == 0)
	{
		*out = SymbolKind.METHOD;
		return true;
	}
	if (name.compare_to("class") == 0)
	{
		*out = SymbolKind.CLASS;
		return true;
	}
	if (name.compare_to("type") == 0)
	{
		*out = SymbolKind.TYPE;
		return true;
	}
	if (name.compare_to("enum") == 0)
	{
		*out = SymbolKind.ENUM;
		return true;
	}
	if (name.compare_to("const") == 0)
	{
		*out = SymbolKind.CONST;
		return true;
	}
	if (name.compare_to("variable") == 0)
	{
		*out = SymbolKind.VARIABLE;
		return true;
	}
	return false;
}

fn String kind_label(SymbolKind kind)
{
	switch (kind)
	{
		case SymbolKind.FUNCTION:
			return "fn";
		case SymbolKind.METHOD:
			return "method";
		case SymbolKind.CLASS:
			return "class";
		case SymbolKind.TYPE:
			return "type";
		case SymbolKind.ENUM:
			return "enum";
		case SymbolKind.CONST:
			return "const";
		case SymbolKind.VARIABLE:
			return "var";
	}
}

fn void extract_file(Allocator allocator, String path, highlight::Language language, List{Symbol}* out)
{
	if (language == highlight::Language.NONE) return;
	@pool()
	{
		char[]? data = file::load(tmem, path);
		if (catch excuse = data) return;
		String text = (String)data;

		TSParser* parser = tree_sitter::ts_parser_new();
		if (!parser) return;
		if (!tree_sitter::ts_parser_set_language(parser, highlight::grammar_language(language)))
		{
			tree_sitter::ts_parser_delete(parser);
			return;
		}
		TSQuery* query = make_query(language, def_query_text(language));
		if (!query)
		{
			tree_sitter::ts_parser_delete(parser);
			return;
		}

		TSTree* tree = tree_sitter::ts_parser_parse_string(parser, null, (char*)text.ptr, (uint)text.len);
		if (tree)
		{
			TSNode root           = tree_sitter::ts_tree_root_node(tree);
			TSQueryCursor* cursor = tree_sitter::ts_query_cursor_new();
			if (cursor)
			{
				tree_sitter::ts_query_cursor_exec(cursor, query, root);
				TSQueryMatch match;
				uint capture_index = 0;
				uint last_match    = 0xFFFFFFFF;
				bool first         = true;
				while (tree_sitter::ts_query_cursor_next_capture(cursor, &match, &capture_index))
				{
					if (!first && match.id == last_match) continue;
					last_match = match.id;
					first = false;
					for (uint c = 0; c < match.capture_count; c++)
					{
						TSQueryCapture capture = match.captures[c];
						uint name_len = 0;
						char* capture_name = tree_sitter::ts_query_capture_name_for_id(query, capture.index, &name_len);
						if (!capture_name || name_len == 0) continue;
						SymbolKind kind;
						if (!kind_from_capture((String)capture_name[0:name_len], &kind)) continue;

						uint start = tree_sitter::ts_node_start_byte(capture.node);
						uint end   = tree_sitter::ts_node_end_byte(capture.node);
						if (end <= start || end > text.len) continue;
						TSPoint point = tree_sitter::ts_node_start_point(capture.node);
						out.push(
							{
								.name = text[start:end - start].copy(allocator),
								.kind = kind,
								.line = point.row,
								.column = point.column,
							}
						);
					}
				}
				tree_sitter::ts_query_cursor_delete(cursor);
			}
			tree_sitter::ts_tree_delete(tree);
		}
		tree_sitter::ts_query_delete(query);
		tree_sitter::ts_parser_delete(parser);
	};
}

fn void symbol_worker(void* arg)
{
	SymbolWork* work             = (SymbolWork*)arg;
	Symbols* symbols             = work.owner;
	String path                  = work.path;
	highlight::Language language = work.language;
	uint generation              = work.generation;

	List{Symbol} out;
	out.init(symbols.allocator);
	if (!symbols.cancel.load())
	{
		extract_file(symbols.allocator, path, language, &out);
	}
	SymbolBatch batch = { .path = path, .symbols = out, .generation = generation };
	if (symbols.results) (void)symbols.results.push(batch);
	alloc::free(symbols.allocator, work);
}

fn void Symbols.clear_files(&self)
{
	for (sz i = 0; i < self.files.len(); i++)
	{
		for (sz s = 0; s < self.files[i].symbols.len(); s++)
		{
			self.files[i].symbols[s].name.free(self.allocator);
		}
		self.files[i].symbols.free();
		self.files[i].path.free(self.allocator);
	}
	self.files.clear();
	self.file_index.clear();
}

fn void Symbols.clear_pending_edit(&self)
{
	if (self.pending_path.len) self.pending_path.free(self.allocator);
	self.pending_path = "";
	self.pending_edit = false;
}

fn void Symbols.init_pool(&self)
{
	int workers = os::num_cpu();
	if (workers < 2) workers = 2;
	if (workers > MAX_SYMBOL_WORKERS) workers = MAX_SYMBOL_WORKERS;
	if (catch excuse = self.pool.init(self.allocator, workers))
	{
		self.pool_ready = false;
		return;
	}
	UnboundedChannel{SymbolBatch}*? created = channel::create_unbounded{SymbolBatch}(self.allocator);
	if (catch excuse = created)
	{
		self.pool.destroy();
		self.pool_ready = false;
		return;
	}
	self.results = created;
	self.pool_ready = true;
	(void)self.pool.prewarm(workers);
}

fn void Symbols.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.files.init(allocator);
	self.file_index.init(allocator);
	self.matches.init(allocator);
	self.generation = 0;
	self.pending = 0;
	self.received = 0;
	self.scanning = false;
	self.known_cards = 0;
	self.cancel.store(false);
	self.pending_edit = false;
	self.pending_path = "";
	self.pending_since = 0.0;
	self.root = "";
	self.open = false;
	self.query_len = 0;
	self.query[0] = 0;
	self.dirty = false;
	self.selected = 0;
	self.scroll = 0;
	self.consumed = false;
	self.results = null;
	self.pool_ready = false;
	self.init_pool();
}

fn void Symbols.destroy(&self)
{
	if (self.pool_ready)
	{
		self.pool.destroy();
		self.pool_ready = false;
	}
	if (self.results)
	{
		self.results.destroy();
		self.results = null;
	}
	self.clear_files();
	self.clear_pending_edit();
	self.files.free();
	self.file_index.free();
	self.matches.free();
	if (self.root.len) self.root.free(self.allocator);
}

fn String Symbols.query_view(&self)
{
	return (String)self.query[0:self.query_len];
}

fn String Symbols.relative(&self, String path)
{
	if (self.root.len > 0 && path.len > self.root.len && path[0:self.root.len].compare_to(
		self.root
	) == 0 && path[self.root.len] == '/')
	{
		return path[self.root.len + 1:path.len - self.root.len - 1];
	}
	return path;
}

fn void Symbols.set_root(&self, String root)
{
	if (self.root.len) self.root.free(self.allocator);
	self.root = root.copy(self.allocator);
}

fn void Symbols.start_scan(&self, project::Project* project)
{
	self.clear_files();
	self.set_root((String)project.root);
	self.known_cards = (usz)project.cards.len();
	self.generation++;
	self.cancel.store(false);
	self.scanning = true;
	self.pending = 0;
	self.received = 0;
	self.dirty = true;
	self.clear_pending_edit();

	if (!self.pool_ready) return;

	@pool()
	{
		HashMap{String, int} seen;
		seen.init(tmem);
		for (sz i = 0; i < project.cards.len(); i++)
		{
			String path = (String)project.cards[i].path;
			if (seen.has_key(path)) continue;
			seen.set(path, 0);
			highlight::Language language = highlight::language_for_path(path);
			if (language == highlight::Language.NONE) continue;

			SymbolWork* work = alloc::new(self.allocator, SymbolWork);
			work.owner = self;
			work.path = path.copy(self.allocator);
			work.language = language;
			work.generation = self.generation;
			if (catch excuse = self.pool.add_task(&symbol_worker, work))
			{
				work.path.free(self.allocator);
				alloc::free(self.allocator, work);
				continue;
			}
			self.pending++;
		}
	};
	if (self.pending == 0) self.scanning = false;
}

fn void Symbols.sync(&self, project::Project* project)
{
	if (self.known_cards != (usz)project.cards.len()) self.start_scan(project);
}

fn void Symbols.note_edit(&self, String path, double now)
{
	if (self.pending_path.compare_to(path) != 0)
	{
		if (self.pending_path.len) self.pending_path.free(self.allocator);
		self.pending_path = path.copy(self.allocator);
	}
	self.pending_edit = true;
	self.pending_since = now;
}

fn void Symbols.store(&self, String path, List{Symbol}* symbols)
{
	int*? existing = self.file_index.get_ref(path);
	if (catch excuse = existing)
	{
		CardSymbols entry;
		entry.path = path.copy(self.allocator);
		entry.symbols = *symbols;
		self.files.push(entry);
		self.file_index.set(entry.path, (int)(self.files.len() - 1));
		return;
	}
	CardSymbols* entry = &self.files[*existing];
	for (sz i = 0; i < entry.symbols.len(); i++) entry.symbols[i].name.free(self.allocator);
	entry.symbols.free();
	entry.symbols = *symbols;
}

fn void Symbols.flush_edits(&self, project::Project* project, double now)
{
	if (!self.pending_edit) return;
	if (now - self.pending_since < EDIT_DEBOUNCE) return;

	String path = self.pending_path;
	self.pending_path = "";
	self.pending_edit = false;

	int index = project.find_card(path);
	if (index >= 0)
	{
		highlight::Language language = highlight::language_for_path(path);
		List{Symbol} out;
		out.init(self.allocator);
		extract_file(self.allocator, path, language, &out);
		self.store(path, &out);
		self.dirty = true;
	}
	path.free(self.allocator);
}

fn void Symbols.free_batch(&self, SymbolBatch* batch)
{
	for (sz i = 0; i < batch.symbols.len(); i++) batch.symbols[i].name.free(self.allocator);
	batch.symbols.free();
	batch.path.free(self.allocator);
}

fn void Symbols.pump(&self, project::Project* project, double now)
{
	self.sync(project);
	self.flush_edits(project, now);

	if (self.results)
	{
		while (true)
		{
			SymbolBatch? maybe = self.results.try_pop();
			if (catch excuse = maybe) break;
			SymbolBatch batch = maybe;
			if (batch.generation == self.generation)
			{
				self.received++;
				self.store(batch.path, &batch.symbols);
				batch.path.free(self.allocator);
				self.dirty = true;
			}
			else
			{
				self.free_batch(&batch);
			}
		}
	}
	if (self.scanning && self.received >= self.pending) self.scanning = false;
}

fn void Symbols.refilter(&self)
{
	self.matches.clear();
	self.dirty = false;

	String query = self.query_view();
	for (sz f = 0; f < self.files.len(); f++)
	{
		CardSymbols* file = &self.files[f];
		for (sz s = 0; s < file.symbols.len(); s++)
		{
			if (query.len == 0)
			{
				self.matches.push({ .file = (int)f, .index = (int)s });
				continue;
			}
			usz[QUERY_MAX] positions;
			int score = commands::fuzzy_match(file.symbols[s].name, query, positions[0:QUERY_MAX]);
			if (score < 0) continue;
			self.matches.push({ .file = (int)f, .index = (int)s });
		}
	}
	if (self.selected >= (int)self.matches.len()) self.selected = (int)self.matches.len() - 1;
	if (self.selected < 0) self.selected = 0;
}

fn int Symbols.match_count(&self)
{
	return (int)self.matches.len();
}

fn Symbol* Symbols.symbol_of(&self, SymbolRef ref)
{
	return &self.files[(sz)ref.file].symbols[(sz)ref.index];
}

fn SymbolTarget Symbols.activate(&self)
{
	SymbolTarget target = { .valid = false, .path = "", .line = 0, .column = 0 };
	if (self.selected < 0 || self.selected >= (int)self.matches.len()) return target;
	SymbolRef ref = self.matches[(sz)self.selected];
	target.valid = true;
	target.path = self.files[(sz)ref.file].path;
	target.line = self.files[(sz)ref.file].symbols[(sz)ref.index].line;
	target.column = self.files[(sz)ref.file].symbols[(sz)ref.index].column;
	return target;
}

fn void Symbols.show(&self)
{
	self.open = true;
	self.query_len = 0;
	self.query[0] = 0;
	self.selected = 0;
	self.scroll = 0;
	self.dirty = true;
}

fn void Symbols.close(&self)
{
	self.open = false;
}

fn void Symbols.move_selection(&self, int delta)
{
	int count = (int)self.matches.len();
	if (count == 0) return;
	int next = self.selected + delta;
	if (next < 0) next = 0;
	if (next >= count) next = count - 1;
	self.selected = next;
}

fn void Symbols.ensure_visible(&self, int visible_rows)
{
	if (visible_rows < 1) visible_rows = 1;
	if (self.selected < self.scroll) self.scroll = self.selected;
	if (self.selected >= self.scroll + visible_rows) self.scroll = self.selected - visible_rows + 1;
	if (self.scroll < 0) self.scroll = 0;
}

fn Rect Symbols.panel_rect(&self)
{
	float s      = ui::scale();
	int screen_w = rl::get_screen_width();
	int screen_h = rl::get_screen_height();
	float width  = 640.0f * s;
	if (width > (float)screen_w - 24.0f) width = (float)screen_w - 24.0f;
	int rows = (int)self.matches.len();
	if (rows > MAX_VISIBLE_ROWS) rows = MAX_VISIBLE_ROWS;
	if (rows < 1) rows = 1;
	float height = 90.0f * s + (float)rows * 22.0f * s;
	if (height > (float)screen_h - TOP_MARGIN - 24.0f) height = (float)screen_h - TOP_MARGIN - 24.0f;
	return { .x = ((float)screen_w - width) / 2.0f, .y = TOP_MARGIN, .width = width, .height = height };
}

fn int Symbols.visible_rows(&self)
{
	float s      = ui::scale();
	Rect panel   = self.panel_rect();
	float list_y = panel.y + 62.0f * s;
	float list_h = panel.y + panel.height - list_y - 10.0f * s;
	int visible  = (int)(list_h / (22.0f * s));
	if (visible < 1) visible = 1;
	return visible;
}

fn int Symbols.row_at_mouse(&self, RLVector2 mouse)
{
	float s      = ui::scale();
	Rect panel   = self.panel_rect();
	float list_y = panel.y + 62.0f * s;
	if (mouse[1] < list_y) return -1;
	int row = (int)((mouse[1] - list_y) / (22.0f * s)) + self.scroll;
	if (row < 0 || row >= (int)self.matches.len()) return -1;
	return row;
}

fn bool rect_contains(Rect r, RLVector2 point)
{
	return point[0] >= r.x && point[0] <= r.x + r.width && point[1] >= r.y && point[1] <= r.y + r.height;
}

fn float text_width(RLFont font, String text, float size)
{
	if (text.len == 0) return 0.0f;
	float width = 0.0f;
	@pool()
	{
		width = rl::measure_text_ex(font, text.zstr_tcopy(), size, 0.0f)[0];
	};
	return width;
}

fn void draw_text(RLFont font, String text, float x, float y, float size, RLColor color)
{
	if (text.len == 0) return;
	@pool()
	{
		rl::draw_text_ex(font, text.zstr_tcopy(), { x, y }, size, 0.0f, color);
	};
}

fn SymbolTarget Symbols.update(&self, keymap::Keymap* keymap, project::Project* project, double now)
{
	SymbolTarget target = { .valid = false, .path = "", .line = 0, .column = 0 };
	if (!self.open) return target;
	self.consumed = false;

	if (keymap.pressed((int)commands::CommandId.OVERLAY_CLOSE, commands::CTX_SYMBOLS))
	{
		self.consumed = true;
		self.close();
		return target;
	}
	if (keymap.pressed_repeat((int)commands::CommandId.LIST_ACCEPT, commands::CTX_SYMBOLS))
	{
		self.consumed = true;
		return self.activate();
	}

	int visible = self.visible_rows();
	if (keymap.pressed_repeat((int)commands::CommandId.LIST_DOWN, commands::CTX_SYMBOLS))
	{
		self.consumed = true;
		self.move_selection(1);
	}
	if (keymap.pressed_repeat((int)commands::CommandId.LIST_UP, commands::CTX_SYMBOLS))
	{
		self.consumed = true;
		self.move_selection(-1);
	}
	if (keymap.pressed((int)commands::CommandId.LIST_PAGE_DOWN, commands::CTX_SYMBOLS))
	{
		self.consumed = true;
		self.move_selection(visible);
	}
	if (keymap.pressed((int)commands::CommandId.LIST_PAGE_UP, commands::CTX_SYMBOLS))
	{
		self.consumed = true;
		self.move_selection(-visible);
	}
	self.ensure_visible(visible);

	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		if (self.query_len > 0)
		{
			self.query_len--;
			self.query[self.query_len] = 0;
			self.dirty = true;
		}
	}

	int codepoint = rl::get_char_pressed();
	while (codepoint != 0)
	{
		if (codepoint >= 32 && codepoint <= 126 && self.query_len < QUERY_MAX)
		{
			self.query[self.query_len] = (char)codepoint;
			self.query_len++;
			self.query[self.query_len] = 0;
			self.dirty = true;
		}
		codepoint = rl::get_char_pressed();
	}

	if (self.dirty) self.refilter();

	RLVector2 mouse = rl::get_mouse_position();
	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		int row = self.row_at_mouse(mouse);
		if (row >= 0)
		{
			self.selected = row;
			return self.activate();
		}
	}
	return target;
}

fn void Symbols.draw(&self, RLFont font)
{
	if (!self.open) return;

	float s    = ui::scale();
	Rect panel = self.panel_rect();
	rl::draw_rectangle_rec(panel, theme::current().panel_bg);
	rl::draw_rectangle_lines_ex(panel, 1.0f, theme::current().panel_border);

	float pad     = 10.0f * s;
	float field_h = 30.0f * s;
	Rect field    = { .x = panel.x + pad, .y = panel.y + pad, .width = panel.width - pad * 2.0f, .height = field_h };
	rl::draw_rectangle_rec(field, theme::current().panel_field);
	rl::draw_rectangle_lines_ex(field, 1.0f, theme::current().panel_border);

	String query  = self.query_view();
	float query_w = text_width(font, query, 15.0f * s);
	draw_text(font, query, field.x + 6.0f * s, field.y + 7.0f * s, 15.0f * s, theme::current().panel_text);
	if (query.len == 0)
	{
		draw_text(font, "Go to symbol...", field.x + 6.0f * s, field.y + 7.0f * s, 15.0f * s, theme::current()
			.panel_dim);
	}
	else
	{
		rl::draw_rectangle(
			(int)(field.x + 6.0f * s + query_w + 1.0f),
			(int)(field.y + 6.0f * s),
			2,
			(int)(16.0f * s),
			theme::current()
			.panel_caret);
	}

	@pool()
	{
		String status = string::format(tmem, "%d symbols", (long)self.matches.len());
		draw_text(font, status, panel.x + pad, field.y + field_h + 6.0f * s, 13.0f * s, theme::current().panel_dim);
	};

	float list_y = panel.y + 62.0f * s;
	float list_h = panel.y + panel.height - list_y - 10.0f * s;
	float row_h  = 22.0f * s;
	rl::begin_scissor_mode((int)panel.x + 2, (int)list_y, (int)panel.width - 4, (int)list_h);
	int shown = self.scroll + MAX_VISIBLE_ROWS;
	if (shown > (int)self.matches.len()) shown = (int)self.matches.len();
	for (int i = self.scroll; i < shown; i++)
	{
		SymbolRef ref     = self.matches[(sz)i];
		CardSymbols* file = &self.files[(sz)ref.file];
		Symbol* symbol    = &file.symbols[(sz)ref.index];
		float y           = list_y + (float)(i - self.scroll) * row_h;

		if (i == self.selected)
		{
			rl::draw_rectangle((int)panel.x + 2, (int)y, (int)panel.width - 4, (int)row_h, theme::current()
				.panel_selected);
		}

		float x = panel.x + pad;
		draw_text(font, symbol.name, x, y + 3.0f * s, 15.0f * s, theme::current().panel_text);

		if (query.len > 0)
		{
			usz[QUERY_MAX] positions;
			int score = commands::fuzzy_match(symbol.name, query, positions[0:QUERY_MAX]);
			if (score >= 0)
			{
				for (usz p = 0; p < query.len; p++)
				{
					usz pos = positions[p];
					if (pos >= symbol.name.len) break;
					float mx = x + text_width(font, symbol.name[0:pos], 15.0f * s);
					draw_text(font, symbol.name[pos:1], mx, y + 3.0f * s, 15.0f * s, theme::current().panel_match);
				}
			}
		}

		@pool()
		{
			String right  = string::format(tmem, "%s  %s", kind_label(symbol.kind), self.relative(file.path));
			float right_w = text_width(font, right, 13.0f * s);
			draw_text(font, right, panel.x + panel.width - pad - right_w, y + 4.0f * s, 13.0f * s, theme::current()
				.panel_dim);
		};
	}
	rl::end_scissor_mode();
}