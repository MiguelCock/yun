module yun::connection_details;

import std::collections::list;
import std::core::mem::alloc;
import std::io::file;
import yun::card;
import yun::project;
import yun::symbols;

const int MAX_SYMBOLS       = 32;
const int MAX_USAGES        = 20;
const int MAX_SCAN_BYTES    = 4u * 1024u * 1024u;
const int MAX_CLAUSE_NAMES  = 64;
const int PREVIEW_MAX       = 120;
const int MAX_ALIAS_SEGMENT = 160;

struct ClauseName
{
	String name;
	String local_name;
}

struct DetailUsage
{
	usz line;
	usz column;
	String preview;
}

struct DetailSymbol
{
	String name;
	String alias_name;
	String kind;
	usz line;
	usz column;
	bool has_target;
	List{DetailUsage} usages;
}

struct Details
{
	List{DetailSymbol} symbols;
	int total_usages;
	bool named;
	bool external;
	bool indexed;
}

fn bool is_ident_start(char c)
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_' || c == '$' || (c & 0x80) != 0;
}

fn bool is_ident_char(char c)
{
	return is_ident_start(c) || (c >= '0' && c <= '9');
}

fn char lower_ascii(char c)
{
	return c >= 'A' && c <= 'Z' ? (char)(c + 32) : c;
}

fn bool equals_ignore_case(String a, String b)
{
	if (a.len != b.len) return false;
	for (usz i = 0; i < a.len; i++)
	{
		if (lower_ascii(a[i]) != lower_ascii(b[i])) return false;
	}
	return true;
}

fn String trim_view(String text)
{
	usz start = 0;
	while (start < text.len
		&& (text[start] == ' ' || text[start] == '\t' || text[start] == '\r' || text[start] == '\n')) start++;
	usz end = text.len;
	while (end > start
		&& (text[end - 1] == ' ' || text[end - 1] == '\t' || text[end - 1] == '\r' || text[end - 1] == '\n')) end--;
	return text[start:end - start];
}

fn String ext_of(String path)
{
	usz cut = path.len;
	while (cut > 0)
	{
		cut--;
		if (path[cut] == '/' || path[cut] == '\\') return "";
		if (path[cut] == '.') return path[cut + 1:path.len - cut - 1];
	}
	return "";
}

fn bool ext_is(String path, String a, String b)
{
	String ext = ext_of(path);
	return equals_ignore_case(ext, a) || (b.len > 0 && equals_ignore_case(ext, b));
}

fn bool is_keyword(String token)
{
	String[] words = {
		"as", "from", "import", "use", "using", "static", "type", "pub", "self", "super", "crate",
		"extern", "default", "require", "export", "module", "package", "include", "fn", "let", "mut",
		"ref", "in", "of", "new", "class", "struct", "enum", "interface", "const", "var", "void", "int",
		"bool", "char", "float", "double", "string", "return", "true", "false", "null", "nil", "and",
		"not", "operator", "template", "typename", "where", "impl", "trait", "mod"
	};
	for (usz i = 0; i < words.len; i++)
	{
		if (token.compare_to(words[i]) == 0) return true;
	}
	return false;
}

fn String kind_label(symbols::SymbolKind kind)
{
	switch (kind)
	{
		case symbols::SymbolKind.FUNCTION:
			return "fn";
		case symbols::SymbolKind.METHOD:
			return "method";
		case symbols::SymbolKind.CLASS:
			return "class";
		case symbols::SymbolKind.TYPE:
			return "type";
		case symbols::SymbolKind.ENUM:
			return "enum";
		case symbols::SymbolKind.CONST:
			return "const";
		case symbols::SymbolKind.VARIABLE:
			return "var";
	}
}

fn void ClauseName.destroy(&self, Allocator allocator)
{
	if (self.name.len) self.name.free(allocator);
	if (self.local_name.len) self.local_name.free(allocator);
}

fn bool ClauseName.matches(&self, String symbol)
{
	return self.name.compare_to(symbol) == 0;
}

fn void DetailUsage.destroy(&self, Allocator allocator)
{
	if (self.preview.len) self.preview.free(allocator);
}

fn void DetailSymbol.destroy(&self, Allocator allocator)
{
	if (self.name.len) self.name.free(allocator);
	if (self.alias_name.len) self.alias_name.free(allocator);
	if (self.kind.len) self.kind.free(allocator);
	for (sz i = 0; i < self.usages.len(); i++) self.usages.get_ref(i).destroy(allocator);
	self.usages.free();
}

fn void Details.clear(&self, Allocator allocator)
{
	for (sz i = 0; i < self.symbols.len(); i++) self.symbols.get_ref(i).destroy(allocator);
	self.symbols.clear();
	self.total_usages = 0;
	self.named = false;
	self.external = false;
	self.indexed = false;
}

fn void Details.init(&self, Allocator allocator)
{
	self.symbols.init(allocator);
	self.total_usages = 0;
	self.named = false;
	self.external = false;
	self.indexed = false;
}

fn void Details.destroy(&self, Allocator allocator)
{
	self.clear(allocator);
	self.symbols.free();
}

fn String line_text(String source, usz line, Allocator allocator)
{
	usz current = 0;
	usz start   = 0;
	for (usz i = 0; i <= source.len; i++)
	{
		if (i == source.len || source[i] == '\n')
		{
			if (current == line)
			{
				usz end = i;
				if (end > start && source[end - 1] == '\r') end--;
				return source[start:end - start].copy(allocator);
			}
			current++;
			start = i + 1;
		}
	}
	return "";
}

fn bool contains_identifier(String line, String name)
{
	if (name.len == 0) return false;
	for (usz i = 0; i < line.len; i++)
	{
		if (line[i] != name[0]) continue;
		if (i > 0 && is_ident_char(line[i - 1])) continue;
		if (i + name.len > line.len) continue;
		if (line[i:name.len].compare_to(name) != 0) continue;
		if (i + name.len < line.len && is_ident_char(line[i + name.len])) continue;
		return true;
	}
	return false;
}

fn usz find_word(String text, String word, usz from)
{
	if (word.len == 0) return text.len;
	for (usz i = from; i + word.len <= text.len; i++)
	{
		if (i > 0 && is_ident_char(text[i - 1])) continue;
		if (text[i:word.len].compare_to(word) != 0) continue;
		if (i + word.len < text.len && is_ident_char(text[i + word.len])) continue;
		return i;
	}
	return text.len;
}

fn String first_identifier(String text, usz* offset)
{
	usz i = *offset;
	while (i < text.len && !is_ident_start(text[i])) i++;
	usz start = i;
	while (i < text.len && is_ident_char(text[i])) i++;
	*offset = i;
	if (i == start) return "";
	return text[start:i - start];
}

fn String last_identifier(String text)
{
	String result = "";
	usz i         = 0;
	while (i < text.len)
	{
		if (!is_ident_start(text[i]))
		{
			i++;
			continue;
		}
		usz start = i;
		while (i < text.len && is_ident_char(text[i])) i++;
		result = text[start:i - start];
	}
	return result;
}

fn void clause_push(Allocator allocator, List{ClauseName}* out, String name, String local_name)
{
	if (name.len == 0 || name.compare_to("*") == 0) return;
	if (is_keyword(name)) return;
	for (sz i = 0; i < out.len(); i++)
	{
		ClauseName existing = out.get(i);
		if (existing.name.compare_to(name) == 0) return;
	}
	ClauseName entry;
	entry.name = name.copy(allocator);
	entry.local_name = local_name.len > 0 && local_name.compare_to(name) != 0 ? local_name.copy(allocator) : "";
	out.push(entry);
}

fn void parse_segment(Allocator allocator, List{ClauseName}* out, String segment, bool assignment_form)
{
	String text = trim_view(segment);
	if (text.len == 0 || text.len > MAX_ALIAS_SEGMENT) return;
	usz semicolon = text.len;
	for (usz i = 0; i < text.len; i++)
	{
		if (text[i] == ';')
		{
			semicolon = i;
			break;
		}
	}
	text = trim_view(text[0:semicolon]);

	String name       = "";
	String local_name = "";

	usz as_pos = find_word(text, "as", 0);
	usz arrow  = text.len;
	for (usz i = 0; i + 2 <= text.len; i++)
	{
		if (text[i] == '=' && text[i + 1] == '>')
		{
			arrow = i;
			break;
		}
	}
	usz eq = text.len;
	for (usz i = 0; i < text.len; i++)
	{
		if (text[i] == '=')
		{
			eq = i;
			break;
		}
	}

	if (as_pos < text.len)
	{
		name = last_identifier(text[0:as_pos]);
		usz at = as_pos + 2;
		local_name = first_identifier(text, &at);
	}
	else if (arrow < text.len)
	{
		name = last_identifier(text[0:arrow]);
		usz at = arrow + 2;
		local_name = first_identifier(text, &at);
	}
	else if (assignment_form && eq < text.len)
	{
		usz at = 0;
		local_name = first_identifier(text, &at);
		name = last_identifier(text[eq + 1:text.len - eq - 1]);
	}
	else
	{
		name = last_identifier(text);
	}
	clause_push(allocator, out, name, local_name);
}

fn void split_segments(Allocator allocator, List{ClauseName}* out, String text, bool assignment_form)
{
	usz start = 0;
	for (usz i = 0; i <= text.len; i++)
	{
		if (i == text.len || text[i] == ',')
		{
			parse_segment(allocator, out, text[start:i - start], assignment_form);
			start = i + 1;
		}
	}
}

fn void parse_braces(Allocator allocator, List{ClauseName}* out, String text)
{
	usz open = text.len;
	for (usz i = 0; i < text.len; i++)
	{
		if (text[i] == '{')
		{
			open = i;
			break;
		}
	}
	if (open == text.len) return;
	usz close = text.len;
	for (usz i = open + 1; i < text.len; i++)
	{
		if (text[i] == '}')
		{
			close = i;
			break;
		}
	}
	if (close == text.len) return;
	split_segments(allocator, out, text[open + 1:close - open - 1], false);
}

fn void parse_from_clause(Allocator allocator, List{ClauseName}* out, String text)
{
	usz at = find_word(text, "from", 0);
	if (at == text.len) return;
	usz import_at = find_word(text, "import", at + 4);
	if (import_at == text.len) return;
	String rest = trim_view(text[import_at + 6:text.len - import_at - 6]);
	if (rest.len > 0 && rest[0] == '(')
	{
		rest = rest[1:rest.len - 1];
		usz close = rest.len;
		for (usz i = 0; i < rest.len; i++)
		{
			if (rest[i] == ')')
			{
				close = i;
				break;
			}
		}
		rest = rest[0:close];
	}
	split_segments(allocator, out, rest, false);
}

fn void parse_import_default(Allocator allocator, List{ClauseName}* out, List{ClauseName}* aliases, String text)
{
	if (!text.starts_with("import")) return;
	usz from = find_word(text, "from", 0);
	if (from == text.len) return;
	String head = trim_view(text[7:from - 7]);
	if (head.len == 0) return;
	usz brace = head.len;
	for (usz i = 0; i < head.len; i++)
	{
		if (head[i] == '{' || head[i] == ',')
		{
			brace = i;
			break;
		}
	}
	head = trim_view(head[0:brace]);
	if (head.len == 0) return;
	if (head[0] == '*')
	{
		usz as_pos = find_word(head, "as", 0);
		if (as_pos < head.len)
		{
			usz at         = as_pos + 2;
			String ns_name = first_identifier(head, &at);
			clause_push(allocator, aliases, ns_name, "");
		}
		return;
	}
	usz at      = 0;
	String name = first_identifier(head, &at);
	if (name.len == 0) return;
	if (name.compare_to("type") == 0)
	{
		name = first_identifier(head, &at);
	}
	clause_push(allocator, out, name, "");
}

fn void parse_python_module_alias(Allocator allocator, List{ClauseName}* aliases, String text)
{
	if (!text.starts_with("import")) return;
	usz from = find_word(text, "from", 0);
	if (from < text.len) return;
	String rest = trim_view(text[6:text.len - 6]);
	usz as_pos  = find_word(rest, "as", 0);
	if (as_pos == rest.len) return;
	usz at         = as_pos + 2;
	String ns_name = first_identifier(rest, &at);
	clause_push(allocator, aliases, ns_name, "");
}

fn void parse_go_module_alias(Allocator allocator, List{ClauseName}* aliases, String text)
{
	if (!text.starts_with("import")) return;
	String rest = trim_view(text[6:text.len - 6]);
	usz quote   = rest.len;
	for (usz i = 0; i < rest.len; i++)
	{
		if (rest[i] == '"' || rest[i] == '`')
		{
			quote = i;
			break;
		}
	}
	if (quote == rest.len) return;
	String head = trim_view(rest[0:quote]);
	if (head.len == 0) return;
	usz at         = 0;
	String ns_name = first_identifier(head, &at);
	if (ns_name.len == 0 || ns_name.compare_to("_") == 0 || ns_name.compare_to(".") == 0) return;
	clause_push(allocator, aliases, ns_name, "");
}

fn void parse_rust_clause(Allocator allocator, List{ClauseName}* out, String text)
{
	usz use_pos = find_word(text, "use", 0);
	if (use_pos == text.len) return;
	String rest = trim_view(text[use_pos + 3:text.len - use_pos - 3]);
	if (rest.len == 0 || rest[0] == '{') return;
	for (usz i = 0; i < rest.len; i++)
	{
		if (rest[i] == '*') return;
	}
	if (contains_identifier(rest, "self") && !contains_identifier(rest, "{")) return;
	parse_segment(allocator, out, rest, false);
}

fn void parse_dotted_clause(Allocator allocator, List{ClauseName}* out, String text, bool assignment_form)
{
	if (assignment_form)
	{
		parse_segment(allocator, out, text, true);
		return;
	}
	usz at      = find_word(text, "as", 0);
	String head = at < text.len ? text[0:at] : text;
	String name = last_identifier(head);
	if (name.len == 0 || name.compare_to("_") == 0) return;
	String local_name = "";
	if (at < text.len)
	{
		usz offset = at + 2;
		local_name = first_identifier(text, &offset);
	}
	clause_push(allocator, out, name, local_name);
}

fn void extract_clause_names(
	Allocator allocator,
	String import_text,
	String source_path,
	List{ClauseName}* out,
	List{ClauseName}* aliases
)
{
	String text = trim_view(import_text);
	if (text.len == 0) return;
	if (text.starts_with("#include") || text.starts_with("require") || text.starts_with("//")) return;

	parse_braces(allocator, out, text);

	String ext = ext_of(source_path);
	if (equals_ignore_case(ext, "py") || equals_ignore_case(ext, "pyi"))
	{
		if (find_word(text, "from", 0) < text.len)
		{
			parse_from_clause(allocator, out, text);
		}
		else
		{
			parse_python_module_alias(allocator, aliases, text);
		}
		return;
	}
	if (equals_ignore_case(ext, "go"))
	{
		parse_go_module_alias(allocator, aliases, text);
		return;
	}
	if (equals_ignore_case(ext, "rs"))
	{
		if (out.len() == 0) parse_rust_clause(allocator, out, text);
		return;
	}
	if (equals_ignore_case(
		ext,
		"java"
	) || equals_ignore_case(ext, "kt") || equals_ignore_case(ext, "kts") || equals_ignore_case(ext, "scala"))
	{
		if (out.len() == 0 && text.starts_with("import"))
		{
			parse_dotted_clause(allocator, out, text[6:text.len - 6], false);
		}
		return;
	}
	if (equals_ignore_case(ext, "cs"))
	{
		if (text.starts_with("using"))
		{
			if (out.len() == 0 && !text.starts_with("using static"))
			{
				parse_dotted_clause(allocator, out, text[5:text.len - 5], true);
			}
		}
		return;
	}
	if (equals_ignore_case(
		ext,
		"js"
	) || equals_ignore_case(
		ext,
		"jsx"
	) || equals_ignore_case(
		ext,
		"ts"
	) || equals_ignore_case(ext, "tsx") || equals_ignore_case(ext, "mjs") || equals_ignore_case(ext, "cjs"))
	{
		if (out.len() < MAX_CLAUSE_NAMES) parse_import_default(allocator, out, aliases, text);
		return;
	}

	if (text.starts_with("import") && find_word(text, "from", 0) < text.len)
	{
		parse_import_default(allocator, out, aliases, text);
	}
}

fn String preview_at(String source, usz start, Allocator allocator)
{
	usz line_start = start;
	while (line_start > 0 && source[line_start - 1] != '\n') line_start--;
	usz line_end = start;
	while (line_end < source.len && source[line_end] != '\n') line_end++;
	usz length = line_end - line_start;
	if (length > PREVIEW_MAX)
	{
		length = PREVIEW_MAX;
		while (length > 0 && ((int)source[line_start + length] & 0xC0) == 0x80) length--;
	}
	String text = source[line_start:length];
	while (text.len > 0 && (text[0] == ' ' || text[0] == '\t')) text = text[1:text.len - 1];
	return text.copy(allocator);
}

fn void scan_usages(Allocator allocator, String source, String local, usz import_line, List{DetailUsage}* out)
{
	if (local.len == 0 || source.len == 0) return;
	usz limit = source.len > MAX_SCAN_BYTES ? MAX_SCAN_BYTES : source.len;
	usz line  = 0;
	usz col   = 0;
	for (usz i = 0; i < limit && out.len() < MAX_USAGES;)
	{
		char c = source[i];
		if (c == '\n')
		{
			line++;
			col = 0;
			i++;
			continue;
		}
		if (!is_ident_start(c))
		{
			col++;
			i++;
			continue;
		}
		usz start     = i;
		usz token_col = col;
		while (i < limit && is_ident_char(source[i]))
		{
			i++;
			col++;
		}
		if (line == import_line) continue;
		if (i - start != local.len || source[start:i - start].compare_to(local) != 0) continue;
		out.push(
			{
				.line = line,
				.column = token_col,
				.preview = preview_at(source, start, allocator),
			}
		);
	}
}

fn String load_source(Allocator allocator, project::Project* project, String path, char[]* storage)
{
	int card = project.find_card(path);
	if (card >= 0 && project.cards[card].buffer)
	{
		usz length = project.cards[card].buffer.length();
		if (length > MAX_SCAN_BYTES) length = MAX_SCAN_BYTES;
		*storage = project.cards[card].buffer.slice(0, length, allocator);
		return (String)(*storage);
	}
	File? opened = file::open(path, "r");
	if (catch err = opened) return "";
	File handle = opened;
	*storage = alloc::new_array(allocator, char, MAX_SCAN_BYTES);
	sz? read = handle.read(*storage);
	handle.close();
	if (catch err = read) return "";
	return (String)((*storage)[0:(usz)read]);
}

fn int clause_index(List{ClauseName}* names, String symbol)
{
	for (sz i = 0; i < names.len(); i++)
	{
		ClauseName entry = names.get(i);
		if (entry.matches(symbol)) return (int)i;
	}
	return -1;
}

fn bool clause_used(List{bool}* used, int index)
{
	return index >= 0 && index < (int)used.len() && used.get(index);
}

fn void Details.build(
	&self,
	Allocator allocator,
	project::Project* project,
	symbols::Symbols* index,
	String source_path,
	String target_path,
	usz import_line
)
{
	self.clear(allocator);
	if (source_path.len == 0) return;
	self.external = target_path.len == 0;

	char[] source_storage = { };
	String source         = load_source(allocator, project, source_path, &source_storage);
	if (source.len == 0)
	{
		if (source_storage.len) alloc::free(allocator, source_storage);
		return;
	}

	String import_text = line_text(source, import_line, allocator);
	List{ClauseName} names;
	List{ClauseName} aliases;
	names.init(allocator);
	aliases.init(allocator);
	extract_clause_names(allocator, import_text, source_path, &names, &aliases);
	self.named = names.len() > 0;

	symbols::CardSymbols* target = target_path.len > 0 ? index.file_for_path(target_path) : null;
	self.indexed = target != null;
	List{bool} used;
	used.init(allocator);
	for (sz i = 0; i < names.len(); i++) used.push(false);

	if (target)
	{
		for (sz i = 0; i < target.symbols.len() && self.symbols.len() < MAX_SYMBOLS; i++)
		{
			symbols::Symbol* source_symbol = &target.symbols[i];
			if (source_symbol.name.len == 0) continue;
			int match = -1;
			if (names.len() > 0)
			{
				match = clause_index(&names, source_symbol.name);
				if (match < 0) continue;
				used.set((sz)match, true);
			}

			DetailSymbol detail;
			detail.name = source_symbol.name.copy(allocator);
			detail.kind = kind_label(source_symbol.kind).copy(allocator);
			detail.line = source_symbol.line;
			detail.column = source_symbol.column;
			detail.has_target = true;
			detail.usages.init(allocator);
			if (match >= 0)
			{
				ClauseName clause = names.get(match);
				if (clause.local_name.len > 0) detail.alias_name = clause.local_name.copy(allocator);
			}
			else
			{
				detail.alias_name = "";
			}
			String local = detail.alias_name.len > 0 ? detail.alias_name : source_symbol.name;
			scan_usages(allocator, source, local, import_line, &detail.usages);
			if (names.len() == 0 && detail.usages.len() == 0)
			{
				detail.destroy(allocator);
				continue;
			}
			self.total_usages += (int)detail.usages.len();
			self.symbols.push(detail);
		}
	}

	for (sz i = 0; i < aliases.len() && self.symbols.len() < MAX_SYMBOLS; i++)
	{
		ClauseName alias_name = aliases.get(i);
		DetailSymbol detail;
		detail.name = alias_name.name.copy(allocator);
		detail.alias_name = "";
		detail.kind = "module".copy(allocator);
		detail.line = 0;
		detail.column = 0;
		detail.has_target = false;
		detail.usages.init(allocator);
		scan_usages(allocator, source, detail.name, import_line, &detail.usages);
		self.total_usages += (int)detail.usages.len();
		self.symbols.push(detail);
	}

	if (names.len() > 0)
	{
		for (sz i = 0; i < names.len() && self.symbols.len() < MAX_SYMBOLS; i++)
		{
			if (clause_used(&used, (int)i)) continue;
			ClauseName name = names.get(i);
			DetailSymbol detail;
			detail.name = name.name.copy(allocator);
			detail.alias_name = name.local_name.len > 0 ? name.local_name.copy(allocator) : "";
			detail.kind = "import".copy(allocator);
			detail.line = 0;
			detail.column = 0;
			detail.has_target = false;
			detail.usages.init(allocator);
			String local = detail.alias_name.len > 0 ? detail.alias_name : detail.name;
			scan_usages(allocator, source, local, import_line, &detail.usages);
			self.total_usages += (int)detail.usages.len();
			self.symbols.push(detail);
		}
	}

	for (sz i = 0; i < names.len(); i++) names.get_ref(i).destroy(allocator);
	for (sz i = 0; i < aliases.len(); i++) aliases.get_ref(i).destroy(allocator);
	names.free();
	aliases.free();
	used.free();
	if (import_text.len) import_text.free(allocator);
	alloc::free(allocator, source_storage);
}