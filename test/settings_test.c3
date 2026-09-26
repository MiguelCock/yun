module yun::settings @test;

import std::collections::list;
import std::collections::object;
import std::core::dstring;
import std::encoding::json;
import yun::editor;

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