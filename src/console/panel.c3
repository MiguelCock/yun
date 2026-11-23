module yun::console;

import raylib6::rl;
import std::core::dstring;
import std::math;
import yun::editor;
import yun::theme;
import yun::ui;

const float DEFAULT_HEIGHT = 220.0f;
const float MIN_HEIGHT     = 120.0f;
const float HEADER_HEIGHT  = 30.0f;
const float INPUT_HEIGHT   = 34.0f;
const float PADDING        = 8.0f;
const float RESIZE_GRAB    = 5.0f;
const float BUTTON_WIDTH   = 54.0f;
const float BUTTON_HEIGHT  = 22.0f;
const float BUTTON_GAP     = 6.0f;
const int BUTTON_COUNT     = 4;
const int SCROLL_LINES     = 3;

enum ConsoleButton : int
{
	RUN,
	KILL,
	CLEAR,
	COPY,
	COUNT,
}

struct ConsolePanel
{
	bool visible;
	bool focused;
	float height;
	int scroll;
	bool pinned;
	bool resizing;
	bool focus_requested;
	bool exit_requested;
	float input_scroll;
}

fn void ConsolePanel.init(&self)
{
	self.visible = false;
	self.focused = false;
	self.height = DEFAULT_HEIGHT;
	self.scroll = 0;
	self.pinned = true;
	self.resizing = false;
	self.focus_requested = false;
	self.exit_requested = false;
	self.input_scroll = 0.0f;
}

fn void ConsolePanel.open(&self)
{
	self.visible = true;
	self.focused = true;
	self.pinned = true;
	self.resizing = false;
	self.exit_requested = false;
}

fn void ConsolePanel.close(&self)
{
	self.visible = false;
	self.focused = false;
	self.resizing = false;
}

fn Rect console_panel_rect(float height, int screen_w, int screen_h)
{
	float h     = ui::pxf(height);
	float min_h = ui::pxf(MIN_HEIGHT);
	float max_h = (float)screen_h - ui::pxf(MIN_HEIGHT);
	if (h < min_h) h = min_h;
	if (h > max_h) h = max_h;
	if (h > (float)screen_h) h = (float)screen_h;
	return { .x = 0.0f, .y = (float)screen_h - h, .width = (float)screen_w, .height = h };
}

fn int console_max_scroll(int lines, int visible)
{
	int max = lines - visible;
	return max > 0 ? max : 0;
}

fn int console_clamp_scroll(int scroll, int lines, int visible)
{
	int max = console_max_scroll(lines, visible);
	if (scroll < 0) return 0;
	if (scroll > max) return max;
	return scroll;
}

fn String console_status_label(ConsoleStatus status)
{
	switch (status)
	{
		case ConsoleStatus.IDLE:
			return "Ready";
		case ConsoleStatus.RUNNING:
			return "Running";
		case ConsoleStatus.KILLING:
			return "Stopping";
		case ConsoleStatus.EXITED:
			return "Exit";
		case ConsoleStatus.KILLED:
			return "Killed";
		case ConsoleStatus.FAILED:
			return "Failed";
	}
}

fn Rect ConsolePanel.rect(&self)
{
	return console_panel_rect(self.height, rl::get_screen_width(), rl::get_screen_height());
}

fn bool ConsolePanel.contains_screen(&self, RLVector2 point)
{
	if (!self.visible) return false;
	Rect panel = self.rect();
	return point[0] >= panel.x && point[0] <= panel.x + panel.width && point[1] >= panel.y
		&& point[1] <= panel.y + panel.height;
}

fn Rect ConsolePanel.header_rect(&self)
{
	Rect panel = self.rect();
	return {
		.x = panel.x + ui::pxf(PADDING),
		.y = panel.y + ui::pxf(2.0f),
		.width = panel.width - ui::pxf(PADDING) * 2.0f,
		.height = ui::pxf(HEADER_HEIGHT),
	};
}

fn Rect ConsolePanel.output_rect(&self)
{
	Rect panel   = self.rect();
	float header = ui::pxf(HEADER_HEIGHT);
	float input  = ui::pxf(INPUT_HEIGHT);
	return {
		.x = panel.x,
		.y = panel.y + header,
		.width = panel.width,
		.height = panel.height - header - input,
	};
}

fn Rect ConsolePanel.input_rect(&self)
{
	Rect panel  = self.rect();
	float input = ui::pxf(INPUT_HEIGHT);
	return {
		.x = panel.x + ui::pxf(PADDING),
		.y = panel.y + panel.height - input,
		.width = panel.width - ui::pxf(PADDING) * 2.0f,
		.height = input - ui::pxf(PADDING) * 0.5f,
	};
}

fn Rect ConsolePanel.button_rect(&self, ConsoleButton button)
{
	Rect panel = self.rect();
	Rect input = self.input_rect();
	float bw   = ui::pxf(BUTTON_WIDTH);
	float bh   = ui::pxf(BUTTON_HEIGHT);
	float gap  = ui::pxf(BUTTON_GAP);
	float pad  = ui::pxf(PADDING);
	int index  = (int)button;
	return {
		.x = panel.x + panel.width - pad - bw - (float)index * (bw + gap),
		.y = input.y + (input.height - bh) / 2.0f,
		.width = bw,
		.height = bh,
	};
}

fn bool ConsolePanel.button_enabled(&self, ConsoleButton button, Console* console)
{
	switch (button)
	{
		case ConsoleButton.RUN:
			return !console.running() && console.input.len() > 0;
		case ConsoleButton.KILL:
			return console.running();
		case ConsoleButton.CLEAR:
		case ConsoleButton.COPY:
			return console.buffer.line_count() > 0;
		case ConsoleButton.COUNT:
			return false;
	}
}

fn int ConsolePanel.button_at(&self, RLVector2 point, Console* console)
{
	for (int i = 0; i < BUTTON_COUNT; i++)
	{
		ConsoleButton button = (ConsoleButton)i;
		if (!self.button_enabled(button, console)) continue;
		Rect r = self.button_rect(button);
		if (point[0] >= r.x && point[0] <= r.x + r.width && point[1] >= r.y && point[1] <= r.y + r.height) return i;
	}
	return -1;
}

fn int ConsolePanel.visible_rows(&self, EditorMetrics metrics)
{
	Rect output = self.output_rect();
	if (metrics.line_height <= 0.0f) return 1;
	int rows = (int)(output.height / metrics.line_height);
	return rows > 0 ? rows : 1;
}

fn int ConsolePanel.max_scroll(&self, Console* console, EditorMetrics metrics)
{
	return console_max_scroll((int)console.buffer.line_count(), self.visible_rows(metrics));
}

fn int ConsolePanel.scroll_for(&self, Console* console, EditorMetrics metrics)
{
	int lines   = (int)console.buffer.line_count();
	int visible = self.visible_rows(metrics);
	if (self.pinned) return console_max_scroll(lines, visible);
	return console_clamp_scroll(self.scroll, lines, visible);
}

fn void ConsolePanel.scroll_by(&self, Console* console, EditorMetrics metrics, int delta)
{
	int lines   = (int)console.buffer.line_count();
	int visible = self.visible_rows(metrics);
	int max     = console_max_scroll(lines, visible);
	if (self.pinned) self.scroll = max;
	self.scroll = console_clamp_scroll(self.scroll + delta, lines, visible);
	self.pinned = self.scroll >= max;
}

fn void ConsolePanel.copy_output(&self, Console* console)
{
	DString out;
	out.init(mem);
	for (sz i = 0; i < console.buffer.line_count(); i++)
	{
		ConsoleLine* line = console.buffer.line_at(i);
		out.append_string(line.text);
		out.append_char('\n');
	}
	rl::set_clipboard_text(out.zstr_view());
	out.free();
}

fn bool ctrl_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_CONTROL) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_CONTROL);
}

fn bool shift_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_SHIFT) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SHIFT);
}

fn bool super_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_SUPER) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SUPER);
}

fn void drain_chars()
{
	while (rl::get_char_pressed() != 0)
	{
	}
}

fn bool ConsolePanel.update_input(&self, Console* console, EditorMetrics metrics)
{
	if (!self.visible) return false;
	self.exit_requested = false;
	bool ctrl  = ctrl_down();
	bool shift = shift_down();
	bool super = super_down();

	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		drain_chars();
		self.exit_requested = true;
		return true;
	}

	if (ctrl && shift && rl::is_key_pressed(rl::RLKeyboardKey.C))
	{
		self.copy_output(console);
		drain_chars();
		return false;
	}
	if (ctrl && rl::is_key_pressed(rl::RLKeyboardKey.V))
	{
		String clip = rl::get_clipboard_text().str_view();
		usz end     = 0;
		while (end < clip.len && clip[end] != '\n' && clip[end] != '\r') end++;
		console.input.insert_string(clip[0:end]);
		drain_chars();
		return false;
	}
	if (ctrl && rl::is_key_pressed(rl::RLKeyboardKey.L))
	{
		console.clear();
		self.scroll = 0;
		self.pinned = true;
		drain_chars();
		return false;
	}
	if (ctrl && rl::is_key_pressed(rl::RLKeyboardKey.C))
	{
		if (console.running()) console.kill();
		drain_chars();
		return false;
	}

	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER) || rl::is_key_pressed(rl::RLKeyboardKey.KP_ENTER))
	{
		(void)console.submit();
		self.pinned = true;
		self.scroll = self.max_scroll(console, metrics);
		self.input_scroll = 0.0f;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.UP))
	{
		(void)console.history.previous(&console.input);
		self.input_scroll = 0.0f;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.DOWN))
	{
		(void)console.history.next(&console.input);
		self.input_scroll = 0.0f;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.LEFT) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.LEFT))
	{
		console.input.move_left();
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.RIGHT) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.RIGHT))
	{
		console.input.move_right();
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.HOME))
	{
		console.input.home();
		self.input_scroll = 0.0f;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.END))
	{
		console.input.end();
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.DELETE))
	{
		console.input.delete_forward();
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		console.input.backspace();
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_UP))
	{
		self.scroll_by(console, metrics, -self.visible_rows(metrics));
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_DOWN))
	{
		self.scroll_by(console, metrics, self.visible_rows(metrics));
	}

	if (!ctrl && !super)
	{
		int codepoint = rl::get_char_pressed();
		while (codepoint != 0)
		{
			console.input.insert_codepoint(codepoint);
			codepoint = rl::get_char_pressed();
		}
	}
	else
	{
		drain_chars();
	}
	return false;
}

fn void ConsolePanel.update_mouse(&self, Console* console, EditorMetrics metrics, RLVector2 mouse)
{
	self.focus_requested = false;
	if (!self.visible) return;
	Rect panel  = self.rect();
	Rect input  = self.input_rect();
	Rect output = self.output_rect();

	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		if (mouse[1] >= panel.y && mouse[1] <= panel.y + ui::pxf(RESIZE_GRAB))
		{
			self.resizing = true;
		}
		else
		{
			int button = self.button_at(mouse, console);
			if (button >= 0)
			{
				switch ((ConsoleButton)button)
				{
					case ConsoleButton.RUN:
						(void)console.submit();
						self.pinned = true;
						self.input_scroll = 0.0f;
						break;
					case ConsoleButton.KILL:
						console.kill();
						break;
					case ConsoleButton.CLEAR:
						console.clear();
						self.scroll = 0;
						self.pinned = true;
						break;
					case ConsoleButton.COPY:
						self.copy_output(console);
						break;
					case ConsoleButton.COUNT:
						break;
				}
				self.focus_requested = true;
			}
			else if (mouse[0] >= panel.x && mouse[0] <= panel.x + panel.width && mouse[1] >= panel.y
				&& mouse[1] <= panel.y + panel.height)
			{
				self.focus_requested = true;
			}
		}
	}

	if (self.resizing)
	{
		if (rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
		{
			float height = ((float)rl::get_screen_height() - mouse[1]) / ui::scale();
			float max    = (float)rl::get_screen_height() / ui::scale() - MIN_HEIGHT;
			if (max < MIN_HEIGHT) max = MIN_HEIGHT;
			self.height = math::clamp(height, MIN_HEIGHT, max);
		}
		else
		{
			self.resizing = false;
		}
	}

	if (mouse[0] >= output.x && mouse[0] <= output.x + output.width && mouse[1] >= output.y
		&& mouse[1] <= output.y + output.height)
	{
		float wheel = rl::get_mouse_wheel_move();
		if (wheel != 0.0f) self.scroll_by(console, metrics, -(int)(wheel * (float)SCROLL_LINES));
	}
	if (mouse[1] >= panel.y && mouse[1] <= panel.y + ui::pxf(
		RESIZE_GRAB
	) && mouse[0] >= panel.x && mouse[0] <= panel.x + panel.width)
	{
		ui::request_cursor(rl::RLMouseCursor.RESIZE_NS, 4);
	}
}

fn RLColor console_line_color(ConsoleStream stream)
{
	switch (stream)
	{
		case ConsoleStream.COMMAND:
			return theme::current().panel_header;
		case ConsoleStream.STDERR:
			return theme::current().diag_error;
		case ConsoleStream.STDOUT:
			return theme::current().panel_text;
	}
}

fn void draw_button(RLFont font, Rect r, String label, bool enabled, bool hovered)
{
	RLColor bg = hovered && enabled ? theme::current().topbar_hover : theme::current().panel_field;
	ui::row(r, bg);
	float size     = (float)ui::tpx(13);
	RLVector2 text = rl::measure_text_ex(font, (ZString)label.ptr, size, 0.0f);
	RLColor color  = enabled ? theme::current().panel_text : theme::current().panel_disabled;
	rl::draw_text_ex(
		font,
		(ZString)label.ptr,
		{ r.x + (r.width - text[0]) / 2.0f, r.y + (r.height - text[1]) / 2.0f },
		size,
		0.0f,
		color
	);
}

fn String button_label(ConsoleButton button)
{
	switch (button)
	{
		case ConsoleButton.RUN:
			return "Run";
		case ConsoleButton.KILL:
			return "Kill";
		case ConsoleButton.CLEAR:
			return "Clear";
		case ConsoleButton.COPY:
			return "Copy";
		case ConsoleButton.COUNT:
			return "";
	}
}

fn void ConsolePanel.draw(&self, Console* console, RLFont font, RLFont editor_font, EditorMetrics metrics)
{
	if (!self.visible) return;
	Rect panel  = self.rect();
	Rect header = self.header_rect();
	Rect output = self.output_rect();
	Rect input  = self.input_rect();

	float radius = ui::corner_radius();
	ui::rounded_top(panel, radius, theme::current().panel_bg);
	RLColor border = self.focused ? theme::current().card_focus : theme::current().panel_border;
	rl::draw_rectangle_rec(
		{ .x = panel.x + radius, .y = panel.y, .width = panel.width - radius * 2.0f, .height = 1.0f },
		border
	);
	rl::draw_rectangle_rec(
		{ .x = panel.x, .y = panel.y + radius, .width = 1.0f, .height = panel.height - radius },
		border
	);
	rl::draw_rectangle_rec(
		{ .x = panel.x + panel.width - 1.0f, .y = panel.y + radius, .width = 1.0f, .height = panel.height - radius },
		border
	);
	rl::draw_rectangle_rec(
		{
			.x = panel.x + panel.width / 2.0f - ui::pxf(18.0f),
			.y = panel.y + ui::pxf(2.0f),
			.width = ui::pxf(36.0f),
			.height = 2.0f
		},
		theme::current()
		.panel_dim);

	float title_size = (float)ui::tpx(14);
	rl::draw_text_ex(
		font,
		"Console",
		{ header.x, header.y + (header.height - title_size) / 2.0f },
		title_size,
		0.0f,
		theme::current()
		.panel_header);

	float status_size    = (float)ui::tpx(13);
	RLColor status_color = theme::current().panel_dim;
	if (console.runner.status == ConsoleStatus.RUNNING || console.runner.status == ConsoleStatus.KILLING)
	{
		status_color = theme::current().diag_warning;
	}
	else if (console.runner.status == ConsoleStatus.FAILED
		|| (console.runner.status == ConsoleStatus.EXITED && console.runner.exit_code != 0))
	{
		status_color = theme::current().diag_error;
	}
	@pool()
	{
		String status = console_status_label(console.runner.status);
		if (console.runner.status == ConsoleStatus.EXITED)
		{
			status = string::format(tmem, "Exit %d", console.runner.exit_code);
		}
		if (console.buffer.truncated)
		{
			status = string::format(tmem, "%s  (truncated)", status);
		}
		RLVector2 status_measure = rl::measure_text_ex(font, (ZString)status.ptr, status_size, 0.0f);
		rl::draw_text_ex(
			font,
			(ZString)status.ptr,
			{ header.x + header.width - status_measure[0], header.y + (header.height - status_size) / 2.0f },
			status_size,
			0.0f,
			status_color
		);
	};

	int scroll  = self.scroll_for(console, metrics);
	int visible = self.visible_rows(metrics);
	rl::begin_scissor_mode((int)output.x, (int)output.y, (int)output.width, (int)output.height);
	for (int i = 0; i < visible; i++)
	{
		sz index = (sz)scroll + (sz)i;
		if (index >= console.buffer.line_count()) break;
		ConsoleLine* line = console.buffer.line_at(index);
		float y           = output.y + (float)i * metrics.line_height;
		rl::draw_text_ex(
			editor_font,
			(ZString)line.text.ptr,
			{ output.x + ui::pxf(PADDING), y },
			metrics.font_size,
			0.0f,
			console_line_color(line.stream)
		);
	}
	rl::end_scissor_mode();

	int max_scroll = console_max_scroll((int)console.buffer.line_count(), visible);
	if (max_scroll > 0)
	{
		float track_x = panel.x + panel.width - ui::pxf(5.0f);
		float track_y = output.y + ui::pxf(2.0f);
		float track_h = output.height - ui::pxf(4.0f);
		float thumb_h = track_h * (float)visible / (float)(visible + max_scroll);
		if (thumb_h < ui::pxf(24.0f)) thumb_h = ui::pxf(24.0f);
		float thumb_y = track_y;
		if (max_scroll > 0) thumb_y += (track_h - thumb_h) * (float)scroll / (float)max_scroll;
		rl::draw_rectangle_rec(
			{ .x = track_x, .y = track_y, .width = ui::pxf(3.0f), .height = track_h },
			theme::current()
			.editor_scrollbar);
		rl::draw_rectangle_rec(
			{ .x = track_x, .y = thumb_y, .width = ui::pxf(3.0f), .height = thumb_h },
			theme::current()
			.panel_dim);
	}

	ui::row(input, theme::current().panel_field);
	float prompt_size = (float)ui::tpx(14);
	rl::draw_text_ex(
		font,
		">",
		{ input.x + ui::pxf(PADDING), input.y + (input.height - prompt_size) / 2.0f },
		prompt_size,
		0.0f,
		theme::current()
		.panel_header);

	float button_space = (float)BUTTON_COUNT * ui::pxf(BUTTON_WIDTH) + (float)(BUTTON_COUNT - 1) * ui::pxf(BUTTON_GAP);
	Rect text_rect = {
		.x = input.x + ui::pxf(PADDING) + ui::pxf(14.0f),
		.y = input.y,
		.width = input.width - ui::pxf(PADDING) * 2.0f - ui::pxf(14.0f) - button_space,
		.height = input.height,
	};
	if (text_rect.width < ui::pxf(40.0f)) text_rect.width = ui::pxf(40.0f);

	String view      = console.input.text_view();
	float cursor_x   = 0.0f;
	float text_width = 0.0f;
	@pool()
	{
		String prefix    = view[0:(usz)console.input.cursor];
		ZString prefix_z = prefix.zstr_tcopy();
		ZString view_z   = view.zstr_tcopy();
		cursor_x = rl::measure_text_ex(editor_font, prefix_z, metrics.font_size, 0.0f)[0];
		text_width = rl::measure_text_ex(editor_font, view_z, metrics.font_size, 0.0f)[0];
	};
	if (cursor_x - self.input_scroll > text_rect.width - ui::pxf(2.0f))
	{
		self.input_scroll = cursor_x - text_rect.width + ui::pxf(2.0f);
	}
	if (cursor_x - self.input_scroll < 0.0f) self.input_scroll = cursor_x;
	if (text_width <= text_rect.width) self.input_scroll = 0.0f;

	rl::begin_scissor_mode((int)text_rect.x, (int)text_rect.y, (int)text_rect.width, (int)text_rect.height);
	float text_y = input.y + (input.height - metrics.font_size) / 2.0f;
	rl::draw_text_ex(
		editor_font,
		console.input.zstr_view(),
		{ text_rect.x - self.input_scroll, text_y },
		metrics.font_size,
		0.0f,
		theme::current()
		.panel_text);
	float caret_x = text_rect.x - self.input_scroll + cursor_x;
	rl::draw_rectangle_rec(
		{ .x = caret_x, .y = input.y + ui::pxf(6.0f), .width = 1.0f, .height = input.height - ui::pxf(12.0f) },
		theme::current()
		.panel_caret);
	rl::end_scissor_mode();

	RLVector2 mouse = rl::get_mouse_position();
	for (int i = 0; i < BUTTON_COUNT; i++)
	{
		ConsoleButton button = (ConsoleButton)i;
		Rect r               = self.button_rect(button);
		bool hovered         = mouse[0] >= r.x && mouse[0] <= r.x + r.width && mouse[1] >= r.y
			&& mouse[1] <= r.y + r.height;
		draw_button(font, r, button_label(button), self.button_enabled(button, console), hovered);
	}
}