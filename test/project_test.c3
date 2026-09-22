module yun::project @test;

import raylib6::rl;
import std::io::file;
import std::io::path;
import std::math;
import yun::card;

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

fn void test_path_is_ignored()
{
	assert(path_is_ignored("/home/x/proj/.git/config"));
	assert(path_is_ignored("/home/x/proj/build/out.o"));
	assert(path_is_ignored("/home/x/proj/node_modules/pkg/index.js"));
	assert(path_is_ignored("C:\\proj\\.yun\\workspace.json"));
	assert(!path_is_ignored("/home/x/proj/src/main.c3"));
	assert(!path_is_ignored("/home/x/proj/builder/main.c3"));
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

fn void test_layout_position_grid()
{
	assert(layout_position(0)[0] == 0.0f && layout_position(0)[1] == 0.0f);
	assert(layout_position(1)[0] == LAYOUT_CELL_W);
	assert(layout_position(LAYOUT_COLUMNS)[0] == 0.0f);
	assert(layout_position(LAYOUT_COLUMNS)[1] == LAYOUT_CELL_H);
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

		// expanding all folders makes every card visible again
		for (sz i = 0; i < p.folders.len(); i++)
		{
			p.toggle_collapse((int)i);
		}
		for (sz i = 0; i < p.cards.len(); i++)
		{
			assert(p.card_visible((int)i));
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