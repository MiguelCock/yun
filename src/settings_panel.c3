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
import yun::skin;
import yun::icons;
import yun::theme;
import yun::topbar;
import yun::ui;

const int PANEL_WIDTH         = 1000;
const int ROW_HEIGHT          = 46;
const int HEADER_HEIGHT       = 32;
const int PADDING             = 12;
const int FIELD_HEIGHT        = 36;
const int FOOTER_HEIGHT       = 64;
const int QUERY_MAX           = 64;
const int EDIT_MAX            = 128;
const int SIDEBAR_WIDTH       = 190;
const int CARD_HEIGHT         = 76;
const int CARD_GAP            = 8;
const int CARD_MIN_WIDTH      = 280;
const int KEY_FILTER_HEIGHT   = 30;
const int KEY_FILTER_GAP      = 6;
const int KEY_ACTION_HEIGHT   = 38;
const int KEY_CHIP_HEIGHT     = 22;
const int SKIN_EDIT_MAX       = 512;
const float SKIN_CLOSED_STEP  = 4.0f;
const float SKIN_OPACITY_STEP = 0.05f;
const float SKIN_SPEED_STEP   = 0.1f;
const float SKIN_FPS_STEP     = 1.0f;

enum RowKind : int
{
	HEADER,
	SETTING,
	COMMAND,
	ACTION,
	PAGE_RESET,
	SKIN,
}

enum SkinItem : int
{
	PRESET,
	CARD_STYLE,
	FOLDER_STYLE,
	CLOSED_HEIGHT,
	LANGUAGE_COLORS,
	CARD_LAYOUT,
	SURFACE,
	IMAGE,
	FIT,
	OPACITY,
	TINT,
	SCRIM,
	SPEED,
	FPS,
	RELOAD,
	RESET,
	COUNT,
}

const SkinItem[] SKIN_STYLE_ITEMS = {
	SkinItem.PRESET,
	SkinItem.CARD_STYLE,
	SkinItem.FOLDER_STYLE,
	SkinItem.CLOSED_HEIGHT,
	SkinItem.LANGUAGE_COLORS,
	SkinItem.CARD_LAYOUT,
};

const SkinItem[] SKIN_SURFACE_ITEMS = {
	SkinItem.SURFACE,
	SkinItem.IMAGE,
	SkinItem.FIT,
	SkinItem.OPACITY,
	SkinItem.TINT,
	SkinItem.SCRIM,
	SkinItem.SPEED,
	SkinItem.FPS,
};

const SkinItem[] SKIN_ACTION_ITEMS = {
	SkinItem.RELOAD,
	SkinItem.RESET,
};

enum KeyFilter : int
{
	ALL,
	CONFLICTS,
	MODIFIED,
	UNBOUND,
	COUNT,
}

const String[] KEY_FILTER_LABELS = {
	"All",
	"Conflicts",
	"Modified",
	"Unbound",
};

struct Row
{
	RowKind kind;
	settings::SettingId setting;
	commands::CommandId command;
	SkinItem skin;
	String section;
	settings::SettingPage page;
	int grid_col;
	float grid_y;
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
	KeyFilter key_filter;
	int key_scroll;
	int key_columns;
	float key_content_height;
	keymap::Keymap* keymap;
	config::Config* config;
	skin::SurfaceId skin_surface;
	bool skin_editing;
	char[SKIN_EDIT_MAX + 1] skin_edit_buf;
	int skin_edit_len;
	SkinItem skin_edit_item;
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
	self.key_filter = KeyFilter.ALL;
	self.key_scroll = 0;
	self.key_columns = 1;
	self.key_content_height = 0.0f;
	self.keymap = null;
	self.config = null;
	self.skin_surface = skin::SurfaceId.APP;
	self.skin_editing = false;
	self.skin_edit_len = 0;
	self.skin_edit_buf[0] = 0;
	self.skin_edit_item = SkinItem.PRESET;
}

fn void Panel.destroy(&self)
{
	self.rows.free();
}

fn void Panel.show_page(&self, settings::SettingPage page)
{
	self.show();
	self.page = page;
	self.rebuild();
	if (self.selected_row() < 0) self.move_selection(1);
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
	self.key_filter = KeyFilter.ALL;
	self.key_scroll = 0;
	self.key_columns = 1;
	self.skin_editing = false;
	self.skin_edit_len = 0;
	self.skin_edit_buf[0] = 0;
	self.rebuild();
	if (self.selected_row() < 0) self.move_selection(1);
}

fn void Panel.set_sources(&self, keymap::Keymap* keymap, config::Config* config)
{
	self.keymap = keymap;
	self.config = config;
}

fn void Panel.close(&self)
{
	self.open = false;
	self.editing = false;
	self.capturing = false;
	self.skin_editing = false;
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
	if (commands::fuzzy_match(commands::command_description(id), query, positions[0:QUERY_MAX]) >= 0) return true;
	if (commands::fuzzy_match(commands::command_group(id), query, positions[0:QUERY_MAX]) >= 0) return true;
	return false;
}

fn bool Panel.command_conflict(&self, commands::CommandId id)
{
	if (self.keymap == null) return false;
	return self.keymap.conflicts((int)id);
}

fn bool Panel.command_modified(&self, commands::CommandId id)
{
	if (self.config == null) return false;
	String chord;
	settings::SettingLayer layer;
	return self.config.keymap_override(commands::command_name(id), &chord, &layer);
}

fn bool Panel.command_unbound(&self, commands::CommandId id)
{
	if (self.keymap != null) return self.keymap.shortcut(id).len == 0;
	return commands::command_def(id).shortcut.len == 0;
}

fn bool Panel.key_filter_accepts(&self, commands::CommandId id)
{
	switch (self.key_filter)
	{
		case KeyFilter.ALL:
			return true;
		case KeyFilter.CONFLICTS:
			return self.command_conflict(id);
		case KeyFilter.MODIFIED:
			return self.command_modified(id);
		case KeyFilter.UNBOUND:
			return self.command_unbound(id);
		case KeyFilter.COUNT:
			return true;
	}
}

fn String key_filter_label(KeyFilter filter)
{
	if ((int)filter < 0 || (int)filter >= (int)KEY_FILTER_LABELS.len) return "All";
	return KEY_FILTER_LABELS[(int)filter];
}

fn void Panel.set_key_filter(&self, KeyFilter filter)
{
	if (filter == KeyFilter.COUNT) return;
	if (filter == self.key_filter) return;
	self.key_filter = filter;
	self.selected = 0;
	self.key_scroll = 0;
	self.rebuild();
}

fn float row_grid_height(RowKind kind)
{
	if (kind == RowKind.HEADER) return (float)ui::px(HEADER_HEIGHT);
	if (kind == RowKind.ACTION) return (float)ui::px(KEY_ACTION_HEIGHT);
	return (float)ui::px(CARD_HEIGHT);
}

fn void Panel.layout_keys(&self, int columns)
{
	if (columns < 1) columns = 1;
	self.key_columns = columns;
	float gap = (float)ui::px(CARD_GAP);
	float y   = 0.0f;
	int col   = 0;
	for (sz i = 0; i < self.rows.len(); i++)
	{
		Row* row = self.rows.get_ref(i);
		if (row.kind == RowKind.HEADER || row.kind == RowKind.ACTION)
		{
			if (col > 0)
			{
				y += (float)ui::px(CARD_HEIGHT) + gap;
				col = 0;
			}
			row.grid_col = 0;
			row.grid_y = y;
			y += row_grid_height(row.kind) + gap;
			continue;
		}
		row.grid_col = col;
		row.grid_y = y;
		col++;
		if (col >= columns)
		{
			col = 0;
			y += (float)ui::px(CARD_HEIGHT) + gap;
		}
	}
	if (col > 0) y += (float)ui::px(CARD_HEIGHT) + gap;
	self.key_content_height = y > gap ? y - gap : 0.0f;
}

fn int Panel.grid_columns(&self)
{
	Rect panel      = self.panel_rect();
	float available = panel.width - (float)ui::px(PADDING * 2);
	float min_width = (float)ui::px(CARD_MIN_WIDTH);
	float gap       = (float)ui::px(CARD_GAP);
	if (available >= min_width * 2.0f + gap) return 2;
	return 1;
}

fn void Panel.build_key_rows(&self, String query)
{
	bool has_any = false;
	for (usz g = 0; g < commands::COMMAND_GROUPS.len; g++)
	{
		String group      = commands::COMMAND_GROUPS[g];
		bool wrote_header = false;
		for (usz i = 0; i < commands::command_count(); i++)
		{
			commands::CommandId id = (commands::CommandId)i;
			if (commands::command_group(id).compare_to(group) != 0) continue;
			if (!self.key_filter_accepts(id)) continue;
			if (!command_matches(id, query)) continue;
			if (!wrote_header)
			{
				self.rows.push({ .kind = RowKind.HEADER, .section = group, .page = settings::SettingPage.KEYS });
				wrote_header = true;
			}
			self.rows.push(
				{
					.kind = RowKind.COMMAND,
					.section = group,
					.command = id,
					.page = settings::SettingPage.KEYS,
				}
			);
			has_any = true;
		}
	}
	if (has_any) self.rows.push({ .kind = RowKind.ACTION, .section = "keys", .page = settings::SettingPage.KEYS });
}

fn String skin_item_label(SkinItem item)
{
	switch (item)
	{
		case SkinItem.PRESET:
			return "Preset";
		case SkinItem.CARD_STYLE:
			return "Card style";
		case SkinItem.FOLDER_STYLE:
			return "Folder style";
		case SkinItem.CLOSED_HEIGHT:
			return "Closed height";
		case SkinItem.LANGUAGE_COLORS:
			return "Language colors";
		case SkinItem.CARD_LAYOUT:
			return "Card layout";
		case SkinItem.SURFACE:
			return "Surface";
		case SkinItem.IMAGE:
			return "Image";
		case SkinItem.FIT:
			return "Fit";
		case SkinItem.OPACITY:
			return "Opacity";
		case SkinItem.TINT:
			return "Tint";
		case SkinItem.SCRIM:
			return "Scrim";
		case SkinItem.SPEED:
			return "Speed";
		case SkinItem.FPS:
			return "FPS";
		case SkinItem.RELOAD:
			return "Reload skin";
		case SkinItem.RESET:
			return "Reset skin page";
		case SkinItem.COUNT:
			return "";
	}
}

fn String skin_item_key(SkinItem item)
{
	switch (item)
	{
		case SkinItem.PRESET:
			return "skin_preset";
		case SkinItem.CARD_STYLE:
			return "skin_card_style";
		case SkinItem.FOLDER_STYLE:
			return "skin_folder_style";
		case SkinItem.CLOSED_HEIGHT:
			return "skin_closed_height";
		case SkinItem.LANGUAGE_COLORS:
			return "skin_language_colors";
		case SkinItem.CARD_LAYOUT:
			return "canvas_card_layout";
		case SkinItem.SURFACE:
			return "skin_surface";
		case SkinItem.IMAGE:
			return "skin_surface_image";
		case SkinItem.FIT:
			return "skin_surface_fit";
		case SkinItem.OPACITY:
			return "skin_surface_opacity";
		case SkinItem.TINT:
			return "skin_surface_tint";
		case SkinItem.SCRIM:
			return "skin_surface_scrim";
		case SkinItem.SPEED:
			return "skin_surface_speed";
		case SkinItem.FPS:
			return "skin_surface_fps";
		case SkinItem.RELOAD:
			return "skin_reload";
		case SkinItem.RESET:
			return "skin_reset";
		case SkinItem.COUNT:
			return "";
	}
}

fn String skin_item_description(SkinItem item)
{
	switch (item)
	{
		case SkinItem.PRESET:
			return "Classic, paper, or glass preset. Explicit fields below override the preset.";
		case SkinItem.CARD_STYLE:
			return "Flat, paper, and glass card fills are rendered.";
		case SkinItem.FOLDER_STYLE:
			return "Classic, explorer, and stacked tray folder styles are rendered.";
		case SkinItem.CLOSED_HEIGHT:
			return "Height of closed file cards in pixels (40-240).";
		case SkinItem.LANGUAGE_COLORS:
			return "Tint card accents by the file language.";
		case SkinItem.CARD_LAYOUT:
			return "Arrange cards as a grid, a cascading deck, or a fanned deck.";
		case SkinItem.SURFACE:
			return "Choose which UI surface the fields below edit.";
		case SkinItem.IMAGE:
			return "Relative paths resolve from the config folder. Drop a PNG, JPG, GIF, or BMP here.";
		case SkinItem.FIT:
			return "How the image fills the surface: cover, contain, stretch, or tile.";
		case SkinItem.OPACITY:
			return "Surface image opacity (0-1).";
		case SkinItem.TINT:
			return "Tint colour as #rrggbb or #rrggbbaa.";
		case SkinItem.SCRIM:
			return "Overlay colour as #rrggbb or #rrggbbaa.";
		case SkinItem.SPEED:
			return "Animation speed multiplier (0 stops animated images).";
		case SkinItem.FPS:
			return "Frame rate for animated images.";
		case SkinItem.RELOAD:
			return "Re-read the global and project skin sections from disk.";
		case SkinItem.RESET:
			return "Clear every skin override in the current scope.";
		case SkinItem.COUNT:
			return "";
	}
}

fn bool skin_item_is_text(SkinItem item)
{
	return item == SkinItem.IMAGE || item == SkinItem.TINT || item == SkinItem.SCRIM;
}

fn bool image_path_supported(String path)
{
	usz dot  = 0;
	bool has = false;
	for (usz i = 0; i < path.len; i++)
	{
		if (path[i] == '.')
		{
			dot = i;
			has = true;
		}
	}
	if (!has) return false;
	String ext = path[dot:path.len - dot];
	return ext.compare_to_ignore_case(
		".png"
	) == 0 || ext.compare_to_ignore_case(
		".jpg"
	) == 0 || ext.compare_to_ignore_case(
		".jpeg"
	) == 0 || ext.compare_to_ignore_case(".gif") == 0 || ext.compare_to_ignore_case(".bmp") == 0;
}

fn int skin_field_for(SkinItem item)
{
	switch (item)
	{
		case SkinItem.IMAGE:
			return (int)skin::SurfaceField.IMAGE;
		case SkinItem.FIT:
			return (int)skin::SurfaceField.FIT;
		case SkinItem.OPACITY:
			return (int)skin::SurfaceField.OPACITY;
		case SkinItem.TINT:
			return (int)skin::SurfaceField.TINT;
		case SkinItem.SCRIM:
			return (int)skin::SurfaceField.SCRIM;
		case SkinItem.SPEED:
			return (int)skin::SurfaceField.SPEED;
		case SkinItem.FPS:
			return (int)skin::SurfaceField.FPS;
		default:
			return -1;
	}
}

fn bool skin_item_matches(SkinItem item, String query)
{
	return matches("skin", skin_item_label(item), skin_item_key(item), skin_item_description(item), query);
}

fn void Panel.push_skin_rows(&self, String group, SkinItem[] items, String query)
{
	bool wrote_header = false;
	foreach (SkinItem item : items)
	{
		if (!skin_item_matches(item, query)) continue;
		if (!wrote_header)
		{
			self.rows.push({ .kind = RowKind.HEADER, .section = group, .page = settings::SettingPage.SKIN });
			wrote_header = true;
		}
		self.rows.push(
			{
				.kind = RowKind.SKIN,
				.skin = item,
				.section = group,
				.page = settings::SettingPage.SKIN,
			}
		);
	}
}

fn void Panel.build_skin_rows(&self, String query)
{
	self.push_skin_rows("Style", SKIN_STYLE_ITEMS, query);
	self.push_skin_rows("Surface", SKIN_SURFACE_ITEMS, query);
	self.push_skin_rows("Actions", SKIN_ACTION_ITEMS, query);
}

fn void Panel.rebuild(&self)
{
	self.rows.clear();
	String query = self.query_view();
	if (self.page == settings::SettingPage.KEYS)
	{
		self.build_key_rows(query);
		self.layout_keys(self.grid_columns());
	}
	else if (self.page == settings::SettingPage.SKIN)
	{
		self.build_skin_rows(query);
	}
	else if (query.len == 0)
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
						.section = commands::command_group((commands::CommandId)i),
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

fn int Panel.selected_skin(&self)
{
	int index = self.selected_row();
	if (index < 0 || self.rows[index].kind != RowKind.SKIN) return -1;
	return (int)self.rows[index].skin;
}

fn int Panel.skin_row(&self, SkinItem item)
{
	for (int i = 0; i < (int)self.rows.len(); i++)
	{
		if (self.rows[i].kind == RowKind.SKIN && self.rows[i].skin == item) return i;
	}
	return -1;
}

fn settings::SettingLayer Panel.skin_source(&self, SkinItem item, config::Config* config)
{
	switch (item)
	{
		case SkinItem.PRESET:
			return skin::preset_source();
		case SkinItem.CARD_STYLE:
			return skin::card_style_source();
		case SkinItem.FOLDER_STYLE:
			return skin::folder_style_source();
		case SkinItem.CLOSED_HEIGHT:
			return skin::closed_height_source();
		case SkinItem.LANGUAGE_COLORS:
			return skin::language_colors_source();
		case SkinItem.CARD_LAYOUT:
			if (config == null) return settings::SettingLayer.DEFAULT;
			return config.settings.source(settings::SettingId.CANVAS_CARD_LAYOUT);
		case SkinItem.SURFACE:
			return skin::surface_source_any(self.skin_surface);
		case SkinItem.IMAGE:
		case SkinItem.FIT:
		case SkinItem.OPACITY:
		case SkinItem.TINT:
		case SkinItem.SCRIM:
		case SkinItem.SPEED:
		case SkinItem.FPS:

			{
				int field = skin_field_for(item);
				if (field < 0) return settings::SettingLayer.DEFAULT;
				return skin::surface_source(self.skin_surface, (skin::SurfaceField)field);
			}
		case SkinItem.RELOAD:
		case SkinItem.RESET:
		case SkinItem.COUNT:
			return settings::SettingLayer.DEFAULT;
	}
}

fn void Panel.skin_value_text(&self, DString* out, SkinItem item, config::Config* config)
{
	skin::SurfaceConfig surface = skin::surface(self.skin_surface);
	switch (item)
	{
		case SkinItem.PRESET:
			out.append_string(skin::preset());
		case SkinItem.CARD_STYLE:
			out.append_string(skin::card_style_name(skin::card_style()));
		case SkinItem.FOLDER_STYLE:
			out.append_string(skin::folder_style_name(skin::folder_style()));
		case SkinItem.CLOSED_HEIGHT:
			(void)out.appendf("%.0f", (double)skin::closed_height());
		case SkinItem.LANGUAGE_COLORS:
			out.append_string(skin::language_colors() ? "On" : "Off");
		case SkinItem.CARD_LAYOUT:
			if (config != null) out.append_string(config.settings.get_string(settings::SettingId.CANVAS_CARD_LAYOUT));
		case SkinItem.SURFACE:
			out.append_string(skin::surface_name(self.skin_surface));
		case SkinItem.IMAGE:
			if (surface.image.len > 0)
			{
				out.append_string(surface.image);
			}
			else
			{
				out.append_string("(none)");
			}
		case SkinItem.FIT:
			out.append_string(skin::fit_name(surface.fit));
		case SkinItem.OPACITY:
			(void)out.appendf("%.2f", (double)surface.opacity);
		case SkinItem.TINT:
			skin::append_color(out, surface.tint);
		case SkinItem.SCRIM:
			skin::append_color(out, surface.scrim);
		case SkinItem.SPEED:
			(void)out.appendf("%.2f", (double)surface.speed);
		case SkinItem.FPS:
			(void)out.appendf("%.0f", (double)surface.fps);
		case SkinItem.RELOAD:
			out.append_string("Enter");
		case SkinItem.RESET:
			out.append_string("Enter");
		case SkinItem.COUNT:
			break;
	}
}

fn void Panel.start_skin_edit(&self, config::Config* config)
{
	int index = self.selected_skin();
	if (index < 0) return;
	SkinItem item = (SkinItem)index;
	if (!skin_item_is_text(item)) return;
	DString text;
	text.init(tmem, 64);
	skin::SurfaceConfig surface = skin::surface(self.skin_surface);
	if (item == SkinItem.IMAGE) text.append_string(surface.image);
	if (item == SkinItem.TINT) skin::append_color(&text, surface.tint);
	if (item == SkinItem.SCRIM) skin::append_color(&text, surface.scrim);
	String value = text.str_view();
	usz count    = value.len;
	if (count > (usz)SKIN_EDIT_MAX) count = (usz)SKIN_EDIT_MAX;
	for (usz i = 0; i < count; i++) self.skin_edit_buf[i] = value[i];
	self.skin_edit_len = (int)count;
	self.skin_edit_buf[self.skin_edit_len] = 0;
	self.skin_edit_item = item;
	self.skin_editing = true;
	self.editing = false;
	text.free();
}

fn bool Panel.commit_skin_edit(
	&self,
	config::Config* config,
	bool project_open,
	String project_root,
	notify::Notifier* notifier
)
{
	if (!self.skin_editing) return false;
	if (config == null) return false;
	SkinItem item                = self.skin_edit_item;
	String value                 = (String)self.skin_edit_buf[0:self.skin_edit_len];
	settings::SettingLayer layer = self.scope;
	if (!project_open) layer = settings::SettingLayer.GLOBAL;
	if (item == SkinItem.IMAGE)
	{
		skin::set_surface_image(self.skin_surface, value, layer);
	}
	else if (item == SkinItem.TINT || item == SkinItem.SCRIM)
	{
		if (value.len == 0)
		{
			skin::clear_surface_field(
				self.skin_surface,
				item == SkinItem.TINT ? skin::SurfaceField.TINT : skin::SurfaceField.SCRIM,
				layer
			);
		}
		else if (!skin::color_valid(value))
		{
			if (notifier != null) notifier.push("Use #rrggbb or #rrggbbaa");
			return false;
		}
		else if (item == SkinItem.TINT)
		{
			skin::set_surface_tint(self.skin_surface, skin::parse_color(value, { 255, 255, 255, 255 }), layer);
		}
		else
		{
			skin::set_surface_scrim(self.skin_surface, skin::parse_color(value, { 0, 0, 0, 0 }), layer);
		}
	}
	else
	{
		return false;
	}
	self.skin_editing = false;
	self.persist(config, project_open, project_root);
	return true;
}

fn void Panel.change_skin(
	&self,
	config::Config* config,
	int dir,
	bool project_open,
	String project_root,
	notify::Notifier* notifier
)
{
	if (dir == 0) return;
	int index = self.selected_skin();
	if (index < 0) return;
	SkinItem item = (SkinItem)index;
	if (skin_item_is_text(item))
	{
		self.start_skin_edit(config);
		return;
	}
	settings::SettingLayer layer = self.scope;
	if (!project_open) layer = settings::SettingLayer.GLOBAL;
	switch (item)
	{
		case SkinItem.PRESET:
			skin::set_preset(enum_next(skin::PRESET_NAMES, skin::preset(), dir), layer);
		case SkinItem.CARD_STYLE:
			skin::set_card_style(
				skin::card_style_for_name(
					enum_next(skin::CARD_STYLE_NAMES, skin::card_style_name(skin::card_style()), dir)
				),
				layer
			);
		case SkinItem.FOLDER_STYLE:
			skin::set_folder_style(
				skin::folder_style_for_name(
					enum_next(skin::FOLDER_STYLE_NAMES, skin::folder_style_name(skin::folder_style()), dir)
				),
				layer
			);
		case SkinItem.CLOSED_HEIGHT:
			skin::set_closed_height(
				math::clamp(skin::closed_height() + (float)dir * SKIN_CLOSED_STEP, 40.0f, 240.0f),
				layer
			);
		case SkinItem.LANGUAGE_COLORS:
			skin::set_language_colors(!skin::language_colors(), layer);
		case SkinItem.CARD_LAYOUT:
			if (config == null) return;
			config.settings.set_string(
				settings::SettingId.CANVAS_CARD_LAYOUT,
				enum_next(
					settings::setting_options(settings::SettingId.CANVAS_CARD_LAYOUT),
					config.settings.get_string(settings::SettingId.CANVAS_CARD_LAYOUT),
					dir
				),
				layer
			);
		case SkinItem.SURFACE:

			{
				int count = (int)skin::SurfaceId.COUNT;
				int next  = ((int)self.skin_surface + dir + count) % count;
				self.skin_surface = (skin::SurfaceId)next;
				return;
			}
		case SkinItem.IMAGE:
		case SkinItem.TINT:
		case SkinItem.SCRIM:
			self.start_skin_edit(config);
			return;
		case SkinItem.FIT:

			{
				skin::SurfaceConfig surface = skin::surface(self.skin_surface);
				skin::set_surface_fit(
					self.skin_surface,
					skin::fit_for_name(enum_next(skin::FIT_NAMES, skin::fit_name(surface.fit), dir)),
					layer
				);
				break;
			}
		case SkinItem.OPACITY:

			{
				skin::SurfaceConfig surface = skin::surface(self.skin_surface);
				skin::set_surface_opacity(
					self.skin_surface,
					math::clamp(surface.opacity + (float)dir * SKIN_OPACITY_STEP, 0.0f, 1.0f),
					layer
				);
				break;
			}
		case SkinItem.SPEED:

			{
				skin::SurfaceConfig surface = skin::surface(self.skin_surface);
				skin::set_surface_speed(
					self.skin_surface,
					math::clamp(surface.speed + (float)dir * SKIN_SPEED_STEP, 0.0f, 10.0f),
					layer
				);
				break;
			}
		case SkinItem.FPS:

			{
				skin::SurfaceConfig surface = skin::surface(self.skin_surface);
				skin::set_surface_fps(
					self.skin_surface,
					math::clamp(surface.fps + (float)dir * SKIN_FPS_STEP, 1.0f, 120.0f),
					layer
				);
				break;
			}
		case SkinItem.RELOAD:
			if (config == null) return;
			config.reload_skin(project_root);
			if (notifier != null) notifier.push("Skin reloaded");
			return;
		case SkinItem.RESET:
			skin::clear_layer(layer);
			self.persist(config, project_open, project_root);
			if (notifier != null) notifier.push("Skin reset");
			return;
		case SkinItem.COUNT:
			return;
	}
	self.persist(config, project_open, project_root);
}

fn void Panel.activate_skin(
	&self,
	config::Config* config,
	bool project_open,
	String project_root,
	notify::Notifier* notifier
)
{
	int index = self.selected_skin();
	if (index < 0) return;
	if (skin_item_is_text((SkinItem)index))
	{
		self.start_skin_edit(config);
		return;
	}
	self.change_skin(config, 1, project_open, project_root, notifier);
}

fn void Panel.reset_skin_selected(
	&self,
	config::Config* config,
	bool project_open,
	String project_root,
	notify::Notifier* notifier
)
{
	int index = self.selected_skin();
	if (index < 0) return;
	SkinItem item                = (SkinItem)index;
	settings::SettingLayer layer = self.scope;
	if (!project_open) layer = settings::SettingLayer.GLOBAL;
	switch (item)
	{
		case SkinItem.PRESET:
			skin::clear_preset(layer);
		case SkinItem.CARD_STYLE:
			skin::clear_card_style(layer);
		case SkinItem.FOLDER_STYLE:
			skin::clear_folder_style(layer);
		case SkinItem.CLOSED_HEIGHT:
			skin::clear_closed_height(layer);
		case SkinItem.LANGUAGE_COLORS:
			skin::clear_language_colors(layer);
		case SkinItem.CARD_LAYOUT:
			if (config == null) return;
			config.settings.clear(settings::SettingId.CANVAS_CARD_LAYOUT, layer);
		case SkinItem.SURFACE:
			skin::clear_surface(self.skin_surface, layer);
		case SkinItem.IMAGE:
		case SkinItem.FIT:
		case SkinItem.OPACITY:
		case SkinItem.TINT:
		case SkinItem.SCRIM:
		case SkinItem.SPEED:
		case SkinItem.FPS:

			{
				int field = skin_field_for(item);
				if (field < 0) return;
				skin::clear_surface_field(self.skin_surface, (skin::SurfaceField)field, layer);
			}
		case SkinItem.RELOAD:
			return;
		case SkinItem.RESET:
			skin::clear_layer(layer);
		case SkinItem.COUNT:
			return;
	}
	self.persist(config, project_open, project_root);
	if (notifier != null) notifier.push("Skin override cleared");
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

fn void Panel.clamp_key_scroll_bounds(&self)
{
	float view       = self.keys_view_height();
	float max_scroll = self.key_content_height - view;
	if (max_scroll < 0.0f) max_scroll = 0.0f;
	if ((float)self.key_scroll > max_scroll) self.key_scroll = (int)max_scroll;
	if (self.key_scroll < 0) self.key_scroll = 0;
}

fn void Panel.reveal_selected(&self)
{
	int index = self.selected_row();
	if (index < 0) return;
	float top    = self.rows[index].grid_y;
	float bottom = top + row_grid_height(self.rows[index].kind);
	float view   = self.keys_view_height();
	if (top < (float)self.key_scroll)
	{
		self.key_scroll = (int)top;
	}
	else if (bottom > (float)self.key_scroll + view)
	{
		self.key_scroll = (int)(bottom - view);
	}
}

fn void Panel.clamp_scroll(&self)
{
	if (self.page == settings::SettingPage.KEYS)
	{
		self.clamp_key_scroll_bounds();
		self.reveal_selected();
		return;
	}
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

fn void Panel.move_keys_horizontal(&self, int dir)
{
	int rows = (int)self.rows.len();
	if (rows == 0 || dir == 0) return;
	int step    = dir > 0 ? 1 : -1;
	int current = self.selected;
	if (current < 0 || current >= rows) current = dir > 0 ? -1 : rows;
	for (int guard = 0; guard < rows; guard++)
	{
		current += step;
		if (current < 0) current = rows - 1;
		if (current >= rows) current = 0;
		if (self.rows[current].kind == RowKind.COMMAND)
		{
			self.selected = current;
			self.clamp_scroll();
			return;
		}
	}
}

fn int Panel.key_vertical_target(&self, int dir)
{
	int current = self.selected_row();
	if (current < 0) return -1;
	float y       =  self.rows[current].grid_y;
	int col       =  self.rows[current].grid_col;
	int best      = -1;
	float best_dy =  0.0f;
	int best_dx   =  0;
	for (int i = 0; i < (int)self.rows.len(); i++)
	{
		if (i == current) continue;
		if (self.rows[i].kind == RowKind.HEADER) continue;
		float dy = self.rows[i].grid_y - y;
		if (dir > 0 && dy <= 0.5f) continue;
		if (dir < 0 && dy >= -0.5f) continue;
		float ady = dy < 0.0f ? -dy : dy;
		int dx    = self.rows[i].grid_col - col;
		if (dx < 0) dx = -dx;
		if (best < 0 || ady < best_dy - 0.5f || ((ady - best_dy <= 0.5f && best_dy - ady <= 0.5f) && dx < best_dx))
		{
			best = i;
			best_dy = ady;
			best_dx = dx;
		}
	}
	return best;
}

fn void Panel.move_keys_vertical(&self, int dir)
{
	int target = self.key_vertical_target(dir);
	if (target < 0) return;
	self.selected = target;
	self.clamp_scroll();
}

fn void Panel.move_keys_page(&self, int dir)
{
	float page = self.keys_view_height();
	int steps  = (int)(page / ((float)ui::px(CARD_HEIGHT + CARD_GAP)));
	if (steps < 1) steps = 1;
	for (int i = 0; i < steps; i++) self.move_keys_vertical(dir);
}

fn void Panel.move_keys_edge(&self, bool end)
{
	if (end)
	{
		for (int i = (int)self.rows.len() - 1; i >= 0; i--)
		{
			if (self.rows[i].kind != RowKind.COMMAND) continue;
			self.selected = i;
			self.clamp_scroll();
			return;
		}
		return;
	}
	for (int i = 0; i < (int)self.rows.len(); i++)
	{
		if (self.rows[i].kind != RowKind.COMMAND) continue;
		self.selected = i;
		self.clamp_scroll();
		return;
	}
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
	self.rebuild();
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
	self.rebuild();
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
	self.rebuild();
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
	self.rebuild();
	notifier.push("Keybindings reset");
}

fn Rect Panel.outer_rect(&self)
{
	Rect content = topbar::content_rect();
	float width  = math::min((float)ui::px(PANEL_WIDTH), content.width - (float)ui::px(40));
	float y      = content.y + (float)ui::px(18);
	float height = math::min((float)ui::px(700), content.y + content.height - y - (float)ui::px(24));
	return {
		.x = content.x + (content.width - width) / 2.0f,
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

fn float Panel.keys_list_top(&self)
{
	return self.list_y() + (float)ui::px(KEY_FILTER_HEIGHT + KEY_FILTER_GAP);
}

fn float Panel.keys_view_height(&self)
{
	Rect panel   = self.panel_rect();
	float footer = panel.y + panel.height - (float)ui::px(FOOTER_HEIGHT);
	float height = footer - self.keys_list_top();
	return height > 1.0f ? height : 1.0f;
}

fn float measure_text(RLFont font, String text, float size)
{
	if (text.len == 0) return 0.0f;
	float width = 0.0f;
	@pool()
	{
		width = rl::measure_text_ex(font, text.zstr_tcopy(), size, 0.0f)[0];
	};
	return width;
}

fn Rect Panel.filter_rect(&self, int filter)
{
	Rect panel = self.panel_rect();
	float x    = panel.x + (float)ui::px(PADDING);
	float y    = self.list_y();
	float gap  = (float)ui::px(6);
	float size = (float)ui::tpx(14);
	for (int i = 0; i < filter; i++)
	{
		float width = measure_text(ui::font(), KEY_FILTER_LABELS[i], size) + (float)ui::px(20);
		x += width + gap;
	}
	float width = measure_text(ui::font(), KEY_FILTER_LABELS[filter], size) + (float)ui::px(20);
	return { .x = x, .y = y, .width = width, .height = (float)ui::px(KEY_FILTER_HEIGHT) };
}

fn int Panel.filter_at(&self, RLVector2 mouse)
{
	for (int i = 0; i < (int)KEY_FILTER_LABELS.len; i++)
	{
		if (ui::pointer_in(self.filter_rect(i), mouse)) return i;
	}
	return -1;
}

fn Rect Panel.key_rect(&self, int index)
{
	Rect panel = self.panel_rect();
	if (index < 0 || index >= (int)self.rows.len()) return { .x = panel.x, .y = panel.y };
	Row row     = self.rows[index];
	float top   = self.keys_list_top() + row.grid_y - (float)self.key_scroll;
	float width = panel.width - (float)ui::px(PADDING * 2);
	if (row.kind == RowKind.HEADER)
	{
		return {
			.x = panel.x + (float)ui::px(PADDING),
			.y = top,
			.width = width,
			.height = (float)ui::px(HEADER_HEIGHT),
		};
	}
	if (row.kind == RowKind.ACTION)
	{
		return {
			.x = panel.x + (float)ui::px(PADDING),
			.y = top,
			.width = width,
			.height = (float)ui::px(KEY_ACTION_HEIGHT),
		};
	}
	int columns = self.key_columns > 0 ? self.key_columns : 1;
	float gap   = (float)ui::px(CARD_GAP);
	float card  = (width - gap * (float)(columns - 1)) / (float)columns;
	return {
		.x = panel.x + (float)ui::px(PADDING) + (card + gap) * (float)row.grid_col,
		.y = top,
		.width = card,
		.height = (float)ui::px(CARD_HEIGHT),
	};
}

fn String Panel.key_chip_text(&self, commands::CommandId id, keymap::Keymap* keymap)
{
	if (self.capturing && (int)id == (int)self.capture_id) return "Press a chord...";
	String text = keymap != null ? keymap.shortcut(id) : commands::command_def(id).shortcut;
	if (text.len == 0) return "(unbound)";
	return text;
}

fn Rect Panel.key_chip_rect(&self, int index, keymap::Keymap* keymap)
{
	Rect card = self.key_rect(index);
	if (index < 0 || index >= (int)self.rows.len()) return card;
	if (self.rows[index].kind != RowKind.COMMAND) return card;
	String text = self.key_chip_text(self.rows[index].command, keymap);
	float size  = (float)ui::tpx(15);
	float width = measure_text(ui::font(), text, size) + (float)ui::px(16);
	if (width < (float)ui::px(54)) width = (float)ui::px(54);
	float max_width = card.width - (float)ui::px(20);
	if (width > max_width) width = max_width;
	return {
		.x = card.x + (float)ui::px(10),
		.y = card.y + (float)ui::px(44),
		.width = width,
		.height = (float)ui::px(KEY_CHIP_HEIGHT),
	};
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
	self.key_filter = KeyFilter.ALL;
	self.key_scroll = 0;
	self.rebuild();
}

fn int Panel.key_row_at(&self, RLVector2 mouse)
{
	Rect panel  = self.panel_rect();
	float top   = self.keys_list_top();
	float limit = panel.y + panel.height - (float)ui::px(FOOTER_HEIGHT);
	if (mouse[1] < top || mouse[1] > limit) return -1;
	for (int i = 0; i < (int)self.rows.len(); i++)
	{
		if (self.rows[i].kind == RowKind.HEADER) continue;
		if (ui::pointer_in(self.key_rect(i), mouse)) return i;
	}
	return -1;
}

fn int Panel.row_at(&self, RLVector2 mouse)
{
	Rect panel = self.panel_rect();
	if (mouse[0] < panel.x || mouse[0] > panel.x + panel.width) return -1;
	if (self.page == settings::SettingPage.KEYS) return self.key_row_at(mouse);
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
	self.key_scroll = 0;
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
	else if (self.page == settings::SettingPage.SKIN)
	{
		skin::clear_layer(self.scope);
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
	self.set_sources(keymap, config);
	if (self.page == settings::SettingPage.KEYS)
	{
		int columns = self.grid_columns();
		if (columns != self.key_columns)
		{
			self.layout_keys(columns);
			self.clamp_scroll();
		}
	}

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

	if (self.skin_editing)
	{
		self.consumed = true;
		if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
		{
			self.skin_editing = false;
			return;
		}
		if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER))
		{
			(void)self.commit_skin_edit(config, project_open, project_root, notifier);
			return;
		}
		if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
		{
			if (self.skin_edit_len > 0)
			{
				self.skin_edit_len--;
				self.skin_edit_buf[self.skin_edit_len] = 0;
			}
		}
		int skin_codepoint = rl::get_char_pressed();
		while (skin_codepoint != 0)
		{
			if (skin_codepoint >= 32 && skin_codepoint <= 126 && self.skin_edit_len < SKIN_EDIT_MAX)
			{
				self.skin_edit_buf[self.skin_edit_len] = (char)skin_codepoint;
				self.skin_edit_len++;
				self.skin_edit_buf[self.skin_edit_len] = 0;
			}
			skin_codepoint = rl::get_char_pressed();
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

	if (self.page == settings::SettingPage.SKIN && rl::is_file_dropped())
	{
		self.consumed = true;
		RLFilePathList files = rl::load_dropped_files();
		bool applied         = false;
		for (uint i = 0; i < files.count; i++)
		{
			if (!rl::is_path_file(files.paths[i])) continue;
			String path = files.paths[i].str_view();
			if (!image_path_supported(path)) continue;
			settings::SettingLayer layer = self.scope;
			if (!project_open) layer = settings::SettingLayer.GLOBAL;
			skin::set_surface_image(self.skin_surface, path, layer);
			applied = true;
			break;
		}
		rl::unload_dropped_files(files);
		if (applied)
		{
			self.persist(config, project_open, project_root);
			if (notifier != null) notifier.push("Skin image updated");
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

	bool keys_page = self.page == settings::SettingPage.KEYS;
	bool skin_page = self.page == settings::SettingPage.SKIN;
	if (keys_page)
	{
		if (keymap.pressed_repeat((int)commands::CommandId.LIST_DOWN, commands::CTX_SETTINGS))
		{
			self.consumed = true;
			self.move_keys_vertical(1);
		}
		if (keymap.pressed_repeat((int)commands::CommandId.LIST_UP, commands::CTX_SETTINGS))
		{
			self.consumed = true;
			self.move_keys_vertical(-1);
		}
		if (keymap.pressed_repeat((int)commands::CommandId.SETTINGS_VALUE_DEC, commands::CTX_SETTINGS))
		{
			self.consumed = true;
			self.move_keys_horizontal(-1);
		}
		if (keymap.pressed_repeat((int)commands::CommandId.SETTINGS_VALUE_INC, commands::CTX_SETTINGS))
		{
			self.consumed = true;
			self.move_keys_horizontal(1);
		}
		if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_UP))
		{
			self.consumed = true;
			self.move_keys_page(-1);
		}
		if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_DOWN))
		{
			self.consumed = true;
			self.move_keys_page(1);
		}
		if (rl::is_key_pressed(rl::RLKeyboardKey.HOME))
		{
			self.consumed = true;
			self.move_keys_edge(false);
		}
		if (rl::is_key_pressed(rl::RLKeyboardKey.END))
		{
			self.consumed = true;
			self.move_keys_edge(true);
		}
	}
	else
	{
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
				case RowKind.SKIN:
					self.reset_skin_selected(config, project_open, project_root, notifier);
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
				case RowKind.SKIN:
					self.activate_skin(config, project_open, project_root, notifier);
				default:
					break;
			}
		}
	}

	if (!keys_page)
	{
		int dir = 0;
		if (keymap.pressed_repeat((int)commands::CommandId.SETTINGS_VALUE_DEC, commands::CTX_SETTINGS)) dir = -1;
		if (keymap.pressed_repeat((int)commands::CommandId.SETTINGS_VALUE_INC, commands::CTX_SETTINGS)) dir = 1;
		if (dir != 0)
		{
			self.consumed = true;
			if (skin_page)
			{
				self.change_skin(config, dir, project_open, project_root, notifier);
			}
			else
			{
				self.change_selected(config, dir, project_open, project_root);
			}
		}
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
		if (keys_page)
		{
			int filter = self.filter_at(mouse);
			if (filter >= 0)
			{
				self.consumed = true;
				self.set_key_filter((KeyFilter)filter);
				return;
			}
		}
	}

	if (mouse[0] < panel.x)
	{
		return;
	}

	float wheel = rl::get_mouse_wheel_move();
	if (keys_page)
	{
		if (wheel > 0.0f || wheel < 0.0f)
		{
			self.key_scroll -= (int)(wheel * (float)ui::px(CARD_HEIGHT));
			self.clamp_key_scroll_bounds();
		}
	}
	else
	{
		if (wheel > 0.0f) self.move_selection(-1);
		if (wheel < 0.0f) self.move_selection(1);
	}

	int row = self.row_at(mouse);
	if (row >= 0 && self.rows[row].kind != RowKind.HEADER)
	{
		if (row != self.selected)
		{
			self.selected = row;
			self.clamp_scroll();
		}
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
		{
			if (keys_page)
			{
				switch (self.rows[row].kind)
				{
					case RowKind.COMMAND:
						if (ui::pointer_in(self.key_chip_rect(row, keymap), mouse))
						{
							self.start_capture(self.rows[row].command);
						}
					case RowKind.ACTION:
						self.reset_all(keymap, config, project_open, project_root, notifier);
					default:
						break;
				}
			}
			else if (skin_page)
			{
				float value_x = panel.x + panel.width - 260.0f;
				if (mouse[0] >= value_x && self.rows[row].kind == RowKind.SKIN)
				{
					self.activate_skin(config, project_open, project_root, notifier);
				}
				else
				{
					self.selected = row;
				}
			}
			else
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

fn void draw_text_clipped(RLFont font, String text, float x, float y, float size, float max_width, RLColor color)
{
	if (text.len == 0) return;
	if (measure_text(font, text, size) <= max_width)
	{
		draw_text(font, text, x, y, size, color);
		return;
	}
	@pool()
	{
		float ellipsis_width = measure_text(font, "...", size);
		usz fit              = 0;
		for (usz i = 1; i <= text.len; i++)
		{
			if (measure_text(font, text[0:i], size) + ellipsis_width > max_width) break;
			fit = i;
		}
		DString out;
		out.init(tmem, (sz)(fit + 4));
		out.append_bytes(text.ptr[0:fit]);
		out.append_string("...");
		rl::draw_text_ex(font, out.str_view().zstr_tcopy(), { x, y }, size, 0.0f, color);
		out.free();
	};
}

fn String Panel.binding_source(&self, commands::CommandId id, config::Config* config)
{
	if (config == null) return "default";
	String chord;
	settings::SettingLayer layer;
	if (!config.keymap_override(commands::command_name(id), &chord, &layer)) return "default";
	return layer == settings::SettingLayer.PROJECT ? "project" : "global";
}

fn String Panel.key_empty_title(&self)
{
	if (self.query_len > 0) return "No matching keybindings";
	switch (self.key_filter)
	{
		case KeyFilter.CONFLICTS:
			return "No shortcut conflicts";
		case KeyFilter.MODIFIED:
			return "No modified bindings";
		case KeyFilter.UNBOUND:
			return "No unbound commands";
		case KeyFilter.ALL:
		case KeyFilter.COUNT:
			return "No keybindings";
	}
}

fn String Panel.key_empty_hint(&self)
{
	if (self.query_len > 0) return "Try another search or filter.";
	switch (self.key_filter)
	{
		case KeyFilter.CONFLICTS:
			return "Every shortcut is unique in its context.";
		case KeyFilter.MODIFIED:
			return "Every shortcut is at its default.";
		case KeyFilter.UNBOUND:
			return "Every command has a shortcut.";
		case KeyFilter.ALL:
		case KeyFilter.COUNT:
			return "";
	}
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
		case settings::SettingPage.SKIN:
			return icons::IconKind.THEME;
		case settings::SettingPage.COUNT:
			return icons::IconKind.SETTINGS;
	}
}

fn void Panel.draw_key_filters(&self, RLFont font)
{
	for (int i = 0; i < (int)KEY_FILTER_LABELS.len; i++)
	{
		Rect r                 = self.filter_rect(i);
		bool active            = (int)self.key_filter == i;
		ui::ControlState state = ui::control_state(r, true, active);
		ui::rounded_rect(r, ui::row_radius(), ui::control_fill(state, active ? theme::current()
			.panel_selected : theme::current()
				.panel_field, theme::current()
					.topbar_hover, theme::current().panel_selected, theme::current().panel_bg_alt));
		draw_text(
			font,
			key_filter_label((KeyFilter)i),
			r.x + (float)ui::px(10),
			r.y + (float)ui::px(6),
			(float)ui::tpx(14),
			active ? theme::current()
			.panel_text : theme::current().panel_dim);
	}
}

fn void Panel.draw_key_card(
	&self,
	RLFont font,
	Rect card,
	int index,
	bool selected,
	bool hovered,
	bool pressed,
	keymap::Keymap* keymap,
	config::Config* config
)
{
	Row row                = self.rows[index];
	commands::CommandId id = row.command;
	RLColor fill           = theme::current().panel_field;
	if (selected)
	{
		fill = theme::current().panel_bg_alt;
	}
	else if (hovered)
	{
		fill = pressed ? theme::current().panel_selected : theme::current().topbar_hover;
		if (pressed) fill[3] = 80;
	}
	ui::rounded_rect(card, ui::row_radius(), fill);
	ui::rounded_rect_lines(card, ui::row_radius(), selected ? 2.0f : 1.0f, selected ? theme::current()
		.card_focus : theme::current().panel_border);

	String source      = self.binding_source(id, config);
	float source_size  = (float)ui::tpx(13);
	float source_width = measure_text(font, source, source_size);
	float pad          = (float)ui::px(10);
	draw_text(
		font,
		source,
		card.x + card.width - pad - source_width,
		card.y + (float)ui::px(8),
		source_size,
		source.compare_to("default") == 0 ? theme::current()
		.panel_dim : theme::current().panel_header);
	draw_text_clipped(font, commands::command_def(id)
		.label, card.x + pad, card.y + (float)ui::px(
			5
		), (float)ui::tpx(19), card.width - pad * 2.0f - source_width - (float)ui::px(8), theme::current()
			.panel_text);
	draw_text_clipped(
		font,
		commands::command_description(id),
		card.x + pad,
		card.y + (float)ui::px(26),
		(float)ui::tpx(14),
		card.width - pad * 2.0f,
		theme::current()
		.panel_dim);

	Rect chip         = self.key_chip_rect(index, keymap);
	bool capturing    = self.capturing && (int)id == (int)self.capture_id;
	bool unbound      = !capturing && keymap != null && keymap.shortcut(id).len == 0;
	RLColor chip_text = capturing ? theme::current()
		.panel_match : (unbound ? theme::current().panel_dim : theme::current().panel_text);
	ui::rounded_rect(chip, ui::row_radius(), theme::current().panel_bg_alt);
	draw_text(
		font,
		self.key_chip_text(id, keymap),
		chip.x + (float)ui::px(8),
		chip.y + (chip.height - (float)ui::tpx(15)) * 0.5f,
		(float)ui::tpx(15),
		chip_text
	);

	if (self.command_conflict(id))
	{
		String marker     = "conflict";
		float marker_size = (float)ui::tpx(12);
		float marker_w    = measure_text(font, marker, marker_size);
		draw_text(
			font,
			marker,
			card.x + card.width - pad - marker_w,
			card.y + (float)ui::px(50),
			marker_size,
			theme::current()
			.panel_match);
	}
}

fn void Panel.draw_key_grid(&self, RLFont font, keymap::Keymap* keymap, config::Config* config)
{
	Rect panel   = self.panel_rect();
	float top    = self.keys_list_top();
	float limit  = panel.y + panel.height - (float)ui::px(FOOTER_HEIGHT);
	bool has_any = false;
	for (sz i = 0; i < self.rows.len(); i++)
	{
		if (self.rows[i].kind == RowKind.COMMAND)
		{
			has_any = true;
			break;
		}
	}
	if (!has_any)
	{
		ui::empty_state(
			font,
			{
				.x = panel.x + (float)ui::px(PADDING),
				.y = top,
				.width = panel.width - (float)ui::px(PADDING * 2),
				.height = limit - top,
			},
			self.key_empty_title(),
			self.key_empty_hint()
		);
		return;
	}

	RLVector2 mouse = rl::get_mouse_position();
	bool pressed    = rl::is_mouse_button_down(rl::RLMouseButton.LEFT);
	int hover       = self.row_at(mouse);
	rl::begin_scissor_mode((int)panel.x, (int)top, (int)panel.width, (int)(limit - top));
	for (int i = 0; i < (int)self.rows.len(); i++)
	{
		Rect r = self.key_rect(i);
		if (r.y + r.height < top || r.y > limit) continue;
		Row row = self.rows[i];
		if (row.kind == RowKind.HEADER)
		{
			draw_text(
				font,
				row.section,
				r.x + (float)ui::px(4),
				r.y + (float)ui::px(5),
				(float)ui::tpx(18),
				theme::current()
				.panel_header);
			ui::separator_h(
				{
					.x = r.x,
					.y = r.y + r.height - (float)ui::px(2),
					.width = r.width,
					.height = 1.0f,
				}
			);
			continue;
		}
		bool selected = i == self.selected;
		bool hovered  = i == hover;
		if (row.kind == RowKind.ACTION)
		{
			RLColor fill = theme::current().panel_field;
			if (selected)
			{
				fill = theme::current().panel_bg_alt;
			}
			else if (hovered)
			{
				fill = pressed ? theme::current().panel_selected : theme::current().topbar_hover;
				if (pressed) fill[3] = 80;
			}
			ui::rounded_rect(r, ui::row_radius(), fill);
			draw_text(
				font,
				"Reset all keybindings in this scope",
				r.x + (float)ui::px(10),
				r.y + (float)ui::px(9),
				(float)ui::tpx(17),
				theme::current()
				.panel_text);
			continue;
		}
		self.draw_key_card(font, r, i, selected, hovered, pressed, keymap, config);
	}
	rl::end_scissor_mode();
}

fn void Panel.draw_skin_row(&self, RLFont font, Rect panel, Row row, bool selected, float y, config::Config* config)
{
	SkinItem item = row.skin;
	String label  = skin_item_label(item);
	draw_text_clipped(
		font,
		label,
		panel.x + (float)ui::px(PADDING) + (float)ui::px(4),
		y + (float)ui::px(5),
		(float)ui::tpx(19),
		panel.width - (float)ui::px(320),
		theme::current()
		.panel_text);
	draw_text_clipped(
		font,
		skin_item_description(item),
		panel.x + (float)ui::px(PADDING) + (float)ui::px(4),
		y + (float)ui::px(25),
		(float)ui::tpx(14),
		panel.width - (float)ui::px(320),
		theme::current()
		.panel_dim);

	bool action = item == SkinItem.RELOAD || item == SkinItem.RESET;
	if (!action)
	{
		settings::SettingLayer source = self.skin_source(item, config);
		String source_text            = skin::source_label(source);
		float source_size             = (float)ui::tpx(15);
		float source_width            = measure_text(font, source_text, source_size);
		draw_text(
			font,
			source_text,
			panel.x + panel.width - (float)ui::px(260) - source_width - (float)ui::px(8),
			y + (float)ui::px(11),
			source_size,
			source == settings::SettingLayer.DEFAULT ? theme::current()
			.panel_dim : theme::current().panel_header);
	}

	@pool()
	{
		DString value_text;
		value_text.init(tmem, 64);
		if (self.skin_editing && self.skin_edit_item == item)
		{
			value_text.append_string((String)self.skin_edit_buf[0:self.skin_edit_len]);
			value_text.append_string("_");
		}
		else
		{
			self.skin_value_text(&value_text, item, config);
		}
		float value_size = (float)ui::tpx(20);
		if (measure_text(font, value_text.str_view(), value_size) > (float)ui::px(240))
		{
			draw_text_clipped(
				font,
				value_text.str_view(),
				panel.x + panel.width - (float)ui::px(PADDING) - (float)ui::px(240),
				y + (float)ui::px(6),
				value_size,
				(float)ui::px(240),
				selected ? theme::current()
				.panel_text : theme::current().panel_dim);
		}
		else
		{
			float width = measure_text(font, value_text.str_view(), value_size);
			draw_text(
				font,
				value_text.str_view(),
				panel.x + panel.width - (float)ui::px(PADDING) - width,
				y + (float)ui::px(6),
				value_size,
				self.skin_editing && self.skin_edit_item == item ? theme::current()
				.panel_match : (selected ? theme::current().panel_text : theme::current().panel_dim));
		}
		value_text.free();
	};
}

fn void Panel.draw_skin_page(&self, RLFont font, config::Config* config)
{
	Rect panel   = self.panel_rect();
	float y      = self.list_y();
	float limit  = panel.y + panel.height - (float)ui::px(FOOTER_HEIGHT);
	bool has_any = false;
	for (sz i = 0; i < self.rows.len(); i++)
	{
		if (self.rows[i].kind == RowKind.SKIN)
		{
			has_any = true;
			break;
		}
	}
	if (!has_any)
	{
		ui::empty_state(
			font,
			{
				.x = panel.x + (float)ui::px(PADDING),
				.y = y,
				.width = panel.width - (float)ui::px(PADDING * 2),
				.height = limit - y,
			},
			"No matching skin settings",
			"Try another search or clear the query."
		);
		return;
	}
	RLVector2 mouse = rl::get_mouse_position();
	int hover_row   = self.row_at(mouse);
	bool pressed    = rl::is_mouse_button_down(rl::RLMouseButton.LEFT);
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
		else if (index == hover_row)
		{
			ui::row(
				{
					.x = panel.x + 2.0f,
					.y = y,
					.width = panel.width - 4.0f,
					.height = (float)ui::px(ROW_HEIGHT),
				},
				pressed ? theme::current()
				.panel_selected : theme::current().panel_bg_alt);
		}
		if (row.kind == RowKind.SKIN) self.draw_skin_row(font, panel, row, selected, y, config);
		y += (float)ui::px(ROW_HEIGHT);
	}
}

fn void Panel.draw(&self, RLFont font, bool project_open, keymap::Keymap* keymap, config::Config* config)
{
	if (!self.open) return;

	Rect outer   = self.outer_rect();
	Rect panel   = self.panel_rect();
	Rect sidebar = self.sidebar_rect();
	ui::floating_panel(outer, theme::current().panel_bg, theme::current().panel_border);
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
		Rect pr                = self.page_rect(i);
		bool active            = i == (int)self.page;
		ui::ControlState state = ui::control_state(pr, true, active);
		ui::row(pr, ui::control_fill(state, active ? theme::current()
			.panel_selected : theme::current()
				.panel_field, theme::current()
					.topbar_hover, theme::current().panel_selected, theme::current().panel_bg_alt));
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

	Rect global_scope             = self.scope_rect(false);
	Rect project_scope            = self.scope_rect(true);
	bool project_enabled          = project_open;
	ui::ControlState global_state = ui::control_state(global_scope, true, self.scope == settings::SettingLayer.GLOBAL);
	ui::ControlState project_state = ui::control_state(
		project_scope,
		project_enabled,
		self.scope == settings::SettingLayer.PROJECT
	);
	ui::rounded_rect(
		global_scope,
		ui::row_radius(),
		ui::control_fill(global_state, self.scope == settings::SettingLayer.GLOBAL ? theme::current()
		.panel_selected : theme::current()
			.panel_field, theme::current()
				.topbar_hover, theme::current().panel_selected, theme::current().panel_bg_alt));
	ui::rounded_rect(
		project_scope,
		ui::row_radius(),
		ui::control_fill(project_state, self.scope == settings::SettingLayer.PROJECT ? theme::current()
		.panel_selected : theme::current()
			.panel_field, theme::current()
				.topbar_hover, theme::current().panel_selected, theme::current().panel_bg_alt));
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
			"Search settings and commands",
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

	if (self.page == settings::SettingPage.KEYS)
	{
		self.draw_key_filters(font);
		self.draw_key_grid(font, keymap, config);
	}
	else if (self.page == settings::SettingPage.SKIN)
	{
		self.draw_skin_page(font, config);
	}
	else
	{
		float y         = self.list_y();
		float limit     = panel.y + panel.height - (float)ui::px(FOOTER_HEIGHT);
		RLVector2 mouse = rl::get_mouse_position();
		int hover_row   = self.row_at(mouse);
		bool pressed    = rl::is_mouse_button_down(rl::RLMouseButton.LEFT);
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
			else if (index == hover_row)
			{
				ui::row(
					{
						.x = panel.x + 2.0f,
						.y = y,
						.width = panel.width - 4.0f,
						.height = (float)ui::px(ROW_HEIGHT),
					},
					pressed ? theme::current()
					.panel_selected : theme::current().panel_bg_alt);
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
				"Arrows: navigate   Enter: capture   Del: unbind   Backspace: reset",
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
		else if (row.kind == RowKind.SKIN)
		{
			draw_text(
				font,
				"Enter: edit/cycle   Del: clear   Tab: scope   Arrows: navigate",
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