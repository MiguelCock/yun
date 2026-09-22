module yun::highlight;

import libc;
import raylib6::rl;
import std::collections::list;
import std::core::mem::alloc;
import std::io::file;
import std::io::path;
import yun::text;
import tree_sitter;
import tree_sitter_c;
import tree_sitter_c3;
import tree_sitter_javascript;
import tree_sitter_python;

enum Language : int
{
	NONE,
	C3,
	C,
	PYTHON,
	JAVASCRIPT,
}

enum SyntaxRole : int
{
	TEXT,
	KEYWORD,
	STRING,
	COMMENT,
	NUMBER,
	TYPE,
	FUNCTION,
	VARIABLE,
	CONSTANT,
	OPERATOR,
	PUNCTUATION,
	ATTRIBUTE,
	MODULE,
	LABEL,
	BOOLEAN,
	CHARACTER,
	ESCAPE,
	PARAMETER,
	PROPERTY,
	BUILTIN,
	NONE,
}

const RLColor SYNTAX_BASE = { 210, 214, 222, 255 };

struct Span
{
	uint start;
	uint end;
	SyntaxRole role;
}

struct Highlighter
{
	Language language;
	TSParser* parser;
	TSTree* tree;
	TSQuery* query;
	String source;
	List{Span} spans;
	bool dirty;
	bool has_tree;
	PieceTable* table;
	Allocator allocator;
}

TSQuery*[5] query_cache;
bool[5] query_loaded;

fn int span_compare(void* a, void* b)
{
	Span* sa = (Span*)a;
	Span* sb = (Span*)b;
	if (sa.start != sb.start) return sa.start < sb.start ? -1 : 1;
	if (sa.end != sb.end) return sa.end > sb.end ? -1 : 1;
	return 0;
}

fn String path_extension(String path)
{
	sz dot = -1;
	for (sz i = (sz)path.len; i > 0; i--)
	{
		char c = path[(usz)(i - 1)];
		if (c == '.')
		{
			dot = i - 1;
			break;
		}
		if (c == '/' || c == '\\') break;
	}
	if (dot < 0) return "";
	return path[(usz)dot:path.len - (usz)dot];
}

fn Language language_for_path(String path)
{
	String ext = path_extension(path);
	if (ext.compare_to(".c3") == 0 || ext.compare_to(".c3i") == 0) return Language.C3;
	if (ext.compare_to(".c") == 0 || ext.compare_to(".h") == 0) return Language.C;
	if (ext.compare_to(".py") == 0) return Language.PYTHON;
	if (ext.compare_to(".js") == 0) return Language.JAVASCRIPT;
	if (ext.compare_to(".mjs") == 0) return Language.JAVASCRIPT;
	if (ext.compare_to(".cjs") == 0) return Language.JAVASCRIPT;
	return Language.NONE;
}

fn TSLanguage* grammar_language(Language language)
{
	switch (language)
	{
		case Language.C3:
			return tree_sitter_c3::tree_sitter_c3();
		case Language.C:
			return tree_sitter_c::tree_sitter_c();
		case Language.PYTHON:
			return tree_sitter_python::tree_sitter_python();
		case Language.JAVASCRIPT:
			return tree_sitter_javascript::tree_sitter_javascript();
		case Language.NONE:
			return null;
	}
}

fn String grammar_query_path(Language language)
{
	switch (language)
	{
		case Language.C3:
			return "lib/tree_sitter_c3.c3l/queries/highlights.scm";
		case Language.C:
			return "lib/tree_sitter_c.c3l/queries/highlights.scm";
		case Language.PYTHON:
			return "lib/tree_sitter_python.c3l/queries/highlights.scm";
		case Language.JAVASCRIPT:
			return "lib/tree_sitter_javascript.c3l/queries/highlights.scm";
		case Language.NONE:
			return "";
	}
}

fn char[] load_query_text(Allocator allocator, String rel)
{
	if (file::exists(rel))
	{
		char[]? text = file::load(allocator, rel);
		if (catch excuse = text) return { };
		return text;
	}
	@pool()
	{
		String exe    = rl::get_application_directory().str_view();
		String joined = string::format(tmem, "%s%s", exe, rel);
		if (file::exists(joined))
		{
			char[]? text = file::load(allocator, joined);
			if (catch excuse = text) return { };
			return text;
		}
	};
	return { };
}

fn TSQuery* build_query(Language language)
{
	String rel = grammar_query_path(language);
	if (rel.len == 0) return null;

	TSQuery* result = null;
	@pool()
	{
		char[] text = load_query_text(tmem, rel);
		if (text.len != 0)
		{
			uint offset        = 0;
			TSQueryError error = TS_QUERY_ERROR_NONE;
			result = tree_sitter::ts_query_new(
				grammar_language(language),
				(char*)text.ptr,
				(uint)text.len,
				&offset,
				&error
			);
			if (result && error != TS_QUERY_ERROR_NONE) result = null;
		}
	};
	return result;
}

fn TSQuery* query_for(Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= 5) return null;
	if (query_loaded[index]) return query_cache[index];
	query_loaded[index] = true;
	query_cache[index] = build_query(language);
	return query_cache[index];
}

fn SyntaxRole role_for_name(String name)
{
	if (name.starts_with("keyword")) return SyntaxRole.KEYWORD;
	if (name.starts_with("comment")) return SyntaxRole.COMMENT;
	if (name.starts_with("string.escape")) return SyntaxRole.ESCAPE;
	if (name.starts_with("string.special")) return SyntaxRole.ESCAPE;
	if (name.starts_with("string")) return SyntaxRole.STRING;
	if (name.starts_with("character")) return SyntaxRole.CHARACTER;
	if (name.starts_with("number")) return SyntaxRole.NUMBER;
	if (name.starts_with("boolean")) return SyntaxRole.BOOLEAN;
	if (name.starts_with("constant.builtin")) return SyntaxRole.BUILTIN;
	if (name.starts_with("constant")) return SyntaxRole.CONSTANT;
	if (name.starts_with("type.builtin")) return SyntaxRole.TYPE;
	if (name.starts_with("type")) return SyntaxRole.TYPE;
	if (name.starts_with("constructor")) return SyntaxRole.TYPE;
	if (name.starts_with("function")) return SyntaxRole.FUNCTION;
	if (name.starts_with("method")) return SyntaxRole.FUNCTION;
	if (name.starts_with("variable.parameter")) return SyntaxRole.PARAMETER;
	if (name.starts_with("variable.member")) return SyntaxRole.PROPERTY;
	if (name.starts_with("variable.builtin")) return SyntaxRole.BUILTIN;
	if (name.starts_with("variable")) return SyntaxRole.VARIABLE;
	if (name.starts_with("property")) return SyntaxRole.PROPERTY;
	if (name.starts_with("field")) return SyntaxRole.PROPERTY;
	if (name.starts_with("operator")) return SyntaxRole.OPERATOR;
	if (name.starts_with("punctuation")) return SyntaxRole.PUNCTUATION;
	if (name.starts_with("attribute")) return SyntaxRole.ATTRIBUTE;
	if (name.starts_with("module")) return SyntaxRole.MODULE;
	if (name.starts_with("namespace")) return SyntaxRole.MODULE;
	if (name.starts_with("label")) return SyntaxRole.LABEL;
	if (name.starts_with("tag")) return SyntaxRole.TYPE;
	if (name.starts_with("escape")) return SyntaxRole.ESCAPE;
	return SyntaxRole.NONE;
}

fn SyntaxRole role_for_capture(TSQuery* query, uint index)
{
	uint length = 0;
	char* name  = tree_sitter::ts_query_capture_name_for_id(query, index, &length);
	if (!name || length == 0) return SyntaxRole.NONE;
	return role_for_name((String)name[0:length]);
}

fn RLColor role_color(SyntaxRole role)
{
	switch (role)
	{
		case SyntaxRole.KEYWORD:
			return { 197, 134, 192, 255 };
		case SyntaxRole.STRING:
			return { 152, 195, 121, 255 };
		case SyntaxRole.COMMENT:
			return { 108, 112, 134, 255 };
		case SyntaxRole.NUMBER:
			return { 209, 154, 102, 255 };
		case SyntaxRole.TYPE:
			return { 229, 192, 123, 255 };
		case SyntaxRole.FUNCTION:
			return { 97, 175, 239, 255 };
		case SyntaxRole.CONSTANT:
			return { 209, 154, 102, 255 };
		case SyntaxRole.OPERATOR:
			return { 86, 182, 194, 255 };
		case SyntaxRole.PUNCTUATION:
			return { 150, 155, 170, 255 };
		case SyntaxRole.ATTRIBUTE:
			return { 229, 192, 123, 255 };
		case SyntaxRole.MODULE:
			return { 229, 192, 123, 255 };
		case SyntaxRole.LABEL:
			return { 97, 175, 239, 255 };
		case SyntaxRole.BOOLEAN:
			return { 209, 154, 102, 255 };
		case SyntaxRole.CHARACTER:
			return { 152, 195, 121, 255 };
		case SyntaxRole.ESCAPE:
			return { 86, 182, 194, 255 };
		case SyntaxRole.PARAMETER:
			return { 220, 190, 160, 255 };
		case SyntaxRole.PROPERTY:
			return { 224, 108, 117, 255 };
		case SyntaxRole.BUILTIN:
			return { 86, 182, 194, 255 };
		case SyntaxRole.VARIABLE:
			return SYNTAX_BASE;
		case SyntaxRole.TEXT:
			return SYNTAX_BASE;
		case SyntaxRole.NONE:
			return SYNTAX_BASE;
	}
}

fn Highlighter* create(Allocator allocator, PieceTable* table, String path)
{
	Language language = language_for_path(path);
	if (language == Language.NONE) return null;

	TSQuery* query = query_for(language);
	if (!query) return null;

	Highlighter* highlighter = alloc::new(allocator, Highlighter);
	highlighter.language = language;
	highlighter.allocator = allocator;
	highlighter.table = table;
	highlighter.query = query;
	highlighter.source = "";
	highlighter.tree = null;
	highlighter.has_tree = false;
	highlighter.dirty = true;
	highlighter.spans.init(allocator);
	highlighter.parser = tree_sitter::ts_parser_new();
	if (!highlighter.parser)
	{
		highlighter.spans.free();
		alloc::free(allocator, highlighter);
		return null;
	}
	if (!tree_sitter::ts_parser_set_language(highlighter.parser, grammar_language(language)))
	{
		tree_sitter::ts_parser_delete(highlighter.parser);
		highlighter.spans.free();
		alloc::free(allocator, highlighter);
		return null;
	}
	return highlighter;
}

fn void destroy(Highlighter* highlighter, Allocator allocator)
{
	if (!highlighter) return;
	if (highlighter.tree) tree_sitter::ts_tree_delete(highlighter.tree);
	if (highlighter.parser) tree_sitter::ts_parser_delete(highlighter.parser);
	if (highlighter.source.len) highlighter.source.free(allocator);
	highlighter.spans.free();
	alloc::free(allocator, highlighter);
}

fn void Highlighter.mark_dirty(&self)
{
	self.dirty = true;
}

fn void Highlighter.rebuild_spans(&self)
{
	self.spans.clear();
	if (!self.has_tree || !self.query) return;

	TSQueryCursor* cursor = tree_sitter::ts_query_cursor_new();
	if (!cursor) return;

	TSNode root = tree_sitter::ts_tree_root_node(self.tree);
	tree_sitter::ts_query_cursor_exec(cursor, self.query, root);

	TSQueryMatch match;
	uint capture_index = 0;
	while (tree_sitter::ts_query_cursor_next_capture(cursor, &match, &capture_index))
	{
		if (match.capture_count == 0) continue;
		TSQueryCapture capture = match.captures[0];
		SyntaxRole role        = role_for_capture(self.query, capture.index);
		if (role == SyntaxRole.NONE) continue;
		uint start = tree_sitter::ts_node_start_byte(capture.node);
		uint end   = tree_sitter::ts_node_end_byte(capture.node);
		if (end <= start) continue;
		self.spans.push({ .start = start, .end = end, .role = role });
	}
	tree_sitter::ts_query_cursor_delete(cursor);

	if (self.spans.len() > 1)
	{
		libc::qsort(self.spans.entries, (usz)self.spans.size, Span::size, &span_compare);
	}
}

fn void Highlighter.ensure_parsed(&self)
{
	if (!self.dirty && self.has_tree) return;
	if (self.source.len)
	{
		self.source.free(self.allocator);
		self.source = "";
	}
	self.source = self.table.slice(0, self.table.length(), self.allocator);
	if (self.tree)
	{
		tree_sitter::ts_tree_delete(self.tree);
		self.tree = null;
	}
	self.tree = tree_sitter::ts_parser_parse_string(self.parser, null, (char*)self.source.ptr, (uint)self.source.len);
	self.has_tree = self.tree != null;
	self.rebuild_spans();
	self.dirty = false;
}

fn SyntaxRole Highlighter.role_at(&self, usz offset, sz first)
{
	uint off        = (uint)offset;
	SyntaxRole role = SyntaxRole.TEXT;
	for (sz i = first; i < self.spans.len(); i++)
	{
		Span span = self.spans[i];
		if (span.start > off) break;
		if (span.start <= off && span.end > off) role = span.role;
	}
	return role;
}

fn void Highlighter.runs_for_line(&self, usz line_start, usz line_end, List{Span}* out)
{
	out.clear();
	if (line_end <= line_start) return;

	sz first = 0;
	while (first < self.spans.len() && (usz)self.spans[first].end <= line_start) first++;

	usz pos = line_start;
	while (pos < line_end)
	{
		SyntaxRole role = self.role_at(pos, first);
		usz next        = pos + 1;
		while (next < line_end && self.role_at(next, first) == role) next++;
		out.push({ .start = (uint)pos, .end = (uint)next, .role = role });
		pos = next;
	}
}