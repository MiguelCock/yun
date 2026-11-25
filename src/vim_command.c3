module yun::vim_command;

import raylib6::rl;
import std::collections::list;
import std::math::geometry;
import std::core::mem::alloc;
import yun::theme;
import yun::topbar;
import yun::ui;

const int FIELD_MAX   = 256;
const int HISTORY_MAX = 50;
const int LINE_HEIGHT = 34;

enum Kind : int
{
	NONE,
	WRITE,
	QUIT,
	WRITE_QUIT,
	EDIT,
	UNKNOWN,
}

struct Command
{
	Kind kind;
	String arg;
}

struct CommandLine
{
	Allocator allocator;
	bool open;
	char[FIELD_MAX + 1] text;
	int len;
	List{String} history;
	int history_index;
}

fn void CommandLine.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.open = false;
	self.len = 0;
	self.text[0] = 0;
	self.history.init(allocator);
	self.history_index = 0;
}

fn void CommandLine.destroy(&self)
{
	for (sz i = 0; i < self.history.len(); i++) self.history[i].free(self.allocator);
	self.history.free();
}

fn void CommandLine.show(&self)
{
	self.open = true;
	self.len = 0;
	self.text[0] = 0;
	self.history_index = (int)self.history.len();
}

fn void CommandLine.close(&self)
{
	self.open = false;
}

fn String CommandLine.text_view(&self)
{
	return (String)self.text[0:self.len];
}

fn void CommandLine.set_text(&self, String text)
{
	usz count = text.len > FIELD_MAX ? FIELD_MAX : text.len;
	for (usz i = 0; i < count; i++) self.text[i] = text[i];
	self.len = (int)count;
	self.text[count] = 0;
}

fn void CommandLine.append(&self, int codepoint)
{
	if (codepoint < 32 || codepoint > 126 || self.len >= FIELD_MAX) return;
	self.text[self.len] = (char)codepoint;
	self.len++;
	self.text[self.len] = 0;
}

fn void CommandLine.backspace(&self)
{
	if (self.len == 0) return;
	self.len--;
	self.text[self.len] = 0;
}

fn void CommandLine.add_history(&self, String text)
{
	if (text.len == 0) return;
	if (self.history.len() > 0 && self.history[self.history.len() - 1].compare_to(text) == 0) return;
	if (self.history.len() >= HISTORY_MAX)
	{
		self.history[0].free(self.allocator);
		self.history.remove_at(0);
	}
	self.history.push(text.copy(self.allocator));
}

fn void CommandLine.history_prev(&self)
{
	if (self.history.len() == 0) return;
	if (self.history_index > (int)self.history.len() - 1)
	{
		self.history_index = (int)self.history.len() - 1;
	}
	else if (self.history_index > 0)
	{
		self.history_index--;
	}
	self.set_text(self.history[self.history_index]);
}

fn void CommandLine.history_next(&self)
{
	if (self.history_index >= (int)self.history.len() - 1)
	{
		self.history_index = (int)self.history.len();
		self.len = 0;
		self.text[0] = 0;
		return;
	}
	self.history_index++;
	self.set_text(self.history[self.history_index]);
}

fn bool CommandLine.update(&self, bool* submitted)
{
	*submitted = false;
	if (!self.open) return false;

	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		self.close();
		return true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.UP))
	{
		self.history_prev();
		return true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.DOWN))
	{
		self.history_next();
		return true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		self.backspace();
		return true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER) || rl::is_key_pressed(rl::RLKeyboardKey.KP_ENTER))
	{
		*submitted = true;
		return true;
	}

	int codepoint = rl::get_char_pressed();
	while (codepoint != 0)
	{
		self.append(codepoint);
		codepoint = rl::get_char_pressed();
	}
	return true;
}

fn Rect CommandLine.panel_rect(&self)
{
	Rect content = topbar::content_rect();
	float height = (float)ui::px(LINE_HEIGHT);
	return {
		.x = content.x + (float)ui::px(12),
		.y = content.y + content.height - height - (float)ui::px(12),
		.width = content.width - (float)ui::px(24),
		.height = height,
	};
}

fn void CommandLine.draw(&self, RLFont font, String prefix)
{
	if (!self.open) return;
	Rect rect = self.panel_rect();
	ui::panel(rect, theme::current().panel_bg, theme::current().panel_border);
	float pad = (float)ui::px(10);
	@pool()
	{
		String line = string::format(tmem, "%s%s", prefix, self.text_view());
		rl::draw_text_ex(
			font,
			line.zstr_tcopy(),
			{ rect.x + pad, rect.y + (rect.height - (float)ui::tpx(16)) * 0.5f },
			(float)ui::tpx(16),
			0.0f,
			theme::current()
			.panel_text);
	};
	float caret_x = rect.x + pad + rl::measure_text_ex(font, self.text_view()
		.zstr_tcopy(), (float)ui::tpx(16), 0.0f)[0];
	if (rl::get_time() - (double)((long)rl::get_time()) < 0.5)
	{
		rl::draw_rectangle(
			(int)caret_x,
			(int)(rect.y + (rect.height - (float)ui::tpx(16)) * 0.5f),
			2,
			(int)ui::tpx(16),
			theme::current()
			.panel_caret);
	}
}

fn String trim_spaces(String text)
{
	usz start = 0;
	usz end   = text.len;
	while (start < end && (text[start] == ' ' || text[start] == '\t')) start++;
	while (end > start && (text[end - 1] == ' ' || text[end - 1] == '\t')) end--;
	return text[start:end - start];
}

fn Command parse_command(String line, Allocator allocator)
{
	String text = trim_spaces(line);
	if (text.len == 0) return { .kind = Kind.NONE, .arg = "" };

	usz split = text.len;
	for (usz i = 0; i < text.len; i++)
	{
		if (text[i] == ' ' || text[i] == '\t')
		{
			split = i;
			break;
		}
	}
	String name = text[0:split];
	String arg  = split < text.len ? trim_spaces(text[split:text.len - split]) : "";
	Kind kind   = Kind.UNKNOWN;
	if (name.compare_to("w") == 0 || name.compare_to("write") == 0)
	{
		kind = Kind.WRITE;
	}
	else if (name.compare_to("q") == 0 || name.compare_to("quit") == 0)
	{
		kind = Kind.QUIT;
	}
	else if (name.compare_to("wq") == 0 || name.compare_to("x") == 0)
	{
		kind = Kind.WRITE_QUIT;
	}
	else if (name.compare_to("e") == 0 || name.compare_to("edit") == 0)
	{
		kind = Kind.EDIT;
	}
	return { .kind = kind, .arg = arg.copy(allocator) };
}