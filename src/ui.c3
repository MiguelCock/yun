module yun::ui;

import raylib6::rl;
import std::math;
import yun::theme;

const int BASE_SIZE = 16;

RLFont g_font;
int g_size                 =  BASE_SIZE;
float g_layout_scale       =  1.0f;
float g_font_scale         =  1.0f;
float g_ui_scale           =  1.0f;
float g_corner_radius      =  6.0f;
String g_tooltip           =  "";
String g_tooltip_shortcut  =  "";
RLVector2 g_tooltip_anchor =  { 0.0f, 0.0f };
bool g_tooltip_active      =  false;
int g_tooltip_last_frame   = -10;
int g_frame_count          =  0;
double g_tooltip_since     =  0.0;
RLMouseCursor g_cursor     =  RLMouseCursor.DEFAULT;
int g_cursor_priority      = -1;

const double TOOLTIP_DELAY_SECONDS = 0.35;

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

enum ControlState : int
{
	NORMAL,
	HOVER,
	PRESSED,
	FOCUSED,
	DISABLED,
}

fn bool pointer_in(Rect r, RLVector2 point)
{
	return point[0] >= r.x && point[0] <= r.x + r.width && point[1] >= r.y && point[1] <= r.y + r.height;
}

fn ControlState control_state_at(Rect r, RLVector2 mouse, bool mouse_down, bool enabled, bool focused)
{
	if (!enabled) return ControlState.DISABLED;
	bool hovered = pointer_in(r, mouse);
	if (hovered && mouse_down) return ControlState.PRESSED;
	if (hovered) return ControlState.HOVER;
	if (focused) return ControlState.FOCUSED;
	return ControlState.NORMAL;
}

fn ControlState control_state(Rect r, bool enabled, bool focused)
{
	return control_state_at(
		r,
		rl::get_mouse_position(),
		rl::is_mouse_button_down(rl::RLMouseButton.LEFT),
		enabled,
		focused
	);
}

fn RLColor control_fill(ControlState state, RLColor normal, RLColor hover, RLColor pressed, RLColor disabled)
{
	switch (state)
	{
		case ControlState.HOVER:
			return hover;
		case ControlState.PRESSED:
			return pressed;
		case ControlState.DISABLED:
			return disabled;
		case ControlState.NORMAL:
		case ControlState.FOCUSED:
			return normal;
	}
}

fn RLColor control_text(ControlState state, RLColor normal, RLColor disabled)
{
	return state == ControlState.DISABLED ? disabled : normal;
}

fn void focus_ring(Rect r)
{
	rounded_rect_lines(r, row_radius(), 2.0f, theme::current().card_focus);
}

fn void reset_cursor()
{
	g_cursor = RLMouseCursor.DEFAULT;
	g_cursor_priority = -1;
	g_tooltip_active = false;
	g_frame_count++;
}

fn void request_cursor(RLMouseCursor cursor, int priority)
{
	if (priority >= g_cursor_priority)
	{
		g_cursor = cursor;
		g_cursor_priority = priority;
	}
}

fn void apply_cursor()
{
	rl::set_mouse_cursor(g_cursor);
}

fn RLMouseCursor cursor_requested()
{
	return g_cursor;
}

fn void tooltip_shortcut(String text, String shortcut)
{
	if (text.len == 0) return;
	bool changed = !g_tooltip_active || g_tooltip.compare_to(text) != 0 || g_tooltip_shortcut.compare_to(shortcut) != 0;
	if (changed) g_tooltip_since = rl::get_time();
	g_tooltip = text;
	g_tooltip_shortcut = shortcut;
	g_tooltip_anchor = rl::get_mouse_position();
	g_tooltip_active = true;
}

fn void tooltip(String text)
{
	tooltip_shortcut(text, "");
}

fn bool tooltip_ready(double since, double now)
{
	return now - since >= TOOLTIP_DELAY_SECONDS;
}

fn Rect clamp_tooltip(Rect tip, RLVector2 anchor, float screen_w, float screen_h)
{
	float margin = pxf(4.0f);
	if (tip.x + tip.width > screen_w - margin) tip.x = screen_w - tip.width - margin;
	if (tip.y + tip.height > screen_h - margin) tip.y = anchor[1] - tip.height - pxf(8.0f);
	if (tip.x < margin) tip.x = margin;
	if (tip.y < margin) tip.y = margin;
	return tip;
}

fn void draw_tooltip(RLFont font)
{
	if (!g_tooltip_active) return;
	if (!tooltip_ready(g_tooltip_since, rl::get_time())) return;
	float size       = (float)tpx(13);
	float pad        = pxf(8.0f);
	float gap        = pxf(8.0f);
	float chip_size  = (float)tpx(11);
	float chip_pad   = pxf(5.0f);
	float text_width = rl::measure_text_ex(font, (ZString)g_tooltip.ptr, size, 0.0f)[0];
	float chip_width = g_tooltip_shortcut.len > 0 ? rl::measure_text_ex(
		font,
		(ZString)g_tooltip_shortcut.ptr,
		chip_size,
		0.0f
	)[0] + chip_pad * 2.0f
		: 0.0f;
	float width      = pad * 2.0f + text_width + (chip_width > 0.0f ? gap + chip_width : 0.0f);
	float height     = size + pxf(8.0f);
	Rect tip = {
		.x = g_tooltip_anchor[0] + pxf(14.0f),
		.y = g_tooltip_anchor[1] + pxf(20.0f),
		.width = width,
		.height = height,
	};
	tip = clamp_tooltip(tip, g_tooltip_anchor, (float)rl::get_screen_width(), (float)rl::get_screen_height());
	panel(tip, theme::current().panel_bg_alt, theme::current().panel_border);
	rl::draw_text_ex(font, (ZString)g_tooltip.ptr, { tip.x + pad, tip.y + pxf(4.0f) }, size, 0.0f, theme::current()
		.panel_text);
	if (chip_width > 0.0f)
	{
		Rect chip = {
			.x = tip.x + pad + text_width + gap,
			.y = tip.y + pxf(4.0f),
			.width = chip_width,
			.height = height - pxf(8.0f),
		};
		rounded_rect(chip, row_radius(), theme::current().panel_selected);
		rl::draw_text_ex(
			font,
			(ZString)g_tooltip_shortcut.ptr,
			{ chip.x + chip_pad, chip.y + (chip.height - chip_size) / 2.0f },
			chip_size,
			0.0f,
			theme::current()
			.panel_text);
	}
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
	rl::draw_circle_sector({ r.x + rad, r.y + rad }, rad, 180.0f, 360.0f, 16, color);
	rl::draw_circle_sector({ r.x + r.width - rad, r.y + rad }, rad, 180.0f, 360.0f, 16, color);
}