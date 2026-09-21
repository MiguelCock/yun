module yun::menu;

import raylib6::rl;
import std::collections::list;
import std::math;

const int MENU_ROW_HEIGHT   = 26;
const int MENU_PADDING_X    = 12;
const int MENU_PADDING_Y    = 6;
const int MENU_MIN_WIDTH    = 140;
const RLColor MENU_BG       = { 28, 30, 40, 245 };
const RLColor MENU_BORDER   = { 90, 110, 150, 255 };
const RLColor MENU_TEXT     = { 220, 220, 230, 255 };
const RLColor MENU_SELECTED = { 60, 90, 150, 255 };

struct Menu
{
	bool open;
	List{String} items;
	Allocator allocator;
	int selected;
	RLVector2 position;
}

fn void Menu.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.items.init(allocator);
	self.open = false;
	self.selected = 0;
	self.position = { 0.0f, 0.0f };
}

fn void Menu.open_at(&self, RLVector2 position, String[] items)
{
	self.items.clear();
	foreach (String item : items)
	{
		self.items.push(item.copy(self.allocator));
	}
	self.selected = 0;
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

fn void Menu.move_selection(&self, int delta)
{
	if (self.rows() == 0) return;
	self.selected += delta;
	if (self.selected < 0) self.selected = 0;
	if (self.selected >= self.rows()) self.selected = self.rows() - 1;
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
		int chosen = self.selected;
		self.open = false;
		return chosen;
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
	if (row >= 0 && row < self.rows()) self.selected = row;
	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		int chosen = self.selected;
		self.open = false;
		return chosen;
	}
	return -1;
}

fn void Menu.draw(&self)
{
	if (!self.open) return;

	Rect panel = self.panel_rect();
	rl::draw_rectangle_rec(panel, MENU_BG);
	rl::draw_rectangle_lines_ex(panel, 1.0f, MENU_BORDER);
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
				MENU_SELECTED
			);
		}
		rl::draw_text(
			(ZString)self.items[(sz)i].ptr,
			(int)(panel.x + (float)MENU_PADDING_X),
			(int)(row_y + 4.0f),
			16,
			MENU_TEXT
		);
	}
}