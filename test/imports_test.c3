module yun::imports @test;

import std::collections::list;
import std::collections::map;
import std::io;
import std::io::path;
import std::math;
import raylib6::rl;
import tree_sitter;
import yun::language;

fn void test_extract_c3_module_and_imports()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(tree_sitter::ts_parser_set_language(parser, language::grammar_language(language::Language.C3)));

	TSQuery* import_query = make_query(language::Language.C3, language::import_query_text(language::Language.C3));
	TSQuery* module_query = make_query(language::Language.C3, language::module_query_text(language::Language.C3));
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
	assert(tree_sitter::ts_parser_set_language(parser, language::grammar_language(language::Language.C3)));

	TSQuery* import_query = make_query(language::Language.C3, language::import_query_text(language::Language.C3));
	TSQuery* module_query = make_query(language::Language.C3, language::module_query_text(language::Language.C3));
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
		ImportContext ctx;
		context_build(&ctx, tmem, "/proj");
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
			&ctx,
			&paths,
			files[0:1],
			tmem,
			"/proj/src/card.c3",
			"yun::highlight",
			"",
			false,
			&targets
		);
		assert(ok);
		assert(targets.len() == 1);
		assert(targets[0].compare_to("/proj/src/highlight.c3") == 0);

		List{String} miss;
		miss.init(tmem);
		assert(!resolve_import(&ctx, &paths, files[0:1], tmem, "/proj/src/card.c3", "std::io::file", "", false, &miss));
		assert(miss.len() == 0);
		paths.free();
	};
}

fn void test_resolve_c3_multiple_files_skips_tests()
{
	@pool()
	{
		ImportContext ctx;
		context_build(&ctx, tmem, "/proj");
		HashMap{String, int} paths;
		paths.init(tmem);
		CardImports[3] files;
		files[0] = { .path = (Path)"/proj/src/text/history.c3", .module_name = "yun::text" };
		files[1] = { .path = (Path)"/proj/test/text_test.c3", .module_name = "yun::text", .is_test = true };
		files[2] = { .path = (Path)"/proj/src/text/piece_table.c3", .module_name = "yun::text" };

		List{String} targets;
		targets.init(tmem);
		bool ok = resolve_import(&ctx, &paths, files[0:3], tmem, "/proj/src/main.c3", "yun::text", "", false, &targets);
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
		ImportContext ctx;
		context_build(&ctx, tmem, "/proj");
		HashMap{String, int} paths;
		paths.init(tmem);
		paths.set("/proj/src/util.c3", 0);
		CardImports[1] files;

		List{String} targets;
		targets.init(tmem);
		bool ok = resolve_import(&ctx, &paths, files[0:1], tmem, "/proj/src/main.c3", "util", "", false, &targets);
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
		ImportContext ctx;
		context_build(&ctx, tmem, "/proj");
		HashMap{String, int} paths;
		paths.init(tmem);
		CardImports[1] files;

		List{String} targets;
		targets.init(tmem);
		assert(!resolve_import(&ctx, &paths, files[0:1], tmem, "/proj/a.c", "stdio.h", "include", true, &targets));
		assert(targets.len() == 0);
		paths.free();
	};
}

fn void test_point_segment_distance()
{
	RLVector2 a = { 0.0f, 0.0f };
	RLVector2 b = { 10.0f, 0.0f };
	assert(math::is_approx(point_segment_distance({ 5.0f, 3.0f }, a, b), 3.0f, 0.001f));
	assert(math::is_approx(point_segment_distance({ -4.0f, 0.0f }, a, b), 4.0f, 0.001f));
	assert(math::is_approx(point_segment_distance({ 14.0f, 0.0f }, a, b), 4.0f, 0.001f));
	assert(math::is_approx(point_segment_distance({ 3.0f, 4.0f }, a, a), 5.0f, 0.001f));
}

fn void test_bezier_min_distance()
{
	RLVector2 p1 = { 0.0f, 0.0f };
	RLVector2 p2 = { 100.0f, 0.0f };
	RLVector2 c2;
	RLVector2 c3;
	bezier_controls(p1, p2, &c2, &c3);

	RLVector2 mid = rl::get_spline_point_bezier_cubic(p1, c2, c3, p2, 0.5f);
	assert(bezier_min_distance(mid, p1, c2, c3, p2, 20) < 1.0f);
	assert(bezier_min_distance({ 50.0f, 500.0f }, p1, c2, c3, p2, 20) > 100.0f);
}

fn void test_edit_debounce_elapsed()
{
	ImportSettings saved = settings();
	ImportSettings s     = saved;
	s.rescan_debounce = 0.25f;
	set_settings(s);
	assert(!edit_debounce_elapsed(10.0, 10.0));
	assert(!edit_debounce_elapsed(10.0, 10.2));
	assert(edit_debounce_elapsed(10.0, 10.25));
	assert(edit_debounce_elapsed(10.0, 11.0));

	s.rescan_debounce = 0.0f;
	set_settings(s);
	assert(edit_debounce_elapsed(10.0, 10.0));
	set_settings(saved);
}

fn void test_settings_clamps()
{
	ImportSettings saved = settings();
	ImportSettings s     = saved;
	s.line_thickness = -1.0f;
	s.hover_thickness = -2.0f;
	s.arrowhead_size = -3.0f;
	s.hit_tolerance = -4.0f;
	s.rescan_debounce = -1.0f;
	s.scan_workers = 99;
	set_settings(s);
	ImportSettings got = settings();
	assert(got.line_thickness >= 0.0f);
	assert(got.hover_thickness >= 0.0f);
	assert(got.arrowhead_size >= 0.0f);
	assert(got.hit_tolerance >= 0.0f);
	assert(got.rescan_debounce >= 0.0f);
	assert(got.scan_workers <= MAX_SCAN_WORKERS);
	set_settings(saved);
}

fn void test_resolve_scan_workers()
{
	ImportSettings saved = settings();
	ImportSettings s     = saved;
	s.scan_workers = 0;
	set_settings(s);
	assert(resolve_scan_workers() >= 1);
	assert(resolve_scan_workers() <= MAX_SCAN_WORKERS);

	s.scan_workers = 3;
	set_settings(s);
	assert(resolve_scan_workers() == 3);
	set_settings(saved);
}

fn void test_hit_test_disabled_gate()
{
	ImportSettings saved = settings();
	ImportSettings s     = saved;
	s.enabled = false;
	set_settings(s);
	ImportIndex index;
	RLCamera2D camera = { };
	assert(!index.hit_test(null, camera, { 0.0f, 0.0f }));
	set_settings(saved);
}

fn void test_all_import_queries_compile()
{
	for (int i = 1; i < language::LANGUAGE_COUNT; i++)
	{
		String text = language::import_query_text((language::Language)i);
		if (text.len == 0) continue;
		TSQuery* q = import_query_for((language::Language)i);
		assert(q != null);
	}
}

fn void test_all_module_queries_compile()
{
	for (int i = 1; i < language::LANGUAGE_COUNT; i++)
	{
		String text = language::module_query_text((language::Language)i);
		if (text.len == 0) continue;
		assert(module_query_for((language::Language)i) != null);
	}
}

struct FixtureCase
{
	language::Language lang;
	String dir;
	String source;
	String specifier;
	String target;
}

fn void test_fixture_resolution()
{
	FixtureCase[] cases = {
		{
			.lang = language::Language.C3,
			.dir = "c3",
			.source = "main.c3",
			.specifier = "app::util",
			.target = "app/util.c3"
		},
		{
			.lang = language::Language.GO,
			.dir = "go",
			.source = "main.go",
			.specifier = "example.com/demo/pkg/util",
			.target = "pkg/util/util.go"
		},
		{
			.lang = language::Language.RUST,
			.dir = "rust",
			.source = "src/main.rs",
			.specifier = "crate::bar::Baz",
			.target = "src/bar.rs"
		},
		{
			.lang = language::Language.RUST,
			.dir = "rust",
			.source = "src/main.rs",
			.specifier = "foo",
			.target = "src/foo.rs"
		},
		{
			.lang = language::Language.ZIG,
			.dir = "zig",
			.source = "main.zig",
			.specifier = "foo.zig",
			.target = "foo.zig"
		},
		{
			.lang = language::Language.ODIN,
			.dir = "odin",
			.source = "main.odin",
			.specifier = "util",
			.target = "util/util.odin"
		},
		{
			.lang = language::Language.V,
			.dir = "v",
			.source = "main.v",
			.specifier = "my.util",
			.target = "my/util/util.v"
		},
		{
			.lang = language::Language.NIM,
			.dir = "nim",
			.source = "main.nim",
			.specifier = "util",
			.target = "util.nim"
		},
		{
			.lang = language::Language.CPP,
			.dir = "cpp",
			.source = "main.cpp",
			.specifier = "util.h",
			.target = "include/util.h"
		},
		{
			.lang = language::Language.JAVA,
			.dir = "java",
			.source = "src/main/java/com/example/App.java",
			.specifier = "com.example.util.Util",
			.target = "src/main/java/com/example/util/Util.java"
		},
		{
			.lang = language::Language.KOTLIN,
			.dir = "kotlin",
			.source = "src/main/kotlin/com/example/App.kt",
			.specifier = "com.example.util.Util",
			.target = "src/main/kotlin/com/example/util/Util.kt"
		},
		{
			.lang = language::Language.SCALA,
			.dir = "scala",
			.source = "src/main/scala/com/example/App.scala",
			.specifier = "import com.example.util.Util",
			.target = "src/main/scala/com/example/util/Util.scala"
		},
		{
			.lang = language::Language.C_SHARP,
			.dir = "csharp",
			.source = "App.cs",
			.specifier = "Demo.Util",
			.target = "Demo/Util.cs"
		},
		{
			.lang = language::Language.TYPESCRIPT,
			.dir = "typescript",
			.source = "src/index.ts",
			.specifier = "@lib/a",
			.target = "src/lib/a.ts"
		},
		{
			.lang = language::Language.TYPESCRIPT,
			.dir = "typescript",
			.source = "src/index.ts",
			.specifier = "./b",
			.target = "src/b.ts"
		},
		{
			.lang = language::Language.CSS,
			.dir = "css",
			.source = "style.css",
			.specifier = "base.css",
			.target = "base.css"
		},
		{
			.lang = language::Language.HTML,
			.dir = "html",
			.source = "index.html",
			.specifier = "app.js",
			.target = "app.js"
		},
		{
			.lang = language::Language.LUA,
			.dir = "lua",
			.source = "main.lua",
			.specifier = "util",
			.target = "util.lua"
		},
		{
			.lang = language::Language.PHP,
			.dir = "php",
			.source = "src/App.php",
			.specifier = "App\\Util\\Helper",
			.target = "src/Util/Helper.php"
		},
		{
			.lang = language::Language.RUBY,
			.dir = "ruby",
			.source = "app.rb",
			.specifier = "lib/util",
			.target = "lib/util.rb"
		},
		{ .lang = language::Language.R, .dir = "r", .source = "main.R", .specifier = "util.R", .target = "util.R" },
		{
			.lang = language::Language.JULIA,
			.dir = "julia",
			.source = "main.jl",
			.specifier = "util.jl",
			.target = "util.jl"
		},
		{
			.lang = language::Language.HASKELL,
			.dir = "haskell",
			.source = "src/Main.hs",
			.specifier = "Foo.Bar",
			.target = "src/Foo/Bar.hs"
		},
		{
			.lang = language::Language.GLEAM,
			.dir = "gleam",
			.source = "src/app.gleam",
			.specifier = "my/mod",
			.target = "src/my/mod.gleam"
		},
		{
			.lang = language::Language.ERLANG,
			.dir = "erlang",
			.source = "src/app.erl",
			.specifier = "app.hrl",
			.target = "include/app.hrl"
		},
		{
			.lang = language::Language.ELIXIR,
			.dir = "elixir",
			.source = "lib/app.ex",
			.specifier = "Demo.Util",
			.target = "lib/demo/util.ex"
		},
		{
			.lang = language::Language.DART,
			.dir = "dart",
			.source = "lib/main.dart",
			.specifier = "src/util.dart",
			.target = "lib/src/util.dart"
		},
		{
			.lang = language::Language.DART,
			.dir = "dart",
			.source = "lib/main.dart",
			.specifier = "package:demo/src/util.dart",
			.target = "lib/src/util.dart"
		},
	};

	for (usz i = 0; i < cases.len; i++)
	{
		FixtureCase c = cases[i];
		@pool()
		{
			String root = string::format(tmem, "fixtures/imports/%s", c.dir);
			ImportContext ctx;
			context_build(&ctx, tmem, root);

			HashMap{String, int} paths;
			paths.init(tmem);
			RLFilePathList fl = rl::load_directory_files_ex(root.zstr_tcopy(), "".zstr_tcopy(), true);
			for (uint f = 0; f < fl.count; f++)
			{
				paths.set(fl.paths[f].str_view().copy(tmem), (int)f);
			}

			char[]? data = file::load(tmem, string::format(tmem, "%s/%s", root, c.source));
			if (catch excuse = data) continue;
			String text = (String)data;

			List{ImportRef} refs;
			refs.init(tmem);
			String module_name = "";
			bool is_test       = false;
			extract_imports(
				tmem,
				import_parser_for(c.lang),
				import_query_for(c.lang),
				module_query_for(c.lang),
				text,
				&refs,
				&module_name,
				&is_test
			);

			bool matched = false;
			for (sz r = 0; r < refs.len(); r++)
			{
				if (refs[r].specifier.compare_to(c.specifier) != 0) continue;
				CardImports[1] files;
				List{String} targets;
				targets.init(tmem);
				bool ok = resolve_import(
					&ctx,
					&paths,
					files[0:0],
					tmem,
					string::format(tmem, "%s/%s", root, c.source),
					refs[r].specifier,
					refs[r].kind,
					refs[r].angled,
					&targets
				);
				String want = string::format(tmem, "%s/%s", root, c.target);
				bool found  = false;
				for (sz t = 0; t < targets.len(); t++)
				{
					if (targets[t].compare_to(want) == 0) found = true;
				}
				if (!ok || !found)
				{
					io::eprintfn(
						"fixture %s: %s -> %s failed (ok=%b found=%b targets=%d)",
						c.dir,
						c.specifier,
						c.target,
						ok,
						found,
						targets.len()
					);
				}
				assert(ok && found);
				matched = true;
				break;
			}
			if (!matched) io::eprintfn("fixture %s: specifier not extracted: %s", c.dir, c.specifier);
			assert(matched);
		};
	}
}