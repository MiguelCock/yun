module yun::topbar @test;

import raylib6::rl;
import std::math;
import yun::commands;

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
	assert(hit_button(inside, true, true) == (int)commands::CommandId.SAVE);
	assert(hit_button(inside, true, false) == -1);

	Rect open         = button_rect(1);
	RLVector2 open_in = { open.x + 1.0f, open.y + 1.0f };
	assert(hit_button(open_in, false, false) == (int)commands::CommandId.OPEN);
	assert(hit_button({ 0.0f, 0.0f }, true, true) == -1);
}
fn void test_keyboard_selection()
{
	TopBar bar;
	bar.init();
	// bar commands: NEW_FILE, OPEN, SAVE
	bar.selected = 0;
	bar.clamp_selection(false, false);
	assert(bar.selected == 1); // NEW_FILE disabled -> OPEN

	bar.move_selection(1, false, false);
	assert(bar.selected == 1); // only OPEN enabled
	assert(bar.activate(false, false) == (int)commands::CommandId.OPEN);

	bar.selected = 0;
	bar.move_selection(1, true, true);
	assert(bar.selected == 1);
	bar.move_selection(-1, true, true);
	assert(bar.selected == 0);
	bar.move_selection(-1, true, true);
	assert(bar.selected == (int)commands::bar_command_count() - 1);

	bar.selected = 2; // SAVE
	assert(bar.activate(true, false) == -1); // disabled without a buffer
	assert(bar.activate(true, true) == (int)commands::CommandId.SAVE);
}