module yun::palette;

import raylib6::rl;
import std::collections::list;
import std::math;
import yun::commands;
import yun::topbar;

const int QUERY_MAX            = 64;
const int ROW_HEIGHT           = 26;
const int PADDING              = 10;
const int PANEL_WIDTH          = 560;
const int MAX_VISIBLE_ROWS     = 10;
const int TOP_MARGIN           = 24;
const RLColor PALETTE_BG       = { 24, 26, 34, 250 };
const RLColor PALETTE_BORDER   = { 90, 110, 150, 255 };
const RLColor PALETTE_FIELD    = { 16, 18, 24, 255 };
const RLColor PALETTE_TEXT     = { 230, 232, 238, 255 };
const RLColor PALETTE_DIM      = { 140, 150, 170, 255 };
const RLColor PALETTE_DISABLED = { 100, 106, 118, 255 };
const RLColor PALETTE_SELECTED = { 60, 90, 150, 255 };
const RLColor PALETTE_MATCH    = { 240, 200, 120, 255 };
const RLColor PALETTE_CARET    = { 240, 240, 240, 255 };

struct Palette
{
	bool open;
	char[QUERY_MAX + 1] query;
	int query_len;
	List{commands::CommandId} results;
	List{commands::CommandId} recent;
	Allocator allocator;
	int selected;
	int scroll;
}

fn void Palette.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.results.init(allocator);
	self.recent.init(allocator);
	self.open = false;
	self.query_len = 0;
	self.query[0] = 0;
	self.selected = 0;
	self.scroll = 0;
}

fn void Palette.show(&self)
{
	self.open = true;
	self.query_len = 0;
	self.query[0] = 0;
	self.selected = 0;
	self.scroll = 0;
}

fn void Palette.close(&self)
{
	self.open = false;
}

fn String Palette.query_view(&self)
{
	return (String)self.query[0:self.query_len];
}

fn bool Palette.append_codepoint(&self, int codepoint)
{
	if (codepoint < 32 || codepoint > 126) return false;
	if (self.query_len >= QUERY_MAX) return false;
	self.query[self.query_len] = (char)codepoint;
	self.query_len++;
	self.query[self.query_len] = 0;
	return true;
}

fn void Palette.backspace(&self)
{
	if (self.query_len == 0) return;
	self.query_len--;
	self.query[self.query_len] = 0;
}

fn bool Palette.contains_result(&self, commands::CommandId id)
{
	for (sz i = 0; i < self.results.len(); i++)
	{
		if (self.results[i] == id) return true;
	}
	return false;
}

fn int Palette.score_of(&self, commands::CommandId id, String query)
{
	usz[QUERY_MAX] positions;
	return commands::fuzzy_match(commands::command_def(id).label, query, positions[0:QUERY_MAX]);
}

fn void Palette.clamp_scroll(&self)
{
	int rows = (int)self.results.len();
	if (self.selected < self.scroll) self.scroll = self.selected;
	if (self.selected >= self.scroll + MAX_VISIBLE_ROWS) self.scroll = self.selected - MAX_VISIBLE_ROWS + 1;
	int max_scroll = rows - MAX_VISIBLE_ROWS;
	if (max_scroll < 0) max_scroll = 0;
	if (self.scroll > max_scroll) self.scroll = max_scroll;
	if (self.scroll < 0) self.scroll = 0;
}

fn void Palette.filter(&self)
{
	self.results.clear();
	String query = self.query_view();

	if (query.len == 0)
	{
		for (sz i = 0; i < self.recent.len(); i++)
		{
			self.results.push(self.recent[i]);
		}
		for (usz i = 0; i < commands::command_count(); i++)
		{
			commands::CommandId id = (commands::CommandId)i;
			if (!self.contains_result(id)) self.results.push(id);
		}
	}
	else
	{
		for (usz i = 0; i < commands::command_count(); i++)
		{
			commands::CommandId id = (commands::CommandId)i;
			int score              = self.score_of(id, query);
			if (score < 0) continue;
			sz insert = (sz)self.results.len();
			for (sz j = 0; j < self.results.len(); j++)
			{
				if (score > self.score_of(self.results[j], query))
				{
					insert = j;
					break;
				}
			}
			self.results.insert_at(insert, id);
		}
	}

	if (self.selected >= (int)self.results.len()) self.selected = (int)self.results.len() - 1;
	if (self.selected < 0) self.selected = 0;
	self.clamp_scroll();
}

fn void Palette.move_selection(&self, int delta)
{
	int rows = (int)self.results.len();
	if (rows == 0) return;
	self.selected += delta;
	if (self.selected < 0) self.selected = 0;
	if (self.selected >= rows) self.selected = rows - 1;
	self.clamp_scroll();
}

fn int Palette.selected_command(&self)
{
	if (self.selected < 0 || self.selected >= (int)self.results.len()) return -1;
	return (int)self.results[self.selected];
}

fn void Palette.record(&self, commands::CommandId id)
{
	for (sz i = 0; i < self.recent.len(); i++)
	{
		if (self.recent[i] == id)
		{
			self.recent.remove_at(i);
			break;
		}
	}
	self.recent.insert_at(0, id);
	while (self.recent.len() > (sz)commands::command_count())
	{
		self.recent.remove_at(self.recent.len() - 1);
	}
}

fn Rect Palette.panel_rect(&self)
{
	int rows = (int)self.results.len();
	if (rows > MAX_VISIBLE_ROWS) rows = MAX_VISIBLE_ROWS;
	if (rows == 0) rows = 1;
	int height = PADDING * 2 + ROW_HEIGHT + 6 + rows * ROW_HEIGHT;
	int x      = (rl::get_screen_width() - PANEL_WIDTH) / 2;
	int y      = (int)topbar::TOP_BAR_HEIGHT + TOP_MARGIN;
	return { .x = (float)x, .y = (float)y, .width = (float)PANEL_WIDTH, .height = (float)height };
}

fn Rect Palette.field_rect(&self)
{
	Rect panel = self.panel_rect();
	return {
		.x = panel.x + (float)PADDING,
		.y = panel.y + (float)PADDING,
		.width = panel.width - (float)(PADDING * 2),
		.height = (float)ROW_HEIGHT,
	};
}

fn float Palette.list_y(&self)
{
	return self.panel_rect().y + (float)(PADDING + ROW_HEIGHT + 6);
}

fn int Palette.row_at(&self, RLVector2 mouse)
{
	float list_y = self.list_y();
	if (mouse[1] < list_y) return -1;
	int row = (int)((mouse[1] - list_y) / (float)ROW_HEIGHT) + self.scroll;
	if (row < 0 || row >= (int)self.results.len()) return -1;
	return row;
}

fn int Palette.update(&self, bool has_project, bool has_buffer)
{
	if (!self.open) return -1;

	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		self.open = false;
		return -1;
	}

	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		self.backspace();
	}
	int codepoint = rl::get_char_pressed();
	while (codepoint != 0)
	{
		self.append_codepoint(codepoint);
		codepoint = rl::get_char_pressed();
	}
	self.filter();

	if (rl::is_key_pressed(
		rl::RLKeyboardKey.DOWN
	) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.DOWN)) self.move_selection(1);
	if (rl::is_key_pressed(
		rl::RLKeyboardKey.UP
	) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.UP)) self.move_selection(-1);

	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER))
	{
		int id = self.selected_command();
		if (id >= 0 && commands::command_enabled((commands::CommandId)id, has_project, has_buffer))
		{
			self.open = false;
			return id;
		}
	}

	Rect panel      = self.panel_rect();
	RLVector2 mouse = rl::get_mouse_position();
	bool inside     = mouse[0] >= panel.x && mouse[0] <= panel.x + panel.width && mouse[1] >= panel.y
		&& mouse[1] <= panel.y + panel.height;
	if (!inside)
	{
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT)) self.open = false;
		return -1;
	}

	int row = self.row_at(mouse);
	if (row >= 0)
	{
		self.selected = row;
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
		{
			int id = self.selected_command();
			if (id >= 0 && commands::command_enabled((commands::CommandId)id, has_project, has_buffer))
			{
				self.open = false;
				return id;
			}
		}
	}
	return -1;
}

fn bool position_matched(usz[] positions, usz count, usz index)
{
	for (usz i = 0; i < count; i++)
	{
		if (positions[i] == index) return true;
	}
	return false;
}

fn void draw_run(RLFont font, String text, float x, float y, RLColor color)
{
	if (text.len == 0) return;
	@pool()
	{
		ZString z = text.zstr_tcopy();
		rl::draw_text_ex(font, z, { x, y }, 16.0f, 0.0f, color);
	};
}

fn float measure_width(RLFont font, String text)
{
	if (text.len == 0) return 0.0f;
	float width;
	@pool()
	{
		width = rl::measure_text_ex(font, text.zstr_tcopy(), 16.0f, 0.0f)[0];
	};
	return width;
}

fn float draw_label(RLFont font, String label, String query, float x, float y, RLColor color)
{
	if (query.len == 0)
	{
		draw_run(font, label, x, y, color);
		return measure_width(font, label);
	}

	usz[QUERY_MAX] positions;
	if (commands::fuzzy_match(label, query, positions[0:QUERY_MAX]) < 0)
	{
		draw_run(font, label, x, y, color);
		return measure_width(font, label);
	}

	float cursor = x;
	usz i        = 0;
	while (i < label.len)
	{
		bool matched = position_matched(positions[0:QUERY_MAX], query.len, i);
		usz start    = i;
		while (i < label.len && position_matched(positions[0:QUERY_MAX], query.len, i) == matched) i++;
		String run = label[start:i - start];
		draw_run(font, run, cursor, y, matched ? PALETTE_MATCH : color);
		cursor += measure_width(font, run);
	}
	return cursor - x;
}

fn void Palette.draw(&self, bool has_project, bool has_buffer, RLFont font)
{
	if (!self.open) return;

	Rect panel = self.panel_rect();
	rl::draw_rectangle_rec(panel, PALETTE_BG);
	rl::draw_rectangle_lines_ex(panel, 1.0f, PALETTE_BORDER);

	Rect field = self.field_rect();
	rl::draw_rectangle_rec(field, PALETTE_FIELD);
	String query = self.query_view();
	draw_run(font, query, field.x + 8.0f, field.y + 5.0f, PALETTE_TEXT);
	float query_width = measure_width(font, query);
	rl::draw_rectangle((int)(field.x + 8.0f + query_width + 1.0f), (int)(field.y + 5.0f), 2, 16, PALETTE_CARET);

	float list_y = self.list_y();
	if (self.results.len() == 0)
	{
		draw_run(font, "No matching commands", panel.x + (float)PADDING + 4.0f, list_y + 5.0f, PALETTE_DIM);
		return;
	}

	for (int slot = 0; slot < MAX_VISIBLE_ROWS; slot++)
	{
		int index = self.scroll + slot;
		if (index >= (int)self.results.len()) break;
		commands::CommandId id   = self.results[index];
		commands::CommandDef def = commands::command_def(id);
		bool enabled             = commands::command_enabled(id, has_project, has_buffer);
		float row_y              = list_y + (float)slot * (float)ROW_HEIGHT;
		if (index == self.selected)
		{
			rl::draw_rectangle((int)panel.x + 2, (int)row_y, (int)panel.width - 4, ROW_HEIGHT, PALETTE_SELECTED);
		}
		draw_label(
			font,
			def.label,
			query,
			panel.x + (float)PADDING + 4.0f,
			row_y + 5.0f,
			enabled ? PALETTE_TEXT : PALETTE_DISABLED
		);
		if (def.shortcut.len > 0)
		{
			@pool()
			{
				ZString z      = def.shortcut.zstr_tcopy();
				RLVector2 size = rl::measure_text_ex(font, z, 14.0f, 0.0f);
				rl::draw_text_ex(
					font,
					z,
					{ panel.x + panel.width - (float)PADDING - size[0], row_y + 6.0f },
					14.0f,
					0.0f,
					PALETTE_DIM
				);
			};
		}
	}
}