module yun::console;

import raylib6::rl;
import std::core::dstring;
import std::math;
import yun::commands;
import yun::editor;
import yun::keymap;
import yun::theme;
import yun::ui;

const float DEFAULT_HEIGHT = 220.0f;
const float MIN_HEIGHT     = 120.0f;
const float HEADER_HEIGHT  = 30.0f;
const float INPUT_HEIGHT   = 34.0f;
const float PADDING        = 8.0f;
const float RESIZE_GRAB    = 5.0f;
const float BUTTON_WIDTH   = 54.0f;
const float BUTTON_HEIGHT  = 22.0f;
const float BUTTON_GAP     = 6.0f;
const int BUTTON_COUNT     = 4;
const int SCROLL_LINES     = 3;
const int FIND_QUERY_MAX   = 128;
const int FIND_MAX_MATCHES = 1000;

struct ConsoleFindMatch
{
	sz line;
	usz start;
	usz len;
}

enum ConsoleButton : int
{
	RUN,
	KILL,
	CLEAR,
	COPY,
	COUNT,
}

struct ConsolePanel
{
	bool visible;
	bool focused;
	float height;
	float setting_height;
	bool auto_scroll;
	int scroll;
	bool pinned;
	bool resizing;
	bool focus_requested;
	bool exit_requested;
	float input_scroll;
	float output_scroll_x;
	float output_max_width;
	int output_width_revision;
	bool selecting;
	bool has_selection;
	sz sel_anchor_line;
	usz sel_anchor_offset;
	sz sel_cursor_line;
	usz sel_cursor_offset;
	sz sel_first_line;
	double last_click_time;
	RLVector2 last_click_pos;
	bool completion_enabled;
	bool completion_active;
	bool completion_dismissed;
	int completion_index;
	sz completion_input_len;
	bool find_open;
	char[FIND_QUERY_MAX + 1] find_query;
	int find_len;
	ConsoleFindMatch[FIND_MAX_MATCHES] find_matches;
	int find_count;
	int find_index;
	int find_revision;
	bool find_dirty;
}

fn void ConsolePanel.init(&self)
{
	self.visible = false;
	self.focused = false;
	self.height = DEFAULT_HEIGHT;
	self.setting_height = DEFAULT_HEIGHT;
	self.auto_scroll = true;
	self.scroll = 0;
	self.pinned = true;
	self.resizing = false;
	self.focus_requested = false;
	self.exit_requested = false;
	self.input_scroll = 0.0f;
	self.output_scroll_x = 0.0f;
	self.output_max_width = 0.0f;
	self.output_width_revision = -1;
	self.selecting = false;
	self.has_selection = false;
	self.sel_anchor_line = 0;
	self.sel_anchor_offset = 0;
	self.sel_cursor_line = 0;
	self.sel_cursor_offset = 0;
	self.sel_first_line = 0;
	self.last_click_time = -1.0;
	self.last_click_pos = { 0.0f, 0.0f };
	self.completion_enabled = true;
	self.completion_active = false;
	self.completion_dismissed = false;
	self.completion_index = -1;
	self.completion_input_len = 0;
	self.find_open = false;
	self.find_query[0] = 0;
	self.find_len = 0;
	self.find_count = 0;
	self.find_index = 0;
	self.find_revision = -1;
	self.find_dirty = false;
}

fn void ConsolePanel.open(&self)
{
	self.visible = true;
	self.focused = true;
	self.pinned = self.auto_scroll;
	self.resizing = false;
	self.exit_requested = false;
}

fn void ConsolePanel.close(&self)
{
	self.visible = false;
	self.focused = false;
	self.resizing = false;
	self.clear_selection();
	self.find_open = false;
	self.find_count = 0;
	self.find_dirty = false;
}

fn void ConsolePanel.apply_settings(&self, ConsoleSettings settings)
{
	if (self.setting_height != settings.panel_height)
	{
		self.setting_height = settings.panel_height;
		if (!self.resizing) self.height = settings.panel_height;
	}
	if (!self.auto_scroll && settings.auto_scroll) self.pinned = true;
	self.auto_scroll = settings.auto_scroll;
	self.completion_enabled = settings.autocomplete;
	if (!self.completion_enabled)
	{
		self.completion_active = false;
		self.completion_index = -1;
	}
}

fn Rect console_panel_rect(float height, int screen_w, int screen_h)
{
	float h     = ui::pxf(height);
	float min_h = ui::pxf(MIN_HEIGHT);
	float max_h = (float)screen_h - ui::pxf(MIN_HEIGHT);
	if (h < min_h) h = min_h;
	if (h > max_h) h = max_h;
	if (h > (float)screen_h) h = (float)screen_h;
	return { .x = 0.0f, .y = (float)screen_h - h, .width = (float)screen_w, .height = h };
}

fn int console_max_scroll(int lines, int visible)
{
	int max = lines - visible;
	return max > 0 ? max : 0;
}

fn int console_clamp_scroll(int scroll, int lines, int visible)
{
	int max = console_max_scroll(lines, visible);
	if (scroll < 0) return 0;
	if (scroll > max) return max;
	return scroll;
}

fn float console_clamp_hscroll(float offset, float content_width, float view_width)
{
	float max = content_width - view_width;
	if (max <= 0.0f) return 0.0f;
	if (offset < 0.0f) return 0.0f;
	if (offset > max) return max;
	return offset;
}

fn usz console_offset_at_x(String text, float x, float char_width)
{
	if (x <= 0.0f || char_width <= 0.0f) return 0;
	float col = 0.0f;
	usz i     = 0;
	while (i < text.len)
	{
		usz next = i + 1;
		while (next < text.len && (((int)text[next] & 0xC0) == 0x80)) next++;
		if (col + char_width * 0.5f >= x) return i;
		col += char_width;
		i = next;
	}
	return text.len;
}

fn sz console_columns_before(String text, usz offset)
{
	if (offset > text.len) offset = text.len;
	sz columns = 0;
	usz i      = 0;
	while (i < offset)
	{
		i++;
		while (i < offset && (((int)text[i] & 0xC0) == 0x80)) i++;
		columns++;
	}
	return columns;
}

fn bool console_word_byte(int b)
{
	return (b >= 'a' && b <= 'z') || (b >= 'A' && b <= 'Z') || (b >= '0' && b <= '9') || b == '_';
}

fn void console_word_range(String text, usz offset, usz* start, usz* end)
{
	*start = 0;
	*end = 0;
	if (text.len == 0) return;
	if (offset > text.len) offset = text.len;
	if (offset == text.len) offset--;
	int b = (int)text[offset] & 0xFF;
	if (!console_word_byte(b)) return;
	usz s = offset;
	while (s > 0)
	{
		int prev = (int)text[s - 1] & 0xFF;
		if (!console_word_byte(prev)) break;
		s--;
	}
	usz e = offset;
	while (e < text.len && console_word_byte((int)text[e] & 0xFF)) e++;
	*start = s;
	*end = e;
}

fn String console_status_label(ConsoleStatus status)
{
	switch (status)
	{
		case ConsoleStatus.IDLE:
			return "Ready";
		case ConsoleStatus.RUNNING:
			return "Running";
		case ConsoleStatus.KILLING:
			return "Stopping";
		case ConsoleStatus.EXITED:
			return "Exit";
		case ConsoleStatus.KILLED:
			return "Killed";
		case ConsoleStatus.FAILED:
			return "Failed";
	}
}

fn Rect ConsolePanel.rect(&self)
{
	return console_panel_rect(self.height, rl::get_screen_width(), rl::get_screen_height());
}

fn bool ConsolePanel.contains_screen(&self, RLVector2 point)
{
	if (!self.visible) return false;
	Rect panel = self.rect();
	return point[0] >= panel.x && point[0] <= panel.x + panel.width && point[1] >= panel.y
		&& point[1] <= panel.y + panel.height;
}

fn Rect ConsolePanel.header_rect(&self)
{
	Rect panel = self.rect();
	return {
		.x = panel.x + ui::pxf(PADDING),
		.y = panel.y + ui::pxf(2.0f),
		.width = panel.width - ui::pxf(PADDING) * 2.0f,
		.height = ui::pxf(HEADER_HEIGHT),
	};
}

fn Rect ConsolePanel.output_rect(&self)
{
	Rect panel   = self.rect();
	float header = ui::pxf(HEADER_HEIGHT);
	float input  = ui::pxf(INPUT_HEIGHT);
	return {
		.x = panel.x,
		.y = panel.y + header,
		.width = panel.width,
		.height = panel.height - header - input,
	};
}

fn Rect ConsolePanel.input_rect(&self)
{
	Rect panel  = self.rect();
	float input = ui::pxf(INPUT_HEIGHT);
	return {
		.x = panel.x + ui::pxf(PADDING),
		.y = panel.y + panel.height - input,
		.width = panel.width - ui::pxf(PADDING) * 2.0f,
		.height = input - ui::pxf(PADDING) * 0.5f,
	};
}

fn Rect ConsolePanel.button_rect(&self, ConsoleButton button)
{
	Rect panel = self.rect();
	Rect input = self.input_rect();
	float bw   = ui::pxf(BUTTON_WIDTH);
	float bh   = ui::pxf(BUTTON_HEIGHT);
	float gap  = ui::pxf(BUTTON_GAP);
	float pad  = ui::pxf(PADDING);
	int index  = (int)button;
	return {
		.x = panel.x + panel.width - pad - bw - (float)index * (bw + gap),
		.y = input.y + (input.height - bh) / 2.0f,
		.width = bw,
		.height = bh,
	};
}

fn bool ConsolePanel.button_enabled(&self, ConsoleButton button, Console* console)
{
	switch (button)
	{
		case ConsoleButton.RUN:
			return !console.running() && console.input.len() > 0;
		case ConsoleButton.KILL:
			return console.running();
		case ConsoleButton.CLEAR:
		case ConsoleButton.COPY:
			return console.buffer.line_count() > 0;
		case ConsoleButton.COUNT:
			return false;
	}
}

fn int ConsolePanel.button_at(&self, RLVector2 point, Console* console)
{
	for (int i = 0; i < BUTTON_COUNT; i++)
	{
		ConsoleButton button = (ConsoleButton)i;
		if (!self.button_enabled(button, console)) continue;
		Rect r = self.button_rect(button);
		if (point[0] >= r.x && point[0] <= r.x + r.width && point[1] >= r.y && point[1] <= r.y + r.height) return i;
	}
	return -1;
}

fn int ConsolePanel.visible_rows(&self, EditorMetrics metrics)
{
	Rect output = self.output_rect();
	if (metrics.line_height <= 0.0f) return 1;
	int rows = (int)(output.height / metrics.line_height);
	return rows > 0 ? rows : 1;
}

fn float ConsolePanel.output_width(&self, Console* console, EditorMetrics metrics)
{
	if (self.output_width_revision == console.buffer.revision) return self.output_max_width;
	float max = 0.0f;
	for (sz i = 0; i < console.buffer.line_count(); i++)
	{
		ConsoleLine* line = console.buffer.line_at(i);
		float width       = (float)line.text.len * metrics.char_width;
		if (width > max) max = width;
	}
	self.output_max_width = max;
	self.output_width_revision = console.buffer.revision;
	return max;
}

fn void ConsolePanel.scroll_horizontal(&self, Console* console, EditorMetrics metrics, float delta)
{
	Rect output   = self.output_rect();
	float view    = output.width - ui::pxf(PADDING) * 2.0f;
	float content = self.output_width(console, metrics);
	self.output_scroll_x = console_clamp_hscroll(self.output_scroll_x + delta, content, view);
}

fn void ConsolePanel.clear_selection(&self)
{
	self.selecting = false;
	self.has_selection = false;
	self.sel_anchor_line = 0;
	self.sel_anchor_offset = 0;
	self.sel_cursor_line = 0;
	self.sel_cursor_offset = 0;
}

fn bool ConsolePanel.selection_range(
	&self,
	Console* console,
	sz* start_line,
	usz* start_offset,
	sz* end_line,
	usz* end_offset
)
{
	if (!self.has_selection) return false;
	if (console.buffer.first != self.sel_first_line)
	{
		self.clear_selection();
		return false;
	}
	bool forward = self.sel_anchor_line < self.sel_cursor_line
		|| (self.sel_anchor_line == self.sel_cursor_line && self.sel_anchor_offset <= self.sel_cursor_offset);
	if (forward)
	{
		*start_line = self.sel_anchor_line;
		*start_offset = self.sel_anchor_offset;
		*end_line = self.sel_cursor_line;
		*end_offset = self.sel_cursor_offset;
	}
	else
	{
		*start_line = self.sel_cursor_line;
		*start_offset = self.sel_cursor_offset;
		*end_line = self.sel_anchor_line;
		*end_offset = self.sel_anchor_offset;
	}
	if (*start_line == *end_line && *start_offset == *end_offset) return false;
	ConsoleLine* line = console.buffer.line_at(*start_line);
	if (!line) return false;
	if (*start_offset > line.text.len) *start_offset = line.text.len;
	line = console.buffer.line_at(*end_line);
	if (!line) return false;
	if (*end_offset > line.text.len) *end_offset = line.text.len;
	return true;
}

fn int ConsolePanel.line_at_mouse(&self, Console* console, EditorMetrics metrics, RLVector2 mouse, Rect output)
{
	int count = (int)console.buffer.line_count();
	if (count == 0) return -1;
	int scroll = self.scroll_for(console, metrics);
	float rel  = (mouse[1] - output.y) / metrics.line_height;
	int line   = scroll + (int)rel;
	if (rel < 0.0f) line = scroll;
	if (line < 0) line = 0;
	if (line >= count) line = count - 1;
	return line;
}

fn void ConsolePanel.begin_selection(&self, Console* console, EditorMetrics metrics, RLVector2 mouse, bool double_click)
{
	Rect output = self.output_rect();
	int line    = self.line_at_mouse(console, metrics, mouse, output);
	if (line < 0) return;
	ConsoleLine* text_line = console.buffer.line_at(line);
	if (!text_line) return;
	float x    = mouse[0] - (output.x + ui::pxf(PADDING) - self.output_scroll_x);
	usz offset = console_offset_at_x(text_line.text, x, metrics.char_width);
	self.sel_first_line = console.buffer.first;
	self.sel_anchor_line = line;
	self.sel_anchor_offset = offset;
	self.sel_cursor_line = line;
	self.sel_cursor_offset = offset;
	if (double_click)
	{
		usz start = 0;
		usz end   = 0;
		console_word_range(text_line.text, offset, &start, &end);
		self.sel_anchor_offset = start;
		self.sel_cursor_offset = end;
		self.has_selection = start != end;
		self.selecting = false;
	}
	else
	{
		self.has_selection = false;
		self.selecting = true;
	}
}

fn void ConsolePanel.update_selection(&self, Console* console, EditorMetrics metrics, RLVector2 mouse)
{
	Rect output = self.output_rect();
	int line    = self.line_at_mouse(console, metrics, mouse, output);
	if (line < 0) return;
	ConsoleLine* text_line = console.buffer.line_at(line);
	if (!text_line) return;
	float x = mouse[0] - (output.x + ui::pxf(PADDING) - self.output_scroll_x);
	self.sel_cursor_line = line;
	self.sel_cursor_offset = console_offset_at_x(text_line.text, x, metrics.char_width);
	self.has_selection = self.sel_anchor_line != self.sel_cursor_line
		|| self.sel_anchor_offset != self.sel_cursor_offset;
}

fn String ConsolePanel.selection_text(&self, Console* console, Allocator allocator)
{
	sz start_line;
	usz start_offset;
	sz end_line;
	usz end_offset;
	if (!self.selection_range(console, &start_line, &start_offset, &end_line, &end_offset)) return "";
	DString out;
	out.init(allocator);
	for (sz i = start_line; i <= end_line; i++)
	{
		ConsoleLine* line = console.buffer.line_at(i);
		if (!line) break;
		usz a = i == start_line ? start_offset : 0;
		usz b = i == end_line ? end_offset : line.text.len;
		if (b > a) out.append_string(line.text[a:b - a]);
		if (i != end_line) out.append_char('\n');
	}
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn void ConsolePanel.copy_selection_or_all(&self, Console* console)
{
	String selected = self.selection_text(console, tmem);
	if (selected.len > 0)
	{
		rl::set_clipboard_text(selected.zstr_tcopy());
	}
	else
	{
		self.copy_output(console);
	}
}

fn int ConsolePanel.max_scroll(&self, Console* console, EditorMetrics metrics)
{
	return console_max_scroll((int)console.buffer.line_count(), self.visible_rows(metrics));
}

fn int ConsolePanel.scroll_for(&self, Console* console, EditorMetrics metrics)
{
	int lines   = (int)console.buffer.line_count();
	int visible = self.visible_rows(metrics);
	if (self.pinned) return console_max_scroll(lines, visible);
	return console_clamp_scroll(self.scroll, lines, visible);
}

fn void ConsolePanel.scroll_by(&self, Console* console, EditorMetrics metrics, int delta)
{
	int lines   = (int)console.buffer.line_count();
	int visible = self.visible_rows(metrics);
	int max     = console_max_scroll(lines, visible);
	if (self.pinned) self.scroll = max;
	self.scroll = console_clamp_scroll(self.scroll + delta, lines, visible);
	self.pinned = self.scroll >= max;
}

fn void ConsolePanel.copy_output(&self, Console* console)
{
	DString out;
	out.init(mem);
	for (sz i = 0; i < console.buffer.line_count(); i++)
	{
		ConsoleLine* line = console.buffer.line_at(i);
		out.append_string(line.text);
		out.append_char('\n');
	}
	rl::set_clipboard_text(out.zstr_view());
	out.free();
}

fn bool ctrl_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_CONTROL) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_CONTROL);
}

fn bool shift_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_SHIFT) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SHIFT);
}

fn bool super_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_SUPER) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SUPER);
}

fn void drain_chars()
{
	while (rl::get_char_pressed() != 0)
	{
	}
}

fn void ConsolePanel.paste(&self, Console* console)
{
	String clip = rl::get_clipboard_text().str_view();
	usz end     = 0;
	while (end < clip.len && clip[end] != '\n' && clip[end] != '\r') end++;
	console.input.insert_string(clip[0:end]);
}

fn bool console_prefix_match(String entry, String input, bool fold)
{
	if (entry.len <= input.len) return false;
	for (usz i = 0; i < input.len; i++)
	{
		int a = (int)entry[i] & 0xFF;
		int b = (int)input[i] & 0xFF;
		if (fold)
		{
			a = lower_ascii(a);
			b = lower_ascii(b);
		}
		if (a != b) return false;
	}
	return true;
}

fn void ConsolePanel.refresh_completion(&self, Console* console)
{
	self.completion_active = false;
	self.completion_index = -1;
	if (!self.completion_enabled || self.completion_dismissed || console.history.browsing) return;
	if (console.input.cursor != console.input.len() || console.input.len() == 0) return;
	String input =  console.input.text_view();
	int found    = -1;
	for (int pass = 0; pass < 2 && found < 0; pass++)
	{
		bool fold = pass == 1;
		for (sz i = console.history.entries.len() - 1; i >= 0; i--)
		{
			String entry = console.history.entries[i];
			if (console_prefix_match(entry, input, fold))
			{
				found = (int)i;
				break;
			}
		}
	}
	if (found < 0) return;
	self.completion_index = found;
	self.completion_active = true;
}

fn String ConsolePanel.completion_candidate(&self, Console* console)
{
	if (!self.completion_active || self.completion_index < 0
		|| self.completion_index >= (int)console.history.entries.len()) return "";
	return console.history.entries[self.completion_index];
}

fn String ConsolePanel.completion_suffix(&self, Console* console)
{
	if (!self.completion_active) return "";
	String candidate = self.completion_candidate(console);
	if (candidate.len <= console.input.len()) return "";
	return candidate[console.input.len():candidate.len - console.input.len()];
}

fn void ConsolePanel.accept_completion(&self, Console* console)
{
	String candidate = self.completion_candidate(console);
	if (candidate.len == 0) return;
	console.input.set(candidate);
	self.completion_active = false;
	self.completion_index = -1;
	self.completion_dismissed = false;
	self.completion_input_len = console.input.len();
}

fn void ConsolePanel.dismiss_completion(&self)
{
	self.completion_active = false;
	self.completion_index = -1;
	self.completion_dismissed = true;
}

fn void ConsolePanel.sync_completion_input(&self, Console* console)
{
	if (console.input.len() == self.completion_input_len) return;
	self.completion_input_len = console.input.len();
	self.completion_dismissed = false;
}

fn String ConsolePanel.find_query_view(&self)
{
	return (String)self.find_query[0:self.find_len];
}

fn void ConsolePanel.find_close(&self)
{
	self.find_open = false;
	self.find_count = 0;
	self.find_dirty = false;
}

fn void ConsolePanel.find_open_panel(&self)
{
	self.find_open = true;
	self.find_dirty = true;
	self.find_index = 0;
}

fn void ConsolePanel.find_set(&self, String query)
{
	self.find_len = 0;
	for (usz i = 0; i < query.len && self.find_len < FIND_QUERY_MAX; i++)
	{
		self.find_query[self.find_len] = query[i];
		self.find_len++;
	}
	self.find_query[self.find_len] = 0;
	self.find_dirty = true;
}

fn void ConsolePanel.find_backspace(&self)
{
	if (self.find_len == 0) return;
	self.find_len--;
	while (self.find_len > 0 && (((int)self.find_query[self.find_len] & 0xC0) == 0x80)) self.find_len--;
	self.find_query[self.find_len] = 0;
}

fn int lower_ascii(int c)
{
	if (c >= 'A' && c <= 'Z') return c + ('a' - 'A');
	return c;
}

fn void ConsolePanel.find_refresh(&self, Console* console)
{
	if (!self.find_open) return;
	if (!self.find_dirty && self.find_revision == console.buffer.revision) return;
	self.find_revision = console.buffer.revision;
	self.find_dirty = false;
	self.find_count = 0;
	if (self.find_len == 0) return;
	String query = self.find_query_view();
	for (sz line_index = 0; line_index < console.buffer.line_count(); line_index++)
	{
		ConsoleLine* line = console.buffer.line_at(line_index);
		if (line.text.len < query.len) continue;
		usz limit = line.text.len - query.len;
		for (usz i = 0; i <= limit; i++)
		{
			bool match = true;
			for (usz j = 0; j < query.len; j++)
			{
				if (lower_ascii((int)line.text[i + j] & 0xFF) != lower_ascii((int)query[j] & 0xFF))
				{
					match = false;
					break;
				}
			}
			if (!match) continue;
			if (self.find_count < FIND_MAX_MATCHES)
			{
				self.find_matches[self.find_count] = { .line = line_index, .start = i, .len = query.len };
				self.find_count++;
			}
		}
	}
	if (self.find_count == 0)
	{
		self.find_index = 0;
	}
	else if (self.find_index >= self.find_count)
	{
		self.find_index = self.find_count - 1;
	}
}

fn void ConsolePanel.find_next(&self, Console* console, EditorMetrics metrics, int dir)
{
	self.find_refresh(console);
	if (self.find_count == 0) return;
	int next = self.find_index + dir;
	next = (next % self.find_count + self.find_count) % self.find_count;
	self.find_index = next;
	ConsoleFindMatch match = self.find_matches[next];
	int visible            = self.visible_rows(metrics);
	int target             = (int)match.line - visible / 2;
	int max                = self.max_scroll(console, metrics);
	if (target < 0) target = 0;
	if (target > max) target = max;
	self.scroll = target;
	self.pinned = false;
}

fn bool ConsolePanel.update_input(&self, Console* console, keymap::Keymap* keymap, EditorMetrics metrics)
{
	if (!self.visible) return false;
	self.exit_requested = false;
	bool ctrl  = ctrl_down();
	bool super = super_down();

	if (self.find_open)
	{
		if (keymap.pressed(
			(int)commands::CommandId.CONSOLE_FIND,
			commands::CTX_CONSOLE
		) || rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
		{
			self.find_close();
			drain_chars();
			return false;
		}
		if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER) || rl::is_key_pressed(rl::RLKeyboardKey.KP_ENTER))
		{
			self.find_next(console, metrics, shift_down() ? -1 : 1);
			drain_chars();
			return false;
		}
		if (rl::is_key_pressed(rl::RLKeyboardKey.UP))
		{
			self.find_next(console, metrics, -1);
			drain_chars();
			return false;
		}
		if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN))
		{
			self.find_next(console, metrics, 1);
			drain_chars();
			return false;
		}
		if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
		{
			self.find_backspace();
			self.find_dirty = true;
			self.find_refresh(console);
			drain_chars();
			return false;
		}
		if (!ctrl && !super)
		{
			int codepoint = rl::get_char_pressed();
			while (codepoint != 0)
			{
				if (codepoint >= 32 && codepoint < 0x80 && self.find_len < FIND_QUERY_MAX)
				{
					self.find_query[self.find_len] = (char)codepoint;
					self.find_len++;
					self.find_query[self.find_len] = 0;
					self.find_dirty = true;
				}
				codepoint = rl::get_char_pressed();
			}
			self.find_refresh(console);
		}
		else
		{
			drain_chars();
		}
		return false;
	}

	if (keymap.pressed((int)commands::CommandId.CONSOLE_FIND, commands::CTX_CONSOLE))
	{
		self.find_open_panel();
		self.find_refresh(console);
		drain_chars();
		return false;
	}

	self.sync_completion_input(console);
	self.refresh_completion(console);

	if (keymap.pressed((int)commands::CommandId.CONSOLE_LEAVE_FOCUS, commands::CTX_CONSOLE))
	{
		drain_chars();
		if (self.completion_active)
		{
			self.dismiss_completion();
			return false;
		}
		self.exit_requested = true;
		return true;
	}
	if (self.completion_active && (rl::is_key_pressed(
		rl::RLKeyboardKey.RIGHT
	) || rl::is_key_pressed(rl::RLKeyboardKey.END) || rl::is_key_pressed(rl::RLKeyboardKey.TAB)))
	{
		self.accept_completion(console);
		drain_chars();
		return false;
	}
	if (keymap.pressed((int)commands::CommandId.CONSOLE_COPY, commands::CTX_CONSOLE))
	{
		self.copy_selection_or_all(console);
		drain_chars();
		return false;
	}
	if (keymap.pressed((int)commands::CommandId.CONSOLE_PASTE, commands::CTX_CONSOLE))
	{
		self.paste(console);
		self.sync_completion_input(console);
		drain_chars();
		return false;
	}
	if (keymap.pressed((int)commands::CommandId.CONSOLE_CLEAR, commands::CTX_CONSOLE))
	{
		console.clear();
		self.scroll = 0;
		self.output_scroll_x = 0.0f;
		self.pinned = self.auto_scroll;
		self.clear_selection();
		drain_chars();
		return false;
	}
	if (keymap.pressed((int)commands::CommandId.CONSOLE_KILL, commands::CTX_CONSOLE))
	{
		console.kill();
		drain_chars();
		return false;
	}

	if (keymap.pressed(
		(int)commands::CommandId.CONSOLE_RUN,
		commands::CTX_CONSOLE
	) || rl::is_key_pressed(rl::RLKeyboardKey.KP_ENTER))
	{
		(void)console.submit();
		self.pinned = self.auto_scroll;
		self.scroll = self.max_scroll(console, metrics);
		self.input_scroll = 0.0f;
	}
	if (keymap.pressed_repeat((int)commands::CommandId.CONSOLE_HISTORY_PREV, commands::CTX_CONSOLE))
	{
		(void)console.history.previous(&console.input);
		self.input_scroll = 0.0f;
	}
	if (keymap.pressed_repeat((int)commands::CommandId.CONSOLE_HISTORY_NEXT, commands::CTX_CONSOLE))
	{
		(void)console.history.next(&console.input);
		self.input_scroll = 0.0f;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.LEFT) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.LEFT))
	{
		console.input.move_left();
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.RIGHT) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.RIGHT))
	{
		console.input.move_right();
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.HOME))
	{
		console.input.home();
		self.input_scroll = 0.0f;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.END))
	{
		console.input.end();
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.DELETE))
	{
		console.input.delete_forward();
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		console.input.backspace();
	}
	if (keymap.pressed((int)commands::CommandId.CONSOLE_SCROLL_UP, commands::CTX_CONSOLE))
	{
		self.scroll_by(console, metrics, -self.visible_rows(metrics));
	}
	if (keymap.pressed((int)commands::CommandId.CONSOLE_SCROLL_DOWN, commands::CTX_CONSOLE))
	{
		self.scroll_by(console, metrics, self.visible_rows(metrics));
	}

	if (!ctrl && !super)
	{
		int codepoint = rl::get_char_pressed();
		while (codepoint != 0)
		{
			console.input.insert_codepoint(codepoint);
			codepoint = rl::get_char_pressed();
		}
	}
	else
	{
		drain_chars();
	}
	self.sync_completion_input(console);
	return false;
}

fn void ConsolePanel.update_mouse(&self, Console* console, EditorMetrics metrics, RLVector2 mouse)
{
	self.focus_requested = false;
	if (!self.visible) return;
	if (self.has_selection && console.buffer.first != self.sel_first_line) self.clear_selection();
	Rect panel  = self.rect();
	Rect input  = self.input_rect();
	Rect output = self.output_rect();

	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		if (mouse[1] >= panel.y && mouse[1] <= panel.y + ui::pxf(RESIZE_GRAB))
		{
			self.resizing = true;
		}
		else
		{
			int button = self.button_at(mouse, console);
			if (button >= 0)
			{
				switch ((ConsoleButton)button)
				{
					case ConsoleButton.RUN:
						(void)console.submit();
						self.pinned = self.auto_scroll;
						self.input_scroll = 0.0f;
						break;
					case ConsoleButton.KILL:
						console.kill();
						self.clear_selection();
						break;
					case ConsoleButton.CLEAR:
						console.clear();
						self.scroll = 0;
						self.output_scroll_x = 0.0f;
						self.pinned = true;
						self.clear_selection();
						break;
					case ConsoleButton.COPY:
						self.copy_selection_or_all(console);
						break;
					case ConsoleButton.COUNT:
						break;
				}
				self.focus_requested = true;
			}
			else if (mouse[0] >= output.x && mouse[0] <= output.x + output.width && mouse[1] >= output.y
				&& mouse[1] <= output.y + output.height)
			{
				double now        = rl::get_time();
				bool double_click = now - self.last_click_time < 0.4 && math::abs(
					mouse[0] - self.last_click_pos[0]
				) < 5.0f && math::abs(mouse[1] - self.last_click_pos[1]) < 5.0f;
				self.last_click_time = now;
				self.last_click_pos = mouse;
				self.begin_selection(console, metrics, mouse, double_click);
				self.focus_requested = true;
			}
			else if (mouse[0] >= panel.x && mouse[0] <= panel.x + panel.width && mouse[1] >= panel.y
				&& mouse[1] <= panel.y + panel.height)
			{
				self.clear_selection();
				self.focus_requested = true;
			}
		}
	}

	if (self.selecting)
	{
		if (rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
		{
			self.update_selection(console, metrics, mouse);
		}
		else
		{
			self.selecting = false;
		}
	}

	if (self.resizing)
	{
		if (rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
		{
			float height = ((float)rl::get_screen_height() - mouse[1]) / ui::scale();
			float max    = (float)rl::get_screen_height() / ui::scale() - MIN_HEIGHT;
			if (max < MIN_HEIGHT) max = MIN_HEIGHT;
			self.height = math::clamp(height, MIN_HEIGHT, max);
		}
		else
		{
			self.resizing = false;
		}
	}

	if (mouse[0] >= output.x && mouse[0] <= output.x + output.width && mouse[1] >= output.y
		&& mouse[1] <= output.y + output.height)
	{
		float wheel = rl::get_mouse_wheel_move();
		if (wheel != 0.0f)
		{
			if (shift_down())
			{
				self.scroll_horizontal(console, metrics, -wheel * metrics.char_width * 8.0f);
			}
			else
			{
				self.scroll_by(console, metrics, -(int)(wheel * (float)SCROLL_LINES));
			}
		}
	}
	if (mouse[1] >= panel.y && mouse[1] <= panel.y + ui::pxf(
		RESIZE_GRAB
	) && mouse[0] >= panel.x && mouse[0] <= panel.x + panel.width)
	{
		ui::request_cursor(rl::RLMouseCursor.RESIZE_NS, 4);
	}
}

fn RLColor console_line_color(ConsoleStream stream)
{
	switch (stream)
	{
		case ConsoleStream.COMMAND:
			return theme::current().panel_header;
		case ConsoleStream.STDERR:
			return theme::current().diag_error;
		case ConsoleStream.STDOUT:
			return theme::current().panel_text;
	}
}

fn RLColor console_adjust_color(RLColor color, int delta)
{
	int r = ((int)color[0] & 0xFF) + delta;
	int g = ((int)color[1] & 0xFF) + delta;
	int b = ((int)color[2] & 0xFF) + delta;
	if (r < 0) r = 0;
	if (g < 0) g = 0;
	if (b < 0) b = 0;
	if (r > 255) r = 255;
	if (g > 255) g = 255;
	if (b > 255) b = 255;
	return (RLColor) { (char)r, (char)g, (char)b, color[3] };
}

fn float draw_console_segment(
	RLFont font,
	EditorMetrics metrics,
	String text,
	float x,
	float y,
	RLColor fg,
	RLColor bg,
	bool has_bg,
	uint attrs
)
{
	if (text.len == 0) return 0.0f;
	@pool()
	{
		ZString z     = text.zstr_tcopy();
		float width   = rl::measure_text_ex(font, z, metrics.font_size, 0.0f)[0];
		RLColor color = fg;
		if ((attrs & SPAN_BOLD) != 0) color = console_adjust_color(color, 40);
		if ((attrs & SPAN_DIM) != 0) color = console_adjust_color(color, -50);
		if (has_bg)
		{
			rl::draw_rectangle_rec({ .x = x, .y = y, .width = width, .height = metrics.line_height }, bg);
		}
		rl::draw_text_ex(font, z, { x, y }, metrics.font_size, 0.0f, color);
		if ((attrs & SPAN_UNDERLINE) != 0)
		{
			rl::draw_rectangle_rec(
				{ .x = x, .y = y + metrics.font_size + 1.0f, .width = width, .height = 1.0f },
				color
			);
		}
		return width;
	};
}

fn void draw_console_line(RLFont font, EditorMetrics metrics, ConsoleLine* line, float x, float y)
{
	RLColor default_color = console_line_color(line.stream);
	if (line.span_count == 0 || !line.spans)
	{
		rl::draw_text_ex(font, (ZString)line.text.ptr, { x, y }, metrics.font_size, 0.0f, default_color);
		return;
	}
	usz cursor = 0;
	float px   = x;
	for (int i = 0; i < line.span_count; i++)
	{
		ConsoleSpan span = line.spans[i];
		if (span.start > cursor)
		{
			px += draw_console_segment(
				font,
				metrics,
				line.text[cursor:span.start - cursor],
				px,
				y,
				default_color,
				{ },
				false,
				0
			);
		}
		RLColor fg = span.fg;
		if (!span.fg[3]) fg = default_color;
		px += draw_console_segment(
			font,
			metrics,
			line.text[span.start:span.len],
			px,
			y,
			fg,
			span.bg,
			span.bg[3] != 0,
			span.attrs
		);
		cursor = span.start + span.len;
	}
	if (cursor < line.text.len)
	{
		draw_console_segment(
			font,
			metrics,
			line.text[cursor:line.text.len - cursor],
			px,
			y,
			default_color,
			{ },
			false,
			0
		);
	}
}

fn void draw_button(RLFont font, Rect r, String label, bool enabled, bool hovered)
{
	RLColor bg = hovered && enabled ? theme::current().topbar_hover : theme::current().panel_field;
	ui::row(r, bg);
	float size     = (float)ui::tpx(13);
	RLVector2 text = rl::measure_text_ex(font, (ZString)label.ptr, size, 0.0f);
	RLColor color  = enabled ? theme::current().panel_text : theme::current().panel_disabled;
	rl::draw_text_ex(
		font,
		(ZString)label.ptr,
		{ r.x + (r.width - text[0]) / 2.0f, r.y + (r.height - text[1]) / 2.0f },
		size,
		0.0f,
		color
	);
}

fn String button_label(ConsoleButton button)
{
	switch (button)
	{
		case ConsoleButton.RUN:
			return "Run";
		case ConsoleButton.KILL:
			return "Kill";
		case ConsoleButton.CLEAR:
			return "Clear";
		case ConsoleButton.COPY:
			return "Copy";
		case ConsoleButton.COUNT:
			return "";
	}
}

fn void ConsolePanel.draw(&self, Console* console, RLFont font, RLFont editor_font, EditorMetrics metrics)
{
	if (!self.visible) return;
	Rect panel  = self.rect();
	Rect header = self.header_rect();
	Rect output = self.output_rect();
	Rect input  = self.input_rect();

	float radius = ui::corner_radius();
	ui::rounded_top(panel, radius, theme::current().panel_bg);
	RLColor border = self.focused ? theme::current().card_focus : theme::current().panel_border;
	rl::draw_rectangle_rec(
		{ .x = panel.x + radius, .y = panel.y, .width = panel.width - radius * 2.0f, .height = 1.0f },
		border
	);
	rl::draw_rectangle_rec(
		{ .x = panel.x, .y = panel.y + radius, .width = 1.0f, .height = panel.height - radius },
		border
	);
	rl::draw_rectangle_rec(
		{ .x = panel.x + panel.width - 1.0f, .y = panel.y + radius, .width = 1.0f, .height = panel.height - radius },
		border
	);
	rl::draw_rectangle_rec(
		{
			.x = panel.x + panel.width / 2.0f - ui::pxf(18.0f),
			.y = panel.y + ui::pxf(2.0f),
			.width = ui::pxf(36.0f),
			.height = 2.0f
		},
		theme::current()
		.panel_dim);

	float title_size = (float)ui::tpx(14);
	rl::draw_text_ex(
		font,
		"Console",
		{ header.x, header.y + (header.height - title_size) / 2.0f },
		title_size,
		0.0f,
		theme::current()
		.panel_header);

	float status_size    = (float)ui::tpx(13);
	RLColor status_color = theme::current().panel_dim;
	if (console.runner.status == ConsoleStatus.RUNNING || console.runner.status == ConsoleStatus.KILLING)
	{
		status_color = theme::current().diag_warning;
	}
	else if (console.runner.status == ConsoleStatus.FAILED
		|| (console.runner.status == ConsoleStatus.EXITED && console.runner.exit_code != 0))
	{
		status_color = theme::current().diag_error;
	}
	@pool()
	{
		String status = console_status_label(console.runner.status);
		if (console.runner.status == ConsoleStatus.EXITED)
		{
			status = string::format(tmem, "Exit %d", console.runner.exit_code);
		}
		if (console.buffer.truncated)
		{
			status = string::format(tmem, "%s  (truncated)", status);
		}
		RLVector2 status_measure = rl::measure_text_ex(font, (ZString)status.ptr, status_size, 0.0f);
		rl::draw_text_ex(
			font,
			(ZString)status.ptr,
			{ header.x + header.width - status_measure[0], header.y + (header.height - status_size) / 2.0f },
			status_size,
			0.0f,
			status_color
		);
	};

	if (self.find_open)
	{
		float find_w = ui::pxf(260.0f);
		float max_w  = header.width - ui::pxf(170.0f);
		if (find_w > max_w) find_w = max_w;
		if (find_w < ui::pxf(120.0f)) find_w = ui::pxf(120.0f);
		Rect field = {
			.x = header.x + ui::pxf(86.0f),
			.y = header.y + ui::pxf(3.0f),
			.width = find_w,
			.height = header.height - ui::pxf(6.0f),
		};
		ui::row(field, theme::current().panel_field);
		String query    = self.find_query_view();
		float text_size = (float)ui::tpx(13);
		float pad       = ui::pxf(6.0f);
		String result   = "0/0";
		@pool()
		{
			if (self.find_count > 0) result = string::format(
				tmem,
				"%d/%d",
				(long)(self.find_index + 1),
				(long)self.find_count
			);
			float result_w = rl::measure_text_ex(font, result.zstr_tcopy(), text_size, 0.0f)[0];
			float inner    = field.width - pad * 2.0f - result_w - ui::pxf(8.0f);
			String display = query.len > 0 ? query : "Find output";
			RLColor color  = query.len > 0 ? theme::current().panel_text : theme::current().panel_dim;
			float text_w   = rl::measure_text_ex(font, display.zstr_tcopy(), text_size, 0.0f)[0];
			float x        = field.x + pad;
			if (text_w > inner) x -= text_w - inner;
			rl::begin_scissor_mode((int)(field.x + pad), (int)field.y, (int)(inner + pad), (int)field.height);
			rl::draw_text_ex(
				font,
				display.zstr_tcopy(),
				{ x, field.y + (field.height - text_size) / 2.0f },
				text_size,
				0.0f,
				color
			);
			if (query.len > 0)
			{
				rl::draw_rectangle_rec(
					{
						.x = x + text_w,
						.y = field.y + ui::pxf(4.0f),
						.width = 1.0f,
						.height = field.height - ui::pxf(8.0f)
					},
					theme::current()
					.panel_caret);
			}
			rl::end_scissor_mode();
			rl::draw_text_ex(
				font,
				result.zstr_tcopy(),
				{ field.x + field.width - pad - result_w, field.y + (field.height - text_size) / 2.0f },
				text_size,
				0.0f,
				theme::current()
				.panel_dim);
		};
	}

	if (self.find_open) self.find_refresh(console);
	int scroll        = self.scroll_for(console, metrics);
	int visible       = self.visible_rows(metrics);
	float output_view = output.width - ui::pxf(PADDING) * 2.0f;
	float content     = self.output_width(console, metrics);
	self.output_scroll_x = console_clamp_hscroll(self.output_scroll_x, content, output_view);
	rl::begin_scissor_mode((int)output.x, (int)output.y, (int)output.width, (int)output.height);
	float text_x = output.x + ui::pxf(PADDING) - self.output_scroll_x;

	if (self.find_open && self.find_count > 0)
	{
		for (int i = 0; i < visible; i++)
		{
			sz index          = (sz)scroll + (sz)i;
			ConsoleLine* line = console.buffer.line_at(index);
			if (!line) break;
			for (int m = 0; m < self.find_count; m++)
			{
				ConsoleFindMatch match = self.find_matches[m];
				if (match.line != index) continue;
				float x1      = text_x + (float)console_columns_before(line.text, match.start) * metrics.char_width;
				float x2      = text_x + (float)console_columns_before(
					line.text,
					match.start + match.len
				) * metrics.char_width;
				float y       = output.y + (float)i * metrics.line_height;
				RLColor color = m == self.find_index ? theme::current()
					.editor_match_current : theme::current().editor_match;
				rl::draw_rectangle_rec({ .x = x1, .y = y, .width = x2 - x1, .height = metrics.line_height }, color);
			}
		}
	}

	sz sel_start_line;
	usz sel_start_offset;
	sz sel_end_line;
	usz sel_end_offset;
	bool has_sel = self.selection_range(console, &sel_start_line, &sel_start_offset, &sel_end_line, &sel_end_offset);
	if (has_sel)
	{
		for (int i = 0; i < visible; i++)
		{
			sz index = (sz)scroll + (sz)i;
			if (index < sel_start_line || index > sel_end_line) continue;
			ConsoleLine* line = console.buffer.line_at(index);
			if (!line) break;
			usz a = index == sel_start_line ? sel_start_offset : 0;
			usz b = index == sel_end_line ? sel_end_offset : line.text.len;
			if (b <= a) continue;
			float x1 = text_x + (float)console_columns_before(line.text, a) * metrics.char_width;
			float x2 = text_x + (float)console_columns_before(line.text, b) * metrics.char_width;
			float y  = output.y + (float)i * metrics.line_height;
			rl::draw_rectangle_rec(
				{ .x = x1, .y = y, .width = x2 - x1, .height = metrics.line_height },
				theme::current()
				.editor_selection);
		}
	}

	for (int i = 0; i < visible; i++)
	{
		sz index = (sz)scroll + (sz)i;
		if (index >= console.buffer.line_count()) break;
		ConsoleLine* line = console.buffer.line_at(index);
		float y           = output.y + (float)i * metrics.line_height;
		draw_console_line(editor_font, metrics, line, text_x, y);
	}
	rl::end_scissor_mode();

	if (content > output_view)
	{
		float track_x = output.x + ui::pxf(PADDING);
		float track_y = output.y + output.height - ui::pxf(4.0f);
		float track_w = output_view;
		float thumb_w = track_w * output_view / content;
		if (thumb_w < ui::pxf(24.0f)) thumb_w = ui::pxf(24.0f);
		float max     = content - output_view;
		float thumb_x = track_x;
		if (max > 0.0f) thumb_x += (track_w - thumb_w) * self.output_scroll_x / max;
		rl::draw_rectangle_rec(
			{ .x = track_x, .y = track_y, .width = track_w, .height = ui::pxf(2.0f) },
			theme::current()
			.editor_scrollbar);
		rl::draw_rectangle_rec(
			{ .x = thumb_x, .y = track_y, .width = thumb_w, .height = ui::pxf(2.0f) },
			theme::current()
			.panel_dim);
	}

	int max_scroll = console_max_scroll((int)console.buffer.line_count(), visible);
	if (max_scroll > 0)
	{
		float track_x = panel.x + panel.width - ui::pxf(5.0f);
		float track_y = output.y + ui::pxf(2.0f);
		float track_h = output.height - ui::pxf(4.0f);
		float thumb_h = track_h * (float)visible / (float)(visible + max_scroll);
		if (thumb_h < ui::pxf(24.0f)) thumb_h = ui::pxf(24.0f);
		float thumb_y = track_y;
		if (max_scroll > 0) thumb_y += (track_h - thumb_h) * (float)scroll / (float)max_scroll;
		rl::draw_rectangle_rec(
			{ .x = track_x, .y = track_y, .width = ui::pxf(3.0f), .height = track_h },
			theme::current()
			.editor_scrollbar);
		rl::draw_rectangle_rec(
			{ .x = track_x, .y = thumb_y, .width = ui::pxf(3.0f), .height = thumb_h },
			theme::current()
			.panel_dim);
	}

	ui::row(input, theme::current().panel_field);
	float prompt_size = (float)ui::tpx(14);
	rl::draw_text_ex(
		font,
		">",
		{ input.x + ui::pxf(PADDING), input.y + (input.height - prompt_size) / 2.0f },
		prompt_size,
		0.0f,
		theme::current()
		.panel_header);

	float button_space = (float)BUTTON_COUNT * ui::pxf(BUTTON_WIDTH) + (float)(BUTTON_COUNT - 1) * ui::pxf(BUTTON_GAP);
	Rect text_rect = {
		.x = input.x + ui::pxf(PADDING) + ui::pxf(14.0f),
		.y = input.y,
		.width = input.width - ui::pxf(PADDING) * 2.0f - ui::pxf(14.0f) - button_space,
		.height = input.height,
	};
	if (text_rect.width < ui::pxf(40.0f)) text_rect.width = ui::pxf(40.0f);

	self.refresh_completion(console);
	String view      = console.input.text_view();
	float cursor_x   = 0.0f;
	float text_width = 0.0f;
	@pool()
	{
		String prefix    = view[0:(usz)console.input.cursor];
		ZString prefix_z = prefix.zstr_tcopy();
		ZString view_z   = view.zstr_tcopy();
		cursor_x = rl::measure_text_ex(editor_font, prefix_z, metrics.font_size, 0.0f)[0];
		text_width = rl::measure_text_ex(editor_font, view_z, metrics.font_size, 0.0f)[0];
	};
	if (cursor_x - self.input_scroll > text_rect.width - ui::pxf(2.0f))
	{
		self.input_scroll = cursor_x - text_rect.width + ui::pxf(2.0f);
	}
	if (cursor_x - self.input_scroll < 0.0f) self.input_scroll = cursor_x;
	if (text_width <= text_rect.width) self.input_scroll = 0.0f;

	rl::begin_scissor_mode((int)text_rect.x, (int)text_rect.y, (int)text_rect.width, (int)text_rect.height);
	float text_y = input.y + (input.height - metrics.font_size) / 2.0f;
	rl::draw_text_ex(
		editor_font,
		console.input.zstr_view(),
		{ text_rect.x - self.input_scroll, text_y },
		metrics.font_size,
		0.0f,
		theme::current()
		.panel_text);
	float caret_x = text_rect.x - self.input_scroll + cursor_x;
	if (self.completion_active)
	{
		String ghost = self.completion_suffix(console);
		if (ghost.len > 0)
		{
			@pool()
			{
				rl::draw_text_ex(
					editor_font,
					ghost.zstr_tcopy(),
					{ caret_x, text_y },
					metrics.font_size,
					0.0f,
					theme::current()
					.panel_disabled);
			};
		}
	}
	rl::draw_rectangle_rec(
		{ .x = caret_x, .y = input.y + ui::pxf(6.0f), .width = 1.0f, .height = input.height - ui::pxf(12.0f) },
		theme::current()
		.panel_caret);
	rl::end_scissor_mode();

	RLVector2 mouse = rl::get_mouse_position();
	for (int i = 0; i < BUTTON_COUNT; i++)
	{
		ConsoleButton button = (ConsoleButton)i;
		Rect r               = self.button_rect(button);
		bool hovered         = mouse[0] >= r.x && mouse[0] <= r.x + r.width && mouse[1] >= r.y
			&& mouse[1] <= r.y + r.height;
		draw_button(font, r, button_label(button), self.button_enabled(button, console), hovered);
	}
}