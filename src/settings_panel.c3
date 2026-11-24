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
import yun::icons;
import yun::theme;
import yun::topbar;
import yun::ui;

const int PANEL_WIDTH   = 1000;
const int ROW_HEIGHT    = 46;
const int HEADER_HEIGHT = 32;
const int PADDING       = 12;
const int FIELD_HEIGHT  = 36;
const int FOOTER_HEIGHT = 64;
const int QUERY_MAX     = 64;
const int EDIT_MAX      = 128;
const int SIDEBAR_WIDTH = 190;

enum RowKind : int
{
	HEADER,
	SETTING,
	COMMAND,
	ACTION,
	PAGE_RESET,
}

struct Row
{
	RowKind kind;
	settings::SettingId setting;
	commands::CommandId command;
	String section;
	settings::SettingPage page;
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
	bool capturing;
	commands::CommandId capture_id;
	bool consumed;
	settings::SettingPage page;
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

fn String enum_next(String[] options, String current, int dir)
{
	usz count = options.len;
	if (count == 0) return current;
	usz index  = 0;
	bool found = false;
	for (usz i = 0; i < count; i++)
	{
		if (options[i].compare_to(current) == 0)
		{
			index = i;
			found = true;
			break;
		}
	}
	if (!found) return dir > 0 ? options[0] : options[count - 1];
	if (dir < 0)
	{
		index = (index + count - 1) % count;
	}
	else
	{
		index = (index + 1) % count;
	}
	return options[index];
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
	self.capturing = false;
	self.capture_id = (commands::CommandId)0;
	self.consumed = false;
	self.page = settings::SettingPage.GENERAL;
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
	self.capturing = false;
	self.rebuild();
	if (self.selected_row() < 0) self.move_selection(1);
}

fn void Panel.close(&self)
{
	self.open = false;
	self.editing = false;
	self.capturing = false;
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

fn bool command_matches(commands::CommandId id, String query)
{
	if (query.len == 0) return true;
	usz[QUERY_MAX] positions;
	if (commands::fuzzy_match(commands::command_def(id).label, query, positions[0:QUERY_MAX]) >= 0) return true;
	if (commands::fuzzy_match(commands::command_name(id), query, positions[0:QUERY_MAX]) >= 0) return true;
	return false;
}

fn void Panel.rebuild(&self)
{
	self.rows.clear();
	String query = self.query_view();
	if (query.len == 0)
	{
		if (self.page == settings::SettingPage.KEYS)
		{
			self.rows.push({ .kind = RowKind.HEADER, .section = "Keybindings", .page = settings::SettingPage.KEYS });
			self.rows.push({ .kind = RowKind.ACTION, .section = "keys", .page = settings::SettingPage.KEYS });
			for (usz i = 0; i < commands::command_count(); i++)
			{
				self.rows.push(
					{
						.kind = RowKind.COMMAND,
						.section = "keys",
						.command = (commands::CommandId)i,
						.page = settings::SettingPage.KEYS,
					}
				);
			}
		}
		else
		{
			String last_group = "";
			bool has_settings = false;
			for (usz i = 0; i < settings::SETTINGS.len; i++)
			{
				settings::SettingId id = (settings::SettingId)i;
				if (settings::page_for(id) != self.page) continue;
				String group = settings::group_for(id);
				if (group.compare_to(last_group) != 0)
				{
					self.rows.push({ .kind = RowKind.HEADER, .section = group, .page = self.page });
					last_group = group;
				}
				self.rows.push({ .kind = RowKind.SETTING, .section = group, .setting = id, .page = self.page });
				has_settings = true;
			}
			if (has_settings)
			{
				self.rows.push({ .kind = RowKind.PAGE_RESET, .section = settings::page_label(self.page) });
			}
		}
	}
	else
	{
		settings::SettingPage last_page = settings::SettingPage.COUNT;
		for (usz i = 0; i < settings::SETTINGS.len; i++)
		{
			settings::SettingId id  = (settings::SettingId)i;
			settings::SettingSpec s = settings::spec(id);
			if (!matches(s.section, s.label, s.key, s.description, query)) continue;
			settings::SettingPage page = settings::page_for(id);
			if (page != last_page)
			{
				self.rows.push({ .kind = RowKind.HEADER, .section = settings::page_label(page), .page = page });
				last_page = page;
			}
			self.rows.push(
				{ .kind = RowKind.SETTING, .section = settings::group_for(id), .setting = id, .page = page }
			);
		}

		bool any_command = false;
		for (usz i = 0; i < commands::command_count(); i++)
		{
			if (command_matches((commands::CommandId)i, query))
			{
				any_command = true;
				break;
			}
		}
		if (any_command)
		{
			self.rows.push({ .kind = RowKind.HEADER, .section = "Keybindings", .page = settings::SettingPage.KEYS });
			self.rows.push({ .kind = RowKind.ACTION, .section = "keys", .page = settings::SettingPage.KEYS });
			for (usz i = 0; i < commands::command_count(); i++)
			{
				if (!command_matches((commands::CommandId)i, query)) continue;
				self.rows.push(
					{
						.kind = RowKind.COMMAND,
						.section = "keys",
						.command = (commands::CommandId)i,
						.page = settings::SettingPage.KEYS,
					}
				);
			}
		}
	}
	self.clamp_selection();
}

fn bool Panel.is_header(&self, int index)
{
	if (index < 0 || index >= (int)self.rows.len()) return true;
	return self.rows[index].kind == RowKind.HEADER;
}

fn int Panel.selected_row(&self)
{
	if (self.selected < 0 || self.selected >= (int)self.rows.len()) return -1;
	if (self.rows[self.selected].kind == RowKind.HEADER) return -1;
	return self.selected;
}

fn int Panel.selected_setting(&self)
{
	int index = self.selected_row();
	if (index < 0 || self.rows[index].kind != RowKind.SETTING) return -1;
	return (int)self.rows[index].setting;
}

fn int Panel.selected_command(&self)
{
	int index = self.selected_row();
	if (index < 0 || self.rows[index].kind != RowKind.COMMAND) return -1;
	return (int)self.rows[index].command;
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
	int visible = self.visible_rows();
	if (self.selected >= self.scroll + visible) self.scroll = self.selected - visible + 1;
	int max_scroll = rows - visible;
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
			if (self.rows[next].kind != RowKind.HEADER) break;
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
	int index = self.selected_setting();
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
			config.settings.set_string(
				id,
				enum_next(settings::setting_options(id), config.settings.get_string(id), dir),
				self.scope
			);
			self.persist(config, project_open, project_root);
		case settings::SettingKind.STRING:
			break;
	}
}

fn void Panel.start_edit(&self, config::Config* config)
{
	int index = self.selected_setting();
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

fn void Panel.activate_setting(&self, config::Config* config, bool project_open, String project_root)
{
	int index = self.selected_setting();
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

fn void Panel.reset_setting(
	&self,
	config::Config* config,
	bool project_open,
	String project_root,
	notify::Notifier* notifier
)
{
	int index = self.selected_setting();
	if (index < 0) return;
	config.settings.clear((settings::SettingId)index, self.scope);
	self.persist(config, project_open, project_root);
	notifier.push("Reset to default");
}

fn void Panel.start_capture(&self, commands::CommandId id)
{
	self.capturing = true;
	self.capture_id = id;
}

fn void Panel.apply_capture(
	&self,
	keymap::Keymap* keymap,
	config::Config* config,
	keymap::Chord chord,
	bool project_open,
	String project_root,
	notify::Notifier* notifier
)
{
	String name = commands::command_name(self.capture_id);
	@pool()
	{
		String text = keymap::format_chord(tmem, chord, keymap::is_macos());
		config.set_key_binding(name, text, self.scope);
	};
	keymap.build(config);
	self.persist(config, project_open, project_root);
	if (keymap.conflicts((int)self.capture_id))
	{
		notifier.push("Shortcut conflict");
	}
	else
	{
		notifier.push("Shortcut updated");
	}
}

fn void Panel.command_unbind(
	&self,
	keymap::Keymap* keymap,
	config::Config* config,
	bool project_open,
	String project_root,
	notify::Notifier* notifier
)
{
	int index = self.selected_command();
	if (index < 0) return;
	config.set_key_binding(commands::command_name((commands::CommandId)index), "", self.scope);
	keymap.build(config);
	self.persist(config, project_open, project_root);
	notifier.push("Shortcut cleared");
}

fn void Panel.command_reset(
	&self,
	keymap::Keymap* keymap,
	config::Config* config,
	bool project_open,
	String project_root,
	notify::Notifier* notifier
)
{
	int index = self.selected_command();
	if (index < 0) return;
	config.remove_key_binding(commands::command_name((commands::CommandId)index), self.scope);
	keymap.build(config);
	self.persist(config, project_open, project_root);
	notifier.push("Reset to default");
}

fn void Panel.reset_all(
	&self,
	keymap::Keymap* keymap,
	config::Config* config,
	bool project_open,
	String project_root,
	notify::Notifier* notifier
)
{
	config.clear_keymap(self.scope);
	keymap.build(config);
	self.persist(config, project_open, project_root);
	notifier.push("Keybindings reset");
}

fn Rect Panel.outer_rect(&self)
{
	float width  = math::min((float)ui::px(PANEL_WIDTH), (float)rl::get_screen_width() - (float)ui::px(40));
	float y      = ui::pxf(topbar::TOP_BAR_HEIGHT) + (float)ui::px(18);
	float height = math::min((float)ui::px(700), (float)rl::get_screen_height() - y - (float)ui::px(24));
	return {
		.x = ((float)rl::get_screen_width() - width) / 2.0f,
		.y = y,
		.width = width,
		.height = height,
	};
}

fn Rect Panel.sidebar_rect(&self)
{
	Rect outer = self.outer_rect();
	return { .x = outer.x, .y = outer.y, .width = (float)ui::px(SIDEBAR_WIDTH), .height = outer.height };
}

fn Rect Panel.panel_rect(&self)
{
	Rect outer = self.outer_rect();
	return {
		.x = outer.x + (float)ui::px(SIDEBAR_WIDTH),
		.y = outer.y,
		.width = outer.width - (float)ui::px(SIDEBAR_WIDTH),
		.height = outer.height,
	};
}

fn Rect Panel.field_rect(&self)
{
	Rect panel        = self.panel_rect();
	float scope_width = (float)ui::px(210);
	return {
		.x = panel.x + (float)ui::px(PADDING),
		.y = panel.y + (float)ui::px(PADDING),
		.width = panel.width - (float)(ui::px(PADDING) * 2) - scope_width,
		.height = (float)ui::px(FIELD_HEIGHT),
	};
}

fn float Panel.list_y(&self)
{
	Rect field = self.field_rect();
	return field.y + field.height + (float)ui::px(6);
}

fn int Panel.visible_rows(&self)
{
	Rect panel   = self.panel_rect();
	float footer = panel.y + panel.height - (float)ui::px(FOOTER_HEIGHT);
	int rows     = (int)((footer - self.list_y()) / (float)ui::px(ROW_HEIGHT));
	return rows > 0 ? rows : 1;
}

fn Rect Panel.scope_rect(&self, bool project)
{
	Rect panel = self.panel_rect();
	float w    = (float)ui::px(96);
	float x    = panel.x + panel.width - (float)ui::px(PADDING) - w * 2.0f - (float)ui::px(4);
	return {
		.x = project ? x + w + (float)ui::px(4) : x,
		.y = panel.y + (float)ui::px(PADDING) + (float)ui::px(3),
		.width = w,
		.height = (float)ui::px(30),
	};
}

fn Rect Panel.page_rect(&self, int page)
{
	Rect sidebar = self.sidebar_rect();
	return {
		.x = sidebar.x + (float)ui::px(8),
		.y = sidebar.y + (float)ui::px(64) + (float)ui::px(34) * (float)page,
		.width = sidebar.width - (float)ui::px(16),
		.height = (float)ui::px(30),
	};
}

fn int Panel.page_at(&self, RLVector2 mouse)
{
	for (int i = 0; i < (int)settings::SettingPage.COUNT; i++)
	{
		if (mouse[0] >= self.page_rect(i)
			.x && mouse[0] <= self.page_rect(i)
				.x + self.page_rect(i)
					.width && mouse[1] >= self.page_rect(i)
						.y && mouse[1] <= self.page_rect(i).y + self.page_rect(i).height)
		{
			return i;
		}
	}
	return -1;
}

fn void Panel.set_page(&self, settings::SettingPage page)
{
	if (page == settings::SettingPage.COUNT) return;
	self.page = page;
	self.query_len = 0;
	self.query[0] = 0;
	self.selected = 0;
	self.scroll = 0;
	self.rebuild();
}


fn int Panel.row_at(&self, RLVector2 mouse)
{
	Rect panel = self.panel_rect();
	if (mouse[0] < panel.x || mouse[0] > panel.x + panel.width) return -1;
	float y     = self.list_y();
	float limit = panel.y + panel.height - (float)ui::px(FOOTER_HEIGHT);
	int index   = self.scroll;
	while (index < (int)self.rows.len())
	{
		float h = self.rows[index].kind == RowKind.HEADER ? (float)ui::px(HEADER_HEIGHT) : (float)ui::px(ROW_HEIGHT);
		if (mouse[1] >= y && mouse[1] < y + h) return index;
		y += h;
		if (y > limit) break;
		index++;
	}
	return -1;
}

fn void Panel.clear_query(&self)
{
	self.query_len = 0;
	self.query[0] = 0;
	self.selected = 0;
	self.scroll = 0;
	self.rebuild();
}

fn void Panel.reset_page(
	&self,
	keymap::Keymap* keymap,
	config::Config* config,
	bool project_open,
	String project_root,
	notify::Notifier* notifier
)
{
	if (self.page == settings::SettingPage.KEYS)
	{
		config.clear_keymap(self.scope);
		keymap.build(config);
	}
	else
	{
		for (usz i = 0; i < settings::SETTINGS.len; i++)
		{
			settings::SettingId id = (settings::SettingId)i;
			if (settings::page_for(id) == self.page) config.settings.clear(id, self.scope);
		}
	}
	self.persist(config, project_open, project_root);
	self.rebuild();
	notifier.push("Page reset to defaults");
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

	if (self.capturing)
	{
		self.consumed = true;
		keymap::Chord chord;
		int captured = keymap::capture_chord(&chord);
		while (rl::get_char_pressed() != 0)
		{
		}
		if (captured < 0)
		{
			self.capturing = false;
		}
		else if (captured > 0)
		{
			self.capturing = false;
			self.apply_capture(keymap, config, chord, project_open, project_root, notifier);
		}
		return;
	}

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

	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		self.consumed = true;
		if (self.query_len > 0)
		{
			self.clear_query();
		}
		else
		{
			self.open = false;
		}
		return;
	}

	if (rl::is_key_down(rl::RLKeyboardKey.LEFT_CONTROL) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_CONTROL))
	{
		for (int i = 0; i < (int)settings::SettingPage.COUNT; i++)
		{
			if (rl::is_key_pressed((rl::RLKeyboardKey)((int)rl::RLKeyboardKey.ONE + i)))
			{
				self.consumed = true;
				self.clear_query();
				self.set_page((settings::SettingPage)i);
				return;
			}
		}
	}

	bool typed = false;
	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		if (self.query_len > 0)
		{
			self.backspace_query();
			typed = true;
		}
		else
		{
			self.consumed = true;
			self.command_reset(keymap, config, project_open, project_root, notifier);
		}
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
		int row = self.selected_row();
		if (row >= 0)
		{
			switch (self.rows[row].kind)
			{
				case RowKind.SETTING:
					self.reset_setting(config, project_open, project_root, notifier);
				case RowKind.COMMAND:
					self.command_unbind(keymap, config, project_open, project_root, notifier);
				case RowKind.ACTION:
					self.reset_all(keymap, config, project_open, project_root, notifier);
				case RowKind.PAGE_RESET:
					self.reset_page(keymap, config, project_open, project_root, notifier);
				default:
					break;
			}
		}
	}
	if (keymap.pressed((int)commands::CommandId.LIST_ACCEPT, commands::CTX_SETTINGS))
	{
		self.consumed = true;
		int row = self.selected_row();
		if (row >= 0)
		{
			switch (self.rows[row].kind)
			{
				case RowKind.SETTING:
					self.activate_setting(config, project_open, project_root);
				case RowKind.COMMAND:
					self.start_capture(self.rows[row].command);
				case RowKind.ACTION:
					self.reset_all(keymap, config, project_open, project_root, notifier);
				case RowKind.PAGE_RESET:
					self.reset_page(keymap, config, project_open, project_root, notifier);
				default:
					break;
			}
		}
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
	Rect outer      = self.outer_rect();
	RLVector2 mouse = rl::get_mouse_position();
	bool inside     = mouse[0] >= outer.x && mouse[0] <= outer.x + outer.width && mouse[1] >= outer.y
		&& mouse[1] <= outer.y + outer.height;
	if (!inside)
	{
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT)) self.open = false;
		return;
	}

	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		int page = self.page_at(mouse);
		if (page >= 0)
		{
			self.consumed = true;
			self.set_page((settings::SettingPage)page);
			return;
		}
		Rect global_scope  = self.scope_rect(false);
		Rect project_scope = self.scope_rect(true);
		if (mouse[0] >= global_scope.x && mouse[0] <= global_scope.x + global_scope.width && mouse[1] >= global_scope.y
			&& mouse[1] <= global_scope.y + global_scope.height)
		{
			self.scope = settings::SettingLayer.GLOBAL;
			return;
		}
		if (project_open && mouse[0] >= project_scope.x && mouse[0] <= project_scope.x + project_scope.width
			&& mouse[1] >= project_scope.y
			&& mouse[1] <= project_scope.y + project_scope.height)
		{
			self.scope = settings::SettingLayer.PROJECT;
			return;
		}
	}

	if (mouse[0] < panel.x)
	{
		return;
	}

	if (rl::get_mouse_wheel_move() > 0.0f) self.move_selection(-1);
	if (rl::get_mouse_wheel_move() < 0.0f) self.move_selection(1);

	int row = self.row_at(mouse);
	if (row >= 0 && self.rows[row].kind != RowKind.HEADER)
	{
		if (row != self.selected) self.selected = row;
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
		{
			float value_x = panel.x + panel.width - 200.0f;
			if (mouse[0] >= value_x)
			{
				switch (self.rows[row].kind)
				{
					case RowKind.SETTING:
						self.change_selected(config, 1, project_open, project_root);
					case RowKind.COMMAND:
						self.start_capture(self.rows[row].command);
					case RowKind.ACTION:
						self.reset_all(keymap, config, project_open, project_root, notifier);
					case RowKind.PAGE_RESET:
						self.reset_page(keymap, config, project_open, project_root, notifier);
					default:
						break;
				}
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


fn icons::IconKind page_icon(settings::SettingPage page)
{
	switch (page)
	{
		case settings::SettingPage.GENERAL:
			return icons::IconKind.SETTINGS;
		case settings::SettingPage.APPEARANCE:
			return icons::IconKind.THEME;
		case settings::SettingPage.EDITOR:
			return icons::IconKind.SYMBOLS;
		case settings::SettingPage.CANVAS:
			return icons::IconKind.MAXIMIZE;
		case settings::SettingPage.INTEGRATIONS:
			return icons::IconKind.CONNECTIONS;
		case settings::SettingPage.KEYS:
			return icons::IconKind.KEYBOARD;
		case settings::SettingPage.CONSOLE:
			return icons::IconKind.CONSOLE;
		case settings::SettingPage.ADVANCED:
			return icons::IconKind.SETTINGS;
		case settings::SettingPage.COUNT:
			return icons::IconKind.SETTINGS;
	}
}

fn void Panel.draw(&self, RLFont font, bool project_open, keymap::Keymap* keymap, config::Config* config)
{
	if (!self.open) return;

	Rect outer   = self.outer_rect();
	Rect panel   = self.panel_rect();
	Rect sidebar = self.sidebar_rect();
	ui::panel(outer, theme::current().panel_bg, theme::current().panel_border);
	ui::rounded_rect(sidebar, ui::corner_radius(), theme::current().panel_bg_alt);
	rl::draw_line(
		(int)(sidebar.x + sidebar.width),
		(int)sidebar.y,
		(int)(sidebar.x + sidebar.width),
		(int)(sidebar.y + sidebar.height),
		theme::current()
		.panel_border);

	float title_icon = icons::icon_size(20);
	icons::draw(
		icons::IconKind.SETTINGS,
		{
			.x = sidebar.x + (float)ui::px(PADDING),
			.y = sidebar.y + (float)ui::px(12),
			.width = title_icon,
			.height = title_icon
		},
		theme::current()
		.panel_header);
	draw_text(
		font,
		"Settings",
		sidebar.x + (float)ui::px(PADDING) + title_icon + (float)ui::px(8),
		sidebar.y + (float)ui::px(12),
		(float)ui::tpx(22),
		theme::current()
		.panel_header);

	for (int i = 0; i < (int)settings::SettingPage.COUNT; i++)
	{
		Rect pr = self.page_rect(i);
		if (i == (int)self.page)
		{
			ui::row(pr, theme::current().panel_selected);
		}
		float icon_size = icons::icon_size(16);
		icons::draw(
			page_icon((settings::SettingPage)i),
			{
				.x = pr.x + (float)ui::px(6),
				.y = pr.y + (pr.height - icon_size) * 0.5f,
				.width = icon_size,
				.height = icon_size,
			},
			i == (int)self.page ? theme::current()
			.panel_text : theme::current().panel_dim);
		draw_text(
			font,
			settings::page_label((settings::SettingPage)i),
			pr.x + (float)ui::px(6) + icon_size + (float)ui::px(6),
			pr.y + (float)ui::px(5),
			(float)ui::tpx(18),
			i == (int)self.page ? theme::current()
			.panel_text : theme::current().panel_dim);
	}

	Rect global_scope    = self.scope_rect(false);
	Rect project_scope   = self.scope_rect(true);
	bool project_enabled = project_open;
	ui::rounded_rect(global_scope, ui::row_radius(), self.scope == settings::SettingLayer.GLOBAL ? theme::current()
		.panel_selected : theme::current().panel_field);
	ui::rounded_rect(project_scope, ui::row_radius(), self.scope == settings::SettingLayer.PROJECT ? theme::current()
		.panel_selected : theme::current().panel_field);
	draw_text(
		font,
		"Global",
		global_scope.x + (float)ui::px(12),
		global_scope.y + (float)ui::px(6),
		(float)ui::tpx(16),
		theme::current()
		.panel_text);
	draw_text(
		font,
		"Project",
		project_scope.x + (float)ui::px(12),
		project_scope.y + (float)ui::px(6),
		(float)ui::tpx(16),
		project_enabled ? theme::current()
		.panel_text : theme::current().panel_disabled);

	Rect field = self.field_rect();
	ui::rounded_rect(field, ui::row_radius(), theme::current().panel_field);
	String query = self.query_view();
	draw_text(font, query, field.x + (float)ui::px(8), field.y + (float)ui::px(8), (float)ui::tpx(20), theme::current()
		.panel_text);
	if (query.len == 0)
	{
		draw_text(
			font,
			"Search settings",
			field.x + (float)ui::px(8),
			field.y + (float)ui::px(8),
			(float)ui::tpx(20),
			theme::current()
			.panel_dim);
	}
	float query_width = 0.0f;
	if (query.len > 0)
	{
		@pool()
		{
			query_width = rl::measure_text_ex(font, query.zstr_tcopy(), (float)ui::tpx(20), 0.0f)[0];
		};
	}
	rl::draw_rectangle(
		(int)(field.x + (float)ui::px(8) + query_width + 1.0f),
		(int)(field.y + (float)ui::px(8)),
		2,
		ui::px(20),
		theme::current()
		.panel_caret);

	float y     = self.list_y();
	float limit = panel.y + panel.height - (float)ui::px(FOOTER_HEIGHT);
	for (int index = self.scroll; index < (int)self.rows.len(); index++)
	{
		if (y >= limit) break;
		Row row = self.rows[index];
		if (row.kind == RowKind.HEADER)
		{
			float header_icon = icons::icon_size(16);
			icons::draw(
				page_icon(row.page),
				{
					.x = panel.x + (float)ui::px(PADDING),
					.y = y + (float)ui::px(7),
					.width = header_icon,
					.height = header_icon,
				},
				theme::current()
				.panel_header);
			draw_text(
				font,
				row.section,
				panel.x + (float)ui::px(PADDING) + header_icon + (float)ui::px(6),
				y + (float)ui::px(7),
				(float)ui::tpx(18),
				theme::current()
				.panel_header);
			y += (float)ui::px(HEADER_HEIGHT);
			continue;
		}
		bool selected = index == self.selected;
		if (selected)
		{
			ui::row(
				{
					.x = panel.x + 2.0f,
					.y = y,
					.width = panel.width - 4.0f,
					.height = (float)ui::px(ROW_HEIGHT),
				},
				theme::current()
				.panel_selected);
		}
		if (row.kind == RowKind.SETTING)
		{
			self.draw_setting_row(font, panel, row, selected, y, config);
		}
		else if (row.kind == RowKind.COMMAND)
		{
			self.draw_command_row(font, panel, row, selected, y, keymap, config);
		}
		else if (row.kind == RowKind.ACTION)
		{
			draw_text(
				font,
				"Reset all keybindings (scope)",
				panel.x + (float)ui::px(PADDING) + (float)ui::px(4),
				y + (float)ui::px(9),
				(float)ui::tpx(20),
				theme::current()
				.panel_text);
		}
		else
		{
			@pool()
			{
				String label = string::format(tmem, "Reset %s to defaults", row.section);
				draw_text(
					font,
					label,
					panel.x + (float)ui::px(PADDING) + (float)ui::px(4),
					y + (float)ui::px(9),
					(float)ui::tpx(20),
					theme::current()
					.panel_text);
			};
		}
		y += (float)ui::px(ROW_HEIGHT);
	}

	float footer_y = panel.y + panel.height - (float)ui::px(FOOTER_HEIGHT);
	rl::draw_line((int)panel.x, (int)footer_y, (int)(panel.x + panel.width), (int)footer_y, theme::current()
		.panel_border);
	int index = self.selected_row();
	if (index >= 0)
	{
		Row row = self.rows[index];
		if (row.kind == RowKind.SETTING)
		{
			draw_text(
				font,
				"Enter: edit/toggle   Del: reset   Tab: scope",
				panel.x + (float)ui::px(PADDING),
				footer_y + (float)ui::px(10),
				(float)ui::tpx(18),
				theme::current()
				.panel_dim);
		}
		else if (row.kind == RowKind.COMMAND)
		{
			draw_text(
				font,
				"Enter: capture   Del: unbind   Backspace: reset (empty search)",
				panel.x + (float)ui::px(PADDING),
				footer_y + (float)ui::px(10),
				(float)ui::tpx(18),
				theme::current()
				.panel_dim);
		}
		else if (row.kind == RowKind.ACTION)
		{
			draw_text(
				font,
				"Enter: reset all keybindings in this scope",
				panel.x + (float)ui::px(PADDING),
				footer_y + (float)ui::px(10),
				(float)ui::tpx(18),
				theme::current()
				.panel_dim);
		}
		else
		{
			draw_text(
				font,
				"Enter: reset this page to defaults",
				panel.x + (float)ui::px(PADDING),
				footer_y + (float)ui::px(10),
				(float)ui::tpx(18),
				theme::current()
				.panel_dim);
		}
	}
	draw_text(
		font,
		self.capturing ? "Press a chord   Esc: cancel" : "Enter: activate   Tab: scope   Esc: close",
		panel.x + (float)ui::px(PADDING),
		footer_y + (float)ui::px(34),
		(float)ui::tpx(15),
		theme::current()
		.panel_dim);
}

fn void Panel.draw_setting_row(&self, RLFont font, Rect panel, Row row, bool selected, float y, config::Config* config)
{
	settings::SettingSpec spec = settings::spec(row.setting);
	draw_text(
		font,
		spec.label,
		panel.x + (float)ui::px(PADDING) + (float)ui::px(4),
		y + (float)ui::px(5),
		(float)ui::tpx(19),
		theme::current()
		.panel_text);
	draw_text(
		font,
		spec.description,
		panel.x + (float)ui::px(PADDING) + (float)ui::px(4),
		y + (float)ui::px(25),
		(float)ui::tpx(14),
		theme::current()
		.panel_dim);

	@pool()
	{
		String source              = "default";
		settings::SettingLayer src = config.settings.source(row.setting);
		if (src == settings::SettingLayer.GLOBAL) source = "global";
		if (src == settings::SettingLayer.PROJECT) source = "project";
		RLVector2 src_size = rl::measure_text_ex(font, source.zstr_tcopy(), (float)ui::tpx(15), 0.0f);
		rl::draw_text_ex(
			font,
			source.zstr_tcopy(),
			{ panel.x + panel.width - (float)ui::px(210) - src_size[0] - (float)ui::px(8), y + (float)ui::px(11) },
			(float)ui::tpx(15),
			0.0f,
			theme::current()
			.panel_dim);

		DString value_text;
		value_text.init(tmem, 32);
		if (self.editing && (int)row.setting == (int)self.edit_id)
		{
			value_text.append_string(self.edit_view());
			value_text.append_string("_");
		}
		else
		{
			append_value(&value_text, config.settings.effective(row.setting), spec.kind);
		}
		RLVector2 value_size = rl::measure_text_ex(font, value_text.str_view().zstr_tcopy(), (float)ui::tpx(20), 0.0f);
		rl::draw_text_ex(font, value_text.str_view()
			.zstr_tcopy(), {
				panel.x + panel.width - (float)ui::px(PADDING) - value_size[0],
				y + (float)ui::px(6)
			}, (float)ui::tpx(20), 0.0f, selected ? theme::current()
				.panel_text : theme::current().panel_dim);
		value_text.free();
	};
}

fn void Panel.draw_command_row(
	&self,
	RLFont font,
	Rect panel,
	Row row,
	bool selected,
	float y,
	keymap::Keymap* keymap,
	config::Config* config
)
{
	commands::CommandId id = row.command;
	draw_text(font, commands::command_def(id)
		.label, panel.x + (float)ui::px(
			PADDING
		) + (float)ui::px(4), y + (float)ui::px(9), (float)ui::tpx(20), theme::current()
			.panel_text);

	bool capturing = self.capturing && (int)id == (int)self.capture_id;
	bool conflict  = keymap.conflicts((int)id);
	@pool()
	{
		String source = "default";
		String chord;
		settings::SettingLayer layer;
		if (config.keymap_override(commands::command_name(id), &chord, &layer))
		{
			source = layer == settings::SettingLayer.PROJECT ? "project" : "global";
		}
		RLVector2 src_size = rl::measure_text_ex(font, source.zstr_tcopy(), (float)ui::tpx(15), 0.0f);
		rl::draw_text_ex(
			font,
			source.zstr_tcopy(),
			{ panel.x + panel.width - (float)ui::px(210) - src_size[0] - (float)ui::px(8), y + (float)ui::px(11) },
			(float)ui::tpx(15),
			0.0f,
			theme::current()
			.panel_dim);

		String text = capturing ? "Press a chord..." : keymap.shortcut(id);
		if (text.len == 0) text = "(unbound)";
		RLVector2 value_size = rl::measure_text_ex(font, text.zstr_tcopy(), (float)ui::tpx(20), 0.0f);
		RLColor color        = selected ? theme::current().panel_text : theme::current().panel_dim;
		if (conflict || capturing) color = theme::current().panel_match;
		rl::draw_text_ex(
			font,
			text.zstr_tcopy(),
			{ panel.x + panel.width - (float)ui::px(PADDING) - value_size[0], y + (float)ui::px(9) },
			(float)ui::tpx(20),
			0.0f,
			color
		);
	};
}