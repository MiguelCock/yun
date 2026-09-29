module yun::highlight;

import libc;
import raylib6::rl;
import std::collections::list;
import std::core::dstring;
import std::core::mem::alloc;
import std::io::file;
import std::io::path;
import yun::text;
import yun::theme;
import yun::language;
import tree_sitter;

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
	TITLE,
	EMPHASIS,
	STRONG,
	LITERAL,
	URI,
	REFERENCE,
	NONE,
}

struct Span
{
	uint start;
	uint end;
	SyntaxRole role;
}

struct Highlighter
{
	language::Language language;
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

TSQuery*[language::LANGUAGE_COUNT] query_cache;
bool[language::LANGUAGE_COUNT] query_loaded;

fn int span_compare(void* a, void* b)
{
	Span* sa = (Span*)a;
	Span* sb = (Span*)b;
	if (sa.start != sb.start) return sa.start < sb.start ? -1 : 1;
	if (sa.end != sb.end) return sa.end > sb.end ? -1 : 1;
	return 0;
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

fn String query_first_line(String text)
{
	usz i = 0;
	while (i < text.len && (text[i] == '\n' || text[i] == '\r' || text[i] == ' ' || text[i] == '\t')) i++;
	usz start = i;
	while (i < text.len && text[i] != '\n' && text[i] != '\r') i++;
	return text[start:i - start];
}

fn void append_query_with_inherits(Allocator allocator, DString* out, String text, int depth)
{
	if (depth > 4) return;
	String first = query_first_line(text);
	if (first.starts_with("; inherits:"))
	{
		String rest = first[11:first.len - 11];
		usz i       = 0;
		while (i < rest.len)
		{
			while (i < rest.len && (rest[i] == ' ' || rest[i] == '\t' || rest[i] == ',')) i++;
			usz start = i;
			while (i < rest.len && rest[i] != ',' && rest[i] != ' ' && rest[i] != '\t') i++;
			if (i > start)
			{
				String name = rest[start:i - start];
				String path = language::highlights_path_for_name(name);
				if (path.len > 0)
				{
					char[] parent = load_query_text(allocator, path);
					if (parent.len > 0)
					{
						append_query_with_inherits(allocator, out, (String)parent, depth + 1);
					}
				}
			}
		}
	}
	out.append_string(text);
	out.append_char('\n');
}

fn TSQuery* build_query(language::Language language)
{
	String rel = language::grammar_query_path(language);
	if (rel.len == 0) return null;
	TSLanguage* lang = language::grammar_language(language);
	if (!lang) return null;

	TSQuery* result = null;
	@pool()
	{
		char[] text = load_query_text(tmem, rel);
		if (text.len != 0)
		{
			DString combined;
			combined.init(tmem, text.len + 512);
			append_query_with_inherits(tmem, &combined, (String)text, 0);
			String query_text = combined.str_view();

			uint offset        = 0;
			TSQueryError error = TS_QUERY_ERROR_NONE;
			result = tree_sitter::ts_query_new(lang, (char*)query_text.ptr, (uint)query_text.len, &offset, &error);
			if (result && error != TS_QUERY_ERROR_NONE) result = null;
			combined.free();
		}
	};
	return result;
}

fn TSQuery* query_for(language::Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= language::LANGUAGE_COUNT) return null;
	if (query_loaded[index]) return query_cache[index];
	query_loaded[index] = true;
	query_cache[index] = build_query(language);
	return query_cache[index];
}

TSQuery*[language::LANGUAGE_COUNT] injection_cache;
bool[language::LANGUAGE_COUNT] injection_loaded;
TSParser*[language::LANGUAGE_COUNT] injection_parsers;

const int MAX_INJECTION_DEPTH = 3;

fn TSQuery* build_injection_query(language::Language language)
{
	String rel = language::injections_query_path(language);
	if (rel.len == 0) return null;
	TSLanguage* lang = language::grammar_language(language);
	if (!lang) return null;

	TSQuery* result = null;
	@pool()
	{
		char[] text = load_query_text(tmem, rel);
		if (text.len != 0)
		{
			uint offset        = 0;
			TSQueryError error = TS_QUERY_ERROR_NONE;
			result = tree_sitter::ts_query_new(lang, (char*)text.ptr, (uint)text.len, &offset, &error);
			if (result && error != TS_QUERY_ERROR_NONE) result = null;
		}
	};
	return result;
}

fn TSQuery* injection_query_for(language::Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= language::LANGUAGE_COUNT) return null;
	if (injection_loaded[index]) return injection_cache[index];
	injection_loaded[index] = true;
	injection_cache[index] = build_injection_query(language);
	return injection_cache[index];
}

fn TSParser* injection_parser_for(language::Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= language::LANGUAGE_COUNT) return null;
	if (injection_parsers[index]) return injection_parsers[index];
	TSLanguage* ts = language::grammar_language(language);
	if (!ts) return null;
	TSParser* parser = tree_sitter::ts_parser_new();
	if (!parser) return null;
	if (!tree_sitter::ts_parser_set_language(parser, ts))
	{
		tree_sitter::ts_parser_delete(parser);
		return null;
	}
	injection_parsers[index] = parser;
	return parser;
}

fn String query_capture_name(TSQuery* query, uint index)
{
	uint length = 0;
	char* name  = tree_sitter::ts_query_capture_name_for_id(query, index, &length);
	if (!name || length == 0) return "";
	return (String)name[0:length];
}

fn String query_string_value(TSQuery* query, uint index)
{
	uint length = 0;
	char* value = tree_sitter::ts_query_string_value_for_id(query, index, &length);
	if (!value || length == 0) return "";
	return (String)value[0:length];
}

fn String capture_text(TSQueryMatch* match, uint capture_id, String source)
{
	for (ushort i = 0; i < match.capture_count; i++)
	{
		TSQueryCapture capture = match.captures[i];
		if (capture.index != capture_id) continue;
		uint start = tree_sitter::ts_node_start_byte(capture.node);
		uint end   = tree_sitter::ts_node_end_byte(capture.node);
		if (end <= start || (usz)end > source.len) return "";
		return source[start:end - start];
	}
	return "";
}

fn bool eval_predicate(
	TSQuery* query,
	String name,
	TSQueryPredicateStep* steps,
	uint start,
	uint end,
	TSQueryMatch* match,
	String source
)
{
	if (name.compare_to("set!") == 0) return true;
	bool positive = name.compare_to("eq?") == 0 || name.compare_to("any-of?") == 0;
	bool negative = name.compare_to("not-eq?") == 0 || name.compare_to("not-any-of?") == 0;
	if (!positive && !negative) return false;
	if (start >= end) return false;
	if (steps[start].type != TSQueryPredicateStepType.TS_PREDICATE_STEP_TYPE_CAPTURE) return false;

	String value = capture_text(match, steps[start].value_id, source);
	bool matched = false;
	for (uint i = start + 1; i < end; i++)
	{
		String arg = "";
		if (steps[i].type == TSQueryPredicateStepType.TS_PREDICATE_STEP_TYPE_STRING)
		{
			arg = query_string_value(query, steps[i].value_id);
		}
		else if (steps[i].type == TSQueryPredicateStepType.TS_PREDICATE_STEP_TYPE_CAPTURE)
		{
			arg = capture_text(match, steps[i].value_id, source);
		}
		if (arg.len > 0 && value.compare_to(arg) == 0)
		{
			matched = true;
			break;
		}
	}
	return positive ? matched : !matched;
}

fn bool eval_predicates(TSQuery* query, TSQueryMatch* match, String source)
{
	uint step_count             = 0;
	TSQueryPredicateStep* steps = tree_sitter::ts_query_predicates_for_pattern(query, match.pattern_index, &step_count);
	if (!steps || step_count == 0) return true;

	uint i = 0;
	while (i < step_count)
	{
		if (steps[i].type != TSQueryPredicateStepType.TS_PREDICATE_STEP_TYPE_STRING)
		{
			i++;
			continue;
		}
		String name = query_string_value(query, steps[i].value_id);
		i++;
		uint args_start = i;
		while (i < step_count && steps[i].type != TSQueryPredicateStepType.TS_PREDICATE_STEP_TYPE_DONE) i++;
		if (!eval_predicate(query, name, steps, args_start, i, match, source)) return false;
		if (i < step_count) i++;
	}
	return true;
}

struct InjectionProps
{
	bool combined;
	bool dynamic_language;
	uint language_capture;
	language::Language language;
}

fn InjectionProps injection_props(TSQuery* query, TSQueryMatch* match)
{
	InjectionProps props;
	uint step_count             = 0;
	TSQueryPredicateStep* steps = tree_sitter::ts_query_predicates_for_pattern(query, match.pattern_index, &step_count);
	uint i                      = 0;
	while (i < step_count)
	{
		if (steps[i].type != TSQueryPredicateStepType.TS_PREDICATE_STEP_TYPE_STRING)
		{
			i++;
			continue;
		}
		String name = query_string_value(query, steps[i].value_id);
		i++;
		uint args_start = i;
		while (i < step_count && steps[i].type != TSQueryPredicateStepType.TS_PREDICATE_STEP_TYPE_DONE) i++;
		if (name.compare_to(
			"set!"
		) == 0 && args_start < i && steps[args_start].type == TSQueryPredicateStepType.TS_PREDICATE_STEP_TYPE_STRING)
		{
			String key = query_string_value(query, steps[args_start].value_id);
			if (key.compare_to("injection.language") == 0 && args_start + 1 < i)
			{
				if (steps[args_start + 1].type == TSQueryPredicateStepType.TS_PREDICATE_STEP_TYPE_STRING)
				{
					props.language = language::language_for_name(
						query_string_value(query, steps[args_start + 1].value_id)
					);
				}
				else if (steps[args_start + 1].type == TSQueryPredicateStepType.TS_PREDICATE_STEP_TYPE_CAPTURE)
				{
					props.dynamic_language = true;
					props.language_capture = steps[args_start + 1].value_id;
				}
			}
			else if (key.compare_to("injection.combined") == 0)
			{
				props.combined = true;
			}
		}
		if (i < step_count) i++;
	}
	return props;
}

struct InjectionSegment
{
	uint combined_start;
	uint combined_end;
	uint original_start;
}

fn void collect_highlights(TSQuery* query, TSNode root, String source, uint base_offset, List{Span}* out)
{
	if (!query) return;
	TSQueryCursor* cursor = tree_sitter::ts_query_cursor_new();
	if (!cursor) return;
	tree_sitter::ts_query_cursor_exec(cursor, query, root);

	TSQueryMatch match;
	while (tree_sitter::ts_query_cursor_next_match(cursor, &match))
	{
		for (ushort i = 0; i < match.capture_count; i++)
		{
			TSQueryCapture capture = match.captures[i];
			SyntaxRole role        = role_for_capture(query, capture.index);
			if (role == SyntaxRole.NONE) continue;
			uint start = tree_sitter::ts_node_start_byte(capture.node) + base_offset;
			uint end   = tree_sitter::ts_node_end_byte(capture.node) + base_offset;
			if (end <= start) continue;
			out.push({ .start = start, .end = end, .role = role });
		}
	}
	tree_sitter::ts_query_cursor_delete(cursor);
}

fn void collect_spans(
	Allocator allocator,
	language::Language language,
	TSTree* tree,
	String source,
	uint base_offset,
	List{Span}* out,
	int depth
)
{
	TSNode root = tree_sitter::ts_tree_root_node(tree);
	collect_highlights(query_for(language), root, source, base_offset, out);

	if (depth >= MAX_INJECTION_DEPTH) return;
	TSQuery* injections = injection_query_for(language);
	if (!injections) return;

	TSQueryCursor* cursor = tree_sitter::ts_query_cursor_new();
	if (!cursor) return;
	tree_sitter::ts_query_cursor_exec(cursor, injections, root);

	List{TSNode}[language::LANGUAGE_COUNT] combined_nodes;
	bool[language::LANGUAGE_COUNT] combined_used;
	bool any_combined = false;

	TSQueryMatch match;
	while (tree_sitter::ts_query_cursor_next_match(cursor, &match))
	{
		if (!eval_predicates(injections, &match, source)) continue;

		InjectionProps props = injection_props(injections, &match);

		bool dynamic          = props.dynamic_language;
		uint language_capture = props.language_capture;
		if (!dynamic)
		{
			for (ushort i = 0; i < match.capture_count; i++)
			{
				TSQueryCapture capture = match.captures[i];
				if (query_capture_name(injections, capture.index).compare_to("injection.language") == 0)
				{
					dynamic = true;
					language_capture = capture.index;
					break;
				}
			}
		}

		language::Language target = props.language;
		if (dynamic)
		{
			target = language::language_for_name(capture_text(&match, language_capture, source));
		}
		if (target == language::Language.NONE) continue;

		List{TSNode} content;
		content.init(allocator);
		for (ushort i = 0; i < match.capture_count; i++)
		{
			TSQueryCapture capture = match.captures[i];
			if (query_capture_name(injections, capture.index).compare_to("injection.content") == 0)
			{
				content.push(capture.node);
			}
		}
		if (content.len() == 0)
		{
			content.free();
			continue;
		}

		if (props.combined)
		{
			int target_index = (int)target;
			if (!combined_used[target_index])
			{
				combined_nodes[target_index].init(allocator);
				combined_used[target_index] = true;
			}
			foreach (TSNode node : content)
			{
				combined_nodes[target_index].push(node);
			}
			any_combined = true;
			content.free();
			continue;
		}

		TSParser* parser = injection_parser_for(target);
		if (parser)
		{
			foreach (TSNode node : content)
			{
				uint start = tree_sitter::ts_node_start_byte(node);
				uint end   = tree_sitter::ts_node_end_byte(node);
				if (end <= start || (usz)end > source.len) continue;
				TSTree* child = tree_sitter::ts_parser_parse_string(
					parser,
					null,
					(char*)source.ptr + start,
					end - start
				);
				if (child)
				{
					collect_spans(
						allocator,
						target,
						child,
						source[start:end - start],
						base_offset + start,
						out,
						depth + 1
					);
					tree_sitter::ts_tree_delete(child);
				}
			}
		}
		content.free();
	}
	tree_sitter::ts_query_cursor_delete(cursor);

	if (!any_combined) return;
	for (int i = 1; i < language::LANGUAGE_COUNT; i++)
	{
		if (!combined_used[i]) continue;
		List{TSNode}* nodes = &combined_nodes[i];

		DString combined;
		combined.init(allocator, 256);
		List{InjectionSegment} segments;
		segments.init(allocator);
		for (sz k = 0; k < nodes.len(); k++)
		{
			TSNode node = (*nodes)[(usz)k];
			uint start  = tree_sitter::ts_node_start_byte(node);
			uint end    = tree_sitter::ts_node_end_byte(node);
			if (end <= start || (usz)end > source.len) continue;
			uint combined_start = (uint)combined.len();
			combined.append_string(source[start:end - start]);
			combined.append_char('\n');
			segments.push(
				{ .combined_start = combined_start, .combined_end = (uint)combined.len() - 1, .original_start = start }
			);
		}

		String combined_text = combined.str_view();
		TSParser* parser     = injection_parser_for((language::Language)i);
		if (parser && combined_text.len > 0)
		{
			TSTree* child = tree_sitter::ts_parser_parse_string(
				parser,
				null,
				(char*)combined_text.ptr,
				(uint)combined_text.len
			);
			if (child)
			{
				List{Span} child_spans;
				child_spans.init(allocator);
				collect_spans(allocator, (language::Language)i, child, combined_text, 0, &child_spans, depth + 1);
				foreach (Span span : child_spans)
				{
					foreach (InjectionSegment segment : segments)
					{
						uint start = span.start > segment.combined_start ? span.start : segment.combined_start;
						uint end   = span.end < segment.combined_end ? span.end : segment.combined_end;
						if (end > start)
						{
							out.push(
								{
									.start = segment.original_start + (start - segment.combined_start),
									.end = segment.original_start + (end - segment.combined_start),
									.role = span.role,
								}
							);
						}
					}
				}
				child_spans.free();
				tree_sitter::ts_tree_delete(child);
			}
		}
		combined.free();
		segments.free();
		nodes.free();
	}
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
	if (name.starts_with("text.title")) return SyntaxRole.TITLE;
	if (name.starts_with("text.literal")) return SyntaxRole.LITERAL;
	if (name.starts_with("text.uri")) return SyntaxRole.URI;
	if (name.starts_with("text.reference")) return SyntaxRole.REFERENCE;
	if (name.starts_with("text.strong")) return SyntaxRole.STRONG;
	if (name.starts_with("text.emphasis")) return SyntaxRole.EMPHASIS;
	return SyntaxRole.NONE;
}

fn SyntaxRole role_for_capture(TSQuery* query, uint index)
{
	String name = query_capture_name(query, index);
	if (name.len == 0) return SyntaxRole.NONE;
	return role_for_name(name);
}

fn RLColor role_color(SyntaxRole role)
{
	Theme* t = theme::current();
	switch (role)
	{
		case SyntaxRole.KEYWORD:
			return t.syn_keyword;
		case SyntaxRole.STRING:
			return t.syn_string;
		case SyntaxRole.COMMENT:
			return t.syn_comment;
		case SyntaxRole.NUMBER:
			return t.syn_number;
		case SyntaxRole.TYPE:
			return t.syn_type;
		case SyntaxRole.FUNCTION:
			return t.syn_function;
		case SyntaxRole.CONSTANT:
			return t.syn_constant;
		case SyntaxRole.OPERATOR:
			return t.syn_operator;
		case SyntaxRole.PUNCTUATION:
			return t.syn_punctuation;
		case SyntaxRole.ATTRIBUTE:
			return t.syn_attribute;
		case SyntaxRole.MODULE:
			return t.syn_module;
		case SyntaxRole.LABEL:
			return t.syn_label;
		case SyntaxRole.BOOLEAN:
			return t.syn_boolean;
		case SyntaxRole.CHARACTER:
			return t.syn_character;
		case SyntaxRole.ESCAPE:
			return t.syn_escape;
		case SyntaxRole.PARAMETER:
			return t.syn_parameter;
		case SyntaxRole.PROPERTY:
			return t.syn_property;
		case SyntaxRole.BUILTIN:
			return t.syn_builtin;
		case SyntaxRole.TITLE:
			return t.syn_keyword;
		case SyntaxRole.EMPHASIS:
			return t.syn_attribute;
		case SyntaxRole.STRONG:
			return t.syn_type;
		case SyntaxRole.LITERAL:
			return t.syn_string;
		case SyntaxRole.URI:
			return t.syn_module;
		case SyntaxRole.REFERENCE:
			return t.syn_function;
		case SyntaxRole.VARIABLE:
			return t.editor_text;
		case SyntaxRole.TEXT:
			return t.editor_text;
		case SyntaxRole.NONE:
			return t.editor_text;
	}
}

fn Highlighter* create(Allocator allocator, PieceTable* table, String path)
{
	language::Language language = language::language_for_path(path);
	if (language == language::Language.NONE) return null;

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
	if (!tree_sitter::ts_parser_set_language(highlighter.parser, language::grammar_language(language)))
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

fn void shutdown()
{
	for (int i = 0; i < language::LANGUAGE_COUNT; i++)
	{
		if (query_cache[i])
		{
			tree_sitter::ts_query_delete(query_cache[i]);
			query_cache[i] = null;
		}
		if (injection_cache[i])
		{
			tree_sitter::ts_query_delete(injection_cache[i]);
			injection_cache[i] = null;
		}
		if (injection_parsers[i])
		{
			tree_sitter::ts_parser_delete(injection_parsers[i]);
			injection_parsers[i] = null;
		}
		query_loaded[i] = false;
		injection_loaded[i] = false;
	}
}

fn void Highlighter.mark_dirty(&self)
{
	self.dirty = true;
}

fn void Highlighter.rebuild_spans(&self)
{
	self.spans.clear();
	if (!self.has_tree || !self.query) return;

	collect_spans(self.allocator, self.language, self.tree, self.source, 0, &self.spans, 0);

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