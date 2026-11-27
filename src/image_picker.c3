module yun::image_picker;

import raylib6::rl;
import std::collections::list;
import std::io::path;
import std::math;
import yun::icons;
import yun::image;
import yun::theme;
import yun::ui;

const int PICKER_WIDTH  = 940;
const int PICKER_HEIGHT = 500;
const int ROW_HEIGHT    = 24;
const int VISIBLE_ROWS  = 16;
const int HEADER_HEIGHT = 28;
const int FOOTER_HEIGHT = 28;
const int PREVIEW_WIDTH = 300;
const int PREVIEW_MAX   = 320;
const int PREVIEW_GAP   = 12;

const double PREVIEW_DELAY   = 0.12;
const double REPEAT_DELAY    = 0.28;
const double REPEAT_INTERVAL = 0.055;
const double DOUBLE_CLICK    = 0.35;

enum PickerAction : int
{
	NONE,
	SELECTED,
	CANCELLED,
}

enum PreviewKind : int
{
	EMPTY,
	PARENT,
	FOLDER,
	LOADING,
	IMAGE,
	FAILED,
}

struct Entry
{
	String path;
	bool dir;
	bool parent;
}

struct PreviewState
{
	String path;
	RLTexture2D texture;
	int width;
	int height;
	PreviewKind kind;
	double due;
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
	PreviewState preview;
	int repeat_key;
	double repeat_at;
	int last_click_row;
	double last_click_at;
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
	self.preview = { };
	self.repeat_key = 0;
	self.repeat_at = 0.0;
	self.last_click_row = -1;
	self.last_click_at = 0.0;
}

fn void ImagePicker.preview_clear(&self)
{
	if (self.preview.texture.is_valid()) rl::unload_texture(self.preview.texture);
	if (self.preview.path.len) self.preview.path.free(self.allocator);
	self.preview = { };
}

fn void ImagePicker.destroy(&self)
{
	self.preview_clear();
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
	return image::supported(path);
}

fn bool entry_before(Entry a, Entry b)
{
	if (a.parent != b.parent) return a.parent;
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
	Path? parent = ((Path)self.dir).parent();
	if (try p = parent)
	{
		if (p.len > 0 && p.compare_to(self.dir) != 0)
		{
			self.entries.push({ .path = ((String)p).copy(self.allocator), .dir = true, .parent = true });
		}
	}
	PathList? listed = path::ls(self.allocator, (Path)self.dir, no_dirs: false, recursive: false, relative: false);
	if (catch excuse = listed) return;
	foreach (Path item : listed)
	{
		bool dir = path::is_dir(item);
		if (!dir && !image_path_supported((String)item)) continue;
		self.entries.push({ .path = (String)item, .dir = dir, .parent = false });
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

fn int ImagePicker.initial_selection(&self)
{
	return self.entries.len() > 0 && self.entries[0].parent ? (self.entries.len() > 1 ? 1 : 0) : 0;
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
	self.selected = self.initial_selection();
	self.scroll = 0;
	self.last_click_row = -1;
	self.last_click_at = 0.0;
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

fn void ImagePicker.select_path(&self, String path)
{
	for (sz i = 0; i < self.entries.len(); i++)
	{
		if (self.entries[i].path.compare_to(path) != 0) continue;
		self.selected = (int)i;
		if (self.selected < self.scroll) self.scroll = self.selected;
		if (self.selected >= self.scroll + VISIBLE_ROWS) self.scroll = self.selected - VISIBLE_ROWS + 1;
		if (self.scroll < 0) self.scroll = 0;
		return;
	}
}

fn bool ImagePicker.navigate_parent(&self)
{
	if (self.dir.len == 0) return false;
	Path? parent = ((Path)self.dir).parent();
	if (catch excuse = parent) return false;
	String next = (String)parent;
	if (next.len == 0 && (self.dir[0] == '/' || self.dir[0] == '\\')) next = self.dir[0:1];
	if (next.len == 0 || next.compare_to(self.dir) == 0) return false;
	String previous = self.dir.copy(self.allocator);
	bool ok         = self.navigate(next);
	if (ok) self.select_path(previous);
	previous.free(self.allocator);
	return ok;
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

fn bool ImagePicker.selected_parent(&self)
{
	if (self.selected < 0 || self.selected >= (int)self.entries.len()) return false;
	return self.entries[self.selected].parent;
}

fn PickerAction ImagePicker.activate_selected(&self)
{
	if (self.selected < 0 || self.selected >= (int)self.entries.len()) return PickerAction.NONE;
	Entry entry = self.entries[self.selected];
	if (entry.parent)
	{
		(void)self.navigate_parent();
		return PickerAction.NONE;
	}
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

fn Rect ImagePicker.panel_rect(&self)
{
	int width  = math::min(ui::px(PICKER_WIDTH), rl::get_screen_width() - ui::px(40));
	int height = math::min(ui::px(PICKER_HEIGHT), rl::get_screen_height() - ui::px(40));
	return {
		.x = (float)((rl::get_screen_width() - width) / 2),
		.y = (float)((rl::get_screen_height() - height) / 2),
		.width = (float)width,
		.height = (float)height,
	};
}

fn bool preview_visible(Rect panel)
{
	return panel.width >= (float)ui::px(760);
}

fn float list_width(Rect panel)
{
	float width = panel.width - (float)ui::px(20);
	if (preview_visible(panel)) width -= (float)ui::px(PREVIEW_WIDTH) + (float)ui::px(PREVIEW_GAP);
	return width;
}

fn Rect preview_area(Rect panel)
{
	return {
		.x = panel.x + panel.width - (float)ui::px(PREVIEW_WIDTH) - (float)ui::px(12),
		.y = panel.y + (float)ui::px(HEADER_HEIGHT) + (float)ui::px(8),
		.width = (float)ui::px(PREVIEW_WIDTH),
		.height = panel.height - (float)ui::px(HEADER_HEIGHT) - (float)ui::px(FOOTER_HEIGHT) - (float)ui::px(16),
	};
}

fn Rect contain_rect(int width, int height, Rect area)
{
	if (width <= 0 || height <= 0 || area.width <= 0.0f || area.height <= 0.0f) return area;
	float scale = math::min(area.width / (float)width, area.height / (float)height);
	float w     = (float)width * scale;
	float h     = (float)height * scale;
	return {
		.x = area.x + (area.width - w) * 0.5f,
		.y = area.y + (area.height - h) * 0.5f,
		.width = w,
		.height = h,
	};
}

fn void ImagePicker.sync_preview(&self, double now)
{
	if (self.selected < 0 || self.selected >= (int)self.entries.len())
	{
		if (self.preview.kind != PreviewKind.EMPTY) self.preview_clear();
		return;
	}
	Entry entry = self.entries[self.selected];
	if (self.preview.path.compare_to(entry.path) == 0) return;
	self.preview_clear();
	self.preview.path = entry.path.copy(self.allocator);
	if (entry.parent)
	{
		self.preview.kind = PreviewKind.PARENT;
	}
	else if (entry.dir)
	{
		self.preview.kind = PreviewKind.FOLDER;
	}
	else
	{
		self.preview.kind = PreviewKind.LOADING;
		self.preview.due = now + PREVIEW_DELAY;
	}
}

fn void ImagePicker.update_preview(&self, double now)
{
	if (self.preview.kind != PreviewKind.LOADING || now < self.preview.due) return;
	Thumbnail? loaded = image::load_thumbnail(self.preview.path, ui::px(PREVIEW_MAX));
	if (catch excuse = loaded)
	{
		self.preview.kind = PreviewKind.FAILED;
		return;
	}
	self.preview.texture = loaded.texture;
	self.preview.width = loaded.width;
	self.preview.height = loaded.height;
	self.preview.kind = PreviewKind.IMAGE;
}

fn void ImagePicker.start_repeat(&self, int key, double now)
{
	self.repeat_key = key;
	self.repeat_at = now + REPEAT_DELAY;
}

fn void ImagePicker.update_repeat(&self, double now)
{
	if (self.repeat_key == 0) return;
	if (!rl::is_key_down((rl::RLKeyboardKey)self.repeat_key))
	{
		self.repeat_key = 0;
		return;
	}
	if (now < self.repeat_at) return;
	self.move_selection(self.repeat_key == (int)rl::RLKeyboardKey.UP ? -1 : 1);
	self.repeat_at = now + REPEAT_INTERVAL;
}

fn PickerAction ImagePicker.update(&self)
{
	if (!self.open) return PickerAction.NONE;
	self.consumed = false;
	while (rl::get_char_pressed() != 0)
	{
	}
	double now      = rl::get_time();
	Rect panel      = self.panel_rect();
	RLVector2 mouse = rl::get_mouse_position();
	int top         = (int)panel.y + ui::px(HEADER_HEIGHT) + ui::px(8);
	int bottom      = (int)(panel.y + panel.height) - ui::px(FOOTER_HEIGHT);
	int row_h       = ui::px(ROW_HEIGHT);
	float rows_w    = list_width(panel);
	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		self.consumed = true;
		if (mouse[0] < panel.x || mouse[0] >= panel.x + panel.width || mouse[1] < panel.y
			|| mouse[1] >= panel.y + panel.height)
		{
			self.cancel();
			return PickerAction.CANCELLED;
		}
		if (mouse[0] < panel.x + rows_w + (float)ui::px(10) && mouse[1] >= (float)top && mouse[1] < (float)bottom)
		{
			int row = self.scroll + (int)((mouse[1] - (float)top) / (float)row_h);
			if (row >= 0 && row < (int)self.entries.len())
			{
				bool repeated = row == self.last_click_row && now - self.last_click_at < DOUBLE_CLICK;
				self.selected = row;
				self.last_click_row = row;
				self.last_click_at = now;
				Entry entry = self.entries[row];
				if (entry.dir)
				{
					(void)self.activate_selected();
				}
				else if (repeated)
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
	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE))
	{
		self.consumed = true;
		(void)self.navigate_parent();
		return PickerAction.NONE;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP))
	{
		self.consumed = true;
		self.move_selection(-1);
		self.start_repeat((int)rl::RLKeyboardKey.UP, now);
	}
	else if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN))
	{
		self.consumed = true;
		self.move_selection(1);
		self.start_repeat((int)rl::RLKeyboardKey.DOWN, now);
	}
	else
	{
		self.update_repeat(now);
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
	self.sync_preview(now);
	self.update_preview(now);
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

fn void ImagePicker.draw_preview(&self, Rect panel, RLFont font)
{
	Rect area = preview_area(panel);
	float pad = (float)ui::px(10);
	ui::rounded_rect(area, ui::corner_radius(), theme::current().panel_bg_alt);
	ui::rounded_rect_lines(area, ui::corner_radius(), 1.0f, theme::current().panel_border);
	Rect inner = {
		.x = area.x + pad,
		.y = area.y + pad,
		.width = area.width - pad * 2.0f,
		.height = area.height - pad * 2.0f,
	};
	switch (self.preview.kind)
	{
		case PreviewKind.EMPTY:
			draw_text(font, "Select a file", inner.x, inner.y, (float)ui::tpx(15), theme::current().panel_dim);
		case PreviewKind.PARENT:
			draw_text(font, "..", inner.x, inner.y, (float)ui::tpx(24), theme::current().panel_text);
			draw_text(font, "Parent folder", inner.x, inner.y + (float)ui::px(34), (float)ui::tpx(14), theme::current()
				.panel_dim);
		case PreviewKind.FOLDER:
			icons::draw_folder(
				false,
				{
					.x = inner.x,
					.y = inner.y,
					.width = (float)ui::px(42),
					.height = (float)ui::px(42),
				},
				rl::WHITE
			);
			draw_text(
				font,
				file_name(self.preview.path),
				inner.x,
				inner.y + (float)ui::px(50),
				(float)ui::tpx(16),
				theme::current()
				.panel_text);
			draw_text(font, "Folder", inner.x, inner.y + (float)ui::px(74), (float)ui::tpx(14), theme::current()
				.panel_dim);
		case PreviewKind.LOADING:
			draw_text(font, "Loading preview…", inner.x, inner.y, (float)ui::tpx(15), theme::current().panel_dim);
		case PreviewKind.FAILED:
			draw_text(font, "No preview", inner.x, inner.y, (float)ui::tpx(16), theme::current().panel_text);
			draw_text(
				font,
				"Unsupported or unreadable image",
				inner.x,
				inner.y + (float)ui::px(24),
				(float)ui::tpx(14),
				theme::current()
				.panel_dim);
		case PreviewKind.IMAGE:
			Rect image_area = inner;
			image_area.height -= (float)ui::px(54);
			float square = (float)ui::px(16);
			RLColor dark = theme::current().panel_bg;
			RLColor light = theme::current().panel_bg_alt;
			for (float y = image_area.y; y < image_area.y + image_area.height; y += square)
			{
				for (float x = image_area.x; x < image_area.x + image_area.width; x += square)
				{
					bool alt = ((int)((x - image_area.x) / square) + (int)((y - image_area.y) / square)) % 2 == 1;
					rl::draw_rectangle(
						(int)x,
						(int)y,
						(int)math::min(square, image_area.x + image_area.width - x),
						(int)math::min(square, image_area.y + image_area.height - y),
						alt ? light : dark
					);
				}
			}
			Rect dest = contain_rect(self.preview.width, self.preview.height, image_area);
			rl::draw_texture_pro(
				self.preview.texture,
				{ 0.0f, 0.0f, (float)self.preview.width, (float)self.preview.height },
				dest,
				{ 0.0f, 0.0f },
				0.0f,
				rl::WHITE
			);
			float info_y = inner.y + inner.height - (float)ui::px(44);
			draw_text(font, file_name(self.preview.path), inner.x, info_y, (float)ui::tpx(14), theme::current()
				.panel_text);
			@pool()
			{
				String size = string::format(tmem, "%dx%d", self.preview.width, self.preview.height);
				draw_text(font, size, inner.x, info_y + (float)ui::px(18), (float)ui::tpx(13), theme::current()
					.panel_dim);
			};
	}
}

fn void ImagePicker.draw(&self)
{
	if (!self.open) return;
	Rect panel  = self.panel_rect();
	RLFont font = ui::font();
	ui::rounded_rect(panel, ui::corner_radius(), theme::current().panel_bg);
	ui::rounded_top(
		{
			.x = panel.x,
			.y = panel.y,
			.width = panel.width,
			.height = (float)ui::px(HEADER_HEIGHT),
		},
		ui::corner_radius(),
		theme::current()
		.panel_bg_alt);
	ui::rounded_rect_lines(panel, ui::corner_radius(), 1.0f, theme::current().panel_border);

	rl::begin_scissor_mode(
		(int)panel.x + ui::px(10),
		(int)panel.y,
		(int)list_width(panel) - ui::px(20),
		ui::px(HEADER_HEIGHT)
	);
	draw_text(
		font,
		self.dir.len > 0 ? self.dir : "Select an image",
		panel.x + (float)ui::px(10),
		panel.y + (float)ui::px(6),
		(float)ui::tpx(16),
		theme::current()
		.panel_text);
	rl::end_scissor_mode();

	int top  = (int)panel.y + ui::px(HEADER_HEIGHT) + ui::px(8);
	int last = math::min(self.scroll + VISIBLE_ROWS, (int)self.entries.len());
	if (self.entries.len() == 0)
	{
		draw_text(
			font,
			"No images or folders here",
			panel.x + (float)ui::px(12),
			(float)top,
			(float)ui::tpx(16),
			theme::current()
			.panel_dim);
	}
	rl::begin_scissor_mode(
		(int)panel.x + ui::px(4),
		top,
		(int)list_width(panel) - ui::px(4),
		(int)panel.height - ui::px(HEADER_HEIGHT) - ui::px(FOOTER_HEIGHT) - ui::px(8)
	);
	for (int i = self.scroll; i < last; i++)
	{
		int row_y = top + (i - self.scroll) * ui::px(ROW_HEIGHT);
		if (i == self.selected) ui::row(
			{
				.x = panel.x + (float)ui::px(4),
				.y = (float)(row_y - ui::px(2)),
				.width = list_width(panel) - (float)ui::px(8),
				.height = (float)ui::px(ROW_HEIGHT),
			},
			theme::current()
			.panel_selected);
		Entry entry   = self.entries[i];
		float icon    = (float)ui::px(16);
		float label_x = panel.x + (float)ui::px(12);
		bool has_icon = false;
		if (entry.dir)
		{
			has_icon = icons::draw_folder(
				false,
				{
					.x = panel.x + (float)ui::px(10),
					.y = (float)row_y,
					.width = icon,
					.height = icon,
				},
				rl::WHITE
			);
		}
		else
		{
			has_icon = icons::draw_file(
				entry.path,
				{
					.x = panel.x + (float)ui::px(10),
					.y = (float)row_y,
					.width = icon,
					.height = icon,
				},
				rl::WHITE
			);
		}
		if (has_icon) label_x += icon + (float)ui::px(4);
		draw_text(
			font,
			entry.parent ? ".." : file_name(entry.path),
			label_x,
			(float)row_y,
			(float)ui::tpx(16),
			theme::current()
			.panel_text);
	}
	rl::end_scissor_mode();

	if (preview_visible(panel)) self.draw_preview(panel, font);
	draw_text(
		font,
		"Enter/double-click: select    Backspace/..: up    Esc: cancel",
		panel.x + (float)ui::px(10),
		panel.y + panel.height - (float)ui::px(FOOTER_HEIGHT) + (float)ui::px(4),
		(float)ui::tpx(14),
		theme::current()
		.panel_dim);
}