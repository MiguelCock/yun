module yun::topbar;

import raylib6::rl;
import std::math;
import yun::commands;

const float TOP_BAR_HEIGHT    = 34.0f;
const float BUTTON_WIDTH      = 72.0f;
const float BUTTON_HEIGHT     = 24.0f;
const float BUTTON_GAP        = 8.0f;
const float PADDING_X         = 8.0f;
const float PADDING_Y         = 5.0f;
const RLColor TOPBAR_BG       = { 30, 32, 40, 255 };
const RLColor TOPBAR_BORDER   = { 60, 66, 80, 255 };
const RLColor TOPBAR_BUTTON   = { 48, 52, 64, 255 };
const RLColor TOPBAR_HOVER    = { 64, 72, 92, 255 };
const RLColor TOPBAR_TEXT     = { 220, 224, 232, 255 };
const RLColor TOPBAR_DISABLED = { 110, 116, 128, 255 };
const RLColor TOPBAR_NAME     = { 180, 200, 230, 255 };
const RLColor TOPBAR_ERROR    = { 240, 110, 110, 255 };
const RLColor TOPBAR_WARNING  = { 230, 190, 80, 255 };

struct TopBar
{
	int active;
}

fn Rect topbar_rect()
{
	return { .x = 0.0f, .y = 0.0f, .width = (float)rl::get_screen_width(), .height = TOP_BAR_HEIGHT };
}

fn bool contains_screen(RLVector2 screen)
{
	return screen[0] >= 0.0f && screen[1] >= 0.0f && screen[1] <= TOP_BAR_HEIGHT;
}

fn Rect button_rect(usz index)
{
	return {
		.x = PADDING_X + (float)index * (BUTTON_WIDTH + BUTTON_GAP),
		.y = PADDING_Y,
		.width = BUTTON_WIDTH,
		.height = BUTTON_HEIGHT,
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
}

fn int TopBar.update(&self, RLVector2 screen, bool has_project, bool has_buffer)
{
	if (!contains_screen(screen))
	{
		self.active = -1;
		return -1;
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
	return (TOP_BAR_HEIGHT - text_height) / 2.0f;
}

fn void TopBar.draw(
	&self,
	bool has_project,
	bool has_buffer,
	String project_name,
	float zoom,
	String lsp_status,
	int errors,
	int warnings,
	RLFont font
)
{
	(void)self;
	Rect bar = topbar_rect();
	rl::draw_rectangle_rec(bar, TOPBAR_BG);
	rl::draw_line(0, (int)TOP_BAR_HEIGHT, rl::get_screen_width(), (int)TOP_BAR_HEIGHT, TOPBAR_BORDER);

	RLVector2 mouse = rl::get_mouse_position();
	for (usz i = 0; i < commands::bar_command_count(); i++)
	{
		CommandDef def = commands::bar_command(i);
		bool enabled   = commands::command_enabled(def.id, has_project, has_buffer);
		Rect r         = button_rect(i);
		bool hovered   = mouse[0] >= r.x && mouse[0] <= r.x + r.width && mouse[1] >= r.y && mouse[1] <= r.y + r.height;
		rl::draw_rectangle_rec(r, hovered && enabled ? TOPBAR_HOVER : TOPBAR_BUTTON);
		RLVector2 size = rl::measure_text_ex(font, (ZString)def.label.ptr, 16.0f, 0.0f);
		rl::draw_text_ex(
			font,
			(ZString)def.label.ptr,
			{ r.x + (r.width - size[0]) / 2.0f, r.y + (r.height - size[1]) / 2.0f },
			16.0f,
			0.0f,
			enabled ? TOPBAR_TEXT : TOPBAR_DISABLED
		);
	}

	float name_x = PADDING_X + (float)commands::bar_command_count() * (BUTTON_WIDTH + BUTTON_GAP) + 12.0f;
	if (has_project && project_name.len > 0)
	{
		rl::draw_text_ex(font, (ZString)project_name.ptr, { name_x, bar_text_y(16.0f) }, 16.0f, 0.0f, TOPBAR_NAME);
	}

	@pool()
	{
		String label   = string::format(tmem, "%d%%", (int)(zoom * 100.0f));
		RLVector2 size = rl::measure_text_ex(font, (ZString)label.ptr, 16.0f, 0.0f);
		float zoom_x   = (float)rl::get_screen_width() - 12.0f - size[0];
		rl::draw_text_ex(font, (ZString)label.ptr, { zoom_x, bar_text_y(16.0f) }, 16.0f, 0.0f, TOPBAR_NAME);

		float cursor_x = zoom_x;
		if (lsp_status.len > 0)
		{
			RLVector2 lsp_size = rl::measure_text_ex(font, (ZString)lsp_status.ptr, 16.0f, 0.0f);
			cursor_x -= 24.0f + lsp_size[0];
			rl::draw_text_ex(
				font,
				(ZString)lsp_status.ptr,
				{ cursor_x, bar_text_y(16.0f) },
				16.0f,
				0.0f,
				TOPBAR_DISABLED
			);
		}
		if (errors > 0 || warnings > 0)
		{
			String counts        = string::format(tmem, "E%d W%d", errors, warnings);
			RLVector2 count_size = rl::measure_text_ex(font, (ZString)counts.ptr, 16.0f, 0.0f);
			cursor_x -= 24.0f + count_size[0];
			rl::draw_text_ex(
				font,
				(ZString)counts.ptr,
				{ cursor_x, bar_text_y(16.0f) },
				16.0f,
				0.0f,
				errors > 0 ? TOPBAR_ERROR : TOPBAR_WARNING
			);
		}
	};
}