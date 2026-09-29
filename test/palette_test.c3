module yun::palette @test;

import yun::commands;

fn void test_filter_empty_lists_all()
{
	@pool()
	{
		Palette p;
		p.init(tmem);
		p.show();
		p.filter();
		assert(p.results.len() == (sz)commands::command_count());
		assert(p.selected == 0);
	};
}

fn void test_filter_matches()
{
	@pool()
	{
		Palette p;
		p.init(tmem);
		p.show();
		p.append_codepoint('s');
		p.append_codepoint('a');
		p.append_codepoint('v');
		p.append_codepoint('e');
		p.filter();
		assert(p.results.len() == 1);
		assert(p.selected_command() == (int)commands::CommandId.SAVE);
	};
}

fn void test_filter_no_match()
{
	@pool()
	{
		Palette p;
		p.init(tmem);
		p.show();
		p.append_codepoint('z');
		p.append_codepoint('z');
		p.filter();
		assert(p.results.len() == 0);
		assert(p.selected_command() == -1);
	};
}

fn void test_recent_ordering()
{
	@pool()
	{
		Palette p;
		p.init(tmem);
		p.show();
		p.record(commands::CommandId.SAVE);
		p.filter();
		assert(p.results[0] == commands::CommandId.SAVE);

		p.record(commands::CommandId.OPEN);
		p.filter();
		assert(p.results[0] == commands::CommandId.OPEN);
		assert(p.results[1] == commands::CommandId.SAVE);
	};
}

fn void test_selection_clamped()
{
	@pool()
	{
		Palette p;
		p.init(tmem);
		p.show();
		p.filter();
		p.move_selection(100);
		assert(p.selected == (int)p.results.len() - 1);
		p.move_selection(-100);
		assert(p.selected == 0);
	};
}

fn void test_backspace_editing()
{
	@pool()
	{
		Palette p;
		p.init(tmem);
		p.show();
		assert(p.append_codepoint('o'));
		assert(p.append_codepoint('p'));
		assert(p.query_view().compare_to("op") == 0);
		p.backspace();
		assert(p.query_view().compare_to("o") == 0);
		p.backspace();
		assert(p.query_view().len == 0);
	};
}