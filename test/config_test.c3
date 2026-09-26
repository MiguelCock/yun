module yun::config @test;

import std::io::file;
import std::io::path;
import yun::commands;
import yun::settings;

fn void test_defaults()
{
	@pool()
	{
		Config c;
		c.init(tmem);
		c.reset();
		assert(c.settings.get_string(settings::SettingId.APP_THEME).compare_to("dark") == 0);
		assert(c.settings.get_int(settings::SettingId.EDITOR_FONT_SIZE) == 16);
		assert(c.settings.source(settings::SettingId.APP_THEME) == settings::SettingLayer.DEFAULT);
		assert(c.warnings.len() == 0);
		assert(c.keymap.len() == 0);
		assert(c.lsp.len() == 0);
	};
}

fn void test_apply_and_layering()
{
	@pool()
	{
		Config c;
		c.init(tmem);
		c.reset();

		assert(c.apply_json(
			"{\"app\":{\"theme\":\"light\"},\"editor\":{\"font_size\":14}}",
			settings::SettingLayer.GLOBAL
		));
		assert(c.settings.get_string(settings::SettingId.APP_THEME).compare_to("light") == 0);
		assert(c.settings.get_int(settings::SettingId.EDITOR_FONT_SIZE) == 14);

		assert(c.apply_json("{\"app\":{\"theme\":\"dark\"}}", settings::SettingLayer.GLOBAL));
		assert(c.settings.get_string(settings::SettingId.APP_THEME).compare_to("dark") == 0);
		assert(c.settings.get_int(settings::SettingId.EDITOR_FONT_SIZE) == 14);
	};
}

fn void test_unknown_key_warns()
{
	@pool()
	{
		Config c;
		c.init(tmem);
		c.reset();
		assert(c.apply_json("{\"nope\":1,\"editor\":{\"font_size\":12}}", settings::SettingLayer.GLOBAL));
		assert(c.settings.get_int(settings::SettingId.EDITOR_FONT_SIZE) == 12);
		assert(c.warnings.len() == 1);
		assert(c.warnings[0].compare_to("Unknown config key: nope") == 0);
	};
}

fn void test_type_mismatch_warns()
{
	@pool()
	{
		Config c;
		c.init(tmem);
		c.reset();
		assert(c.apply_json(
			"{\"app\":{\"theme\":42},\"editor\":{\"font_size\":\"big\"}}",
			settings::SettingLayer.GLOBAL
		));
		assert(c.settings.get_string(settings::SettingId.APP_THEME).compare_to("dark") == 0);
		assert(c.settings.get_int(settings::SettingId.EDITOR_FONT_SIZE) == 16);
		assert(c.warnings.len() == 2);
	};
}

fn void test_keymap_and_lsp_accessors()
{
	@pool()
	{
		Config c;
		c.init(tmem);
		c.reset();
		assert(c.apply_json(
			"{\"keymap\":{\"save\":\"Ctrl+Shift+S\"},\"lsp\":{\"c3\":\"c3-lsp\"}}",
			settings::SettingLayer.GLOBAL
		));

		assert(c.key_binding(commands::CommandId.SAVE).compare_to("Ctrl+Shift+S") == 0);
		assert(c.key_binding(commands::CommandId.OPEN).len == 0);
		assert(c.lsp_command("c3").compare_to("c3-lsp") == 0);
		assert(c.lsp_command("python").len == 0);

		assert(c.apply_json("{\"keymap\":{\"save\":\"Ctrl+Alt+S\"}}", settings::SettingLayer.GLOBAL));
		assert(c.key_binding(commands::CommandId.SAVE).compare_to("Ctrl+Alt+S") == 0);
		assert(c.keymap.len() == 1);
	};
}

fn void test_malformed_file_warns()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_config_bad");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "config.json");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "{ not json")) return;

		Config c;
		c.init(tmem);
		c.reset();
		assert(!c.load_path(f, settings::SettingLayer.GLOBAL));
		assert(c.warnings.len() == 1);

		(void)path::rmtree(dir);
	};
}

fn void test_project_overrides_global()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_config_project");
		if (catch excuse = d) return;
		Path root = d;
		(void)path::rmtree(root);
		if (catch excuse = path::mkdir(root, recursive: true)) return;
		Path? yun = root.append(tmem, ".yun");
		if (catch excuse = yun) return;
		if (catch excuse = path::mkdir(yun, recursive: true)) return;
		Path? f = yun.append(tmem, "config.json");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "{\"app\":{\"theme\":\"light\"},\"editor\":{\"font_size\":20}}")) return;

		Config c;
		c.init(tmem);
		c.reset();
		assert(c.apply_json(
			"{\"app\":{\"theme\":\"dark\"},\"editor\":{\"font_size\":14}}",
			settings::SettingLayer.GLOBAL
		));
		c.load_project((String)root);
		assert(c.settings.get_string(settings::SettingId.APP_THEME).compare_to("light") == 0);
		assert(c.settings.get_int(settings::SettingId.EDITOR_FONT_SIZE) == 20);
		assert(c.settings.source(settings::SettingId.APP_THEME) == settings::SettingLayer.PROJECT);

		(void)path::rmtree(root);
	};
}

fn void test_ensure_defaults_creates_valid_file()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_config_defaults");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "config.json");
		if (catch excuse = f) return;

		Config c;
		c.init(tmem);
		c.reset();
		c.ensure_defaults(dir, f);
		assert(path::exists(f));
		assert(c.load_path(f, settings::SettingLayer.GLOBAL));
		assert(c.settings.get_string(settings::SettingId.APP_THEME).compare_to("dark") == 0);
		assert(c.settings.get_int(settings::SettingId.EDITOR_FONT_SIZE) == 16);
		assert(c.warnings.len() == 0);

		(void)path::rmtree(dir);
	};
}

fn void test_save_load_roundtrip()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_config_save");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "config.json");
		if (catch excuse = f) return;
		Path file = f;

		Config c;
		c.init(tmem);
		c.settings.set_string(settings::SettingId.APP_THEME, "dracula", settings::SettingLayer.GLOBAL);
		c.settings.set_int(settings::SettingId.EDITOR_FONT_SIZE, 20, settings::SettingLayer.GLOBAL);
		c.set_key_binding("find", "Ctrl+Shift+F");
		c.set_lsp_command("c3", "c3-lsp");
		c.save_path(file, settings::SettingLayer.GLOBAL);

		Config loaded;
		loaded.init(tmem);
		assert(loaded.load_path(file, settings::SettingLayer.GLOBAL));
		assert(loaded.settings.get_string(settings::SettingId.APP_THEME).compare_to("dracula") == 0);
		assert(loaded.settings.get_int(settings::SettingId.EDITOR_FONT_SIZE) == 20);
		assert(loaded.key_binding(commands::CommandId.FIND).compare_to("Ctrl+Shift+F") == 0);
		assert(loaded.lsp_command("c3").compare_to("c3-lsp") == 0);
		assert(loaded.warnings.len() == 0);

		c.destroy();
		loaded.destroy();
		(void)path::rmtree(dir);
	};
}

fn void test_empty_chord_roundtrip()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_config_empty_chord");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "config.json");
		if (catch excuse = f) return;
		Path file = f;

		Config c;
		c.init(tmem);
		c.set_key_binding("save", "");
		c.save_path(file, settings::SettingLayer.GLOBAL);

		Config loaded;
		loaded.init(tmem);
		assert(loaded.load_path(file, settings::SettingLayer.GLOBAL));
		assert(loaded.keymap.len() == 1);
		assert(loaded.keymap[0].chord.len == 0);
		assert(loaded.key_binding(commands::CommandId.SAVE).len == 0);

		c.destroy();
		loaded.destroy();
		(void)path::rmtree(dir);
	};
}