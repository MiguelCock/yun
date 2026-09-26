module yun::search;

import raylib6::rl;
import std::atomic::types;
import std::collections::list;
import std::collections::map;
import std::core::mem::alloc;
import std::io::file;
import std::io::path;
import std::math::geometry;
import std::os;
import std::thread;
import std::thread::channel;
import yun::card;
import yun::commands;
import yun::editor;
import yun::find;
import yun::keymap;
import yun::project;
import yun::theme;
import yun::ui;

const int MAX_MATCHES_PER_FILE = 200;
const int MAX_RESULTS          = 2000;
const long MAX_FILE_BYTES      = 2 * 1024 * 1024;
const int BINARY_SCAN_BYTES    = 8192;
const int PREVIEW_MAX          = 120;
const int MAX_SEARCH_WORKERS   = 4;
const int QUERY_MAX            = 256;
const double RESTART_DEBOUNCE  = 0.15;
const float TOP_MARGIN         = 24.0f;

struct SearchMatch
{
	usz line;
	usz column;
	String preview;
}

struct SearchGroup
{
	String path;
	List{SearchMatch} matches;
}

struct SearchBatch
{
	String path;
	List{SearchMatch} matches;
	uint generation;
}

struct SearchWork
{
	Search* search;
	String path;
	String query;
	bool case_sensitive;
	bool whole_word;
	uint generation;
}

struct SearchTarget
{
	bool valid;
	String path;
	usz line;
	usz column;
}

struct Search
{
	Allocator allocator;
	bool open;
	char[QUERY_MAX] query;
	usz query_len;
	bool case_sensitive;
	bool whole_word;
	List{SearchGroup} groups;
	HashMap{String, int} group_index;
	bool scanning;
	usz submitted;
	usz received;
	uint generation;
	ThreadPool pool;
	bool pool_ready;
	UnboundedChannel{SearchBatch}* results;
	Atomic{bool} cancel;
	int selected;
	int scroll;
	usz total_matches;
	bool restart_pending;
	double restart_at;
	String root;
	bool consumed;
}

fn bool search_match_at(String line, usz at, String query, bool case_sensitive, bool whole_word)
{
	if (at + query.len > line.len) return false;
	for (usz i = 0; i < query.len; i++)
	{
		char a = line[at + i];
		char b = query[i];
		if (!case_sensitive)
		{
			a = find::fold_ascii(a);
			b = find::fold_ascii(b);
		}
		if (a != b) return false;
	}
	if (whole_word)
	{
		if (at > 0 && find::is_word_char(line[at - 1])) return false;
		usz end = at + query.len;
		if (end < line.len && find::is_word_char(line[end])) return false;
	}
	return true;
}

fn usz find_in_line(String line, String query, bool case_sensitive, bool whole_word, usz[] out, usz cap)
{
	usz count = 0;
	if (query.len == 0) return 0;
	usz pos = 0;
	while (pos + query.len <= line.len && count < cap)
	{
		if (search_match_at(line, pos, query, case_sensitive, whole_word))
		{
			out[count] = pos;
			count++;
			pos += query.len;
		}
		else
		{
			pos++;
		}
	}
	return count;
}

fn String preview_of(Allocator allocator, String line)
{
	usz start = 0;
	while (start < line.len && (line[start] == ' ' || line[start] == '\t')) start++;
	usz end = line.len;
	if (end - start > (usz)PREVIEW_MAX) end = start + (usz)PREVIEW_MAX;
	return line[start:end - start].copy(allocator);
}

fn void scan_content(
	Allocator allocator,
	String content,
	String query,
	bool case_sensitive,
	bool whole_word,
	List{SearchMatch}* out
)
{
	usz[MAX_MATCHES_PER_FILE] columns;
	usz line  = 0;
	usz start = 0;
	usz found = 0;
	while (start <= content.len && found < (usz)MAX_MATCHES_PER_FILE)
	{
		usz end = start;
		while (end < content.len && content[end] != '\n') end++;
		String text = content[start:end - start];
		if (text.len > 0 && text[text.len - 1] == '\r') text = text[0:text.len - 1];

		usz cap = (usz)MAX_MATCHES_PER_FILE - found;
		usz n   = find_in_line(text, query, case_sensitive, whole_word, columns[0:MAX_MATCHES_PER_FILE], cap);
		for (usz i = 0; i < n; i++)
		{
			out.push({ .line = line, .column = columns[i], .preview = preview_of(allocator, text) });
			found++;
		}

		if (end >= content.len) break;
		line++;
		start = end + 1;
	}
}

fn bool looks_binary(String content)
{
	usz n = content.len < (usz)BINARY_SCAN_BYTES ? content.len : (usz)BINARY_SCAN_BYTES;
	for (usz i = 0; i < n; i++)
	{
		if (content[i] == 0) return true;
	}
	return false;
}

fn void scan_file_path(
	Allocator allocator,
	String path,
	String query,
	bool case_sensitive,
	bool whole_word,
	List{SearchMatch}* out
)
{
	@pool()
	{
		long? size = path::file_size((Path)path);
		if (catch excuse = size) return;
		if (size > MAX_FILE_BYTES) return;

		char[]? data = file::load(tmem, path);
		if (catch excuse = data) return;
		String content = (String)data;
		if (looks_binary(content)) return;
		scan_content(allocator, content, query, case_sensitive, whole_word, out);
	};
}

fn void free_batch(Allocator allocator, SearchBatch* batch)
{
	for (sz i = 0; i < batch.matches.len(); i++) batch.matches[i].preview.free(allocator);
	batch.matches.free();
	batch.path.free(allocator);
}

fn void search_worker(void* arg)
{
	SearchWork* work    = (SearchWork*)arg;
	Search* search      = work.search;
	String path         = work.path;
	String query        = work.query;
	bool case_sensitive = work.case_sensitive;
	bool whole_word     = work.whole_word;
	uint generation     = work.generation;

	List{SearchMatch} matches;
	matches.init(search.allocator);

	if (!search.cancel.load())
	{
		scan_file_path(search.allocator, path, query, case_sensitive, whole_word, &matches);
	}

	SearchBatch batch = { .path = path, .matches = matches, .generation = generation };
	if (search.results) (void)search.results.push(batch);
	query.free(search.allocator);
	alloc::free(search.allocator, work);
}

fn void Search.init_pool(&self)
{
	int workers = os::num_cpu();
	if (workers < 2) workers = 2;
	if (workers > MAX_SEARCH_WORKERS) workers = MAX_SEARCH_WORKERS;
	if (catch excuse = self.pool.init(self.allocator, workers))
	{
		self.pool_ready = false;
		return;
	}
	UnboundedChannel{SearchBatch}*? created = channel::create_unbounded{SearchBatch}(self.allocator);
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

fn void Search.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.open = false;
	self.query_len = 0;
	self.query[0] = 0;
	self.case_sensitive = false;
	self.whole_word = false;
	self.groups.init(allocator);
	self.group_index.init(allocator);
	self.scanning = false;
	self.submitted = 0;
	self.received = 0;
	self.generation = 0;
	self.selected = 0;
	self.scroll = 0;
	self.total_matches = 0;
	self.restart_pending = false;
	self.restart_at = 0.0;
	self.root = "";
	self.consumed = false;
	self.cancel.store(false);
	self.results = null;
	self.pool_ready = false;
	self.init_pool();
}

fn void Search.clear_results(&self)
{
	for (sz i = 0; i < self.groups.len(); i++)
	{
		for (sz m = 0; m < self.groups[i].matches.len(); m++)
		{
			self.groups[i].matches[m].preview.free(self.allocator);
		}
		self.groups[i].matches.free();
		self.groups[i].path.free(self.allocator);
	}
	self.groups.clear();
	self.group_index.clear();
	self.total_matches = 0;
	self.selected = 0;
	self.scroll = 0;
}

fn void Search.destroy(&self)
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
	self.clear_results();
	self.groups.free();
	self.group_index.free();
	if (self.root.len) self.root.free(self.allocator);
}

fn String Search.query_view(&self)
{
	return (String)self.query[0:self.query_len];
}

fn void Search.set_root(&self, String root)
{
	if (self.root.len) self.root.free(self.allocator);
	self.root = root.copy(self.allocator);
}

fn String Search.relative(&self, String path)
{
	if (self.root.len > 0 && path.len > self.root.len && path[0:self.root.len].compare_to(
		self.root
	) == 0 && path[self.root.len] == '/')
	{
		return path[self.root.len + 1:path.len - self.root.len - 1];
	}
	return path;
}

fn void Search.show(&self)
{
	self.open = true;
	self.query_len = 0;
	self.query[0] = 0;
	self.case_sensitive = false;
	self.whole_word = false;
	self.restart_pending = false;
	self.cancel_run();
	self.clear_results();
}

fn void Search.close(&self)
{
	self.cancel_run();
	self.open = false;
}

fn void Search.cancel_run(&self)
{
	self.cancel.store(true);
	self.generation++;
	self.scanning = false;
	self.submitted = 0;
	self.received = 0;
	self.restart_pending = false;
}

fn void Search.schedule_restart(&self, double now)
{
	self.restart_pending = true;
	self.restart_at = now + RESTART_DEBOUNCE;
}

fn void Search.start(&self, project::Project* project)
{
	self.clear_results();
	self.set_root((String)project.root);
	self.generation++;
	self.cancel.store(false);
	self.scanning = true;
	self.submitted = 0;
	self.received = 0;

	String query = self.query_view();
	if (query.len == 0 || !self.pool_ready)
	{
		self.scanning = false;
		return;
	}

	@pool()
	{
		HashMap{String, int} seen;
		seen.init(tmem);
		for (sz i = 0; i < project.cards.len(); i++)
		{
			String path = (String)project.cards[i].path;
			if (seen.has_key(path)) continue;
			seen.set(path, 0);

			SearchWork* work = alloc::new(self.allocator, SearchWork);
			work.search = self;
			work.path = path.copy(self.allocator);
			work.query = query.copy(self.allocator);
			work.case_sensitive = self.case_sensitive;
			work.whole_word = self.whole_word;
			work.generation = self.generation;
			if (catch excuse = self.pool.add_task(&search_worker, work))
			{
				work.path.free(self.allocator);
				work.query.free(self.allocator);
				alloc::free(self.allocator, work);
				continue;
			}
			self.submitted++;
		}
	};
	if (self.submitted == 0) self.scanning = false;
}

fn void Search.merge_batch(&self, SearchBatch* batch)
{
	if (batch.matches.len() > 0 && self.total_matches < (usz)MAX_RESULTS)
	{
		int group      = -1;
		int*? existing =  self.group_index.get_ref(batch.path);
		if (catch excuse = existing)
		{
			SearchGroup created;
			created.path = batch.path.copy(self.allocator);
			created.matches.init(self.allocator);
			self.groups.push(created);
			group = (int)(self.groups.len() - 1);
			self.group_index.set(self.groups[group].path, group);
		}
		else
		{
			group = *existing;
		}
		for (sz i = 0; i < batch.matches.len(); i++)
		{
			self.groups[group].matches.push(batch.matches[i]);
			self.total_matches++;
		}
		batch.matches.free();
		batch.path.free(self.allocator);
		return;
	}
	free_batch(self.allocator, batch);
}

fn void Search.pump(&self, project::Project* project, double now)
{
	if (self.restart_pending && now >= self.restart_at)
	{
		self.restart_pending = false;
		if (self.open && self.query_len > 0) self.start(project);
	}
	if (self.results)
	{
		while (true)
		{
			SearchBatch? maybe = self.results.try_pop();
			if (catch excuse = maybe) break;
			SearchBatch batch = maybe;
			if (batch.generation == self.generation)
			{
				self.received++;
				self.merge_batch(&batch);
			}
			else
			{
				free_batch(self.allocator, &batch);
			}
		}
	}
	if (self.scanning && self.received >= self.submitted) self.scanning = false;
}

fn int Search.match_count(&self)
{
	return (int)self.total_matches;
}

fn bool Search.match_at_index(&self, int index, String* path, usz* line, usz* column)
{
	if (index < 0) return false;
	int k = 0;
	for (sz g = 0; g < self.groups.len(); g++)
	{
		for (sz m = 0; m < self.groups[g].matches.len(); m++)
		{
			if (k == index)
			{
				*path = self.groups[g].path;
				*line = self.groups[g].matches[m].line;
				*column = self.groups[g].matches[m].column;
				return true;
			}
			k++;
		}
	}
	return false;
}

fn void Search.move_selection(&self, int delta)
{
	int count = self.match_count();
	if (count == 0) return;
	int next = self.selected + delta;
	if (next < 0) next = 0;
	if (next >= count) next = count - 1;
	self.selected = next;
}

fn int Search.selected_ordinal(&self)
{
	int ordinal = 0;
	int k       = 0;
	for (sz g = 0; g < self.groups.len(); g++)
	{
		ordinal++;
		for (sz m = 0; m < self.groups[g].matches.len(); m++)
		{
			if (k == self.selected) return ordinal;
			ordinal++;
			k++;
		}
	}
	return 0;
}

fn float Search.list_y(&self)
{
	float s    = ui::scale();
	Rect panel = self.panel_rect();
	float pad  = 10.0f * s;
	Rect case_rect;
	Rect word_rect;
	self.chip_rects(&case_rect, &word_rect);
	float status_y = case_rect.y + case_rect.height + 6.0f * s;
	return status_y + 20.0f * s;
}

fn int Search.visible_rows(&self)
{
	float s      = ui::scale();
	Rect panel   = self.panel_rect();
	float pad    = 10.0f * s;
	float list_y = self.list_y();
	float list_h = panel.y + panel.height - list_y - pad;
	float row_h  = 20.0f * s;
	int visible  = (int)(list_h / row_h);
	if (visible < 1) visible = 1;
	return visible;
}

fn void Search.ensure_visible(&self)
{
	int ordinal = self.selected_ordinal();
	int visible = self.visible_rows();
	if (ordinal < self.scroll) self.scroll = ordinal;
	if (ordinal >= self.scroll + visible) self.scroll = ordinal - visible + 1;
	if (self.scroll < 0) self.scroll = 0;
}

fn int Search.row_at_mouse(&self, RLVector2 mouse)
{
	float s      = ui::scale();
	Rect panel   = self.panel_rect();
	float list_y = self.list_y();
	if (mouse[1] < list_y) return -1;
	float row_h    = 20.0f * s;
	float header_h = 22.0f * s;
	float y        = list_y;
	int flat       = 0;
	for (sz g = 0; g < self.groups.len(); g++)
	{
		y += header_h;
		for (sz m = 0; m < self.groups[g].matches.len(); m++)
		{
			if (mouse[1] >= y && mouse[1] < y + row_h) return flat;
			y += row_h;
			flat++;
		}
	}
	return -1;
}

fn SearchTarget Search.activate(&self)
{
	SearchTarget target = { .valid = false, .path = "", .line = 0, .column = 0 };
	String path;
	usz line;
	usz column;
	if (self.match_at_index(self.selected, &path, &line, &column))
	{
		target.valid = true;
		target.path = path;
		target.line = line;
		target.column = column;
	}
	return target;
}

fn Rect Search.panel_rect(&self)
{
	float s      = ui::scale();
	int screen_w = rl::get_screen_width();
	int screen_h = rl::get_screen_height();
	float width  = 780.0f * s;
	if (width > (float)screen_w - 24.0f) width = (float)screen_w - 24.0f;
	float height = 460.0f * s;
	if (height > (float)screen_h - TOP_MARGIN - 24.0f) height = (float)screen_h - TOP_MARGIN - 24.0f;
	if (height < 120.0f) height = 120.0f;
	return { .x = ((float)screen_w - width) / 2.0f, .y = TOP_MARGIN, .width = width, .height = height };
}

fn void Search.chip_rects(&self, Rect* case_rect, Rect* word_rect)
{
	float s    = ui::scale();
	Rect panel = self.panel_rect();
	float pad  = 10.0f * s;
	float y    = panel.y + pad + 30.0f * s + 8.0f * s;
	float h    = 22.0f * s;
	float w    = 58.0f * s;
	*case_rect = { .x = panel.x + pad, .y = y, .width = w, .height = h };
	*word_rect = { .x = panel.x + pad + w + 6.0f * s, .y = y, .width = w, .height = h };
}

fn SearchTarget Search.update(&self, keymap::Keymap* keymap, project::Project* project, double now)
{
	SearchTarget target = { .valid = false, .path = "", .line = 0, .column = 0 };
	if (!self.open) return target;
	self.consumed = false;

	if (keymap.pressed((int)commands::CommandId.OVERLAY_CLOSE, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.close();
		return target;
	}
	if (keymap.pressed_repeat((int)commands::CommandId.LIST_ACCEPT, commands::CTX_SEARCH))
	{
		self.consumed = true;
		return self.activate();
	}

	int visible = self.visible_rows();
	if (keymap.pressed_repeat((int)commands::CommandId.LIST_DOWN, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.move_selection(1);
	}
	if (keymap.pressed_repeat((int)commands::CommandId.LIST_UP, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.move_selection(-1);
	}
	if (keymap.pressed((int)commands::CommandId.LIST_PAGE_DOWN, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.move_selection(visible);
	}
	if (keymap.pressed((int)commands::CommandId.LIST_PAGE_UP, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.move_selection(-visible);
	}
	self.ensure_visible();

	if (keymap.pressed((int)commands::CommandId.SEARCH_TOGGLE_CASE, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.case_sensitive = !self.case_sensitive;
		self.schedule_restart(now);
	}
	if (keymap.pressed((int)commands::CommandId.SEARCH_TOGGLE_WORD, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.whole_word = !self.whole_word;
		self.schedule_restart(now);
	}

	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		if (self.query_len > 0)
		{
			self.query_len--;
			self.query[self.query_len] = 0;
			self.schedule_restart(now);
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
			self.schedule_restart(now);
		}
		codepoint = rl::get_char_pressed();
	}

	// Mouse: chips.
	RLVector2 mouse = rl::get_mouse_position();
	Rect case_rect;
	Rect word_rect;
	self.chip_rects(&case_rect, &word_rect);
	bool case_over = rect_contains(case_rect, mouse);
	bool word_over = rect_contains(word_rect, mouse);
	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		if (case_over)
		{
			self.case_sensitive = !self.case_sensitive;
			self.schedule_restart(now);
		}
		else if (word_over)
		{
			self.whole_word = !self.whole_word;
			self.schedule_restart(now);
		}
		else
		{
			int row = self.row_at_mouse(mouse);
			if (row >= 0)
			{
				self.selected = row;
				return self.activate();
			}
		}
	}
	return target;
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

fn void Search.draw(&self, RLFont font)
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
		draw_text(font, "Search in project...", field.x + 6.0f * s, field.y + 7.0f * s, 15.0f * s, theme::current()
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

	Rect case_rect;
	Rect word_rect;
	self.chip_rects(&case_rect, &word_rect);
	draw_chip(font, case_rect, "Case", self.case_sensitive, s);
	draw_chip(font, word_rect, "Word", self.whole_word, s);

	float status_y = case_rect.y + case_rect.height + 6.0f * s;
	@pool()
	{
		String status;
		if (query.len == 0)
		{
			status = "Type to search";
		}
		else if (self.scanning)
		{
			status = string::format(
				tmem,
				"Searching... %d files, %d matches",
				(long)self.groups.len(),
				(long)self.total_matches
			);
		}
		else
		{
			status = string::format(tmem, "%d matches in %d files", (long)self.total_matches, (long)self.groups.len());
		}
		draw_text(font, status, panel.x + pad, status_y, 14.0f * s, theme::current().panel_dim);
	};

	float list_y = self.list_y();
	float list_h = panel.y + panel.height - list_y - pad;
	if (list_h < 0.0f) list_h = 0.0f;
	float row_h    = 20.0f * s;
	float header_h = 22.0f * s;

	int ordinal = 0;
	int flat    = 0;
	float y     = list_y;
	bool done   = false;
	rl::begin_scissor_mode((int)panel.x + 2, (int)list_y, (int)panel.width - 4, (int)list_h);
	for (sz g = 0; g < self.groups.len() && !done; g++)
	{
		if (ordinal >= self.scroll)
		{
			draw_text(font, self.relative(self.groups[g].path), panel.x + pad, y + 3.0f * s, 14.0f * s, theme::current()
				.panel_header);
			y += header_h;
			if (y > panel.y + panel.height) break;
		}
		ordinal++;
		for (sz m = 0; m < self.groups[g].matches.len(); m++)
		{
			SearchMatch* match = &self.groups[g].matches[m];
			if (ordinal >= self.scroll)
			{
				if (flat == self.selected)
				{
					rl::draw_rectangle((int)panel.x + 2, (int)y, (int)panel.width - 4, (int)row_h, theme::current()
						.panel_selected);
				}
				@pool()
				{
					String label = string::format(
						tmem,
						"%d:%d  %s",
						(long)(match.line + 1),
						(long)(match.column + 1),
						match.preview
					);
					draw_text(font, label, panel.x + pad + 12.0f * s, y + 2.0f * s, 14.0f * s, theme::current()
						.panel_text);
				};
				y += row_h;
				if (y > panel.y + panel.height)
				{
					done = true;
					break;
				}
			}
			ordinal++;
			flat++;
		}
	}
	rl::end_scissor_mode();
}

fn void draw_chip(RLFont font, Rect r, String label, bool on, float s)
{
	rl::draw_rectangle_rec(r, on ? theme::current().panel_selected : theme::current().findbar_chip);
	rl::draw_rectangle_lines_ex(r, 1.0f, theme::current().panel_border);
	@pool()
	{
		float w = text_width(font, label, 14.0f * s);
		draw_text(font, label, r.x + (r.width - w) / 2.0f, r.y + 4.0f * s, 14.0f * s, theme::current().panel_text);
	};
}