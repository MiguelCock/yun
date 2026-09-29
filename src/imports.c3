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
import yun::editor;
import yun::language;
import yun::hover;
import yun::project;
import yun::text;
import yun::theme;
import yun::ui;

const int MAX_SCAN_WORKERS         = 8;
const float ARROW_HIT_PX           = 6.0f;
const float ARROW_MIN_DRAW_PX      = 6.0f;
const float ARROW_LABEL_MIN_ZOOM   = 0.5f;
const int BEZIER_HIT_STEPS         = 20;
const double EDIT_DEBOUNCE_SECONDS = 0.15;

enum ArrowStyle : int
{
	SOLID,
	DASHED,
	DOTTED,
	LONG_DASH,
	DASH_DOT,
}

struct ImportSettings
{
	bool enabled;
	bool show_internal;
	bool show_external;
	bool labels;
	float line_thickness;
	float hover_thickness;
	float arrowhead_size;
	float hit_tolerance;
	float rescan_debounce;
	int scan_workers;
	ArrowStyle internal_style;
	ArrowStyle external_style;
	float dash_length;
	float dash_gap;
}

fn ArrowStyle parse_arrow_style(String value)
{
	if (value.compare_to("dashed") == 0) return ArrowStyle.DASHED;
	if (value.compare_to("dotted") == 0) return ArrowStyle.DOTTED;
	if (value.compare_to("long-dash") == 0) return ArrowStyle.LONG_DASH;
	if (value.compare_to("dash-dot") == 0) return ArrowStyle.DASH_DOT;
	return ArrowStyle.SOLID;
}

ImportSettings g_import_settings = {
	.enabled = true,
	.show_internal = true,
	.show_external = true,
	.labels = true,
	.line_thickness = 2.0f,
	.hover_thickness = 3.6f,
	.arrowhead_size = 10.0f,
	.hit_tolerance = ARROW_HIT_PX,
	.rescan_debounce = (float)EDIT_DEBOUNCE_SECONDS,
	.scan_workers = 0,
	.internal_style = ArrowStyle.SOLID,
	.external_style = ArrowStyle.DASHED,
	.dash_length = 8.0f,
	.dash_gap = 6.0f,
};

fn ImportSettings settings()
{
	return g_import_settings;
}

fn void set_settings(ImportSettings value)
{
	if (value.line_thickness < 0.0f) value.line_thickness = 0.0f;
	if (value.hover_thickness < 0.0f) value.hover_thickness = 0.0f;
	if (value.arrowhead_size < 0.0f) value.arrowhead_size = 0.0f;
	if (value.hit_tolerance < 0.0f) value.hit_tolerance = 0.0f;
	if (value.rescan_debounce < 0.0f) value.rescan_debounce = 0.0f;
	if (value.scan_workers < 0) value.scan_workers = 0;
	if (value.scan_workers > MAX_SCAN_WORKERS) value.scan_workers = MAX_SCAN_WORKERS;
	if (value.dash_length < 1.0f) value.dash_length = 1.0f;
	if (value.dash_gap < 1.0f) value.dash_gap = 1.0f;
	g_import_settings = value;
}

struct ImportRef
{
	String specifier;
	String target_path;
	String kind;
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
	language::Language language;
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
	int workers;
	UnboundedChannel{ScanResult}* results;
	uint generation;
	usz pending;
	usz received;
	bool scanning;
	usz scan_cursor;
	usz known_cards;
	int cached_revision;
	ImportHit hover;
	bool pending_edit;
	String pending_path;
	double pending_since;
	List{ImportContext*} contexts;
	HashMap{String, int} context_index;
}

TSQuery*[language::LANGUAGE_COUNT] import_query_cache;
bool[language::LANGUAGE_COUNT] import_query_loaded;
TSParser*[language::LANGUAGE_COUNT] import_parser_cache;
TSQuery*[language::LANGUAGE_COUNT] module_query_cache;
bool[language::LANGUAGE_COUNT] module_query_loaded;

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
	self.cached_revision = -1;
	self.generation = 0;
	self.pending = 0;
	self.received = 0;
	self.pool_ready = false;
	self.results = null;
	self.hover.valid = false;
	self.pending_edit = false;
	self.pending_path = "";
	self.pending_since = 0.0;
	self.contexts.init(allocator);
	self.context_index.init(allocator);
	self.init_pool();
}

fn void ImportIndex.free_contexts(&self)
{
	for (sz i = 0; i < self.contexts.len(); i++)
	{
		context_destroy(self.contexts[i]);
		alloc::free(self.allocator, self.contexts[i]);
	}
	self.contexts.clear();
	self.context_index.clear();
}

fn ImportContext* ImportIndex.context_for(&self, String source_path, language::Language language, String project_root)
{
	String root = find_module_root(self.allocator, project_root, source_path, language);
	int*? hit   = self.context_index.get_ref(root);
	if (try existing = hit)
	{
		root.free(self.allocator);
		return self.contexts[*existing];
	}

	ImportContext* ctx = alloc::new(self.allocator, ImportContext);
	context_build(ctx, self.allocator, root);
	root.free(self.allocator);
	self.contexts.push(ctx);
	self.context_index.set(ctx.root, (int)(self.contexts.len() - 1));
	return ctx;
}

fn int resolve_scan_workers()
{
	int workers = g_import_settings.scan_workers;
	if (workers <= 0) workers = os::num_cpu();
	if (workers < 1) workers = 1;
	if (workers > MAX_SCAN_WORKERS) workers = MAX_SCAN_WORKERS;
	return workers;
}

fn void ImportIndex.init_pool(&self)
{
	int workers = resolve_scan_workers();
	self.workers = workers;
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

fn void ImportIndex.apply_settings(&self)
{
	int want = resolve_scan_workers();
	if (want == self.workers) return;
	if (self.scanning) return;
	self.destroy_pool();
	self.init_pool();
}

fn void ImportIndex.destroy_pool(&self)
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
}

fn void ImportIndex.destroy(&self)
{
	self.destroy_pool();
	self.free_files();
	self.files.free();
	self.file_index.free();
	self.card_paths.free();
	self.clear_pending_edit();
	self.free_contexts();
	self.contexts.free();
	self.context_index.free();
}

fn TSQuery* make_query(language::Language language, String text)
{
	if (text.len == 0) return null;
	TSLanguage* lang = language::grammar_language(language);
	if (!lang) return null;
	uint offset        = 0;
	TSQueryError error = TS_QUERY_ERROR_NONE;
	TSQuery* query     = tree_sitter::ts_query_new(lang, (char*)text.ptr, (uint)text.len, &offset, &error);
	if (!query || error != TS_QUERY_ERROR_NONE) return null;
	return query;
}

fn TSParser* import_parser_for(language::Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= language::LANGUAGE_COUNT) return null;
	if (import_parser_cache[index]) return import_parser_cache[index];

	TSParser* parser = tree_sitter::ts_parser_new();
	if (!parser) return null;
	if (!tree_sitter::ts_parser_set_language(parser, language::grammar_language(language)))
	{
		tree_sitter::ts_parser_delete(parser);
		return null;
	}
	import_parser_cache[index] = parser;
	return parser;
}

fn TSQuery* import_query_for(language::Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= language::LANGUAGE_COUNT) return null;
	if (import_query_loaded[index]) return import_query_cache[index];
	import_query_loaded[index] = true;
	import_query_cache[index] = make_query(language, language::import_query_text(language));
	return import_query_cache[index];
}

fn TSQuery* module_query_for(language::Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= language::LANGUAGE_COUNT) return null;
	if (module_query_loaded[index]) return module_query_cache[index];
	module_query_loaded[index] = true;
	module_query_cache[index] = make_query(language, language::module_query_text(language));
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

				if (capture_name.compare_to("fn") == 0 || capture_name.compare_to("kind") == 0)
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
					if (node_type)
					{
						String nt = cstr_to_string(node_type);
						if (nt.compare_to("system_lib_string") == 0)
						{
							angled = true;
						}
					}
				}
			}
			if (!has_path) continue;

			String specifier = strip_quotes(path_text).copy(allocator);
			out.push(
				{
					.specifier = specifier,
					.target_path = "",
					.kind = fn_name.len > 0 ? fn_name.copy(allocator) : "",
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

// ---------------------------------------------------------------------------
// Import resolution context (project manifests + conventional source roots)
// ---------------------------------------------------------------------------

struct TsAlias
{
	String prefix;
	String target;
}

struct Psr4
{
	String prefix;
	String dir;
}

struct ImportContext
{
	Allocator allocator;
	String root;
	String go_module;
	String crate_name;
	String package_name;
	String ts_base;
	List{TsAlias} ts_paths;
	List{Psr4} psr4;
	List{String} hs_sources;
}

const String[] TS_EXTS    = { "", ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs" };
const String[] JS_EXTS    = { "", ".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx" };
const String[] INDEX_EXTS = { ".js", ".jsx", ".mjs", ".cjs", ".ts", ".tsx", ".index", "" };

fn String read_text(Allocator allocator, String path)
{
	char[]? data = file::load(allocator, path);
	if (catch excuse = data) return "";
	return (String)data;
}

fn String trim_spaces(String s)
{
	usz start = 0;
	usz end   = s.len;
	while (start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\r')) start++;
	while (end > start && (s[end - 1] == ' ' || s[end - 1] == '\t' || s[end - 1] == '\r')) end--;
	return s[start:end - start];
}

fn bool line_starts(String line, String prefix)
{
	return line.len >= prefix.len && line[0:prefix.len].compare_to(prefix) == 0;
}

fn String strip_assignment(String value)
{
	usz i = 0;
	while (i < value.len && (value[i] == ' ' || value[i] == '\t' || value[i] == '=' || value[i] == ':')) i++;
	String v = trim_spaces(value[i:value.len - i]);
	if (v.len > 0 && v[v.len - 1] == ',') v = trim_spaces(v[0:v.len - 1]);
	if (v.len >= 2 && ((v[0] == '"' && v[v.len - 1] == '"') || (v[0] == '\'' && v[v.len - 1] == '\'')))
	{
		return v[1:v.len - 2];
	}
	return v;
}

fn String manifest_value(Allocator allocator, String file_path, String key)
{
	@pool()
	{
		String text = read_text(tmem, file_path);
		usz i       = 0;
		while (i < text.len)
		{
			usz e = i;
			while (e < text.len && text[e] != '\n') e++;
			String line = trim_spaces(text[i:e - i]);
			if (line_starts(line, key))
			{
				String value = strip_assignment(line[key.len:line.len - key.len]);
				return value.copy(allocator);
			}
			i = e + 1;
		}
	};
	return "";
}

fn void context_build(ImportContext* ctx, Allocator allocator, String root)
{
	ctx.allocator = allocator;
	ctx.root = root.copy(allocator);
	ctx.go_module = manifest_value(allocator, string::format(tmem, "%s/go.mod", root), "module");
	ctx.crate_name = manifest_value(allocator, string::format(tmem, "%s/Cargo.toml", root), "name");
	ctx.package_name = manifest_value(allocator, string::format(tmem, "%s/pubspec.yaml", root), "name");
	ctx.ts_paths.init(allocator);
	ctx.psr4.init(allocator);
	ctx.hs_sources.init(allocator);

	// TypeScript / JavaScript baseUrl
	String tsconfig = string::format(tmem, "%s/tsconfig.json", root);
	if (!path::exists((Path)tsconfig)) tsconfig = string::format(tmem, "%s/jsconfig.json", root);
	String base = manifest_value(allocator, tsconfig, "\"baseUrl\"");
	if (base.len == 0) base = manifest_value(allocator, tsconfig, "baseUrl");
	if (base.len > 0 && base.compare_to(".") != 0)
	{
		ctx.ts_base = string::format(allocator, "%s/%s", root, base);
	}
	else if (base.len > 0)
	{
		ctx.ts_base = root.copy(allocator);
	}
	else
	{
		ctx.ts_base = "";
	}

	// TypeScript path aliases
	if (path::exists((Path)tsconfig))
	{
		String tstext     = read_text(tmem, tsconfig);
		String alias_base = ctx.ts_base.len > 0 ? ctx.ts_base : root;
		ctx_read_ts_paths(ctx, tstext, alias_base);
	}

	// composer.json PSR-4 prefixes
	String composer = string::format(tmem, "%s/composer.json", root);
	if (path::exists((Path)composer))
	{
		String text = read_text(tmem, composer);
		usz psr     = find_substr(text, 0, "psr-4");
		if (psr < text.len) ctx_read_psr4(ctx, text, psr);
	}

	// cabal hs-source-dirs
	@pool()
	{
		RLFilePathList files = rl::load_directory_files_ex(root.zstr_tcopy(), ".cabal".zstr_tcopy(), false);
		for (uint i = 0; i < files.count; i++)
		{
			String cpath = files.paths[i].str_view();
			String dirs  = manifest_value(allocator, string::format(tmem, "%s", cpath), "hs-source-dirs");
			if (dirs.len == 0) continue;
			ctx.hs_sources.push(string::format(allocator, "%s/%s", root, dirs));
		}
	};
	if (ctx.hs_sources.len() == 0)
	{
		ctx.hs_sources.push(string::format(allocator, "%s/src", root));
	}
}

fn void ctx_read_psr4(ImportContext* ctx, String text, usz start)
{
	// scan "Prefix\\": "dir/" pairs until the braces of the psr-4 block close
	usz i = start;
	while (i < text.len && text[i] != '{') i++;
	if (i >= text.len) return;
	i++;
	int depth = 1;
	while (i < text.len && depth > 0)
	{
		char c = text[i];
		if (c == '{')
		{
			depth++;
		}
		else if (c == '}')
		{
			depth--;
			i++;
			continue;
		}
		else if (c == '"')
		{
			usz ks = i + 1;
			usz ke = ks;
			while (ke < text.len && text[ke] != '"') ke++;
			String key = text[ks:ke - ks];
			usz j      = ke + 1;
			while (j < text.len && text[j] != '"') j++;
			usz vs = j + 1;
			usz ve = vs;
			while (ve < text.len && text[ve] != '"') ve++;
			if (j < text.len && ve < text.len)
			{
				String val = text[vs:ve - vs];
				while (val.len > 0 && (val[val.len - 1] == '/' || val[val.len - 1] == '\\')) val = val[0:val.len - 1];
				ctx.psr4.push(
					{
						.prefix = unescape_backslash(ctx.allocator, key),
						.dir = string::format(ctx.allocator, "%s/%s", ctx.root, val),
					}
				);
				i = ve + 1;
				continue;
			}
		}
		i++;
	}
}

fn void ctx_read_ts_paths(ImportContext* ctx, String text, String base_dir)
{
	usz start = find_substr(text, 0, "\"paths\"");
	if (start >= text.len) return;
	usz i = start;
	while (i < text.len && text[i] != '{') i++;
	if (i >= text.len) return;
	i++;
	int depth = 1;
	while (i < text.len && depth > 0)
	{
		char c = text[i];
		if (c == '{')
		{
			depth++;
			i++;
			continue;
		}
		if (c == '}')
		{
			depth--;
			i++;
			continue;
		}
		if (c == '"')
		{
			usz ks = i + 1;
			usz ke = ks;
			while (ke < text.len && text[ke] != '"') ke++;
			String key = text[ks:ke - ks];
			usz j      = ke + 1;
			while (j < text.len && text[j] != '[') j++;
			usz vs = j + 1;
			while (vs < text.len && text[vs] != '"') vs++;
			usz ve = vs + 1;
			while (ve < text.len && text[ve] != '"') ve++;
			if (ve < text.len)
			{
				String val = text[vs + 1:ve - vs - 1];
				ctx.ts_paths.push(
					{
						.prefix = key.copy(ctx.allocator),
						.target = string::format(ctx.allocator, "%s/%s", base_dir, val),
					}
				);
				i = ve + 1;
				continue;
			}
		}
		i++;
	}
}

fn void context_destroy(ImportContext* ctx)
{
	if (ctx.root.len) ctx.root.free(ctx.allocator);
	if (ctx.go_module.len) ctx.go_module.free(ctx.allocator);
	if (ctx.crate_name.len) ctx.crate_name.free(ctx.allocator);
	if (ctx.package_name.len) ctx.package_name.free(ctx.allocator);
	if (ctx.ts_base.len) ctx.ts_base.free(ctx.allocator);
	for (sz i = 0; i < ctx.ts_paths.len(); i++)
	{
		ctx.ts_paths[i].prefix.free(ctx.allocator);
		ctx.ts_paths[i].target.free(ctx.allocator);
	}
	ctx.ts_paths.free();
	for (sz i = 0; i < ctx.psr4.len(); i++)
	{
		ctx.psr4[i].prefix.free(ctx.allocator);
		ctx.psr4[i].dir.free(ctx.allocator);
	}
	ctx.psr4.free();
	for (sz i = 0; i < ctx.hs_sources.len(); i++) ctx.hs_sources[i].free(ctx.allocator);
	ctx.hs_sources.free();
}

fn usz find_substr(String haystack, usz from, String needle)
{
	if (needle.len == 0 || haystack.len < needle.len) return haystack.len;
	usz i = from;
	while (i + needle.len <= haystack.len)
	{
		if (haystack[i:needle.len].compare_to(needle) == 0) return i;
		i++;
	}
	return haystack.len;
}

fn bool push_if(HashMap{String, int}* paths, Allocator allocator, String candidate, List{String}* out)
{
	if (candidate.len == 0) return false;
	if (!paths.has_key(candidate)) return false;
	out.push(candidate.copy(allocator));
	return true;
}

fn bool try_dir(HashMap{String, int}* paths, Allocator allocator, String dir, String[] names, List{String}* out)
{
	for (usz i = 0; i < names.len; i++)
	{
		String candidate = string::format(allocator, "%s/%s", dir, names[i]);
		if (push_if(paths, allocator, candidate, out)) return true;
	}
	return false;
}

fn bool try_root(
	HashMap{String, int}* paths,
	Allocator allocator,
	String root,
	String rel,
	String[] exts,
	String index_name,
	List{String}* out
)
{
	String base = root.len > 0 ? string::format(allocator, "%s/%s", root, rel) : rel;
	for (usz e = 0; e < exts.len; e++)
	{
		String candidate = string::format(allocator, "%s%s", base, exts[e]);
		if (push_if(paths, allocator, candidate, out)) return true;
	}
	if (index_name.len > 0)
	{
		String candidate = string::format(allocator, "%s/%s", base, index_name);
		if (push_if(paths, allocator, candidate, out)) return true;
	}
	return false;
}

fn bool try_base(
	HashMap{String, int}* paths,
	Allocator allocator,
	String base,
	String[] exts,
	String index_name,
	List{String}* out
)
{
	for (usz e = 0; e < exts.len; e++)
	{
		String candidate = string::format(allocator, "%s%s", base, exts[e]);
		if (push_if(paths, allocator, candidate, out)) return true;
	}
	if (index_name.len > 0)
	{
		String candidate = string::format(allocator, "%s/%s", base, index_name);
		if (push_if(paths, allocator, candidate, out)) return true;
	}
	return false;
}

fn bool try_roots(
	HashMap{String, int}* paths,
	Allocator allocator,
	String[] roots,
	String rel,
	String[] exts,
	String index_name,
	List{String}* out
)
{
	for (usz r = 0; r < roots.len; r++)
	{
		if (try_root(paths, allocator, roots[r], rel, exts, index_name, out)) return true;
	}
	return false;
}

fn bool try_module_drop(
	HashMap{String, int}* paths,
	Allocator allocator,
	String[] roots,
	String rel,
	String[] exts,
	String index_name,
	List{String}* out
)
{
	String cur = rel;
	while (cur.len > 0)
	{
		if (try_roots(paths, allocator, roots, cur, exts, index_name, out)) return true;
		usz slash = cur.len;
		while (slash > 0 && cur[slash - 1] != '/') slash--;
		if (slash == 0) break;
		cur = cur[0:slash - 1];
	}
	return false;
}

fn String unescape_backslash(Allocator allocator, String s)
{
	DString out;
	out.init(allocator, s.len);
	usz i = 0;
	while (i < s.len)
	{
		if (s[i] == '\\' && i + 1 < s.len && s[i + 1] == '\\')
		{
			out.append_char('\\');
			i += 2;
			continue;
		}
		out.append_char(s[i]);
		i++;
	}
	String r = out.str_view().copy(allocator);
	out.free();
	return r;
}

fn String snake_path(Allocator allocator, String s)
{
	DString out;
	out.init(allocator, s.len + 8);
	for (usz i = 0; i < s.len; i++)
	{
		char c = s[i];
		if (c == '/')
		{
			out.append_char('/');
			continue;
		}
		if (c >= 'A' && c <= 'Z')
		{
			bool prev_lower = i > 0 && ((s[i - 1] >= 'a' && s[i - 1] <= 'z') || (s[i - 1] >= '0' && s[i - 1] <= '9'));
			bool prev_upper = i > 0 && s[i - 1] >= 'A' && s[i - 1] <= 'Z';
			bool next_lower = i + 1 < s.len && s[i + 1] >= 'a' && s[i + 1] <= 'z';
			if (prev_lower || (prev_upper && next_lower)) out.append_char('_');
			out.append_char((char)(c + 32));
		}
		else
		{
			out.append_char(c);
		}
	}
	String r = out.str_view().copy(allocator);
	out.free();
	return r;
}

fn bool any_file_under(HashMap{String, int}* paths, Allocator allocator, String dir_base, String ext, List{String}* out)
{
	String prefix = string::format(allocator, "%s/", dir_base);
	String[] keys = paths.keys(allocator);
	for (usz i = 0; i < keys.len; i++)
	{
		String key = keys[i];
		if (key.len > prefix.len && key[0:prefix.len].compare_to(prefix) == 0 && (ext.len == 0 || key.ends_with(ext)))
		{
			out.push(key.copy(allocator));
			return true;
		}
	}
	return false;
}

fn String replace_seps(Allocator allocator, String s, char from_a, char from_b, char to)
{
	DString out;
	out.init(allocator, s.len);
	for (usz i = 0; i < s.len; i++)
	{
		char c = s[i];
		if (c == from_a || c == from_b)
		{
			out.append_char(to);
		}
		else
		{
			out.append_char(c);
		}
	}
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn String strip_dotted(Allocator allocator, String s, String prefix)
{
	if (s.len >= prefix.len && s[0:prefix.len].compare_to(prefix) == 0)
	{
		String rest = s[prefix.len:s.len - prefix.len];
		while (rest.len > 0
			&& (rest[0] == '/' || rest[0] == '.' || rest[0] == ':' || rest[0] == '\\')) rest = rest[1:rest.len - 1];
		return rest;
	}
	return s;
}

fn bool any_ext_in(Allocator allocator, String dir, String ext)
{
	@pool()
	{
		RLFilePathList files = rl::load_directory_files_ex(dir.zstr_tcopy(), string::format(tmem, "*%s", ext)
			.zstr_tcopy(), false);
		return files.count > 0;
	};
}

fn bool has_manifest(String dir, language::Language language)
{
	@pool()
	{
		switch (language)
		{
			case language::Language.GO:
				return path::exists((Path)string::format(tmem, "%s/go.mod", dir));
			case language::Language.RUST:
				return path::exists((Path)string::format(tmem, "%s/Cargo.toml", dir));
			case language::Language.JAVASCRIPT:
			case language::Language.TYPESCRIPT:
			case language::Language.TSX:
				if (path::exists((Path)string::format(tmem, "%s/tsconfig.json", dir))) return true;
				if (path::exists((Path)string::format(tmem, "%s/jsconfig.json", dir))) return true;
				return path::exists((Path)string::format(tmem, "%s/package.json", dir));
			case language::Language.PHP:
				return path::exists((Path)string::format(tmem, "%s/composer.json", dir));
			case language::Language.DART:
				return path::exists((Path)string::format(tmem, "%s/pubspec.yaml", dir));
			case language::Language.ELIXIR:
				return path::exists((Path)string::format(tmem, "%s/mix.exs", dir));
			case language::Language.RUBY:
				return path::exists((Path)string::format(tmem, "%s/Gemfile", dir));
			case language::Language.V:
				return path::exists((Path)string::format(tmem, "%s/v.mod", dir));
			case language::Language.GLEAM:
				return path::exists((Path)string::format(tmem, "%s/gleam.toml", dir));
			case language::Language.JAVA:
				return path::exists(
					(Path)string::format(tmem, "%s/pom.xml", dir)
				) || path::exists(
					(Path)string::format(tmem, "%s/build.gradle", dir)
				) || path::exists(
					(Path)string::format(tmem, "%s/build.gradle.kts", dir)
				) || path::exists((Path)string::format(tmem, "%s/src/main/java", dir));
			case language::Language.KOTLIN:
				return path::exists(
					(Path)string::format(tmem, "%s/build.gradle", dir)
				) || path::exists(
					(Path)string::format(tmem, "%s/build.gradle.kts", dir)
				) || path::exists((Path)string::format(tmem, "%s/src/main/kotlin", dir));
			case language::Language.SCALA:
				return path::exists(
					(Path)string::format(tmem, "%s/build.sbt", dir)
				) || path::exists((Path)string::format(tmem, "%s/src/main/scala", dir));
			case language::Language.HASKELL:
				return any_ext_in(
					tmem,
					dir,
					".cabal"
				) || path::exists(
					(Path)string::format(tmem, "%s/stack.yaml", dir)
				) || path::exists((Path)string::format(tmem, "%s/package.yaml", dir));
			case language::Language.C_SHARP:
				return any_ext_in(tmem, dir, ".csproj") || any_ext_in(tmem, dir, ".sln");
			case language::Language.NIM:
				return any_ext_in(tmem, dir, ".nimble");
			default:
				return false;
		}
	};
}

fn String find_module_root(Allocator allocator, String project_root, String source_path, language::Language language)
{
	@pool()
	{
		String dir = dir_of(tmem, source_path);
		while (true)
		{
			if (has_manifest(dir, language)) return dir.copy(allocator);
			if (dir.compare_to(project_root) == 0) break;
			String parent = dir_of(tmem, dir);
			if (parent.compare_to(dir) == 0) break;
			if (parent.len < project_root.len) break;
			dir = parent;
		}
		return project_root.copy(allocator);
	};
}

fn bool roots_has(List{String}* out, String value)
{
	for (sz i = 0; i < out.len(); i++)
	{
		if ((*out)[i].compare_to(value) == 0) return true;
	}
	return false;
}

fn void roots_push_ancestor(Allocator allocator, String dir, List{String}* out)
{
	String[9] candidates;
	candidates[0] = dir.copy(allocator);
	candidates[1] = string::format(allocator, "%s/src", dir);
	candidates[2] = string::format(allocator, "%s/lib", dir);
	candidates[3] = string::format(allocator, "%s/src/main/java", dir);
	candidates[4] = string::format(allocator, "%s/src/main/kotlin", dir);
	candidates[5] = string::format(allocator, "%s/src/main/scala", dir);
	candidates[6] = string::format(allocator, "%s/test", dir);
	candidates[7] = string::format(allocator, "%s/app", dir);
	candidates[8] = string::format(allocator, "%s/include", dir);
	for (usz i = 0; i < 9; i++)
	{
		if (!roots_has(out, candidates[i])) out.push(candidates[i]);
	}
}

fn void roots_for(Allocator allocator, String ctx_root, String source_path, List{String}* out)
{
	@pool()
	{
		String dir = dir_of(tmem, source_path);
		while (true)
		{
			roots_push_ancestor(allocator, dir, out);
			if (dir.compare_to(ctx_root) == 0) break;
			String parent = dir_of(tmem, dir);
			if (parent.compare_to(dir) == 0) break;
			if (parent.len < ctx_root.len) break;
			dir = parent;
		}
	};
}

fn bool resolve_import(
	ImportContext* ctx,
	String[] roots,
	HashMap{String, int}* paths,
	CardImports[] files,
	Allocator allocator,
	String source_path,
	String specifier,
	String kind,
	bool angled,
	List{String}* out_targets
)
{
	if (specifier.len == 0) return false;
	language::Language language = language::language_for_path(source_path);
	String root                 = ctx.root;
	String dir                  = dir_of(allocator, source_path);

	switch (language)
	{
		case language::Language.C:
		case language::Language.CPP:

			{
				if (angled) return false;
				if (push_if(
					paths,
					allocator,
					string::format(allocator, "%s/%s", dir, specifier),
					out_targets
				)) return true;
				for (usz r = 0; r < roots.len; r++)
				{
					if (push_if(
						paths,
						allocator,
						string::format(allocator, "%s/%s", roots[r], specifier),
						out_targets
					)) return true;
				}
				return false;
			}
		case language::Language.JAVASCRIPT:
		case language::Language.TYPESCRIPT:
		case language::Language.TSX:

			{
				if (kind.len > 0 && kind.compare_to("require") != 0 && kind.compare_to("import") != 0) return false;
				if (specifier[0] == '.')
				{
					String rel = specifier;
					if (line_starts(rel, "./")) rel = rel[2:rel.len - 2];
					String base = string::format(allocator, "%s/%s", dir, rel);
					if (try_base(paths, allocator, base, JS_EXTS, "", out_targets)) return true;
					if (try_root(paths, allocator, base, "index", JS_EXTS, "", out_targets)) return true;
					return false;
				}
				for (sz a = 0; a < ctx.ts_paths.len(); a++)
				{
					String p = ctx.ts_paths[a].prefix;
					String t = ctx.ts_paths[a].target;
					if (p.len > 0 && p[p.len - 1] == '*') p = p[0:p.len - 1];
					if (t.len > 0 && t[t.len - 1] == '*') t = t[0:t.len - 1];
					if (specifier.len < p.len || p.len == 0 || specifier[0:p.len].compare_to(p) != 0) continue;
					String rest = specifier[p.len:specifier.len - p.len];
					String base = string::format(allocator, "%s%s", t, rest);
					if (try_base(paths, allocator, base, TS_EXTS, "", out_targets)) return true;
				}
				if (ctx.ts_base.len > 0)
				{
					String base = string::format(allocator, "%s/%s", ctx.ts_base, specifier);
					if (try_base(paths, allocator, base, TS_EXTS, "", out_targets)) return true;
				}
				for (usz r = 0; r < roots.len; r++)
				{
					String base = string::format(allocator, "%s/%s", roots[r], specifier);
					if (try_base(paths, allocator, base, TS_EXTS, "", out_targets)) return true;
				}
				return false;
			}
		case language::Language.PYTHON:

			{
				if (specifier[0] == '.')
				{
					usz dots = 0;
					while (dots < specifier.len && specifier[dots] == '.') dots++;
					String base = dir;
					usz back    = 1;
					while (back < dots)
					{
						base = dir_of(allocator, base);
						back++;
					}
					String rest = specifier[dots:specifier.len - dots];
					if (rest.len == 0) return false;
					String rel = module_rel(allocator, rest);
					if (try_root(paths, allocator, base, rel, { ".py" }, "__init__.py", out_targets)) return true;
					return false;
				}
				String rel = module_rel(allocator, specifier);
				if (try_roots(paths, allocator, roots, rel, { ".py" }, "__init__.py", out_targets)) return true;
				return false;
			}
		case language::Language.C3:

			{
				for (sz i = 0; i < files.len; i++)
				{
					if (files[i].is_test) continue;
					if (files[i].module_name.len == 0) continue;
					if (files[i].module_name.compare_to(specifier) != 0) continue;
					out_targets.push(((String)files[i].path).copy(allocator));
				}
				if (out_targets.len() > 0) return true;
				String rel = module_rel(allocator, specifier);
				if (try_roots(paths, allocator, roots, rel, { ".c3", ".c3i" }, "", out_targets)) return true;
				return false;
			}
		case language::Language.GO:

			{
				String rel = specifier;
				if (ctx.go_module.len > 0 && specifier.len >= ctx.go_module.len
					&& specifier[0:ctx.go_module.len].compare_to(
					ctx.go_module
				) == 0)
				{
					rel = specifier[ctx.go_module.len:specifier.len - ctx.go_module.len];
				}
				rel = strip_dotted(allocator, rel, "");
				// any .go file inside the directory
				String dir_base = string::format(allocator, "%s/%s", root, rel);
				String prefix   = string::format(allocator, "%s/", dir_base);
				String[] keys   = paths.keys(allocator);
				for (usz i = 0; i < keys.len; i++)
				{
					String key = keys[i];
					if (key.len > prefix.len && key[0:prefix.len].compare_to(prefix) == 0 && key.ends_with(".go"))
					{
						out_targets.push(key.copy(allocator));
						return true;
					}
				}
				return false;
			}
		case language::Language.RUST:

			{
				if (specifier.contains("::"))
				{
					String rel = replace_seps(allocator, specifier, ':', ':', '/');
					rel = strip_dotted(allocator, rel, "crate");
					rel = strip_dotted(allocator, rel, "self");
					String[1] src_root = { string::format(allocator, "%s/src", root) };
					if (try_module_drop(
						paths,
						allocator,
						src_root[0:1],
						rel,
						{ ".rs" },
						"mod.rs",
						out_targets
					)) return true;
					return false;
				}
				String base = string::format(allocator, "%s/%s", dir, specifier);
				if (push_if(paths, allocator, string::format(allocator, "%s.rs", base), out_targets)) return true;
				if (push_if(paths, allocator, string::format(allocator, "%s/mod.rs", base), out_targets)) return true;
				return false;
			}
		case language::Language.ZIG:

			{
				if (kind.len > 0 && kind.compare_to("@import") != 0 && kind.compare_to("import") != 0) return false;
				if (push_if(
					paths,
					allocator,
					string::format(allocator, "%s/%s", dir, specifier),
					out_targets
				)) return true;
				for (usz r = 0; r < roots.len; r++)
				{
					if (push_if(
						paths,
						allocator,
						string::format(allocator, "%s/%s", roots[r], specifier),
						out_targets
					)) return true;
				}
				return false;
			}
		case language::Language.ODIN:

			{
				if (specifier.contains(":")) return false;
				return try_root(
					paths,
					allocator,
					dir,
					specifier,
					{ ".odin" },
					"",
					out_targets
				) || try_roots(
					paths,
					allocator,
					roots,
					specifier,
					{ ".odin" },
					"",
					out_targets
				) || any_file_under(
					paths,
					allocator,
					string::format(allocator, "%s/%s", dir, specifier),
					".odin",
					out_targets
				);
			}
		case language::Language.V:

			{
				if (!specifier.contains(".") && !specifier.contains("/")) return false;
				String rel = replace_seps(allocator, specifier, '.', '.', '/');
				return try_roots(
					paths,
					allocator,
					roots,
					rel,
					{ ".v" },
					"",
					out_targets
				) || any_file_under(paths, allocator, string::format(allocator, "%s/%s", dir, rel), ".v", out_targets);
			}
		case language::Language.NIM:

			{
				if (line_starts(specifier, "std/")) return false;
				String rel = replace_seps(allocator, specifier, '/', '.', '/');
				rel = strip_dotted(allocator, rel, "./");
				return try_roots(paths, allocator, roots, rel, { ".nim" }, "", out_targets);
			}
		case language::Language.JAVA:

			{
				if (specifier.starts_with("java.") || specifier.starts_with("javax.")) return false;
				String rel = replace_seps(allocator, specifier, '.', '.', '/');
				return try_module_drop(paths, allocator, roots, rel, { ".java" }, "", out_targets);
			}
		case language::Language.KOTLIN:

			{
				if (specifier.starts_with("kotlin.")) return false;
				String rel = replace_seps(allocator, specifier, '.', '.', '/');
				return try_module_drop(paths, allocator, roots, rel, { ".kt", ".kts" }, "", out_targets);
			}
		case language::Language.SCALA:

			{
				String spec = trim_spaces(specifier);
				if (line_starts(spec, "import ")) spec = trim_spaces(spec[7:spec.len - 7]);
				if (spec.starts_with("scala.") || spec.starts_with("java.")) return false;
				String rel = replace_seps(allocator, spec, '.', '.', '/');
				return try_module_drop(paths, allocator, roots, rel, { ".scala", ".sc" }, "", out_targets);
			}
		case language::Language.C_SHARP:

			{
				if (specifier.starts_with("System")) return false;
				String rel = replace_seps(allocator, specifier, '.', '.', '/');
				return try_module_drop(paths, allocator, roots, rel, { ".cs" }, "", out_targets);
			}
		case language::Language.CSS:

			{
				return try_root(
					paths,
					allocator,
					dir,
					specifier,
					{ "", ".css" },
					"",
					out_targets
				) || try_roots(paths, allocator, roots, specifier, { "", ".css" }, "", out_targets);
			}
		case language::Language.HTML:

			{
				if (kind.len > 0 && kind.compare_to("src") != 0 && kind.compare_to("href") != 0) return false;
				if (specifier.starts_with("http") || specifier.starts_with("//")) return false;
				return try_root(paths, allocator, dir, specifier, { "" }, "", out_targets);
			}
		case language::Language.LUA:

			{
				if (kind.len > 0 && kind.compare_to("require") != 0) return false;
				String rel = module_rel(allocator, specifier);
				if (push_if(
					paths,
					allocator,
					string::format(allocator, "%s/%s.lua", dir, rel),
					out_targets
				)) return true;
				if (push_if(
					paths,
					allocator,
					string::format(allocator, "%s/%s/init.lua", dir, rel),
					out_targets
				)) return true;
				return try_roots(paths, allocator, roots, rel, { ".lua" }, "init.lua", out_targets);
			}
		case language::Language.PHP:

			{
				if (specifier.contains("\\"))
				{
					for (sz p = 0; p < ctx.psr4.len(); p++)
					{
						String prefix = ctx.psr4[p].prefix;
						if (specifier.len < prefix.len || specifier[0:prefix.len].compare_to(prefix) != 0) continue;
						String rest = specifier[prefix.len:specifier.len - prefix.len];
						String rel  = replace_seps(allocator, rest, '\\', '\\', '/');
						if (try_roots(
							paths,
							allocator,
							{ ctx.psr4[p].dir },
							rel,
							{ ".php" },
							"",
							out_targets
						)) return true;
					}
					String rel = replace_seps(allocator, specifier, '\\', '\\', '/');
					return try_roots(paths, allocator, roots, rel, { ".php" }, "", out_targets);
				}
				return try_root(paths, allocator, dir, specifier, { "" }, "", out_targets);
			}
		case language::Language.RUBY:

			{
				String rel = specifier;
				if (kind.compare_to("require_relative") == 0)
				{
					return try_root(paths, allocator, dir, rel, { ".rb" }, "", out_targets);
				}
				if (kind.len > 0 && kind.compare_to("require") != 0 && kind.compare_to("load") != 0) return false;
				return try_roots(paths, allocator, roots, rel, { ".rb" }, "", out_targets);
			}
		case language::Language.R:

			{
				if (kind.len > 0 && kind.compare_to("source") != 0 && kind.compare_to("sys.source") != 0) return false;
				return try_root(paths, allocator, dir, specifier, { ".R", ".r", "" }, "", out_targets);
			}
		case language::Language.JULIA:

			{
				if (kind.len > 0)
				{
					if (kind.compare_to("include") != 0) return false;
					return try_root(paths, allocator, dir, specifier, { "", ".jl" }, "", out_targets);
				}
				// using/import: package or relative file
				if (try_roots(paths, allocator, roots, specifier, { "", ".jl" }, "", out_targets)) return true;
				return try_roots(
					paths,
					allocator,
					roots,
					string::format(allocator, "%s/src/%s", specifier, specifier),
					{ "", ".jl" },
					"",
					out_targets
				);
			}
		case language::Language.HASKELL:

			{
				String rel = replace_seps(allocator, specifier, '.', '.', '/');
				List{String} hs;
				hs.init(tmem);
				for (sz i = 0; i < ctx.hs_sources.len(); i++) hs.push(ctx.hs_sources[i]);
				for (usz r = 0; r < roots.len; r++) hs.push(roots[r]);
				return try_roots(paths, allocator, hs.entries[0:hs.len()], rel, { ".hs", ".lhs" }, "", out_targets);
			}
		case language::Language.GLEAM:

			{
				if (specifier.starts_with("gleam/")) return false;
				String rel = module_rel(allocator, specifier);
				return try_roots(paths, allocator, roots, rel, { ".gleam" }, "", out_targets);
			}
		case language::Language.ERLANG:

			{
				if (kind.compare_to("include_lib") == 0) return false;
				return try_root(
					paths,
					allocator,
					dir,
					specifier,
					{ "" },
					"",
					out_targets
				) || try_roots(paths, allocator, roots, specifier, { "" }, "", out_targets);
			}
		case language::Language.ELIXIR:

			{
				if (kind.len > 0 && kind.compare_to(
					"alias"
				) != 0 && kind.compare_to(
					"import"
				) != 0 && kind.compare_to("require") != 0 && kind.compare_to("use") != 0) return false;
				String rel = replace_seps(allocator, specifier, '.', '.', '/');
				rel = snake_path(allocator, rel);
				return try_module_drop(paths, allocator, roots, rel, { ".ex", ".exs" }, "", out_targets);
			}
		case language::Language.DART:

			{
				if (specifier.starts_with("dart:")) return false;
				if (specifier.starts_with("package:"))
				{
					String rest = specifier[8:specifier.len - 8];
					usz slash   = 0;
					while (slash < rest.len && rest[slash] != '/') slash++;
					if (slash >= rest.len) return false;
					String pkg = rest[0:slash];
					String rel = rest[slash + 1:rest.len - slash - 1];
					if (ctx.package_name.len == 0 || pkg.compare_to(ctx.package_name) != 0) return false;
					return try_root(
						paths,
						allocator,
						string::format(allocator, "%s/lib", root),
						rel,
						{ "", ".dart" },
						"",
						out_targets
					);
				}
				return try_root(paths, allocator, dir, specifier, { "", ".dart" }, "", out_targets);
			}
		case language::Language.MARKDOWN:
		case language::Language.MARKDOWN_INLINE:
		case language::Language.NONE:
			return false;
		default:
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
		if (ref.kind.len) ref.kind.free(allocator);
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
	if (self.cached_revision == project.cards_revision) return;
	self.card_paths.clear();
	for (sz i = 0; i < project.cards.len(); i++)
	{
		self.card_paths.set((String)project.cards[i].path, (int)i);
	}
	self.cached_revision = project.cards_revision;
}

fn void ImportIndex.resolve_file(&self, project::Project* project, CardImports[] all_files, CardImports* file)
{
	language::Language language = language::language_for_path((String)file.path);
	if (language == language::Language.NONE) return;
	ImportContext* ctx = self.context_for((String)file.path, language, (String)project.root);
	List{String} roots;
	roots.init(tmem);
	roots_for(tmem, ctx.root, (String)file.path, &roots);
	String[] root_view = roots.entries[0:roots.len()];

	List{ImportRef} next;
	next.init(self.allocator);
	for (sz r = 0; r < file.imports.len(); r++)
	{
		ImportRef* ref = &file.imports[r];
		List{String} targets;
		targets.init(tmem);
		bool ok = resolve_import(
			ctx,
			root_view,
			&self.card_paths,
			all_files,
			tmem,
			(String)file.path,
			ref.specifier,
			ref.kind,
			ref.angled,
			&targets
		);
		if (!ok)
		{
			next.push(
				{
					.specifier = ref.specifier.copy(self.allocator),
					.target_path = "",
					.kind = ref.kind.len > 0 ? ref.kind.copy(self.allocator) : "",
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
						.kind = ref.kind.len > 0 ? ref.kind.copy(self.allocator) : "",
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
	self.free_contexts();
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
		FileCard* card              = &project.cards[i];
		language::Language language = language::language_for_path((String)card.path);
		if (language == language::Language.NONE) continue;
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
	FileCard* card              = &project.cards[card_index];
	language::Language language = language::language_for_path((String)card.path);
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
		if (language != language::Language.NONE)
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
	self.apply_settings();
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
	if (language::language_for_path((String)card.path) == language::Language.NONE) return;
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
	return now - since >= (double)g_import_settings.rescan_debounce;
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
	language::Language language,
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
		if (!tree_sitter::ts_parser_set_language(parser, language::grammar_language(language)))
		{
			tree_sitter::ts_parser_delete(parser);
			return;
		}
		TSQuery* import_query = make_query(language, language::import_query_text(language));
		TSQuery* module_query = make_query(language, language::module_query_text(language));
		extract_imports(allocator, parser, import_query, module_query, text, out, out_module, out_is_test);
		if (import_query) tree_sitter::ts_query_delete(import_query);
		if (module_query) tree_sitter::ts_query_delete(module_query);
		tree_sitter::ts_parser_delete(parser);
	};
}

fn void import_scan_worker(void* arg)
{
	ScanWork* work              = (ScanWork*)arg;
	ImportIndex* index          = work.index;
	String path                 = work.path;
	language::Language language = work.language;
	uint generation             = work.generation;

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
	float size      = g_import_settings.arrowhead_size / zoom;
	float half      = size * 0.5f;
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

fn int dash_steps(RLVector2 p1, RLVector2 p2, float zoom)
{
	float dx         = p2[0] - p1[0];
	float dy         = p2[1] - p1[1];
	float screen_len = math::sqrt(dx * dx + dy * dy) * zoom;
	int steps        = (int)(screen_len / 5.0f);
	return (int)math::clamp((float)steps, 16.0f, 64.0f);
}

fn void draw_styled_bezier(RLVector2 p1, RLVector2 p2, float thick, float zoom, ArrowStyle style, RLColor color)
{
	if (style == ArrowStyle.SOLID)
	{
		draw_bezier(p1, p2, thick, color);
		return;
	}

	RLVector2 c2;
	RLVector2 c3;
	bezier_controls(p1, p2, &c2, &c3);

	float dash = g_import_settings.dash_length / zoom;
	float gap  = g_import_settings.dash_gap / zoom;
	if (style == ArrowStyle.DOTTED)
	{
		dash = 1.0f / zoom;
	}
	else if (style == ArrowStyle.LONG_DASH)
	{
		dash = (g_import_settings.dash_length * 2.0f) / zoom;
	}
	float small = 1.0f / zoom;

	int steps       = dash_steps(p1, p2, zoom);
	bool on         = true;
	bool short_dash = false;
	float remaining = dash;
	RLVector2 prev  = p1;
	for (int s = 1; s <= steps; s++)
	{
		float t         = (float)s / (float)steps;
		RLVector2 point = rl::get_spline_point_bezier_cubic(p1, c2, c3, p2, t);
		if (on) rl::draw_line_ex(prev, point, thick, color);
		float dx = point[0] - prev[0];
		float dy = point[1] - prev[1];
		remaining -= math::sqrt(dx * dx + dy * dy);
		if (remaining <= 0.0f)
		{
			if (on)
			{
				on = false;
				remaining = gap;
			}
			else if (style == ArrowStyle.DASH_DOT && !short_dash)
			{
				on = true;
				short_dash = true;
				remaining = small;
			}
			else
			{
				on = true;
				short_dash = false;
				remaining = dash;
			}
		}
		prev = point;
	}
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

	float label_scale = ui::scale();
	*out_p2 = {
		card.rect.x + card.rect.width + 40.0f * label_scale,
		card.rect.y - (18.0f + (float)slot * 16.0f) * label_scale,
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
	int active,
	int slot,
	bool hovered
)
{
	float zoom = camera.zoom > 0.0f ? camera.zoom : 1.0f;
	if (ref.resolved && !g_import_settings.show_internal) return;
	if (!ref.resolved && !g_import_settings.show_external) return;

	int target = -1;
	RLVector2 p1;
	RLVector2 c2;
	RLVector2 c3;
	RLVector2 p2;
	if (!arrow_geometry(index, project, card, ref, slot, &target, &p1, &c2, &c3, &p2)) return;

	if (!hovered)
	{
		float dx = p2[0] - p1[0];
		float dy = p2[1] - p1[1];
		if (math::sqrt(dx * dx + dy * dy) * zoom < ARROW_MIN_DRAW_PX) return;
	}

	bool related = active < 0 || source_index == active || target == active;
	float thick  = (hovered ? g_import_settings.hover_thickness : g_import_settings.line_thickness) / zoom;
	if (hovered)
	{
		related = true;
	}

	if (ref.resolved)
	{
		RLColor color = hovered ? theme::current()
			.import_solid_hover : (related ? theme::current().import_solid : theme::current().import_solid_dim);
		draw_styled_bezier(p1, p2, thick, zoom, g_import_settings.internal_style, color);
		draw_arrowhead(p1, c2, c3, p2, zoom, color);
		return;
	}

	RLColor line_color  = hovered ? theme::current()
		.import_external_hover : (related ? theme::current().import_external : theme::current().import_external_dim);
	RLColor label_color = hovered ? theme::current()
		.import_external_hover : (related ? theme::current().import_label : theme::current().import_label_dim);
	draw_styled_bezier(p1, p2, thick, zoom, g_import_settings.external_style, line_color);
	draw_arrowhead(p1, c2, c3, p2, zoom, line_color);
	float s  = ui::scale();
	float ts = ui::text_scale();
	rl::draw_circle_v(p2, 3.0f * s / zoom, line_color);
	if (g_import_settings.labels && (hovered || zoom >= ARROW_LABEL_MIN_ZOOM))
	{
		draw_label(font, ref.specifier, p2[0] + 8.0f * s / zoom, p2[1] - 6.0f * s / zoom, 14.0f * ts, label_color);
	}
}

fn void ImportIndex.clear_hover(&self)
{
	self.hover.valid = false;
}

fn bool ImportIndex.hit_test(&self, project::Project* project, RLCamera2D camera, RLVector2 world)
{
	self.hover.valid = false;
	if (!g_import_settings.enabled) return false;
	self.refresh_card_paths(project);
	float zoom      = camera.zoom > 0.0f ? camera.zoom : 1.0f;
	float threshold = g_import_settings.hit_tolerance / zoom;
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
			if (ref.resolved && !g_import_settings.show_internal) continue;
			if (!ref.resolved && !g_import_settings.show_external) continue;
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
	if (!g_import_settings.enabled) return;
	self.refresh_card_paths(project);
	int active   = project.focused;
	Rect visible = project::expand_rect(project::visible_world_rect(camera), 64.0f);

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
			draw_one(self, project, (int)i, card, ref, camera, font, active, slot, hovered);
		}
	}
}

fn void ImportIndex.draw_tooltip(&self, project::Project* project, RLFont font)
{
	if (!g_import_settings.enabled) return;
	if (!self.hover.valid) return;
	if (self.hover.source < 0 || self.hover.source >= (int)project.cards.len()) return;
	FileCard* card   = &project.cards[self.hover.source];
	ImportRef[] refs = self.imports_for((String)card.path);
	if (self.hover.ref_index >= refs.len) return;
	ImportRef ref = refs[self.hover.ref_index];

	@pool()
	{
		String source_name = rl::get_file_name((ZString)card.path.ptr).str_view();
		String keyword     = language::language_for_path((String)card.path) == language::Language.C ? "#include"
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