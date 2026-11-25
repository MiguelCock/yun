module yun::ui @test;

import raylib6::rl;
import std::math::geometry;

fn void test_scale_and_px()
{
	set_ui_scale(1.0f);
	set_dpi(1.0f, 1.0f);
	set_font((RLFont) { }, 16);
	assert(scale() == 1.0f);
	assert(px(20) == 20);
	assert(tpx(20) == 20);

	set_font((RLFont) { }, 24);
	assert(scale() == 1.0f);
	assert(px(20) == 20);
	assert(text_scale() == 1.5f);
	assert(tpx(20) == 30);
	assert(tpxf(20.0f) == 30.0f);
	assert(size() == 24);

	set_font((RLFont) { }, 0);
	assert(scale() == 1.0f);
	assert(size() == 16);
	assert(text_scale() == 1.0f);
}

fn void test_ui_scale_geometry()
{
	set_font((RLFont) { }, 16);
	set_dpi(1.0f, 1.5f);
	set_ui_scale(2.0f);
	assert(scale() == 3.0f);
	assert(px(10) == 30);
	assert(tpx(10) == 30);

	set_font((RLFont) { }, 12);
	assert(px(10) == 30);
	assert(tpx(10) == 23);

	set_ui_scale(0.0f);
	assert(ui_scale() == 1.0f);
	set_ui_scale(1.0f);
	set_dpi(1.0f, 1.0f);
}

fn void test_dpi_scales()
{
	set_font((RLFont) { }, 16);
	set_ui_scale(1.0f);
	set_dpi(2.0f, 1.0f);
	assert(scale() == 1.0f);
	assert(font_scale() == 2.0f);
	assert(px(20) == 20);

	set_dpi(1.5f, 1.5f);
	assert(font_scale() == 1.5f);
	assert(px(20) == 30);
	assert(pxf(20.0f) == 30.0f);

	set_dpi(0.5f, 0.0f);
	assert(scale() == 1.0f);
	assert(font_scale() == 1.0f);
	set_dpi(1.0f, 1.0f);
}

fn void test_atlas_and_draw_px()
{
	set_font((RLFont) { }, 12);
	set_dpi(1.494f, 1.494f);
	set_ui_scale(1.0f);
	assert(atlas_px(12) == 18);
	assert(draw_px(14) == 21);

	set_ui_scale(2.0f);
	assert(atlas_px(12) == 36);
	assert(draw_px(14) == 42);

	set_ui_scale(1.0f);
	set_dpi(1.0f, 1.0f);
}
fn void test_corner_radius()
{
	set_ui_scale(1.0f);
	set_dpi(1.0f, 1.0f);
	set_corner_radius(6.0f);
	assert(corner_radius() == 6.0f);

	Rect wide = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 40.0f };
	assert(roundness_for(wide, 6.0f) == 0.3f);
	assert(roundness_for({ .x = 0.0f, .y = 0.0f, .width = 10.0f, .height = 10.0f }, 16.0f) == 1.0f);
	assert(roundness_for(wide, 0.0f) == 0.0f);

	set_corner_radius(100.0f);
	assert(corner_radius() == 16.0f);
	set_corner_radius(-4.0f);
	assert(corner_radius() == 0.0f);
	set_corner_radius(6.0f);
}
fn void test_control_state()
{
	Rect r            = { .x = 10.0f, .y = 20.0f, .width = 100.0f, .height = 40.0f };
	RLVector2 inside  = { 20.0f, 30.0f };
	RLVector2 outside = { 0.0f, 0.0f };
	assert(control_state_at(r, inside, false, true, false) == ControlState.HOVER);
	assert(control_state_at(r, inside, true, true, false) == ControlState.PRESSED);
	assert(control_state_at(r, inside, false, false, false) == ControlState.DISABLED);
	assert(control_state_at(r, outside, false, true, true) == ControlState.FOCUSED);
	assert(control_state_at(r, outside, false, true, false) == ControlState.NORMAL);
}

fn void test_control_colors()
{
	RLColor normal   = { 1, 2, 3, 4 };
	RLColor hover    = { 5, 6, 7, 8 };
	RLColor pressed  = { 9, 10, 11, 12 };
	RLColor disabled = { 13, 14, 15, 16 };
	assert(control_fill(ControlState.NORMAL, normal, hover, pressed, disabled)[0] == 1);
	assert(control_fill(ControlState.HOVER, normal, hover, pressed, disabled)[0] == 5);
	assert(control_fill(ControlState.PRESSED, normal, hover, pressed, disabled)[0] == 9);
	assert(control_fill(ControlState.DISABLED, normal, hover, pressed, disabled)[0] == 13);
	assert(control_text(ControlState.DISABLED, normal, disabled)[0] == 13);
}

fn void test_tooltip_ready_and_clamp()
{
	set_ui_scale(1.0f);
	set_dpi(1.0f, 1.0f);
	assert(!tooltip_ready(0.0, 0.34));
	assert(tooltip_ready(0.0, 0.35));

	Rect tip     = { .x = 900.0f, .y = 790.0f, .width = 150.0f, .height = 30.0f };
	Rect clamped = clamp_tooltip(tip, { 950.0f, 720.0f }, 1000.0f, 800.0f);
	assert(clamped.x == 846.0f);
	assert(clamped.y == 682.0f);

	Rect small    = { .x = -20.0f, .y = -10.0f, .width = 40.0f, .height = 20.0f };
	Rect top_left = clamp_tooltip(small, { 0.0f, 0.0f }, 1000.0f, 800.0f);
	assert(top_left.x == 4.0f && top_left.y == 4.0f);
}

fn void test_scrollbar_geometry()
{
	set_ui_scale(1.0f);
	set_dpi(1.0f, 1.0f);
	Rect vertical = { .x = 10.0f, .y = 20.0f, .width = 4.0f, .height = 100.0f };
	Rect full     = scrollbar_thumb(vertical, 50.0f, 100.0f, 0.0f, false);
	assert(full.height == 100.0f && full.y == 20.0f);
	Rect top = scrollbar_thumb(vertical, 400.0f, 100.0f, 0.0f, false);
	assert(top.height == 25.0f && top.y == 20.0f);
	Rect bottom = scrollbar_thumb(vertical, 400.0f, 100.0f, 300.0f, false);
	assert(bottom.y == 95.0f);
	Rect small = scrollbar_thumb(vertical, 1000.0f, 100.0f, 0.0f, false);
	assert(small.height == 24.0f);

	Rect horizontal = { .x = 0.0f, .y = 10.0f, .width = 200.0f, .height = 4.0f };
	Rect left       = scrollbar_thumb(horizontal, 400.0f, 200.0f, 0.0f, true);
	assert(left.width == 100.0f && left.x == 0.0f);
	Rect right = scrollbar_thumb(horizontal, 400.0f, 200.0f, 200.0f, true);
	assert(right.x == 100.0f);
}

fn void test_motion_respects_animations_setting()
{
	set_animations(false);
	Motion motion;
	motion.update(true);
	assert(motion.value == 1.0f);
	assert(motion.offset(10.0f) == 0.0f);
	motion.update(false);
	assert(motion.value == 0.0f);
	assert(motion.offset(10.0f) == 10.0f);
	set_animations(true);
}

fn void test_cursor_priority()
{
	reset_cursor();
	assert(cursor_requested() == RLMouseCursor.DEFAULT);
	request_cursor(RLMouseCursor.POINTING_HAND, 5);
	assert(cursor_requested() == RLMouseCursor.POINTING_HAND);
	request_cursor(RLMouseCursor.IBEAM, 1);
	assert(cursor_requested() == RLMouseCursor.POINTING_HAND);
	request_cursor(RLMouseCursor.IBEAM, 10);
	assert(cursor_requested() == RLMouseCursor.IBEAM);
	reset_cursor();
}