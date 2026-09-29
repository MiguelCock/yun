module yun::project @test;

import raylib6::rl;
import std::collections::list;
import std::io::file;
import std::io::path;
import std::math;
import yun::card;
import yun::editor;

fn void test_path_is_inside()
{
	String root = "/home/user/proj";
	assert(path_is_inside(root, "/home/user/proj/src/a.c3"));
	assert(path_is_inside(root, root));
	assert(!path_is_inside(root, "/home/user/proj2/a.c3"));
	assert(!path_is_inside(root, "/home/user/other.c3"));
}

fn void test_collision_name()
{
	@pool()
	{
		String a = collision_name(tmem, "notes", ".txt", 0);
		assert(a.compare_to("notes.txt") == 0);
		String b = collision_name(tmem, "notes", ".txt", 2);
		assert(b.compare_to("notes (2).txt") == 0);
	};
}

fn void test_find_card_dedup()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.cards.push({ .path = (Path)"/tmp/a.c3".copy(tmem), .name = "a.c3".copy(tmem), .folder = ROOT_FOLDER });
		p.cards.push({ .path = (Path)"/tmp/b.c3".copy(tmem), .name = "b.c3".copy(tmem), .folder = ROOT_FOLDER });
		assert(p.find_card("/tmp/a.c3") == 0);
		assert(p.find_card("/tmp/b.c3") == 1);
		assert(p.find_card("/tmp/c.c3") == -1);
	};
}

fn void test_hit_test_topmost()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.cards.push(
			{
				.path = (Path)"/tmp/a".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/tmp/b".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		assert(p.hit_test({ 50.0f, 50.0f }) == 1);
		assert(p.hit_test({ 200.0f, 200.0f }) == -1);
	};
}

fn void test_card_move_by()
{
	FileCard c = { .rect = { .x = 10.0f, .y = 20.0f, .width = 100.0f, .height = 50.0f } };
	c.move_by({ 5.0f, -3.0f });
	assert(c.rect.x == 15.0f && c.rect.y == 17.0f);
}

fn void test_folder_for_deepest()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		int a = p.add_folder("/root/a", ROOT_FOLDER);
		int b = p.add_folder("/root/a/b", a);
		assert(p.folder_for("/root/a/x.c3") == a);
		assert(p.folder_for("/root/a/b/y.c3") == b);
		assert(p.folder_for("/root/other.c3") == ROOT_FOLDER);
	};
}

fn void test_cluster_bounds_union()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		int f = p.add_folder("/root/a", ROOT_FOLDER);
		p.cards.push(
			{
				.path = (Path)"/root/a/x.c3".copy(tmem),
				.rect = { .x = 100.0f, .y = 100.0f, .width = 200.0f, .height = 100.0f },
				.folder = f,
			}
		);
		Rect b = p.cluster_bounds(f);
		assert(b.x <= 100.0f && b.y <= 100.0f);
		assert(b.x + b.width >= 300.0f);
		assert(b.y + b.height >= 200.0f);
	};
}

fn void test_move_cluster_moves_children()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		int f = p.add_folder("/root/a", ROOT_FOLDER);
		p.cards.push(
			{
				.path = (Path)"/root/a/x.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 50.0f },
				.folder = f,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/root/other.c3".copy(tmem),
				.rect = { .x = 500.0f, .y = 0.0f, .width = 100.0f, .height = 50.0f },
				.folder = ROOT_FOLDER,
			}
		);
		p.move_cluster(f, { 10.0f, 5.0f });
		assert(p.cards[0].rect.x == 10.0f && p.cards[0].rect.y == 5.0f);
		assert(p.cards[1].rect.x == 500.0f);
	};
}

fn void test_collapsed_cluster_hides_cards()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		int f = p.add_folder("/root/a", ROOT_FOLDER);
		p.cards.push(
			{
				.path = (Path)"/root/a/x.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 50.0f },
				.folder = f,
			}
		);
		assert(p.card_visible(0));
		assert(p.hit_test({ 50.0f, 25.0f }) == 0);
		p.toggle_collapse(f);
		assert(!p.card_visible(0));
		assert(p.hit_test({ 50.0f, 25.0f }) == -1);
	};
}

fn void test_ensure_folder_chain()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.root = (Path)"/root".copy(tmem);
		int b = p.ensure_folder("/root/a/b");
		int a = p.folder_by_path("/root/a");
		assert(a >= 0);
		assert(p.folders[b].parent == a);
		assert(p.folders[a].parent == ROOT_FOLDER);
		assert(p.ensure_folder("/root") == ROOT_FOLDER);
		assert(p.folder_by_path("/root/a/b") == b);
	};
}

fn void test_layout_packs_clusters()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.root = (Path)"/root".copy(tmem);
		int a = p.add_folder("/root/a", ROOT_FOLDER);
		int b = p.add_folder("/root/b", ROOT_FOLDER);
		for (int k = 0; k < 4; k++)
		{
			p.cards.push(
				{
					.path = (Path)string::format(tmem, "/root/a/f%d.c3", k)
				.copy(tmem), .folder = a, .rect = { .width = 1.0f, .height = 1.0f }, });
		}
		for (int k = 0; k < 4; k++)
		{
			p.cards.push(
				{
					.path = (Path)string::format(tmem, "/root/b/f%d.c3", k)
				.copy(tmem), .folder = b, .rect = { .width = 1.0f, .height = 1.0f }, });
		}

		p.layout();

		// each level packs folders as chips, so expanded boxes overlap
		assert(rect_intersects(p.cluster_bounds(a), p.cluster_bounds(b)));

		// collapsed chips are packed tightly and never overlap
		p.folders[a].collapsed = true;
		p.folders[b].collapsed = true;
		assert(!rect_intersects(p.cluster_visual_bounds(a), p.cluster_visual_bounds(b)));
	};
}

fn void test_layout_nests_child_clusters()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.root = (Path)"/root".copy(tmem);
		int a = p.add_folder("/root/a", ROOT_FOLDER);
		int d = p.add_folder("/root/a/d", a);
		p.cards.push(
			{ .path = (Path)"/root/a/x.c3".copy(tmem), .folder = a, .rect = { .width = 1.0f, .height = 1.0f } }
		);
		p.cards.push(
			{ .path = (Path)"/root/a/d/y.c3".copy(tmem), .folder = d, .rect = { .width = 1.0f, .height = 1.0f } }
		);

		p.layout();

		// the nested folder's box is contained in its parent
		Rect ra = p.cluster_bounds(a);
		Rect rd = p.cluster_visual_bounds(d);
		assert(rd.x >= ra.x - 0.01f && rd.y >= ra.y - 0.01f);
		assert(rd.x + rd.width <= ra.x + ra.width + 0.01f);
		assert(rd.y + rd.height <= ra.y + ra.height + 0.01f);
	};
}

fn void test_open_job_completes_and_cancels()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_open_job");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;

		char[] content = { 'x' };
		Path? sub      = dir.append(tmem, "src");
		if (catch excuse = sub) return;
		if (catch excuse = path::mkdir(sub)) return;
		Path? root_file = dir.append(tmem, "README.md");
		if (catch excuse = root_file) return;
		if (catch excuse = file::save(root_file, content)) return;
		Path? nested = sub.append(tmem, "main.c3");
		if (catch excuse = nested) return;
		if (catch excuse = file::save(nested, content)) return;

		Path? env = dir.append(tmem, "env");
		if (catch excuse = env) return;
		if (catch excuse = path::mkdir(env)) return;
		Path? env_file = env.append(tmem, "site.py");
		if (catch excuse = env_file) return;
		if (catch excuse = file::save(env_file, content)) return;
		Path? gitignore = dir.append(tmem, ".gitignore");
		if (catch excuse = gitignore) return;
		if (catch excuse = file::save(gitignore, "env/\n")) return;

		Project p;
		p.init(tmem);
		OpenJob* job = open_job_create(tmem, &p, (String)dir);
		while (!job.step(1))
		{
		}
		assert(job.phase == OpenPhase.DONE);
		assert(p.cards.len() == 3);
		assert(p.folders.len() == 1);
		assert(job.scanned_dirs >= 2);
		for (sz i = 0; i < p.folders.len(); i++)
		{
			assert(!((String)p.folders[i].path).contains("env"));
		}
		open_job_destroy(job);

		Project cancelled;
		cancelled.init(tmem);
		OpenJob* cancel_job = open_job_create(tmem, &cancelled, (String)dir);
		cancel_job.cancel();
		assert(cancel_job.cancelled);
		assert(cancel_job.phase == OpenPhase.FAILED);
		assert(cancel_job.step(1));
		open_job_destroy(cancel_job);

		(void)path::rmtree(dir);
	};
}

fn void test_resolve_path_absolute()
{
	@pool()
	{
		String? r = resolve_path(tmem, "/tmp/foo");
		if (catch excuse = r)
		{
			assert(false);
		}
		assert(r.compare_to("/tmp/foo") == 0);
	};
}

fn void test_resolve_path_relative()
{
	@pool()
	{
		Path? cwd = path::cwd(tmem);
		if (catch excuse = cwd) return;
		String? r = resolve_path(tmem, "sub/dir");
		if (catch excuse = r)
		{
			assert(false);
		}
		assert(path_is_inside((String)cwd, r));
	};
}

fn void test_open_scans_directory()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_open_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);

		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? s = dir.append(tmem, "src");
		if (catch excuse = s) return;
		Path src = s;
		if (catch excuse = path::mkdir(src)) return;
		Path? sub = src.append(tmem, "sub");
		if (catch excuse = sub) return;
		Path subdir = sub;
		if (catch excuse = path::mkdir(subdir)) return;

		char[] content = { 'x' };
		Path? readme   = dir.append(tmem, "README.md");
		if (catch excuse = readme) return;
		if (catch excuse = file::save(readme, content)) return;
		Path? fa = src.append(tmem, "a.c3");
		if (catch excuse = fa) return;
		if (catch excuse = file::save(fa, content)) return;
		Path? fb = subdir.append(tmem, "b.c3");
		if (catch excuse = fb) return;
		if (catch excuse = file::save(fb, content)) return;

		Project p;
		p.init(tmem);
		assert(p.open((String)dir));
		assert(p.cards.len() == 3);
		assert(p.folders.len() == 2);
		assert(p.folder_by_path((String)src) >= 0);
		assert(p.folder_by_path((String)subdir) >= 0);

		// opened with every folder collapsed, and cached membership matches folder_for
		for (sz i = 0; i < p.folders.len(); i++)
		{
			assert(p.folders[i].collapsed);
		}
		for (sz i = 0; i < p.cards.len(); i++)
		{
			assert(p.cards[i].folder == p.folder_for((String)p.cards[i].path));
		}

		(void)path::rmtree(dir);
	};
}

fn void test_collapsed_cluster_is_compact()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		int f = p.add_folder("/root/a", ROOT_FOLDER);
		p.cards.push(
			{
				.path = (Path)"/root/a/x.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 50.0f },
				.folder = f,
			}
		);
		Rect expanded = p.cluster_visual_bounds(f);
		assert(expanded.height > CLUSTER_TITLE_HEIGHT);

		p.toggle_collapse(f);
		Rect collapsed = p.cluster_visual_bounds(f);
		assert(collapsed.height == CLUSTER_TITLE_HEIGHT);
		assert(collapsed.width == CLUSTER_COLLAPSED_WIDTH);
		assert(collapsed.x == expanded.x && collapsed.y == expanded.y);

		p.toggle_collapse(f);
		Rect again = p.cluster_visual_bounds(f);
		assert(again.width == expanded.width && again.height == expanded.height);
	};
}

fn void test_is_valid_name()
{
	assert(is_valid_name("notes.txt"));
	assert(is_valid_name("a b c"));
	assert(!is_valid_name(""));
	assert(!is_valid_name("."));
	assert(!is_valid_name(".."));
	assert(!is_valid_name("a/b"));
	assert(!is_valid_name("a\\b"));
	assert(!is_valid_name("a:b"));
}

fn void test_create_file_and_folder()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_create_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;

		Project p;
		p.init(tmem);
		p.root = dir.copy(tmem);

		int first = p.create_file(ROOT_FOLDER, "hello.txt", { 0.0f, 0.0f });
		assert(first == 0);
		assert(p.cards.len() == 1);
		assert(p.focused == 0);
		assert(path::exists(p.cards[0].path));

		int second = p.create_file(ROOT_FOLDER, "hello.txt", { 0.0f, 0.0f });
		assert(second == 1);
		assert(p.cards.len() == 2);
		assert(p.cards[1].name.compare_to("hello (1).txt") == 0);

		int folder = p.create_folder_on_disk(ROOT_FOLDER, "sub", { 0.0f, 0.0f });
		assert(folder == 0);
		assert(p.folders.len() == 1);
		assert(path::exists(p.folders[0].path));
		assert(p.create_folder_on_disk(ROOT_FOLDER, "sub", { 0.0f, 0.0f }) == -1);

		(void)path::rmtree(dir);
	};
}

fn void test_folder_at_returns_cluster()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.root = (Path)"/root".copy(tmem);
		int f = p.add_folder("/root/a", ROOT_FOLDER);
		p.folders[f].bounds = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f };
		assert(p.folder_at({ 50.0f, 50.0f }) == f);
		assert(p.folder_at({ 200.0f, 200.0f }) == ROOT_FOLDER);
		assert(p.hit_test({ 50.0f, 50.0f }) == -1);
	};
}

fn void test_content_bounds()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		Rect out;
		assert(!p.content_bounds(&out));

		p.cards.push(
			{
				.path = (Path)"/root/a.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 50.0f },
				.folder = ROOT_FOLDER,
			}
		);
		assert(p.content_bounds(&out));
		assert(out.x == 0.0f && out.y == 0.0f);
		assert(out.width == 100.0f && out.height == 50.0f);
	};
}

fn void test_collapsing_parent_hides_child_clusters()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.root = (Path)"/root".copy(tmem);
		int a = p.add_folder("/root/a", ROOT_FOLDER);
		int b = p.add_folder("/root/a/b", a);
		assert(p.cluster_visible(a));
		assert(p.cluster_visible(b));
		p.toggle_collapse(a);
		assert(p.cluster_visible(a));
		assert(!p.cluster_visible(b));
		p.toggle_collapse(a);
		assert(p.cluster_visible(b));
	};
}
fn void test_card_file_operations()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_card_ops");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;

		Project p;
		p.init(tmem);
		p.root = dir.copy(tmem);

		assert(p.create_file(ROOT_FOLDER, "a.txt", { 0.0f, 0.0f }) == 0);
		Path old = p.cards[0].path.copy(tmem);
		if (catch excuse = file::save(p.cards[0].path, "hello")) return;

		assert(p.rename_card(0, "b.txt"));
		assert(p.cards[0].name.compare_to("b.txt") == 0);
		assert(path::exists(p.cards[0].path));
		assert(!path::exists(old));
		assert(!p.rename_card(0, "b.txt"));

		int dup = p.duplicate_card(0, { 0.0f, 0.0f });
		assert(dup == 1);
		assert(p.cards.len() == 2);
		assert(p.cards[1].name.compare_to("b (1).txt") == 0);
		assert(path::exists(p.cards[1].path));
		Path dup_path = p.cards[1].path.copy(tmem);

		assert(p.delete_card_file(1));
		assert(p.cards.len() == 1);
		assert(!path::exists(dup_path));

		p.focused = 0;
		p.remove_card(0);
		assert(p.cards.len() == 0);
		assert(p.focused == -1);

		(void)path::rmtree(dir);
	};
}

fn void test_basename_is_ignored()
{
	assert(basename_is_ignored("/home/x/proj/.git"));
	assert(basename_is_ignored("/home/x/proj/build"));
	assert(basename_is_ignored("/home/x/proj/node_modules"));
	assert(basename_is_ignored("C:\\proj\\out"));
	assert(!basename_is_ignored("/home/x/proj/src"));
	assert(!basename_is_ignored("/home/x/proj/builder"));
	assert(!basename_is_ignored("/home/x/build/src"));
}

fn void test_rect_intersects_and_expand()
{
	assert(rect_intersects(
		{ .x = 0.0f, .y = 0.0f, .width = 10.0f, .height = 10.0f },
		{ .x = 5.0f, .y = 5.0f, .width = 10.0f, .height = 10.0f }
	));
	assert(!rect_intersects(
		{ .x = 0.0f, .y = 0.0f, .width = 10.0f, .height = 10.0f },
		{ .x = 20.0f, .y = 20.0f, .width = 5.0f, .height = 5.0f }
	));
	Rect e = expand_rect({ .x = 0.0f, .y = 0.0f, .width = 10.0f, .height = 10.0f }, 5.0f);
	assert(e.x == -5.0f && e.y == -5.0f && e.width == 20.0f && e.height == 20.0f);
}

fn void test_bounds_cache_invalidated_on_move()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		int f = p.add_folder("/root/a", ROOT_FOLDER);
		p.cards.push(
			{
				.path = (Path)"/root/a/x.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 50.0f },
				.folder = f,
			}
		);
		Rect before = p.cluster_bounds(f);
		p.move_cluster(f, { 1000.0f, 0.0f });
		Rect after = p.cluster_bounds(f);
		assert(after.x == before.x + 1000.0f);
		assert(after.width == before.width);
	};
}

fn void test_open_prunes_ignored_dirs()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_prune_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;

		char[] content        = { 'x' };
		String[] ignored_dirs = { "node_modules", "build", "out", ".git", "src" };
		foreach (String name : ignored_dirs)
		{
			Path? child = dir.append(tmem, name);
			if (catch excuse = child) return;
			if (catch excuse = path::mkdir(child)) return;
			Path? f = child.append(tmem, "file.txt");
			if (catch excuse = f) return;
			if (catch excuse = file::save(f, content)) return;
		}
		Path? root_file = dir.append(tmem, "root.txt");
		if (catch excuse = root_file) return;
		if (catch excuse = file::save(root_file, content)) return;

		Project p;
		p.init(tmem);
		assert(p.open((String)dir));
		assert(p.cards.len() == 2);
		assert(p.folders.len() == 1);

		Path? src = dir.append(tmem, "src");
		if (catch excuse = src) return;
		assert(p.folder_by_path((String)src) >= 0);

		Path? ignored = dir.append(tmem, "node_modules");
		if (catch excuse = ignored) return;
		assert(p.folder_by_path((String)ignored) == ROOT_FOLDER);

		for (sz i = 0; i < p.cards.len(); i++)
		{
			String path = (String)p.cards[i].path;
			assert(path.contains("node_modules") == false);
			assert(p.cards[i].folder == p.folder_for(path));
		}

		(void)path::rmtree(dir);
	};
}
fn void test_double_click_detection()
{
	RLVector2 a    = { 10.0f, 10.0f };
	RLVector2 near = { 12.0f, 11.0f };
	RLVector2 far  = { 40.0f, 10.0f };

	assert(is_double_click(1.0, a, 0.9, a));
	assert(is_double_click(1.0, near, 0.9, a));
	assert(!is_double_click(1.0, far, 0.9, a));
	assert(!is_double_click(1.0, a, 0.5, a));
	assert(!is_double_click(0.8, a, 0.9, a));
}
fn void test_discard_ephemeral()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_ephemeral");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "tmp.c");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "x")) return;

		Project p;
		p.init(tmem);
		p.root = dir.copy(tmem);
		int index = p.add_card((String)f, { 0.0f, 0.0f });
		assert(index >= 0);
		assert(p.focused == index);
		p.cards[index].ephemeral = true;

		p.discard_ephemeral(p.focused);
		assert(p.cards.len() == 1);

		p.discard_ephemeral(-1);
		assert(p.cards.len() == 0);
		assert(!path::exists(f));

		(void)path::rmtree(dir);
	};
}

fn void test_cluster_title_hit_only_top_bar()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		int f = p.add_folder("/root/a", ROOT_FOLDER);
		p.folders[f].bounds = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f };
		p.folders[f].bounds_valid = false;

		assert(p.cluster_title_hit(f, { 50.0f, 10.0f }));
		assert(!p.cluster_title_hit(f, { 50.0f, 50.0f }));
		assert(!p.cluster_title_hit(f, { 50.0f, 200.0f }));

		p.toggle_collapse(f);
		assert(p.cluster_title_hit(f, { 50.0f, 10.0f }));
	};
}
fn void test_jump_fade()
{
	assert(jump_fade(10.0, 11.0, 1.0) == 1.0f);
	assert(jump_fade(10.5, 11.0, 1.0) == 0.5f);
	assert(jump_fade(11.0, 11.0, 1.0) == 0.0f);
	assert(jump_fade(11.5, 11.0, 1.0) == 0.0f);
	assert(jump_fade(10.0, 11.0, 0.0) == 0.0f);
}

fn void test_mark_and_clear_jump()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.cards.push({ .path = (Path)"/root/a.c3".copy(tmem), .folder = ROOT_FOLDER });
		p.mark_jump("/root/a.c3", 3, 100.0);
		assert(p.jump_path.compare_to("/root/a.c3") == 0);
		assert(p.jump_line == 3);
		p.clear_jump();
		assert(p.jump_path.len == 0);
		assert(p.jump_line == 0);
	};
}
fn void test_refresh_sleep()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		int folder = p.add_folder("/root/sub", ROOT_FOLDER);
		p.cards.push(
			{
				.path = (Path)"/root/a.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/root/b.c3".copy(tmem),
				.rect = { .x = 1000.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/root/sub/c.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = folder,
				.open = true,
			}
		);
		p.toggle_collapse(folder);

		Rect visible = { .x = 0.0f, .y = 0.0f, .width = 200.0f, .height = 200.0f };
		p.refresh_sleep(visible, 1.0f);
		assert(!p.cards[0].sleeping);
		assert(p.cards[1].sleeping);
		assert(p.cards[2].sleeping);
		assert(p.awake_count == 1);
		assert(p.asleep_count == 2);

		p.focused = 1;
		p.refresh_sleep(visible, 1.0f);
		assert(!p.cards[1].sleeping);
		assert(p.awake_count == 2);
	};
}
fn void test_next_visible_card()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		int folder = p.add_folder("/root/sub", ROOT_FOLDER);
		p.cards.push(
			{
				.path = (Path)"/root/a.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/root/sub/b.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = folder,
				.open = true,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/root/c.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		p.toggle_collapse(folder);

		assert(p.next_visible_card(-1, 1) == 0);
		assert(p.next_visible_card(0, 1) == 2);
		assert(p.next_visible_card(2, 1) == 0);
		assert(p.next_visible_card(0, -1) == 2);
		assert(p.next_visible_card(2, -1) == 0);
	};
}
fn void test_item_in_direction()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.cards.push(
			{
				.path = (Path)"/root/a.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/root/b.c3".copy(tmem),
				.rect = { .x = 500.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/root/c.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 500.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/root/d.c3".copy(tmem),
				.rect = { .x = 500.0f, .y = 500.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);

		NavItem item;
		p.select_card(0);
		assert(p.item_in_direction(Dir.RIGHT, &item) && !item.folder && item.index == 1);
		assert(p.item_in_direction(Dir.DOWN, &item) && !item.folder && item.index == 2);
		assert(!p.item_in_direction(Dir.LEFT, &item));
		assert(!p.item_in_direction(Dir.UP, &item));

		p.select_card(1);
		assert(p.item_in_direction(Dir.LEFT, &item) && item.index == 0);

		p.select_card(3);
		assert(p.item_in_direction(Dir.UP, &item) && item.index == 1);
		assert(p.item_in_direction(Dir.LEFT, &item) && item.index == 2);
	};
}

fn void test_nav_scope_is_direct_children()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.root = (Path)"/root".copy(tmem);
		int sub  = p.add_folder("/root/sub", ROOT_FOLDER);
		int deep = p.add_folder("/root/sub/deep", sub);
		p.cards.push(
			{
				.path = (Path)"/root/a.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/root/sub/b.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = sub,
				.open = true,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/root/sub/deep/c.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = deep,
				.open = true,
			}
		);

		// at root: only the root card and the top-level folder chip
		List{NavItem} items;
		items.init(tmem);
		p.current_folder = ROOT_FOLDER;
		p.nav_items(&items);
		assert(items.len() == 2);
		items.clear();

		// inside sub: only its own card and the nested folder chip
		p.current_folder = sub;
		p.nav_items(&items);
		assert(items.len() == 2);
		assert(items[0].index == 1);
		assert(items[1].folder && items[1].index == deep);
	};
}

fn void test_enter_and_leave_folder()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.root = (Path)"/root".copy(tmem);
		int sub = p.add_folder("/root/sub", ROOT_FOLDER);
		p.cards.push(
			{
				.path = (Path)"/root/a.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/root/sub/b.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 200.0f, .width = 100.0f, .height = 100.0f },
				.folder = sub,
				.open = true,
			}
		);
		p.folders[sub].collapsed = true;

		p.enter_folder(sub);
		assert(p.current_folder == sub);
		assert(!p.folders[sub].collapsed);
		assert(p.selected == 1 && p.selected_cluster == -1);

		assert(p.leave_folder());
		assert(p.current_folder == ROOT_FOLDER);
		assert(p.selected_cluster == sub && p.selected == -1);

		// leaving again at root just clears the selection
		assert(p.leave_folder());
		assert(p.selected == -1 && p.selected_cluster == -1);
	};
}

fn void test_grab_move_selected()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.root = (Path)"/root".copy(tmem);
		int sub = p.add_folder("/root/sub", ROOT_FOLDER);
		p.cards.push(
			{
				.path = (Path)"/root/a.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		p.cards.push(
			{
				.path = (Path)"/root/sub/b.c3".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
				.folder = sub,
				.open = true,
			}
		);

		// moving a card keeps its folder membership
		p.select_card(0);
		float x0 = p.cards[0].rect.x;
		float y0 = p.cards[0].rect.y;
		p.move_selected({ 200.0f, 0.0f });
		assert(p.cards[0].rect.x == x0 + 200.0f);
		assert(p.cards[0].rect.y == y0);
		assert(p.cards[0].folder == ROOT_FOLDER);

		// moving a folder moves its contents
		p.select_folder(sub);
		float bx = p.cards[1].rect.x;
		p.move_selected({ 0.0f, 120.0f });
		assert(p.cards[1].rect.x == bx);
		assert(p.cards[1].rect.y == 120.0f);
	};
}

fn void test_minimize_selected_card()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.root = (Path)"/root".copy(tmem);
		p.cards.push(
			{
				.path = (Path)"/root/a.c3".copy(tmem),
				.rect = { .x = 10.0f, .y = 20.0f, .width = 900.0f, .height = 800.0f },
				.folder = ROOT_FOLDER,
				.open = true,
			}
		);
		EditorMetrics metrics = {
			.char_width = 8.0f,
			.line_height = 16.0f,
			.padding_x = 8.0f,
			.padding_y = 8.0f,
			.font_size = 16.0f,
		};

		p.select_card(0);
		p.minimize_selected(metrics);
		assert(p.cards[0].rect.x == 10.0f && p.cards[0].rect.y == 20.0f);
		assert(p.cards[0].rect.width == editor::min_card_width(metrics));
		assert(p.cards[0].rect.height == editor::min_card_height(metrics));
	};
}
fn void test_layout_compact_square()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.root = (Path)"/root".copy(tmem);
		int a = p.add_folder("/root/a", ROOT_FOLDER);
		int b = p.add_folder("/root/b", ROOT_FOLDER);
		int d = p.add_folder("/root/a/d", a);
		for (int k = 0; k < 6; k++)
		{
			String path = string::format(tmem, "/root/b/f%d.c3", k);
			p.cards.push(
				{
					.path = (Path)path.copy(tmem),
					.folder = b,
					.rect = { .width = 1.0f, .height = 1.0f },
				}
			);
		}
		for (int k = 0; k < 6; k++)
		{
			String path = string::format(tmem, "/root/a/d/g%d.c3", k);
			p.cards.push(
				{
					.path = (Path)path.copy(tmem),
					.folder = d,
					.rect = { .width = 1.0f, .height = 1.0f },
				}
			);
		}

		p.layout();

		// the nested cluster is contained in its parent
		Rect ra = p.cluster_bounds(a);
		Rect rd = p.cluster_visual_bounds(d);
		assert(rd.x >= ra.x - 0.01f && rd.y >= ra.y - 0.01f);
		assert(rd.x + rd.width <= ra.x + ra.width + 0.01f);
		assert(rd.y + rd.height <= ra.y + ra.height + 0.01f);

		// top-level siblings overlap because each level packs only chip footprints
		Rect rb = p.cluster_bounds(b);
		assert(rect_intersects(ra, rb));

		// the overall footprint is roughly square
		Rect out;
		assert(p.content_bounds(&out));
		float ratio = out.width / out.height;
		assert(ratio >= 0.5f && ratio <= 2.0f);
	};
}
fn void test_cards_revision_bumps()
{
	@pool()
	{
		Project p;
		p.init(tmem);
		p.root = (Path)"/root".copy(tmem);
		int r0    = p.cards_revision;
		int index = p.append_card("/root/a.c3", { 0.0f, 0.0f });
		assert(index == 0);
		assert(p.cards_revision == r0 + 1);
		p.remove_card(0);
		assert(p.cards_revision == r0 + 2);
	};
}