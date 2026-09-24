module yun::imports;

import raylib6::rl;
import std::collections::list;
import std::collections::map;
import std::core::dstring;
import std::core::mem::alloc;
import std::io::file;
import std::io::path;
import std::math;
import std::os;
import std::thread;
import std::thread::channel;
import tree_sitter;
import yun::card;
import yun::highlight;
import yun::hover;
import yun::project;
import yun::text;
import yun::theme;

const int MAX_SCAN_WORKERS         = 8;
const float ARROW_HIT_PX           = 6.0f;
const int BEZIER_HIT_STEPS         = 20;
const double EDIT_DEBOUNCE_SECONDS = 0.15;

struct ImportRef
{
	String specifier;
	String target_path;
	bool resolved;
	bool angled;
	usz line;
	usz column;
}

struct ImportHit
{
	bool valid;
	int source;
	usz ref_index;
	int target;
	RLVector2 world;
}

struct CardImports
{
	String path;
	String module_name;
	bool is_test;
	List{ImportRef} imports;
}

struct ScanWork
{
	ImportIndex* index;
	String path;
	highlight::Language language;
	uint generation;
}

struct ScanResult
{
	String path;
	String module_name;
	bool is_test;
	List{ImportRef} imports;
	uint generation;
}

struct ImportIndex
{
	Allocator allocator;
	List{CardImports} files;
	HashMap{String, int} file_index;
	HashMap{String, int} card_paths;
	ThreadPool pool;
	bool pool_ready;
	UnboundedChannel{ScanResult}* results;
	uint generation;
	usz pending;
	usz received;
	bool scanning;
	usz scan_cursor;
	usz known_cards;
	ImportHit hover;
	bool pending_edit;
	String pending_path;
	double pending_since;
}

TSQuery*[5] import_query_cache;
bool[5] import_query_loaded;
TSParser*[5] import_parser_cache;
TSQuery*[5] module_query_cache;
bool[5] module_query_loaded;

const ImportRef[] NO_IMPORTS = { };

fn void ImportIndex.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.files.init(allocator);
	self.file_index.init(allocator);
	self.card_paths.init(allocator);
	self.scanning = false;
	self.scan_cursor = 0;
	self.known_cards = 0;
	self.generation = 0;
	self.pending = 0;
	self.received = 0;
	self.pool_ready = false;
	self.results = null;
	self.hover.valid = false;
	self.pending_edit = false;
	self.pending_path = "";
	self.pending_since = 0.0;
	self.init_pool();
}

fn void ImportIndex.init_pool(&self)
{
	int workers = os::num_cpu();
	if (workers < 2) workers = 2;
	if (workers > MAX_SCAN_WORKERS) workers = MAX_SCAN_WORKERS;
	if (catch excuse = self.pool.init(self.allocator, workers))
	{
		self.pool_ready = false;
		return;
	}
	UnboundedChannel{ScanResult}*? created = channel::create_unbounded{ScanResult}(self.allocator);
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

fn void ImportIndex.destroy(&self)
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
	self.free_files();
	self.files.free();
	self.file_index.free();
	self.card_paths.free();
	self.clear_pending_edit();
}

fn String import_query_text(highlight::Language language)
{
	switch (language)
	{
		case highlight::Language.C:
			return "(preproc_include path: (_) @path)";
		case highlight::Language.C3:
			return "(import_declaration (import_path (path_ident) @path))";
		case highlight::Language.PYTHON:
			return "(import_statement name: (dotted_name) @path)\n"
				"(import_statement name: (aliased_import (dotted_name) @path))\n"
				"(import_from_statement module_name: (dotted_name) @path)\n"
				"(import_from_statement module_name: (relative_import) @path)";
		case highlight::Language.JAVASCRIPT:
			return "(import_statement source: (string) @path)\n"
				"(call_expression function: (identifier) @fn arguments: (arguments (string) @path))";
		case highlight::Language.NONE:
			return "";
	}
}

fn String module_query_text(highlight::Language language)
{
	if (language == highlight::Language.C3) return "(module_declaration) @module";
	return "";
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

fn TSParser* import_parser_for(highlight::Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= 5) return null;
	if (import_parser_cache[index]) return import_parser_cache[index];

	TSParser* parser = tree_sitter::ts_parser_new();
	if (!parser) return null;
	if (!tree_sitter::ts_parser_set_language(parser, highlight::grammar_language(language)))
	{
		tree_sitter::ts_parser_delete(parser);
		return null;
	}
	import_parser_cache[index] = parser;
	return parser;
}

fn TSQuery* import_query_for(highlight::Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= 5) return null;
	if (import_query_loaded[index]) return import_query_cache[index];
	import_query_loaded[index] = true;
	import_query_cache[index] = make_query(language, import_query_text(language));
	return import_query_cache[index];
}

fn TSQuery* module_query_for(highlight::Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= 5) return null;
	if (module_query_loaded[index]) return module_query_cache[index];
	module_query_loaded[index] = true;
	module_query_cache[index] = make_query(language, module_query_text(language));
	return module_query_cache[index];
}

fn String cstr_to_string(char* z)
{
	usz len = 0;
	while (z[len] != 0) len++;
	return (String)z[0:len];
}

fn String strip_quotes(String s)
{
	if (s.len >= 2)
	{
		char first = s[0];
		char last  = s[s.len - 1];
		if ((first == '"' && last == '"') || (first == '\'' && last == '\'') || (first == '`' && last == '`'))
		{
			return s[1:s.len - 2];
		}
	}
	return s;
}

fn bool is_angled(String s)
{
	return s.len >= 2 && s[0] == '<' && s[s.len - 1] == '>';
}

fn bool contains(String haystack, String needle)
{
	if (needle.len == 0 || haystack.len < needle.len) return false;
	for (usz i = 0; i + needle.len <= haystack.len; i++)
	{
		if (haystack[i:needle.len].compare_to(needle) == 0) return true;
	}
	return false;
}

fn void extract_imports(
	Allocator allocator,
	TSParser* parser,
	TSQuery* import_query,
	TSQuery* module_query,
	String text,
	List{ImportRef}* out,
	String* out_module,
	bool* out_is_test
)
{
	*out_module = "";
	*out_is_test = false;
	if (!parser || !import_query) return;

	TSTree* tree = tree_sitter::ts_parser_parse_string(parser, null, (char*)text.ptr, (uint)text.len);
	if (!tree) return;
	TSNode root = tree_sitter::ts_tree_root_node(tree);

	if (module_query)
	{
		TSQueryCursor* module_cursor = tree_sitter::ts_query_cursor_new();
		if (module_cursor)
		{
			tree_sitter::ts_query_cursor_exec(module_cursor, module_query, root);
			TSQueryMatch module_match;
			uint module_capture = 0;
			if (tree_sitter::ts_query_cursor_next_capture(
				module_cursor,
				&module_match,
				&module_capture
			) && module_match.capture_count > 0)
			{
				TSNode decl = module_match.captures[0].node;
				uint dstart = tree_sitter::ts_node_start_byte(decl);
				uint dend   = tree_sitter::ts_node_end_byte(decl);
				if (dend > dstart && dend <= text.len)
				{
					*out_is_test = contains(text[dstart:dend - dstart], "@test");
				}
				TSNode path_node = tree_sitter::ts_node_child_by_field_name(decl, "path", 4);
				if (!tree_sitter::ts_node_is_null(path_node))
				{
					uint pstart = tree_sitter::ts_node_start_byte(path_node);
					uint pend   = tree_sitter::ts_node_end_byte(path_node);
					if (pend > pstart && pend <= text.len)
					{
						*out_module = text[pstart:pend - pstart].copy(allocator);
					}
				}
			}
			tree_sitter::ts_query_cursor_delete(module_cursor);
		}
	}

	TSQueryCursor* cursor = tree_sitter::ts_query_cursor_new();
	if (cursor)
	{
		tree_sitter::ts_query_cursor_exec(cursor, import_query, root);
		TSQueryMatch match;
		uint capture_index = 0;
		uint last_match_id = 0xFFFFFFFF;
		bool first_match   = true;
		while (tree_sitter::ts_query_cursor_next_capture(cursor, &match, &capture_index))
		{
			if (!first_match && match.id == last_match_id) continue;
			last_match_id = match.id;
			first_match = false;

			String fn_name   = "";
			String path_text = "";
			bool has_path    = false;
			bool angled      = false;
			usz line         = 0;
			usz column       = 0;

			for (uint c = 0; c < match.capture_count; c++)
			{
				TSQueryCapture capture = match.captures[c];
				uint name_len = 0;
				char* name = tree_sitter::ts_query_capture_name_for_id(import_query, capture.index, &name_len);
				if (!name || name_len == 0) continue;
				String capture_name = (String)name[0:name_len];

				uint start = tree_sitter::ts_node_start_byte(capture.node);
				uint end   = tree_sitter::ts_node_end_byte(capture.node);
				if (end <= start || end > text.len) continue;
				String raw = text[start:end - start];

				if (capture_name.compare_to("fn") == 0)
				{
					fn_name = raw;
				}
				else if (capture_name.compare_to("path") == 0)
				{
					has_path = true;
					path_text = raw;
					TSPoint point = tree_sitter::ts_node_start_point(capture.node);
					line = point.row;
					column = point.column;
					char* node_type = tree_sitter::ts_node_type(capture.node);
					if (node_type && cstr_to_string(node_type).compare_to("system_lib_string") == 0)
					{
						angled = true;
					}
				}
			}
			if (!has_path) continue;
			if (fn_name.len > 0 && fn_name.compare_to("require") != 0) continue;

			String specifier = strip_quotes(path_text).copy(allocator);
			out.push(
				{
					.specifier = specifier,
					.target_path = "",
					.resolved = false,
					.angled = angled,
					.line = line,
					.column = column,
				}
			);
		}
		tree_sitter::ts_query_cursor_delete(cursor);
	}
	tree_sitter::ts_tree_delete(tree);
}

fn String dir_of(Allocator allocator, String path)
{
	String dir = rl::get_prev_directory_path((ZString)path.ptr).str_view();
	return dir.copy(allocator);
}

fn String module_rel(Allocator allocator, String spec)
{
	DString out;
	out.init(allocator, spec.len);
	usz i = 0;
	while (i < spec.len)
	{
		if (spec[i] == ':' && i + 1 < spec.len && spec[i + 1] == ':')
		{
			out.append_char('/');
			i += 2;
			continue;
		}
		out.append_char(spec[i]);
		i++;
	}
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn bool any_candidate(
	HashMap{String, int}* paths,
	Allocator allocator,
	String base,
	String[] suffixes,
	String* out_path
)
{
	for (usz i = 0; i < suffixes.len; i++)
	{
		String candidate = string::format(allocator, "%s%s", base, suffixes[i]);
		if (paths.has_key(candidate))
		{
			*out_path = candidate;
			return true;
		}
	}
	return false;
}

fn bool resolve_import(
	HashMap{String, int}* paths,
	CardImports[] files,
	Allocator allocator,
	String root,
	String source_path,
	String specifier,
	bool angled,
	List{String}* out_targets
)
{
	if (angled || specifier.len == 0) return false;

	highlight::Language language = highlight::language_for_path(source_path);
	String dir                   = dir_of(allocator, source_path);

	switch (language)
	{
		case highlight::Language.C:

			{
				String candidate = string::format(allocator, "%s/%s", dir, specifier);
				if (paths.has_key(candidate))
				{
					out_targets.push(candidate);
					return true;
				}
				return false;
			}
		case highlight::Language.JAVASCRIPT:

			{
				if (specifier[0] != '.') return false;
				String base    = string::format(allocator, "%s/%s", dir, specifier);
				String[7] exts = { "", ".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx" };
				String found   = "";
				if (any_candidate(paths, allocator, base, exts[0:7], &found))
				{
					out_targets.push(found);
					return true;
				}
				String index_base    = string::format(allocator, "%s/index", base);
				String[6] index_exts = { ".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx" };
				if (any_candidate(paths, allocator, index_base, index_exts[0:6], &found))
				{
					out_targets.push(found);
					return true;
				}
				return false;
			}
		case highlight::Language.PYTHON:

			{
				String spec = specifier;
				String base = dir;
				if (spec[0] == '.')
				{
					usz dots = 0;
					while (dots < spec.len && spec[dots] == '.') dots++;
					usz back = 1;
					while (back < dots)
					{
						base = dir_of(allocator, base);
						back++;
					}
					String rest = spec[dots:spec.len - dots];
					if (rest.len == 0) return false;
					String rel       = module_rel(allocator, rest);
					String candidate = string::format(allocator, "%s/%s", base, rel);
					String[1] py     = { ".py" };
					String found     = "";
					if (any_candidate(paths, allocator, candidate, py[0:1], &found))
					{
						out_targets.push(found);
						return true;
					}
					String pkg = string::format(allocator, "%s/%s/__init__.py", base, rel);
					if (paths.has_key(pkg))
					{
						out_targets.push(pkg);
						return true;
					}
					return false;
				}
				String rel       = module_rel(allocator, spec);
				String candidate = string::format(allocator, "%s/%s", root, rel);
				String[1] py     = { ".py" };
				String found     = "";
				if (any_candidate(paths, allocator, candidate, py[0:1], &found))
				{
					out_targets.push(found);
					return true;
				}
				String pkg = string::format(allocator, "%s/%s/__init__.py", root, rel);
				if (paths.has_key(pkg))
				{
					out_targets.push(pkg);
					return true;
				}
				return false;
			}
		case highlight::Language.C3:

			{
				for (sz i = 0; i < files.len; i++)
				{
					if (files[i].is_test) continue;
					if (files[i].module_name.len == 0) continue;
					if (files[i].module_name.compare_to(specifier) != 0) continue;
					out_targets.push(((String)files[i].path).copy(allocator));
				}
				if (out_targets.len() > 0) return true;

				String rel       = module_rel(allocator, specifier);
				String candidate = string::format(allocator, "%s/%s", root, rel);
				String[2] exts   = { ".c3", ".c3i" };
				String found     = "";
				if (any_candidate(paths, allocator, candidate, exts[0:2], &found))
				{
					out_targets.push(found);
					return true;
				}
				return false;
			}
		case highlight::Language.NONE:
			return false;
	}
}

fn void free_refs(Allocator allocator, List{ImportRef}* refs)
{
	for (sz i = 0; i < refs.len(); i++)
	{
		ImportRef* ref = refs.get_ref(i);
		if (ref.specifier.len) ref.specifier.free(allocator);
		if (ref.target_path.len) ref.target_path.free(allocator);
	}
}

fn void ImportIndex.free_files(&self)
{
	for (sz i = 0; i < self.files.len(); i++)
	{
		free_refs(self.allocator, &self.files[i].imports);
		self.files[i].imports.free();
		self.files[i].path.free(self.allocator);
		if (self.files[i].module_name.len) self.files[i].module_name.free(self.allocator);
	}
	self.files.clear();
	self.file_index.clear();
}

fn void ImportIndex.refresh_card_paths(&self, project::Project* project)
{
	self.card_paths.clear();
	for (sz i = 0; i < project.cards.len(); i++)
	{
		self.card_paths.set((String)project.cards[i].path, (int)i);
	}
}

fn void ImportIndex.resolve_file(&self, project::Project* project, CardImports[] all_files, CardImports* file)
{
	List{ImportRef} next;
	next.init(self.allocator);
	for (sz r = 0; r < file.imports.len(); r++)
	{
		ImportRef* ref = &file.imports[r];
		List{String} targets;
		targets.init(tmem);
		bool ok = resolve_import(
			&self.card_paths,
			all_files,
			tmem,
			(String)project.root,
			(String)file.path,
			ref.specifier,
			ref.angled,
			&targets
		);
		if (!ok)
		{
			next.push(
				{
					.specifier = ref.specifier.copy(self.allocator),
					.target_path = "",
					.resolved = false,
					.angled = ref.angled,
					.line = ref.line,
					.column = ref.column,
				}
			);
		}
		else
		{
			for (usz t = 0; t < (usz)targets.len(); t++)
			{
				next.push(
					{
						.specifier = ref.specifier.copy(self.allocator),
						.target_path = targets[(sz)t].copy(self.allocator),
						.resolved = true,
						.angled = ref.angled,
						.line = ref.line,
						.column = ref.column,
					}
				);
			}
		}
		targets.free();
	}
	free_refs(self.allocator, &file.imports);
	file.imports.free();
	file.imports = next;
}

fn void ImportIndex.resolve_all(&self, project::Project* project)
{
	@pool()
	{
		CardImports[] all_files = self.files.entries[0:self.files.len()];
		for (sz i = 0; i < self.files.len(); i++)
		{
			self.resolve_file(project, all_files, &self.files[i]);
		}
	};
}

fn void ImportIndex.resolve_one(&self, project::Project* project, String path)
{
	@pool()
	{
		CardImports[] all_files = self.files.entries[0:self.files.len()];
		int*? entry             = self.file_index.get_ref(path);
		if (catch excuse = entry) return;
		self.resolve_file(project, all_files, &self.files[*entry]);
	};
}

fn void ImportIndex.start_scan(&self, project::Project* project)
{
	self.free_files();
	self.clear_pending_edit();
	self.refresh_card_paths(project);
	self.known_cards = (usz)project.cards.len();
	self.generation++;
	self.pending = 0;
	self.received = 0;
	self.scanning = true;

	if (!self.pool_ready)
	{
		self.scan_cursor = 0;
		return;
	}

	for (sz i = 0; i < project.cards.len(); i++)
	{
		FileCard* card               = &project.cards[i];
		highlight::Language language = highlight::language_for_path((String)card.path);
		if (language == highlight::Language.NONE) continue;
		if (card.buffer)
		{
			self.scan_one(project, (int)i);
			continue;
		}

		ScanWork* work = alloc::new(self.allocator, ScanWork);
		work.index = self;
		work.path = ((String)card.path).copy(self.allocator);
		work.language = language;
		work.generation = self.generation;
		if (catch excuse = self.pool.add_task(&import_scan_worker, work))
		{
			work.path.free(self.allocator);
			alloc::free(self.allocator, work);
			continue;
		}
		self.pending++;
	}
}

fn void ImportIndex.sync(&self, project::Project* project)
{
	if (self.known_cards != (usz)project.cards.len()) self.start_scan(project);
}

fn void ImportIndex.store(&self, String path, List{ImportRef}* refs, String module_name, bool is_test)
{
	int*? existing = self.file_index.get_ref(path);
	if (catch excuse = existing)
	{
		CardImports file;
		file.path = path.copy(self.allocator);
		file.module_name = module_name;
		file.is_test = is_test;
		file.imports = *refs;
		self.files.push(file);
		self.file_index.set(file.path, (int)(self.files.len() - 1));
		return;
	}
	CardImports* file = &self.files[*existing];
	free_refs(self.allocator, &file.imports);
	file.imports.free();
	if (file.module_name.len) file.module_name.free(self.allocator);
	file.module_name = module_name;
	file.is_test = is_test;
	file.imports = *refs;
}

fn void ImportIndex.scan_one(&self, project::Project* project, int card_index)
{
	FileCard* card               = &project.cards[card_index];
	highlight::Language language = highlight::language_for_path((String)card.path);
	@pool()
	{
		String text = "";
		if (card.buffer)
		{
			text = card.buffer.slice(0, card.buffer.length(), tmem);
		}
		else
		{
			char[]? data = file::load(tmem, (String)card.path);
			if (catch excuse = data) return;
			text = (String)data;
		}

		List{ImportRef} refs;
		refs.init(self.allocator);
		String module_name = "";
		bool is_test       = false;
		if (language != highlight::Language.NONE)
		{
			extract_imports(
				self.allocator,
				import_parser_for(language),
				import_query_for(language),
				module_query_for(language),
				text,
				&refs,
				&module_name,
				&is_test
			);
		}
		self.store((String)card.path, &refs, module_name, is_test);
	};
}

fn bool ImportIndex.scan_step(&self, project::Project* project, usz budget)
{
	if (!self.scanning) return true;
	usz processed = 0;
	while (self.scan_cursor < (usz)project.cards.len() && processed < budget)
	{
		self.scan_one(project, (int)self.scan_cursor);
		self.scan_cursor++;
		processed++;
	}
	if (self.scan_cursor >= (usz)project.cards.len())
	{
		self.scanning = false;
		self.resolve_all(project);
		return true;
	}
	return false;
}

fn void ImportIndex.pump(&self, project::Project* project)
{
	if (!self.pool_ready)
	{
		(void)self.scan_step(project, 16);
		return;
	}
	if (self.results)
	{
		while (true)
		{
			ScanResult? maybe = self.results.try_pop();
			if (catch excuse = maybe) break;
			ScanResult result = maybe;
			if (result.generation != self.generation)
			{
				free_refs(self.allocator, &result.imports);
				result.imports.free();
				if (result.module_name.len) result.module_name.free(self.allocator);
				result.path.free(self.allocator);
				continue;
			}
			self.received++;
			if (self.card_paths.has_key(result.path))
			{
				self.store(result.path, &result.imports, result.module_name, result.is_test);
			}
			else
			{
				free_refs(self.allocator, &result.imports);
				result.imports.free();
				if (result.module_name.len) result.module_name.free(self.allocator);
			}
			result.path.free(self.allocator);
		}
	}
	if (self.scanning && self.received >= self.pending)
	{
		self.scanning = false;
		self.resolve_all(project);
	}
}

fn String ImportIndex.module_for_path(&self, Allocator allocator, String path)
{
	int*? entry = self.file_index.get_ref(path);
	if (catch excuse = entry) return "";
	return self.files[*entry].module_name.copy(allocator);
}

fn void ImportIndex.rescan(&self, project::Project* project, int card_index)
{
	if (card_index < 0 || card_index >= (int)project.cards.len()) return;
	FileCard* card = &project.cards[card_index];
	if (highlight::language_for_path((String)card.path) == highlight::Language.NONE) return;
	String path = (String)card.path;

	@pool()
	{
		String old_module = self.module_for_path(tmem, path);

		self.scan_one(project, card_index);

		String new_module = self.module_for_path(tmem, path);

		if (new_module.compare_to(old_module) != 0)
		{
			self.resolve_all(project);
		}
		else
		{
			self.resolve_one(project, path);
		}
	};
}

fn ImportRef[] ImportIndex.imports_for(&self, String path)
{
	int*? entry = self.file_index.get_ref(path);
	if (catch excuse = entry) return NO_IMPORTS;
	CardImports* file = &self.files[*entry];
	return file.imports.entries[0:file.imports.len()];
}

fn void ImportIndex.clear_pending_edit(&self)
{
	if (self.pending_path.len) self.pending_path.free(self.allocator);
	self.pending_path = "";
	self.pending_edit = false;
}

fn void ImportIndex.note_edit(&self, String path, double now)
{
	if (self.pending_path.compare_to(path) != 0)
	{
		if (self.pending_path.len) self.pending_path.free(self.allocator);
		self.pending_path = path.copy(self.allocator);
	}
	self.pending_edit = true;
	self.pending_since = now;
}

fn bool edit_debounce_elapsed(double since, double now)
{
	return now - since >= EDIT_DEBOUNCE_SECONDS;
}

fn void ImportIndex.flush_edits(&self, project::Project* project, double now)
{
	if (!self.pending_edit) return;
	if (!edit_debounce_elapsed(self.pending_since, now)) return;

	String path = self.pending_path;
	self.pending_path = "";
	self.pending_edit = false;
	int index = project.find_card(path);
	if (index >= 0) self.rescan(project, index);
	path.free(self.allocator);
}

fn void import_extract_file(
	Allocator allocator,
	String path,
	highlight::Language language,
	List{ImportRef}* out,
	String* out_module,
	bool* out_is_test
)
{
	*out_module = "";
	*out_is_test = false;
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
		TSQuery* import_query = make_query(language, import_query_text(language));
		TSQuery* module_query = make_query(language, module_query_text(language));
		extract_imports(allocator, parser, import_query, module_query, text, out, out_module, out_is_test);
		if (import_query) tree_sitter::ts_query_delete(import_query);
		if (module_query) tree_sitter::ts_query_delete(module_query);
		tree_sitter::ts_parser_delete(parser);
	};
}

fn void import_scan_worker(void* arg)
{
	ScanWork* work               = (ScanWork*)arg;
	ImportIndex* index           = work.index;
	String path                  = work.path;
	highlight::Language language = work.language;
	uint generation              = work.generation;

	List{ImportRef} refs;
	refs.init(index.allocator);
	String module_name = "";
	bool is_test       = false;
	import_extract_file(index.allocator, path, language, &refs, &module_name, &is_test);

	ScanResult result = {
		.path = path,
		.module_name = module_name,
		.is_test = is_test,
		.imports = refs,
		.generation = generation,
	};
	if (index.results) (void)index.results.push(result);
	alloc::free(index.allocator, work);
}

fn RLVector2 rect_center(Rect r)
{
	return { r.x + r.width / 2.0f, r.y + r.height / 2.0f };
}

fn RLVector2 rect_edge_point(Rect r, RLVector2 toward)
{
	RLVector2 center = rect_center(r);
	float dx         = toward[0] - center[0];
	float dy         = toward[1] - center[1];
	if (dx == 0.0f && dy == 0.0f) return center;
	float tx = dx != 0.0f ? (r.width / 2.0f) / math::abs(dx) : 1000000.0f;
	float ty = dy != 0.0f ? (r.height / 2.0f) / math::abs(dy) : 1000000.0f;
	float t  = math::min(tx, ty);
	return { center[0] + dx * t, center[1] + dy * t };
}

fn void bezier_controls(RLVector2 p1, RLVector2 p2, RLVector2* c2, RLVector2* c3)
{
	float mx = (p1[0] + p2[0]) * 0.5f;
	*c2 = { mx, p1[1] };
	*c3 = { mx, p2[1] };
}

fn void draw_arrowhead(RLVector2 p1, RLVector2 c2, RLVector2 c3, RLVector2 p2, float zoom, RLColor color)
{
	RLVector2 before = rl::get_spline_point_bezier_cubic(p1, c2, c3, p2, 0.9f);
	float dx         = p2[0] - before[0];
	float dy         = p2[1] - before[1];
	float len        = math::sqrt(dx * dx + dy * dy);
	if (len <= 0.0001f) return;
	float ux        = dx / len;
	float uy        = dy / len;
	float size      = 10.0f / zoom;
	float half      = 5.0f / zoom;
	RLVector2 base  = { p2[0] - ux * size, p2[1] - uy * size };
	RLVector2 perp  = { -uy, ux };
	RLVector2 left  = { base[0] + perp[0] * half, base[1] + perp[1] * half };
	RLVector2 right = { base[0] - perp[0] * half, base[1] - perp[1] * half };
	rl::draw_triangle(p2, left, right, color);
}

fn void draw_bezier(RLVector2 p1, RLVector2 p2, float thick, RLColor color)
{
	RLVector2 c2;
	RLVector2 c3;
	bezier_controls(p1, p2, &c2, &c3);
	rl::draw_spline_segment_bezier_cubic(p1, c2, c3, p2, thick, color);
}

fn void draw_dashed_bezier(RLVector2 p1, RLVector2 p2, float thick, float zoom, RLColor color)
{
	RLVector2 c2;
	RLVector2 c3;
	bezier_controls(p1, p2, &c2, &c3);

	int steps      = 26;
	bool on        = true;
	RLVector2 prev = p1;
	for (int s = 1; s <= steps; s++)
	{
		float t         = (float)s / (float)steps;
		RLVector2 point = rl::get_spline_point_bezier_cubic(p1, c2, c3, p2, t);
		if (on) rl::draw_line_ex(prev, point, thick, color);
		prev = point;
		on = !on;
	}
	draw_arrowhead(p1, c2, c3, p2, zoom, color);
}

fn void draw_label(RLFont font, String text, float x, float y, float size, RLColor color)
{
	if (text.len == 0) return;
	@pool()
	{
		rl::draw_text_ex(font, text.zstr_tcopy(), { x, y }, size, 0.0f, color);
	};
}

fn bool arrow_geometry(
	ImportIndex* index,
	project::Project* project,
	FileCard* card,
	ImportRef ref,
	int slot,
	int* out_target,
	RLVector2* out_p1,
	RLVector2* out_c2,
	RLVector2* out_c3,
	RLVector2* out_p2
)
{
	*out_target = -1;
	if (ref.resolved)
	{
		if (ref.target_path.compare_to((String)card.path) == 0) return false;
		int*? target = index.card_paths.get_ref(ref.target_path);
		if (catch excuse = target) return false;
		if (*target < 0 || *target >= (int)project.cards.len()) return false;
		if (!project.card_visible(*target)) return false;
		FileCard* target_card = &project.cards[*target];
		RLVector2 source_pt   = rect_center(card.rect);
		RLVector2 target_pt   = rect_center(target_card.rect);
		*out_target = *target;
		*out_p1 = rect_edge_point(card.rect, target_pt);
		*out_p2 = rect_edge_point(target_card.rect, source_pt);
		bezier_controls(*out_p1, *out_p2, out_c2, out_c3);
		return true;
	}

	*out_p2 = {
		card.rect.x + card.rect.width + 40.0f,
		card.rect.y - 18.0f - (float)slot * 16.0f,
	};
	*out_p1 = rect_edge_point(card.rect, *out_p2);
	bezier_controls(*out_p1, *out_p2, out_c2, out_c3);
	return true;
}

fn float point_segment_distance(RLVector2 p, RLVector2 a, RLVector2 b)
{
	float abx   = b[0] - a[0];
	float aby   = b[1] - a[1];
	float apx   = p[0] - a[0];
	float apy   = p[1] - a[1];
	float denom = abx * abx + aby * aby;
	float t     = 0.0f;
	if (denom > 0.000001f) t = (apx * abx + apy * aby) / denom;
	if (t < 0.0f) t = 0.0f;
	if (t > 1.0f) t = 1.0f;
	float cx = a[0] + abx * t;
	float cy = a[1] + aby * t;
	float dx = p[0] - cx;
	float dy = p[1] - cy;
	return math::sqrt(dx * dx + dy * dy);
}

fn float bezier_min_distance(RLVector2 p, RLVector2 p1, RLVector2 c2, RLVector2 c3, RLVector2 p2, int steps)
{
	if (steps < 1) steps = 1;
	float best     = 1000000000.0f;
	RLVector2 prev = p1;
	for (int s = 1; s <= steps; s++)
	{
		float t         = (float)s / (float)steps;
		RLVector2 point = rl::get_spline_point_bezier_cubic(p1, c2, c3, p2, t);
		float d         = point_segment_distance(p, prev, point);
		if (d < best) best = d;
		prev = point;
	}
	return best;
}

fn void draw_one(
	ImportIndex* index,
	project::Project* project,
	int source_index,
	FileCard* card,
	ImportRef ref,
	RLCamera2D camera,
	RLFont font,
	float thick,
	int active,
	int slot,
	bool hovered
)
{
	float zoom =  camera.zoom > 0.0f ? camera.zoom : 1.0f;
	int target = -1;
	RLVector2 p1;
	RLVector2 c2;
	RLVector2 c3;
	RLVector2 p2;
	if (!arrow_geometry(index, project, card, ref, slot, &target, &p1, &c2, &c3, &p2)) return;

	bool related = active < 0 || source_index == active || target == active;
	if (hovered)
	{
		related = true;
		thick *= 1.8f;
	}

	if (ref.resolved)
	{
		RLColor color = hovered ? theme::current()
			.import_solid_hover : (related ? theme::current().import_solid : theme::current().import_solid_dim);
		draw_bezier(p1, p2, thick, color);
		draw_arrowhead(p1, c2, c3, p2, zoom, color);
		return;
	}

	RLColor line_color  = hovered ? theme::current()
		.import_external_hover : (related ? theme::current().import_external : theme::current().import_external_dim);
	RLColor label_color = hovered ? theme::current()
		.import_external_hover : (related ? theme::current().import_label : theme::current().import_label_dim);
	draw_dashed_bezier(p1, p2, thick, zoom, line_color);
	rl::draw_circle_v(p2, 3.0f / zoom, line_color);
	draw_label(font, ref.specifier, p2[0] + 8.0f / zoom, p2[1] - 6.0f / zoom, 14.0f, label_color);
}

fn void ImportIndex.clear_hover(&self)
{
	self.hover.valid = false;
}

fn bool ImportIndex.hit_test(
	&self,
	project::Project* project,
	RLCamera2D camera,
	RLVector2 world,
	float screen_threshold
)
{
	self.hover.valid = false;
	self.refresh_card_paths(project);
	float zoom      = camera.zoom > 0.0f ? camera.zoom : 1.0f;
	float threshold = screen_threshold / zoom;
	Rect visible    = project::expand_rect(project::visible_world_rect(camera), 64.0f);
	float best      = threshold;

	for (sz i = 0; i < project.cards.len(); i++)
	{
		FileCard* card = &project.cards[i];
		if (!project.card_visible((int)i)) continue;
		if (!project::rect_intersects(card.rect, visible)) continue;

		ImportRef[] refs = self.imports_for((String)card.path);
		if (refs.len == 0) continue;

		usz external_slot = 0;
		for (usz r = 0; r < refs.len; r++)
		{
			ImportRef ref = refs[r];
			int slot      = 0;
			if (!ref.resolved)
			{
				slot = (int)external_slot;
				external_slot++;
			}
			int target = -1;
			RLVector2 p1;
			RLVector2 c2;
			RLVector2 c3;
			RLVector2 p2;
			if (!arrow_geometry(self, project, card, ref, slot, &target, &p1, &c2, &c3, &p2)) continue;
			float d = bezier_min_distance(world, p1, c2, c3, p2, BEZIER_HIT_STEPS);
			if (d <= best)
			{
				best = d;
				self.hover.valid = true;
				self.hover.source = (int)i;
				self.hover.ref_index = r;
				self.hover.target = target;
				self.hover.world = world;
			}
		}
	}
	return self.hover.valid;
}

fn void ImportIndex.draw(&self, project::Project* project, RLCamera2D camera, RLFont font)
{
	self.refresh_card_paths(project);
	int active   = project.focused;
	Rect visible = project::expand_rect(project::visible_world_rect(camera), 64.0f);
	float thick  = 2.0f / (camera.zoom > 0.0f ? camera.zoom : 1.0f);

	for (sz i = 0; i < project.cards.len(); i++)
	{
		FileCard* card = &project.cards[i];
		if (!project.card_visible((int)i)) continue;
		if (!project::rect_intersects(card.rect, visible)) continue;

		ImportRef[] refs = self.imports_for((String)card.path);
		if (refs.len == 0) continue;

		usz external_slot = 0;
		for (usz r = 0; r < refs.len; r++)
		{
			ImportRef ref = refs[r];
			int slot      = 0;
			if (!ref.resolved)
			{
				slot = (int)external_slot;
				external_slot++;
			}
			bool hovered = self.hover.valid && self.hover.source == (int)i && self.hover.ref_index == r;
			draw_one(self, project, (int)i, card, ref, camera, font, thick, active, slot, hovered);
		}
	}
}

fn void ImportIndex.draw_tooltip(&self, project::Project* project, RLFont font)
{
	if (!self.hover.valid) return;
	if (self.hover.source < 0 || self.hover.source >= (int)project.cards.len()) return;
	FileCard* card   = &project.cards[self.hover.source];
	ImportRef[] refs = self.imports_for((String)card.path);
	if (self.hover.ref_index >= refs.len) return;
	ImportRef ref = refs[self.hover.ref_index];

	@pool()
	{
		String source_name = rl::get_file_name((ZString)card.path.ptr).str_view();
		String keyword     = highlight::language_for_path((String)card.path) == highlight::Language.C ? "#include"
			: "import";
		String markdown;
		if (ref.resolved)
		{
			String target_name = "";
			int*? target       = self.card_paths.get_ref(ref.target_path);
			if (catch excuse = target)
			{
				target_name = "";
			}
			else
			{
				target_name = rl::get_file_name((ZString)project.cards[*target].path.ptr).str_view();
			}
			markdown = string::format(
				tmem,
				"`%s %s`\n%s:%d -> %s",
				keyword,
				ref.specifier,
				source_name,
				(long)(ref.line + 1),
				target_name
			);
		}
		else
		{
			markdown = string::format(
				tmem,
				"`%s %s`\n%s:%d (unresolved)",
				keyword,
				ref.specifier,
				source_name,
				(long)(ref.line + 1)
			);
		}
		hover::draw_hover(markdown, rl::get_mouse_position(), font);
	};
}