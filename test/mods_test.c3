module yun::mods_test @test;

import std::io::path;
import yun::config;
import yun::commands;
import yun::editor;
import yun::mods;
import yun::mods_test_helpers;
import yun::notify;
import yun::palette;
import yun::project;
import yun::settings;

fn void test_loader_orders_and_skips_failures()
{
	@pool()
	{
		String root = mods_test_helpers::temp_root(tmem);
		assert(mods_test_helpers::prepare_root(tmem, root));
		assert(mods_test_helpers::write_file(root, "b.lua", "return { version = \"2.0\" }"));
		assert(mods_test_helpers::write_file(root, "a.lua", "return { version = \"1.0\" }"));
		assert(mods_test_helpers::write_file(root, "bad.lua", "this is not valid lua"));
		assert(mods_test_helpers::write_file(root, "notes.txt", "ignored"));

		project::Project project;
		mods_test_helpers::init_project(&project, root);
		defer project.destroy();

		notify::Notifier notifier;
		notifier.init(tmem);
		defer notifier.destroy();

		bool project_open = true;
		mods::Mods registry;
		mods_test_helpers::init_mods(&registry, &project, &notifier, &project_open);
		defer registry.destroy();

		registry.load_project((String)project.root);
		assert(registry.mods.len() == 2);
		assert(registry.mods[0].name.compare_to("a") == 0);
		assert(registry.mods[1].name.compare_to("b") == 0);
		assert(registry.mods[1].version.compare_to("2.0") == 0);
		assert(registry.skipped.len() == 1);
		assert(registry.memory_used() > 0);

		registry.unload_all();
		assert(registry.memory_used() == 0);
		mods_test_helpers::cleanup_root(root);
	};
}

fn void test_allocator_cap_disables_mod()
{
	@pool()
	{
		String root = mods_test_helpers::temp_root(tmem);
		assert(mods_test_helpers::prepare_root(tmem, root));
		assert(mods_test_helpers::write_file(
			root,
			"bomb.lua",
			"local t = {}\n"
				"yun.on_startup(function()\n"
				"  while true do t[#t + 1] = string.rep('x', 4096) end\n"
				"end)\n"
		));

		project::Project project;
		mods_test_helpers::init_project(&project, root);
		defer project.destroy();

		notify::Notifier notifier;
		notifier.init(tmem);
		defer notifier.destroy();

		bool project_open = true;
		mods::Mods registry;
		mods_test_helpers::init_mods(&registry, &project, &notifier, &project_open);
		defer registry.destroy();

		registry.memory_cap = 512 * 1024;
		registry.instruction_budget = 100000000;
		registry.load_project((String)project.root);
		assert(registry.mods.len() == 1);
		registry.dispatch_startup();
		assert(registry.mods[0].disabled);
		assert(registry.mods[0].runtime.alloc_failed);
		assert(registry.mods[0].error_count >= 1);
		mods_test_helpers::cleanup_root(root);
	};
}

fn void test_instruction_budget_stops_infinite_loop()
{
	@pool()
	{
		String root = mods_test_helpers::temp_root(tmem);
		assert(mods_test_helpers::prepare_root(tmem, root));
		assert(mods_test_helpers::write_file(root, "spin.lua", "yun.on_startup(function() while true do end end)\n"));

		project::Project project;
		mods_test_helpers::init_project(&project, root);
		defer project.destroy();

		notify::Notifier notifier;
		notifier.init(tmem);
		defer notifier.destroy();

		bool project_open = true;
		mods::Mods registry;
		mods_test_helpers::init_mods(&registry, &project, &notifier, &project_open);
		defer registry.destroy();

		registry.instruction_budget = 50000;
		registry.load_project((String)project.root);
		assert(registry.mods.len() == 1);
		registry.dispatch_startup();
		assert(registry.mods[0].disabled);
		assert(registry.mods[0].error_count >= 1);
		mods_test_helpers::cleanup_root(root);
	};
}

fn void test_error_isolation_and_repeat_disable()
{
	@pool()
	{
		String root = mods_test_helpers::temp_root(tmem);
		assert(mods_test_helpers::prepare_root(tmem, root));
		assert(mods_test_helpers::write_file(root, "a_error.lua", "yun.on_startup(function() error('boom') end)\n"));
		assert(mods_test_helpers::write_file(root, "b_ok.lua", "yun.on_startup(function() yun.notify('b ran') end)\n"));
		assert(mods_test_helpers::write_file(
			root,
			"c_selection.lua",
			"yun.on_selection(function() error('bad selection') end)\n"
		));

		project::Project project;
		mods_test_helpers::init_project(&project, root);
		defer project.destroy();

		notify::Notifier notifier;
		notifier.init(tmem);
		defer notifier.destroy();

		bool project_open = true;
		mods::Mods registry;
		mods_test_helpers::init_mods(&registry, &project, &notifier, &project_open);
		defer registry.destroy();

		registry.load_project((String)project.root);
		assert(registry.mods.len() == 3);
		registry.dispatch_startup();
		assert(registry.mods[0].name.compare_to("a_error") == 0);
		assert(registry.mods[0].error_count == 1);
		assert(!registry.mods[0].disabled);
		assert(!registry.mods[1].disabled);
		assert(mods_test_helpers::notifier_has(&notifier, "b ran"));

		registry.dispatch_selection(0, 0, 0);
		registry.dispatch_selection(0, 0, 0);
		registry.dispatch_selection(0, 0, 0);
		assert(registry.mods[2].name.compare_to("c_selection") == 0);
		assert(registry.mods[2].disabled);
		assert(registry.mods[2].error_count >= 3);
		mods_test_helpers::cleanup_root(root);
	};
}

fn void test_api_version_read_only_and_unknown_members()
{
	@pool()
	{
		String root = mods_test_helpers::temp_root(tmem);
		assert(mods_test_helpers::prepare_root(tmem, root));
		assert(mods_test_helpers::write_file(
			root,
			"api.lua",
			"assert(yun.api_version == 1)\n"
				"assert(yun.host_version ~= nil)\n"
				"assert(yun.nope == nil)\n"
				"local ok = pcall(function() yun.nope() end)\n"
				"assert(not ok)\n"
				"local write_ok = pcall(function() yun.nope = 1 end)\n"
				"assert(not write_ok)\n"
				"assert(yun.has_capability('read'))\n"
				"assert(yun.has_capability('notify'))\n"
				"assert(type(yun.cards()) == 'table')\n"
		));

		project::Project project;
		mods_test_helpers::init_project(&project, root);
		defer project.destroy();

		notify::Notifier notifier;
		notifier.init(tmem);
		defer notifier.destroy();

		bool project_open = true;
		mods::Mods registry;
		mods_test_helpers::init_mods(&registry, &project, &notifier, &project_open);
		defer registry.destroy();

		registry.load_project((String)project.root);
		assert(registry.mods.len() == 1);
		assert(registry.mods[0].error_count == 0);
		mods_test_helpers::cleanup_root(root);
	};
}

fn void test_event_marshalling_and_buffer_cap()
{
	@pool()
	{
		String root = mods_test_helpers::temp_root(tmem);
		assert(mods_test_helpers::prepare_root(tmem, root));
		assert(mods_test_helpers::write_file(root, "demo.c3", "hello world\n"));
		assert(mods_test_helpers::write_file(
			root,
			"marsh.lua",
			"yun.on_file_open(function(c)\n"
				"  assert(c.valid == true)\n"
				"  assert(c.id == 0)\n"
				"  assert(c.language == 'c3')\n"
				"  assert(c.line_count >= 1)\n"
				"  assert(yun.project().card_count == 1)\n"
				"  assert(yun.focused().id == 0)\n"
				"  local text, truncated = yun.buffer(0, 0, 12)\n"
				"  assert(text == 'hello world\\n')\n"
				"  assert(truncated == false)\n"
				"  local big, clipped = yun.buffer(0, 0, 10 * 1024 * 1024)\n"
				"  assert(clipped == true)\n"
				"  assert(#big == 12)\n"
				"  local selection = yun.selection()\n"
				"  assert(selection.card == 0)\n"
				"  assert(selection.start == 0)\n"
				"  assert(selection['end'] == 5)\n"
				"  assert(selection.text == 'hello')\n"
				"end)\n"
				"yun.on_file_save(function(c) yun.notify('save ' .. c.id) end)\n"
				"yun.on_file_close(function(c) yun.notify('close ' .. c.id) end)\n"
				"yun.on_command(function(c) yun.notify('command ' .. c.name) end)\n"
		));

		project::Project project;
		mods_test_helpers::init_project(&project, root);
		defer project.destroy();

		@pool()
		{
			Path? demo_opt = ((Path)root).append(tmem, ".yun/mods/demo.c3");
			if (catch excuse = demo_opt) assert(false);
			Path demo = demo_opt;
			int index = project.append_card((String)demo, { 0.0f, 0.0f });
			assert(index == 0);
		};
		project.focused = 0;
		project.selected = 0;
		editor::ensure_buffer(&project.cards[0], project.allocator);
		assert(project.cards[0].buffer != null);
		project.cards[0].selection_anchor = 0;
		project.cards[0].cursor = 5;

		notify::Notifier notifier;
		notifier.init(tmem);
		defer notifier.destroy();

		bool project_open = true;
		mods::Mods registry;
		mods_test_helpers::init_mods(&registry, &project, &notifier, &project_open);
		defer registry.destroy();

		registry.load_project((String)project.root);
		assert(registry.mods.len() == 1);
		registry.dispatch_file_open(0);
		registry.dispatch_file_save(0);
		registry.dispatch_file_close(0);
		registry.dispatch_command(1, "save", "Save", 0);
		assert(mods_test_helpers::notifier_has(&notifier, "save 0"));
		assert(mods_test_helpers::notifier_has(&notifier, "close 0"));
		assert(mods_test_helpers::notifier_has(&notifier, "command save"));
		assert(registry.mods[0].error_count == 0);
		assert(!registry.mods[0].disabled);
		mods_test_helpers::cleanup_root(root);
	};
}

fn void test_capability_gating()
{
	@pool()
	{
		String root = mods_test_helpers::temp_root(tmem);
		assert(mods_test_helpers::prepare_root(tmem, root));
		assert(mods_test_helpers::write_file(
			root,
			"gated.lua",
			"yun.on_update(function(dt)\n"
				"  assert(yun.has_capability('render') == false)\n"
				"  local ok = pcall(function() yun.draw.rect(0, 0, 10, 10, 0xFFFFFFFF) end)\n"
				"  assert(not ok)\n"
				"  assert(yun.is_key_down('a') == false)\n"
				"  assert(yun.mouse() == nil)\n"
				"  yun.notify('update ran')\n"
				"end)\n"
		));

		project::Project project;
		mods_test_helpers::init_project(&project, root);
		defer project.destroy();

		notify::Notifier notifier;
		notifier.init(tmem);
		defer notifier.destroy();

		bool project_open = true;
		mods::Mods registry;
		mods_test_helpers::init_mods(&registry, &project, &notifier, &project_open);
		defer registry.destroy();

		registry.load_project((String)project.root);
		assert(registry.mods.len() == 1);
		registry.dispatch_update(0.016f);
		assert(registry.mods[0].error_count == 0);
		assert(mods_test_helpers::notifier_has(&notifier, "update ran"));
		mods_test_helpers::cleanup_root(root);
	};
}

fn void test_command_and_menu_registration()
{
	@pool()
	{
		String root = mods_test_helpers::temp_root(tmem);
		assert(mods_test_helpers::prepare_root(tmem, root));
		assert(mods_test_helpers::write_file(
			root,
			"ui.lua",
			"yun.register_command('demo.hello', 'Hello from mod', function() yun.notify('command ran') end)\n"
				"yun.add_menu_item('Mod menu item', function() yun.notify('menu ran') end)\n"
		));

		project::Project project;
		mods_test_helpers::init_project(&project, root);
		defer project.destroy();

		notify::Notifier notifier;
		notifier.init(tmem);
		defer notifier.destroy();

		bool project_open = true;
		mods::Mods registry;
		mods_test_helpers::init_mods(&registry, &project, &notifier, &project_open);
		defer registry.destroy();

		registry.load_project((String)project.root);
		assert(registry.mods.len() == 1);
		assert(registry.palette_count() == 1);
		assert(registry.palette_label(0).compare_to("Hello from mod") == 0);
		assert(registry.menu_count() == 1);
		assert(registry.menu_label(0).compare_to("Mod menu item") == 0);
		assert(registry.run_palette(mods::palette_encoded(0)));
		assert(mods_test_helpers::notifier_has(&notifier, "command ran"));
		assert(registry.run_menu_item(0));
		assert(mods_test_helpers::notifier_has(&notifier, "menu ran"));
		mods_test_helpers::cleanup_root(root);
	};
}

fn void test_frame_hooks_and_overlay_dispatch()
{
	@pool()
	{
		String root = mods_test_helpers::temp_root(tmem);
		assert(mods_test_helpers::prepare_root(tmem, root));
		assert(mods_test_helpers::write_file(
			root,
			"frame.lua",
			"yun.set_overlay('below')\n"
				"yun.on_startup(function() yun.notify('startup ran') end)\n"
				"yun.on_update(function(dt) yun.notify('update ran') end)\n"
				"yun.on_draw(function() yun.notify('draw ran') end)\n"
		));

		project::Project project;
		mods_test_helpers::init_project(&project, root);
		defer project.destroy();

		notify::Notifier notifier;
		notifier.init(tmem);
		defer notifier.destroy();

		bool project_open = true;
		mods::Mods registry;
		mods_test_helpers::init_mods(&registry, &project, &notifier, &project_open);
		defer registry.destroy();
		registry.load_project((String)project.root);
		registry.dispatch_startup();
		assert(mods_test_helpers::notifier_has(&notifier, "startup ran"));
		assert(registry.mods[0].overlay == mods::ModOverlay.BELOW);

		registry.allow_input = true;
		registry.allow_render = false;
		registry.frame(0.016f);
		registry.frame(0.016f);
		assert(mods_test_helpers::notifier_count_text(&notifier, "update ran") == 2);
		registry.draw(mods::ModOverlay.ABOVE);
		assert(!mods_test_helpers::notifier_has(&notifier, "draw ran"));

		registry.allow_render = true;
		registry.draw(mods::ModOverlay.ABOVE);
		assert(!mods_test_helpers::notifier_has(&notifier, "draw ran"));
		registry.draw(mods::ModOverlay.BELOW);
		assert(mods_test_helpers::notifier_has(&notifier, "draw ran"));
		assert(registry.mods[0].error_count == 0);
		mods_test_helpers::cleanup_root(root);
	};
}
fn void test_mod_settings_defaults()
{
	@pool()
	{
		config::Config cfg;
		cfg.init(tmem);
		cfg.reset();
		assert(cfg.settings.get_bool(settings::SettingId.MODS_ENABLED));
		assert(!cfg.settings.get_bool(settings::SettingId.MODS_ALLOW_RENDER));
		assert(!cfg.settings.get_bool(settings::SettingId.MODS_ALLOW_INPUT));
		cfg.destroy();
	};
}
fn void test_handler_added_during_dispatch_is_not_reentered()
{
	@pool()
	{
		String root = mods_test_helpers::temp_root(tmem);
		assert(mods_test_helpers::prepare_root(tmem, root));
		assert(mods_test_helpers::write_file(
			root,
			"grow.lua",
			"yun.on_startup(function()\n"
				"  yun.on_startup(function() error('late handler must not run') end)\n"
				"  yun.notify('first handler')\n"
				"end)\n"
		));

		project::Project project;
		mods_test_helpers::init_project(&project, root);
		defer project.destroy();

		notify::Notifier notifier;
		notifier.init(tmem);
		defer notifier.destroy();

		bool project_open = true;
		mods::Mods registry;
		mods_test_helpers::init_mods(&registry, &project, &notifier, &project_open);
		defer registry.destroy();
		registry.load_project((String)project.root);
		assert(registry.mods[0].handlers.len() == 1);
		registry.dispatch_startup();
		assert(registry.mods[0].handlers.len() == 2);
		assert(registry.mods[0].error_count == 0);
		assert(!registry.mods[0].disabled);
		assert(mods_test_helpers::notifier_has(&notifier, "first handler"));
		mods_test_helpers::cleanup_root(root);
	};
}
fn void test_project_without_mods_folder_is_stable()
{
	@pool()
	{
		String root = mods_test_helpers::temp_root(tmem);
		assert(mods_test_helpers::prepare_root(tmem, root));

		project::Project project;
		mods_test_helpers::init_project(&project, root);
		defer project.destroy();

		notify::Notifier notifier;
		notifier.init(tmem);
		defer notifier.destroy();

		bool project_open = true;
		mods::Mods registry;
		mods_test_helpers::init_mods(&registry, &project, &notifier, &project_open);
		defer registry.destroy();

		registry.ensure_loaded(&project, true);
		assert(registry.loaded_project);
		assert(registry.project_root.compare_to(root) == 0);
		registry.ensure_loaded(&project, true);
		assert(registry.loaded_project);
		assert(registry.mods.len() == 0);
		mods_test_helpers::cleanup_root(root);
	};
}
fn void test_palette_exposes_mod_commands()
{
	@pool()
	{
		String root = mods_test_helpers::temp_root(tmem);
		assert(mods_test_helpers::prepare_root(tmem, root));
		assert(mods_test_helpers::write_file(
			root,
			"palette.lua",
			"yun.register_command('demo.palette', 'Palette demo command', function() end)\n"
		));

		project::Project project;
		mods_test_helpers::init_project(&project, root);
		defer project.destroy();

		notify::Notifier notifier;
		notifier.init(tmem);
		defer notifier.destroy();

		bool project_open = true;
		mods::Mods registry;
		mods_test_helpers::init_mods(&registry, &project, &notifier, &project_open);
		defer registry.destroy();
		registry.load_project((String)project.root);

		palette::Palette panel;
		panel.init(tmem);
		defer panel.destroy();
		panel.mods = &registry;
		panel.show();
		panel.filter();
		int encoded = mods::palette_encoded(0);
		assert(panel.results.len() == (sz)commands::command_count() + 1);
		assert((int)panel.results[panel.results.len() - 1] == encoded);
		assert(panel.label_of(encoded).compare_to("Palette demo command") == 0);
		assert(panel.enabled_of(encoded, true, true));
		mods_test_helpers::cleanup_root(root);
	};
}