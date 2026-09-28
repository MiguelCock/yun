module yun::markdown @test;

import std::collections::list;

fn void test_parse_blocks()
{
	@pool()
	{
		String src = "# Title\n\nA paragraph\nline two.\n\n- one\n- two\n\n1. first\n2. second\n\n> quoted\n\n---\n\n```c\nint x = 1;\n```\n";
		MdDocument* doc = parse(tmem, src);

		int headings = 0;
		int paras    = 0;
		int lists    = 0;
		int quotes   = 0;
		int rules    = 0;
		int codes    = 0;
		foreach (MdBlock b : doc.blocks)
		{
			if (b.kind == MdBlockKind.HEADING)
			{
				headings++;
			}
			else if (b.kind == MdBlockKind.PARAGRAPH)
			{
				paras++;
			}
			else if (b.kind == MdBlockKind.LIST_ITEM)
			{
				lists++;
			}
			else if (b.kind == MdBlockKind.QUOTE)
			{
				quotes++;
			}
			else if (b.kind == MdBlockKind.RULE)
			{
				rules++;
			}
			else if (b.kind == MdBlockKind.CODE)
			{
				codes++;
			}
		}
		assert(headings == 1);
		assert(paras == 1);
		assert(lists == 4);
		assert(quotes == 1);
		assert(rules == 1);
		assert(codes == 1);

		foreach (MdBlock b : doc.blocks)
		{
			if (b.kind == MdBlockKind.HEADING)
			{
				assert(b.level == 1);
				assert(b.text.compare_to("Title") == 0);
			}
			else if (b.kind == MdBlockKind.PARAGRAPH)
			{
				assert(b.text.compare_to("A paragraph line two.") == 0);
			}
			else if (b.kind == MdBlockKind.CODE)
			{
				assert(b.language.compare_to("c") == 0);
				assert(b.text.compare_to("int x = 1;\n") == 0);
			}
			else if (b.kind == MdBlockKind.QUOTE)
			{
				assert(b.text.compare_to("quoted") == 0);
			}
		}

		free_document(doc, tmem);
	};
}

fn void test_heading_levels_and_lists()
{
	@pool()
	{
		String src      = "## Two\n### Three\n\n1. a\n2. b\n  - nested\n";
		MdDocument* doc = parse(tmem, src);
		int two         = 0;
		int three       = 0;
		int ordered     = 0;
		int nested      = 0;
		foreach (MdBlock b : doc.blocks)
		{
			if (b.kind == MdBlockKind.HEADING && b.level == 2) two++;
			if (b.kind == MdBlockKind.HEADING && b.level == 3) three++;
			if (b.kind == MdBlockKind.LIST_ITEM && b.ordered) ordered++;
			if (b.kind == MdBlockKind.LIST_ITEM && !b.ordered && b.level > 1) nested++;
		}
		assert(two == 1);
		assert(three == 1);
		assert(ordered == 2);
		assert(nested == 1);
		free_document(doc, tmem);
	};
}

fn void test_parse_inlines()
{
	@pool()
	{
		List{MdInline} inlines;
		parse_inlines(tmem, "a **b** c *d* `e` [f](http://x)", &inlines);

		bool strong = false;
		bool em     = false;
		bool code   = false;
		bool link   = false;
		foreach (MdInline in : inlines)
		{
			if (in.style == MdStyle.STRONG)
			{
				strong = true;
				assert(in.text.compare_to("b") == 0);
			}
			else if (in.style == MdStyle.EM)
			{
				em = true;
				assert(in.text.compare_to("d") == 0);
			}
			else if (in.style == MdStyle.CODE)
			{
				code = true;
				assert(in.text.compare_to("e") == 0);
			}
			else if (in.style == MdStyle.LINK)
			{
				link = true;
				assert(in.text.compare_to("f") == 0);
			}
		}
		assert(strong);
		assert(em);
		assert(code);
		assert(link);
		inlines.free();
	};
}

fn void test_layout_wraps_and_scales()
{
	@pool()
	{
		MdDocument* doc = parse(tmem, "hello world hello world hello world\n");
		MdLayout* l     = layout(tmem, doc, 10.0f, 1.0f, 10.0f, 10.0f);
		assert(l.runs.len() > 1);
		assert(l.height > 0.0f);
		free_layout(l, tmem);
		free_document(doc, tmem);
	};
	@pool()
	{
		MdDocument* doc = parse(tmem, "# Big\n");
		MdLayout* l     = layout(tmem, doc, 80.0f, 1.0f, 10.0f, 10.0f);
		bool scaled     = false;
		foreach (MdRun run : l.runs)
		{
			if (run.style == MdStyle.HEADING && run.size > 10.0f) scaled = true;
		}
		assert(scaled);
		free_layout(l, tmem);
		free_document(doc, tmem);
	};
}

fn void test_layout_code_no_wrap()
{
	@pool()
	{
		MdDocument* doc = parse(tmem, "```\nthis is a very long code line that should not wrap at all\n```\n");
		MdLayout* l     = layout(tmem, doc, 8.0f, 1.0f, 10.0f, 10.0f);
		int code_runs   = 0;
		foreach (MdRun run : l.runs)
		{
			if (run.style == MdStyle.CODE) code_runs++;
		}
		assert(code_runs == 1);
		free_layout(l, tmem);
		free_document(doc, tmem);
	};
}

fn void test_block_anchors()
{
	@pool()
	{
		MdDocument* doc = parse(tmem, "# A\n\nB\n");
		MdLayout* l     = layout(tmem, doc, 80.0f, 1.0f, 10.0f, 10.0f);
		assert(l.anchors.len() == 2);
		assert(l.anchors[0].offset == 0);
		assert(l.anchors[1].offset > l.anchors[0].offset);
		free_layout(l, tmem);
		free_document(doc, tmem);
	};
}

fn void test_is_markdown_path()
{
	assert(is_markdown_path("README.md"));
	assert(is_markdown_path("doc.markdown"));
	assert(!is_markdown_path("main.c"));
}