module yun::prompt;

import raylib6::rl;
import std::math;
import yun::commands;
import yun::keymap;
import yun::theme;
import yun::ui;

const int PROMPT_WIDTH  = 440;
const int PROMPT_HEIGHT = 100;
const int PROMPT_MAX    = 120;

struct Prompt
{
	bool open;
	String title;
	char[PROMPT_MAX + 1] text;
	int len;
	bool consumed;
}

fn void Prompt.init(&self)
{
	self.open = false;
	self.title = "";
	self.len = 0;
	self.consumed = false;
}

fn void Prompt.open_with(&self, String title, String default_text)
{
	self.title = title;
	self.len = 0;
	for (usz i = 0; i < default_text.len && self.len < PROMPT_MAX; i++)
	{
		self.text[self.len] = default_text[i];
		self.len++;
	}
	self.text[self.len] = 0;
	self.open = true;
}

fn void Prompt.close(&self)
{
	self.open = false;
}

fn String Prompt.text_view(&self)
{
	return (String)self.text[0:self.len];
}

fn bool Prompt.append_codepoint(&self, int codepoint)
{
	if (codepoint < 32 || codepoint > 0x10FFFF) return false;

	char[4] encoded;
	int count = 0;
	if (codepoint < 0x80)
	{
		encoded[0] = (char)codepoint;
		count = 1;
	}
	else if (codepoint < 0x800)
	{
		encoded[0] = (char)(0xC0 | (codepoint >> 6));
		encoded[1] = (char)(0x80 | (codepoint & 0x3F));
		count = 2;
	}
	else if (codepoint < 0x10000)
	{
		encoded[0] = (char)(0xE0 | (codepoint >> 12));
		encoded[1] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
		encoded[2] = (char)(0x80 | (codepoint & 0x3F));
		count = 3;
	}
	else
	{
		encoded[0] = (char)(0xF0 | (codepoint >> 18));
		encoded[1] = (char)(0x80 | ((codepoint >> 12) & 0x3F));
		encoded[2] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
		encoded[3] = (char)(0x80 | (codepoint & 0x3F));
		count = 4;
	}

	if (self.len + count > PROMPT_MAX) return false;
	for (int i = 0; i < count; i++)
	{
		self.text[self.len] = encoded[i];
		self.len++;
	}
	self.text[self.len] = 0;
	return true;
}

fn void Prompt.backspace(&self)
{
	if (self.len == 0) return;
	self.len--;
	while (self.len > 0 && (self.text[self.len] & 0xC0) == 0x80)
	{
		self.len--;
	}
	self.text[self.len] = 0;
}

fn Rect Prompt.panel_rect(&self)
{
	int width  = ui::px(PROMPT_WIDTH);
	int height = ui::px(PROMPT_HEIGHT);
	int x      = (rl::get_screen_width() - width) / 2;
	int y      = (rl::get_screen_height() - height) / 2;
	return { .x = (float)x, .y = (float)y, .width = (float)width, .height = (float)height };
}

fn bool Prompt.update(&self, keymap::Keymap* keymap)
{
	if (!self.open) return false;
	self.consumed = false;

	if (keymap.pressed((int)commands::CommandId.OVERLAY_CLOSE, commands::CTX_PROMPT))
	{
		self.consumed = true;
		self.open = false;
		return false;
	}
	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		Rect panel      = self.panel_rect();
		RLVector2 mouse = rl::get_mouse_position();
		if (mouse[0] < panel.x || mouse[0] > panel.x + panel.width || mouse[1] < panel.y
			|| mouse[1] > panel.y + panel.height)
		{
			self.open = false;
			return false;
		}
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE)) self.backspace();
	if (keymap.pressed((int)commands::CommandId.LIST_ACCEPT, commands::CTX_PROMPT))
	{
		self.consumed = true;
		return true;
	}

	int codepoint = rl::get_char_pressed();
	while (codepoint != 0)
	{
		self.append_codepoint(codepoint);
		codepoint = rl::get_char_pressed();
	}
	return false;
}

fn void Prompt.draw(&self, RLFont font)
{
	if (!self.open) return;

	Rect panel      = self.panel_rect();
	float pad       = (float)ui::px(12);
	float text_size = (float)ui::px(16);
	float hint_size = (float)ui::px(14);
	rl::draw_rectangle_rec(panel, theme::current().panel_bg);
	rl::draw_rectangle_lines_ex(panel, 1.0f, theme::current().panel_border);

	Rect field = {
		.x = panel.x + pad,
		.y = panel.y + (float)ui::px(36),
		.width = panel.width - pad * 2.0f,
		.height = (float)ui::px(28),
	};
	rl::draw_rectangle_rec(field, theme::current().panel_field);

	String text = self.text_view();
	@pool()
	{
		rl::draw_text_ex(
			font,
			self.title.zstr_tcopy(),
			{ panel.x + pad, panel.y + (float)ui::px(8) },
			text_size,
			0.0f,
			theme::current()
			.panel_header);
		float tx = panel.x + (float)ui::px(18);
		float ty = panel.y + (float)ui::px(42);
		rl::draw_text_ex(font, text.zstr_tcopy(), { tx, ty }, text_size, 0.0f, theme::current().panel_text);
		float width = rl::measure_text_ex(font, text.zstr_tcopy(), text_size, 0.0f)[0];
		rl::draw_rectangle((int)(tx + width + 1.0f), (int)ty, 2, ui::px(16), theme::current().panel_caret);
	};
	rl::draw_text_ex(
		font,
		"Enter: create    Esc: cancel",
		{ panel.x + pad, panel.y + panel.height - (float)ui::px(22) },
		hint_size,
		0.0f,
		theme::current()
		.panel_dim);
}