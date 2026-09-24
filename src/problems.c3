module yun::problems;

import raylib6::rl;
import std::collections::list;
import std::core::dstring;
import std::core::mem::alloc;
import std::math;
import yun::lsp;
import yun::theme;

const int ROW_HEIGHT       = 24;
const int PADDING          = 10;
const int PANEL_WIDTH      = 720;
const int MAX_VISIBLE_ROWS = 14;
const int TOP_MARGIN       = 24;
const float TITLE_HEIGHT   = 28.0f;

struct ProblemEntry
{
	String path;
	uint line;
	uint character;
	int severity;
	String message;
}

struct ProblemRow
{
	bool header;
	String label;
	int entry;
}

struct Problems
{
	Allocator allocator;
	bool open;
	List{ProblemEntry} entries;
	List{ProblemRow} rows;
	int selected;
	int scroll;
}

fn void Problems.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.open = false;
	self.entries.init(allocator);
	self.rows.init(allocator);
	self.selected = 0;
	self.scroll = 0;
}

fn void Problems.free_contents(&self)
{
	for (sz i = 0; i < self.entries.len(); i++)
	{
		if (self.entries[i].path.len) self.entries[i].path.free(self.allocator);
		if (self.entries[i].message.len) self.entries[i].message.free(self.allocator);
	}
	self.entries.clear();
	for (sz i = 0; i < self.rows.len(); i++)
	{
		if (self.rows[i].header && self.rows[i].label.len) self.rows[i].label.free(self.allocator);
	}
	self.rows.clear();
}

fn void Problems.build_rows(&self)
{
	for (sz i = 0; i < self.rows.len(); i++)
	{
		if (self.rows[i].header && self.rows[i].label.len) self.rows[i].label.free(self.allocator);
	}
	self.rows.clear();
	for (sz i = 0; i < self.entries.len(); i++)
	{
		bool new_file = i == 0 || self.entries[i].path.compare_to(self.entries[i - 1].path) != 0;
		if (new_file)
		{
			self.rows.push({ .header = true, .label = self.entries[i].path.copy(self.allocator), .entry = -1 });
		}
		self.rows.push({ .header = false, .label = "", .entry = (int)i });
	}
}

fn void Problems.show(&self)
{
	self.free_contents();
	@pool()
	{
		List{lsp::LspDiagnosticRef} refs;
		refs.init(tmem);
		lsp::lsp_collect_all(&refs);
		for (sz i = 0; i < refs.len(); i++)
		{
			ProblemEntry entry;
			entry.path = refs[i].path.copy(self.allocator);
			entry.line = refs[i].diag.start_line;
			entry.character = refs[i].diag.start_character;
			entry.severity = refs[i].diag.severity;
			entry.message = refs[i].diag.message.copy(self.allocator);
			self.entries.push(entry);
		}
	};
	self.build_rows();
	self.selected = self.first_selectable();
	self.scroll = 0;
	self.open = true;
}

fn void Problems.close(&self)
{
	self.open = false;
}

fn int Problems.first_selectable(&self)
{
	for (sz i = 0; i < self.rows.len(); i++)
	{
		if (!self.rows[i].header) return (int)i;
	}
	return 0;
}

fn ProblemEntry* Problems.entry_at(&self, int index)
{
	if (index < 0 || index >= (int)self.entries.len()) return null;
	return &self.entries[index];
}

fn int Problems.selected_entry(&self)
{
	if (self.selected < 0 || self.selected >= (int)self.rows.len()) return -1;
	if (self.rows[self.selected].header) return -1;
	return self.rows[self.selected].entry;
}

fn void Problems.clamp_scroll(&self)
{
	int rows = (int)self.rows.len();
	if (self.selected < self.scroll) self.scroll = self.selected;
	if (self.selected >= self.scroll + MAX_VISIBLE_ROWS) self.scroll = self.selected - MAX_VISIBLE_ROWS + 1;
	int max_scroll = rows - MAX_VISIBLE_ROWS;
	if (max_scroll < 0) max_scroll = 0;
	if (self.scroll > max_scroll) self.scroll = max_scroll;
	if (self.scroll < 0) self.scroll = 0;
}

fn void Problems.move_selection(&self, int delta)
{
	int count = (int)self.rows.len();
	if (count == 0) return;
	int step      = delta > 0 ? 1 : -1;
	int remaining = delta > 0 ? delta : -delta;
	int current   = self.selected;
	for (int i = 0; i < remaining; i++)
	{
		int next = current;
		for (int j = 0; j < count; j++)
		{
			next += step;
			if (next < 0) next = count - 1;
			if (next >= count) next = 0;
			if (!self.rows[next].header) break;
		}
		current = next;
	}
	self.selected = current;
	self.clamp_scroll();
}

fn Rect Problems.panel_rect(&self)
{
	int rows = (int)self.rows.len();
	if (rows > MAX_VISIBLE_ROWS) rows = MAX_VISIBLE_ROWS;
	if (rows < 1) rows = 1;
	int height = PADDING * 2 + (int)TITLE_HEIGHT + rows * ROW_HEIGHT;
	int x      = (rl::get_screen_width() - PANEL_WIDTH) / 2;
	int y      = (int)TOP_MARGIN;
	return { .x = (float)x, .y = (float)y, .width = (float)PANEL_WIDTH, .height = (float)height };
}

fn float Problems.list_y(&self)
{
	return self.panel_rect().y + (float)PADDING + TITLE_HEIGHT;
}

fn int Problems.row_at(&self, RLVector2 mouse)
{
	float list_y = self.list_y();
	if (mouse[1] < list_y) return -1;
	int row = (int)((mouse[1] - list_y) / (float)ROW_HEIGHT) + self.scroll;
	if (row < 0 || row >= (int)self.rows.len()) return -1;
	return row;
}

fn int Problems.update(&self)
{
	if (!self.open) return -1;

	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		self.open = false;
		return -1;
	}
	if (rl::is_key_pressed(
		rl::RLKeyboardKey.DOWN
	) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.DOWN)) self.move_selection(1);
	if (rl::is_key_pressed(
		rl::RLKeyboardKey.UP
	) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.UP)) self.move_selection(-1);
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_DOWN)) self.move_selection(MAX_VISIBLE_ROWS);
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_UP)) self.move_selection(-MAX_VISIBLE_ROWS);
	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER))
	{
		int entry = self.selected_entry();
		if (entry >= 0)
		{
			self.open = false;
			return entry;
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
	if (row >= 0 && !self.rows[row].header)
	{
		self.selected = row;
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
		{
			int entry = self.rows[row].entry;
			self.open = false;
			return entry;
		}
	}
	return -1;
}

fn RLColor severity_color(int severity)
{
	switch (severity)
	{
		case lsp::DIAGNOSTIC_ERROR:
			return theme::current().diag_error;
		case lsp::DIAGNOSTIC_WARNING:
			return theme::current().diag_warning;
		case lsp::DIAGNOSTIC_INFO:
			return theme::current().diag_info;
		default:
			return theme::current().diag_hint;
	}
}

fn String severity_letter(int severity)
{
	switch (severity)
	{
		case lsp::DIAGNOSTIC_ERROR:
			return "E";
		case lsp::DIAGNOSTIC_WARNING:
			return "W";
		case lsp::DIAGNOSTIC_INFO:
			return "I";
		default:
			return "H";
	}
}

fn void draw_text(RLFont font, String text, float x, float y, float size, RLColor color)
{
	if (text.len == 0) return;
	@pool()
	{
		rl::draw_text_ex(font, text.zstr_tcopy(), { x, y }, size, 0.0f, color);
	};
}

fn void Problems.draw(&self, RLFont font)
{
	if (!self.open) return;

	Rect panel = self.panel_rect();
	rl::draw_rectangle_rec(panel, theme::current().panel_bg);
	rl::draw_rectangle_lines_ex(panel, 1.0f, theme::current().panel_border);

	@pool()
	{
		String title = string::format(tmem, "Problems (%d)", (long)self.entries.len());
		draw_text(font, title, panel.x + (float)PADDING, panel.y + (float)PADDING, 18.0f, theme::current().panel_text);
	};

	float list_y = self.list_y();
	if (self.rows.len() == 0)
	{
		draw_text(font, "No problems", panel.x + (float)PADDING, list_y + 4.0f, 16.0f, theme::current().panel_dim);
		return;
	}

	int shown = (int)self.rows.len() - self.scroll;
	if (shown > MAX_VISIBLE_ROWS) shown = MAX_VISIBLE_ROWS;
	rl::begin_scissor_mode((int)panel.x + 2, (int)list_y, (int)panel.width - 4, shown * ROW_HEIGHT);
	for (int slot = 0; slot < MAX_VISIBLE_ROWS; slot++)
	{
		int index = self.scroll + slot;
		if (index >= (int)self.rows.len()) break;
		ProblemRow row = self.rows[index];
		float row_y    = list_y + (float)slot * (float)ROW_HEIGHT;

		if (row.header)
		{
			draw_text(font, row.label, panel.x + (float)PADDING, row_y + 3.0f, 15.0f, theme::current().panel_header);
			continue;
		}

		if (index == self.selected)
		{
			rl::draw_rectangle((int)panel.x + 2, (int)row_y, (int)panel.width - 4, ROW_HEIGHT, theme::current()
				.panel_selected);
		}
		ProblemEntry* entry = self.entry_at(row.entry);
		if (!entry) continue;
		@pool()
		{
			String label = string::format(
				tmem,
				"%s  %d:%d  %s",
				severity_letter(entry.severity),
				(long)(entry.line + 1),
				(long)(entry.character + 1),
				entry.message
			);
			draw_text(font, label, panel.x + (float)PADDING + 16.0f, row_y + 3.0f, 16.0f, theme::current().panel_text);
		};
	}
	rl::end_scissor_mode();
}

fn float text_width(RLFont font, String text)
{
	if (text.len == 0) return 0.0f;
	float width = 0.0f;
	@pool()
	{
		width = rl::measure_text_ex(font, text.zstr_tcopy(), 14.0f, 0.0f)[0];
	};
	return width;
}

fn void wrap_text(Allocator allocator, RLFont font, float max_width, String text, List{String}* out)
{
	DString line;
	line.init(allocator, 64);
	usz i = 0;
	while (i < text.len)
	{
		if (text[i] == '\n')
		{
			out.push(line.str_view().copy(allocator));
			line.clear();
			i++;
			continue;
		}
		usz start = i;
		while (i < text.len && text[i] != ' ' && text[i] != '\n') i++;
		String word = text[start:i - start];
		if (i < text.len && text[i] == ' ') i++;

		bool fits = false;
		@pool()
		{
			if (line.len() == 0)
			{
				fits = text_width(font, word) <= max_width;
			}
			else
			{
				String candidate = string::format(tmem, "%s %s", line.str_view(), word);
				fits = text_width(font, candidate) <= max_width;
			}
		};
		if (fits)
		{
			if (line.len() > 0) line.append_char(' ');
			line.append_string(word);
		}
		else
		{
			if (line.len() > 0)
			{
				out.push(line.str_view().copy(allocator));
				line.clear();
			}
			line.append_string(word);
		}
	}
	out.push(line.str_view().copy(allocator));
	line.free();
}

fn void draw_tooltip(String message, RLVector2 screen_pos, RLFont font)
{
	if (message.len == 0) return;
	@pool()
	{
		List{String} lines;
		lines.init(tmem);
		wrap_text(tmem, font, 420.0f, message, &lines);

		int count = (int)lines.len();
		if (count > 12) count = 12;
		float width = 0.0f;
		for (int i = 0; i < count; i++)
		{
			float w = text_width(font, lines[(sz)i]);
			if (w > width) width = w;
		}
		float height = (float)count * 18.0f + 12.0f;
		Rect panel = {
			.x = screen_pos[0] + 14.0f,
			.y = screen_pos[1] + 14.0f,
			.width = width + 16.0f,
			.height = height,
		};
		if (panel.x + panel.width > (float)rl::get_screen_width()) panel.x = screen_pos[0] - panel.width - 8.0f;
		if (panel.y + panel.height > (float)rl::get_screen_height()) panel.y = screen_pos[1] - panel.height - 8.0f;
		if (panel.x < 4.0f) panel.x = 4.0f;
		if (panel.y < 4.0f) panel.y = 4.0f;

		rl::draw_rectangle_rec(panel, theme::current().panel_bg_alt);
		rl::draw_rectangle_lines_ex(panel, 1.0f, theme::current().panel_border);
		for (int i = 0; i < count; i++)
		{
			draw_text(font, lines[(sz)i], panel.x + 8.0f, panel.y + 6.0f + (float)i * 18.0f, 14.0f, theme::current()
				.panel_text);
		}
	};
}