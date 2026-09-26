module yun::findbar;

import raylib6::rl;
import std::collections::list;
import std::math;
import yun::commands;
import yun::editor;
import yun::find;
import yun::keymap;
import yun::text;
import yun::theme;
import yun::ui;

const int FIELD_MAX  = 64;
const int BAR_HEIGHT = 34;
const int ROW_HEIGHT = 24;
const int PADDING    = 6;

struct FindBar
{
	bool open;
	char[FIELD_MAX + 1] query;
	int query_len;
	char[FIELD_MAX + 1] replacement;
	int replace_len;
	find::FindField field;
	bool case_sensitive;
	bool whole_word;
	int current;
	int total;
	bool capped;
	bool needs_search;
	List{usz} starts;
	Allocator allocator;
	bool consumed;
}

fn void FindBar.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.starts.init(allocator);
	self.open = false;
	self.query_len = 0;
	self.query[0] = 0;
	self.replace_len = 0;
	self.replacement[0] = 0;
	self.field = find::FindField.QUERY;
	self.case_sensitive = false;
	self.whole_word = false;
	self.current = 0;
	self.total = 0;
	self.capped = false;
	self.needs_search = false;
	self.consumed = false;
}

fn void FindBar.open_for(&self, find::FindField field)
{
	self.open = true;
	self.field = field;
	self.needs_search = true;
}

fn void FindBar.close(&self)
{
	self.open = false;
	self.starts.clear();
	self.total = 0;
	self.current = 0;
}

fn String FindBar.query_view(&self)
{
	return (String)self.query[0:self.query_len];
}

fn String FindBar.replace_view(&self)
{
	return (String)self.replacement[0:self.replace_len];
}

fn bool FindBar.append_codepoint(&self, int codepoint)
{
	if (codepoint < 32 || codepoint > 126) return false;
	if (self.field == find::FindField.QUERY)
	{
		if (self.query_len >= FIELD_MAX) return false;
		self.query[self.query_len] = (char)codepoint;
		self.query_len++;
		self.query[self.query_len] = 0;
		self.needs_search = true;
	}
	else
	{
		if (self.replace_len >= FIELD_MAX) return false;
		self.replacement[self.replace_len] = (char)codepoint;
		self.replace_len++;
		self.replacement[self.replace_len] = 0;
	}
	return true;
}

fn void FindBar.backspace(&self)
{
	if (self.field == find::FindField.QUERY)
	{
		if (self.query_len == 0) return;
		self.query_len--;
		self.query[self.query_len] = 0;
		self.needs_search = true;
	}
	else
	{
		if (self.replace_len == 0) return;
		self.replace_len--;
		self.replacement[self.replace_len] = 0;
	}
}

fn void FindBar.cycle_field(&self)
{
	self.field = self.field == find::FindField.QUERY ? find::FindField.REPLACE : find::FindField.QUERY;
}

fn void FindBar.research(&self, PieceTable* table)
{
	usz count = find::collect_matches(
		table,
		self.query_view(),
		self.case_sensitive,
		self.whole_word,
		find::MATCH_COUNT_CAP,
		&self.starts
	);
	self.total = (int)count;
	self.capped = count >= find::MATCH_COUNT_CAP;
	if (self.current >= self.total) self.current = self.total - 1;
	if (self.current < 0) self.current = 0;
	self.needs_search = false;
}

fn usz FindBar.current_start(&self)
{
	if (self.current < 0 || self.current >= (int)self.starts.len()) return 0;
	return self.starts[self.current];
}

fn bool FindBar.move_next(&self)
{
	if (self.total == 0) return false;
	self.current++;
	if (self.current >= self.total) self.current = 0;
	return true;
}

fn bool FindBar.move_prev(&self)
{
	if (self.total == 0) return false;
	self.current--;
	if (self.current < 0) self.current = self.total - 1;
	return true;
}

fn void FindBar.mark_dirty(&self)
{
	self.needs_search = true;
}

fn bool FindBar.replace_current(&self, PieceTable* table, History* history, double now)
{
	if (self.total == 0 || self.needs_search) return false;
	usz start = self.current_start();
	find::replace_at(table, history, start, self.query_view().len, self.replace_view(), now);
	self.needs_search = true;
	return true;
}

fn usz FindBar.replace_all(&self, PieceTable* table, History* history, double now)
{
	if (self.query_len == 0) return 0;
	usz replaced = find::replace_all(
		table,
		history,
		self.query_view(),
		self.replace_view(),
		self.case_sensitive,
		self.whole_word,
		find::MATCH_COUNT_CAP,
		now
	);
	self.needs_search = true;
	return replaced;
}

fn Rect FindBar.bar_rect(&self, Rect card_rect, EditorMetrics metrics)
{
	(void)metrics;
	return {
		.x = card_rect.x + 1.0f,
		.y = card_rect.y + 1.0f,
		.width = card_rect.width - 2.0f,
		.height = (float)ui::px(BAR_HEIGHT),
	};
}

fn int FindBar.update(
	&self,
	keymap::Keymap* keymap,
	PieceTable* table,
	History* history,
	bool content_changed,
	usz* out_reveal,
	bool* out_replaced,
	bool* out_jumped
)
{
	*out_reveal = 0;
	*out_replaced = false;
	*out_jumped = false;
	if (!self.open) return 0;
	self.consumed = false;
	if (content_changed) self.needs_search = true;

	bool ctrl  = rl::is_key_down(rl::RLKeyboardKey.LEFT_CONTROL) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_CONTROL);
	double now = rl::get_time();

	if (keymap.pressed((int)commands::CommandId.OVERLAY_CLOSE, commands::CTX_FIND))
	{
		self.consumed = true;
		self.close();
		return -1;
	}
	if (keymap.pressed((int)commands::CommandId.FIND_CYCLE_FIELD, commands::CTX_FIND))
	{
		self.consumed = true;
		self.cycle_field();
	}

	if (keymap.pressed((int)commands::CommandId.FIND_REPLACE, commands::CTX_FIND))
	{
		self.consumed = true;
		if (self.replace_current(table, history, now))
		{
			self.needs_search = true;
			*out_replaced = true;
		}
	}
	if (keymap.pressed((int)commands::CommandId.FIND_REPLACE_ALL, commands::CTX_FIND))
	{
		self.consumed = true;
		if (self.replace_all(table, history, now) > 0) *out_replaced = true;
	}
	if (keymap.pressed((int)commands::CommandId.FIND_PREV, commands::CTX_FIND))
	{
		self.consumed = true;
		if (self.move_prev())
		{
			*out_reveal = self.current_start();
			*out_jumped = true;
		}
	}
	if (keymap.pressed((int)commands::CommandId.FIND_NEXT, commands::CTX_FIND))
	{
		self.consumed = true;
		if (self.move_next())
		{
			*out_reveal = self.current_start();
			*out_jumped = true;
		}
	}

	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		self.backspace();
	}
	if (!ctrl)
	{
		int codepoint = rl::get_char_pressed();
		while (codepoint != 0)
		{
			self.append_codepoint(codepoint);
			codepoint = rl::get_char_pressed();
		}
	}

	if (self.needs_search) self.research(table);
	if (*out_reveal == 0 && self.total > 0) *out_reveal = self.current_start();
	return 1;
}

fn void draw_field(RLFont font, Rect field, String text, bool active)
{
	rl::draw_rectangle_rec(field, theme::current().panel_field);
	rl::draw_rectangle_lines_ex(field, 1.0f, active ? theme::current().panel_border : theme::current().findbar_chip);
	if (text.len > 0)
	{
		@pool()
		{
			rl::draw_text_ex(
				font,
				text.zstr_tcopy(),
				{ field.x + (float)ui::px(4), field.y + (float)ui::px(3) },
				(float)ui::px(15),
				0.0f,
				theme::current()
				.panel_text);
		};
	}
	if (active)
	{
		@pool()
		{
			float width = text.len > 0 ? rl::measure_text_ex(font, text.zstr_tcopy(), (float)ui::px(15), 0.0f)[0]
				: 0.0f;
			rl::draw_rectangle(
				(int)(field.x + (float)ui::px(5) + width),
				(int)(field.y + (float)ui::px(3)),
				2,
				ui::px(16),
				theme::current()
				.panel_caret);
		};
	}
}

fn void draw_chip(RLFont font, Rect chip, String label, bool toggled)
{
	rl::draw_rectangle_rec(chip, toggled ? theme::current().panel_selected : theme::current().findbar_chip);
	@pool()
	{
		ZString z      = label.zstr_tcopy();
		RLVector2 size = rl::measure_text_ex(font, z, (float)ui::px(13), 0.0f);
		rl::draw_text_ex(
			font,
			z,
			{ chip.x + (chip.width - size[0]) / 2.0f, chip.y + (chip.height - size[1]) / 2.0f },
			(float)ui::px(13),
			0.0f,
			theme::current()
			.panel_text);
	};
}

fn void FindBar.draw_matches(
	&self,
	Rect card_rect,
	PieceTable* table,
	float scroll_y,
	float scroll_x,
	EditorMetrics metrics,
	RLCamera2D camera
)
{
	if (!self.open || self.total == 0) return;
	Rect text = editor::text_rect(card_rect, metrics, table.line_count());
	editor::draw_matches(
		table,
		text,
		scroll_y,
		scroll_x,
		metrics,
		camera,
		self.starts.entries[0:self.starts.len()],
		(usz)self.total,
		self.query_view()
		.len, (usz)self.current, theme::current().editor_match, theme::current().editor_match_current);
}

fn void FindBar.draw(&self, Rect card_rect, EditorMetrics metrics, RLFont font, keymap::Keymap* keymap)
{
	if (!self.open) return;

	Rect bar = self.bar_rect(card_rect, metrics);
	rl::draw_rectangle_rec(bar, theme::current().panel_bg_alt);
	rl::draw_line_ex({ bar.x, bar.y + bar.height }, { bar.x + bar.width, bar.y + bar.height }, 1.0f, theme::current()
		.panel_border);

	float x      = bar.x + (float)ui::px(PADDING);
	float y      = bar.y + (float)ui::px(PADDING) - (float)ui::px(2);
	float height = (float)ui::px(ROW_HEIGHT);

	Rect query_field = { .x = x, .y = y, .width = (float)ui::px(150), .height = height };
	draw_field(font, query_field, self.query_view(), self.field == find::FindField.QUERY);
	x += query_field.width + (float)ui::px(6);

	Rect replace_field = { .x = x, .y = y, .width = (float)ui::px(150), .height = height };
	draw_field(font, replace_field, self.replace_view(), self.field == find::FindField.REPLACE);
	x += replace_field.width + (float)ui::px(8);

	Rect word_chip = { .x = x, .y = y, .width = (float)ui::px(52), .height = height };
	draw_chip(font, word_chip, "Word", self.whole_word);
	x += word_chip.width + (float)ui::px(4);

	Rect case_chip = { .x = x, .y = y, .width = (float)ui::px(44), .height = height };
	draw_chip(font, case_chip, "Case", self.case_sensitive);
	x += case_chip.width + (float)ui::px(8);

	@pool()
	{
		String count = self.total > 0 ? string::format(
			tmem,
			"%d/%d%s",
			self.current + 1,
			self.total,
			self.capped ? "+" : ""
		)
			: "0/0";
		rl::draw_text_ex(
			font,
			(ZString)count.ptr,
			{ x, y + (float)ui::px(4) },
			(float)ui::px(14),
			0.0f,
			theme::current()
			.panel_dim);
	};

	(void)keymap;
}