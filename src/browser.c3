module yun::browser;

import raylib6::rl;
import std::collections::list;
import std::io::path;
import std::math;

const int BROWSER_WIDTH        = 680;
const int BROWSER_HEIGHT       = 460;
const int ROW_HEIGHT           = 24;
const int VISIBLE_ROWS         = 15;
const RLColor BROWSER_BG       = { 22, 24, 32, 245 };
const RLColor BROWSER_BORDER   = { 90, 110, 150, 255 };
const RLColor BROWSER_TITLE    = { 40, 46, 60, 255 };
const RLColor BROWSER_TEXT     = { 220, 220, 230, 255 };
const RLColor BROWSER_SELECTED = { 60, 90, 150, 255 };

struct Browser
{
	bool open;
	Path dir;
	List{Path} entries;
	Allocator allocator;
	int selected;
	int scroll;
}

fn void Browser.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.entries.init(allocator);
	self.open = false;
	self.selected = 0;
	self.scroll = 0;
}

fn String Browser.parent_dir(&self)
{
	return rl::get_prev_directory_path((ZString)self.dir.ptr).str_view().copy(self.allocator);
}

fn void Browser.scan(&self)
{
	self.entries.clear();
	PathList? list = path::ls(self.allocator, self.dir, no_dirs: false, recursive: false, relative: false);
	if (catch excuse = list) return;
	foreach (Path entry : list)
	{
		if (path::is_dir(entry)) self.entries.push(entry.copy(self.allocator));
	}
	for (sz i = 1; i < self.entries.len(); i++)
	{
		sz j = i;
		while (j > 0 && ((String)self.entries[j - 1]).compare_to((String)self.entries[j]) > 0)
		{
			self.entries.swap(j - 1, j);
			j--;
		}
	}
}

fn void Browser.navigate(&self, String dir)
{
	self.dir = (Path)dir.copy(self.allocator);
	self.scan();
	self.selected = 0;
	self.scroll = 0;
}

fn void Browser.open_at(&self, String dir)
{
	self.navigate(dir);
	self.open = true;
}

fn int Browser.rows(&self)
{
	return (int)self.entries.len() + 2;
}

fn void Browser.move_selection(&self, int delta)
{
	self.selected += delta;
	int last = self.rows() - 1;
	if (self.selected < 0) self.selected = 0;
	if (self.selected > last) self.selected = last;

	if (self.selected < self.scroll) self.scroll = self.selected;
	if (self.selected >= self.scroll + VISIBLE_ROWS) self.scroll = self.selected - VISIBLE_ROWS + 1;
}

fn bool Browser.update(&self)
{
	if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN)) self.move_selection(1);
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP)) self.move_selection(-1);

	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		self.open = false;
		return false;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE))
	{
		self.navigate(self.parent_dir());
		return false;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER))
	{
		if (self.selected == 0)
		{
			self.open = false;
			return true;
		}
		if (self.selected == 1)
		{
			self.navigate(self.parent_dir());
			return false;
		}
		int index = self.selected - 2;
		if (index >= 0 && index < (int)self.entries.len())
		{
			self.navigate((String)self.entries[(sz)index]);
		}
	}
	return false;
}

fn String Browser.row_label(&self, int index)
{
	if (index == 0) return "[Open this folder]";
	if (index == 1) return "..";
	Path entry = self.entries[(sz)(index - 2)];
	return rl::get_file_name((ZString)entry.ptr).str_view();
}

fn void Browser.draw(&self)
{
	if (!self.open) return;

	int x = (rl::get_screen_width() - BROWSER_WIDTH) / 2;
	int y = (rl::get_screen_height() - BROWSER_HEIGHT) / 2;
	rl::draw_rectangle(x, y, BROWSER_WIDTH, BROWSER_HEIGHT, BROWSER_BG);
	rl::draw_rectangle(x, y, BROWSER_WIDTH, 28, BROWSER_TITLE);
	rl::draw_rectangle_lines(x, y, BROWSER_WIDTH, BROWSER_HEIGHT, BROWSER_BORDER);
	rl::draw_text((ZString)self.dir.ptr, x + 10, y + 6, 16, BROWSER_TEXT);

	int last = math::min(self.scroll + VISIBLE_ROWS, self.rows());
	for (int i = self.scroll; i < last; i++)
	{
		int row_y = y + 36 + (i - self.scroll) * ROW_HEIGHT;
		if (i == self.selected) rl::draw_rectangle(x + 4, row_y - 2, BROWSER_WIDTH - 8, ROW_HEIGHT, BROWSER_SELECTED);
		String label = self.row_label(i);
		rl::draw_text((ZString)label.ptr, x + 12, row_y, 16, BROWSER_TEXT);
	}

	rl::draw_text(
		"Enter: open/select    Backspace: up    Esc: cancel",
		x + 10,
		y + BROWSER_HEIGHT - 24,
		14,
		BROWSER_TEXT
	);
}