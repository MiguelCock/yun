module yun::image_picker;

import raylib6::rl;
import std::collections::list;
import std::io::path;
import std::math;
import yun::icons;
import yun::theme;
import yun::ui;

const int PICKER_WIDTH  = 680;
const int PICKER_HEIGHT = 460;
const int ROW_HEIGHT    = 24;
const int VISIBLE_ROWS  = 15;
const int HEADER_HEIGHT = 28;
const int FOOTER_HEIGHT = 28;

enum PickerAction : int
{
	NONE,
	SELECTED,
	CANCELLED,
}

struct Entry
{
	String path;
	bool dir;
}

struct ImagePicker
{
	bool open;
	String dir;
	List{Entry} entries;
	Allocator allocator;
	int selected;
	int scroll;
	bool consumed;
	String result;
}

fn void ImagePicker.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.entries.init(allocator);
	self.open = false;
	self.dir = "";
	self.selected = 0;
	self.scroll = 0;
	self.consumed = false;
	self.result = "";
}

fn void ImagePicker.destroy(&self)
{
	if (self.dir.len) self.dir.free(self.allocator);
	if (self.result.len) self.result.free(self.allocator);
	self.free_entries();
	self.entries.free();
	self.dir = "";
	self.result = "";
}

fn void ImagePicker.free_entries(&self)
{
	for (sz i = 0; i < self.entries.len(); i++)
	{
		if (self.entries[i].path.len) self.entries[i].path.free(self.allocator);
	}
	self.entries.clear();
}

fn void ImagePicker.clear_result(&self)
{
	if (self.result.len) self.result.free(self.allocator);
	self.result = "";
}

fn String file_name(String path)
{
	usz start = 0;
	for (usz i = 0; i < path.len; i++)
	{
		if (path[i] == '/' || path[i] == '\\') start = i + 1;
	}
	return path[start:path.len - start];
}

fn bool image_path_supported(String path)
{
	String name = file_name(path);
	usz dot     = 0;
	bool has    = false;
	for (usz i = 0; i < name.len; i++)
	{
		if (name[i] == '.')
		{
			dot = i;
			has = true;
		}
	}
	if (!has || dot + 1 >= name.len) return false;
	String ext = name[dot:name.len - dot];
	return ext.compare_to_ignore_case(
		".png"
	) == 0 || ext.compare_to_ignore_case(
		".jpg"
	) == 0 || ext.compare_to_ignore_case(
		".jpeg"
	) == 0 || ext.compare_to_ignore_case(
		".gif"
	) == 0 || ext.compare_to_ignore_case(".bmp") == 0 || ext.compare_to_ignore_case(".webp") == 0;
}

fn bool entry_before(Entry a, Entry b)
{
	if (a.dir != b.dir) return a.dir;
	String an = file_name(a.path);
	String bn = file_name(b.path);
	int cmp   = an.compare_to_ignore_case(bn);
	if (cmp != 0) return cmp < 0;
	return an.compare_to(bn) < 0;
}

fn void ImagePicker.scan(&self)
{
	self.free_entries();
	PathList? listed = path::ls(self.allocator, (Path)self.dir, no_dirs: false, recursive: false, relative: false);
	if (catch excuse = listed) return;
	foreach (Path item : listed)
	{
		bool dir = path::is_dir(item);
		if (!dir && !image_path_supported((String)item)) continue;
		self.entries.push({ .path = (String)item, .dir = dir });
	}
	listed.free();
	for (sz i = 1; i < self.entries.len(); i++)
	{
		sz j = i;
		while (j > 0 && entry_before(self.entries[j], self.entries[j - 1]))
		{
			self.entries.swap(j - 1, j);
			j--;
		}
	}
}

fn bool ImagePicker.navigate(&self, String dir)
{
	Path? absolute = dir.to_absolute_path(self.allocator);
	if (catch excuse = absolute) return false;
	if (!path::is_dir(absolute))
	{
		((String)absolute).free(self.allocator);
		return false;
	}
	if (self.dir.len) self.dir.free(self.allocator);
	self.dir = (String)absolute;
	self.scan();
	self.selected = 0;
	self.scroll = 0;
	return true;
}

fn bool ImagePicker.open_at(&self, String dir)
{
	self.clear_result();
	bool ok = self.navigate(dir);
	if (!ok) ok = self.navigate(".");
	if (!ok) return false;
	self.open = true;
	return true;
}

fn bool ImagePicker.navigate_parent(&self)
{
	if (self.dir.len == 0) return false;
	Path? parent = ((Path)self.dir).parent();
	if (catch excuse = parent) return false;
	String next = (String)parent;
	if (next.len == 0 && (self.dir[0] == '/' || self.dir[0] == '\\')) next = self.dir[0:1];
	if (next.len == 0 || next.compare_to(self.dir) == 0) return false;
	return self.navigate(next);
}

fn void ImagePicker.move_selection(&self, int delta)
{
	if (self.entries.len() == 0)
	{
		self.selected = 0;
		self.scroll = 0;
		return;
	}
	int last = (int)self.entries.len() - 1;
	self.selected += delta;
	if (self.selected < 0) self.selected = 0;
	if (self.selected > last) self.selected = last;
	if (self.selected < self.scroll) self.scroll = self.selected;
	if (self.selected >= self.scroll + VISIBLE_ROWS) self.scroll = self.selected - VISIBLE_ROWS + 1;
	if (self.scroll < 0) self.scroll = 0;
}

fn String ImagePicker.selected_path(&self)
{
	if (self.selected < 0 || self.selected >= (int)self.entries.len()) return "";
	return self.entries[self.selected].path;
}

fn PickerAction ImagePicker.activate_selected(&self)
{
	if (self.selected < 0 || self.selected >= (int)self.entries.len()) return PickerAction.NONE;
	Entry entry = self.entries[self.selected];
	if (entry.dir)
	{
		(void)self.navigate(entry.path);
		return PickerAction.NONE;
	}
	self.clear_result();
	self.result = entry.path.copy(self.allocator);
	self.open = false;
	return PickerAction.SELECTED;
}

fn void ImagePicker.cancel(&self)
{
	self.open = false;
	self.clear_result();
}

fn String ImagePicker.take_result(&self, Allocator allocator)
{
	if (self.result.len == 0) return "";
	String out = self.result.copy(allocator);
	self.clear_result();
	return out;
}

fn String ImagePicker.result_view(&self)
{
	return self.result;
}

fn PickerAction ImagePicker.update(&self)
{
	if (!self.open) return PickerAction.NONE;
	self.consumed = false;
	while (rl::get_char_pressed() != 0)
	{
	}
	RLVector2 mouse = rl::get_mouse_position();
	int width       = ui::px(PICKER_WIDTH);
	int height      = ui::px(PICKER_HEIGHT);
	int panel_x     = (rl::get_screen_width() - width) / 2;
	int panel_y     = (rl::get_screen_height() - height) / 2;
	int list_top    = panel_y + ui::px(HEADER_HEIGHT) + ui::px(8);
	int list_bottom = panel_y + height - ui::px(FOOTER_HEIGHT);
	int row_h       = ui::px(ROW_HEIGHT);
	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		self.consumed = true;
		if (mouse[0] < (float)panel_x || mouse[0] >= (float)(panel_x + width) || mouse[1] < (float)panel_y
			|| mouse[1] >= (float)(panel_y + height))
		{
			self.cancel();
			return PickerAction.CANCELLED;
		}
		if (mouse[1] >= (float)list_top && mouse[1] < (float)list_bottom)
		{
			int row = self.scroll + (int)((mouse[1] - (float)list_top) / (float)row_h);
			if (row >= 0 && row < (int)self.entries.len())
			{
				self.selected = row;
				if (self.entries[row].dir)
				{
					(void)self.navigate(self.entries[row].path);
				}
				else
				{
					return self.activate_selected();
				}
			}
		}
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		self.consumed = true;
		self.cancel();
		return PickerAction.CANCELLED;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER))
	{
		self.consumed = true;
		return self.activate_selected();
	}
	if (rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		self.consumed = true;
		(void)self.navigate_parent();
		return PickerAction.NONE;
	}
	if (rl::is_key_pressed_repeat(rl::RLKeyboardKey.UP))
	{
		self.consumed = true;
		self.move_selection(-1);
	}
	if (rl::is_key_pressed_repeat(rl::RLKeyboardKey.DOWN))
	{
		self.consumed = true;
		self.move_selection(1);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_UP))
	{
		self.consumed = true;
		self.move_selection(-VISIBLE_ROWS);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_DOWN))
	{
		self.consumed = true;
		self.move_selection(VISIBLE_ROWS);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.HOME))
	{
		self.consumed = true;
		self.move_selection(-(int)self.entries.len());
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.END))
	{
		self.consumed = true;
		self.move_selection((int)self.entries.len());
	}
	float wheel = rl::get_mouse_wheel_move();
	if (wheel > 0.0f)
	{
		self.consumed = true;
		self.move_selection(-1);
	}
	if (wheel < 0.0f)
	{
		self.consumed = true;
		self.move_selection(1);
	}
	return PickerAction.NONE;
}

fn void draw_text(RLFont font, String text, float x, float y, float size, RLColor color)
{
	if (text.len == 0) return;
	@pool()
	{
		rl::draw_text_ex(font, text.zstr_tcopy(), { x, y }, size, 0.0f, color);
	};
}

fn void ImagePicker.draw(&self)
{
	if (!self.open) return;
	int width   = ui::px(PICKER_WIDTH);
	int height  = ui::px(PICKER_HEIGHT);
	int row_h   = ui::px(ROW_HEIGHT);
	int x       = (rl::get_screen_width() - width) / 2;
	int y       = (rl::get_screen_height() - height) / 2;
	int header  = ui::px(HEADER_HEIGHT);
	int footer  = ui::px(FOOTER_HEIGHT);
	Rect panel  = { .x = (float)x, .y = (float)y, .width = (float)width, .height = (float)height };
	RLFont font = ui::font();
	ui::rounded_rect(panel, ui::corner_radius(), theme::current().panel_bg);
	ui::rounded_top(
		{ .x = (float)x, .y = (float)y, .width = (float)width, .height = (float)header },
		ui::corner_radius(),
		theme::current()
		.panel_bg_alt);
	ui::rounded_rect_lines(panel, ui::corner_radius(), 1.0f, theme::current().panel_border);

	rl::begin_scissor_mode(x + ui::px(10), y, width - ui::px(20), header);
	draw_text(
		font,
		self.dir.len > 0 ? self.dir : "Select an image",
		(float)(x + ui::px(10)),
		(float)(y + ui::px(6)),
		(float)ui::tpx(16),
		theme::current()
		.panel_text);
	rl::end_scissor_mode();

	int top  = y + header + ui::px(8);
	int last = math::min(self.scroll + VISIBLE_ROWS, (int)self.entries.len());
	if (self.entries.len() == 0)
	{
		draw_text(
			font,
			"No images or folders here",
			(float)(x + ui::px(12)),
			(float)top,
			(float)ui::tpx(16),
			theme::current()
			.panel_dim);
	}
	rl::begin_scissor_mode(x + ui::px(4), top, width - ui::px(8), height - header - footer - ui::px(8));
	for (int i = self.scroll; i < last; i++)
	{
		int row_y = top + (i - self.scroll) * row_h;
		if (i == self.selected) ui::row(
			{
				.x = (float)(x + ui::px(4)),
				.y = (float)(row_y - ui::px(2)),
				.width = (float)(width - ui::px(8)),
				.height = (float)row_h,
			},
			theme::current()
			.panel_selected);
		Entry entry   = self.entries[i];
		float icon    = (float)ui::px(16);
		float label_x = (float)(x + ui::px(12));
		bool has_icon = false;
		if (entry.dir)
		{
			has_icon = icons::draw_folder(
				false,
				{ .x = (float)(x + ui::px(10)), .y = (float)row_y, .width = icon, .height = icon },
				rl::WHITE
			);
		}
		else
		{
			has_icon = icons::draw_file(
				entry.path,
				{ .x = (float)(x + ui::px(10)), .y = (float)row_y, .width = icon, .height = icon },
				rl::WHITE
			);
		}
		if (has_icon) label_x += icon + (float)ui::px(4);
		draw_text(font, file_name(entry.path), label_x, (float)row_y, (float)ui::tpx(16), theme::current().panel_text);
	}
	rl::end_scissor_mode();

	draw_text(
		font,
		"Enter/click: open/select    Backspace: up    Esc: cancel",
		(float)(x + ui::px(10)),
		(float)(y + height - footer + ui::px(4)),
		(float)ui::tpx(14),
		theme::current()
		.panel_dim);
}