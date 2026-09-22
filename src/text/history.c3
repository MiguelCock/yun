module yun::text;

import std::collections::list;
import std::core::mem::alloc;

const double COALESCE_SECONDS = 0.4;
const usz HISTORY_BUDGET      = 4 * 1024 * 1024;

enum CommandKind
{
	INSERT,
	BACKSPACE,
	DELETE,
}

struct EditCommand
{
	CommandKind kind;
	usz offset;
	String text;
}

struct History
{
	List{EditCommand} commands;
	sz index;
	usz memory;
	usz budget;
	double last_time;
	Allocator allocator;
}

fn void History.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.commands.init(allocator);
	self.index = 0;
	self.memory = 0;
	self.budget = HISTORY_BUDGET;
	self.last_time = 0.0;
}

fn void History.reset(&self)
{
	for (sz i = 0; i < self.commands.len(); i++)
	{
		self.commands[i].text.free(self.allocator);
	}
	self.commands.clear();
	self.index = 0;
	self.memory = 0;
	self.last_time = 0.0;
}

fn void History.free(&self)
{
	self.reset();
	self.commands.free();
}

fn void History.break_coalescing(&self)
{
	self.last_time = -1000.0;
}

fn void History.truncate_redo(&self)
{
	while ((sz)self.commands.len() > self.index)
	{
		sz last = self.commands.len() - 1;
		self.memory -= self.commands[last].text.len;
		self.commands[last].text.free(self.allocator);
		self.commands.remove_at(last);
	}
}

fn void History.push(&self, CommandKind kind, usz offset, String text, double now)
{
	self.truncate_redo();
	self.commands.push({ .kind = kind, .offset = offset, .text = text });
	self.index = self.commands.len();
	self.memory += text.len;
	self.last_time = now;
	self.evict();
}

fn void History.evict(&self)
{
	while (self.memory > self.budget && self.commands.len() > 0)
	{
		self.memory -= self.commands[0].text.len;
		self.commands[0].text.free(self.allocator);
		self.commands.remove_at(0);
		if (self.index > 0) self.index--;
	}
}

fn bool History.can_coalesce(&self, CommandKind kind, double now)
{
	if (self.index == 0 || self.index != (sz)self.commands.len()) return false;
	if (now - self.last_time > COALESCE_SECONDS) return false;
	return self.commands[self.index - 1].kind == kind;
}

fn usz History.insert(&self, PieceTable* table, usz cursor, String text, double now)
{
	if (text.len == 0) return cursor;
	(void)table.insert(cursor, text);

	if (self.can_coalesce(CommandKind.INSERT, now))
	{
		EditCommand* last = self.commands.get_ref(self.index - 1);
		if (last.offset + last.text.len == cursor)
		{
			String merged = string::format(self.allocator, "%s%s", last.text, text);
			last.text.free(self.allocator);
			last.text = merged;
			self.memory += text.len;
			self.last_time = now;
			self.evict();
			return cursor + text.len;
		}
	}

	self.push(CommandKind.INSERT, cursor, text.copy(self.allocator), now);
	return cursor + text.len;
}

fn usz History.backspace(&self, PieceTable* table, usz cursor, double now)
{
	if (cursor == 0) return 0;
	usz prev       = table.prev_boundary(cursor - 1);
	String removed = table.slice(prev, cursor - prev, self.allocator);
	(void)table.delete(prev, cursor - prev);

	if (self.can_coalesce(CommandKind.BACKSPACE, now))
	{
		EditCommand* last = self.commands.get_ref(self.index - 1);
		if (last.offset == cursor)
		{
			usz removed_len = removed.len;
			String merged   = string::format(self.allocator, "%s%s", removed, last.text);
			removed.free(self.allocator);
			last.text.free(self.allocator);
			last.text = merged;
			last.offset = prev;
			self.memory += removed_len;
			self.last_time = now;
			self.evict();
			return prev;
		}
	}

	self.push(CommandKind.BACKSPACE, prev, removed, now);
	return prev;
}

fn usz History.delete_forward(&self, PieceTable* table, usz cursor, double now)
{
	if (cursor >= table.length()) return cursor;
	usz next       = table.next_boundary(cursor);
	String removed = table.slice(cursor, next - cursor, self.allocator);
	(void)table.delete(cursor, next - cursor);

	if (self.can_coalesce(CommandKind.DELETE, now))
	{
		EditCommand* last = self.commands.get_ref(self.index - 1);
		if (last.offset + last.text.len == cursor)
		{
			usz removed_len = removed.len;
			String merged   = string::format(self.allocator, "%s%s", last.text, removed);
			removed.free(self.allocator);
			last.text.free(self.allocator);
			last.text = merged;
			self.memory += removed_len;
			self.last_time = now;
			self.evict();
			return cursor;
		}
	}

	self.push(CommandKind.DELETE, cursor, removed, now);
	return cursor;
}

fn bool History.undo(&self, PieceTable* table, usz* cursor)
{
	if (self.index <= 0) return false;
	EditCommand* cmd = self.commands.get_ref(self.index - 1);

	if (cmd.kind == CommandKind.INSERT)
	{
		(void)table.delete(cmd.offset, cmd.text.len);
		*cursor = cmd.offset;
	}
	else
	{
		(void)table.insert(cmd.offset, cmd.text);
		*cursor = cmd.offset + cmd.text.len;
	}

	self.index--;
	self.last_time = -1000.0;
	return true;
}