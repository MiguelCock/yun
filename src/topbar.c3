module yun::topbar;

import raylib6::rl;
import std::math;
import yun::commands;
import yun::theme;
import yun::ui;

const float TOP_BAR_HEIGHT = 34.0f;
const float BUTTON_WIDTH   = 88.0f;
const float BUTTON_HEIGHT  = 24.0f;
const float BUTTON_GAP     = 8.0f;
const float PADDING_X      = 8.0f;
const float PADDING_Y      = 5.0f;

struct TopBar
{
	int active;
	int selected;
	Rect counter_hit;
}

fn Rect topbar_rect()
{
	return { .x = 0.0f, .y = 0.0f, .width = (float)rl::get_screen_width(), .height = ui::pxf(TOP_BAR_HEIGHT) };
}

fn bool contains_screen(RLVector2 screen)
{
	return screen[0] >= 0.0f && screen[1] >= 0.0f && screen[1] <= ui::pxf(TOP_BAR_HEIGHT);
}

fn Rect button_rect(usz index)
{
	return {
		.x = ui::pxf(PADDING_X) + (float)index * (ui::pxf(BUTTON_WIDTH) + ui::pxf(BUTTON_GAP)),
		.y = ui::pxf(PADDING_Y),
		.width = ui::pxf(BUTTON_WIDTH),
		.height = ui::pxf(BUTTON_HEIGHT),
	};
}

fn int hit_button(RLVector2 screen, bool has_project, bool has_buffer)
{
	for (usz i = 0; i < commands::bar_command_count(); i++)
	{
		CommandDef def = commands::bar_command(i);
		if (!commands::command_enabled(def.id, has_project, has_buffer)) continue;
		Rect r = button_rect(i);
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
		self.active = hit_button(screen, has_project, has_buffer);
	}
	if (rl::is_mouse_button_released(rl::RLMouseButton.LEFT))
	{
		int index  = hit_button(screen, has_project, has_buffer);
		int active = self.active;
		self.active = -1;
		if (index >= 0 && index == active) return index;
	}
	return -1;
}

fn float bar_text_y(float text_height)
{
	return (ui::pxf(TOP_BAR_HEIGHT) - text_height) / 2.0f;
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
	Rect bar        = topbar_rect();
	float text_size = (float)ui::tpx(16);
	rl::draw_rectangle_rec(bar, theme::current().topbar_bg);
	rl::draw_line(
		0,
		(int)ui::pxf(TOP_BAR_HEIGHT),
		rl::get_screen_width(),
		(int)ui::pxf(TOP_BAR_HEIGHT),
		theme::current()
		.topbar_border);

	RLVector2 mouse = rl::get_mouse_position();
	for (usz i = 0; i < commands::bar_command_count(); i++)
	{
		CommandDef def = commands::bar_command(i);
		bool enabled   = commands::command_enabled(def.id, has_project, has_buffer);
		Rect r         = button_rect(i);
		bool hovered   = mouse[0] >= r.x && mouse[0] <= r.x + r.width && mouse[1] >= r.y && mouse[1] <= r.y + r.height;
		rl::draw_rectangle_rec(r, hovered && enabled ? theme::current().topbar_hover : theme::current().topbar_button);
		String label   = def.label;
		RLVector2 size = rl::measure_text_ex(font, (ZString)label.ptr, text_size, 0.0f);
		rl::draw_text_ex(
			font,
			(ZString)label.ptr,
			{ r.x + (r.width - size[0]) / 2.0f, r.y + (r.height - size[1]) / 2.0f },
			text_size,
			0.0f,
			enabled ? theme::current()
			.topbar_text : theme::current().topbar_disabled);
	}

	float name_x = ui::pxf(
		PADDING_X
	) + (float)commands::bar_command_count() * (ui::pxf(BUTTON_WIDTH) + ui::pxf(BUTTON_GAP)) + (float)ui::px(12);
	if (focused && self.selected >= 0 && self.selected < (int)commands::bar_command_count() && button_enabled(
		(usz)self.selected,
		has_project,
		has_buffer
	))
	{
		rl::draw_rectangle_lines_ex(button_rect((usz)self.selected), 2.0f, theme::current().card_focus);
	}
	@pool()
	{
		String zoom_label = string::format(tmem, "%d%%", (int)(zoom * 100.0f));
		float zoom_width  = rl::measure_text_ex(font, (ZString)zoom_label.ptr, text_size, 0.0f)[0];
		float zoom_x      = (float)rl::get_screen_width() - (float)ui::px(12) - zoom_width;
		float right_start = zoom_x;

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
					{ name_x, bar_text_y(text_size) },
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
						rl::draw_text_ex(
							font,
							(ZString)mode.ptr,
							{ status_x, bar_text_y(text_size) },
							text_size,
							0.0f,
							theme::current()
							.topbar_name);
						float mode_width = rl::measure_text_ex(font, (ZString)mode.ptr, text_size, 0.0f)[0];
						float folder_x   = status_x + mode_width + (float)ui::px(12);
						float folder_max = right_start - folder_x - (float)ui::px(12);
						if (folder.len > 0 && folder_max > 0.0f)
						{
							String shown = elide_text(font, folder, text_size, folder_max);
							if (shown.len > 0)
							{
								rl::draw_text_ex(
									font,
									(ZString)shown.ptr,
									{ folder_x, bar_text_y(text_size) },
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

		rl::draw_text_ex(
			font,
			(ZString)zoom_label.ptr,
			{ zoom_x, bar_text_y(text_size) },
			text_size,
			0.0f,
			theme::current()
			.topbar_name);

		float cursor_x = zoom_x;
		self.counter_hit = { };
		if (lsp_status.len > 0)
		{
			cursor_x -= (float)ui::px(24) + lsp_width;
			rl::draw_text_ex(
				font,
				(ZString)lsp_status.ptr,
				{ cursor_x, bar_text_y(text_size) },
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
				{ cursor_x, bar_text_y(text_size) },
				text_size,
				0.0f,
				errors > 0 ? theme::current()
				.topbar_error : theme::current().topbar_warning);
			self.counter_hit = {
				.x = cursor_x,
				.y = bar_text_y(text_size),
				.width = counts_size,
				.height = text_size,
			};
		}
	};
}