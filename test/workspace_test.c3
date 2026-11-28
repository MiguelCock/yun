module yun::workspace @test;

import raylib6::rl;
import std::io::file;
import std::io::path;
import yun::canvas;
import yun::console;
import yun::project;
import yun::ui;

fn void test_relative_path_roundtrip()
{
	@pool()
	{
		String root = "/root/proj";
		String abs  = "/root/proj/src/a.c3";
		String rel  = relative_path(tmem, root, abs);
		assert(rel.compare_to("src/a.c3") == 0);

		Path? back = absolute_path(tmem, root, rel);
		if (catch err = back)
		{
			assert(false);
			return;
		}
		assert(((String)back).compare_to(abs) == 0);
	};
}

fn void test_workspace_save_load_roundtrip()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch err = tmp) return;
		Path? d = tmp.append(tmem, "yun_ws_test");
		if (catch err = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch err = path::mkdir(dir, recursive: true)) return;

		char[] content = { 'x' };
		Path? f        = dir.append(tmem, "a.c3");
		if (catch err = f) return;
		if (catch err = file::save(f, content)) return;
		Path? sub = dir.append(tmem, "sub");
		if (catch err = sub) return;
		if (catch err = path::mkdir(sub)) return;

		Project p;
		p.init(tmem);
		p.root = dir.copy(tmem);
		int card = p.append_card((String)f, { 0.0f, 0.0f });
		p.cards[card].rect = { .x = 10.0f, .y = 20.0f, .width = 240.0f, .height = 160.0f };
		p.cards[card].open = true;
		p.cards[card].preview = true;
		int folder = p.add_folder((String)sub, project::ROOT_FOLDER);
		p.folders[folder].collapsed = false;
		p.folders[folder].body = { .x = 100.0f, .y = 200.0f, .width = 300.0f, .height = 150.0f };
		p.folders[folder].bounds = { .x = 100.0f, .y = 200.0f, .width = 300.0f, .height = 150.0f };
		p.folders[folder].bounds_valid = true;

		canvas::Canvas canvas;
		canvas.camera.target = { 5.0f, -3.0f };
		canvas.camera.zoom = 2.0f;
		canvas.target = canvas.camera;

		assert(save(&p, &canvas));

		// scramble the in-memory state, then load it back
		p.cards[card].rect = { .x = 0.0f, .y = 0.0f, .width = 1.0f, .height = 1.0f };
		p.cards[card].open = false;
		p.cards[card].preview = false;
		p.folders[folder].collapsed = true;
		p.folders[folder].body = { .x = 0.0f, .y = 0.0f, .width = 1.0f, .height = 1.0f };
		canvas.camera.target = { 0.0f, 0.0f };
		canvas.camera.zoom = 1.0f;

		assert(load(&p, &canvas));
		assert(!migrated());
		assert(p.cards[card].rect.x == 10.0f && p.cards[card].rect.y == 20.0f);
		assert(p.cards[card].rect.width == 240.0f && p.cards[card].rect.height == 160.0f);
		assert(p.cards[card].open);
		assert(p.cards[card].preview);
		assert(!p.folders[folder].collapsed);
		assert(p.folders[folder].body.x == 100.0f && p.folders[folder].body.y == 200.0f);
		assert(p.folders[folder].body.width == 300.0f && p.folders[folder].body.height == 150.0f);
		assert(canvas.camera.zoom == 2.0f);
		assert(canvas.camera.target[0] == 5.0f && canvas.camera.target[1] == -3.0f);

		(void)path::rmtree(dir);
	};
}

fn void test_workspace_version_mismatch()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch err = tmp) return;
		Path? d = tmp.append(tmem, "yun_ws_version_test");
		if (catch err = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch err = path::mkdir(dir, recursive: true)) return;
		Path? yun = dir.append(tmem, ".yun");
		if (catch err = yun) return;
		if (catch err = path::mkdir(yun)) return;
		Path? wf = yun.append(tmem, "workspace.json");
		if (catch err = wf) return;
		char[] json = "{\"version\":\"999\",\"camera\":{\"target_x\":0.0,\"target_y\":0.0,\"zoom\":1.0},\"cards\":[],\"folders\":[]}";
		if (catch err = file::save(wf, json)) return;

		Project p;
		p.init(tmem);
		p.root = dir.copy(tmem);
		canvas::Canvas canvas;
		assert(!load(&p, &canvas));

		(void)path::rmtree(dir);
	};
}

fn void test_workspace_drops_unknown_cards()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch err = tmp) return;
		Path? d = tmp.append(tmem, "yun_ws_drop_test");
		if (catch err = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch err = path::mkdir(dir, recursive: true)) return;

		char[] content = { 'x' };
		Path? f        = dir.append(tmem, "a.c3");
		if (catch err = f) return;
		if (catch err = file::save(f, content)) return;

		Project p;
		p.init(tmem);
		p.root = dir.copy(tmem);
		p.append_card((String)f, { 0.0f, 0.0f });

		canvas::Canvas canvas;
		assert(save(&p, &canvas));

		// drop all cards, then load: the saved entry has no match and is skipped
		p.reset();
		assert(load(&p, &canvas));
		assert(p.cards.len() == 0);

		(void)path::rmtree(dir);
	};
}
fn void test_workspace_console_roundtrip()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch err = tmp) return;
		Path? d = tmp.append(tmem, "yun_ws_console_test");
		if (catch err = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch err = path::mkdir(dir, recursive: true)) return;

		Project p;
		p.init(tmem);
		p.root = dir.copy(tmem);

		canvas::Canvas canvas;

		console::ConsoleManager manager;
		manager.init(mem);
		defer manager.destroy();
		manager.reset((String)dir);
		manager.visible = true;
		manager.height = 300.0f;
		manager.active_console().history.add("c3c build");
		manager.add_session_named("Build");
		manager.active_console().history.add("c3c test");
		manager.active = 1;

		assert(save(&p, &canvas, &manager));

		manager.reset((String)dir);
		assert(load(&p, &canvas, &manager));
		assert(manager.visible);
		assert(manager.height == 300.0f);
		assert(manager.sessions.len() == 2);
		assert(manager.active == 1);
		assert(manager.sessions[0].title.compare_to("Console 1") == 0);
		assert(manager.sessions[1].title.compare_to("Build") == 0);
		assert(manager.sessions[0].console.history.entries.len() == 1);
		assert(manager.sessions[0].console.history.entries[0].compare_to("c3c build") == 0);
		assert(manager.sessions[1].console.history.entries.len() == 1);
		assert(manager.sessions[1].console.history.entries[0].compare_to("c3c test") == 0);

		(void)path::rmtree(dir);
	};
}
fn void test_console_persistence_toggles()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch err = tmp) return;
		Path? d = tmp.append(tmem, "yun_ws_console_toggles");
		if (catch err = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch err = path::mkdir(dir, recursive: true)) return;

		Project p;
		p.init(tmem);
		p.root = dir.copy(tmem);
		canvas::Canvas canvas;

		console::ConsoleSettings saved = console::settings();
		defer console::set_settings(saved);

		console::ConsoleManager manager;
		manager.init(mem);
		defer manager.destroy();
		manager.reset((String)dir);
		manager.visible = true;
		manager.height = 300.0f;
		manager.add_session_named("Build");
		manager.active_console().history.add("c3c test");

		console::ConsoleSettings settings = saved;
		settings.restore_sessions = false;
		console::set_settings(settings);
		assert(save(&p, &canvas, &manager));
		manager.reset((String)dir);
		assert(load(&p, &canvas, &manager));
		assert(manager.sessions.len() == 1);
		assert(manager.visible);
		assert(manager.height == 300.0f);
		assert(manager.sessions[0].console.history.entries.len() == 0);

		settings.restore_sessions = true;
		settings.persist_history = false;
		console::set_settings(settings);
		manager.add_session_named("Build");
		manager.active_console().history.add("c3c test");
		assert(save(&p, &canvas, &manager));
		manager.reset((String)dir);
		assert(load(&p, &canvas, &manager));
		assert(manager.sessions.len() == 2);
		assert(manager.sessions[1].title.compare_to("Build") == 0);
		assert(manager.sessions[0].console.history.entries.len() == 0);
		assert(manager.sessions[1].console.history.entries.len() == 0);

		(void)path::rmtree(dir);
	};
}
fn void test_workspace_v4_folder_body_migration()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch err = tmp) return;
		Path? d = tmp.append(tmem, "yun_ws_v4_body");
		if (catch err = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch err = path::mkdir(dir, recursive: true)) return;
		Path? yun = dir.append(tmem, ".yun");
		if (catch err = yun) return;
		if (catch err = path::mkdir(yun)) return;
		Path? wf = yun.append(tmem, "workspace.json");
		if (catch err = wf) return;
		char[] json = "{\"version\":\"4\",\"camera\":{\"target_x\":0.0,\"target_y\":0.0,\"zoom\":1.0},\"cards\":[],\"folders\":[{\"path\":\"sub\",\"collapsed\":true,\"x\":100.0,\"y\":200.0,\"w\":300.0,\"h\":150.0}]}";
		if (catch err = file::save(wf, json)) return;

		Path? sub = dir.append(tmem, "sub");
		if (catch err = sub) return;
		Project p;
		p.init(tmem);
		p.root = dir.copy(tmem);
		int folder = p.add_folder((String)sub, project::ROOT_FOLDER);
		(void)folder;
		canvas::Canvas canvas;
		canvas.init();
		assert(load(&p, &canvas));
		assert(migrated());
		int index = p.folder_by_path((String)sub);
		assert(index >= 0);
		assert(p.folders[index].collapsed);
		assert(p.folders[index].body.x == 100.0f && p.folders[index].body.y == 200.0f);
		assert(p.folders[index].body.width == ui::pxf(project::CLUSTER_COLLAPSED_WIDTH));
		assert(p.folders[index].body.height == ui::pxf(project::CLUSTER_COLLAPSED_BODY));
		(void)path::rmtree(dir);
	};
}