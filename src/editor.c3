module yun::editor;

import raylib6::rl;
import std::core::mem::alloc;
import std::math;
import yun::card;
import yun::text;

const RLColor EDITOR_TEXT        = { 210, 214, 222, 255 };
const RLColor EDITOR_PLACEHOLDER = { 70, 76, 90, 255 };
const RLColor EDITOR_CARET       = { 230, 230, 235, 255 };

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

fn EditorMetrics metrics_for_font(RLFont font, float font_size)
{
	EditorMetrics metrics;
	RLVector2 size = rl::measure_text_ex(font, "M", font_size, 0.0f);
	metrics.char_width = size[0];
	metrics.line_height = font_size * 1.25f;
	metrics.padding_x = 8.0f;
	metrics.padding_y = 6.0f;
	return metrics;
}

fn Rect inner_rect(Rect card_rect, EditorMetrics metrics)
{
	return {
		.x = card_rect.x + metrics.padding_x,
		.y = card_rect.y + card::CARD_TITLE_HEIGHT + metrics.padding_y,
		.width = card_rect.width - metrics.padding_x * 2.0f,
		.height = card_rect.height - card::CARD_TITLE_HEIGHT - metrics.padding_y * 2.0f,
	};
}

fn void ensure_buffer(FileCard* card, Allocator allocator)
{
	if (card.buffer) return;
	PieceTable* buffer = alloc::new(allocator, PieceTable);
	(void)buffer.init_from_file(allocator, (String)card.path);
	card.buffer = buffer;
}

fn Rect world_rect_to_screen(Rect area, RLCamera2D camera)
{
	RLVector2 tl = rl::get_world_to_screen2d({ area.x, area.y }, camera);
	RLVector2 br = rl::get_world_to_screen2d({ area.x + area.width, area.y + area.height }, camera);
	return { .x = tl[0], .y = tl[1], .width = br[0] - tl[0], .height = br[1] - tl[1] };
}

fn void apply_scissor(Rect area, RLCamera2D camera)
{
	Rect screen = world_rect_to_screen(area, camera);
	rl::begin_scissor_mode((int)screen.x, (int)screen.y, (int)screen.width, (int)screen.height);
}

fn float max_scroll(usz line_count, EditorMetrics metrics, float area_height)
{
	float content = (float)line_count * metrics.line_height + metrics.padding_y * 2.0f;
	float max     = content - area_height;
	return max > 0.0f ? max : 0.0f;
}

fn void draw_text(
	PieceTable* table,
	Rect area,
	float scroll_y,
	EditorMetrics metrics,
	RLCamera2D camera,
	RLFont font,
	float font_size,
	RLColor color
)
{
	if (table.length() == 0 || metrics.line_height <= 0.0f) return;
	apply_scissor(area, camera);
	@pool()
	{
		VisibleRange range = visible_lines(table.line_count(), scroll_y, area.height, metrics.line_height);
		for (usz line = range.first; line < range.last; line++)
		{
			String text = line_text(table, line, tmem);
			if (text.len == 0) continue;
			float y = area.y + (float)line * metrics.line_height - scroll_y;
			rl::draw_text_ex(font, (ZString)text.ptr, { area.x, y }, font_size, 0.0f, color);
		}
	};
	rl::end_scissor_mode();
}

fn float placeholder_bar_width(int line_index, float max_width, float char_width)
{
	if (char_width <= 0.0f) return max_width;
	int columns = (int)(max_width / char_width);
	if (columns <= 1) return max_width;
	int[5] pattern = { 32, 20, 28, 12, 24 };
	int target     = pattern[line_index % 5];
	if (target > columns) target = columns;
	return (float)target * char_width;
}

fn void draw_placeholder(Rect area, EditorMetrics metrics, RLCamera2D camera, RLColor color)
{
	if (metrics.line_height <= 0.0f) return;
	apply_scissor(area, camera);
	int lines = (int)(area.height / metrics.line_height);
	for (int i = 0; i < lines; i++)
	{
		float y     = area.y + (float)i * metrics.line_height + metrics.line_height * 0.25f;
		float width = placeholder_bar_width(i, area.width, metrics.char_width);
		rl::draw_rectangle((int)area.x, (int)y, (int)width, (int)(metrics.line_height * 0.5f), color);
	}
	rl::end_scissor_mode();
}
fn int utf8_encode(int codepoint, char* out)
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

fn usz cursor_prev(PieceTable* table, usz cursor)
{
	if (cursor == 0) return 0;
	return table.prev_boundary(cursor - 1);
}

fn usz cursor_next(PieceTable* table, usz cursor)
{
	if (cursor >= table.length()) return table.length();
	return table.next_boundary(cursor);
}

fn usz cursor_home(PieceTable* table, usz cursor)
{
	return table.line_start(table.line_of(cursor));
}

fn usz cursor_end(PieceTable* table, usz cursor)
{
	usz line = table.line_of(cursor);
	return table.line_start(line) + line_length_bytes(table, line);
}

fn usz offset_for_column(PieceTable* table, usz line, usz column)
{
	usz start = table.line_start(line);
	usz end   = start + line_length_bytes(table, line);
	usz pos   = start;
	usz col   = 0;
	while (col < column && pos < end)
	{
		pos = table.next_boundary(pos);
		col++;
	}
	return pos;
}

fn usz cursor_up(PieceTable* table, usz cursor, usz desired_column, usz* out_column)
{
	usz line = table.line_of(cursor);
	if (line == 0)
	{
		*out_column = column_for_offset(table, line, cursor);
		return cursor;
	}
	usz target = offset_for_column(table, line - 1, desired_column);
	*out_column = column_for_offset(table, line - 1, target);
	return target;
}

fn usz cursor_down(PieceTable* table, usz cursor, usz desired_column, usz* out_column)
{
	usz line       = table.line_of(cursor);
	usz line_count = table.line_count();
	if (line + 1 >= line_count)
	{
		*out_column = column_for_offset(table, line, cursor);
		return cursor;
	}
	usz target = offset_for_column(table, line + 1, desired_column);
	*out_column = column_for_offset(table, line + 1, target);
	return target;
}

fn usz insert_text(PieceTable* table, usz cursor, String text)
{
	(void)table.insert(cursor, text);
	return cursor + text.len;
}

fn usz backspace(PieceTable* table, usz cursor)
{
	if (cursor == 0) return 0;
	usz prev = cursor_prev(table, cursor);
	(void)table.delete(prev, cursor - prev);
	return prev;
}

fn usz delete_forward(PieceTable* table, usz cursor)
{
	if (cursor >= table.length()) return cursor;
	usz next = cursor_next(table, cursor);
	(void)table.delete(cursor, next - cursor);
	return cursor;
}

fn Rect caret_rect(PieceTable* table, Rect area, float scroll_y, EditorMetrics metrics, usz cursor)
{
	usz line    = table.line_of(cursor);
	usz column  = column_for_offset(table, line, cursor);
	float x     = area.x + (float)column * metrics.char_width;
	float y     = area.y + (float)line * metrics.line_height - scroll_y;
	float width = metrics.char_width > 0.0f ? metrics.char_width : 1.0f;
	return { .x = x, .y = y, .width = width, .height = metrics.line_height };
}

fn float scroll_to_reveal(PieceTable* table, EditorMetrics metrics, float area_height, usz cursor, float current_scroll)
{
	usz line     = table.line_of(cursor);
	float top    = (float)line * metrics.line_height;
	float bottom = top + metrics.line_height;
	float scroll = current_scroll;
	if (top < scroll) scroll = top;
	if (bottom > scroll + area_height) scroll = bottom - area_height;
	if (scroll < 0.0f) scroll = 0.0f;
	return scroll;
}

fn void draw_caret(
	PieceTable* table,
	Rect area,
	float scroll_y,
	EditorMetrics metrics,
	RLCamera2D camera,
	usz cursor,
	RLColor color
)
{
	apply_scissor(area, camera);
	rl::draw_rectangle_rec(caret_rect(table, area, scroll_y, metrics, cursor), color);
	rl::end_scissor_mode();
}