module yun::menu @test;

import raylib6::rl;

fn void test_menu_selection()
{
	@pool()
	{
		Menu m;
		m.init(tmem);
		String[2] items = { "New file", "New folder" };
		m.open_at({ 0.0f, 0.0f }, items[..]);
		assert(m.open);
		assert(m.rows() == 2);
		assert(m.selected == 0);

		m.move_selection(5);
		assert(m.selected == 1);
		m.move_selection(-5);
		assert(m.selected == 0);

		m.close();
		assert(!m.open);
	};
}
fn void test_menu_disabled_items()
{
	@pool()
	{
		Menu m;
		m.init(tmem);
		String[3] items = { "A", "B", "C" };
		bool[3] enabled = { true, false, true };
		m.open_with({ 0.0f, 0.0f }, items[..], enabled[..]);
		assert(m.rows() == 3);
		assert(m.is_enabled(0));
		assert(!m.is_enabled(1));
		assert(m.is_enabled(2));
		assert(m.selected == 0);

		m.move_selection(1);
		assert(m.selected == 2);
		m.move_selection(1);
		assert(m.selected == 0);
		m.move_selection(-1);
		assert(m.selected == 2);
	};
}