module yun::console;

import std::collections::list;
import std::core::dstring;
import std::core::mem::alloc;
import raylib6::rl;
import yun::theme;

const int TERM_MAX_COLS = 400;
const int TERM_MAX_ROWS = 200;
const int TERM_SEQ_MAX  = 64;

const uint TERM_BOLD      = 1;
const uint TERM_DIM       = 2;
const uint TERM_UNDERLINE = 4;
const uint TERM_INVERSE   = 8;

struct TermCell
{
	char[5] text;
	char len;
	RLColor fg;
	RLColor bg;
	uint attrs;
}

struct ConsoleTerminal
{
	Allocator allocator;
	int cols;
	int rows;
	List{TermCell} cells;
	int cursor_x;
	int cursor_y;
	int saved_x;
	int saved_y;
	int scroll_top;
	int scroll_bottom;
	bool wrap_pending;
	bool wrap_enabled;
	bool cursor_visible;
	bool alt_screen;
	RLColor default_fg;
	RLColor default_bg;
	RLColor fg;
	RLColor bg;
	uint attrs;
	int parser;
	char[TERM_SEQ_MAX] seq;
	int seq_len;
	List{TermCell} main_cells;
	int main_x;
	int main_y;
	int main_top;
	int main_bottom;
}

fn TermCell term_cell(RLColor fg, RLColor bg)
{
	return { .len = 0, .fg = fg, .bg = bg, .attrs = 0 };
}

fn void ConsoleTerminal.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.cols = 80;
	self.rows = 24;
	self.cells.init(allocator);
	self.main_cells.init(allocator);
	self.cursor_x = 0;
	self.cursor_y = 0;
	self.saved_x = 0;
	self.saved_y = 0;
	self.scroll_top = 0;
	self.scroll_bottom = self.rows - 1;
	self.wrap_pending = false;
	self.wrap_enabled = true;
	self.cursor_visible = true;
	self.alt_screen = false;
	self.default_fg = theme::current().panel_text;
	self.default_bg = theme::current().panel_bg;
	self.fg = self.default_fg;
	self.bg = self.default_bg;
	self.attrs = 0;
	self.parser = 0;
	self.seq_len = 0;
	self.main_x = 0;
	self.main_y = 0;
	self.main_top = 0;
	self.main_bottom = 0;
	self.resize(self.cols, self.rows);
}

fn String ConsoleTerminal.copy_text(&self, Allocator allocator)
{
	DString out;
	out.init(allocator, 1024);
	for (int y = 0; y < self.rows; y++)
	{
		usz end = 0;
		for (int x = 0; x < self.cols; x++)
		{
			TermCell* cell = self.cell_at(x, y);
			if (cell && cell.len > 0) end = (usz)x + 1;
		}
		for (int x = 0; x < (int)end; x++)
		{
			TermCell* cell = self.cell_at(x, y);
			if (!cell || cell.len == 0)
			{
				out.append_char(' ');
				continue;
			}
			for (int i = 0; i < (int)cell.len; i++) out.append_char(cell.text[i]);
		}
		if (y + 1 < self.rows) out.append_char('\n');
	}
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn void ConsoleTerminal.destroy(&self)
{
	self.cells.free();
	self.main_cells.free();
}

fn TermCell* ConsoleTerminal.cell_at(&self, int x, int y)
{
	if (x < 0 || y < 0 || x >= self.cols || y >= self.rows) return null;
	return self.cells.get_ref((sz)y * self.cols + x);
}

fn void ConsoleTerminal.reset_cell(&self, TermCell* cell)
{
	cell.text[0] = 0;
	cell.len = 0;
	cell.fg = self.fg;
	cell.bg = self.bg;
	cell.attrs = self.attrs;
}

fn void ConsoleTerminal.clear_all(&self)
{
	for (sz i = 0; i < self.cells.len(); i++)
	{
		TermCell* cell = self.cells.get_ref(i);
		cell.text[0] = 0;
		cell.len = 0;
		cell.fg = self.default_fg;
		cell.bg = self.default_bg;
		cell.attrs = 0;
	}
}

fn void ConsoleTerminal.resize(&self, int cols, int rows)
{
	if (cols < 1) cols = 1;
	if (rows < 1) rows = 1;
	if (cols > TERM_MAX_COLS) cols = TERM_MAX_COLS;
	if (rows > TERM_MAX_ROWS) rows = TERM_MAX_ROWS;
	if (cols == self.cols && rows == self.rows && self.cells.len() > 0) return;

	int old_cols       = self.cols;
	int old_rows       = self.rows;
	List{TermCell} old = self.cells;
	self.cols = cols;
	self.rows = rows;
	self.cells = { };
	self.cells.init(self.allocator);
	for (int y = 0; y < rows; y++)
	{
		for (int x = 0; x < cols; x++)
		{
			TermCell cell = term_cell(self.default_fg, self.default_bg);
			if (x < old_cols && y < old_rows && old.len() > 0)
			{
				TermCell* previous = old.get_ref((sz)y * old_cols + x);
				cell = *previous;
			}
			self.cells.push(cell);
		}
	}
	old.free();
	if (self.cursor_x >= cols) self.cursor_x = cols - 1;
	if (self.cursor_y >= rows) self.cursor_y = rows - 1;
	self.scroll_top = 0;
	self.scroll_bottom = rows - 1;
	self.wrap_pending = false;
}

fn void ConsoleTerminal.scroll_up(&self, int count)
{
	if (count < 1) count = 1;
	if (count > self.scroll_bottom - self.scroll_top + 1) count = self.scroll_bottom - self.scroll_top + 1;
	for (int y = self.scroll_top; y <= self.scroll_bottom - count; y++)
	{
		for (int x = 0; x < self.cols; x++)
		{
			TermCell* dst = self.cell_at(x, y);
			TermCell* src = self.cell_at(x, y + count);
			if (dst && src) *dst = *src;
		}
	}
	for (int y = self.scroll_bottom - count + 1; y <= self.scroll_bottom; y++)
	{
		for (int x = 0; x < self.cols; x++)
		{
			TermCell* cell = self.cell_at(x, y);
			if (cell) self.reset_cell(cell);
		}
	}
}

fn void ConsoleTerminal.scroll_down(&self, int count)
{
	if (count < 1) count = 1;
	if (count > self.scroll_bottom - self.scroll_top + 1) count = self.scroll_bottom - self.scroll_top + 1;
	for (int y = self.scroll_bottom; y >= self.scroll_top + count; y--)
	{
		for (int x = 0; x < self.cols; x++)
		{
			TermCell* dst = self.cell_at(x, y);
			TermCell* src = self.cell_at(x, y - count);
			if (dst && src) *dst = *src;
		}
	}
	for (int y = self.scroll_top; y < self.scroll_top + count; y++)
	{
		for (int x = 0; x < self.cols; x++)
		{
			TermCell* cell = self.cell_at(x, y);
			if (cell) self.reset_cell(cell);
		}
	}
}

fn void ConsoleTerminal.linefeed(&self)
{
	if (self.cursor_y == self.scroll_bottom)
	{
		self.scroll_up(1);
	}
	else if (self.cursor_y < self.rows - 1)
	{
		self.cursor_y++;
	}
	self.wrap_pending = false;
}

fn void ConsoleTerminal.enter_alt(&self)
{
	if (self.alt_screen) return;
	self.main_cells.clear();
	for (sz i = 0; i < self.cells.len(); i++) self.main_cells.push(self.cells.get(i));
	self.main_x = self.cursor_x;
	self.main_y = self.cursor_y;
	self.main_top = self.scroll_top;
	self.main_bottom = self.scroll_bottom;
	self.alt_screen = true;
	self.clear_all();
	self.cursor_x = 0;
	self.cursor_y = 0;
	self.scroll_top = 0;
	self.scroll_bottom = self.rows - 1;
}

fn void ConsoleTerminal.exit_alt(&self)
{
	if (!self.alt_screen) return;
	List{TermCell} tmp = self.cells;
	self.cells = self.main_cells;
	self.main_cells = tmp;
	self.main_cells.clear();
	self.alt_screen = false;
	self.cursor_x = self.main_x;
	self.cursor_y = self.main_y;
	self.scroll_top = self.main_top;
	self.scroll_bottom = self.main_bottom;
	self.wrap_pending = false;
}

fn void ConsoleTerminal.put(&self, int codepoint)
{
	if (self.wrap_pending && self.wrap_enabled)
	{
		self.cursor_x = 0;
		self.linefeed();
	}
	TermCell* cell = self.cell_at(self.cursor_x, self.cursor_y);
	if (cell)
	{
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
		for (int i = 0; i < count; i++) cell.text[i] = encoded[i];
		cell.text[count] = 0;
		cell.len = (char)count;
		cell.fg = self.fg;
		cell.bg = self.bg;
		cell.attrs = self.attrs;
	}
	self.wrap_pending = false;
	if (self.cursor_x + 1 >= self.cols)
	{
		self.cursor_x = self.cols - 1;
		self.wrap_pending = self.wrap_enabled;
	}
	else
	{
		self.cursor_x++;
	}
}

fn void ConsoleTerminal.erase_in_line(&self, int mode)
{
	int start = 0;
	int end   = self.cols;
	if (mode == 0)
	{
		start = self.cursor_x;
	}
	else if (mode == 1)
	{
		end = self.cursor_x + 1;
	}
	for (int x = start; x < end; x++)
	{
		TermCell* cell = self.cell_at(x, self.cursor_y);
		if (cell)
		{
			cell.text[0] = 0;
			cell.len = 0;
			cell.fg = self.default_fg;
			cell.bg = self.bg;
			cell.attrs = 0;
		}
	}
}

fn void ConsoleTerminal.erase_display(&self, int mode)
{
	if (mode == 0)
	{
		for (int y = self.cursor_y; y < self.rows; y++)
		{
			for (int x = 0; x < self.cols; x++)
			{
				if (y == self.cursor_y && x < self.cursor_x) continue;
				TermCell* cell = self.cell_at(x, y);
				if (cell)
				{
					cell.text[0] = 0;
					cell.len = 0;
					cell.fg = self.default_fg;
					cell.bg = self.bg;
					cell.attrs = 0;
				}
			}
		}
	}
	else if (mode == 1)
	{
		for (int y = 0; y <= self.cursor_y; y++)
		{
			for (int x = 0; x < self.cols; x++)
			{
				if (y == self.cursor_y && x > self.cursor_x) continue;
				TermCell* cell = self.cell_at(x, y);
				if (cell)
				{
					cell.text[0] = 0;
					cell.len = 0;
					cell.fg = self.default_fg;
					cell.bg = self.bg;
					cell.attrs = 0;
				}
			}
		}
	}
	else
	{
		self.clear_all();
	}
}

fn void ConsoleTerminal.reset(&self)
{
	self.clear_all();
	self.cursor_x = 0;
	self.cursor_y = 0;
	self.saved_x = 0;
	self.saved_y = 0;
	self.scroll_top = 0;
	self.scroll_bottom = self.rows - 1;
	self.wrap_pending = false;
	self.wrap_enabled = true;
	self.cursor_visible = true;
	self.fg = self.default_fg;
	self.bg = self.default_bg;
	self.attrs = 0;
}

fn int term_param(int[] params, int count, int index, int fallback)
{
	if (index >= count) return fallback;
	return params[index] > 0 ? params[index] : fallback;
}

fn int term_parse_params(String seq, int[] params, int max, bool* private)
{
	*private = false;
	int count      = 0;
	int value      = 0;
	bool has_value = false;
	for (usz i = 0; i < seq.len && count < max; i++)
	{
		char c = seq[i];
		if (c == '?' || c == '>' || c == '<')
		{
			*private = true;
			continue;
		}
		if (c >= '0' && c <= '9')
		{
			value = value * 10 + (int)(c - '0');
			has_value = true;
		}
		else if (c == ';' || c == ':')
		{
			params[count] = has_value ? value : 0;
			count++;
			value = 0;
			has_value = false;
		}
	}
	if (count < max) params[count] = has_value ? value : 0;
	return count + (has_value ? 1 : 0);
}

fn void ConsoleTerminal.sgr(&self, int[] params, int count)
{
	if (count == 0)
	{
		self.fg = self.default_fg;
		self.bg = self.default_bg;
		self.attrs = 0;
		return;
	}
	int i = 0;
	while (i < count)
	{
		int code = params[i];
		if (code == 0)
		{
			self.fg = self.default_fg;
			self.bg = self.default_bg;
			self.attrs = 0;
		}
		else if (code == 1)
		{
			self.attrs |= TERM_BOLD;
		}
		else if (code == 2)
		{
			self.attrs |= TERM_DIM;
		}
		else if (code == 4)
		{
			self.attrs |= TERM_UNDERLINE;
		}
		else if (code == 7)
		{
			self.attrs |= TERM_INVERSE;
		}
		else if (code == 22)
		{
			self.attrs &= ~(TERM_BOLD | TERM_DIM);
		}
		else if (code == 24)
		{
			self.attrs &= ~TERM_UNDERLINE;
		}
		else if (code == 27)
		{
			self.attrs &= ~TERM_INVERSE;
		}
		else if (code >= 30 && code <= 37)
		{
			self.fg = ansi_basic(code - 30, false);
		}
		else if (code == 39)
		{
			self.fg = self.default_fg;
		}
		else if (code >= 40 && code <= 47)
		{
			self.bg = ansi_basic(code - 40, false);
		}
		else if (code == 49)
		{
			self.bg = self.default_bg;
		}
		else if (code >= 90 && code <= 97)
		{
			self.fg = ansi_basic(code - 90, true);
		}
		else if (code >= 100 && code <= 107)
		{
			self.bg = ansi_basic(code - 100, true);
		}
		else if ((code == 38 || code == 48) && i + 1 < count)
		{
			bool foreground = code == 38;
			int mode        = params[i + 1];
			RLColor color   = { };
			bool have       = false;
			if (mode == 5 && i + 2 < count)
			{
				color = ansi_256(params[i + 2]);
				have = true;
				i += 2;
			}
			else if (mode == 2 && i + 4 < count)
			{
				color = ansi_truecolor(params[i + 2], params[i + 3], params[i + 4]);
				have = true;
				i += 4;
			}
			if (have)
			{
				if (foreground)
				{
					self.fg = color;
				}
				else
				{
					self.bg = color;
				}
			}
		}
		i++;
	}
}

fn void ConsoleTerminal.handle_csi(&self, char final, String seq)
{
	int[16] params;
	bool private;
	int count = term_parse_params(seq, params[0:16], 16, &private);
	int n     = term_param(params[0:16], count, 0, 1);

	if (private)
	{
		if (final == 'h' || final == 'l')
		{
			bool enable = final == 'h';
			for (int i = 0; i < count; i++)
			{
				if (params[i] == 25)
				{
					self.cursor_visible = enable;
				}
				else if (params[i] == 7)
				{
					self.wrap_enabled = enable;
				}
				else if (params[i] == 1049)
				{
					if (enable)
					{
						self.enter_alt();
					}
					else
					{
						self.exit_alt();
					}
				}
			}
		}
		return;
	}

	switch (final)
	{
		case 'A':
			self.cursor_y -= n;
			if (self.cursor_y < 0) self.cursor_y = 0;
		case 'B':
			self.cursor_y += n;
			if (self.cursor_y >= self.rows) self.cursor_y = self.rows - 1;
		case 'C':
			self.cursor_x += n;
			if (self.cursor_x >= self.cols) self.cursor_x = self.cols - 1;
		case 'D':
			self.cursor_x -= n;
			if (self.cursor_x < 0) self.cursor_x = 0;
		case 'E':
			self.cursor_y += n;
			if (self.cursor_y >= self.rows) self.cursor_y = self.rows - 1;
			self.cursor_x = 0;
		case 'F':
			self.cursor_y -= n;
			if (self.cursor_y < 0) self.cursor_y = 0;
			self.cursor_x = 0;
		case 'G':
			self.cursor_x = term_param(params[0:16], count, 0, 1) - 1;
			if (self.cursor_x < 0) self.cursor_x = 0;
		case 'd':
			self.cursor_y = term_param(params[0:16], count, 0, 1) - 1;
			if (self.cursor_y < 0) self.cursor_y = 0;
		case 'H':
		case 'f':
			self.cursor_y = term_param(params[0:16], count, 0, 1) - 1;
			self.cursor_x = term_param(params[0:16], count, 1, 1) - 1;
			if (self.cursor_y < 0) self.cursor_y = 0;
			if (self.cursor_y >= self.rows) self.cursor_y = self.rows - 1;
			if (self.cursor_x < 0) self.cursor_x = 0;
			if (self.cursor_x >= self.cols) self.cursor_x = self.cols - 1;
		case 'J':
			self.erase_display(term_param(params[0:16], count, 0, 0));
		case 'K':
			self.erase_in_line(term_param(params[0:16], count, 0, 0));
		case 'L':
			self.scroll_down(n);
		case 'M':
			self.scroll_up(n);
		case 'P':
			for (int i = 0; i < n; i++)
			{
				for (int x = self.cursor_x; x < self.cols - 1; x++)
				{
					TermCell* dst = self.cell_at(x, self.cursor_y);
					TermCell* src = self.cell_at(x + 1, self.cursor_y);
					if (dst && src) *dst = *src;
				}
				TermCell* cell = self.cell_at(self.cols - 1, self.cursor_y);
				if (cell)
				{
					cell.text[0] = 0;
					cell.len = 0;
					cell.fg = self.default_fg;
					cell.bg = self.bg;
					cell.attrs = 0;
				}
			}
		case '@':
			for (int i = 0; i < n; i++)
			{
				for (int x = self.cols - 1; x > self.cursor_x; x--)
				{
					TermCell* dst = self.cell_at(x, self.cursor_y);
					TermCell* src = self.cell_at(x - 1, self.cursor_y);
					if (dst && src) *dst = *src;
				}
				TermCell* cell = self.cell_at(self.cursor_x, self.cursor_y);
				if (cell) self.reset_cell(cell);
			}
		case 'S':
			self.scroll_up(n);
		case 'T':
			self.scroll_down(n);
		case 'r':
			self.scroll_top = term_param(params[0:16], count, 0, 1) - 1;
			self.scroll_bottom = term_param(params[0:16], count, 1, self.rows) - 1;
			if (self.scroll_top < 0) self.scroll_top = 0;
			if (self.scroll_bottom >= self.rows) self.scroll_bottom = self.rows - 1;
			if (self.scroll_bottom < self.scroll_top) self.scroll_bottom = self.scroll_top;
			self.cursor_x = 0;
			self.cursor_y = 0;
		case 'm':
			self.sgr(params[0:16], count);
		case 's':
			self.saved_x = self.cursor_x;
			self.saved_y = self.cursor_y;
		case 'u':
			self.cursor_x = self.saved_x;
			self.cursor_y = self.saved_y;
		case 'c':
			self.reset();
		case 'n':
		case 't':
			break;
	}
	self.wrap_pending = false;
}

fn bool term_is_csi_final(char c)
{
	return c >= 0x40 && c <= 0x7E;
}

fn void ConsoleTerminal.feed(&self, String data)
{
	usz i = 0;
	while (i < data.len)
	{
		char c = data[i];
		if (self.parser == 0)
		{
			if (c == 27)
			{
				self.parser = 1;
				i++;
				continue;
			}
			if (c == '\r')
			{
				self.cursor_x = 0;
				self.wrap_pending = false;
				i++;
				continue;
			}
			if (c == '\n')
			{
				self.linefeed();
				i++;
				continue;
			}
			if (c == '\b')
			{
				if (self.cursor_x > 0) self.cursor_x--;
				self.wrap_pending = false;
				i++;
				continue;
			}
			if (c == '\t')
			{
				int next = (self.cursor_x / 8 + 1) * 8;
				if (next >= self.cols) next = self.cols - 1;
				self.cursor_x = next;
				self.wrap_pending = false;
				i++;
				continue;
			}
			if ((int)c < 32 || (int)c == 127)
			{
				i++;
				continue;
			}
			int b         = (int)c & 0xFF;
			int len       = 1;
			int codepoint = b;
			if (b >= 0xC2 && b <= 0xDF)
			{
				len = 2;
				codepoint = b & 0x1F;
			}
			else if (b >= 0xE0 && b <= 0xEF)
			{
				len = 3;
				codepoint = b & 0x0F;
			}
			else if (b >= 0xF0 && b <= 0xF4)
			{
				len = 4;
				codepoint = b & 0x07;
			}
			if (i + (usz)len > data.len) len = 1;
			for (int k = 1; k < len; k++)
			{
				codepoint = (codepoint << 6) | ((int)data[i + (usz)k] & 0x3F);
			}
			self.put(codepoint);
			i += (usz)len;
			continue;
		}
		if (self.parser == 1)
		{
			self.parser = 0;
			if (c == '[')
			{
				self.parser = 2;
				self.seq_len = 0;
			}
			else if (c == ']')
			{
				self.parser = 3;
				self.seq_len = 0;
			}
			else if (c == '7')
			{
				self.saved_x = self.cursor_x;
				self.saved_y = self.cursor_y;
			}
			else if (c == '8')
			{
				self.cursor_x = self.saved_x;
				self.cursor_y = self.saved_y;
			}
			else if (c == 'D')
			{
				self.linefeed();
			}
			else if (c == 'M')
			{
				if (self.cursor_y == self.scroll_top)
				{
					self.scroll_down(1);
				}
				else if (self.cursor_y > 0)
				{
					self.cursor_y--;
				}
			}
			else if (c == 'E')
			{
				self.cursor_x = 0;
				self.linefeed();
			}
			else if (c == 'c')
			{
				self.reset();
			}
			i++;
			continue;
		}
		if (self.parser == 2)
		{
			if (term_is_csi_final(c))
			{
				self.handle_csi(c, (String)self.seq[0:self.seq_len]);
				self.parser = 0;
				self.seq_len = 0;
			}
			else if (self.seq_len < TERM_SEQ_MAX - 1)
			{
				self.seq[self.seq_len] = c;
				self.seq_len++;
			}
			i++;
			continue;
		}
		if (self.parser == 3)
		{
			if (c == 7)
			{
				self.parser = 0;
			}
			else if (c == 27)
			{
				self.parser = 4;
			}
			i++;
			continue;
		}
		if (self.parser == 4)
		{
			if (c == '\\')
			{
				self.parser = 0;
			}
			else
			{
				self.parser = 3;
			}
			i++;
			continue;
		}
	}
}