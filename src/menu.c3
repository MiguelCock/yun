module yun::menu;

import raylib6::rl;
import std::collections::list;
import std::math;
import yun::theme;

const int MENU_ROW_HEIGHT = 26;
const int MENU_PADDING_X  = 12;
const int MENU_PADDING_Y  = 6;
const int MENU_MIN_WIDTH  = 140;

struct Menu
{
	bool open;
	List{String} items;
	List{bool} enabled;
	Allocator allocator;
	int selected;
	RLVector2 position;
}

fn void Menu.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.items.init(allocator);
	self.enabled.init(allocator);
	self.open = false;
	self.selected = 0;
	self.position = { 0.0f, 0.0f };
}

fn void Menu.open_at(&self, RLVector2 position, String[] items)
{
	self.items.clear();
	self.enabled.clear();
	for (usz i = 0; i < items.len; i++)
	{
		self.items.push(items[i].copy(self.allocator));
		self.enabled.push(true);
	}
	self.selected = self.first_enabled(0);
	self.position = position;
	self.open = true;
}

fn void Menu.open_with(&self, RLVector2 position, String[] items, bool[] enabled)
{
	self.items.clear();
	self.enabled.clear();
	for (usz i = 0; i < items.len; i++)
	{
		self.items.push(items[i].copy(self.allocator));
		self.enabled.push(i < enabled.len ? enabled[i] : true);
	}
	self.selected = self.first_enabled(0);
	self.position = position;
	self.open = true;
}

fn void Menu.close(&self)
{
	self.open = false;
}

fn int Menu.rows(&self)
{
	return (int)self.items.len();
}

fn bool Menu.is_enabled(&self, int index)
{
	if (index < 0 || index >= self.rows()) return false;
	return self.enabled[index];
}

fn int Menu.first_enabled(&self, int from)
{
	for (int i = from; i < self.rows(); i++)
	{
		if (self.enabled[i]) return i;
	}
	return 0;
}

fn void Menu.move_selection(&self, int delta)
{
	int rows = self.rows();
	if (rows == 0) return;

	int step      = delta > 0 ? 1 : -1;
	int remaining = delta > 0 ? delta : -delta;
	int current   = self.selected;
	for (int i = 0; i < remaining; i++)
	{
		int next = current;
		for (int j = 0; j < rows; j++)
		{
			next += step;
			if (next < 0) next = rows - 1;
			if (next >= rows) next = 0;
			if (self.enabled[next]) break;
		}
		current = next;
	}
	self.selected = current;
}

fn int Menu.width(&self)
{
	int width = MENU_MIN_WIDTH;
	for (sz i = 0; i < self.items.len(); i++)
	{
		int item_width = rl::measure_text((ZString)self.items[i].ptr, 16) + MENU_PADDING_X * 2;
		if (item_width > width) width = item_width;
	}
	return width;
}

fn Rect Menu.panel_rect(&self)
{
	int width  = self.width();
	int height = self.rows() * MENU_ROW_HEIGHT + MENU_PADDING_Y * 2;
	float x    = self.position[0];
	float y    = self.position[1];
	if (x + (float)width > (float)rl::get_screen_width()) x = (float)(rl::get_screen_width() - width);
	if (y + (float)height > (float)rl::get_screen_height()) y = (float)(rl::get_screen_height() - height);
	if (x < 0.0f) x = 0.0f;
	if (y < 0.0f) y = 0.0f;
	return { .x = x, .y = y, .width = (float)width, .height = (float)height };
}

fn int Menu.update(&self)
{
	if (!self.open) return -1;

	if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN)) self.move_selection(1);
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP)) self.move_selection(-1);
	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		self.open = false;
		return -1;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER))
	{
		if (self.is_enabled(self.selected))
		{
			int chosen = self.selected;
			self.open = false;
			return chosen;
		}
	}

	Rect panel      = self.panel_rect();
	RLVector2 mouse = rl::get_mouse_position();
	if (mouse[0] < panel.x || mouse[0] > panel.x + panel.width || mouse[1] < panel.y
		|| mouse[1] > panel.y + panel.height)
	{
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT)) self.open = false;
		return -1;
	}
	int row = (int)((mouse[1] - panel.y - (float)MENU_PADDING_Y) / (float)MENU_ROW_HEIGHT);
	if (row >= 0 && row < self.rows() && self.enabled[row]) self.selected = row;
	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		if (row >= 0 && row < self.rows() && self.enabled[row])
		{
			int chosen = row;
			self.open = false;
			return chosen;
		}
	}
	return -1;
}

fn void Menu.draw(&self)
{
	if (!self.open) return;

	Rect panel = self.panel_rect();
	rl::draw_rectangle_rec(panel, theme::current().panel_bg_alt);
	rl::draw_rectangle_lines_ex(panel, 1.0f, theme::current().panel_border);
	for (int i = 0; i < self.rows(); i++)
	{
		float row_y = panel.y + (float)MENU_PADDING_Y + (float)(i * MENU_ROW_HEIGHT);
		if (i == self.selected)
		{
			rl::draw_rectangle(
				(int)(panel.x + 2.0f),
				(int)row_y,
				(int)(panel.width - 4.0f),
				MENU_ROW_HEIGHT,
				theme::current()
				.panel_selected);
		}
		rl::draw_text(
			(ZString)self.items[(sz)i].ptr,
			(int)(panel.x + (float)MENU_PADDING_X),
			(int)(row_y + 4.0f),
			16,
			self.enabled[(sz)i] ? theme::current()
			.panel_text : theme::current().panel_disabled);
	}
}