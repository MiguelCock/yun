module tree_sitter_smoke @test;

import std::io::file;
import tree_sitter;
import tree_sitter_c;
import tree_sitter_c3;
import tree_sitter_javascript;
import tree_sitter_python;

macro bool parses_ok(parser, language, source)
{
	assert(tree_sitter::ts_parser_set_language(parser, language));
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
	assert(parses_ok(parser, tree_sitter_c::tree_sitter_c(), "int main(void) { return 0; }"));
}

fn void test_parse_python()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, tree_sitter_python::tree_sitter_python(), "def main():\n    return 0\n"));
}

fn void test_parse_javascript()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, tree_sitter_javascript::tree_sitter_javascript(), "function main() { return 0; }\n"));
}

fn void test_parse_c3()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(parses_ok(parser, tree_sitter_c3::tree_sitter_c3(), "fn int main() { return 0; }\n"));
}

fn void test_incomplete_input_still_usable()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(tree_sitter::ts_parser_set_language(parser, tree_sitter_c::tree_sitter_c()));
	String broken = "int main( {";
	TSTree* tree  = tree_sitter::ts_parser_parse_string(parser, null, broken.ptr, (uint)broken.len);
	assert(tree != null);
	TSNode root = tree_sitter::ts_tree_root_node(tree);
	assert(!tree_sitter::ts_node_is_null(root));
	tree_sitter::ts_tree_delete(tree);
}

fn void test_language_abi()
{
	assert(tree_sitter::ts_language_symbol_count(tree_sitter_c::tree_sitter_c()) > 0);
	assert(tree_sitter::ts_language_symbol_count(tree_sitter_python::tree_sitter_python()) > 0);
	assert(tree_sitter::ts_language_symbol_count(tree_sitter_javascript::tree_sitter_javascript()) > 0);
	assert(tree_sitter::ts_language_symbol_count(tree_sitter_c3::tree_sitter_c3()) > 0);
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
	TSLanguage*[4] languages = {
		tree_sitter_c::tree_sitter_c(),
		tree_sitter_python::tree_sitter_python(),
		tree_sitter_javascript::tree_sitter_javascript(),
		tree_sitter_c3::tree_sitter_c3(),
	};
	for (int i = 0; i < 4; i++)
	{
		char[]? data = file::load(tmem, query_paths[i]);
		if (catch excuse = data) assert(false);

		uint offset        = 0;
		TSQueryError error = TS_QUERY_ERROR_NONE;
		TSQuery* q         = tree_sitter::ts_query_new(languages[i], (char*)data.ptr, (uint)data.len, &offset, &error);
		assert(q != null);
		assert(error == TS_QUERY_ERROR_NONE);
		assert(tree_sitter::ts_query_capture_count(q) > 0);
		tree_sitter::ts_query_delete(q);
	}
}