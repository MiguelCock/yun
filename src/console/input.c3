module yun::console;

import std::collections::list;
import std::core::dstring;

const int DEFAULT_HISTORY = 100;

struct ConsoleInput
{
	Allocator allocator;
	DString text;
	sz cursor;
}

fn void ConsoleInput.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.text.init(allocator);
	self.cursor = 0;
}

fn void ConsoleInput.destroy(&self)
{
	self.text.free();
}

fn sz ConsoleInput.len(&self)
{
	return self.text.len();
}

fn String ConsoleInput.text_view(&self)
{
	return self.text.str_view();
}

fn void ConsoleInput.clear(&self)
{
	self.text.clear();
	self.cursor = 0;
}

fn void ConsoleInput.set(&self, String value)
{
	self.text.clear();
	self.text.append_string(value);
	self.cursor = self.text.len();
}

fn sz ConsoleInput.prev_boundary(&self, sz at)
{
	if (at <= 0) return 0;
	sz pos = at - 1;
	while (pos > 0 && (((int)self.text.char_at(pos) & 0xC0) == 0x80)) pos--;
	return pos;
}

fn sz ConsoleInput.next_boundary(&self, sz at)
{
	sz len = self.text.len();
	if (at >= len) return len;
	sz pos = at + 1;
	while (pos < len && (((int)self.text.char_at(pos) & 0xC0) == 0x80)) pos++;
	return pos;
}

fn int encode_utf8(int codepoint, char* out)
{
	if (codepoint < 0x80)
	{
		out[0] = (char)codepoint;
		return 1;
	}
	if (codepoint < 0x800)
	{
		out[0] = (char)(0xC0 | (codepoint >> 6));
		out[1] = (char)(0x80 | (codepoint & 0x3F));
		return 2;
	}
	if (codepoint < 0x10000)
	{
		out[0] = (char)(0xE0 | (codepoint >> 12));
		out[1] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
		out[2] = (char)(0x80 | (codepoint & 0x3F));
		return 3;
	}
	out[0] = (char)(0xF0 | (codepoint >> 18));
	out[1] = (char)(0x80 | ((codepoint >> 12) & 0x3F));
	out[2] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
	out[3] = (char)(0x80 | (codepoint & 0x3F));
	return 4;
}

fn void ConsoleInput.insert_codepoint(&self, int codepoint)
{
	if (codepoint < 32 || codepoint > 0x10FFFF) return;
	char[4] encoded;
	int count = encode_utf8(codepoint, &encoded[0]);
	if (self.cursor == self.text.len())
	{
		self.text.append_bytes(encoded[0:count]);
	}
	else
	{
		self.text.insert_chars_at(self.cursor, (String)encoded[0:count]);
	}
	self.cursor += count;
}

fn void ConsoleInput.insert_string(&self, String value)
{
	if (value.len == 0) return;
	if (self.cursor == self.text.len())
	{
		self.text.append_string(value);
	}
	else
	{
		self.text.insert_chars_at(self.cursor, value);
	}
	self.cursor += value.len;
}

fn void ConsoleInput.backspace(&self)
{
	if (self.cursor <= 0) return;
	sz start = self.prev_boundary(self.cursor);
	self.text.delete(start, self.cursor - start);
	self.cursor = start;
}

fn void ConsoleInput.delete_forward(&self)
{
	if (self.cursor >= self.text.len()) return;
	sz end = self.next_boundary(self.cursor);
	self.text.delete(self.cursor, end - self.cursor);
}

fn void ConsoleInput.move_left(&self)
{
	if (self.cursor <= 0) return;
	self.cursor = self.prev_boundary(self.cursor);
}

fn void ConsoleInput.move_right(&self)
{
	if (self.cursor >= self.text.len()) return;
	self.cursor = self.next_boundary(self.cursor);
}

fn void ConsoleInput.home(&self)
{
	self.cursor = 0;
}

fn void ConsoleInput.end(&self)
{
	self.cursor = self.text.len();
}

struct ConsoleHistory
{
	Allocator allocator;
	List{String} entries;
	String draft;
	sz cursor;
	bool browsing;
	int max_entries;
}

fn void ConsoleHistory.init(&self, Allocator allocator, int max_entries = DEFAULT_HISTORY)
{
	self.allocator = allocator;
	self.entries.init(allocator);
	self.draft = "";
	self.cursor = 0;
	self.browsing = false;
	self.max_entries = max_entries > 0 ? max_entries : 1;
}

fn void ConsoleHistory.clear_draft(&self)
{
	if (self.draft.len > 0) self.draft.free(self.allocator);
	self.draft = "";
}

fn void ConsoleHistory.clear(&self)
{
	for (sz i = 0; i < self.entries.len(); i++)
	{
		if (self.entries[i].len > 0) self.entries[i].free(self.allocator);
	}
	self.entries.clear();
	self.clear_draft();
	self.cursor = 0;
	self.browsing = false;
}

fn void ConsoleHistory.destroy(&self)
{
	self.clear();
	self.entries.free();
}

fn void ConsoleHistory.add(&self, String command)
{
	if (command.len == 0) return;
	if (self.entries.len() > 0 && self.entries[self.entries.len() - 1].compare_to(command) == 0)
	{
		self.browsing = false;
		self.cursor = self.entries.len();
		return;
	}
	if (self.entries.len() >= (sz)self.max_entries)
	{
		self.entries[0].free(self.allocator);
		self.entries.remove_at(0);
	}
	self.entries.push(command.copy(self.allocator));
	self.clear_draft();
	self.browsing = false;
	self.cursor = self.entries.len();
}

fn bool ConsoleHistory.previous(&self, ConsoleInput* input)
{
	if (self.entries.len() == 0) return false;
	if (!self.browsing)
	{
		self.clear_draft();
		self.draft = input.text_view().copy(self.allocator);
		self.browsing = true;
		self.cursor = self.entries.len();
	}
	if (self.cursor > 0) self.cursor--;
	input.set(self.entries[self.cursor]);
	return true;
}

fn bool ConsoleHistory.next(&self, ConsoleInput* input)
{
	if (!self.browsing) return false;
	self.cursor++;
	if (self.cursor >= self.entries.len())
	{
		self.browsing = false;
		self.cursor = self.entries.len();
		String draft = self.draft;
		self.draft = "";
		input.set(draft);
		if (draft.len > 0) draft.free(self.allocator);
		return true;
	}
	input.set(self.entries[self.cursor]);
	return true;
}