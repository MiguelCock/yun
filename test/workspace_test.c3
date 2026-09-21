module yun::workspace @test;

import raylib6::rl;
import std::io::file;
import std::io::path;
import yun::canvas;
import yun::project;

fn void test_relative_path_roundtrip()
{
	@pool()
	{
		String root = "/root/proj";
		String abs  = "/root/proj/src/a.c3";
		String rel  = relative_path(tmem, root, abs);
		assert(rel.compare_to("src/a.c3") == 0);

		Path? back = absolute_path(tmem, root, rel);
		if (catch excuse = back)
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
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_ws_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;

		char[] content = { 'x' };
		Path? f        = dir.append(tmem, "a.c3");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, content)) return;
		Path? sub = dir.append(tmem, "sub");
		if (catch excuse = sub) return;
		if (catch excuse = path::mkdir(sub)) return;

		Project p;
		p.init(tmem);
		p.root = dir.copy(tmem);
		int card = p.append_card((String)f, { 0.0f, 0.0f });
		p.cards[card].rect = { .x = 10.0f, .y = 20.0f, .width = 240.0f, .height = 160.0f };
		p.cards[card].open = true;
		int folder = p.add_folder((String)sub, project::ROOT_FOLDER);
		p.folders[folder].collapsed = false;

		canvas::Canvas canvas;
		canvas.camera.target = { 5.0f, -3.0f };
		canvas.camera.zoom = 2.0f;
		canvas.target = canvas.camera;

		assert(save(&p, &canvas));

		// scramble the in-memory state, then load it back
		p.cards[card].rect = { .x = 0.0f, .y = 0.0f, .width = 1.0f, .height = 1.0f };
		p.cards[card].open = false;
		p.folders[folder].collapsed = true;
		canvas.camera.target = { 0.0f, 0.0f };
		canvas.camera.zoom = 1.0f;

		assert(load(&p, &canvas));
		assert(p.cards[card].rect.x == 10.0f && p.cards[card].rect.y == 20.0f);
		assert(p.cards[card].rect.width == 240.0f && p.cards[card].rect.height == 160.0f);
		assert(p.cards[card].open);
		assert(!p.folders[folder].collapsed);
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
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_ws_version_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? yun = dir.append(tmem, ".yun");
		if (catch excuse = yun) return;
		if (catch excuse = path::mkdir(yun)) return;
		Path? wf = yun.append(tmem, "workspace.json");
		if (catch excuse = wf) return;
		char[] json = "{\"version\":\"999\",\"camera\":{\"target_x\":0.0,\"target_y\":0.0,\"zoom\":1.0},\"cards\":[],\"folders\":[]}";
		if (catch excuse = file::save(wf, json)) return;

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
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_ws_drop_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;

		char[] content = { 'x' };
		Path? f        = dir.append(tmem, "a.c3");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, content)) return;

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