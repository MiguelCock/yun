module yun::settings_panel;

import raylib6::rl;
import std::collections::list;
import std::core::dstring;
import std::math;
import yun::commands;
import yun::config;
import yun::keymap;
import yun::notify;
import yun::settings;
import yun::theme;
import yun::topbar;

const int PANEL_WIDTH      = 780;
const int ROW_HEIGHT       = 38;
const int HEADER_HEIGHT    = 32;
const int PADDING          = 12;
const int TITLE_HEIGHT     = 46;
const int FIELD_HEIGHT     = 36;
const int FOOTER_HEIGHT    = 64;
const int MAX_VISIBLE_ROWS = 10;
const int QUERY_MAX        = 64;
const int EDIT_MAX         = 128;

struct Row
{
	settings::SettingId id;
	bool header;
	String section;
}

struct Panel
{
	bool open;
	settings::SettingLayer scope;
	char[QUERY_MAX + 1] query;
	int query_len;
	List{Row} rows;
	Allocator allocator;
	int selected;
	int scroll;
	bool editing;
	char[EDIT_MAX + 1] edit_buf;
	int edit_len;
	settings::SettingId edit_id;
	bool consumed;
}

fn bool matches(String section, String label, String key, String description, String query)
{
	if (query.len == 0) return true;
	usz[QUERY_MAX] positions;
	if (commands::fuzzy_match(label, query, positions[0:QUERY_MAX]) >= 0) return true;
	if (commands::fuzzy_match(key, query, positions[0:QUERY_MAX]) >= 0) return true;
	if (commands::fuzzy_match(section, query, positions[0:QUERY_MAX]) >= 0) return true;
	if (commands::fuzzy_match(description, query, positions[0:QUERY_MAX]) >= 0) return true;
	return false;
}

fn long step_int(settings::SettingSpec s, long value, int dir)
{
	long step = (long)s.step;
	if (step <= 0) step = 1;
	long next = value + (long)dir * step;
	if (next < (long)s.min) next = (long)s.min;
	if (next > (long)s.max) next = (long)s.max;
	return next;
}

fn double step_float(settings::SettingSpec s, double value, int dir)
{
	double step = s.step;
	if (step <= 0.0) step = 1.0;
	double next = value + (double)dir * step;
	if (next < s.min) next = s.min;
	if (next > s.max) next = s.max;
	return next;
}

fn String enum_next(settings::SettingSpec s, String current, int dir)
{
	usz count = s.options.len;
	if (count == 0) return current;
	usz index  = 0;
	bool found = false;
	for (usz i = 0; i < count; i++)
	{
		if (s.options[i].compare_to(current) == 0)
		{
			index = i;
			found = true;
			break;
		}
	}
	if (!found) return dir > 0 ? s.options[0] : s.options[count - 1];
	if (dir < 0)
	{
		index = (index + count - 1) % count;
	}
	else
	{
		index = (index + 1) % count;
	}
	return s.options[index];
}

fn void append_value(DString* out, settings::SettingValue value, settings::SettingKind kind)
{
	switch (kind)
	{
		case settings::SettingKind.INT:
			(void)out.appendf("%d", value.i);
		case settings::SettingKind.FLOAT:
			(void)out.appendf("%.1f", value.f);
		case settings::SettingKind.BOOL:
			out.append_string(value.b ? "On" : "Off");
		case settings::SettingKind.STRING:
		case settings::SettingKind.ENUM:
			out.append_string(value.s);
	}
}

fn void Panel.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.rows.init(allocator);
	self.open = false;
	self.scope = settings::SettingLayer.GLOBAL;
	self.query_len = 0;
	self.query[0] = 0;
	self.selected = 0;
	self.scroll = 0;
	self.editing = false;
	self.edit_len = 0;
	self.edit_buf[0] = 0;
	self.edit_id = settings::SettingId.APP_THEME;
	self.consumed = false;
}

fn void Panel.destroy(&self)
{
	self.rows.free();
}

fn void Panel.show(&self)
{
	self.open = true;
	self.scope = settings::SettingLayer.GLOBAL;
	self.query_len = 0;
	self.query[0] = 0;
	self.selected = 0;
	self.scroll = 0;
	self.editing = false;
	self.rebuild();
	if (self.selected_id() < 0) self.move_selection(1);
}

fn void Panel.close(&self)
{
	self.open = false;
	self.editing = false;
}

fn String Panel.query_view(&self)
{
	return (String)self.query[0:self.query_len];
}

fn String Panel.edit_view(&self)
{
	return (String)self.edit_buf[0:self.edit_len];
}

fn bool Panel.append_query(&self, int codepoint)
{
	if (codepoint < 32 || codepoint > 126) return false;
	if (self.query_len >= QUERY_MAX) return false;
	self.query[self.query_len] = (char)codepoint;
	self.query_len++;
	self.query[self.query_len] = 0;
	return true;
}

fn void Panel.backspace_query(&self)
{
	if (self.query_len == 0) return;
	self.query_len--;
	self.query[self.query_len] = 0;
}

fn bool section_visible_before(usz index, String query)
{
	String section = settings::SETTINGS[index].section;
	for (usz j = 0; j < index; j++)
	{
		settings::SettingSpec s = settings::SETTINGS[j];
		if (s.section.compare_to(section) != 0) continue;
		if (matches(s.section, s.label, s.key, s.description, query)) return true;
	}
	return false;
}

fn void Panel.rebuild(&self)
{
	self.rows.clear();
	String query = self.query_view();
	for (usz i = 0; i < settings::SETTINGS.len; i++)
	{
		settings::SettingSpec s = settings::SETTINGS[i];
		if (!matches(s.section, s.label, s.key, s.description, query)) continue;
		if (!section_visible_before(i, query))
		{
			self.rows.push({ .header = true, .section = s.section });
		}
		self.rows.push({ .header = false, .section = s.section, .id = (settings::SettingId)i });
	}
	self.clamp_selection();
}

fn bool Panel.is_header(&self, int index)
{
	if (index < 0 || index >= (int)self.rows.len()) return true;
	return self.rows[index].header;
}

fn int Panel.selected_id(&self)
{
	if (self.selected < 0 || self.selected >= (int)self.rows.len()) return -1;
	if (self.rows[self.selected].header) return -1;
	return (int)self.rows[self.selected].id;
}

fn void Panel.clamp_selection(&self)
{
	int rows = (int)self.rows.len();
	if (rows == 0)
	{
		self.selected = 0;
		self.scroll = 0;
		return;
	}
	if (self.selected < 0) self.selected = 0;
	if (self.selected >= rows) self.selected = rows - 1;
	if (self.is_header(self.selected)) self.move_selection(1);
	self.clamp_scroll();
}

fn void Panel.clamp_scroll(&self)
{
	int rows = (int)self.rows.len();
	if (self.selected < self.scroll) self.scroll = self.selected;
	if (self.selected >= self.scroll + MAX_VISIBLE_ROWS) self.scroll = self.selected - MAX_VISIBLE_ROWS + 1;
	int max_scroll = rows - MAX_VISIBLE_ROWS;
	if (max_scroll < 0) max_scroll = 0;
	if (self.scroll > max_scroll) self.scroll = max_scroll;
	if (self.scroll < 0) self.scroll = 0;
}

fn void Panel.move_selection(&self, int delta)
{
	int rows = (int)self.rows.len();
	if (rows == 0) return;
	int step      = delta > 0 ? 1 : -1;
	int remaining = delta > 0 ? delta : -delta;
	int current   = self.selected;
	if (current < 0 || current >= rows) current = step > 0 ? -1 : rows;
	for (int k = 0; k < remaining; k++)
	{
		int next = current;
		for (int guard = 0; guard < rows; guard++)
		{
			next += step;
			if (next < 0) next = rows - 1;
			if (next >= rows) next = 0;
			if (!self.rows[next].header) break;
		}
		current = next;
	}
	self.selected = current;
	self.clamp_scroll();
}

fn void Panel.persist(&self, config::Config* config, bool project_open, String project_root)
{
	if (self.scope == settings::SettingLayer.PROJECT && project_open)
	{
		config.save_project(project_root);
	}
	else
	{
		config.save_global();
	}
}

fn void Panel.change_selected(&self, config::Config* config, int dir, bool project_open, String project_root)
{
	int index = self.selected_id();
	if (index < 0) return;
	settings::SettingId id     = (settings::SettingId)index;
	settings::SettingSpec spec = settings::spec(id);
	switch (spec.kind)
	{
		case settings::SettingKind.INT:
			config.settings.set_int(id, step_int(spec, config.settings.get_int(id), dir), self.scope);
			self.persist(config, project_open, project_root);
		case settings::SettingKind.FLOAT:
			config.settings.set_float(id, step_float(spec, config.settings.get_float(id), dir), self.scope);
			self.persist(config, project_open, project_root);
		case settings::SettingKind.BOOL:
			config.settings.set_bool(id, !config.settings.get_bool(id), self.scope);
			self.persist(config, project_open, project_root);
		case settings::SettingKind.ENUM:
			config.settings.set_string(id, enum_next(spec, config.settings.get_string(id), dir), self.scope);
			self.persist(config, project_open, project_root);
		case settings::SettingKind.STRING:
			break;
	}
}

fn void Panel.start_edit(&self, config::Config* config)
{
	int index = self.selected_id();
	if (index < 0) return;
	settings::SettingId id = (settings::SettingId)index;
	if (settings::spec(id).kind != settings::SettingKind.STRING) return;
	String current = config.settings.get_string(id);
	usz n          = current.len;
	if (n > (usz)EDIT_MAX) n = (usz)EDIT_MAX;
	for (usz i = 0; i < n; i++) self.edit_buf[i] = current[i];
	self.edit_len = (int)n;
	self.edit_buf[self.edit_len] = 0;
	self.edit_id = id;
	self.editing = true;
}

fn void Panel.activate(&self, config::Config* config, bool project_open, String project_root)
{
	int index = self.selected_id();
	if (index < 0) return;
	settings::SettingId id = (settings::SettingId)index;
	switch (settings::spec(id).kind)
	{
		case settings::SettingKind.STRING:
			self.start_edit(config);
		case settings::SettingKind.BOOL:
			self.change_selected(config, 1, project_open, project_root);
		case settings::SettingKind.ENUM:
			self.change_selected(config, 1, project_open, project_root);
		default:
			break;
	}
}

fn void Panel.toggle_scope(&self, bool project_open)
{
	if (!project_open) return;
	self.scope = self.scope == settings::SettingLayer.PROJECT ? settings::SettingLayer.GLOBAL
		: settings::SettingLayer.PROJECT;
}

fn void Panel.reset_selected(
	&self,
	config::Config* config,
	bool project_open,
	String project_root,
	notify::Notifier* notifier
)
{
	int index = self.selected_id();
	if (index < 0) return;
	config.settings.clear((settings::SettingId)index, self.scope);
	self.persist(config, project_open, project_root);
	notifier.push("Reset to default");
}

fn Rect Panel.panel_rect(&self)
{
	float height = (float)(TITLE_HEIGHT + PADDING + FIELD_HEIGHT + 6 + FOOTER_HEIGHT + PADDING)
		+ (float)(MAX_VISIBLE_ROWS * ROW_HEIGHT);
	float x      = ((float)rl::get_screen_width() - (float)PANEL_WIDTH) / 2.0f;
	float y      = (float)topbar::TOP_BAR_HEIGHT + 18.0f;
	return { .x = x, .y = y, .width = (float)PANEL_WIDTH, .height = height };
}

fn Rect Panel.field_rect(&self)
{
	Rect panel = self.panel_rect();
	return {
		.x = panel.x + (float)PADDING,
		.y = panel.y + (float)TITLE_HEIGHT,
		.width = panel.width - (float)(PADDING * 2),
		.height = (float)FIELD_HEIGHT,
	};
}

fn float Panel.list_y(&self)
{
	return self.panel_rect().y + (float)(TITLE_HEIGHT + FIELD_HEIGHT + 6);
}

fn int Panel.row_at(&self, RLVector2 mouse)
{
	Rect panel = self.panel_rect();
	if (mouse[0] < panel.x || mouse[0] > panel.x + panel.width) return -1;
	float y     = self.list_y();
	float limit = panel.y + panel.height - (float)FOOTER_HEIGHT;
	int index   = self.scroll;
	while (index < (int)self.rows.len())
	{
		float h = self.rows[index].header ? (float)HEADER_HEIGHT : (float)ROW_HEIGHT;
		if (mouse[1] >= y && mouse[1] < y + h) return index;
		y += h;
		if (y > limit) break;
		index++;
	}
	return -1;
}

fn void Panel.update(
	&self,
	keymap::Keymap* keymap,
	config::Config* config,
	bool project_open,
	String project_root,
	notify::Notifier* notifier
)
{
	if (!self.open) return;
	self.consumed = false;

	if (!project_open && self.scope == settings::SettingLayer.PROJECT) self.scope = settings::SettingLayer.GLOBAL;

	if (self.editing)
	{
		if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
		{
			self.editing = false;
			return;
		}
		if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER))
		{
			config.settings.set_string(self.edit_id, self.edit_view(), self.scope);
			self.persist(config, project_open, project_root);
			self.editing = false;
			return;
		}
		if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
		{
			if (self.edit_len > 0)
			{
				self.edit_len--;
				self.edit_buf[self.edit_len] = 0;
			}
		}
		int codepoint = rl::get_char_pressed();
		while (codepoint != 0)
		{
			if (codepoint >= 32 && codepoint <= 126 && self.edit_len < EDIT_MAX)
			{
				self.edit_buf[self.edit_len] = (char)codepoint;
				self.edit_len++;
				self.edit_buf[self.edit_len] = 0;
			}
			codepoint = rl::get_char_pressed();
		}
		return;
	}

	if (keymap.pressed((int)commands::CommandId.OVERLAY_CLOSE, commands::CTX_SETTINGS))
	{
		self.consumed = true;
		self.open = false;
		return;
	}

	bool typed = false;
	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		self.backspace_query();
		typed = true;
	}
	int codepoint = rl::get_char_pressed();
	while (codepoint != 0)
	{
		if (self.append_query(codepoint)) typed = true;
		codepoint = rl::get_char_pressed();
	}
	if (typed) self.rebuild();

	if (keymap.pressed_repeat((int)commands::CommandId.LIST_DOWN, commands::CTX_SETTINGS))
	{
		self.consumed = true;
		self.move_selection(1);
	}
	if (keymap.pressed_repeat((int)commands::CommandId.LIST_UP, commands::CTX_SETTINGS))
	{
		self.consumed = true;
		self.move_selection(-1);
	}
	if (keymap.pressed((int)commands::CommandId.SETTINGS_SCOPE_TOGGLE, commands::CTX_SETTINGS))
	{
		self.consumed = true;
		self.toggle_scope(project_open);
	}
	if (keymap.pressed((int)commands::CommandId.SETTINGS_RESET, commands::CTX_SETTINGS))
	{
		self.consumed = true;
		self.reset_selected(config, project_open, project_root, notifier);
	}
	if (keymap.pressed((int)commands::CommandId.LIST_ACCEPT, commands::CTX_SETTINGS))
	{
		self.consumed = true;
		self.activate(config, project_open, project_root);
	}

	int dir = 0;
	if (keymap.pressed_repeat((int)commands::CommandId.SETTINGS_VALUE_DEC, commands::CTX_SETTINGS)) dir = -1;
	if (keymap.pressed_repeat((int)commands::CommandId.SETTINGS_VALUE_INC, commands::CTX_SETTINGS)) dir = 1;
	if (dir != 0)
	{
		self.consumed = true;
		self.change_selected(config, dir, project_open, project_root);
	}

	Rect panel      = self.panel_rect();
	RLVector2 mouse = rl::get_mouse_position();
	bool inside     = mouse[0] >= panel.x && mouse[0] <= panel.x + panel.width && mouse[1] >= panel.y
		&& mouse[1] <= panel.y + panel.height;
	if (!inside)
	{
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT)) self.open = false;
		return;
	}

	if (rl::get_mouse_wheel_move() > 0.0f) self.move_selection(-1);
	if (rl::get_mouse_wheel_move() < 0.0f) self.move_selection(1);

	int row = self.row_at(mouse);
	if (row >= 0 && !self.rows[row].header)
	{
		if (row != self.selected) self.selected = row;
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
		{
			float value_x = panel.x + panel.width - 200.0f;
			if (mouse[0] >= value_x)
			{
				self.change_selected(config, 1, project_open, project_root);
			}
			else
			{
				self.selected = row;
			}
		}
	}
}

fn String Panel.scope_label(&self)
{
	switch (self.scope)
	{
		case settings::SettingLayer.GLOBAL:
			return "Global";
		case settings::SettingLayer.PROJECT:
			return "Project";
		case settings::SettingLayer.DEFAULT:
			return "Default";
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

fn void Panel.draw(&self, RLFont font, bool project_open, config::Config* config)
{
	if (!self.open) return;

	Rect panel = self.panel_rect();
	rl::draw_rectangle_rec(panel, theme::current().panel_bg);
	rl::draw_rectangle_lines_ex(panel, 1.0f, theme::current().panel_border);

	draw_text(font, "Settings", panel.x + (float)PADDING, panel.y + 12.0f, 24.0f, theme::current().panel_header);
	@pool()
	{
		String label   = string::format(tmem, "Scope: %s%s", self.scope_label(), project_open ? "" : " (no project)");
		RLVector2 size = rl::measure_text_ex(font, label.zstr_tcopy(), 18.0f, 0.0f);
		rl::draw_text_ex(
			font,
			label.zstr_tcopy(),
			{ panel.x + panel.width - (float)PADDING - size[0], panel.y + 15.0f },
			18.0f,
			0.0f,
			theme::current()
			.panel_dim);
	};

	Rect field = self.field_rect();
	rl::draw_rectangle_rec(field, theme::current().panel_field);
	String query = self.query_view();
	draw_text(font, query, field.x + 8.0f, field.y + 8.0f, 20.0f, theme::current().panel_text);
	if (query.len == 0)
	{
		draw_text(font, "Search settings", field.x + 8.0f, field.y + 8.0f, 20.0f, theme::current().panel_dim);
	}
	float query_width = 0.0f;
	if (query.len > 0)
	{
		@pool()
		{
			query_width = rl::measure_text_ex(font, query.zstr_tcopy(), 20.0f, 0.0f)[0];
		};
	}
	rl::draw_rectangle((int)(field.x + 8.0f + query_width + 1.0f), (int)(field.y + 8.0f), 2, 20, theme::current()
		.panel_caret);

	float y     = self.list_y();
	float limit = panel.y + panel.height - (float)FOOTER_HEIGHT;
	for (int index = self.scroll; index < (int)self.rows.len(); index++)
	{
		if (y >= limit) break;
		Row row = self.rows[index];
		if (row.header)
		{
			draw_text(font, row.section, panel.x + (float)PADDING, y + 7.0f, 18.0f, theme::current().panel_header);
			y += (float)HEADER_HEIGHT;
			continue;
		}
		bool selected = index == self.selected;
		if (selected)
		{
			rl::draw_rectangle((int)panel.x + 2, (int)y, (int)panel.width - 4, ROW_HEIGHT, theme::current()
				.panel_selected);
		}
		settings::SettingSpec spec = settings::spec(row.id);
		draw_text(font, spec.label, panel.x + (float)PADDING + 4.0f, y + 9.0f, 20.0f, theme::current().panel_text);

		@pool()
		{
			String source              = "default";
			settings::SettingLayer src = config.settings.source(row.id);
			if (src == settings::SettingLayer.GLOBAL) source = "global";
			if (src == settings::SettingLayer.PROJECT) source = "project";
			RLVector2 src_size = rl::measure_text_ex(font, source.zstr_tcopy(), 15.0f, 0.0f);
			rl::draw_text_ex(
				font,
				source.zstr_tcopy(),
				{ panel.x + panel.width - 210.0f - src_size[0] - 8.0f, y + 11.0f },
				15.0f,
				0.0f,
				theme::current()
				.panel_dim);

			DString value_text;
			value_text.init(tmem, 32);
			if (self.editing && (int)row.id == (int)self.edit_id)
			{
				value_text.append_string(self.edit_view());
				value_text.append_string("_");
			}
			else
			{
				append_value(&value_text, config.settings.effective(row.id), spec.kind);
			}
			RLVector2 value_size = rl::measure_text_ex(font, value_text.str_view().zstr_tcopy(), 20.0f, 0.0f);
			rl::draw_text_ex(font, value_text.str_view()
				.zstr_tcopy(), {
					panel.x + panel.width - (float)PADDING - value_size[0],
					y + 9.0f
				}, 20.0f, 0.0f, selected ? theme::current()
					.panel_text : theme::current().panel_dim);
			value_text.free();
		};
		y += (float)ROW_HEIGHT;
	}

	float footer_y = panel.y + panel.height - (float)FOOTER_HEIGHT;
	rl::draw_line((int)panel.x, (int)footer_y, (int)(panel.x + panel.width), (int)footer_y, theme::current()
		.panel_border);
	int index = self.selected_id();
	if (index >= 0)
	{
		settings::SettingSpec spec = settings::spec((settings::SettingId)index);
		draw_text(font, spec.description, panel.x + (float)PADDING, footer_y + 10.0f, 18.0f, theme::current()
			.panel_dim);
	}
	draw_text(
		font,
		"Arrows: change   Enter: edit/toggle   Tab: scope   Del: reset   Esc: close",
		panel.x + (float)PADDING,
		footer_y + 34.0f,
		15.0f,
		theme::current()
		.panel_dim);
}