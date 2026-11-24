module yun::console;

import raylib6::rl;
import std::collections::list;
import std::core::dstring;
import std::core::mem::alloc;

const int DEFAULT_MAX_LINES = 2000;
const usz DEFAULT_MAX_BYTES = 1024 * 1024;
const usz MAX_LINE_BYTES    = 16 * 1024;
const sz COMPACT_THRESHOLD  = 512;
const int STREAM_OUT        = 0;
const int STREAM_ERR        = 1;
const uint SPAN_BOLD        = 1;
const uint SPAN_DIM         = 2;
const uint SPAN_UNDERLINE   = 4;

struct ConsoleSpan
{
	usz start;
	usz len;
	RLColor fg;
	RLColor bg;
	uint attrs;
}

struct ConsoleStyle
{
	RLColor fg;
	RLColor bg;
	bool fg_set;
	bool bg_set;
	uint attrs;
}

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
	ConsoleSpan* spans;
	int span_count;
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
	char[64] csi;
	int csi_len;
	List{ConsoleSpan} spans;
	ConsoleStyle style;
	usz span_start;
}

struct ConsoleBuffer
{
	Allocator allocator;
	List{ConsoleLine} lines;
	sz first;
	usz total_bytes;
	int max_lines;
	usz max_bytes;
	int revision;
	bool truncated;
	bool render_ansi;
	bool show_headers;
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
	self.revision = 0;
	self.truncated = false;
	self.render_ansi = true;
	self.show_headers = true;
	for (int i = 0; i < 2; i++)
	{
		self.streams[i].pending.init(allocator);
		self.streams[i].ansi_state = (int)ConsoleAnsiState.TEXT;
		self.streams[i].pending_cr = false;
		self.streams[i].csi_len = 0;
		self.streams[i].spans.init(allocator);
		self.streams[i].style = { };
		self.streams[i].span_start = 0;
	}
}

fn void ConsoleBuffer.set_render_ansi(&self, bool enabled)
{
	if (self.render_ansi == enabled) return;
	self.render_ansi = enabled;
	if (!enabled)
	{
		for (int i = 0; i < 2; i++)
		{
			self.streams[i].spans.clear();
			self.streams[i].style = { };
			self.streams[i].span_start = (usz)self.streams[i].pending.len();
		}
	}
}

fn void ConsoleBuffer.set_show_headers(&self, bool enabled)
{
	self.show_headers = enabled;
}

fn void ConsoleBuffer.set_limits(&self, int max_lines, usz max_bytes)
{
	int lines = max_lines > 0 ? max_lines : 1;
	if (self.max_lines == lines && self.max_bytes == max_bytes) return;
	self.max_lines = lines;
	self.max_bytes = max_bytes;
	self.trim();
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
	if (text.len == 0) return "";
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
		if (line.spans) alloc::free(self.allocator, line.spans);
		line.text = "";
		line.spans = null;
		line.span_count = 0;
		if (length <= self.total_bytes)
		{
			self.total_bytes -= length;
		}
		else
		{
			self.total_bytes = 0;
		}
		self.first++;
		self.revision++;
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

fn void ConsoleBuffer.push_line(&self, ConsoleStream stream, String text, ConsoleSpan* spans, int span_count)
{
	self.lines.push({ .text = text, .stream = stream, .spans = spans, .span_count = span_count });
	self.revision++;
	self.total_bytes += text.len;
	self.trim();
}

fn void ConsoleBuffer.emit_pending(&self, int index, bool force)
{
	ConsoleStreamState* state = &self.streams[index];
	if (state.pending.len() == 0 && !force) return;
	self.close_span(index);
	String text;
	ConsoleSpan* clean_spans = null;
	int clean_count          = 0;
	if (state.spans.len() == 0)
	{
		text = sanitize_utf8(self.allocator, state.pending.str_view());
	}
	else
	{
		DString clean;
		clean.init(self.allocator, state.pending.len() + 1);
		ConsoleSpan[] mapped = alloc::new_array(self.allocator, ConsoleSpan, (usz)state.spans.len());
		usz raw              = 0;
		for (sz i = 0; i < state.spans.len(); i++)
		{
			ConsoleSpan span = state.spans[i];
			if (span.start > raw)
			{
				String plain = sanitize_utf8(self.allocator, state.pending.str_view()[raw:span.start - raw]);
				clean.append_string(plain);
				if (plain.len > 0) plain.free(self.allocator);
			}
			String segment = sanitize_utf8(self.allocator, state.pending.str_view()[span.start:span.len]);
			usz start      = (usz)clean.len();
			clean.append_string(segment);
			if (segment.len > 0) segment.free(self.allocator);
			if (clean.len() > (sz)start)
			{
				mapped[clean_count] = {
					.start = start,
					.len = (usz)clean.len() - start,
					.fg = span.fg,
					.bg = span.bg,
					.attrs = span.attrs,
				};
				clean_count++;
			}
			raw = span.start + span.len;
		}
		if (raw < (usz)state.pending.len())
		{
			String tail = sanitize_utf8(self.allocator, state.pending.str_view()[raw:(usz)state.pending.len() - raw]);
			clean.append_string(tail);
			if (tail.len > 0) tail.free(self.allocator);
		}
		text = clean.str_view().copy(self.allocator);
		clean.free();
		if (clean_count > 0)
		{
			clean_spans = mapped.ptr;
		}
		else
		{
			alloc::free(self.allocator, mapped.ptr);
		}
	}
	state.pending.clear();
	state.spans.clear();
	state.span_start = 0;
	self.push_line(index == STREAM_ERR ? ConsoleStream.STDERR : ConsoleStream.STDOUT, text, clean_spans, clean_count);
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

fn RLColor ansi_basic(int index, bool bright)
{
	switch (index)
	{
		case 0:
			return bright ? (RLColor) { 102, 102, 102, 255 } : (RLColor) { 0, 0, 0, 255 };
		case 1:
			return bright ? (RLColor) { 241, 76, 76, 255 } : (RLColor) { 205, 49, 49, 255 };
		case 2:
			return bright ? (RLColor) { 35, 209, 139, 255 } : (RLColor) { 13, 188, 121, 255 };
		case 3:
			return bright ? (RLColor) { 245, 245, 67, 255 } : (RLColor) { 229, 229, 16, 255 };
		case 4:
			return bright ? (RLColor) { 59, 142, 234, 255 } : (RLColor) { 36, 114, 200, 255 };
		case 5:
			return bright ? (RLColor) { 214, 112, 214, 255 } : (RLColor) { 188, 63, 188, 255 };
		case 6:
			return bright ? (RLColor) { 41, 184, 219, 255 } : (RLColor) { 17, 168, 205, 255 };
		default:
			return bright ? (RLColor) { 255, 255, 255, 255 } : (RLColor) { 229, 229, 229, 255 };
	}
}

fn RLColor ansi_256(int index)
{
	if (index < 0) index = 0;
	if (index < 16) return ansi_basic(index & 7, index >= 8);
	if (index < 232)
	{
		int value = index - 16;
		int r     = value / 36;
		int g     = (value / 6) % 6;
		int b     = value % 6;
		return (RLColor) {
			(char)(r == 0 ? 0 : 55 + r * 40),
			(char)(g == 0 ? 0 : 55 + g * 40),
			(char)(b == 0 ? 0 : 55 + b * 40),
			255
		};
	}
	int gray = 8 + (index - 232) * 10;
	return (RLColor) { (char)gray, (char)gray, (char)gray, 255 };
}

fn RLColor ansi_truecolor(int r, int g, int b)
{
	if (r < 0) r = 0;
	if (g < 0) g = 0;
	if (b < 0) b = 0;
	if (r > 255) r = 255;
	if (g > 255) g = 255;
	if (b > 255) b = 255;
	return (RLColor) { (char)r, (char)g, (char)b, 255 };
}

fn void ConsoleBuffer.close_span(&self, int index)
{
	ConsoleStreamState* state = &self.streams[index];
	if ((usz)state.pending.len() <= state.span_start) return;
	bool styled = state.style.fg_set || state.style.bg_set || state.style.attrs != 0;
	if (!styled)
	{
		state.span_start = (usz)state.pending.len();
		return;
	}
	state.spans.push(
		{
			.start = state.span_start,
			.len = (usz)state.pending.len() - state.span_start,
			.fg = state.style.fg,
			.bg = state.style.bg,
			.attrs = state.style.attrs,
		}
	);
	state.span_start = (usz)state.pending.len();
}

fn void ConsoleBuffer.apply_sgr(&self, int index, String params)
{
	ConsoleStreamState* state = &self.streams[index];
	self.close_span(index);
	int[32] values;
	int count = 0;
	if (params.len == 0)
	{
		values[0] = 0;
		count = 1;
	}
	else
	{
		int value = 0;
		for (usz i = 0; i < params.len && count < 32; i++)
		{
			char c = params[i];
			if (c >= '0' && c <= '9')
			{
				value = value * 10 + (int)(c - '0');
			}
			else if (c == ';')
			{
				values[count] = value;
				count++;
				value = 0;
			}
		}
		if (count < 32)
		{
			values[count] = value;
			count++;
		}
	}
	for (int i = 0; i < count; i++)
	{
		int value = values[i];
		if (value == 0)
		{
			state.style = { };
		}
		else if (value == 1)
		{
			state.style.attrs |= SPAN_BOLD;
		}
		else if (value == 2)
		{
			state.style.attrs |= SPAN_DIM;
		}
		else if (value == 4)
		{
			state.style.attrs |= SPAN_UNDERLINE;
		}
		else if (value == 22)
		{
			state.style.attrs &= ~(SPAN_BOLD | SPAN_DIM);
		}
		else if (value == 24)
		{
			state.style.attrs &= ~SPAN_UNDERLINE;
		}
		else if (value >= 30 && value <= 37)
		{
			state.style.fg = ansi_basic(value - 30, false);
			state.style.fg_set = true;
		}
		else if (value == 39)
		{
			state.style.fg_set = false;
		}
		else if (value >= 40 && value <= 47)
		{
			state.style.bg = ansi_basic(value - 40, false);
			state.style.bg_set = true;
		}
		else if (value == 49)
		{
			state.style.bg_set = false;
		}
		else if (value >= 90 && value <= 97)
		{
			state.style.fg = ansi_basic(value - 90, true);
			state.style.fg_set = true;
		}
		else if (value >= 100 && value <= 107)
		{
			state.style.bg = ansi_basic(value - 100, true);
			state.style.bg_set = true;
		}
		else if ((value == 38 || value == 48) && i + 1 < count)
		{
			RLColor color   = { };
			bool have_color = false;
			if (values[i + 1] == 5 && i + 2 < count)
			{
				color = ansi_256(values[i + 2]);
				i += 2;
				have_color = true;
			}
			else if (values[i + 1] == 2 && i + 4 < count)
			{
				color = ansi_truecolor(values[i + 2], values[i + 3], values[i + 4]);
				i += 4;
				have_color = true;
			}
			if (have_color)
			{
				if (value == 38)
				{
					state.style.fg = color;
					state.style.fg_set = true;
				}
				else
				{
					state.style.bg = color;
					state.style.bg_set = true;
				}
			}
		}
	}
	state.span_start = (usz)state.pending.len();
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
				state.csi_len = 0;
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
				state.csi_len = 0;
				continue;
			}
			if (b >= 0x20 && b <= 0x3F)
			{
				if (state.csi_len < (int)state.csi.len - 1)
				{
					state.csi[state.csi_len] = c;
					state.csi_len++;
				}
				continue;
			}
			if (b >= 0x40 && b <= 0x7E)
			{
				if (c == 'm' && self.render_ansi) self.apply_sgr(index, (String)state.csi[0:state.csi_len]);
				state.csi_len = 0;
				state.ansi_state = (int)ConsoleAnsiState.TEXT;
				continue;
			}
			state.csi_len = 0;
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
	if (!self.show_headers) return;
	String header = string::format(self.allocator, "$ %s", command);
	self.push_line(ConsoleStream.COMMAND, header, null, 0);
}

fn void ConsoleBuffer.clear(&self)
{
	for (sz i = self.first; i < self.lines.len(); i++)
	{
		if (self.lines[i].text.len > 0) self.lines[i].text.free(self.allocator);
		if (self.lines[i].spans) alloc::free(self.allocator, self.lines[i].spans);
		self.lines[i].spans = null;
		self.lines[i].span_count = 0;
	}
	self.lines.clear();
	self.first = 0;
	self.total_bytes = 0;
	self.revision++;
	self.truncated = false;
	for (int i = 0; i < 2; i++)
	{
		self.streams[i].pending.clear();
		self.streams[i].ansi_state = (int)ConsoleAnsiState.TEXT;
		self.streams[i].pending_cr = false;
		self.streams[i].csi_len = 0;
		self.streams[i].spans.clear();
		self.streams[i].style = { };
		self.streams[i].span_start = 0;
	}
}

fn void ConsoleBuffer.destroy(&self)
{
	self.clear();
	for (int i = 0; i < 2; i++)
	{
		self.streams[i].pending.free();
		self.streams[i].spans.free();
	}
	self.lines.free();
}