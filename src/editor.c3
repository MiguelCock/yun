module yun::editor;

import libc;
import raylib6::rl;
import std::core::mem::alloc;
import std::io::os;
import std::math;
import yun::card;
import yun::text;

const RLColor EDITOR_TEXT         = { 210, 214, 222, 255 };
const RLColor EDITOR_PLACEHOLDER  = { 70, 76, 90, 255 };
const RLColor EDITOR_CARET        = { 230, 230, 235, 255 };
const RLColor EDITOR_GUTTER_BG    = { 24, 26, 32, 255 };
const RLColor EDITOR_GUTTER_TEXT  = { 120, 132, 150, 255 };
const RLColor EDITOR_CURRENT_LINE = { 255, 255, 255, 18 };
const RLColor EDITOR_SCROLLBAR    = { 90, 100, 120, 200 };
const RLColor EDITOR_HANDLE       = { 120, 160, 240, 220 };
const int SCROLL_MARGIN_LINES     = 1;

fn float min_card_width(EditorMetrics metrics)
{
	return (80.0f + 6.0f) * metrics.char_width + metrics.padding_x * 2.0f;
}

fn float min_card_height(EditorMetrics metrics)
{
	return 30.0f * metrics.line_height + card::CARD_TITLE_HEIGHT + metrics.padding_y * 2.0f;
}

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
	if (!card.buffer)
	{
		PieceTable* buffer = alloc::new(allocator, PieceTable);
		(void)buffer.init_from_file(allocator, (String)card.path);
		card.buffer = buffer;
	}
	if (!card.history)
	{
		History* history = alloc::new(allocator, History);
		history.init(allocator);
		card.history = history;
	}
	stamp_file(card);
}

fn void stamp_file(FileCard* card)
{
	Time_t? mtime = os::native_get_modified_time((String)card.path);
	long? size    = os::native_file_size((String)card.path);
	if (catch excuse = mtime)
	{
		card.missing = true;
		return;
	}
	if (catch excuse = size)
	{
		card.missing = true;
		return;
	}
	card.mtime = (long)mtime;
	card.size = size;
	card.missing = false;
}

fn bool file_changed(FileCard* card)
{
	Time_t? mtime = os::native_get_modified_time((String)card.path);
	long? size    = os::native_file_size((String)card.path);
	if (catch excuse = mtime) return true;
	if (catch excuse = size) return true;
	return (long)mtime != card.mtime || size != card.size;
}

fn void reload_buffer(FileCard* card, Allocator allocator)
{
	if (!card.buffer) return;
	card.buffer.destroy();
	(void)card.buffer.init_from_file(allocator, (String)card.path);
	if (card.history) card.history.reset();
	card.cursor = 0;
	card.preferred_column = 0;
	card.scroll = 0.0f;
	card.dirty = false;
	stamp_file(card);
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
	float margin = (float)SCROLL_MARGIN_LINES * metrics.line_height;
	float scroll = current_scroll;
	if (top < scroll + margin) scroll = top - margin;
	if (bottom > scroll + area_height - margin) scroll = bottom - area_height + margin;
	if (scroll < 0.0f) scroll = 0.0f;
	float max = max_scroll(table.line_count(), metrics, area_height);
	if (scroll > max) scroll = max;
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
fn Rect gutter_rect(Rect card_rect, EditorMetrics metrics, usz line_count)
{
	Rect inner = inner_rect(card_rect, metrics);
	inner.width = gutter_width(line_count, metrics);
	return inner;
}

fn Rect text_rect(Rect card_rect, EditorMetrics metrics, usz line_count)
{
	Rect inner   = inner_rect(card_rect, metrics);
	float gutter = gutter_width(line_count, metrics);
	inner.x += gutter;
	inner.width -= gutter;
	return inner;
}

fn Rect current_line_rect(PieceTable* table, Rect area, float scroll_y, EditorMetrics metrics, usz cursor)
{
	usz line = table.line_of(cursor);
	float y  = area.y + (float)line * metrics.line_height - scroll_y;
	return { .x = area.x, .y = y, .width = area.width, .height = metrics.line_height };
}

fn Rect scrollbar_thumb(Rect area, float content_height, float scroll_y)
{
	float width = 4.0f;
	if (content_height <= area.height || content_height <= 0.0f)
	{
		return { .x = area.x + area.width - width, .y = area.y, .width = width, .height = area.height };
	}

	float thumb_height = area.height * (area.height / content_height);
	if (thumb_height < 20.0f) thumb_height = 20.0f;

	float max_scroll = content_height - area.height;
	float t          = max_scroll > 0.0f ? scroll_y / max_scroll : 0.0f;
	if (t < 0.0f) t = 0.0f;
	if (t > 1.0f) t = 1.0f;

	float y = area.y + t * (area.height - thumb_height);
	return { .x = area.x + area.width - width, .y = y, .width = width, .height = thumb_height };
}

fn void draw_current_line(
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
	rl::draw_rectangle_rec(current_line_rect(table, area, scroll_y, metrics, cursor), color);
	rl::end_scissor_mode();
}

fn void draw_gutter(
	PieceTable* table,
	Rect area,
	float scroll_y,
	EditorMetrics metrics,
	RLCamera2D camera,
	RLFont font,
	float font_size,
	RLColor text_color,
	RLColor bg_color
)
{
	apply_scissor(area, camera);
	rl::draw_rectangle_rec(area, bg_color);
	@pool()
	{
		VisibleRange range = visible_lines(table.line_count(), scroll_y, area.height, metrics.line_height);
		for (usz line = range.first; line < range.last; line++)
		{
			String label   = string::format(tmem, "%d", (int)(line + 1));
			RLVector2 size = rl::measure_text_ex(font, (ZString)label.ptr, font_size, 0.0f);
			float x        = area.x + area.width - metrics.padding_x - size[0];
			float y        = area.y + (float)line * metrics.line_height - scroll_y;
			rl::draw_text_ex(font, (ZString)label.ptr, { x, y }, font_size, 0.0f, text_color);
		}
	};
	rl::end_scissor_mode();
}

fn void draw_scrollbar(Rect area, float content_height, float scroll_y, RLCamera2D camera, RLColor color)
{
	if (content_height <= area.height) return;
	apply_scissor(area, camera);
	rl::draw_rectangle_rec(scrollbar_thumb(area, content_height, scroll_y), color);
	rl::end_scissor_mode();
}