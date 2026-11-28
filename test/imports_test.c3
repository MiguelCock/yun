module yun::imports @test;

import std::collections::list;
import std::collections::map;
import std::io;
import std::io::path;
import std::math;
import raylib6::rl;
import tree_sitter;
import yun::language;
import yun::project;

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

fn void test_import_cache_roundtrip()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch err = tmp) return;
		Path? d = tmp.append(tmem, "yun_import_cache");
		if (catch err = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch err = path::mkdir(dir, recursive: true)) return;
		Path? a = dir.append(tmem, "a.c3");
		if (catch err = a) return;
		Path? b = dir.append(tmem, "b.c3");
		if (catch err = b) return;
		if (catch err = file::save(a, "module a;\nimport b;\n")) return;
		if (catch err = file::save(b, "module b;\n")) return;

		project::Project p;
		p.init(mem);
		if (p.root.len) p.root.free(mem);
		p.root = (Path)((String)dir).copy(mem);
		(void)p.append_card((String)a, { 0.0f, 0.0f });
		(void)p.append_card((String)b, { 0.0f, 0.0f });

		ImportIndex first;
		first.init(mem);
		first.refresh_card_paths(&p);
		List{ImportRef} refs;
		refs.init(mem);
		refs.push(
			{
				.specifier = "b".copy(mem),
				.target_path = ((String)b).copy(mem),
				.kind = "import".copy(mem),
				.resolved = true,
				.angled = false,
				.line = 1,
				.column = 0,
			}
		);
		first.store((String)a, &refs, "a".copy(mem), false);
		first.save_cache(&p);
		first.destroy();

		ImportIndex second;
		second.init(mem);
		second.refresh_card_paths(&p);
		assert(second.load_cache(&p));
		assert(second.files.len() == 1);
		assert(second.files[0].module_name.compare_to("a") == 0);
		assert(second.files[0].imports.len() == 1);
		assert(second.files[0].imports[0].specifier.compare_to("b") == 0);
		second.destroy();
		p.destroy();
		(void)path::rmtree(dir);
	};
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

fn void test_extract_sol_module_and_imports()
{
	TSParser* parser = tree_sitter::ts_parser_new();
	defer tree_sitter::ts_parser_delete(parser);
	assert(tree_sitter::ts_parser_set_language(parser, language::grammar_language(language::Language.SOL)));

	TSQuery* import_query = make_query(language::Language.SOL, language::import_query_text(language::Language.SOL));
	TSQuery* module_query = make_query(language::Language.SOL, language::module_query_text(language::Language.SOL));
	assert(import_query != null);
	assert(module_query != null);
	defer tree_sitter::ts_query_delete(import_query);
	defer tree_sitter::ts_query_delete(module_query);

	String source = "module app\n\nimport std::io\nimport geo::shape\n";
	List{ImportRef} refs;
	refs.init(mem);
	String module_name = "";
	bool is_test       = false;
	extract_imports(mem, parser, import_query, module_query, source, &refs, &module_name, &is_test);

	assert(module_name.compare_to("app") == 0);
	assert(!is_test);
	assert(refs.len() == 2);
	assert(refs[0].specifier.compare_to("std::io") == 0);
	assert(refs[1].specifier.compare_to("geo::shape") == 0);

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

		List{String} roots;
		roots.init(tmem);
		roots_for(tmem, ctx.root, "/proj/src/card.c3", &roots);

		List{String} targets;
		targets.init(tmem);
		bool ok = resolve_import(
			&ctx,
			roots.entries[0:roots.len()],
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
		assert(!resolve_import(
			&ctx,
			roots.entries[0:roots.len()],
			&paths,
			files[0:1],
			tmem,
			"/proj/src/card.c3",
			"std::io::file",
			"",
			false,
			&miss
		));
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

		List{String} roots;
		roots.init(tmem);
		roots_for(tmem, ctx.root, "/proj/src/main.c3", &roots);

		List{String} targets;
		targets.init(tmem);
		bool ok = resolve_import(
			&ctx,
			roots.entries[0:roots.len()],
			&paths,
			files[0:3],
			tmem,
			"/proj/src/main.c3",
			"yun::text",
			"",
			false,
			&targets
		);
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

		List{String} roots;
		roots.init(tmem);
		roots_for(tmem, ctx.root, "/proj/src/main.c3", &roots);

		List{String} targets;
		targets.init(tmem);
		bool ok = resolve_import(
			&ctx,
			roots.entries[0:roots.len()],
			&paths,
			files[0:1],
			tmem,
			"/proj/src/main.c3",
			"util",
			"",
			false,
			&targets
		);
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

		List{String} roots;
		roots.init(tmem);
		roots_for(tmem, ctx.root, "/proj/a.c", &roots);

		List{String} targets;
		targets.init(tmem);
		assert(!resolve_import(
			&ctx,
			roots.entries[0:roots.len()],
			&paths,
			files[0:1],
			tmem,
			"/proj/a.c",
			"stdio.h",
			"include",
			true,
			&targets
		));
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
	s.min_zoom = -1.0f;
	s.scan_workers = 99;
	set_settings(s);
	ImportSettings got = settings();
	assert(got.line_thickness >= 0.0f);
	assert(got.hover_thickness >= 0.0f);
	assert(got.arrowhead_size >= 0.0f);
	assert(got.hit_tolerance >= 0.0f);
	assert(got.rescan_debounce >= 0.0f);
	assert(got.min_zoom >= 0.001f);
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

fn void test_parse_arrow_style()
{
	assert(parse_arrow_style("solid") == ArrowStyle.SOLID);
	assert(parse_arrow_style("dashed") == ArrowStyle.DASHED);
	assert(parse_arrow_style("dotted") == ArrowStyle.DOTTED);
	assert(parse_arrow_style("long-dash") == ArrowStyle.LONG_DASH);
	assert(parse_arrow_style("dash-dot") == ArrowStyle.DASH_DOT);
	assert(parse_arrow_style("nope") == ArrowStyle.SOLID);
	assert(parse_arrow_style("") == ArrowStyle.SOLID);
}

fn void test_find_module_root()
{
	@pool()
	{
		String root = "fixtures/imports";
		assert(find_module_root(tmem, root, "fixtures/imports/go/main.go", language::Language.GO)
			.compare_to("fixtures/imports/go") == 0);
		assert(find_module_root(tmem, root, "fixtures/imports/rust/src/main.rs", language::Language.RUST)
			.compare_to("fixtures/imports/rust") == 0);
		assert(find_module_root(tmem, root, "fixtures/imports/typescript/src/index.ts", language::Language.TYPESCRIPT)
			.compare_to("fixtures/imports/typescript") == 0);
		assert(find_module_root(
			tmem,
			root,
			"fixtures/imports/java/src/main/java/com/example/App.java",
			language::Language.JAVA
		)
			.compare_to("fixtures/imports/java") == 0);
		// no manifest for C3 -> project root
		assert(find_module_root(tmem, root, "fixtures/imports/c3/main.c3", language::Language.C3)
			.compare_to(root) == 0);
	};
}

fn void test_roots_for_ancestors()
{
	@pool()
	{
		List{String} roots;
		roots.init(tmem);
		roots_for(tmem, "fixtures/imports", "fixtures/imports/java/src/main/java/com/example/App.java", &roots);
		bool has_file_dir = false;
		bool has_root     = false;
		bool has_java     = false;
		for (sz i = 0; i < roots.len(); i++)
		{
			if (roots[i].compare_to("fixtures/imports/java") == 0) has_file_dir = true;
			if (roots[i].compare_to("fixtures/imports") == 0) has_root = true;
			if (roots[i].compare_to("fixtures/imports/java/src/main/java") == 0) has_java = true;
		}
		assert(has_file_dir);
		assert(has_root);
		assert(has_java);
	};
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
			.lang = language::Language.SOL,
			.dir = "sol",
			.source = "src/app.sol",
			.specifier = "geo::shape",
			.target = "src/geo/shape.sol"
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
			String project_root = "fixtures/imports";
			String source       = string::format(tmem, "%s/%s/%s", project_root, c.dir, c.source);
			String module_root  = find_module_root(tmem, project_root, source, c.lang);
			ImportContext ctx;
			context_build(&ctx, tmem, module_root);
			List{String} roots;
			roots.init(tmem);
			roots_for(tmem, ctx.root, source, &roots);

			HashMap{String, int} paths;
			paths.init(tmem);
			RLFilePathList fl = rl::load_directory_files_ex(project_root.zstr_tcopy(), "".zstr_tcopy(), true);
			for (uint f = 0; f < fl.count; f++)
			{
				paths.set(fl.paths[f].str_view().copy(tmem), (int)f);
			}

			char[]? data = file::load(tmem, source);
			if (catch err = data) continue;
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
					roots.entries[0:roots.len()],
					&paths,
					files[0:0],
					tmem,
					source,
					refs[r].specifier,
					refs[r].kind,
					refs[r].angled,
					&targets
				);
				String want = string::format(tmem, "%s/%s/%s", project_root, c.dir, c.target);
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
fn void test_importers_of()
{
	@pool()
	{
		ImportIndex index;
		index.files.init(tmem);

		CardImports a;
		a.path = "/a.c3".copy(tmem);
		a.module_name = "a".copy(tmem);
		a.is_test = false;
		a.imports.init(tmem);
		a.imports.push(
			{
				.specifier = "/b.c3".copy(tmem),
				.target_path = "/b.c3".copy(tmem),
				.kind = "import".copy(tmem),
				.resolved = true,
				.line = 3,
				.column = 8,
			}
		);
		index.files.push(a);

		CardImports b;
		b.path = "/b.c3".copy(tmem);
		b.module_name = "b".copy(tmem);
		b.is_test = false;
		b.imports.init(tmem);
		b.imports.push(
			{
				.specifier = "/c.c3".copy(tmem),
				.target_path = "/c.c3".copy(tmem),
				.kind = "import".copy(tmem),
				.resolved = true,
				.line = 1,
				.column = 0,
			}
		);
		b.imports.push(
			{
				.specifier = "missing".copy(tmem),
				.target_path = "/d.c3".copy(tmem),
				.kind = "import".copy(tmem),
				.resolved = false,
				.line = 2,
				.column = 0,
			}
		);
		index.files.push(b);

		List{ImporterRef} out;
		out.init(tmem);

		index.importers_of("/b.c3", &out);
		assert(out.len() == 1);
		assert(out[0].file == 0);
		assert(out[0].ref == 0);

		index.importers_of("/c.c3", &out);
		assert(out.len() == 1);
		assert(out[0].file == 1);
		assert(out[0].ref == 0);

		index.importers_of("/d.c3", &out);
		assert(out.len() == 0);

		out.free();
	};
}
fn void test_internal_edges_are_file_to_file()
{
	@pool()
	{
		project::Project p;
		p.init(mem);
		if (p.root.len) p.root.free(mem);
		p.root = (Path)"/root".copy(mem);
		int src = p.add_folder("/root/src", project::ROOT_FOLDER);
		(void)p.add_folder("/root/src/deep", src);
		(void)p.add_folder("/root/lib", project::ROOT_FOLDER);

		int a          = p.append_card("/root/src/a.ts", { 0.0f, 0.0f });
		int b          = p.append_card("/root/src/b.ts", { 0.0f, 0.0f });
		int c          = p.append_card("/root/src/deep/c.ts", { 0.0f, 0.0f });
		int x          = p.append_card("/root/lib/x.ts", { 0.0f, 0.0f });
		int y          = p.append_card("/root/lib/y.ts", { 0.0f, 0.0f });
		int index_card = p.append_card("/root/lib/index.ts", { 0.0f, 0.0f });

		ImportIndex index;
		index.init(mem);
		index.refresh_card_paths(&p);

		List{ImportRef} refs_a;
		refs_a.init(mem);
		refs_a.push(
			{
				.specifier = "./x".copy(mem),
				.target_path = "/root/lib/x.ts".copy(mem),
				.kind = "import".copy(mem),
				.resolved = true,
				.line = 0,
			}
		);
		refs_a.push(
			{
				.specifier = "./x".copy(mem),
				.target_path = "/root/lib/x.ts".copy(mem),
				.kind = "import".copy(mem),
				.resolved = true,
				.line = 1,
			}
		);
		refs_a.push(
			{
				.specifier = "./y".copy(mem),
				.target_path = "/root/lib/y.ts".copy(mem),
				.kind = "import".copy(mem),
				.resolved = true,
				.line = 2,
			}
		);
		index.store("/root/src/a.ts", &refs_a, "", false);

		List{ImportRef} refs_b;
		refs_b.init(mem);
		refs_b.push(
			{
				.specifier = "./y".copy(mem),
				.target_path = "/root/lib/y.ts".copy(mem),
				.kind = "import".copy(mem),
				.resolved = true,
				.line = 0,
			}
		);
		refs_b.push({ .specifier = "react".copy(mem), .kind = "import".copy(mem), .line = 1 });
		index.store("/root/src/b.ts", &refs_b, "", false);

		List{ImportRef} refs_c;
		refs_c.init(mem);
		refs_c.push(
			{
				.specifier = "./components".copy(mem),
				.target_path = "/root/lib/index.ts".copy(mem),
				.kind = "import".copy(mem),
				.resolved = true,
				.line = 0,
			}
		);
		index.store("/root/src/deep/c.ts", &refs_c, "", false);

		List{ImportEdge} edges;
		edges.init(tmem);
		index.build_edges(&p, &edges);
		assert(edges.len() == 4);
		int total = 0;
		for (sz i = 0; i < edges.len(); i++)
		{
			ImportEdge edge = edges[i];
			assert(edge.target_card >= 0);
			assert(edge.target_card != edge.source_card);
			total += edge.count;
			if (edge.source_card == a && edge.target_card == x)
			{
				assert(edge.count == 2);
				assert(edge.label.compare_to("./x") == 0);
			}
			if (edge.source_card == b) assert(edge.target_card == y);
		}
		assert(total == 5);

		ImportHit hit = { .valid = true, .source = a, .ref_index = 0 };
		List{ImporterRef} group;
		group.init(tmem);
		index.collect_group(&p, hit, &group);
		assert(group.len() == 2);
		for (sz i = 0; i < group.len(); i++)
		{
			assert(group[i].file == 0);
			assert(group[i].ref < 3);
		}

		ImportEdge a_x = { .source_card = a, .target_card = x, .count = 1 };
		ImportEdge b_y = { .source_card = b, .target_card = y, .count = 1 };
		p.cards[a].rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 80.0f };
		p.cards[x].rect = { .x = 200.0f, .y = 0.0f, .width = 100.0f, .height = 80.0f };
		Rect src_visible = { .x = -10.0f, .y = -10.0f, .width = 320.0f, .height = 100.0f };
		assert(edge_visible(&p, &a_x, src_visible));
		p.folders[src].collapsed = true;
		assert(!edge_visible(&p, &a_x, src_visible));
		p.folders[src].collapsed = false;

		assert(edge_related(&a_x, a));
		assert(!edge_related(&a_x, b));
		p.cards[a].rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 80.0f };
		p.cards[b].rect = { .x = 500.0f, .y = 0.0f, .width = 100.0f, .height = 80.0f };
		p.cards[x].rect = { .x = 200.0f, .y = 0.0f, .width = 100.0f, .height = 80.0f };
		p.cards[y].rect = { .x = 700.0f, .y = 0.0f, .width = 100.0f, .height = 80.0f };
		Rect visible = { .x = -10.0f, .y = -10.0f, .width = 320.0f, .height = 100.0f };
		assert(edge_visible(&p, &a_x, visible));
		assert(!edge_visible(&p, &b_y, visible));
		(void)c;
		(void)index_card;

		edges.free();
		index.destroy();
		p.destroy();
	};
}

macro void assert_orthogonal(route)
{
	assert(route.count >= 2);
	for (int i = 1; i < route.count; i++)
	{
		RLVector2 a = route.points[(usz)i - 1];
		RLVector2 b = route.points[(usz)i];
		float dx    = math::abs(b[0] - a[0]);
		float dy    = math::abs(b[1] - a[1]);
		assert(dx < 0.01f || dy < 0.01f);
	}
}

fn void test_focus_keeps_cached_edges()
{
	@pool()
	{
		project::Project p;
		p.init(mem);
		if (p.root.len) p.root.free(mem);
		p.root = (Path)"/root".copy(mem);
		int a = p.append_card("/root/a.ts", { 0.0f, 0.0f });
		int b = p.append_card("/root/b.ts", { 100.0f, 0.0f });

		ImportIndex index;
		index.init(mem);
		index.refresh_card_paths(&p);
		List{ImportRef} refs;
		refs.init(mem);
		refs.push(
			{
				.specifier = "./b".copy(mem),
				.target_path = "/root/b.ts".copy(mem),
				.kind = "import".copy(mem),
				.resolved = true,
			}
		);
		index.store("/root/a.ts", &refs, "", false);
		index.ensure_edges(&p);
		assert(index.edges.len() == 1);
		assert(index.edges[0].source_card == a);
		assert(index.edges[0].target_card == b);

		int focused = p.focus(a);
		assert(focused == 0);
		index.ensure_edges(&p);
		assert(index.edges.len() == 1);
		assert(index.edges[0].source_card == focused);
		assert(index.edges[0].target_card == p.find_card("/root/b.ts"));

		index.destroy();
		p.destroy();
	};
}

fn void test_orthogonal_routes_make_right_angles()
{
	@pool()
	{
		project::Project p;
		p.init(mem);
		if (p.root.len) p.root.free(mem);
		p.root = (Path)"/root".copy(mem);
		int a = p.append_card("/root/a.ts", { 0.0f, 0.0f });
		int b = p.append_card("/root/b.ts", { 0.0f, 0.0f });
		p.cards[a].rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 80.0f };
		p.cards[b].rect = { .x = 300.0f, .y = 100.0f, .width = 100.0f, .height = 80.0f };

		ImportEdge edge = { .source_card = a, .target_card = b, .count = 1 };
		EdgeRoute route;
		assert(edge_route(&p, &edge, 1.0f, &route));
		assert_orthogonal(&route);
		assert(route.points[0][0] == 100.0f);
		assert(route.points[0][1] == 40.0f);
		assert(route.points[(usz)route.count - 1][0] == 300.0f);
		assert(route.points[(usz)route.count - 1][1] == 140.0f);
		assert(route_length(&route) > 290.0f);
		RLVector2 mid = route_midpoint(&route);
		assert(route_distance(&route, mid) < 0.01f);

		p.cards[b].rect = { .x = 50.0f, .y = 300.0f, .width = 100.0f, .height = 80.0f };
		assert(edge_route(&p, &edge, 1.0f, &route));
		assert_orthogonal(&route);
		assert(route.points[0][0] == 50.0f);
		assert(route.points[0][1] == 80.0f);
		assert(route.points[(usz)route.count - 1][0] == 100.0f);
		assert(route.points[(usz)route.count - 1][1] == 300.0f);

		p.cards[b].rect = { .x = 300.0f, .y = 0.0f, .width = 100.0f, .height = 80.0f };
		assert(edge_route(&p, &edge, 1.0f, &route));
		assert_orthogonal(&route);

		p.cards[b].rect = { .x = 103.0f, .y = 0.0f, .width = 100.0f, .height = 80.0f };
		assert(edge_route(&p, &edge, 1.0f, &route));
		assert_orthogonal(&route);
		assert(route.points[0][1] == 0.0f);
		assert(route.points[(usz)route.count - 1][1] == 0.0f);

		p.cards[b].rect = { .x = 20.0f, .y = 20.0f, .width = 100.0f, .height = 80.0f };
		assert(!edge_route(&p, &edge, 1.0f, &route));
		p.destroy();
	};
}
fn void test_draw_on_top_toggle()
{
	set_draw_on_top(true);
	assert(draw_on_top());
	set_draw_on_top(false);
	assert(!draw_on_top());
}
fn void test_arrow_mode_cycles_off_related_all()
{
	ImportSettings saved = settings();
	ImportSettings s     = saved;
	s.enabled = false;
	s.related_only = true;
	set_settings(s);
	assert(mode() == ArrowMode.OFF);
	cycle_mode();
	assert(mode() == ArrowMode.RELATED);
	cycle_mode();
	assert(mode() == ArrowMode.ALL);
	cycle_mode();
	assert(mode() == ArrowMode.OFF);
	set_settings(saved);
}