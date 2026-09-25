module yun::hover @test;

import std::collections::list;

fn void test_markdown_parse()
{
	@pool()
	{
		List{HoverLine} lines;
		lines.init(tmem);
		parse_markdown(tmem, "foo `bar` baz\n```\ncode\n```\n# Title", &lines);

		assert(lines.len() == 3);

		assert(lines[0].runs.len() == 3);
		assert(lines[0].runs[1].code);
		assert(lines[0].runs[1].text.compare_to("bar") == 0);
		assert(!lines[0].runs[0].code);

		assert(lines[1].code);
		assert(lines[1].runs[0].text.compare_to("code") == 0);

		assert(lines[2].heading);
		assert(lines[2].runs[0].text.compare_to("Title") == 0);
	};
}

fn void test_markdown_emphasis()
{
	@pool()
	{
		List{HoverLine} lines;
		lines.init(tmem);
		parse_markdown(tmem, "**bold** and _em_", &lines);
		assert(lines.len() == 1);
		assert(lines[0].runs.len() == 1);
		assert(lines[0].runs[0].text.compare_to("bold and em") == 0);
	};
}