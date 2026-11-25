module yun::topbar @test;

import raylib6::rl;
import std::math;
import yun::commands;
import yun::ui;

fn void test_bar_rects()
{
	ui::set_ui_scale(1.0f);
	ui::set_dpi(1.0f, 1.0f);
	set_position(TopBarPosition.TOP);
	Rect top = bar_rect_for(TopBarPosition.TOP, 1000.0f, 800.0f);
	assert(top.x == 0.0f && top.y == 0.0f && top.width == 1000.0f && top.height == TOP_BAR_HEIGHT);

	Rect bottom = bar_rect_for(TopBarPosition.BOTTOM, 1000.0f, 800.0f);
	assert(bottom.y == 800.0f - TOP_BAR_HEIGHT);
	assert(bottom.height == TOP_BAR_HEIGHT);
	Rect left = bar_rect_for(TopBarPosition.LEFT, 1000.0f, 800.0f);
	assert(left.x == 0.0f && left.width == VERTICAL_WIDTH);
	Rect right = bar_rect_for(TopBarPosition.RIGHT, 1000.0f, 800.0f);
	assert(right.x == 1000.0f - VERTICAL_WIDTH);
	Rect content = content_rect_for(TopBarPosition.LEFT, 1000.0f, 800.0f);
	assert(content.x == VERTICAL_WIDTH && content.width == 1000.0f - VERTICAL_WIDTH);
	Rect bottom_content = content_rect_for(TopBarPosition.BOTTOM, 1000.0f, 800.0f);
	assert(bottom_content.y == 0.0f && bottom_content.height == 800.0f - TOP_BAR_HEIGHT);
	set_position(TopBarPosition.TOP);
}

fn void test_button_rects()
{
	ui::set_ui_scale(1.0f);
	ui::set_dpi(1.0f, 1.0f);
	set_position(TopBarPosition.TOP);
	Rect a = button_rect(0);
	Rect b = button_rect(1);
	assert(a.x == PADDING_X);
	assert(a.y == PADDING_Y);
	assert(a.width == BUTTON_WIDTH);
	assert(a.height == BUTTON_HEIGHT);
	assert(b.x == a.x + a.width + BUTTON_GAP);
	Rect settings = button_rect(5);
	assert(settings.width == ICON_BUTTON_WIDTH);
	assert(settings.x > b.x);
}

fn void test_vertical_button_rects()
{
	ui::set_ui_scale(1.0f);
	ui::set_dpi(1.0f, 1.0f);
	Rect first  = button_rect_for(TopBarPosition.LEFT, 0, 1000.0f, 800.0f);
	Rect second = button_rect_for(TopBarPosition.LEFT, 1, 1000.0f, 800.0f);
	assert(first.x == PADDING_X);
	assert(first.y == PADDING_Y);
	assert(first.width == VERTICAL_WIDTH - PADDING_X * 2.0f);
	assert(first.height == BUTTON_HEIGHT);
	assert(second.y == first.y + BUTTON_HEIGHT + BUTTON_GAP);
	Rect right = button_rect_for(TopBarPosition.RIGHT, 0, 1000.0f, 800.0f);
	assert(right.x == 1000.0f - VERTICAL_WIDTH + PADDING_X);
}

fn void test_hit_button()
{
	ui::set_ui_scale(1.0f);
	ui::set_dpi(1.0f, 1.0f);
	set_position(TopBarPosition.TOP);
	Rect save        = button_rect(2);
	RLVector2 inside = { save.x + 1.0f, save.y + 1.0f };
	assert(hit_button(inside, true, true) == (int)commands::CommandId.SAVE);
	assert(hit_button(inside, true, false) == -1);

	Rect open         = button_rect(1);
	RLVector2 open_in = { open.x + 1.0f, open.y + 1.0f };
	assert(hit_button(open_in, false, false) == (int)commands::CommandId.OPEN);
	assert(hit_button({ 0.0f, 0.0f }, true, true) == -1);

	set_position(TopBarPosition.LEFT);
	Rect vertical = button_rect(2);
	assert(hit_button({ vertical.x + 1.0f, vertical.y + 1.0f }, true, true) == (int)commands::CommandId.SAVE);
	set_position(TopBarPosition.TOP);
}
fn void test_keyboard_selection()
{
	TopBar bar;
	bar.init();
	// bar commands: NEW_FILE, OPEN, SAVE, TOGGLE_SCM, TOGGLE_CONSOLE, TOGGLE_SETTINGS
	bar.selected = 0;
	bar.clamp_selection(false, false);
	assert(bar.selected == 1); // NEW_FILE disabled -> OPEN

	bar.move_selection(1, false, false);
	assert(bar.selected == 3); // SAVE disabled -> TOGGLE_SCM
	assert(bar.activate(false, false) == (int)commands::CommandId.TOGGLE_SCM);

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
fn void test_next_utf8()
{
	String text = "aé…";
	assert(next_utf8(text, 0) == 1);
	assert(next_utf8(text, 1) == 3);
	assert(next_utf8(text, 3) == 6);
}