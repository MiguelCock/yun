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
	assert(tree_sitter::TS_MIN_COMPATIBLE_LANGUAGE_VERSION <= tree_sitter::TS_LANGUAGE_VERSION);
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