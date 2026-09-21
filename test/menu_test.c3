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