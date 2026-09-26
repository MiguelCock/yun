module yun::settings @test;

import std::collections::list;
import std::collections::object;
import std::core::dstring;
import std::encoding::json;
import yun::editor;
import yun::theme;

fn void test_defaults()
{
	@pool()
	{
		Settings s;
		s.init(tmem);
		assert(s.get_string(SettingId.APP_THEME).compare_to("dark") == 0);
		assert(s.get_int(SettingId.EDITOR_FONT_SIZE) == 16);
		assert(s.get_bool(SettingId.APP_THEME) == false);
		assert(s.get_float(SettingId.EDITOR_FONT_SIZE) == 0.0);
		assert(s.source(SettingId.APP_THEME) == SettingLayer.DEFAULT);
		assert(s.source(SettingId.EDITOR_FONT_SIZE) == SettingLayer.DEFAULT);
		s.destroy();
	};
}

fn void test_layers_and_precedence()
{
	@pool()
	{
		Settings s;
		s.init(tmem);
		s.set_string(SettingId.APP_THEME, "nord", SettingLayer.GLOBAL);
		s.set_int(SettingId.EDITOR_FONT_SIZE, 20, SettingLayer.PROJECT);

		assert(s.get_string(SettingId.APP_THEME).compare_to("nord") == 0);
		assert(s.source(SettingId.APP_THEME) == SettingLayer.GLOBAL);
		assert(s.get_int(SettingId.EDITOR_FONT_SIZE) == 20);
		assert(s.source(SettingId.EDITOR_FONT_SIZE) == SettingLayer.PROJECT);

		s.set_string(SettingId.APP_THEME, "dracula", SettingLayer.PROJECT);
		assert(s.get_string(SettingId.APP_THEME).compare_to("dracula") == 0);
		assert(s.source(SettingId.APP_THEME) == SettingLayer.PROJECT);
		s.destroy();
	};
}

fn void test_change_tracking()
{
	@pool()
	{
		Settings s;
		s.init(tmem);
		assert(!s.consume_change(SettingId.APP_THEME));
		s.set_string(SettingId.APP_THEME, "nord", SettingLayer.GLOBAL);
		assert(s.consume_change(SettingId.APP_THEME));
		assert(!s.consume_change(SettingId.APP_THEME));

		assert(!s.consume_change(SettingId.EDITOR_FONT_SIZE));
		s.mark_all_changed();
		assert(s.consume_change(SettingId.EDITOR_FONT_SIZE));
		s.destroy();
	};
}

fn void test_clamp_high()
{
	@pool()
	{
		Settings s;
		s.init(tmem);
		List{String} warnings;
		warnings.init(tmem);

		Object*? parsed = json::parse(tmem, "{\"editor\":{\"font_size\":999}}");
		if (catch excuse = parsed)
		{
			assert(false);
		}
		else
		{
			Object* root  = parsed;
			Object*? part = root.get("editor");
			if (catch part_excuse = part)
			{
				assert(false);
			}
			else
			{
				s.apply_section("editor", part, SettingLayer.GLOBAL, &warnings);
				assert(s.get_int(SettingId.EDITOR_FONT_SIZE) == 48);
				assert(warnings.len() == 0);
			}
		}

		s.destroy();
		warnings.free();
	};
}

fn void test_clamp_low()
{
	@pool()
	{
		Settings s;
		s.init(tmem);
		List{String} warnings;
		warnings.init(tmem);

		Object*? parsed = json::parse(tmem, "{\"editor\":{\"font_size\":1}}");
		if (catch excuse = parsed)
		{
			assert(false);
		}
		else
		{
			Object* root  = parsed;
			Object*? part = root.get("editor");
			if (catch part_excuse = part)
			{
				assert(false);
			}
			else
			{
				s.apply_section("editor", part, SettingLayer.GLOBAL, &warnings);
				assert(s.get_int(SettingId.EDITOR_FONT_SIZE) == 8);
				assert(warnings.len() == 0);
			}
		}

		s.destroy();
		warnings.free();
	};
}

fn void test_type_mismatch_warns()
{
	@pool()
	{
		Settings s;
		s.init(tmem);
		List{String} warnings;
		warnings.init(tmem);

		Object*? parsed = json::parse(tmem, "{\"editor\":{\"font_size\":\"big\"}}");
		if (catch excuse = parsed)
		{
			assert(false);
		}
		else
		{
			Object* root  = parsed;
			Object*? part = root.get("editor");
			if (catch part_excuse = part)
			{
				assert(false);
			}
			else
			{
				s.apply_section("editor", part, SettingLayer.GLOBAL, &warnings);
				assert(s.get_int(SettingId.EDITOR_FONT_SIZE) == 16);
				assert(warnings.len() == 1);
			}
		}

		s.destroy();
		warnings.free();
	};
}

fn void test_unknown_key_warns()
{
	@pool()
	{
		Settings s;
		s.init(tmem);
		List{String} warnings;
		warnings.init(tmem);

		Object*? parsed = json::parse(tmem, "{\"editor\":{\"nope\":1}}");
		if (catch excuse = parsed)
		{
			assert(false);
		}
		else
		{
			Object* root  = parsed;
			Object*? part = root.get("editor");
			if (catch part_excuse = part)
			{
				assert(false);
			}
			else
			{
				s.apply_section("editor", part, SettingLayer.GLOBAL, &warnings);
				assert(warnings.len() == 1);
				assert(warnings[0].compare_to("Unknown config key: editor.nope") == 0);
			}
		}

		s.destroy();
		warnings.free();
	};
}

fn void test_write_sections_roundtrip()
{
	@pool()
	{
		Settings s;
		s.init(tmem);
		s.set_string(SettingId.APP_THEME, "nord", SettingLayer.GLOBAL);
		s.set_int(SettingId.EDITOR_FONT_SIZE, 24, SettingLayer.GLOBAL);

		DString out;
		out.init(tmem, 256);
		out.append_string("{\n");
		s.write_sections(&out, SettingLayer.GLOBAL);
		out.append_string("  \"keymap\": {}\n}\n");

		Object*? parsed = json::parse(tmem, out.str_view());
		if (catch excuse = parsed)
		{
			assert(false);
		}
		else
		{
			Object* root = parsed;
			Settings s2;
			s2.init(tmem);
			List{String} warnings;
			warnings.init(tmem);

			Object*? app_section = root.get("app");
			if (catch app_excuse = app_section)
			{
				assert(false);
			}
			else
			{
				s2.apply_section("app", app_section, SettingLayer.GLOBAL, &warnings);
			}
			Object*? editor_section = root.get("editor");
			if (catch editor_excuse = editor_section)
			{
				assert(false);
			}
			else
			{
				s2.apply_section("editor", editor_section, SettingLayer.GLOBAL, &warnings);
			}

			assert(s2.get_string(SettingId.APP_THEME).compare_to("nord") == 0);
			assert(s2.get_int(SettingId.EDITOR_FONT_SIZE) == 24);
			assert(warnings.len() == 0);
			s2.destroy();
			warnings.free();
		}

		out.free();
		s.destroy();
	};
}

fn void test_font_bounds_match_editor()
{
	assert(SETTINGS[(int)SettingId.EDITOR_FONT_SIZE].min == (double)editor::FONT_SIZE_MIN);
	assert(SETTINGS[(int)SettingId.EDITOR_FONT_SIZE].max == (double)editor::FONT_SIZE_MAX);
	assert(SETTINGS[(int)SettingId.EDITOR_FONT_SIZE].fallback.i == editor::FONT_SIZE_DEFAULT);
}

fn void test_clear_falls_back()
{
	@pool()
	{
		Settings s;
		s.init(tmem);
		s.set_string(SettingId.APP_THEME, "nord", SettingLayer.GLOBAL);
		s.set_int(SettingId.EDITOR_FONT_SIZE, 20, SettingLayer.PROJECT);
		assert(s.source(SettingId.EDITOR_FONT_SIZE) == SettingLayer.PROJECT);

		s.clear(SettingId.EDITOR_FONT_SIZE, SettingLayer.PROJECT);
		assert(s.source(SettingId.EDITOR_FONT_SIZE) == SettingLayer.DEFAULT);
		assert(s.get_int(SettingId.EDITOR_FONT_SIZE) == 16);

		s.clear(SettingId.APP_THEME, SettingLayer.GLOBAL);
		assert(s.source(SettingId.APP_THEME) == SettingLayer.DEFAULT);
		assert(s.get_string(SettingId.APP_THEME).compare_to("dark") == 0);
		s.destroy();
	};
}

fn void test_theme_options_match_theme_module()
{
	assert(SETTINGS[(int)SettingId.APP_THEME].kind == SettingKind.ENUM);
	String[] options = SETTINGS[(int)SettingId.APP_THEME].options;
	assert(options.len == (usz)theme::count());
	for (int i = 0; i < theme::count(); i++)
	{
		assert(options[(usz)i].compare_to(theme::name(i)) == 0);
	}
}

fn void test_editor_defaults()
{
	assert(SETTINGS[(int)SettingId.EDITOR_FONT_SIZE].fallback.i == 16);
	assert(SETTINGS[(int)SettingId.EDITOR_FONT_FAMILY].fallback.s.compare_to("JetBrains Mono") == 0);
	assert(SETTINGS[(int)SettingId.EDITOR_LINE_HEIGHT].fallback.f == 1.25);
	assert(SETTINGS[(int)SettingId.EDITOR_PADDING_X].fallback.i == 8);
	assert(SETTINGS[(int)SettingId.EDITOR_PADDING_Y].fallback.i == 6);
	assert(SETTINGS[(int)SettingId.EDITOR_INDENT_STYLE].fallback.s.compare_to("tabs") == 0);
	assert(SETTINGS[(int)SettingId.EDITOR_INDENT_WIDTH].fallback.i == 4);
	assert(SETTINGS[(int)SettingId.EDITOR_AUTO_INDENT].fallback.b);
	assert(SETTINGS[(int)SettingId.EDITOR_CARET_BLINK_MS].fallback.i == 500);
	assert(SETTINGS[(int)SettingId.EDITOR_SCROLL_MARGIN_LINES].fallback.i == 1);
	assert(SETTINGS[(int)SettingId.EDITOR_WHEEL_SCROLL_LINES].fallback.i == 3);
	assert(SETTINGS[(int)SettingId.EDITOR_SHOW_LINE_NUMBERS].fallback.b);
}

fn void test_font_options_hook()
{
	String[] opts = { "A", "B" };
	set_font_options(opts);
	assert(setting_options(SettingId.EDITOR_FONT_FAMILY).len == 2);
	assert(setting_options(SettingId.EDITOR_INDENT_STYLE).len == 2);
	set_font_options({ });
	assert(setting_options(SettingId.EDITOR_FONT_FAMILY).len == 1);
}

fn void test_editor_clamp()
{
	@pool()
	{
		Settings s;
		s.init(tmem);
		List{String} warnings;
		warnings.init(tmem);
		Object*? parsed = json::parse(tmem, "{\"editor\":{\"indent_width\":999}}");
		if (catch excuse = parsed)
		{
			assert(false);
		}
		else
		{
			Object* root  = parsed;
			Object*? part = root.get("editor");
			if (catch part_excuse = part)
			{
				assert(false);
			}
			else
			{
				s.apply_section("editor", part, SettingLayer.GLOBAL, &warnings);
				assert(s.get_int(SettingId.EDITOR_INDENT_WIDTH) == 16);
			}
		}
		s.destroy();
		warnings.free();
	};
}