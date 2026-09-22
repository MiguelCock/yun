module yun::config @test;

import std::io::file;
import std::io::path;
import yun::commands;

fn void test_defaults()
{
	@pool()
	{
		Config c;
		c.init(tmem);
		c.reset();
		assert(c.theme.compare_to("dark") == 0);
		assert(c.font_size == 16);
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

		assert(c.apply_json("{\"theme\":\"light\",\"font_size\":14}"));
		assert(c.theme.compare_to("light") == 0);
		assert(c.font_size == 14);

		assert(c.apply_json("{\"theme\":\"dark\"}"));
		assert(c.theme.compare_to("dark") == 0);
		assert(c.font_size == 14);
	};
}

fn void test_unknown_key_warns()
{
	@pool()
	{
		Config c;
		c.init(tmem);
		c.reset();
		assert(c.apply_json("{\"nope\":1,\"font_size\":12}"));
		assert(c.font_size == 12);
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
		assert(c.apply_json("{\"theme\":42,\"font_size\":\"big\"}"));
		assert(c.theme.compare_to("dark") == 0);
		assert(c.font_size == 16);
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
		assert(c.apply_json("{\"keymap\":{\"save\":\"Ctrl+Shift+S\"},\"lsp\":{\"c3\":\"c3-lsp\"}}"));

		assert(c.key_binding(commands::CommandId.SAVE).compare_to("Ctrl+Shift+S") == 0);
		assert(c.key_binding(commands::CommandId.OPEN).len == 0);
		assert(c.lsp_command("c3").compare_to("c3-lsp") == 0);
		assert(c.lsp_command("python").len == 0);

		assert(c.apply_json("{\"keymap\":{\"save\":\"Ctrl+Alt+S\"}}"));
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
		assert(!c.load_path(f));
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
		if (catch excuse = file::save(f, "{\"theme\":\"light\",\"font_size\":20}")) return;

		Config c;
		c.init(tmem);
		c.reset();
		assert(c.apply_json("{\"theme\":\"dark\",\"font_size\":14}"));
		c.load_project((String)root);
		assert(c.theme.compare_to("light") == 0);
		assert(c.font_size == 20);

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
		assert(c.load_path(f));
		assert(c.theme.compare_to("dark") == 0);
		assert(c.font_size == 16);
		assert(c.warnings.len() == 0);

		(void)path::rmtree(dir);
	};
}