module yun::prompt;

import raylib6::rl;
import std::math;

const int PROMPT_WIDTH      = 440;
const int PROMPT_HEIGHT     = 100;
const int PROMPT_MAX        = 120;
const RLColor PROMPT_BG     = { 24, 26, 34, 245 };
const RLColor PROMPT_BORDER = { 90, 110, 150, 255 };
const RLColor PROMPT_TITLE  = { 180, 200, 230, 255 };
const RLColor PROMPT_TEXT   = { 240, 240, 245, 255 };
const RLColor PROMPT_FIELD  = { 16, 18, 24, 255 };
const RLColor PROMPT_CURSOR = { 240, 240, 240, 255 };
const RLColor PROMPT_HINT   = { 140, 150, 170, 255 };

struct Prompt
{
	bool open;
	String title;
	char[PROMPT_MAX + 1] text;
	int len;
}

fn void Prompt.init(&self)
{
	self.open = false;
	self.title = "";
	self.len = 0;
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
	int x = (rl::get_screen_width() - PROMPT_WIDTH) / 2;
	int y = (rl::get_screen_height() - PROMPT_HEIGHT) / 2;
	return { .x = (float)x, .y = (float)y, .width = (float)PROMPT_WIDTH, .height = (float)PROMPT_HEIGHT };
}

fn bool Prompt.update(&self)
{
	if (!self.open) return false;

	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
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
	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER)) return true;

	int codepoint = rl::get_char_pressed();
	while (codepoint != 0)
	{
		self.append_codepoint(codepoint);
		codepoint = rl::get_char_pressed();
	}
	return false;
}

fn void Prompt.draw(&self)
{
	if (!self.open) return;

	Rect panel = self.panel_rect();
	int x      = (int)panel.x;
	int y      = (int)panel.y;
	rl::draw_rectangle(x, y, PROMPT_WIDTH, PROMPT_HEIGHT, PROMPT_BG);
	rl::draw_rectangle_lines(x, y, PROMPT_WIDTH, PROMPT_HEIGHT, PROMPT_BORDER);
	rl::draw_text((ZString)self.title.ptr, x + 12, y + 8, 16, PROMPT_TITLE);

	Rect field = {
		.x = (float)(x + 12),
		.y = (float)(y + 36),
		.width = (float)(PROMPT_WIDTH - 24),
		.height = 28.0f,
	};
	rl::draw_rectangle_rec(field, PROMPT_FIELD);

	String text = self.text_view();
	rl::draw_text((ZString)text.ptr, x + 18, y + 42, 16, PROMPT_TEXT);
	int width = rl::measure_text((ZString)text.ptr, 16);
	rl::draw_rectangle(x + 18 + width + 1, y + 42, 2, 16, PROMPT_CURSOR);
	rl::draw_text("Enter: create    Esc: cancel", x + 12, y + PROMPT_HEIGHT - 22, 14, PROMPT_HINT);
}