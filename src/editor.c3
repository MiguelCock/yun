module yun::editor;

import std::math;
import yun::text;

struct EditorMetrics
{
	float char_width;
	float line_height;
	float padding_x;
	float padding_y;
}

struct VisibleRange
{
	usz first;
	usz last;
}

fn VisibleRange visible_lines(usz line_count, float scroll_y, float viewport_height, float line_height)
{
	VisibleRange range;
	if (line_height <= 0.0f || line_count == 0)
	{
		range.first = 0;
		range.last = 0;
		return range;
	}
	usz first = (usz)math::floor(math::max(scroll_y / line_height, 0.0f));
	usz last  = (usz)math::ceil((scroll_y + viewport_height) / line_height) + 1;
	if (first > line_count) first = line_count;
	if (last > line_count) last = line_count;
	if (last < first) last = first;
	range.first = first;
	range.last = last;
	return range;
}

fn float line_y(usz line, float scroll_y, EditorMetrics metrics)
{
	return metrics.padding_y + (float)line * metrics.line_height - scroll_y;
}

fn float x_for_column(usz column, EditorMetrics metrics)
{
	return metrics.padding_x + (float)column * metrics.char_width;
}

fn usz line_length_bytes(PieceTable* table, usz line)
{
	usz start = table.line_start(line);
	usz end   = line + 1 < table.line_count() ? table.line_start(line + 1) : table.length();
	usz len   = end - start;
	if (len > 0 && table.char_at(end - 1) == '\n') len--;
	return len;
}

fn String line_text(PieceTable* table, usz line, Allocator allocator)
{
	return table.slice(table.line_start(line), line_length_bytes(table, line), allocator);
}

fn usz column_for_offset(PieceTable* table, usz line, usz offset)
{
	usz start = table.line_start(line);
	if (offset <= start) return 0;
	usz pos    = start;
	usz column = 0;
	while (pos < offset && pos < table.length())
	{
		pos = table.next_boundary(pos);
		column++;
	}
	return column;
}

fn usz offset_for_point(PieceTable* table, float local_x, float local_y, float scroll_y, EditorMetrics metrics)
{
	if (metrics.line_height <= 0.0f || metrics.char_width <= 0.0f) return 0;
	usz line_count = table.line_count();
	if (line_count == 0) return 0;

	float content_y = local_y + scroll_y - metrics.padding_y;
	sz line         = (sz)math::floor(content_y / metrics.line_height);
	if (line < 0) line = 0;
	if ((usz)line >= line_count) line = (sz)(line_count - 1);

	float content_x = local_x - metrics.padding_x;
	sz column       = (sz)math::round(content_x / metrics.char_width);
	if (column < 0) column = 0;

	usz start   = table.line_start((usz)line);
	usz max_col = column_for_offset(table, (usz)line, start + line_length_bytes(table, (usz)line));
	if ((usz)column > max_col) column = (sz)max_col;

	usz pos      = start;
	sz remaining = column;
	while (remaining > 0 && pos < table.length())
	{
		pos = table.next_boundary(pos);
		remaining--;
	}
	return pos;
}

fn float gutter_width(usz line_count, EditorMetrics metrics)
{
	usz digits = 1;
	usz n      = line_count > 0 ? line_count : 1;
	while (n >= 10)
	{
		n /= 10;
		digits++;
	}
	return (float)digits * metrics.char_width + metrics.padding_x * 2.0f;
}

fn usz max_line_columns(PieceTable* table, VisibleRange range)
{
	usz max_columns = 0;
	for (usz line = range.first; line < range.last; line++)
	{
		usz columns = column_for_offset(table, line, table.line_start(line) + line_length_bytes(table, line));
		if (columns > max_columns) max_columns = columns;
	}
	return max_columns;
}

fn float content_width(PieceTable* table, VisibleRange range, EditorMetrics metrics)
{
	return x_for_column(max_line_columns(table, range), metrics);
}