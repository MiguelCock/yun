module yun::ui;

import raylib6::rl;
import std::math;

const int BASE_SIZE = 16;

RLFont g_font;
int g_size            = BASE_SIZE;
float g_layout_scale  = 1.0f;
float g_font_scale    = 1.0f;
float g_ui_scale      = 1.0f;
float g_corner_radius = 6.0f;

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

fn void set_corner_radius(float radius)
{
	g_corner_radius = math::clamp(radius, 0.0f, 16.0f);
}

fn float corner_radius()
{
	return pxf(g_corner_radius);
}

fn float roundness_for(Rect r, float radius)
{
	float max = math::min(r.width, r.height) * 0.5f;
	if (max <= 0.0f || radius <= 0.0f) return 0.0f;
	return math::clamp(radius / max, 0.0f, 1.0f);
}

fn void rounded_rect(Rect r, float radius, RLColor color)
{
	if (radius <= 0.0f)
	{
		rl::draw_rectangle_rec(r, color);
		return;
	}
	rl::draw_rectangle_rounded(r, roundness_for(r, radius), 16, color);
}

fn void rounded_rect_lines(Rect r, float radius, float thickness, RLColor color)
{
	if (radius <= 0.0f)
	{
		rl::draw_rectangle_lines_ex(r, thickness, color);
		return;
	}
	rl::draw_rectangle_rounded_lines_ex(r, roundness_for(r, radius), 16, thickness, color);
}

fn float row_radius()
{
	return math::min(corner_radius(), pxf(4.0f));
}

fn void panel(Rect r, RLColor fill, RLColor border)
{
	rounded_rect(r, corner_radius(), fill);
	rounded_rect_lines(r, corner_radius(), 1.0f, border);
}

fn void row(Rect r, RLColor color)
{
	rounded_rect(r, row_radius(), color);
}

fn void rounded_top(Rect r, float radius, RLColor color)
{
	float rad = math::min(radius, math::min(r.width * 0.5f, r.height));
	if (rad <= 0.5f)
	{
		rl::draw_rectangle_rec(r, color);
		return;
	}
	rl::draw_rectangle_rec({ .x = r.x + rad, .y = r.y, .width = r.width - rad * 2.0f, .height = r.height }, color);
	rl::draw_rectangle_rec({ .x = r.x, .y = r.y + rad, .width = rad, .height = r.height - rad }, color);
	rl::draw_rectangle_rec({ .x = r.x + r.width - rad, .y = r.y + rad, .width = rad, .height = r.height - rad }, color);
	rl::draw_circle_v({ r.x + rad, r.y + rad }, rad, color);
	rl::draw_circle_v({ r.x + r.width - rad, r.y + rad }, rad, color);
}