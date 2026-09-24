module yun::theme @test;

import raylib6::rl;

fn void test_registry_non_empty()
{
	assert(count() >= 2);
	assert(name(0).len > 0);
	assert(label(0).len > 0);
}

fn void test_set_by_name_and_aliases()
{
	assert(set_by_name("yun_dark"));
	assert(current_name().compare_to("yun_dark") == 0);

	assert(set_by_name("dark"));
	assert(current_name().compare_to("yun_dark") == 0);

	assert(set_by_name("light"));
	assert(current_name().compare_to("yun_light") == 0);

	assert(set_by_name("dracula"));
	assert(current_name().compare_to("dracula") == 0);

	assert(!set_by_name("does_not_exist"));
	assert(current_name().compare_to("dracula") == 0);
}

fn void test_set_index_updates_current()
{
	set_index(index_of("nord"));
	assert(current_name().compare_to("nord") == 0);
	Theme* t = current();
	assert(t.window_bg[0] == 46 && t.window_bg[1] == 52 && t.window_bg[2] == 64);
}

fn void test_palettes_differ()
{
	set_by_name("yun_dark");
	RLColor dark_bg = current().window_bg;
	set_by_name("yun_light");
	RLColor light_bg = current().window_bg;
	assert(dark_bg[0] != light_bg[0] || dark_bg[1] != light_bg[1] || dark_bg[2] != light_bg[2]);
}

fn void test_next_cycles()
{
	set_index(0);
	next();
	assert(index() == 1);
	prev();
	assert(index() == 0);
}