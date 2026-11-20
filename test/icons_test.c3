module yun::icons @test;

import raylib6::rl;
import std::math::geometry;
import yun::ui;

fn void test_icon_size_and_box()
{
	ui::set_ui_scale(1.0f);
	ui::set_dpi(1.0f, 1.0f);
	assert(icon_size(16) == 16.0f);

	Rect button = { .x = 10.0f, .y = 10.0f, .width = 100.0f, .height = 40.0f };
	Rect box    = icon_box(button, 16);
	assert(box.x == 52.0f);
	assert(box.y == 22.0f);
	assert(box.width == 16.0f);
	assert(box.height == 16.0f);
}