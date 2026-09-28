module yun::highlight @test;

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
		assert(spec.extensions.len > 0);
		assert(spec.lib.len > 0);
		assert(spec.symbol.len > 0);
		assert(spec.highlights_path.len > 0);
		assert(language::language_for_path(spec.extensions[0]) == (language::Language)i);
		assert(language::grammar_language((language::Language)i) != null);
	}
}