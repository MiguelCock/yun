module yun::console;

import std::collections::list;
import std::core::dstring;

const int DEFAULT_MAX_LINES = 2000;
const usz DEFAULT_MAX_BYTES = 1024 * 1024;
const usz MAX_LINE_BYTES    = 16 * 1024;
const sz COMPACT_THRESHOLD  = 512;
const int STREAM_OUT        = 0;
const int STREAM_ERR        = 1;

enum ConsoleStream : int
{
	COMMAND,
	STDOUT,
	STDERR,
}

struct ConsoleLine
{
	String text;
	ConsoleStream stream;
}

enum ConsoleAnsiState : int
{
	TEXT,
	ESCAPE,
	CSI,
	OSC,
	OSC_ESCAPE,
}

struct ConsoleStreamState
{
	DString pending;
	int ansi_state;
	bool pending_cr;
}

struct ConsoleBuffer
{
	Allocator allocator;
	List{ConsoleLine} lines;
	sz first;
	usz total_bytes;
	int max_lines;
	usz max_bytes;
	bool truncated;
	ConsoleStreamState[2] streams;
}

fn void ConsoleBuffer.init(
	&self,
	Allocator allocator,
	int max_lines = DEFAULT_MAX_LINES,
	usz max_bytes = DEFAULT_MAX_BYTES
)
{
	self.allocator = allocator;
	self.lines.init(allocator);
	self.first = 0;
	self.total_bytes = 0;
	self.max_lines = max_lines > 0 ? max_lines : 1;
	self.max_bytes = max_bytes;
	self.truncated = false;
	for (int i = 0; i < 2; i++)
	{
		self.streams[i].pending.init(allocator);
		self.streams[i].ansi_state = (int)ConsoleAnsiState.TEXT;
		self.streams[i].pending_cr = false;
	}
}

fn sz ConsoleBuffer.line_count(&self)
{
	return self.lines.len() - self.first;
}

fn ConsoleLine* ConsoleBuffer.line_at(&self, sz index)
{
	if (index < 0 || index >= self.line_count()) return null;
	return &self.lines[self.first + index];
}

fn int stream_index(ConsoleStream stream)
{
	return stream == ConsoleStream.STDERR ? STREAM_ERR : STREAM_OUT;
}

fn bool is_continuation(char c)
{
	int b = (int)c & 0xFF;
	return (b & 0xC0) == 0x80;
}

fn int utf8_sequence_length(String text, usz i)
{
	usz len = text.len;
	if (i >= len) return 0;
	int b = (int)text[i] & 0xFF;
	if (b < 0x80) return 1;
	if (b >= 0xC2 && b <= 0xDF)
	{
		return i + 1 < len && is_continuation(text[i + 1]) ? 2 : 0;
	}
	if (b == 0xE0)
	{
		if (i + 2 >= len) return 0;
		int b1 = (int)text[i + 1] & 0xFF;
		return b1 >= 0xA0 && b1 <= 0xBF && is_continuation(text[i + 2]) ? 3 : 0;
	}
	if (b >= 0xE1 && b <= 0xEC)
	{
		return i + 2 < len && is_continuation(text[i + 1]) && is_continuation(text[i + 2]) ? 3 : 0;
	}
	if (b == 0xED)
	{
		if (i + 2 >= len) return 0;
		int b1 = (int)text[i + 1] & 0xFF;
		return b1 >= 0x80 && b1 <= 0x9F && is_continuation(text[i + 2]) ? 3 : 0;
	}
	if (b >= 0xEE && b <= 0xEF)
	{
		return i + 2 < len && is_continuation(text[i + 1]) && is_continuation(text[i + 2]) ? 3 : 0;
	}
	if (b == 0xF0)
	{
		if (i + 3 >= len) return 0;
		int b1 = (int)text[i + 1] & 0xFF;
		return b1 >= 0x90 && b1 <= 0xBF && is_continuation(text[i + 2]) && is_continuation(text[i + 3]) ? 4 : 0;
	}
	if (b >= 0xF1 && b <= 0xF3)
	{
		return i + 3 < len && is_continuation(
			text[i + 1]
		) && is_continuation(text[i + 2]) && is_continuation(text[i + 3]) ? 4
			: 0;
	}
	if (b == 0xF4)
	{
		if (i + 3 >= len) return 0;
		int b1 = (int)text[i + 1] & 0xFF;
		return b1 >= 0x80 && b1 <= 0x8F && is_continuation(text[i + 2]) && is_continuation(text[i + 3]) ? 4 : 0;
	}
	return 0;
}

fn String sanitize_utf8(Allocator allocator, String text)
{
	DString out;
	out.init(allocator, text.len + 1);
	char[3] replacement = { (char)0xEF, (char)0xBF, (char)0xBD };
	usz i               = 0;
	while (i < text.len)
	{
		int length = utf8_sequence_length(text, i);
		if (length == 0)
		{
			out.append_bytes(replacement[0:3]);
			i++;
			continue;
		}
		out.append_bytes(text[i:(usz)length]);
		i += (usz)length;
	}
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn void ConsoleBuffer.compact(&self)
{
	List{ConsoleLine} compacted;
	compacted.init(self.allocator, self.line_count());
	for (sz i = self.first; i < self.lines.len(); i++) compacted.push(self.lines[i]);
	self.lines.free();
	self.lines = compacted;
	self.first = 0;
}

fn void ConsoleBuffer.trim(&self)
{
	while (self.line_count() > (sz)self.max_lines
		|| (self.max_bytes > 0 && self.total_bytes > self.max_bytes && self.line_count() > 1))
	{
		ConsoleLine* line = &self.lines[self.first];
		usz length        = line.text.len;
		if (length > 0) line.text.free(self.allocator);
		line.text = "";
		if (length <= self.total_bytes)
		{
			self.total_bytes -= length;
		}
		else
		{
			self.total_bytes = 0;
		}
		self.first++;
		self.truncated = true;
	}
	if (self.first > 0 && self.first >= self.lines.len())
	{
		self.lines.clear();
		self.first = 0;
	}
	else if (self.first >= COMPACT_THRESHOLD && self.first * 2 >= self.lines.len())
	{
		self.compact();
	}
}

fn void ConsoleBuffer.push_line(&self, ConsoleStream stream, String text)
{
	self.lines.push({ .text = text, .stream = stream });
	self.total_bytes += text.len;
	self.trim();
}

fn void ConsoleBuffer.emit_pending(&self, int index, bool force)
{
	ConsoleStreamState* state = &self.streams[index];
	if (state.pending.len() == 0 && !force) return;
	String text = sanitize_utf8(self.allocator, state.pending.str_view());
	state.pending.clear();
	self.push_line(index == STREAM_ERR ? ConsoleStream.STDERR : ConsoleStream.STDOUT, text);
}

fn void ConsoleBuffer.flush_stream(&self, int index)
{
	ConsoleStreamState* state = &self.streams[index];
	if (state.pending_cr)
	{
		state.pending_cr = false;
		self.emit_pending(index, true);
	}
	else if (state.pending.len() > 0)
	{
		self.emit_pending(index, false);
	}
}

fn void ConsoleBuffer.flush(&self)
{
	self.flush_stream(STREAM_OUT);
	self.flush_stream(STREAM_ERR);
}

fn void ConsoleBuffer.append_stream(&self, int index, String chunk)
{
	ConsoleStreamState* state = &self.streams[index];
	for (usz i = 0; i < chunk.len; i++)
	{
		char c = chunk[i];
		int b  = (int)c & 0xFF;

		if (state.ansi_state == (int)ConsoleAnsiState.ESCAPE)
		{
			if (c == '[')
			{
				state.ansi_state = (int)ConsoleAnsiState.CSI;
			}
			else if (c == ']')
			{
				state.ansi_state = (int)ConsoleAnsiState.OSC;
			}
			else
			{
				state.ansi_state = (int)ConsoleAnsiState.TEXT;
			}
			continue;
		}
		if (state.ansi_state == (int)ConsoleAnsiState.CSI)
		{
			if (b == 0x1B)
			{
				state.ansi_state = (int)ConsoleAnsiState.ESCAPE;
				continue;
			}
			if (b >= 0x20 && b <= 0x3F) continue;
			if (b >= 0x40 && b <= 0x7E)
			{
				state.ansi_state = (int)ConsoleAnsiState.TEXT;
				continue;
			}
			state.ansi_state = (int)ConsoleAnsiState.TEXT;
		}
		else if (state.ansi_state == (int)ConsoleAnsiState.OSC)
		{
			if (b == 0x07)
			{
				state.ansi_state = (int)ConsoleAnsiState.TEXT;
				continue;
			}
			if (b == 0x1B)
			{
				state.ansi_state = (int)ConsoleAnsiState.OSC_ESCAPE;
				continue;
			}
			continue;
		}
		else if (state.ansi_state == (int)ConsoleAnsiState.OSC_ESCAPE)
		{
			if (c == '\\')
			{
				state.ansi_state = (int)ConsoleAnsiState.TEXT;
			}
			else if (b != 0x1B)
			{
				state.ansi_state = (int)ConsoleAnsiState.OSC;
			}
			continue;
		}

		if (state.pending_cr)
		{
			if (b == '\n')
			{
				state.pending_cr = false;
				self.emit_pending(index, true);
				continue;
			}
			state.pending_cr = false;
			self.emit_pending(index, true);
		}

		if (b == 0x1B)
		{
			state.ansi_state = (int)ConsoleAnsiState.ESCAPE;
			continue;
		}
		if (b == '\r')
		{
			state.pending_cr = true;
			continue;
		}
		if (b == '\n')
		{
			self.emit_pending(index, true);
			continue;
		}
		if (b == '\t')
		{
			state.pending.append_char_repeat(' ', 4);
		}
		else if (b >= 0x20 && b != 0x7F)
		{
			state.pending.append_char(c);
		}
		if (state.pending.len() >= (sz)MAX_LINE_BYTES) self.emit_pending(index, false);
	}
}

fn void ConsoleBuffer.append_stdout(&self, String text)
{
	self.append_stream(STREAM_OUT, text);
}

fn void ConsoleBuffer.append_stderr(&self, String text)
{
	self.append_stream(STREAM_ERR, text);
}

fn void ConsoleBuffer.append_command(&self, String command)
{
	self.flush();
	String header = string::format(self.allocator, "$ %s", command);
	self.push_line(ConsoleStream.COMMAND, header);
}

fn void ConsoleBuffer.clear(&self)
{
	for (sz i = self.first; i < self.lines.len(); i++)
	{
		if (self.lines[i].text.len > 0) self.lines[i].text.free(self.allocator);
	}
	self.lines.clear();
	self.first = 0;
	self.total_bytes = 0;
	self.truncated = false;
	for (int i = 0; i < 2; i++)
	{
		self.streams[i].pending.clear();
		self.streams[i].ansi_state = (int)ConsoleAnsiState.TEXT;
		self.streams[i].pending_cr = false;
	}
}

fn void ConsoleBuffer.destroy(&self)
{
	self.clear();
	for (int i = 0; i < 2; i++) self.streams[i].pending.free();
	self.lines.free();
}