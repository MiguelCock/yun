module yun::editor;

import libc;
import raylib6::rl;
import std::collections::list;
import std::core::dstring;
import std::core::mem::alloc;
import std::io::os;
import std::math;
import yun::card;
import yun::highlight;
import yun::lsp;
import yun::text;
import yun::theme;
import yun::ui;

const int MAX_DIAGNOSTIC_SEGMENTS = 512;
const int FONT_SIZE_MIN           = 8;
const int FONT_SIZE_MAX           = 48;
const int FONT_SIZE_DEFAULT       = 16;

struct EditorSettings
{
	float line_height;
	float padding_x;
	float padding_y;
	int caret_blink_ms;
	int scroll_margin_lines;
	int wheel_scroll_lines;
	bool show_line_numbers;
	int indent_width;
	bool indent_spaces;
	bool auto_indent;
}

EditorSettings g_editor_settings = {
	.line_height = 1.25f,
	.padding_x = 8.0f,
	.padding_y = 6.0f,
	.caret_blink_ms = 500,
	.scroll_margin_lines = 1,
	.wheel_scroll_lines = 3,
	.show_line_numbers = true,
	.indent_width = 4,
	.indent_spaces = false,
	.auto_indent = true,
};

fn EditorSettings settings()
{
	return g_editor_settings;
}

fn void set_settings(EditorSettings value)
{
	g_editor_settings = value;
}

fn float min_card_width(EditorMetrics metrics)
{
	return (80.0f + 6.0f) * metrics.char_width + metrics.padding_x * 2.0f;
}

fn float min_card_height(EditorMetrics metrics)
{
	return 30.0f * metrics.line_height + ui::pxf(card::CARD_TITLE_HEIGHT) + metrics.padding_y * 2.0f;
}

struct EditorMetrics
{
	float char_width;
	float line_height;
	float padding_x;
	float padding_y;
	float font_size;
}

struct VisibleRange
{
	usz first;
	usz last;
}

enum CardRegion
{
	NONE,
	HANDLE,
	MARKER,
	CLOSE,
	TITLE,
	BODY,
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

fn int tab_columns()
{
	return g_editor_settings.indent_width > 0 ? g_editor_settings.indent_width : 1;
}

fn String expand_tabs(String text, int width, Allocator allocator)
{
	if (width < 1) width = 1;
	bool has_tab = false;
	for (usz i = 0; i < text.len; i++)
	{
		if (text[i] == '\t')
		{
			has_tab = true;
			break;
		}
	}
	if (!has_tab) return text.copy(allocator);
	DString out;
	out.init(allocator, (sz)(text.len + 8));
	for (usz i = 0; i < text.len; i++)
	{
		char c = text[i];
		if (c == '\t')
		{
			for (int s = 0; s < width; s++) out.append_char(' ');
		}
		else
		{
			out.append_char(c);
		}
	}
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
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
	int tabs   = tab_columns();
	while (pos < offset && pos < table.length())
	{
		if (table.byte_at(pos) == '\t')
		{
			column += (usz)tabs;
		}
		else
		{
			column++;
		}
		pos = table.next_boundary(pos);
	}
	return column;
}

fn usz offset_for_point(
	PieceTable* table,
	float local_x,
	float local_y,
	float scroll_y,
	float scroll_x,
	EditorMetrics metrics
)
{
	if (metrics.line_height <= 0.0f || metrics.char_width <= 0.0f) return 0;
	usz line_count = table.line_count();
	if (line_count == 0) return 0;

	float content_y = local_y + scroll_y - metrics.padding_y;
	sz line         = (sz)math::floor(content_y / metrics.line_height);
	if (line < 0) line = 0;
	if ((usz)line >= line_count) line = (sz)(line_count - 1);

	float content_x = local_x + scroll_x - metrics.padding_x;
	sz column       = (sz)math::round(content_x / metrics.char_width);
	if (column < 0) column = 0;

	usz start   = table.line_start((usz)line);
	usz max_col = column_for_offset(table, (usz)line, start + line_length_bytes(table, (usz)line));
	if ((usz)column > max_col) column = (sz)max_col;
	return offset_for_column(table, (usz)line, (usz)column);
}

fn void selection_range(usz anchor, usz cursor, usz* start, usz* end)
{
	if (anchor < cursor)
	{
		*start = anchor;
		*end = cursor;
	}
	else
	{
		*start = cursor;
		*end = anchor;
	}
}

fn bool has_selection(usz anchor, usz cursor)
{
	return anchor != cursor;
}

fn bool word_char(char c)
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

fn void word_range(PieceTable* table, usz offset, usz* start, usz* end)
{
	usz length = table.length();
	if (length == 0)
	{
		*start = 0;
		*end = 0;
		return;
	}
	if (offset > length) offset = length;

	usz s = offset;
	while (s > 0)
	{
		usz prev = table.prev_boundary(s - 1);
		if (!word_char(table.byte_at(prev))) break;
		s = prev;
	}
	usz e = offset;
	while (e < length)
	{
		if (!word_char(table.byte_at(e))) break;
		e = table.next_boundary(e);
	}
	if (s == e)
	{
		if (offset < length)
		{
			e = table.next_boundary(offset);
		}
		else if (offset > 0)
		{
			s = table.prev_boundary(offset);
		}
	}
	*start = s;
	*end = e;
}

fn float gutter_width(usz line_count, EditorMetrics metrics)
{
	if (!g_editor_settings.show_line_numbers) return 0.0f;
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
	metrics.line_height = font_size * g_editor_settings.line_height;
	metrics.padding_x = g_editor_settings.padding_x;
	metrics.padding_y = g_editor_settings.padding_y;
	metrics.font_size = font_size;
	return metrics;
}

fn String indent_unit(Allocator allocator, bool spaces, int width)
{
	if (!spaces) return "\t".copy(allocator);
	DString out;
	out.init(allocator, (usz)(width > 0 ? width : 1));
	for (int i = 0; i < width; i++) out.append_char(' ');
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn String newline_text(PieceTable* table, usz cursor, bool auto_indent, bool spaces, int width, Allocator allocator)
{
	DString out;
	out.init(allocator, 16);
	out.append_char('\n');
	if (auto_indent)
	{
		usz line       = table.line_of(cursor);
		usz start      = table.line_start(line);
		usz indent_end = start;
		while (indent_end < cursor)
		{
			char c = table.char_at(indent_end);
			if (c != ' ' && c != '\t') break;
			indent_end++;
		}
		for (usz i = start; i < indent_end; i++) out.append_char(table.char_at(i));

		bool brace = false;
		usz p      = cursor;
		while (p > 0)
		{
			char c = table.char_at(p - 1);
			if (c == ' ' || c == '\t')
			{
				p--;
				continue;
			}
			brace = c == '{';
			break;
		}
		if (brace)
		{
			if (spaces)
			{
				for (int i = 0; i < width; i++) out.append_char(' ');
			}
			else
			{
				out.append_char('\t');
			}
		}
	}
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn usz outdent_count(PieceTable* table, usz cursor, bool spaces, int width)
{
	usz line  = table.line_of(cursor);
	usz start = table.line_start(line);
	char c    = table.char_at(start);
	if (c == '\t') return 1;
	if (c != ' ') return 0;
	int count = 0;
	while (count < width && table.char_at(start + (usz)count) == ' ') count++;
	return (usz)count;
}

fn int clamp_font_size(int size)
{
	if (size < FONT_SIZE_MIN) return FONT_SIZE_MIN;
	if (size > FONT_SIZE_MAX) return FONT_SIZE_MAX;
	return size;
}

float g_font_size = (float)FONT_SIZE_DEFAULT;

fn void set_font_size(float size)
{
	g_font_size = size;
}

fn float text_scale()
{
	return g_font_size / (float)FONT_SIZE_DEFAULT;
}

fn Rect inner_rect(Rect card_rect, EditorMetrics metrics)
{
	return {
		.x = card_rect.x + metrics.padding_x,
		.y = card_rect.y + ui::pxf(card::CARD_TITLE_HEIGHT) + metrics.padding_y,
		.width = card_rect.width - metrics.padding_x * 2.0f,
		.height = card_rect.height - ui::pxf(card::CARD_TITLE_HEIGHT) - metrics.padding_y * 2.0f,
	};
}

fn CardRegion region_at(FileCard* card, RLVector2 world, EditorMetrics metrics, RLCamera2D camera)
{
	if (!card.contains(world)) return CardRegion.NONE;
	if (card.resize_handle_at(world, camera) >= 0) return CardRegion.HANDLE;
	if (card.close_marker_hit(world)) return CardRegion.CLOSE;
	if (card.marker_hit(world)) return CardRegion.MARKER;
	if (card.open && world[1] >= card.rect.y + ui::pxf(card::CARD_TITLE_HEIGHT)) return CardRegion.BODY;
	return CardRegion.TITLE;
}

fn void ensure_buffer(FileCard* card, Allocator allocator)
{
	bool created = false;
	if (!card.buffer)
	{
		PieceTable* buffer = alloc::new(allocator, PieceTable);
		(void)buffer.init_from_file(allocator, (String)card.path);
		card.buffer = buffer;
		created = true;
	}
	if (!card.history)
	{
		History* history = alloc::new(allocator, History);
		history.init(allocator);
		card.history = history;
	}
	if (!card.highlight && card.buffer)
	{
		card.highlight = highlight::create(allocator, card.buffer, (String)card.path);
	}
	if (created && card.buffer) lsp::lsp_did_open((String)card.path, card.buffer);
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

fn void destroy_buffer(FileCard* card, Allocator allocator)
{
	lsp::lsp_did_close((String)card.path);
	if (card.buffer)
	{
		card.buffer.destroy();
		alloc::free(allocator, card.buffer);
		card.buffer = null;
	}

	if (card.history)
	{
		card.history.free();
		alloc::free(allocator, card.history);
		card.history = null;
	}

	if (card.highlight)
	{
		highlight::destroy(card.highlight, allocator);
		card.highlight = null;
	}

	card.cursor = 0;
	card.selection_anchor = 0;
	card.preferred_column = 0;
	card.scroll = 0.0f;
	card.scroll_x = 0.0f;
	card.dirty = false;
}

fn bool unload_buffer(FileCard* card, Allocator allocator)
{
	if (!card.buffer) return false;
	if (card.dirty) return false;
	destroy_buffer(card, allocator);
	return true;
}

fn bool save_buffer(FileCard* card, Allocator allocator)
{
	if (!card.buffer) return false;
	if (!card.buffer.save_to_file((String)card.path, allocator)) return false;
	card.dirty = false;
	stamp_file(card);
	return true;
}

fn void reload_buffer(FileCard* card, Allocator allocator)
{
	if (!card.buffer) return;
	card.buffer.destroy();
	(void)card.buffer.init_from_file(allocator, (String)card.path);
	if (card.history) card.history.reset();
	if (card.highlight) card.highlight.mark_dirty();
	if (card.buffer) lsp::lsp_did_change((String)card.path, card.buffer);
	card.cursor = 0;
	card.selection_anchor = 0;
	card.preferred_column = 0;
	card.scroll = 0.0f;
	card.scroll_x = 0.0f;
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
	float scroll_x,
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
			String vis = expand_tabs(text, tab_columns(), tmem);
			float y    = area.y + (float)line * metrics.line_height - scroll_y;
			rl::draw_text_ex(font, vis.zstr_tcopy(), { area.x - scroll_x, y }, font_size, 0.0f, color);
		}
	};
	rl::end_scissor_mode();
}

fn void draw_text_highlighted(
	highlight::Highlighter* highlighter,
	PieceTable* table,
	Rect area,
	float scroll_y,
	float scroll_x,
	EditorMetrics metrics,
	RLCamera2D camera,
	RLFont font,
	float font_size,
	RLColor base
)
{
	if (!highlighter || table.length() == 0 || metrics.line_height <= 0.0f)
	{
		draw_text(table, area, scroll_y, scroll_x, metrics, camera, font, font_size, base);
		return;
	}

	highlighter.ensure_parsed();
	apply_scissor(area, camera);
	@pool()
	{
		VisibleRange range = visible_lines(table.line_count(), scroll_y, area.height, metrics.line_height);
		List{highlight::Span} runs;
		runs.init(tmem);
		for (usz line = range.first; line < range.last; line++)
		{
			usz line_start = table.line_start(line);
			usz len        = line_length_bytes(table, line);
			if (len == 0) continue;

			String text = table.slice(line_start, len, tmem);
			highlighter.runs_for_line(line_start, line_start + len, &runs);

			float y  = area.y + (float)line * metrics.line_height - scroll_y;
			int tabs = tab_columns();
			usz pos  = 0;
			usz col  = 0;
			foreach (highlight::Span run : runs)
			{
				usz start = run.start - line_start;
				usz end   = run.end - line_start;
				while (pos < start)
				{
					char c = text[pos];
					if (c == '\t')
					{
						col += (usz)tabs;
					}
					else if (((int)c & 0xC0) != 0x80)
					{
						col++;
					}
					pos++;
				}
				String span = text[start:end - start];
				String vis  = expand_tabs(span, tabs, tmem);
				rl::draw_text_ex(
					font,
					vis.zstr_tcopy(),
					{ area.x + (float)col * metrics.char_width - scroll_x, y },
					font_size,
					0.0f,
					highlight::role_color(run.role)
				);
			}
		}
		runs.free();
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
	int tabs  = tab_columns();
	while (pos < end)
	{
		if (col >= column) break;
		if (table.byte_at(pos) == '\t')
		{
			if (col + (usz)tabs > column) break;
			col += (usz)tabs;
		}
		else
		{
			col++;
		}
		pos = table.next_boundary(pos);
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

fn usz cursor_page(PieceTable* table, usz cursor, sz delta_lines, usz desired_column, usz* out_column)
{
	usz line       = table.line_of(cursor);
	usz line_count = table.line_count();
	sz target      = (sz)line + delta_lines;
	if (target < 0) target = 0;
	if ((usz)target >= line_count) target = (sz)(line_count - 1);
	usz offset = offset_for_column(table, (usz)target, desired_column);
	*out_column = column_for_offset(table, (usz)target, offset);
	return offset;
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

fn Rect caret_rect(PieceTable* table, Rect area, float scroll_y, float scroll_x, EditorMetrics metrics, usz cursor)
{
	usz line    = table.line_of(cursor);
	usz column  = column_for_offset(table, line, cursor);
	float x     = area.x + (float)column * metrics.char_width - scroll_x;
	float y     = area.y + (float)line * metrics.line_height - scroll_y;
	float width = metrics.char_width > 0.0f ? metrics.char_width : 1.0f;
	return { .x = x, .y = y, .width = width, .height = metrics.line_height };
}

fn Rect match_rect(
	PieceTable* table,
	Rect area,
	float scroll_y,
	float scroll_x,
	EditorMetrics metrics,
	usz start,
	usz end
)
{
	usz line        = table.line_of(start);
	usz col         = column_for_offset(table, line, start);
	usz line_end    = table.line_start(line) + line_length_bytes(table, line);
	usz end_clamped = end > line_end ? line_end : end;
	usz end_col     = end_clamped > start ? column_for_offset(table, line, end_clamped) : col;
	float x         = area.x + (float)col * metrics.char_width - scroll_x;
	float y         = area.y + (float)line * metrics.line_height - scroll_y;
	float width     = (float)(end_col - col) * metrics.char_width;
	if (width <= 0.0f) width = metrics.char_width;
	return { .x = x, .y = y, .width = width, .height = metrics.line_height };
}

fn void draw_matches(
	PieceTable* table,
	Rect area,
	float scroll_y,
	float scroll_x,
	EditorMetrics metrics,
	RLCamera2D camera,
	usz[] starts,
	usz count,
	usz query_len,
	usz current,
	RLColor normal,
	RLColor selected
)
{
	if (count == 0 || query_len == 0 || metrics.line_height <= 0.0f) return;
	apply_scissor(area, camera);
	VisibleRange range = visible_lines(table.line_count(), scroll_y, area.height, metrics.line_height);
	for (usz i = 0; i < count; i++)
	{
		usz start = starts[i];
		usz line  = table.line_of(start);
		if (line < range.first || line >= range.last) continue;
		Rect r = match_rect(table, area, scroll_y, scroll_x, metrics, start, start + query_len);
		rl::draw_rectangle_rec(r, i == current ? selected : normal);
	}
	rl::end_scissor_mode();
}

fn Rect selection_rect_for_line(
	usz start_col,
	usz end_col,
	usz line,
	Rect area,
	float scroll_y,
	float scroll_x,
	EditorMetrics metrics
)
{
	float x = area.x + (float)start_col * metrics.char_width - scroll_x;
	float w = (float)(end_col - start_col) * metrics.char_width;
	float y = area.y + (float)line * metrics.line_height - scroll_y;
	if (w < metrics.char_width) w = metrics.char_width;
	return { .x = x, .y = y, .width = w, .height = metrics.line_height };
}

fn void draw_selection(
	PieceTable* table,
	Rect area,
	float scroll_y,
	float scroll_x,
	EditorMetrics metrics,
	RLCamera2D camera,
	usz start,
	usz end,
	RLColor color
)
{
	if (start >= end || metrics.line_height <= 0.0f) return;
	apply_scissor(area, camera);
	usz first_line     = table.line_of(start);
	usz last_line      = table.line_of(end);
	VisibleRange range = visible_lines(table.line_count(), scroll_y, area.height, metrics.line_height);
	for (usz line = first_line; line <= last_line; line++)
	{
		if (line < range.first || line >= range.last) continue;
		usz line_start = table.line_start(line);
		usz line_end   = line_start + line_length_bytes(table, line);
		usz s          = start > line_start ? start : line_start;
		usz e          = end < line_end ? end : line_end;
		usz start_col  = column_for_offset(table, line, s);
		usz end_col    = column_for_offset(table, line, e);
		Rect r         = selection_rect_for_line(start_col, end_col, line, area, scroll_y, scroll_x, metrics);
		if (end > line_end) r.width = area.x + area.width - r.x;
		rl::draw_rectangle_rec(r, color);
	}
	rl::end_scissor_mode();
}

fn void diagnostic_offsets(PieceTable* table, lsp::LspDiagnostic diag, usz* start, usz* end)
{
	*start = lsp::offset_from_position(table, diag.start_line, diag.start_character);
	*end = lsp::offset_from_position(table, diag.end_line, diag.end_character);
	if (*end < *start) *end = *start;
}

fn bool diagnostic_contains(PieceTable* table, lsp::LspDiagnostic diag, usz offset)
{
	usz start = 0;
	usz end   = 0;
	diagnostic_offsets(table, diag, &start, &end);
	if (end == start) end = start + 1;
	return offset >= start && offset < end;
}

fn RLColor diagnostic_color(int severity)
{
	switch (severity)
	{
		case lsp::DIAGNOSTIC_ERROR:
			return theme::current().diag_error;
		case lsp::DIAGNOSTIC_WARNING:
			return theme::current().diag_warning;
		case lsp::DIAGNOSTIC_INFO:
			return theme::current().diag_info;
		default:
			return theme::current().diag_hint;
	}
}

fn void draw_squiggle(float x0, float x1, float y, float zoom, RLColor color)
{
	if (x1 <= x0) return;
	float amplitude = 2.0f / zoom;
	float step      = 4.0f / zoom;
	float thickness = 1.0f / zoom;
	float x         = x0;
	bool up         = true;
	while (x < x1)
	{
		float next = x + step;
		if (next > x1) next = x1;
		float ay = y + (up ? -amplitude : amplitude);
		float by = y + (up ? amplitude : -amplitude);
		rl::draw_line_ex({ x, ay }, { next, by }, thickness, color);
		x = next;
		up = !up;
	}
}

fn void draw_diagnostics(
	PieceTable* table,
	Rect area,
	float scroll_y,
	float scroll_x,
	EditorMetrics metrics,
	RLCamera2D camera,
	lsp::LspDiagnostic[] diags
)
{
	if (diags.len == 0 || metrics.line_height <= 0.0f || metrics.char_width <= 0.0f) return;
	apply_scissor(area, camera);
	VisibleRange range = visible_lines(table.line_count(), scroll_y, area.height, metrics.line_height);
	int segments       = 0;
	for (usz i = 0; i < diags.len && segments < MAX_DIAGNOSTIC_SEGMENTS; i++)
	{
		usz start = 0;
		usz end   = 0;
		diagnostic_offsets(table, diags[i], &start, &end);
		usz first_line = table.line_of(start);
		usz last_line  = table.line_of(end);
		for (usz line = first_line; line <= last_line && segments < MAX_DIAGNOSTIC_SEGMENTS; line++)
		{
			if (line < range.first || line >= range.last) continue;
			usz line_start = table.line_start(line);
			usz line_end   = line_start + line_length_bytes(table, line);
			usz s          = start > line_start ? start : line_start;
			usz e          = end < line_end ? end : line_end;
			usz start_col  = column_for_offset(table, line, s);
			usz end_col    = column_for_offset(table, line, e);
			float x0       = area.x + (float)start_col * metrics.char_width - scroll_x;
			float x1       = area.x + (float)end_col * metrics.char_width - scroll_x;
			if (e >= line_end || end_col <= start_col) x1 = x0 + metrics.char_width;
			if (x1 < area.x || x0 > area.x + area.width) continue;
			if (x0 < area.x) x0 = area.x;
			if (x1 > area.x + area.width) x1 = area.x + area.width;
			float y = area.y + (float)line * metrics.line_height - scroll_y + metrics.line_height - 2.0f;
			draw_squiggle(x0, x1, y, camera.zoom, diagnostic_color(diags[i].severity));
			segments++;
		}
	}
	rl::end_scissor_mode();
}

fn float scroll_to_reveal(PieceTable* table, EditorMetrics metrics, float area_height, usz cursor, float current_scroll)
{
	usz line     = table.line_of(cursor);
	float top    = (float)line * metrics.line_height;
	float bottom = top + metrics.line_height;
	float margin = (float)g_editor_settings.scroll_margin_lines * metrics.line_height;
	float scroll = current_scroll;
	if (top < scroll + margin) scroll = top - margin;
	if (bottom > scroll + area_height - margin) scroll = bottom - area_height + margin;
	if (scroll < 0.0f) scroll = 0.0f;
	float max = max_scroll(table.line_count(), metrics, area_height);
	if (scroll > max) scroll = max;
	return scroll;
}

fn float scroll_x_to_reveal(
	PieceTable* table,
	EditorMetrics metrics,
	float area_width,
	usz cursor,
	float current_scroll_x
)
{
	usz line     = table.line_of(cursor);
	usz column   = column_for_offset(table, line, cursor);
	float left   = (float)column * metrics.char_width;
	float right  = left + metrics.char_width;
	float margin = metrics.char_width * 4.0f;
	float scroll = current_scroll_x;
	if (left < scroll + margin) scroll = left - margin;
	if (right > scroll + area_width - margin) scroll = right - area_width + margin;
	if (scroll < 0.0f) scroll = 0.0f;
	return scroll;
}

fn void draw_caret(
	PieceTable* table,
	Rect area,
	float scroll_y,
	float scroll_x,
	EditorMetrics metrics,
	RLCamera2D camera,
	usz cursor,
	RLColor color
)
{
	apply_scissor(area, camera);
	rl::draw_rectangle_rec(caret_rect(table, area, scroll_y, scroll_x, metrics, cursor), color);
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
	if (!g_editor_settings.show_line_numbers) return;
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