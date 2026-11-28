module yun::topbar;

import raylib6::rl;
import std::math;
import yun::commands;
import yun::icons;
import yun::imports;
import yun::skin;
import yun::theme;
import yun::ui;

const float TOP_BAR_HEIGHT    = 34.0f;
const float VERTICAL_WIDTH    = 140.0f;
const float BUTTON_WIDTH      = 104.0f;
const float ICON_BUTTON_WIDTH = 34.0f;
const float BUTTON_HEIGHT     = 24.0f;
const float BUTTON_GAP        = 8.0f;
const float PADDING_X         = 8.0f;
const float PADDING_Y         = 5.0f;
const int MAX_BAR_SLOTS       = 16;
const float EXPAND_SECONDS    = 0.15f;
const float ZOOM_BUTTON_WIDTH = 22.0f;
const float ZOOM_PCT_WIDTH    = 44.0f;

enum TopBarPosition : int
{
	TOP,
	BOTTOM,
	LEFT,
	RIGHT,
}

TopBarPosition g_position = TopBarPosition.TOP;

fn void set_position(TopBarPosition position)
{
	g_position = position;
}

fn TopBarPosition position()
{
	return g_position;
}

fn TopBarPosition position_from_name(String name)
{
	if (name.compare_to("bottom") == 0) return TopBarPosition.BOTTOM;
	if (name.compare_to("left") == 0) return TopBarPosition.LEFT;
	if (name.compare_to("right") == 0) return TopBarPosition.RIGHT;
	return TopBarPosition.TOP;
}

struct TopBar
{
	int active;
	int selected;
	Rect counter_hit;
	Rect zoom_out_hit;
	Rect zoom_pct_hit;
	Rect zoom_in_hit;
	float[MAX_BAR_SLOTS] expand;
}

fn bool horizontal_position(TopBarPosition position)
{
	return position == TopBarPosition.TOP || position == TopBarPosition.BOTTOM;
}

fn float thickness_for(TopBarPosition position)
{
	return ui::pxf(horizontal_position(position) ? TOP_BAR_HEIGHT : VERTICAL_WIDTH);
}

fn Rect bar_rect_for(TopBarPosition position, float screen_w, float screen_h)
{
	float thickness = thickness_for(position);
	if (position == TopBarPosition.TOP) return { .x = 0.0f, .y = 0.0f, .width = screen_w, .height = thickness };
	if (position == TopBarPosition.BOTTOM)
	{
		return { .x = 0.0f, .y = screen_h - thickness, .width = screen_w, .height = thickness };
	}
	if (position == TopBarPosition.LEFT) return { .x = 0.0f, .y = 0.0f, .width = thickness, .height = screen_h };
	return { .x = screen_w - thickness, .y = 0.0f, .width = thickness, .height = screen_h };
}

fn Rect bar_rect()
{
	return bar_rect_for(g_position, (float)rl::get_screen_width(), (float)rl::get_screen_height());
}

fn Rect content_rect_for(TopBarPosition position, float screen_w, float screen_h)
{
	Rect bar = bar_rect_for(position, screen_w, screen_h);
	if (position == TopBarPosition.TOP) return {
		.x = 0.0f,
		.y = bar.height,
		.width = screen_w,
		.height = screen_h - bar.height
	};
	if (position == TopBarPosition.BOTTOM) return {
		.x = 0.0f,
		.y = 0.0f,
		.width = screen_w,
		.height = screen_h - bar.height
	};
	if (position == TopBarPosition.LEFT) return {
		.x = bar.width,
		.y = 0.0f,
		.width = screen_w - bar.width,
		.height = screen_h
	};
	return { .x = 0.0f, .y = 0.0f, .width = screen_w - bar.width, .height = screen_h };
}

fn Rect content_rect()
{
	return content_rect_for(g_position, (float)rl::get_screen_width(), (float)rl::get_screen_height());
}

fn bool contains_screen(RLVector2 screen)
{
	Rect bar = bar_rect();
	return screen[0] >= bar.x && screen[0] <= bar.x + bar.width && screen[1] >= bar.y
		&& screen[1] <= bar.y + bar.height;
}

fn float ease_expand(float t)
{
	t = math::clamp(t, 0.0f, 1.0f);
	return t * t * (3.0f - 2.0f * t);
}

fn float TopBar.button_width(&self, usz index)
{
	CommandDef def = commands::bar_command(index);
	if (def.icon_only || !horizontal_position(g_position) || index >= MAX_BAR_SLOTS) return ui::pxf(ICON_BUTTON_WIDTH);
	float collapsed = ui::pxf(ICON_BUTTON_WIDTH);
	float expanded  = ui::pxf(BUTTON_WIDTH);
	return collapsed + (expanded - collapsed) * ease_expand(self.expand[index]);
}

fn float TopBar.button_x(&self, usz index)
{
	float x = ui::pxf(PADDING_X);
	for (usz i = 0; i < index; i++)
	{
		x += self.button_width(i) + ui::pxf(BUTTON_GAP);
	}
	return x;
}

fn Rect TopBar.button_rect_for(&self, TopBarPosition position, usz index, float screen_w, float screen_h)
{
	Rect bar = bar_rect_for(position, screen_w, screen_h);
	if (!horizontal_position(position))
	{
		return {
			.x = bar.x + ui::pxf(PADDING_X),
			.y = bar.y + ui::pxf(PADDING_Y) + (float)index * (ui::pxf(BUTTON_HEIGHT) + ui::pxf(BUTTON_GAP)),
			.width = bar.width - ui::pxf(PADDING_X) * 2.0f,
			.height = ui::pxf(BUTTON_HEIGHT),
		};
	}
	return {
		.x = self.button_x(index),
		.y = bar.y + ui::pxf(PADDING_Y),
		.width = self.button_width(index),
		.height = ui::pxf(BUTTON_HEIGHT),
	};
}

fn Rect TopBar.button_rect(&self, usz index)
{
	return self.button_rect_for(g_position, index, (float)rl::get_screen_width(), (float)rl::get_screen_height());
}

fn void TopBar.zoom_rects(&self, Rect bar, Rect* out, Rect* pct, Rect* in)
{
	float height = ui::pxf(BUTTON_HEIGHT);
	float y      = bar.y + (bar.height - height) * 0.5f;
	float right  = bar.x + bar.width - ui::pxf(12.0f);
	*in = { .x = right - ui::pxf(ZOOM_BUTTON_WIDTH), .y = y, .width = ui::pxf(ZOOM_BUTTON_WIDTH), .height = height };
	*pct = {
		.x = in.x - ui::pxf(ZOOM_PCT_WIDTH) - ui::pxf(2.0f),
		.y = y,
		.width = ui::pxf(ZOOM_PCT_WIDTH),
		.height = height
	};
	*out = {
		.x = pct.x - ui::pxf(ZOOM_BUTTON_WIDTH) - ui::pxf(2.0f),
		.y = y,
		.width = ui::pxf(ZOOM_BUTTON_WIDTH),
		.height = height
	};
}

fn float TopBar.status_start(&self)
{
	float x = self.button_x(commands::bar_command_count());
	if (commands::bar_command_count() > 0) x += ui::pxf(BUTTON_GAP);
	return x;
}

fn void TopBar.update_expansion(&self, RLVector2 mouse, bool focused)
{
	float step = ui::animations() ? rl::get_frame_time() / EXPAND_SECONDS : 1.0f;
	usz count  = commands::bar_command_count();
	for (usz i = 0; i < count && i < MAX_BAR_SLOTS; i++)
	{
		Rect r = self.button_rect_for(g_position, i, (float)rl::get_screen_width(), (float)rl::get_screen_height());
		bool hovered = horizontal_position(g_position) && ui::pointer_in(r, mouse);
		bool selected = focused && (int)i == self.selected;
		float target = (hovered || selected) ? 1.0f : 0.0f;
		if (self.expand[i] < target)
		{
			self.expand[i] += step;
			if (self.expand[i] > target) self.expand[i] = target;
		}
		else if (self.expand[i] > target)
		{
			self.expand[i] -= step;
			if (self.expand[i] < target) self.expand[i] = target;
		}
	}
}

fn int TopBar.hit_button(&self, RLVector2 screen, bool has_project, bool has_buffer)
{
	for (usz i = 0; i < commands::bar_command_count(); i++)
	{
		CommandDef def = commands::bar_command(i);
		if (!commands::command_enabled(def.id, has_project, has_buffer)) continue;
		Rect r = self.button_rect_for(g_position, i, (float)rl::get_screen_width(), (float)rl::get_screen_height());
		if (screen[0] >= r.x && screen[0] <= r.x + r.width && screen[1] >= r.y
			&& screen[1] <= r.y + r.height) return (int)def.id;
	}
	return -1;
}

fn void TopBar.init(&self)
{
	self.active = -1;
	self.selected = 0;
	self.counter_hit = { };
	self.zoom_out_hit = { };
	self.zoom_pct_hit = { };
	self.zoom_in_hit = { };
	for (usz i = 0; i < MAX_BAR_SLOTS; i++) self.expand[i] = 0.0f;
}

fn bool button_enabled(usz index, bool has_project, bool has_buffer)
{
	CommandDef def = commands::bar_command(index);
	return commands::command_enabled(def.id, has_project, has_buffer);
}

fn void TopBar.clamp_selection(&self, bool has_project, bool has_buffer)
{
	usz count = commands::bar_command_count();
	if (count == 0)
	{
		self.selected = 0;
		return;
	}
	if (self.selected < 0) self.selected = 0;
	if (self.selected >= (int)count) self.selected = (int)count - 1;
	if (button_enabled((usz)self.selected, has_project, has_buffer)) return;
	for (usz i = 0; i < count; i++)
	{
		if (button_enabled(i, has_project, has_buffer))
		{
			self.selected = (int)i;
			return;
		}
	}
}

fn void TopBar.move_selection(&self, int delta, bool has_project, bool has_buffer)
{
	usz count = commands::bar_command_count();
	if (count == 0) return;
	int step      = delta > 0 ? 1 : -1;
	int remaining = delta > 0 ? delta : -delta;
	int current   = self.selected;
	for (int i = 0; i < remaining; i++)
	{
		int next = current;
		for (usz j = 0; j < count; j++)
		{
			next += step;
			if (next < 0) next = (int)count - 1;
			if (next >= (int)count) next = 0;
			if (button_enabled((usz)next, has_project, has_buffer)) break;
		}
		current = next;
	}
	self.selected = current;
}

fn int TopBar.activate(&self, bool has_project, bool has_buffer)
{
	usz count = commands::bar_command_count();
	if (count == 0) return -1;
	if (self.selected < 0 || self.selected >= (int)count) return -1;
	CommandDef def = commands::bar_command((usz)self.selected);
	if (!commands::command_enabled(def.id, has_project, has_buffer)) return -1;
	return (int)def.id;
}

fn int TopBar.update(&self, RLVector2 screen, bool has_project, bool has_buffer)
{
	if (!contains_screen(screen))
	{
		self.active = -1;
		return -1;
	}

	Rect bar = bar_rect();
	if (horizontal_position(g_position) && rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		Rect zoom_out_rect;
		Rect zoom_pct_rect;
		Rect zoom_in_rect;
		self.zoom_rects(bar, &zoom_out_rect, &zoom_pct_rect, &zoom_in_rect);
		if (ui::pointer_in(zoom_out_rect, screen)) return (int)commands::CommandId.ZOOM_OUT;
		if (ui::pointer_in(zoom_in_rect, screen)) return (int)commands::CommandId.ZOOM_IN;
		if (ui::pointer_in(zoom_pct_rect, screen)) return (int)commands::CommandId.ZOOM_RESET;
	}
	if (self.counter_hit.width > 0.0f && rl::is_mouse_button_pressed(
		rl::RLMouseButton.LEFT
	) && screen[0] >= self.counter_hit.x && screen[0] <= self.counter_hit.x
		+ self.counter_hit.width && screen[1] >= self.counter_hit.y && screen[1] <= self.counter_hit.y
			+ self.counter_hit.height)
	{
		return (int)commands::CommandId.PROBLEMS;
	}

	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		self.active = self.hit_button(screen, has_project, has_buffer);
	}
	if (rl::is_mouse_button_released(rl::RLMouseButton.LEFT))
	{
		int index  = self.hit_button(screen, has_project, has_buffer);
		int active = self.active;
		self.active = -1;
		if (index >= 0 && index == active) return index;
	}
	return -1;
}

fn icons::IconKind icon_for_command(commands::CommandId id)
{
	switch (id)
	{
		case commands::CommandId.NEW_FILE:
			return icons::IconKind.NEW_FILE;
		case commands::CommandId.OPEN:
			return icons::IconKind.OPEN;
		case commands::CommandId.SAVE:
			return icons::IconKind.SAVE;
		case commands::CommandId.TOGGLE_SETTINGS:
			return icons::IconKind.SETTINGS;
		case commands::CommandId.TOGGLE_SCM:
			return icons::IconKind.GIT;
		case commands::CommandId.TOGGLE_CONSOLE:
			return icons::IconKind.CONSOLE;
		case commands::CommandId.SEARCH_PROJECT:
		case commands::CommandId.SEARCH_REPLACE_PROJECT:
			return icons::IconKind.SEARCH;
		case commands::CommandId.TOGGLE_ARROWS_OVERLAY:
			return icons::IconKind.ARROWS;
		default:
			return icons::IconKind.SETTINGS;
	}
}

fn float bar_text_y(Rect bar, float text_height)
{
	return bar.y + (bar.height - text_height) / 2.0f;
}

fn usz next_utf8(String text, usz i)
{
	i++;
	while (i < text.len && ((int)text[i] & 0xC0) == 0x80) i++;
	return i;
}

fn String elide_text(RLFont font, String text, float size, float max_width)
{
	if (text.len == 0 || max_width <= 0.0f) return "";
	if (rl::measure_text_ex(font, (ZString)text.ptr, size, 0.0f)[0] <= max_width) return text;

	String ellipsis      = "...";
	float ellipsis_width = rl::measure_text_ex(font, (ZString)ellipsis.ptr, size, 0.0f)[0];
	if (max_width <= ellipsis_width) return "";

	usz end       = 0;
	usz last_good = 0;
	while (end < text.len)
	{
		end = next_utf8(text, end);
		String prefix = text[0:end];
		if (rl::measure_text_ex(font, (ZString)prefix.ptr, size, 0.0f)[0] + ellipsis_width > max_width) break;
		last_good = end;
	}
	if (last_good == 0) return "";
	return string::format(tmem, "%s...", text[0:last_good]);
}

fn void draw_elided_row(
	RLFont font,
	String text,
	float x,
	float* y,
	float max_width,
	float row_height,
	float bottom,
	float text_size,
	RLColor color
)
{
	if (text.len == 0) return;
	if (*y + row_height > bottom) return;
	String shown = elide_text(font, text, text_size, max_width);
	if (shown.len == 0) return;
	rl::draw_text_ex(font, (ZString)shown.ptr, { x, *y }, text_size, 0.0f, color);
	*y += row_height;
}

fn void TopBar.draw_horizontal_status(
	&self,
	bool has_project,
	String project_name,
	String mode,
	String folder,
	float zoom,
	String lsp_status,
	int errors,
	int warnings,
	RLFont font,
	Rect bar
)
{
	float text_size = (float)ui::tpx(16);
	float name_x    = self.status_start();
	name_x += (float)ui::px(12);
	@pool()
	{
		Rect zoom_out_rect;
		Rect zoom_pct_rect;
		Rect zoom_in_rect;
		self.zoom_rects(bar, &zoom_out_rect, &zoom_pct_rect, &zoom_in_rect);
		self.zoom_out_hit = zoom_out_rect;
		self.zoom_pct_hit = zoom_pct_rect;
		self.zoom_in_hit = zoom_in_rect;
		RLVector2 mouse            = rl::get_mouse_position();
		ui::ControlState out_state = ui::control_state(zoom_out_rect, true, false);
		ui::ControlState in_state  = ui::control_state(zoom_in_rect, true, false);
		ui::ControlState pct_state = ui::control_state(zoom_pct_rect, true, false);
		ui::rounded_rect(zoom_out_rect, ui::row_radius(), ui::control_fill(out_state, theme::current()
			.topbar_button, theme::current()
				.topbar_hover, theme::current().panel_selected, theme::current().panel_bg_alt));
		ui::rounded_rect(zoom_in_rect, ui::row_radius(), ui::control_fill(in_state, theme::current()
			.topbar_button, theme::current()
				.topbar_hover, theme::current().panel_selected, theme::current().panel_bg_alt));
		ui::rounded_rect(zoom_pct_rect, ui::row_radius(), ui::control_fill(pct_state, theme::current()
			.topbar_button, theme::current()
				.topbar_hover, theme::current().panel_selected, theme::current().panel_bg_alt));
		String zoom_label = string::format(tmem, "%d%%", (int)(zoom * 100.0f));
		float minus_w     = rl::measure_text_ex(font, "-", text_size, 0.0f)[0];
		float plus_w      = rl::measure_text_ex(font, "+", text_size, 0.0f)[0];
		float zoom_width  = rl::measure_text_ex(font, (ZString)zoom_label.ptr, text_size, 0.0f)[0];
		rl::draw_text_ex(
			font,
			"-",
			{ zoom_out_rect.x + (zoom_out_rect.width - minus_w) * 0.5f, bar_text_y(bar, text_size) },
			text_size,
			0.0f,
			theme::current()
			.topbar_text);
		rl::draw_text_ex(
			font,
			"+",
			{ zoom_in_rect.x + (zoom_in_rect.width - plus_w) * 0.5f, bar_text_y(bar, text_size) },
			text_size,
			0.0f,
			theme::current()
			.topbar_text);
		rl::draw_text_ex(
			font,
			(ZString)zoom_label.ptr,
			{ zoom_pct_rect.x + (zoom_pct_rect.width - zoom_width) * 0.5f, bar_text_y(bar, text_size) },
			text_size,
			0.0f,
			theme::current()
			.topbar_name);
		float right_start = zoom_out_rect.x;

		float lsp_width = 0.0f;
		if (lsp_status.len > 0)
		{
			lsp_width = rl::measure_text_ex(font, (ZString)lsp_status.ptr, text_size, 0.0f)[0];
			right_start -= (float)ui::px(24) + lsp_width;
		}

		String counts     = "";
		float counts_size = 0.0f;
		if (errors > 0 || warnings > 0)
		{
			counts = string::format(tmem, "E%d W%d", errors, warnings);
			counts_size = rl::measure_text_ex(font, (ZString)counts.ptr, text_size, 0.0f)[0];
			right_start -= (float)ui::px(24) + counts_size;
		}

		if (has_project && project_name.len > 0)
		{
			String name      = project_name;
			float name_width = rl::measure_text_ex(font, (ZString)name.ptr, text_size, 0.0f)[0];
			float name_max   = right_start - name_x - (float)ui::px(12);
			if (name_max > 0.0f && name_width > name_max) name = elide_text(font, name, text_size, name_max);
			if (name.len > 0)
			{
				name_width = rl::measure_text_ex(font, (ZString)name.ptr, text_size, 0.0f)[0];
				rl::draw_text_ex(
					font,
					(ZString)name.ptr,
					{ name_x, bar_text_y(bar, text_size) },
					text_size,
					0.0f,
					theme::current()
					.topbar_name);
				if (mode.len > 0)
				{
					float status_x   = name_x + name_width + (float)ui::px(16);
					float status_max = right_start - status_x - (float)ui::px(12);
					if (status_max > 0.0f)
					{
						String shown_mode = elide_text(font, mode, text_size, status_max);
						if (shown_mode.len > 0)
						{
							rl::draw_text_ex(
								font,
								(ZString)shown_mode.ptr,
								{ status_x, bar_text_y(bar, text_size) },
								text_size,
								0.0f,
								theme::current()
								.topbar_name);
							float mode_width = rl::measure_text_ex(font, (ZString)shown_mode.ptr, text_size, 0.0f)[0];
							float folder_x   = status_x + mode_width + (float)ui::px(12);
							float folder_max = right_start - folder_x - (float)ui::px(12);
							if (folder.len > 0 && folder_max > 0.0f)
							{
								String shown_folder = elide_text(font, folder, text_size, folder_max);
								if (shown_folder.len > 0)
								{
									rl::draw_text_ex(
										font,
										(ZString)shown_folder.ptr,
										{ folder_x, bar_text_y(bar, text_size) },
										text_size,
										0.0f,
										theme::current()
										.topbar_disabled);
								}
							}
						}
					}
				}
			}
		}

		float cursor_x = zoom_out_rect.x;
		self.counter_hit = { };
		if (lsp_status.len > 0)
		{
			cursor_x -= (float)ui::px(24) + lsp_width;
			rl::draw_text_ex(
				font,
				(ZString)lsp_status.ptr,
				{ cursor_x, bar_text_y(bar, text_size) },
				text_size,
				0.0f,
				theme::current()
				.topbar_disabled);
		}
		if (counts.len > 0)
		{
			cursor_x -= (float)ui::px(24) + counts_size;
			rl::draw_text_ex(
				font,
				(ZString)counts.ptr,
				{ cursor_x, bar_text_y(bar, text_size) },
				text_size,
				0.0f,
				errors > 0 ? theme::current()
				.topbar_error : theme::current().topbar_warning);
			self.counter_hit = {
				.x = cursor_x,
				.y = bar_text_y(bar, text_size),
				.width = counts_size,
				.height = text_size,
			};
		}
	};
}

fn void TopBar.draw_vertical_status(
	&self,
	bool has_project,
	String project_name,
	String mode,
	String folder,
	float zoom,
	String lsp_status,
	int errors,
	int warnings,
	RLFont font,
	Rect bar
)
{
	float text_size  = (float)ui::tpx(14);
	float row_height = text_size + (float)ui::px(6);
	float x          = bar.x + ui::pxf(PADDING_X);
	float max_width  = bar.width - ui::pxf(PADDING_X) * 2.0f;
	float bottom     = bar.y + bar.height - ui::pxf(PADDING_Y);
	float y          = bar.y + ui::pxf(
		PADDING_Y
	) + (float)commands::bar_command_count() * (ui::pxf(BUTTON_HEIGHT) + ui::pxf(BUTTON_GAP)) + (float)ui::px(4);
	self.counter_hit = { };
	@pool()
	{
		if (has_project) draw_elided_row(
			font,
			project_name,
			x,
			&y,
			max_width,
			row_height,
			bottom,
			text_size,
			theme::current()
			.topbar_name);
		draw_elided_row(font, mode, x, &y, max_width, row_height, bottom, text_size, theme::current().topbar_name);
		draw_elided_row(font, folder, x, &y, max_width, row_height, bottom, text_size, theme::current()
			.topbar_disabled);
		String zoom_label = string::format(tmem, "%d%%", (int)(zoom * 100.0f));
		draw_elided_row(font, zoom_label, x, &y, max_width, row_height, bottom, text_size, theme::current()
			.topbar_name);
		draw_elided_row(font, lsp_status, x, &y, max_width, row_height, bottom, text_size, theme::current()
			.topbar_disabled);
		if (errors > 0 || warnings > 0)
		{
			String counts = string::format(tmem, "E%d W%d", errors, warnings);
			if (y + row_height <= bottom)
			{
				rl::draw_text_ex(font, (ZString)counts.ptr, { x, y }, text_size, 0.0f, errors > 0 ? theme::current()
					.topbar_error : theme::current().topbar_warning);
				self.counter_hit = { .x = x, .y = y, .width = max_width, .height = row_height };
				y += row_height;
			}
		}
	};
}

fn void TopBar.draw(
	&self,
	bool has_project,
	bool has_buffer,
	String project_name,
	String mode,
	String folder,
	float zoom,
	String lsp_status,
	int errors,
	int warnings,
	RLFont font,
	bool focused
)
{
	Rect bar            = bar_rect();
	float screen_w      = (float)rl::get_screen_width();
	float screen_h      = (float)rl::get_screen_height();
	bool horizontal     = horizontal_position(g_position);
	RLColor topbar_base = theme::current().topbar_bg;
	if (skin::has_image(skin::SurfaceId.TOPBAR)) topbar_base.a = 255;
	rl::draw_rectangle_rec(bar, topbar_base);
	skin::draw_screen(skin::SurfaceId.TOPBAR, bar, 0.0f);
	if (g_position == TopBarPosition.TOP)
	{
		rl::draw_line(0, (int)(bar.y + bar.height), (int)screen_w, (int)(bar.y + bar.height), theme::current()
			.topbar_border);
	}
	else if (g_position == TopBarPosition.BOTTOM)
	{
		rl::draw_line(0, (int)bar.y, (int)screen_w, (int)bar.y, theme::current().topbar_border);
	}
	else if (g_position == TopBarPosition.LEFT)
	{
		rl::draw_line((int)(bar.x + bar.width), 0, (int)(bar.x + bar.width), (int)screen_h, theme::current()
			.topbar_border);
	}
	else
	{
		rl::draw_line((int)bar.x, 0, (int)bar.x, (int)screen_h, theme::current().topbar_border);
	}

	RLVector2 mouse = rl::get_mouse_position();
	self.update_expansion(mouse, focused);
	for (usz i = 0; i < commands::bar_command_count(); i++)
	{
		CommandDef def                = commands::bar_command(i);
		bool enabled                  = commands::command_enabled(def.id, has_project, has_buffer);
		Rect r                        = self.button_rect_for(g_position, i, screen_w, screen_h);
		bool hovered                  = ui::pointer_in(r, mouse);
		bool arrow_button             = def.id == commands::CommandId.TOGGLE_ARROWS_OVERLAY;
		imports::ArrowMode arrow_mode = arrow_button ? imports::mode() : imports::ArrowMode.OFF;
		bool toggled                  = arrow_button && arrow_mode != imports::ArrowMode.OFF;
		ui::ControlState state = ui::control_state_at(
			r,
			mouse,
			rl::is_mouse_button_down(rl::RLMouseButton.LEFT),
			enabled,
			toggled
		);
		RLColor fill = ui::control_fill(state, theme::current()
			.topbar_button, theme::current()
				.topbar_hover, theme::current().panel_selected, theme::current().panel_bg_alt);
		RLColor arrow_color = arrow_mode == imports::ArrowMode.ALL ? theme::current()
			.topbar_warning : theme::current().card_focus;
		if (arrow_button && arrow_mode != imports::ArrowMode.OFF
			&& (state == ui::ControlState.NORMAL || state == ui::ControlState.FOCUSED)) fill = theme::with_alpha(
			arrow_color,
			38
		);
		ui::rounded_rect(r, ui::row_radius(), fill);
		if (hovered && enabled) ui::request_cursor(rl::RLMouseCursor.POINTING_HAND, 5);

		String label = def.bar_label.len > 0 ? def.bar_label : def.label;
		float button_text_size = (float)ui::tpx(15);
		float icon_size = icons::icon_size(16);
		float gap = (float)ui::px(6);
		RLColor color = ui::control_text(state, theme::current().topbar_text, theme::current().topbar_disabled);
		if (arrow_button)
		{
			if (arrow_mode == imports::ArrowMode.OFF)
			{
				color = theme::current().topbar_disabled;
			}
			else
			{
				color = arrow_color;
			}
		}
		if (arrow_button && arrow_mode != imports::ArrowMode.OFF)
		{
			rl::draw_circle(
				(int)(r.x + r.width - (float)ui::px(6)),
				(int)(r.y + (float)ui::px(6)),
				(float)ui::px(2),
				arrow_color
			);
		}
		float expand = i < MAX_BAR_SLOTS ? ease_expand(self.expand[i]) : 0.0f;
		if (def.icon_only || !horizontal_position(g_position))
		{
			icons::draw(icon_for_command(def.id), icons::icon_box(r, 16), color);
			if (hovered) ui::tooltip_shortcut(
				arrow_button ? string::format(tmem, "Connections: %s", imports::mode_name()) : def.label,
				def.shortcut
			);
		}
		else
		{
			RLVector2 size = rl::measure_text_ex(font, (ZString)label.ptr, button_text_size, 0.0f);
			float start    = r.x + (r.width - icon_size) * 0.5f;
			if (expand > 0.0f)
			{
				float expanded_start = r.x + (float)ui::px(8);
				start = start + (expanded_start - start) * expand;
			}
			icons::draw(
				icon_for_command(def.id),
				{ .x = start, .y = r.y + (r.height - icon_size) * 0.5f, .width = icon_size, .height = icon_size },
				color
			);
			if (expand > 0.02f)
			{
				float label_x = start + icon_size + gap;
				float max_w   = r.x + r.width - (float)ui::px(8) - label_x;
				if (max_w > 0.0f)
				{
					String shown  = elide_text(font, label, button_text_size, max_w);
					RLColor faded = color;
					faded.a = (char)((float)((int)color.a & 0xFF) * expand);
					rl::draw_text_ex(
						font,
						(ZString)shown.ptr,
						{ label_x, r.y + (r.height - size[1]) * 0.5f },
						button_text_size,
						0.0f,
						faded
					);
				}
			}
			if (hovered) ui::tooltip_shortcut(label, def.shortcut);
		}
	}

	if (focused && self.selected >= 0 && self.selected < (int)commands::bar_command_count() && button_enabled(
		(usz)self.selected,
		has_project,
		has_buffer
	))
	{
		Rect selected_rect = self.button_rect_for(g_position, (usz)self.selected, screen_w, screen_h);
		ui::focus_ring(selected_rect);
	}

	if (horizontal)
	{
		self.draw_horizontal_status(
			has_project,
			project_name,
			mode,
			folder,
			zoom,
			lsp_status,
			errors,
			warnings,
			font,
			bar
		);
	}
	else
	{
		self.draw_vertical_status(
			has_project,
			project_name,
			mode,
			folder,
			zoom,
			lsp_status,
			errors,
			warnings,
			font,
			bar
		);
	}
}