module yun::completion;

import raylib6::rl;
import std::collections::list;
import std::core::mem::alloc;
import std::math;
import yun::commands;
import yun::editor;
import yun::lsp;
import yun::text;
import yun::theme;
import yun::ui;

const int VISIBLE_ROWS   = 12;
const int ROW_HEIGHT     = 20;
const int MAX_CANDIDATES = 512;
const int MAX_FILTERED   = 200;
const int KIND_WIDTH     = 44;
const float PANEL_WIDTH  = 360.0f;

struct Completion
{
	Allocator allocator;
	bool open;
	bool waiting;
	String path;
	usz start;
	String prefix;
	List{lsp::CompletionItem} items;
	List{int} order;
	List{int} scores;
	bool incomplete;
	int selected;
	int scroll;
}

Completion* active_completion;

fn void Completion.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.open = false;
	self.waiting = false;
	self.path = "";
	self.start = 0;
	self.prefix = "";
	self.items.init(allocator);
	self.order.init(allocator);
	self.scores.init(allocator);
	self.incomplete = false;
	self.selected = 0;
	self.scroll = 0;
}

fn void Completion.clear_items(&self)
{
	for (sz i = 0; i < self.items.len(); i++)
	{
		lsp::CompletionItem item = self.items[i];
		if (item.label.len) item.label.free(self.allocator);
		if (item.filter_text.len) item.filter_text.free(self.allocator);
		if (item.sort_text.len) item.sort_text.free(self.allocator);
		if (item.insert_text.len) item.insert_text.free(self.allocator);
		if (item.detail.len) item.detail.free(self.allocator);
	}
	self.items.clear();
}

fn bool is_word_char(char c)
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

fn usz prefix_start(PieceTable* table, usz cursor)
{
	usz pos = cursor;
	while (pos > 0)
	{
		usz prev = table.prev_boundary(pos - 1);
		if (!is_word_char(table.byte_at(prev))) break;
		pos = prev;
	}
	return pos;
}

fn void Completion.free_prefix(&self)
{
	if (self.prefix.len) self.prefix.free(self.allocator);
	self.prefix = "";
}

fn void Completion.close(&self)
{
	self.open = false;
	self.waiting = false;
	self.free_prefix();
}

fn void Completion.refilter(&self, PieceTable* table, usz cursor)
{
	self.free_prefix();
	usz end = cursor;
	if (self.start > end) self.start = end;
	self.prefix = table.slice(self.start, end - self.start, self.allocator);

	self.order.clear();
	self.scores.clear();

	usz[64] positions;
	String needle = self.prefix;
	if (needle.len > 64) needle = needle[0:64];

	for (sz i = 0; i < self.items.len() && self.order.len() < MAX_CANDIDATES; i++)
	{
		int score = 0;
		if (needle.len > 0)
		{
			score = commands::fuzzy_match(self.items[i].filter_text, needle, positions[0:64]);
			if (score < 0) continue;
		}
		self.order.push((int)i);
		self.scores.push(score);
	}

	// Insertion sort by score descending (stable-ish, tiny sets).
	for (sz i = 1; i < self.order.len(); i++)
	{
		int order = self.order[i];
		int score = self.scores[i];
		sz j      = i;
		while (j > 0 && self.scores[j - 1] < score)
		{
			self.order[j] = self.order[j - 1];
			self.scores[j] = self.scores[j - 1];
			j--;
		}
		self.order[j] = order;
		self.scores[j] = score;
	}

	while (self.order.len() > MAX_FILTERED)
	{
		self.order.remove_at(self.order.len() - 1);
		self.scores.remove_at(self.scores.len() - 1);
	}

	if (self.selected >= (int)self.order.len()) self.selected = (int)self.order.len() - 1;
	if (self.selected < 0) self.selected = 0;
	self.clamp_scroll();
}

fn void Completion.clamp_scroll(&self)
{
	if (self.selected < self.scroll) self.scroll = self.selected;
	if (self.selected >= self.scroll + VISIBLE_ROWS) self.scroll = self.selected - VISIBLE_ROWS + 1;
	int max_scroll = (int)self.order.len() - VISIBLE_ROWS;
	if (max_scroll < 0) max_scroll = 0;
	if (self.scroll > max_scroll) self.scroll = max_scroll;
	if (self.scroll < 0) self.scroll = 0;
}

fn void Completion.move(&self, int delta)
{
	if (!self.open || self.order.len() == 0) return;
	self.selected += delta;
	if (self.selected < 0) self.selected = 0;
	if (self.selected >= (int)self.order.len()) self.selected = (int)self.order.len() - 1;
	self.clamp_scroll();
}

fn void Completion.request(&self, String path, PieceTable* table, usz cursor, int trigger_kind, String trigger_char)
{
	self.close();
	self.clear_items();
	self.items.free();
	self.items.init(self.allocator);

	self.start = prefix_start(table, cursor);
	self.path = path;
	self.waiting = true;
	if (!lsp::lsp_request_completion(path, table, cursor, trigger_kind, trigger_char))
	{
		self.waiting = false;
		self.open = false;
	}
}

fn void Completion.poll(&self, PieceTable* table, usz cursor)
{
	if (!self.waiting) return;
	List{lsp::CompletionItem} got = { };
	bool incomplete               = false;
	if (!lsp::lsp_take_completion(&got, &incomplete)) return;

	self.clear_items();
	self.items.free();
	self.items = got;
	self.incomplete = incomplete;
	self.waiting = false;
	self.refilter(table, cursor);
	self.selected = 0;
	self.scroll = 0;
	self.open = self.order.len() > 0;
}

fn usz Completion.accept(&self, PieceTable* table, History* history, usz cursor, double now)
{
	if (!self.open || self.order.len() == 0 || !history) return cursor;
	lsp::CompletionItem item = self.items[self.order[self.selected]];

	usz replace_start = self.start;
	usz replace_end   = cursor;
	if (item.has_text_edit)
	{
		replace_start = lsp::offset_from_position(table, item.edit_start_line, item.edit_start_character);
		replace_end = lsp::offset_from_position(table, item.edit_end_line, item.edit_end_character);
	}
	if (replace_end < replace_start) replace_end = replace_start;

	usz result = history.replace(table, replace_start, replace_end - replace_start, item.insert_text, now);
	self.close();
	return result;
}

fn String kind_label(int kind)
{
	switch (kind)
	{
		case 2:
			return "method";
		case 3:
			return "fn";
		case 4:
			return "ctor";
		case 5:
			return "field";
		case 6:
			return "var";
		case 7:
			return "class";
		case 8:
			return "iface";
		case 9:
			return "mod";
		case 10:
			return "prop";
		case 11:
			return "unit";
		case 12:
			return "value";
		case 13:
			return "enum";
		case 14:
			return "kw";
		case 15:
			return "snip";
		case 16:
			return "color";
		case 17:
			return "file";
		case 18:
			return "ref";
		case 19:
			return "folder";
		case 20:
			return "enum";
		case 21:
			return "const";
		case 22:
			return "struct";
		case 23:
			return "event";
		case 24:
			return "op";
		case 25:
			return "type";
		default:
			return "text";
	}
}

fn void draw_text(RLFont font, String text, float x, float y, float size, RLColor color)
{
	if (text.len == 0) return;
	@pool()
	{
		rl::draw_text_ex(font, text.zstr_tcopy(), { x, y }, size, 0.0f, color);
	};
}

fn void Completion.draw(
	&self,
	RLFont font,
	EditorMetrics metrics,
	RLCamera2D camera,
	PieceTable* table,
	Rect card_rect,
	float scroll_y,
	float scroll_x,
	usz cursor
)
{
	if (!self.open || self.order.len() == 0) return;

	Rect text      = editor::text_rect(card_rect, metrics, table.line_count());
	Rect caret     = editor::caret_rect(table, text, scroll_y, scroll_x, metrics, cursor);
	Rect caret_scr = editor::world_rect_to_screen(caret, camera);

	int rows = (int)self.order.len();
	if (rows > VISIBLE_ROWS) rows = VISIBLE_ROWS;
	float height = (float)rows * (float)ui::px(ROW_HEIGHT) + (float)ui::px(6);
	Rect panel = {
		.x = caret_scr.x,
		.y = caret_scr.y + caret_scr.height,
		.width = ui::pxf(PANEL_WIDTH),
		.height = height,
	};
	if (panel.x + panel.width > (float)rl::get_screen_width())
	{
		panel.x = (float)rl::get_screen_width() - panel.width - (float)ui::px(4);
	}
	if (panel.y + panel.height > (float)rl::get_screen_height())
	{
		panel.y = caret_scr.y - panel.height - (float)ui::px(2);
	}
	if (panel.x < (float)ui::px(4)) panel.x = (float)ui::px(4);
	if (panel.y < (float)ui::px(4)) panel.y = (float)ui::px(4);

	rl::draw_rectangle_rec(panel, theme::current().panel_bg);
	rl::draw_rectangle_lines_ex(panel, 1.0f, theme::current().panel_border);

	rl::begin_scissor_mode((int)panel.x + 2, (int)panel.y + 2, (int)panel.width - 4, (int)panel.height - 4);
	for (int slot = 0; slot < VISIBLE_ROWS; slot++)
	{
		int index = self.scroll + slot;
		if (index >= (int)self.order.len()) break;
		lsp::CompletionItem item = self.items[self.order[index]];
		float row_y              = panel.y + (float)ui::px(3) + (float)slot * (float)ui::px(ROW_HEIGHT);
		if (index == self.selected)
		{
			rl::draw_rectangle((int)panel.x + 2, (int)row_y, (int)panel.width - 4, ui::px(ROW_HEIGHT), theme::current()
				.panel_selected);
		}
		draw_text(
			font,
			kind_label(item.kind),
			panel.x + (float)ui::px(6),
			row_y + (float)ui::px(2),
			(float)ui::px(13),
			theme::current()
			.panel_header);
		draw_text(
			font,
			item.label,
			panel.x + (float)ui::px(KIND_WIDTH),
			row_y + (float)ui::px(1),
			(float)ui::px(15),
			theme::current()
			.panel_text);
		if (item.detail.len > 0)
		{
			@pool()
			{
				String detail = string::format(tmem, "  %s", item.detail);
				draw_text(
					font,
					detail,
					panel.x + (float)ui::px(KIND_WIDTH) + (float)ui::px(120),
					row_y + (float)ui::px(3),
					(float)ui::px(13),
					theme::current()
					.panel_dim);
			};
		}
	}
	rl::end_scissor_mode();
}

fn void completion_init(Allocator allocator)
{
	active_completion = alloc::new(allocator, Completion);
	active_completion.init(allocator);
}

fn void completion_poll(PieceTable* table, usz cursor)
{
	if (active_completion) active_completion.poll(table, cursor);
}

fn bool completion_is_open()
{
	return active_completion && active_completion.open;
}

fn void completion_close()
{
	if (active_completion) active_completion.close();
}

fn void completion_move(int delta)
{
	if (active_completion) active_completion.move(delta);
}

fn void completion_refilter(PieceTable* table, usz cursor)
{
	if (!active_completion) return;
	active_completion.refilter(table, cursor);
	active_completion.open = active_completion.order.len() > 0;
}

fn usz completion_accept(PieceTable* table, History* history, usz cursor, double now)
{
	if (!active_completion) return cursor;
	return active_completion.accept(table, history, cursor, now);
}

fn void completion_request(String path, PieceTable* table, usz cursor, int trigger_kind, String trigger_char)
{
	if (active_completion) active_completion.request(path, table, cursor, trigger_kind, trigger_char);
}

fn void completion_draw(
	RLFont font,
	EditorMetrics metrics,
	RLCamera2D camera,
	PieceTable* table,
	Rect card_rect,
	float scroll_y,
	float scroll_x,
	usz cursor
)
{
	if (active_completion)
	{
		active_completion.draw(font, metrics, camera, table, card_rect, scroll_y, scroll_x, cursor);
	}
}