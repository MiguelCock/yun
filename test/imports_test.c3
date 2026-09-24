module yun::imports @test;

import std::collections::list;
import std::collections::map;
import std::io::path;
import tree_sitter;
import tree_sitter_c3;
import yun::highlight;

fn void test_extract_c3_module_and_imports()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(tree_sitter::ts_parser_set_language(parser, tree_sitter_c3::tree_sitter_c3()));

	TSQuery* import_query = make_query(highlight::Language.C3, import_query_text(highlight::Language.C3));
	TSQuery* module_query = make_query(highlight::Language.C3, module_query_text(highlight::Language.C3));
	assert(import_query != null);
	assert(module_query != null);
	defer tree_sitter::ts_query_delete(import_query);
	defer tree_sitter::ts_query_delete(module_query);

	String source = "module yun::demo;\nimport yun::highlight;\nimport std::io::file;\n";
	List{ImportRef} refs;
	refs.init(mem);
	String module_name = "";
	bool is_test       = false;
	extract_imports(mem, parser, import_query, module_query, source, &refs, &module_name, &is_test);

	assert(module_name.compare_to("yun::demo") == 0);
	assert(!is_test);
	assert(refs.len() == 2);
	assert(refs[0].specifier.compare_to("yun::highlight") == 0);
	assert(refs[1].specifier.compare_to("std::io::file") == 0);

	for (sz i = 0; i < refs.len(); i++)
	{
		refs.get_ref(i).specifier.free(mem);
	}
	refs.free();
	module_name.free(mem);
}

fn void test_extract_c3_test_module()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(tree_sitter::ts_parser_set_language(parser, tree_sitter_c3::tree_sitter_c3()));

	TSQuery* import_query = make_query(highlight::Language.C3, import_query_text(highlight::Language.C3));
	TSQuery* module_query = make_query(highlight::Language.C3, module_query_text(highlight::Language.C3));
	defer tree_sitter::ts_query_delete(import_query);
	defer tree_sitter::ts_query_delete(module_query);

	String source = "module yun::canvas @test;\nimport yun::text;\n";
	List{ImportRef} refs;
	refs.init(mem);
	String module_name = "";
	bool is_test       = false;
	extract_imports(mem, parser, import_query, module_query, source, &refs, &module_name, &is_test);

	assert(module_name.compare_to("yun::canvas") == 0);
	assert(is_test);

	for (sz i = 0; i < refs.len(); i++)
	{
		refs.get_ref(i).specifier.free(mem);
	}
	refs.free();
	module_name.free(mem);
}

fn void test_module_rel_converts_separators()
{
	@pool()
	{
		assert(module_rel(tmem, "yun::text").compare_to("yun/text") == 0);
		assert(module_rel(tmem, "a::b::c").compare_to("a/b/c") == 0);
		assert(module_rel(tmem, "plain").compare_to("plain") == 0);
	};
}

fn void test_strip_quotes_variants()
{
	assert(strip_quotes("\"x\"").compare_to("x") == 0);
	assert(strip_quotes("'y'").compare_to("y") == 0);
	assert(strip_quotes("`z`").compare_to("z") == 0);
	assert(strip_quotes("bare").compare_to("bare") == 0);
}

fn void test_is_angled()
{
	assert(is_angled("<stdio.h>"));
	assert(!is_angled("\"stdio.h\""));
}

fn void test_resolve_c3_by_module_name()
{
	@pool()
	{
		HashMap{String, int} paths;
		paths.init(tmem);
		CardImports[1] files;
		files[0] = {
			.path = (Path)"/proj/src/highlight.c3",
			.module_name = "yun::highlight",
			.is_test = false,
		};

		List{String} targets;
		targets.init(tmem);
		bool ok = resolve_import(
			&paths,
			files[0:1],
			tmem,
			"/proj",
			"/proj/src/card.c3",
			"yun::highlight",
			false,
			&targets
		);
		assert(ok);
		assert(targets.len() == 1);
		assert(targets[0].compare_to("/proj/src/highlight.c3") == 0);

		List{String} miss;
		miss.init(tmem);
		assert(!resolve_import(&paths, files[0:1], tmem, "/proj", "/proj/src/card.c3", "std::io::file", false, &miss));
		assert(miss.len() == 0);
		paths.free();
	};
}

fn void test_resolve_c3_multiple_files_skips_tests()
{
	@pool()
	{
		HashMap{String, int} paths;
		paths.init(tmem);
		CardImports[3] files;
		files[0] = { .path = (Path)"/proj/src/text/history.c3", .module_name = "yun::text" };
		files[1] = { .path = (Path)"/proj/test/text_test.c3", .module_name = "yun::text", .is_test = true };
		files[2] = { .path = (Path)"/proj/src/text/piece_table.c3", .module_name = "yun::text" };

		List{String} targets;
		targets.init(tmem);
		bool ok = resolve_import(&paths, files[0:3], tmem, "/proj", "/proj/src/main.c3", "yun::text", false, &targets);
		assert(ok);
		assert(targets.len() == 2);
		assert(targets[0].compare_to("/proj/src/text/history.c3") == 0);
		assert(targets[1].compare_to("/proj/src/text/piece_table.c3") == 0);
		paths.free();
	};
}

fn void test_resolve_c3_path_fallback()
{
	@pool()
	{
		HashMap{String, int} paths;
		paths.init(tmem);
		paths.set("/proj/src/util.c3", 0);
		CardImports[1] files;

		List{String} targets;
		targets.init(tmem);
		bool ok = resolve_import(&paths, files[0:1], tmem, "/proj/src", "/proj/src/main.c3", "util", false, &targets);
		assert(ok);
		assert(targets.len() == 1);
		assert(targets[0].compare_to("/proj/src/util.c3") == 0);
		paths.free();
	};
}

fn void test_resolve_c_include_external_is_angled()
{
	@pool()
	{
		HashMap{String, int} paths;
		paths.init(tmem);
		CardImports[1] files;

		List{String} targets;
		targets.init(tmem);
		assert(!resolve_import(&paths, files[0:1], tmem, "/proj", "/proj/a.c", "stdio.h", true, &targets));
		assert(targets.len() == 0);
		paths.free();
	};
}