module yun::ui;

import raylib6::rl;
import std::math;

const int BASE_SIZE = 16;

RLFont g_font;
int g_size           = BASE_SIZE;
float g_layout_scale = 1.0f;
float g_font_scale   = 1.0f;
float g_ui_scale     = 1.0f;

fn void set_font(RLFont font, int size)
{
	g_font = font;
	g_size = size > 0 ? size : BASE_SIZE;
}

fn RLFont font()
{
	return g_font;
}

fn int size()
{
	return g_size;
}

fn void set_dpi(float font_scale, float layout_scale)
{
	g_font_scale = font_scale >= 1.0f ? font_scale : 1.0f;
	g_layout_scale = layout_scale >= 1.0f ? layout_scale : 1.0f;
}

fn float font_scale()
{
	return g_font_scale;
}

fn float layout_scale()
{
	return g_layout_scale;
}

fn void set_ui_scale(float scale)
{
	g_ui_scale = scale > 0.1f ? scale : 1.0f;
}

fn float ui_scale()
{
	return g_ui_scale;
}

fn float scale()
{
	return g_ui_scale * g_layout_scale;
}

fn float text_scale()
{
	return ((float)g_size / (float)BASE_SIZE) * scale();
}

fn int px(int base)
{
	return (int)math::round((float)base * scale());
}

fn float pxf(float base)
{
	return base * scale();
}

fn int tpx(int base)
{
	return (int)math::round((float)base * text_scale());
}

fn float tpxf(float base)
{
	return base * text_scale();
}

fn int atlas_px(int logical)
{
	int s = (int)math::round((float)logical * g_ui_scale * g_font_scale);
	return s < 1 ? 1 : s;
}

fn int draw_px(int logical)
{
	int s = (int)math::round((float)logical * g_ui_scale * g_layout_scale);
	return s < 1 ? 1 : s;
}