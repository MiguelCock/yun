module yun::lsp;

import std::core::dstring;
import yun::text;

fn uint utf16_len_for_lead(char lead)
{
	int b = (int)lead & 0xFF;
	if (b >= 0xF0) return 2;
	return 1;
}

fn usz line_content_end(PieceTable* table, usz line, usz line_start_offset)
{
	usz count = table.line_count();
	usz end   = line + 1 < count ? table.line_start(line + 1) : table.length();
	if (end > line_start_offset && table.byte_at(end - 1) == '\n') end--;
	if (end > line_start_offset && table.byte_at(end - 1) == '\r') end--;
	return end;
}

fn uint position_character(PieceTable* table, usz line, usz offset)
{
	usz start  = table.line_start(line);
	usz end    = line_content_end(table, line, start);
	usz pos    = start;
	uint units = 0;
	while (pos < offset && pos < end)
	{
		units += utf16_len_for_lead(table.byte_at(pos));
		pos = table.next_boundary(pos);
	}
	return units;
}

fn void position_from_offset(PieceTable* table, usz offset, uint* out_line, uint* out_character)
{
	usz line = table.line_of(offset);
	*out_line = (uint)line;
	*out_character = position_character(table, line, offset);
}

fn usz offset_from_position(PieceTable* table, uint line, uint character)
{
	usz count = table.line_count();
	if (count == 0) return 0;
	usz l      = (usz)line >= count ? count - 1 : (usz)line;
	usz start  = table.line_start(l);
	usz end    = line_content_end(table, l, start);
	usz pos    = start;
	uint units = 0;
	while (pos < end)
	{
		if (units >= character) break;
		uint len = utf16_len_for_lead(table.byte_at(pos));
		if (units + len > character) break;
		units += len;
		pos = table.next_boundary(pos);
	}
	if (pos > end) pos = end;
	return pos;
}

fn bool uri_unreserved(char c)
{
	return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_'
		|| c == '.'
		|| c == '~';
}

fn void append_percent(DString* out, char c)
{
	const char[] HEX_DIGITS = "0123456789ABCDEF";
	int b                   = (int)c & 0xFF;
	out.append_char('%');
	out.append_char(HEX_DIGITS[(b >> 4) & 0xF]);
	out.append_char(HEX_DIGITS[b & 0xF]);
}

fn String path_to_uri(Allocator allocator, String abs_path)
{
	DString out;
	out.init(allocator, abs_path.len + 8);
	out.append_string("file://");
	for (usz i = 0; i < abs_path.len; i++)
	{
		char c = abs_path[i];
		if (uri_unreserved(c) || c == '/')
		{
			out.append_char(c);
		}
		else
		{
			append_percent(&out, c);
		}
	}
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn int hex_value(char c)
{
	if (c >= '0' && c <= '9') return (int)(c - '0');
	if (c >= 'A' && c <= 'F') return (int)(c - 'A') + 10;
	if (c >= 'a' && c <= 'f') return (int)(c - 'a') + 10;
	return -1;
}

fn String uri_to_path(Allocator allocator, String uri)
{
	String body = uri;
	if (body.starts_with("file://")) body = body[7..];
	DString out;
	out.init(allocator, body.len + 1);
	usz i = 0;
	while (i < body.len)
	{
		char c = body[i];
		if (c == '%' && i + 2 < body.len)
		{
			int hi = hex_value(body[i + 1]);
			int lo = hex_value(body[i + 2]);
			if (hi >= 0 && lo >= 0)
			{
				out.append_char((char)((hi << 4) | lo));
				i += 3;
				continue;
			}
		}
		out.append_char(c);
		i++;
	}
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}