module yun::problems @test;

import yun::lsp;

fn void test_grouping_and_navigation()
{
	@pool()
	{
		Problems p;
		p.init(tmem);
		p.entries.push(
			{
				.path = "a.c".copy(tmem),
				.line = 1,
				.character = 2,
				.severity = lsp::DIAGNOSTIC_ERROR,
				.message = "x".copy(tmem),
			}
		);
		p.entries.push(
			{
				.path = "a.c".copy(tmem),
				.line = 3,
				.character = 0,
				.severity = lsp::DIAGNOSTIC_WARNING,
				.message = "y".copy(tmem),
			}
		);
		p.entries.push(
			{
				.path = "b.c".copy(tmem),
				.line = 0,
				.character = 0,
				.severity = lsp::DIAGNOSTIC_ERROR,
				.message = "z".copy(tmem),
			}
		);
		p.build_rows();

		assert(p.rows.len() == 5);
		assert(p.rows[0].header && !p.rows[1].header && !p.rows[2].header);
		assert(p.rows[3].header && !p.rows[4].header);
		assert(p.rows[0].label.compare_to("a.c") == 0);
		assert(p.rows[3].label.compare_to("b.c") == 0);
		assert(p.rows[4].entry == 2);

		assert(p.first_selectable() == 1);
		p.selected = 1;
		assert(p.selected_entry() == 0);

		p.move_selection(1);
		assert(p.selected == 2);
		assert(p.selected_entry() == 1);

		p.move_selection(1);
		assert(p.selected == 4);
		assert(p.selected_entry() == 2);

		p.move_selection(-1);
		assert(p.selected == 2);

		p.free_contents();
		p.entries.free();
		p.rows.free();
	};
}