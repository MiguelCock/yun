module yun::settings;

import std::collections::list;
import std::collections::object;
import std::core::dstring;

enum SettingKind : int
{
	INT,
	FLOAT,
	BOOL,
	STRING,
	ENUM,
}

enum SettingLayer : int
{
	DEFAULT,
	GLOBAL,
	PROJECT,
}

enum SettingId : int
{
	APP_THEME,
	EDITOR_FONT_SIZE,
	EDITOR_FONT_FAMILY,
	EDITOR_LINE_HEIGHT,
	EDITOR_PADDING_X,
	EDITOR_PADDING_Y,
	EDITOR_INDENT_STYLE,
	EDITOR_INDENT_WIDTH,
	EDITOR_AUTO_INDENT,
	EDITOR_CARET_BLINK_MS,
	EDITOR_SCROLL_MARGIN_LINES,
	EDITOR_WHEEL_SCROLL_LINES,
	EDITOR_SHOW_LINE_NUMBERS,
	COUNT,
}

const int SETTING_COUNT = (int)SettingId.COUNT;

struct SettingValue
{
	long i;
	double f;
	bool b;
	String s;
}

struct SettingSpec
{
	String section;
	String key;
	String label;
	String description;
	SettingKind kind;
	SettingValue fallback;
	double min;
	double max;
	double step;
	String[] options;
}

const SettingSpec[] SETTINGS = {
	{
		.section = "app",
		.key = "theme",
		.label = "Theme",
		.description = "Colour theme name.",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "dark" },
		.min = 0.0,
		.max = 0.0,
		.step = 0.0,
		.options = {
			"yun_dark",
			"yun_light",
			"dracula",
			"one_dark",
			"gruvbox_dark",
			"gruvbox_light",
			"nord",
			"catppuccin_mocha",
			"catppuccin_latte",
		},
	},
	{
		.section = "editor",
		.key = "font_size",
		.label = "Font size",
		.description = "Editor font size in pixels.",
		.kind = SettingKind.INT,
		.fallback = { .i = 16 },
		.min = 8.0,
		.max = 48.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "font_family",
		.label = "Font family",
		.description = "Editor font (monospace fonts found on the system).",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "JetBrains Mono" },
		.options = { "JetBrains Mono" },
	},
	{
		.section = "editor",
		.key = "line_height",
		.label = "Line height",
		.description = "Line height multiplier.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 1.25 },
		.min = 1.0,
		.max = 2.5,
		.step = 0.05,
	},
	{
		.section = "editor",
		.key = "padding_x",
		.label = "Padding X",
		.description = "Horizontal editor padding in pixels.",
		.kind = SettingKind.INT,
		.fallback = { .i = 8 },
		.min = 0.0,
		.max = 40.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "padding_y",
		.label = "Padding Y",
		.description = "Vertical editor padding in pixels.",
		.kind = SettingKind.INT,
		.fallback = { .i = 6 },
		.min = 0.0,
		.max = 40.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "indent_style",
		.label = "Indent style",
		.description = "Indent with tabs or spaces.",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "tabs" },
		.options = { "tabs", "spaces" },
	},
	{
		.section = "editor",
		.key = "indent_width",
		.label = "Indent width",
		.description = "Columns per indent level (and spaces when using spaces).",
		.kind = SettingKind.INT,
		.fallback = { .i = 4 },
		.min = 1.0,
		.max = 16.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "auto_indent",
		.label = "Auto indent",
		.description = "Match the previous line's indentation on Enter.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "editor",
		.key = "caret_blink_ms",
		.label = "Caret blink (ms)",
		.description = "Caret blink interval in milliseconds (0 = steady).",
		.kind = SettingKind.INT,
		.fallback = { .i = 500 },
		.min = 0.0,
		.max = 2000.0,
		.step = 50.0,
	},
	{
		.section = "editor",
		.key = "scroll_margin_lines",
		.label = "Scroll margin",
		.description = "Lines kept visible around the caret.",
		.kind = SettingKind.INT,
		.fallback = { .i = 1 },
		.min = 0.0,
		.max = 10.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "wheel_scroll_lines",
		.label = "Wheel scroll",
		.description = "Lines scrolled per mouse-wheel notch.",
		.kind = SettingKind.INT,
		.fallback = { .i = 3 },
		.min = 1.0,
		.max = 20.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "show_line_numbers",
		.label = "Line numbers",
		.description = "Show the line-number gutter.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
};

struct Override
{
	SettingId id;
	SettingValue value;
}

struct Settings
{
	Allocator allocator;
	List{Override} global;
	List{Override} project;
	bool[SETTING_COUNT] changed;
}

fn SettingSpec spec(SettingId id)
{
	return SETTINGS[(int)id];
}

String[] g_font_options = { };

fn void set_font_options(String[] options)
{
	g_font_options = options;
}

fn String[] setting_options(SettingId id)
{
	if (id == SettingId.EDITOR_FONT_FAMILY && g_font_options.len > 0) return g_font_options;
	return spec(id).options;
}

fn bool is_section(String name)
{
	foreach (SettingSpec s : SETTINGS)
	{
		if (s.section.compare_to(name) == 0) return true;
	}
	return false;
}

fn bool section_has_key(String section, String key)
{
	foreach (SettingSpec s : SETTINGS)
	{
		if (s.section.compare_to(section) == 0 && s.key.compare_to(key) == 0) return true;
	}
	return false;
}

fn bool section_is_first(usz index)
{
	String section = SETTINGS[index].section;
	for (usz j = 0; j < index; j++)
	{
		if (SETTINGS[j].section.compare_to(section) == 0) return false;
	}
	return true;
}

fn void append_json_string(DString* out, String s)
{
	out.append_char('"');
	for (usz i = 0; i < s.len; i++)
	{
		char c = s[i];
		if (c == '"' || c == '\\') out.append_char('\\');
		out.append_char(c);
	}
	out.append_char('"');
}

fn void free_value(Allocator allocator, SettingValue* value)
{
	if (value.s.ptr != null) value.s.free(allocator);
}

fn long clamp_int(SettingSpec s, long value)
{
	if (value < (long)s.min) return (long)s.min;
	if (value > (long)s.max) return (long)s.max;
	return value;
}

fn double clamp_float(SettingSpec s, double value)
{
	if (value < s.min) return s.min;
	if (value > s.max) return s.max;
	return value;
}

fn void Settings.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.global.init(allocator);
	self.project.init(allocator);
	for (int i = 0; i < SETTING_COUNT; i++) self.changed[i] = false;
}

fn void Settings.free_layer(&self, List{Override}* list)
{
	for (sz i = 0; i < list.len(); i++)
	{
		free_value(self.allocator, &list.get_ref(i).value);
	}
	list.clear();
}

fn void Settings.destroy(&self)
{
	self.free_layer(&self.global);
	self.free_layer(&self.project);
	self.global.free();
	self.project.free();
}

fn void Settings.reset(&self)
{
	self.free_layer(&self.global);
	self.free_layer(&self.project);
	for (int i = 0; i < SETTING_COUNT; i++) self.changed[i] = false;
}

fn void Settings.mark_all_changed(&self)
{
	for (int i = 0; i < SETTING_COUNT; i++) self.changed[i] = true;
}

fn bool Settings.consume_change(&self, SettingId id)
{
	int i        = (int)id;
	bool changed = self.changed[i];
	self.changed[i] = false;
	return changed;
}

fn List{Override}* Settings.layer_list(&self, SettingLayer layer)
{
	switch (layer)
	{
		case SettingLayer.GLOBAL:
			return &self.global;
		case SettingLayer.PROJECT:
			return &self.project;
		case SettingLayer.DEFAULT:
			return null;
	}
}

fn sz Settings.layer_index(&self, List{Override}* list, SettingId id)
{
	if (list == null) return -1;
	for (sz i = 0; i < list.len(); i++)
	{
		if (list.get(i).id == id) return i;
	}
	return -1;
}

fn SettingValue Settings.value_in(&self, SettingId id, SettingLayer layer)
{
	List{Override}* list = self.layer_list(layer);
	sz index             = self.layer_index(list, id);
	if (index >= 0) return list.get(index).value;
	return spec(id).fallback;
}

fn SettingValue Settings.effective(&self, SettingId id)
{
	sz project = self.layer_index(&self.project, id);
	if (project >= 0) return self.project.get(project).value;
	sz global = self.layer_index(&self.global, id);
	if (global >= 0) return self.global.get(global).value;
	return spec(id).fallback;
}

fn SettingLayer Settings.source(&self, SettingId id)
{
	if (self.layer_index(&self.project, id) >= 0) return SettingLayer.PROJECT;
	if (self.layer_index(&self.global, id) >= 0) return SettingLayer.GLOBAL;
	return SettingLayer.DEFAULT;
}

fn long Settings.get_int(&self, SettingId id)
{
	return self.effective(id).i;
}

fn double Settings.get_float(&self, SettingId id)
{
	return self.effective(id).f;
}

fn bool Settings.get_bool(&self, SettingId id)
{
	return self.effective(id).b;
}

fn String Settings.get_string(&self, SettingId id)
{
	return self.effective(id).s;
}

fn void Settings.set_value(&self, SettingId id, SettingValue value, SettingLayer layer)
{
	List{Override}* list = self.layer_list(layer);
	if (list == null) return;

	SettingKind kind    = spec(id).kind;
	SettingValue stored = value;
	if (kind == SettingKind.STRING || kind == SettingKind.ENUM)
	{
		stored.s = value.s.copy(self.allocator);
	}

	sz index = self.layer_index(list, id);
	if (index >= 0)
	{
		free_value(self.allocator, &list.get_ref(index).value);
		list.set(index, { .id = id, .value = stored });
	}
	else
	{
		list.push({ .id = id, .value = stored });
	}
	self.changed[(int)id] = true;
}

fn void Settings.clear(&self, SettingId id, SettingLayer layer)
{
	List{Override}* list = self.layer_list(layer);
	if (list == null) return;
	sz index = self.layer_index(list, id);
	if (index < 0) return;
	free_value(self.allocator, &list.get_ref(index).value);
	list.remove_at(index);
	self.changed[(int)id] = true;
}

fn void Settings.set_int(&self, SettingId id, long value, SettingLayer layer)
{
	self.set_value(id, { .i = value }, layer);
}

fn void Settings.set_float(&self, SettingId id, double value, SettingLayer layer)
{
	self.set_value(id, { .f = value }, layer);
}

fn void Settings.set_bool(&self, SettingId id, bool value, SettingLayer layer)
{
	self.set_value(id, { .b = value }, layer);
}

fn void Settings.set_string(&self, SettingId id, String value, SettingLayer layer)
{
	self.set_value(id, { .s = value }, layer);
}

fn void Settings.push_warning(&self, List{String}* warnings, String message)
{
	warnings.push(message);
}

fn void Settings.apply_key(&self, SettingId id, SettingSpec s, Object* obj, SettingLayer layer, List{String}* warnings)
{
	switch (s.kind)
	{
		case SettingKind.INT:

			{
				int? value = obj.get_int(s.key);
				if (catch excuse = value)
				{
					self.push_warning(
						warnings,
						string::format(self.allocator, "Config \"%s.%s\" must be an integer", s.section, s.key)
					);
				}
				else
				{
					self.set_int(id, clamp_int(s, (long)value), layer);
				}
				break;
			}
		case SettingKind.FLOAT:

			{
				double? value = obj.get_float(s.key);
				if (catch excuse = value)
				{
					self.push_warning(
						warnings,
						string::format(self.allocator, "Config \"%s.%s\" must be a number", s.section, s.key)
					);
				}
				else
				{
					self.set_float(id, clamp_float(s, value), layer);
				}
				break;
			}
		case SettingKind.BOOL:

			{
				bool? value = obj.get_bool(s.key);
				if (catch excuse = value)
				{
					self.push_warning(
						warnings,
						string::format(self.allocator, "Config \"%s.%s\" must be a boolean", s.section, s.key)
					);
				}
				else
				{
					self.set_bool(id, value, layer);
				}
				break;
			}
		case SettingKind.STRING:
		case SettingKind.ENUM:

			{
				String? value = obj.get_string(s.key);
				if (catch excuse = value)
				{
					self.push_warning(
						warnings,
						string::format(self.allocator, "Config \"%s.%s\" must be a string", s.section, s.key)
					);
				}
				else
				{
					self.set_string(id, value, layer);
				}
				break;
			}
	}
}

fn void Settings.apply_section(&self, String name, Object* obj, SettingLayer layer, List{String}* warnings)
{
	if (!obj.is_map())
	{
		self.push_warning(warnings, string::format(self.allocator, "Config \"%s\" must be an object", name));
		return;
	}

	obj.@each_entry(; String key, Object* value)
	{
		if (!section_has_key(name, key))
		{
			self.push_warning(warnings, string::format(self.allocator, "Unknown config key: %s.%s", name, key));
		}
	};

	for (usz i = 0; i < SETTINGS.len; i++)
	{
		SettingSpec s = SETTINGS[i];
		if (s.section.compare_to(name) != 0) continue;
		if (!obj.has_key(s.key)) continue;
		self.apply_key((SettingId)i, s, obj, layer, warnings);
	}
}

fn bool Settings.section_has_output(&self, String section, SettingLayer scope)
{
	for (usz i = 0; i < SETTINGS.len; i++)
	{
		if (SETTINGS[i].section.compare_to(section) != 0) continue;
		if (scope == SettingLayer.PROJECT)
		{
			if (self.layer_index(&self.project, (SettingId)i) >= 0) return true;
		}
		else
		{
			return true;
		}
	}
	return false;
}

fn void write_value(DString* out, SettingValue value, SettingKind kind)
{
	switch (kind)
	{
		case SettingKind.INT:
			(void)out.appendf("%d", value.i);
		case SettingKind.FLOAT:
			(void)out.appendf("%f", value.f);
		case SettingKind.BOOL:
			out.append_string(value.b ? "true" : "false");
		case SettingKind.STRING:
		case SettingKind.ENUM:
			append_json_string(out, value.s);
	}
}

fn void Settings.write_sections(&self, DString* out, SettingLayer scope)
{
	for (usz i = 0; i < SETTINGS.len; i++)
	{
		String section = SETTINGS[i].section;
		if (!section_is_first(i)) continue;
		if (!self.section_has_output(section, scope)) continue;

		out.append_string("  ");
		append_json_string(out, section);
		out.append_string(": {\n");
		bool first = true;
		for (usz j = 0; j < SETTINGS.len; j++)
		{
			if (SETTINGS[j].section.compare_to(section) != 0) continue;
			if (scope == SettingLayer.PROJECT && self.layer_index(&self.project, (SettingId)j) < 0) continue;
			if (!first) out.append_string(",\n");
			first = false;
			out.append_string("    ");
			append_json_string(out, SETTINGS[j].key);
			out.append_string(": ");
			write_value(out, self.value_in((SettingId)j, scope), SETTINGS[j].kind);
		}
		out.append_string("\n  },\n");
	}
}