module tree_sitter_smoke @test;

import std::io::file;
import tree_sitter;
import yun::language;

macro bool parses_ok(parser, lang, source)
{
	assert(tree_sitter::ts_parser_set_language(parser, lang));
	TSNode root = tree_sitter::ts_tree_root_node(
		tree_sitter::ts_parser_parse_string(parser, null, (source).ptr, (uint)(source).len)
	);
	return !tree_sitter::ts_node_has_error(root) && !tree_sitter::ts_node_is_null(root);
}

fn void test_runtime_symbols()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	assert(parser != null);
	tree_sitter::ts_parser_delete(parser);
}

fn void test_parse_c()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.C), "int main(void) { return 0; }"));
}

fn void test_parse_python()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.PYTHON), "def main():\n    return 0\n"));
}

fn void test_parse_javascript()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(
		parser,
		language::grammar_language(language::Language.JAVASCRIPT),
		"function main() { return 0; }\n"
	));
}

fn void test_parse_c3()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.C3), "fn int main() { return 0; }\n"));
}

fn void test_incomplete_input_still_usable()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(tree_sitter::ts_parser_set_language(parser, language::grammar_language(language::Language.C)));
	String broken = "int main( {";
	TSTree* tree  = tree_sitter::ts_parser_parse_string(parser, null, broken.ptr, (uint)broken.len);
	assert(tree != null);
	TSNode root = tree_sitter::ts_tree_root_node(tree);
	assert(!tree_sitter::ts_node_is_null(root));
	tree_sitter::ts_tree_delete(tree);
}

fn void test_language_abi()
{
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.C)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.PYTHON)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.JAVASCRIPT)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.C3)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.GO)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.RUST)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.ZIG)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.ODIN)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.V)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.NIM)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.CPP)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.JAVA)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.KOTLIN)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.SCALA)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.C_SHARP)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.TYPESCRIPT)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.TSX)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.CSS)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.HTML)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.LUA)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.PHP)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.RUBY)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.R)) > 0);
	assert(tree_sitter::ts_language_symbol_count(language::grammar_language(language::Language.JULIA)) > 0);
	assert(tree_sitter::TS_MIN_COMPATIBLE_LANGUAGE_VERSION <= tree_sitter::TS_LANGUAGE_VERSION);
}

fn void test_parse_go()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.GO), "package main\n\nfunc main() {}\n"));
}

fn void test_parse_rust()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.RUST), "fn main() {}\n"));
}

fn void test_parse_zig()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.ZIG), "pub fn main() void {}\n"));
}

fn void test_parse_odin()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(
		parser,
		language::grammar_language(language::Language.ODIN),
		"package main\n\nmain :: proc() {}\n"
	));
}

fn void test_parse_v()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.V), "fn main() {}\n"));
}

fn void test_parse_nim()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.NIM), "proc main() =\n  discard\n"));
}

fn void test_parse_cpp()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.CPP), "int main() { return 0; }\n"));
}

fn void test_parse_java()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(
		parser,
		language::grammar_language(language::Language.JAVA),
		"class Main { public static void main(String[] args) {} }\n"
	));
}

fn void test_parse_kotlin()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.KOTLIN), "fun main() {}\n"));
}

fn void test_parse_scala()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.SCALA), "object Main extends App {}\n"));
}

fn void test_parse_c_sharp()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(
		parser,
		language::grammar_language(language::Language.C_SHARP),
		"class Main { static void Main() {} }\n"
	));
}

fn void test_parse_typescript()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.TYPESCRIPT), "const x: number = 1;\n"));
}

fn void test_parse_tsx()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(
		parser,
		language::grammar_language(language::Language.TSX),
		"const el = <div className=\"x\">hi</div>;\n"
	));
}

fn void test_parse_css()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.CSS), "a { color: red; }\n"));
}

fn void test_parse_html()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.HTML), "<html><body>hi</body></html>\n"));
}

fn void test_parse_lua()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.LUA), "local x = 1\nprint(x)\n"));
}

fn void test_parse_php()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.PHP), "<?php echo 1; ?>\n"));
}

fn void test_parse_ruby()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.RUBY), "puts \"hi\"\n"));
}

fn void test_parse_r()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.R), "x <- 1\nprint(x)\n"));
}

fn void test_parse_julia()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, language::grammar_language(language::Language.JULIA), "function main()\n    1\nend\n"));
}

fn void test_highlights_query_loads()
{
	String[4] query_paths = {
		"lib/tree_sitter_c.c3l/queries/highlights.scm",
		"lib/tree_sitter_python.c3l/queries/highlights.scm",
		"lib/tree_sitter_javascript.c3l/queries/highlights.scm",
		"lib/tree_sitter_c3.c3l/queries/highlights.scm",
	};
	language::Language[4] langs = {
		language::Language.C,
		language::Language.PYTHON,
		language::Language.JAVASCRIPT,
		language::Language.C3,
	};
	for (int i = 0; i < 4; i++)
	{
		char[]? data = file::load(tmem, query_paths[i]);
		if (catch excuse = data) assert(false);

		uint offset        = 0;
		TSQueryError error = TS_QUERY_ERROR_NONE;
		TSQuery* q = tree_sitter::ts_query_new(
			language::grammar_language(langs[i]),
			(char*)data.ptr,
			(uint)data.len,
			&offset,
			&error
		);
		assert(q != null);
		assert(error == TS_QUERY_ERROR_NONE);
		assert(tree_sitter::ts_query_capture_count(q) > 0);
		tree_sitter::ts_query_delete(q);
	}
}