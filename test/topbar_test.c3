module yun::topbar @test;

import raylib6::rl;
import std::math;

fn void test_contains_screen()
{
	assert(contains_screen({ 10.0f, 0.0f }));
	assert(contains_screen({ 10.0f, TOP_BAR_HEIGHT }));
	assert(!contains_screen({ 10.0f, TOP_BAR_HEIGHT + 1.0f }));
	assert(!contains_screen({ -1.0f, 10.0f }));
}

fn void test_button_rects()
{
	Rect a = button_rect(0);
	Rect b = button_rect(1);
	assert(a.x == PADDING_X);
	assert(a.y == PADDING_Y);
	assert(a.width == BUTTON_WIDTH);
	assert(a.height == BUTTON_HEIGHT);
	assert(b.x == a.x + a.width + BUTTON_GAP);
}

fn void test_hit_button()
{
	Rect save        = button_rect(2);
	RLVector2 inside = { save.x + 1.0f, save.y + 1.0f };
	assert(hit_button(inside, true, true) == 2);
	assert(hit_button(inside, true, false) == -1);

	Rect open         = button_rect(1);
	RLVector2 open_in = { open.x + 1.0f, open.y + 1.0f };
	assert(hit_button(open_in, false, false) == 1);
	assert(hit_button({ 0.0f, 0.0f }, true, true) == -1);
}