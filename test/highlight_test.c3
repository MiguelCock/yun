module yun::highlight @test;

import libc;
import std::collections::list;
import yun::language;
import yun::text;

macro bool runs_have_role(highlighter, table, line, want)
{
	usz l = (usz)line;
	List{Span} runs;
	runs.init(tmem);
	usz start = (table).line_start(l);
	usz end   = l + 1 < (table).line_count() ? (table).line_start(l + 1) : (table).length();
	(highlighter).runs_for_line(start, end, &runs);
	bool found = false;
	foreach (Span run : runs)
	{
		if (run.role == want) found = true;
	}
	runs.free();
	return found;
}

fn void test_language_for_path()
{
	assert(language::language_for_path("src/main.c3") == language::Language.C3);
	assert(language::language_for_path("lib/foo.c3i") == language::Language.C3);
	assert(language::language_for_path("src/main.c") == language::Language.C);
	assert(language::language_for_path("include/foo.h") == language::Language.C);
	assert(language::language_for_path("script.py") == language::Language.PYTHON);
	assert(language::language_for_path("app.js") == language::Language.JAVASCRIPT);
	assert(language::language_for_path("app.mjs") == language::Language.JAVASCRIPT);
	assert(language::language_for_path("main.go") == language::Language.GO);
	assert(language::language_for_path("lib.rs") == language::Language.RUST);
	assert(language::language_for_path("build.zig") == language::Language.ZIG);
	assert(language::language_for_path("build.zon") == language::Language.ZIG);
	assert(language::language_for_path("main.odin") == language::Language.ODIN);
	assert(language::language_for_path("main.v") == language::Language.V);
	assert(language::language_for_path("main.nim") == language::Language.NIM);
	assert(language::language_for_path("main.nims") == language::Language.NIM);
	assert(language::language_for_path("main.cpp") == language::Language.CPP);
	assert(language::language_for_path("main.cc") == language::Language.CPP);
	assert(language::language_for_path("main.cxx") == language::Language.CPP);
	assert(language::language_for_path("main.hpp") == language::Language.CPP);
	assert(language::language_for_path("main.hxx") == language::Language.CPP);
	assert(language::language_for_path("Main.java") == language::Language.JAVA);
	assert(language::language_for_path("Main.kt") == language::Language.KOTLIN);
	assert(language::language_for_path("build.gradle.kts") == language::Language.KOTLIN);
	assert(language::language_for_path("Main.scala") == language::Language.SCALA);
	assert(language::language_for_path("build.sc") == language::Language.SCALA);
	assert(language::language_for_path("build.sbt") == language::Language.SCALA);
	assert(language::language_for_path("Program.cs") == language::Language.C_SHARP);
	assert(language::language_for_path("app.ts") == language::Language.TYPESCRIPT);
	assert(language::language_for_path("app.mts") == language::Language.TYPESCRIPT);
	assert(language::language_for_path("app.cts") == language::Language.TYPESCRIPT);
	assert(language::language_for_path("app.tsx") == language::Language.TSX);
	assert(language::language_for_path("app.jsx") == language::Language.JAVASCRIPT);
	assert(language::language_for_path("style.css") == language::Language.CSS);
	assert(language::language_for_path("index.html") == language::Language.HTML);
	assert(language::language_for_path("index.htm") == language::Language.HTML);
	assert(language::language_for_path("init.lua") == language::Language.LUA);
	assert(language::language_for_path("index.php") == language::Language.PHP);
	assert(language::language_for_path("app.rb") == language::Language.RUBY);
	assert(language::language_for_path("analysis.r") == language::Language.R);
	assert(language::language_for_path("analysis.R") == language::Language.R);
	assert(language::language_for_path("main.jl") == language::Language.JULIA);
	assert(language::language_for_path("Main.hs") == language::Language.HASKELL);
	assert(language::language_for_path("app.gleam") == language::Language.GLEAM);
	assert(language::language_for_path("server.erl") == language::Language.ERLANG);
	assert(language::language_for_path("server.hrl") == language::Language.ERLANG);
	assert(language::language_for_path("lib.ex") == language::Language.ELIXIR);
	assert(language::language_for_path("test.exs") == language::Language.ELIXIR);
	assert(language::language_for_path("main.dart") == language::Language.DART);
	assert(language::language_for_path("README.md") == language::Language.MARKDOWN);
	assert(language::language_for_path("doc.markdown") == language::Language.MARKDOWN);
	assert(language::language_for_path("notes.txt") == language::Language.NONE);
	assert(language::language_for_path("Makefile") == language::Language.NONE);
	assert(language::language_for_path("dir.with.dots/file") == language::Language.NONE);
}

fn void test_role_for_name()
{
	assert(role_for_name("keyword") == SyntaxRole.KEYWORD);
	assert(role_for_name("keyword.function") == SyntaxRole.KEYWORD);
	assert(role_for_name("string") == SyntaxRole.STRING);
	assert(role_for_name("string.escape") == SyntaxRole.ESCAPE);
	assert(role_for_name("comment") == SyntaxRole.COMMENT);
	assert(role_for_name("comment.documentation") == SyntaxRole.COMMENT);
	assert(role_for_name("number") == SyntaxRole.NUMBER);
	assert(role_for_name("type.builtin") == SyntaxRole.TYPE);
	assert(role_for_name("type") == SyntaxRole.TYPE);
	assert(role_for_name("function.call") == SyntaxRole.FUNCTION);
	assert(role_for_name("variable.parameter") == SyntaxRole.PARAMETER);
	assert(role_for_name("variable.member") == SyntaxRole.PROPERTY);
	assert(role_for_name("variable") == SyntaxRole.VARIABLE);
	assert(role_for_name("property") == SyntaxRole.PROPERTY);
	assert(role_for_name("operator") == SyntaxRole.OPERATOR);
	assert(role_for_name("punctuation.bracket") == SyntaxRole.PUNCTUATION);
	assert(role_for_name("spell") == SyntaxRole.NONE);
	assert(role_for_name("local.definition") == SyntaxRole.NONE);
}

fn void test_runs_cover_line_and_inner_wins()
{
	Highlighter highlighter;
	highlighter.spans.init(tmem);
	highlighter.run_cursor = 0;
	highlighter.last_line_start = 0;
	highlighter.spans.push({ .start = 0, .end = 5, .role = SyntaxRole.KEYWORD });
	highlighter.spans.push({ .start = 2, .end = 3, .role = SyntaxRole.NUMBER });

	List{Span} runs;
	runs.init(tmem);
	highlighter.runs_for_line(0, 5, &runs);

	assert(runs.len() == 3);
	assert(runs[0].start == 0 && runs[0].end == 2 && runs[0].role == SyntaxRole.KEYWORD);
	assert(runs[1].start == 2 && runs[1].end == 3 && runs[1].role == SyntaxRole.NUMBER);
	assert(runs[2].start == 3 && runs[2].end == 5 && runs[2].role == SyntaxRole.KEYWORD);

	usz covered = 0;
	foreach (Span run : runs)
	{
		covered += (usz)(run.end - run.start);
	}
	assert(covered == 5);

	runs.free();
	highlighter.spans.free();
}

fn void test_runs_clip_to_line()
{
	Highlighter highlighter;
	highlighter.spans.init(tmem);
	highlighter.run_cursor = 0;
	highlighter.last_line_start = 0;
	highlighter.spans.push({ .start = 3, .end = 20, .role = SyntaxRole.STRING });

	List{Span} runs;
	runs.init(tmem);
	highlighter.runs_for_line(5, 10, &runs);

	assert(runs.len() == 1);
	assert(runs[0].start == 5 && runs[0].end == 10 && runs[0].role == SyntaxRole.STRING);

	runs.free();
	highlighter.spans.free();
}

fn void test_parse_highlights_c3()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "// note\nfn int main() { return 0; }\n");

		Highlighter* highlighter = create(tmem, &table, "sample.c3");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.COMMENT));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.KEYWORD));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.TYPE));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.NUMBER));

		destroy(highlighter, tmem);
	};
}

fn void test_parse_highlights_c()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "int main(void) { return 1; } // done\n");

		Highlighter* highlighter = create(tmem, &table, "sample.c");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.TYPE));
		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.NUMBER));
		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.COMMENT));

		destroy(highlighter, tmem);
	};
}

fn void test_parse_highlights_python()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "def main():\n    return \"hi\"\n");

		Highlighter* highlighter = create(tmem, &table, "sample.py");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.KEYWORD));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.STRING));

		destroy(highlighter, tmem);
	};
}

fn void test_parse_highlights_javascript()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "function main() { return 42; }\n");

		Highlighter* highlighter = create(tmem, &table, "sample.js");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.KEYWORD));
		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.NUMBER));

		destroy(highlighter, tmem);
	};
}

fn void test_unknown_extension_is_plain()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "plain text\n");
		assert(create(tmem, &table, "notes.txt") == null);
	};
}

fn void test_mark_dirty_reparses()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "int x = 1;\n");

		Highlighter* highlighter = create(tmem, &table, "sample.c");
		assert(highlighter != null);
		highlighter.ensure_parsed();
		assert(!runs_have_role(highlighter, &table, 0, SyntaxRole.COMMENT));

		(void)table.insert(0, "// added\n");
		highlighter.mark_dirty();
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.COMMENT));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.TYPE));

		destroy(highlighter, tmem);
	};
}

fn void test_registry_is_well_formed()
{
	assert(language::LANGUAGES.len == (usz)language::LANGUAGE_COUNT);
	assert(language::LANGUAGES[0].lib.len == 0);
	for (int i = 1; i < language::LANGUAGE_COUNT; i++)
	{
		language::LanguageSpec spec = language::LANGUAGES[i];
		assert(spec.name.len > 0);
		assert(spec.lib.len > 0);
		assert(spec.symbol.len > 0);
		assert(spec.highlights_path.len > 0);
		if (spec.extensions.len > 0)
		{
			assert(language::language_for_path(spec.extensions[0]) == (language::Language)i);
		}
		assert(language::grammar_language((language::Language)i) != null);
	}
}

fn void test_highlights_path_for_name()
{
	assert(language::highlights_path_for_name("c").compare_to("lib/tree_sitter_c.c3l/queries/highlights.scm") == 0);
	assert(language::highlights_path_for_name("nope").len == 0);
}

fn void test_all_highlight_queries_compile()
{
	for (int i = 1; i < language::LANGUAGE_COUNT; i++)
	{
		assert(query_for((language::Language)i) != null);
	}
}

fn void test_language_for_name()
{
	assert(language::language_for_name("javascript") == language::Language.JAVASCRIPT);
	assert(language::language_for_name("JS") == language::Language.JAVASCRIPT);
	assert(language::language_for_name("  HTML \n") == language::Language.HTML);
	assert(language::language_for_name("ts") == language::Language.TYPESCRIPT);
	assert(language::language_for_name("c++") == language::Language.CPP);
	assert(language::language_for_name("csharp") == language::Language.C_SHARP);
	assert(language::language_for_name("c-sharp") == language::Language.C_SHARP);
	assert(language::language_for_name("rs") == language::Language.RUST);
	assert(language::language_for_name("hs") == language::Language.HASKELL);
	assert(language::language_for_name("erl") == language::Language.ERLANG);
	assert(language::language_for_name("ex") == language::Language.ELIXIR);
	assert(language::language_for_name("exs") == language::Language.ELIXIR);
	assert(language::language_for_name("md") == language::Language.MARKDOWN);
	assert(language::language_for_name("markdown") == language::Language.MARKDOWN);
	assert(language::language_for_name("markdown_inline") == language::Language.MARKDOWN_INLINE);
	assert(language::language_for_name("sql") == language::Language.NONE);
	assert(language::language_for_name("comment") == language::Language.NONE);
	assert(language::language_for_name("") == language::Language.NONE);
}

fn void test_all_injection_queries_compile()
{
	for (int i = 1; i < language::LANGUAGE_COUNT; i++)
	{
		String path = language::injections_query_path((language::Language)i);
		if (path.len == 0) continue;
		assert(injection_query_for((language::Language)i) != null);
	}
}

fn void test_php_injects_html()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "<?php echo 1; ?>\n<div class=\"x\">hi</div>\n");

		Highlighter* highlighter = create(tmem, &table, "index.php");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.TYPE));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.ATTRIBUTE));

		destroy(highlighter, tmem);
	};
}

fn void test_php_injects_html_across_blocks()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(
			tmem,
			"<!DOCTYPE html>\n<html>\n<body>\n\n<h1>My First PHP Page</h1>\n\n<?php\necho \"Hello World!\";\n?>\n\n<div></div>\n\n</body>\n</html>\n"
		);

		Highlighter* highlighter = create(tmem, &table, "index.php");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 4, SyntaxRole.TYPE));
		assert(runs_have_role(highlighter, &table, 10, SyntaxRole.TYPE));
		assert(runs_have_role(highlighter, &table, 12, SyntaxRole.TYPE));
		assert(runs_have_role(highlighter, &table, 13, SyntaxRole.TYPE));

		destroy(highlighter, tmem);
	};
}

fn void test_html_injects_script_and_style()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "<script>let x = 1;</script>\n<style>.a { color: red; }</style>\n");

		Highlighter* highlighter = create(tmem, &table, "index.html");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.KEYWORD));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.PROPERTY));

		destroy(highlighter, tmem);
	};
}

fn void test_cpp_raw_string_injects_html()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "auto s = R\"html(<div></div>)html\";\n");

		Highlighter* highlighter = create(tmem, &table, "sample.cpp");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.TYPE));

		destroy(highlighter, tmem);
	};
}

fn void test_javascript_tagged_template_combined()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "const x = html`<div>${y}</div>`;\n");

		Highlighter* highlighter = create(tmem, &table, "sample.js");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.TYPE));

		destroy(highlighter, tmem);
	};
}

fn void test_lua_cdef_predicate_guard()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "cdef([[int x;]])\n");

		Highlighter* highlighter = create(tmem, &table, "sample.lua");
		assert(highlighter != null);
		highlighter.ensure_parsed();
		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.TYPE));
		destroy(highlighter, tmem);
	};
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "foo([[int x;]])\n");

		Highlighter* highlighter = create(tmem, &table, "sample.lua");
		assert(highlighter != null);
		highlighter.ensure_parsed();
		assert(!runs_have_role(highlighter, &table, 0, SyntaxRole.TYPE));
		destroy(highlighter, tmem);
	};
}

fn void test_cpp_inherits_c_highlights()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "// note\nint x = 42;\n");

		Highlighter* highlighter = create(tmem, &table, "sample.cpp");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.COMMENT));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.NUMBER));

		destroy(highlighter, tmem);
	};
}

fn void test_parse_highlights_v()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "fn main() {\n\tprintln(\"hi\")\n}\n");

		Highlighter* highlighter = create(tmem, &table, "sample.v");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.KEYWORD));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.STRING));

		destroy(highlighter, tmem);
	};
}

fn void test_parse_highlights_typescript()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "const x = \"hi\";\n");

		Highlighter* highlighter = create(tmem, &table, "sample.ts");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.KEYWORD));
		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.STRING));

		destroy(highlighter, tmem);
	};
}

fn void test_parse_highlights_tsx()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "const el = <div>hi</div>;\n");

		Highlighter* highlighter = create(tmem, &table, "sample.tsx");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.KEYWORD));
		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.TYPE));

		destroy(highlighter, tmem);
	};
}

fn void test_parse_highlights_haskell()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "-- Quicksort implementation\nx = 42\ns = \"hi\"\n");

		Highlighter* highlighter = create(tmem, &table, "Main.hs");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.COMMENT));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.NUMBER));
		assert(runs_have_role(highlighter, &table, 2, SyntaxRole.STRING));

		destroy(highlighter, tmem);
	};
}

fn void test_parse_highlights_gleam()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "// note\npub fn main() { 42 }\n");

		Highlighter* highlighter = create(tmem, &table, "app.gleam");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.COMMENT));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.KEYWORD));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.NUMBER));

		destroy(highlighter, tmem);
	};
}

fn void test_parse_highlights_erlang()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "%% note\nmain() -> \"hi\".\n");

		Highlighter* highlighter = create(tmem, &table, "server.erl");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.COMMENT));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.STRING));

		destroy(highlighter, tmem);
	};
}

fn void test_parse_highlights_elixir()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "# note\ndefmodule Foo do\n  def bar, do: \"hi\"\nend\n");

		Highlighter* highlighter = create(tmem, &table, "lib.ex");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.COMMENT));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.KEYWORD));
		assert(runs_have_role(highlighter, &table, 2, SyntaxRole.STRING));

		destroy(highlighter, tmem);
	};
}

fn void test_haskell_quasiquote_injects_html()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "x = [hamlet|<div></div>|]\n");

		Highlighter* highlighter = create(tmem, &table, "Main.hs");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.TYPE));

		destroy(highlighter, tmem);
	};
}

fn void test_elixir_sigil_injects_javascript()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "x = ~JS[let y = 1]\n");

		Highlighter* highlighter = create(tmem, &table, "lib.ex");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.KEYWORD));

		destroy(highlighter, tmem);
	};
}

fn void test_parse_highlights_dart()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "// note\nvoid main() { int x = 1; }\n");

		Highlighter* highlighter = create(tmem, &table, "main.dart");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.COMMENT));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.TYPE));
		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.NUMBER));

		destroy(highlighter, tmem);
	};
}

fn void test_parse_highlights_markdown()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(
			tmem,
			"# Title\n\nSome *emphasis* and **strong** and `code` and [link](http://x).\n\n- item\n"
		);

		Highlighter* highlighter = create(tmem, &table, "README.md");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 0, SyntaxRole.TITLE));
		assert(runs_have_role(highlighter, &table, 2, SyntaxRole.EMPHASIS));
		assert(runs_have_role(highlighter, &table, 2, SyntaxRole.STRONG));
		assert(runs_have_role(highlighter, &table, 2, SyntaxRole.LITERAL));
		assert(runs_have_role(highlighter, &table, 2, SyntaxRole.URI));
		assert(runs_have_role(highlighter, &table, 4, SyntaxRole.PUNCTUATION));

		destroy(highlighter, tmem);
	};
}

fn void test_markdown_fence_injects_language()
{
	@pool()
	{
		PieceTable table;
		table.init_from_buffer(tmem, "```c\nint x = 1;\n```\n");

		Highlighter* highlighter = create(tmem, &table, "README.md");
		assert(highlighter != null);
		highlighter.ensure_parsed();

		assert(runs_have_role(highlighter, &table, 1, SyntaxRole.TYPE));

		destroy(highlighter, tmem);
	};
}
fn void test_runs_for_line_matches_reference()
{
	Highlighter highlighter;
	highlighter.spans.init(tmem);
	highlighter.run_cursor = 0;
	highlighter.last_line_start = 0;

	uint seed = 12345;
	for (int i = 0; i < 60; i++)
	{
		seed = seed * 1664525 + 1013904223;
		uint start = seed % 80;
		seed = seed * 1664525 + 1013904223;
		uint end        = start + 1 + (seed % 20);
		SyntaxRole role = (seed % 2 == 0) ? SyntaxRole.KEYWORD : SyntaxRole.NUMBER;
		highlighter.spans.push({ .start = start, .end = end, .role = role });
	}
	libc::qsort(highlighter.spans.entries, (usz)highlighter.spans.size, Span::size, &span_compare);

	List{Span} runs;
	runs.init(tmem);

	for (usz line_start = 0; line_start < 80; line_start += 10)
	{
		usz line_end = line_start + 10;
		highlighter.begin_runs();
		highlighter.runs_for_line(line_start, line_end, &runs);

		usz pos      = line_start;
		sz run_index = 0;
		while (pos < line_end)
		{
			SyntaxRole role = SyntaxRole.TEXT;
			for (sz i = 0; i < highlighter.spans.len(); i++)
			{
				Span s = highlighter.spans[i];
				if ((usz)s.start <= pos && (usz)s.end > pos) role = s.role;
			}
			usz next = pos + 1;
			while (next < line_end)
			{
				SyntaxRole edge = SyntaxRole.TEXT;
				for (sz i = 0; i < highlighter.spans.len(); i++)
				{
					Span s = highlighter.spans[i];
					if ((usz)s.start <= next && (usz)s.end > next) edge = s.role;
				}
				if (edge != role) break;
				next++;
			}
			assert(run_index < runs.len());
			assert((usz)runs[run_index].start == pos);
			assert((usz)runs[run_index].end == next);
			assert(runs[run_index].role == role);
			run_index++;
			pos = next;
		}
		assert(run_index == runs.len());
	}

	runs.free();
	highlighter.spans.free();
}