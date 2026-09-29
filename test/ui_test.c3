module yun::ui @test;

import raylib6::rl;

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