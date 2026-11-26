module yun::vim;

import std::core::mem::alloc;
import yun::input;
import yun::text;

const int MAX_COUNT = 100000;

enum Mode : int
{
	NORMAL,
	INSERT,
	VISUAL,
}

enum Pending : int
{
	NONE,
	DELETE,
	CHANGE,
	YANK,
}

enum Request : int
{
	NONE,
	COMMAND,
	SEARCH_FORWARD,
	SEARCH_BACKWARD,
	SEARCH_NEXT,
	SEARCH_PREV,
}

struct State
{
	Allocator allocator;
	Mode mode;
	Pending pending;
	bool pending_g;
	int count;
	String register_text;
	bool register_valid;
	bool register_linewise;
	Request request;
}

fn void State.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.mode = Mode.NORMAL;
	self.pending = Pending.NONE;
	self.pending_g = false;
	self.count = 0;
	self.register_text = "";
	self.register_valid = false;
	self.register_linewise = false;
	self.request = Request.NONE;
}

fn void State.destroy(&self)
{
	if (self.register_text.len) self.register_text.free(self.allocator);
	self.register_text = "";
}

fn void State.reset(&self)
{
	self.mode = Mode.NORMAL;
	self.pending = Pending.NONE;
	self.pending_g = false;
	self.count = 0;
	self.request = Request.NONE;
}

fn Request State.take_request(&self)
{
	Request request = self.request;
	self.request = Request.NONE;
	return request;
}

fn void State.enter_normal(&self, usz* cursor, usz* anchor)
{
	self.mode = Mode.NORMAL;
	self.pending = Pending.NONE;
	self.pending_g = false;
	self.count = 0;
	*anchor = *cursor;
}

fn void State.enter_insert(&self, usz* cursor, usz* anchor)
{
	self.mode = Mode.INSERT;
	self.pending = Pending.NONE;
	self.pending_g = false;
	self.count = 0;
	*anchor = *cursor;
}

fn String mode_name(Mode mode)
{
	switch (mode)
	{
		case Mode.NORMAL:
			return "NORMAL";
		case Mode.INSERT:
			return "INSERT";
		case Mode.VISUAL:
			return "VISUAL";
	}
}

fn int State.take_count(&self)
{
	int count = self.count;
	self.count = 0;
	return count > 0 ? count : 1;
}

fn void State.set_register(&self, String text, bool linewise)
{
	if (self.register_text.len) self.register_text.free(self.allocator);
	self.register_text = text.copy(self.allocator);
	self.register_valid = true;
	self.register_linewise = linewise;
}

fn void State.add_digit(&self, int digit)
{
	if (self.count > MAX_COUNT / 10) return;
	self.count = self.count * 10 + digit;
}

fn bool is_space_at(PieceTable* table, usz offset)
{
	return input::word_class(table.byte_at(offset)) == input::WordClass.SPACE;
}

fn usz line_break(PieceTable* table, usz line)
{
	if (table.length() == 0) return 0;
	if (line + 1 >= table.line_count()) return table.length();
	usz next = table.line_start(line + 1);
	return next > 0 ? next - 1 : 0;
}

fn usz line_last(PieceTable* table, usz line)
{
	usz start = table.line_start(line);
	usz end   = line_break(table, line);
	return end > start ? end - 1 : start;
}

fn usz motion_left(PieceTable* table, usz cursor, int count)
{
	usz start = table.line_start(table.line_of(cursor));
	for (int i = 0; i < count; i++)
	{
		if (cursor <= start) break;
		cursor = table.prev_boundary(cursor - 1);
	}
	return cursor;
}

fn usz motion_right(PieceTable* table, usz cursor, int count)
{
	usz line  = table.line_of(cursor);
	usz start = table.line_start(line);
	usz end   = line_break(table, line);
	for (int i = 0; i < count; i++)
	{
		if (cursor >= end) break;
		cursor = table.next_boundary(cursor);
		if (cursor > end) cursor = end;
	}
	if (cursor < start) cursor = start;
	return cursor;
}

fn usz motion_up(PieceTable* table, usz cursor, int count)
{
	usz line = table.line_of(cursor);
	usz col  = cursor - table.line_start(line);
	if ((usz)count > line)
	{
		line = 0;
	}
	else
	{
		line -= (usz)count;
	}
	usz start = table.line_start(line);
	usz last  = line_last(table, line);
	if (last > start)
	{
		usz width = last - start;
		return start + (col < width ? col : width);
	}
	return start;
}

fn usz motion_down(PieceTable* table, usz cursor, int count)
{
	usz line      = table.line_of(cursor);
	usz col       = cursor - table.line_start(line);
	usz last_line = table.line_count() > 0 ? table.line_count() - 1 : 0;
	line += (usz)count;
	if (line > last_line) line = last_line;
	usz start = table.line_start(line);
	usz last  = line_last(table, line);
	if (last > start)
	{
		usz width = last - start;
		return start + (col < width ? col : width);
	}
	return start;
}

fn usz motion_word_forward(PieceTable* table, usz cursor, int count)
{
	usz len = table.length();
	for (int i = 0; i < count; i++)
	{
		while (cursor < len && is_space_at(table, cursor)) cursor = table.next_boundary(cursor);
		if (cursor >= len) break;
		input::WordClass cls = input::word_class(table.byte_at(cursor));
		while (cursor < len && input::word_class(table.byte_at(cursor)) == cls)
		{
			cursor = table.next_boundary(cursor);
		}
		while (cursor < len && is_space_at(table, cursor)) cursor = table.next_boundary(cursor);
	}
	return cursor;
}

fn usz motion_word_back(PieceTable* table, usz cursor, int count)
{
	for (int i = 0; i < count; i++)
	{
		if (cursor == 0) break;
		cursor = table.prev_boundary(cursor - 1);
		while (cursor > 0 && is_space_at(table, cursor)) cursor = table.prev_boundary(cursor - 1);
		if (is_space_at(table, cursor)) break;
		input::WordClass cls = input::word_class(table.byte_at(cursor));
		while (cursor > 0)
		{
			usz prev = table.prev_boundary(cursor - 1);
			if (input::word_class(table.byte_at(prev)) != cls) break;
			cursor = prev;
		}
	}
	return cursor;
}

fn usz motion_word_end(PieceTable* table, usz cursor, int count)
{
	usz len = table.length();
	for (int i = 0; i < count; i++)
	{
		if (cursor >= len) break;
		if (!is_space_at(table, cursor))
		{
			usz next = table.next_boundary(cursor);
			if (next >= len || input::word_class(table.byte_at(next)) != input::word_class(table.byte_at(cursor)))
			{
				cursor = next;
			}
		}
		while (cursor < len && is_space_at(table, cursor)) cursor = table.next_boundary(cursor);
		if (cursor >= len)
		{
			cursor = len > 0 ? len - 1 : 0;
			break;
		}
		input::WordClass cls = input::word_class(table.byte_at(cursor));
		while (true)
		{
			usz next = table.next_boundary(cursor);
			if (next >= len || input::word_class(table.byte_at(next)) != cls) break;
			cursor = next;
		}
	}
	return cursor;
}

fn usz motion_goto_line(PieceTable* table, int line)
{
	usz last   = table.line_count() > 0 ? table.line_count() - 1 : 0;
	usz target = line <= 0 ? 0 : (usz)line;
	if (target > last) target = last;
	return table.line_start(target);
}

fn String trimmed_line_block(PieceTable* table, usz start, usz end, Allocator allocator)
{
	String text = table.slice(start, end - start, allocator);
	while (text.len > 0 && (text[text.len - 1] == '\n' || text[text.len - 1] == '\r'))
	{
		text = text[0:text.len - 1];
	}
	return text.copy(allocator);
}

fn void yank_lines(State* state, PieceTable* table, usz cursor, int count)
{
	usz line     = table.line_of(cursor);
	usz last     = table.line_count() > 0 ? table.line_count() - 1 : 0;
	usz start    = table.line_start(line);
	usz end_line = line + (usz)(count > 1 ? count - 1 : 0);
	if (end_line > last) end_line = last;
	usz end = end_line + 1 < table.line_count() ? table.line_start(end_line + 1) : table.length();
	if (end < start) end = start;
	@pool()
	{
		String text = trimmed_line_block(table, start, end, tmem);
		state.set_register(text, true);
	};
}

fn bool delete_lines(State* state, PieceTable* table, History* history, usz* cursor, usz* anchor, int count, double now)
{
	usz line     = table.line_of(*cursor);
	usz last     = table.line_count() > 0 ? table.line_count() - 1 : 0;
	usz start    = table.line_start(line);
	usz end_line = line + (usz)(count > 1 ? count - 1 : 0);
	if (end_line > last) end_line = last;
	usz end = end_line + 1 < table.line_count() ? table.line_start(end_line + 1) : table.length();
	if (end <= start) return false;
	@pool()
	{
		String text = trimmed_line_block(table, start, end, tmem);
		state.set_register(text, true);
	};
	(void)history.replace(table, start, end - start, "", now);
	if (start > table.length()) start = table.length();
	*cursor = start;
	*anchor = start;
	return true;
}

fn bool delete_chars(State* state, PieceTable* table, History* history, usz* cursor, usz* anchor, int count, double now)
{
	usz line  = table.line_of(*cursor);
	usz end   = line_break(table, line);
	usz start = *cursor;
	usz stop  = start;
	for (int i = 0; i < count && stop < end; i++) stop = table.next_boundary(stop);
	if (stop > end) stop = end;
	if (stop <= start) return false;
	@pool()
	{
		String text = table.slice(start, stop - start, tmem);
		state.set_register(text, false);
	};
	(void)history.replace(table, start, stop - start, "", now);
	if (start > table.length()) start = table.length();
	*cursor = start;
	*anchor = start;
	return true;
}

fn void visual_range(PieceTable* table, usz anchor, usz cursor, usz* start, usz* end)
{
	usz len = table.length();
	if (len == 0)
	{
		*start = 0;
		*end = 0;
		return;
	}
	if (cursor < anchor)
	{
		*start = cursor;
		usz stop = anchor < len ? table.next_boundary(anchor) : len;
		*end = stop > len ? len : stop;
	}
	else
	{
		*start = anchor;
		usz stop = cursor < len ? table.next_boundary(cursor) : len;
		*end = stop > len ? len : stop;
	}
}

fn bool visual_delete(
	State* state,
	PieceTable* table,
	History* history,
	usz* cursor,
	usz* anchor,
	bool change,
	double now
)
{
	usz start;
	usz end;
	visual_range(table, *anchor, *cursor, &start, &end);
	if (end <= start) return false;
	@pool()
	{
		String text = table.slice(start, end - start, tmem);
		state.set_register(text, false);
	};
	(void)history.replace(table, start, end - start, "", now);
	if (start > table.length()) start = table.length();
	*cursor = start;
	*anchor = start;
	if (change)
	{
		state.enter_insert(cursor, anchor);
	}
	else
	{
		state.enter_normal(cursor, anchor);
	}
	return true;
}

fn bool paste_register(
	State* state,
	PieceTable* table,
	History* history,
	usz* cursor,
	usz* anchor,
	int count,
	bool before,
	double now
)
{
	if (!state.register_valid) return false;
	if (state.register_linewise)
	{
		for (int i = 0; i < count; i++)
		{
			if (before)
			{
				usz line  = table.line_of(*cursor);
				usz start = table.line_start(line);
				@pool()
				{
					String payload = string::format(tmem, "%s\n", state.register_text);
					(void)history.replace(table, start, 0, payload, now);
				};
				*cursor = start;
				*anchor = start;
			}
			else
			{
				usz line = table.line_of(*cursor);
				usz end  = line_break(table, line);
				@pool()
				{
					String payload = string::format(tmem, "\n%s", state.register_text);
					(void)history.replace(table, end, 0, payload, now);
				};
				*cursor = end + 1;
				*anchor = *cursor;
			}
		}
		return true;
	}

	for (int i = 0; i < count; i++)
	{
		usz at = *cursor;
		if (!before && at < table.length()) at = table.next_boundary(at);
		usz after = history.replace(table, at, 0, state.register_text, now);
		*cursor = after;
		*anchor = after;
	}
	return true;
}

fn bool handle_motion(State* state, PieceTable* table, int key, usz* cursor, usz* anchor)
{
	int count  = state.take_count();
	usz next   = *cursor;
	bool moved = true;
	switch (key)
	{
		case 'h':
			next = motion_left(table, *cursor, count);
		case 'l':
			next = motion_right(table, *cursor, count);
		case 'j':
			next = motion_down(table, *cursor, count);
		case 'k':
			next = motion_up(table, *cursor, count);
		case 'w':
			next = motion_word_forward(table, *cursor, count);
		case 'b':
			next = motion_word_back(table, *cursor, count);
		case 'e':
			next = motion_word_end(table, *cursor, count);
		case '0':
			next = table.line_start(table.line_of(*cursor));
		case '$':
			next = line_last(table, table.line_of(*cursor));
		default:
			moved = false;
	}
	if (!moved) return false;
	*cursor = next;
	if (state.mode != Mode.VISUAL) *anchor = *cursor;
	return true;
}

fn bool State.handle(&self, PieceTable* table, History* history, usz* cursor, usz* anchor, int key, double now)
{
	if (key == 27)
	{
		if (self.mode == Mode.INSERT && *cursor > 0)
		{
			usz line = table.line_of(*cursor);
			if (*cursor > table.line_start(line)) *cursor = table.prev_boundary(*cursor - 1);
		}
		self.enter_normal(cursor, anchor);
		return false;
	}
	if (self.mode == Mode.INSERT) return false;

	if (self.pending != Pending.NONE)
	{
		bool linewise = key == 'd' && self.pending == Pending.DELETE;
		bool change   = key == 'c' && self.pending == Pending.CHANGE;
		bool yank     = key == 'y' && self.pending == Pending.YANK;
		if (linewise || change || yank)
		{
			int count = self.take_count();
			self.pending = Pending.NONE;
			if (yank)
			{
				yank_lines(self, table, *cursor, count);
				return false;
			}
			bool changed = delete_lines(self, table, history, cursor, anchor, count, now);
			if (change)
			{
				self.enter_insert(cursor, anchor);
			}
			else
			{
				self.enter_normal(cursor, anchor);
			}
			return changed;
		}
		self.pending = Pending.NONE;
		self.count = 0;
		return false;
	}

	if (self.pending_g)
	{
		self.pending_g = false;
		if (key == 'g')
		{
			int count = self.count > 0 ? self.count : 1;
			self.count = 0;
			*cursor = motion_goto_line(table, count - 1);
			if (self.mode != Mode.VISUAL) *anchor = *cursor;
			return false;
		}
		self.count = 0;
		return false;
	}

	if (key >= '1' && key <= '9')
	{
		self.add_digit(key - '0');
		return false;
	}
	if (key == '0' && self.count > 0)
	{
		self.add_digit(0);
		return false;
	}

	if (key == 'G')
	{
		int count = self.count;
		self.count = 0;
		*cursor = motion_goto_line(table, count > 0 ? count - 1 : (int)table.line_count() - 1);
		if (self.mode != Mode.VISUAL) *anchor = *cursor;
		return false;
	}

	if (self.mode == Mode.VISUAL)
	{
		switch (key)
		{
			case 'v':
				self.enter_normal(cursor, anchor);
				return false;
			case 'd':
			case 'x':
				return visual_delete(self, table, history, cursor, anchor, false, now);
			case 'c':
				return visual_delete(self, table, history, cursor, anchor, true, now);
			case 'y':

				{
					usz start;
					usz end;
					visual_range(table, *anchor, *cursor, &start, &end);
					if (end > start)
					{
						@pool()
						{
							String text = table.slice(start, end - start, tmem);
							self.set_register(text, false);
						};
					}
					*cursor = start;
					self.enter_normal(cursor, anchor);
					return false;
				}
			default:
				break;
		}
	}

	switch (key)
	{
		case ':':
			self.request = Request.COMMAND;
			return false;
		case '/':
			self.request = Request.SEARCH_FORWARD;
			return false;
		case '?':
			self.request = Request.SEARCH_BACKWARD;
			return false;
		case 'n':
			self.request = Request.SEARCH_NEXT;
			return false;
		case 'N':
			self.request = Request.SEARCH_PREV;
			return false;
		case 'i':
			self.enter_insert(cursor, anchor);
			return false;
		case 'a':

			{
				usz line = table.line_of(*cursor);
				usz end  = line_break(table, line);
				if (*cursor < end) *cursor = table.next_boundary(*cursor);
				self.enter_insert(cursor, anchor);
				return false;
			}
		case 'I':
			*cursor = table.line_start(table.line_of(*cursor));
			self.enter_insert(cursor, anchor);
			return false;
		case 'A':
			*cursor = line_break(table, table.line_of(*cursor));
			self.enter_insert(cursor, anchor);
			return false;
		case 'o':

			{
				usz line = table.line_of(*cursor);
				usz end  = line_break(table, line);
				(void)history.replace(table, end, 0, "\n", now);
				*cursor = end + 1;
				self.enter_insert(cursor, anchor);
				return true;
			}
		case 'O':

			{
				usz line  = table.line_of(*cursor);
				usz start = table.line_start(line);
				(void)history.replace(table, start, 0, "\n", now);
				*cursor = start;
				self.enter_insert(cursor, anchor);
				return true;
			}
		case 'v':
			self.mode = Mode.VISUAL;
			*anchor = *cursor;
			self.pending = Pending.NONE;
			self.count = 0;
			return false;
		case 'g':
			self.pending_g = true;
			return false;
		case 'd':
			self.pending = Pending.DELETE;
			return false;
		case 'c':
			self.pending = Pending.CHANGE;
			return false;
		case 'y':
			self.pending = Pending.YANK;
			return false;
		case 'x':
			return delete_chars(self, table, history, cursor, anchor, self.take_count(), now);
		case 'p':
			return paste_register(self, table, history, cursor, anchor, self.take_count(), false, now);
		case 'P':
			return paste_register(self, table, history, cursor, anchor, self.take_count(), true, now);
		case 'u':

			{
				int count    = self.take_count();
				bool changed = false;
				for (int i = 0; i < count; i++)
				{
					if (!history.undo(table, cursor)) break;
					changed = true;
				}
				*anchor = *cursor;
				return changed;
			}
		case 18:

			{
				int count    = self.take_count();
				bool changed = false;
				for (int i = 0; i < count; i++)
				{
					if (!history.redo(table, cursor)) break;
					changed = true;
				}
				*anchor = *cursor;
				return changed;
			}
		default:
			break;
	}

	if (handle_motion(self, table, key, cursor, anchor)) return false;
	self.count = 0;
	return false;
}