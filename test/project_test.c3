module yun::project @test;

import raylib6::rl;
import std::io::path;
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
		p.cards.push({ .path = (Path)"/tmp/a.c3".copy(tmem), .name = "a.c3".copy(tmem) });
		p.cards.push({ .path = (Path)"/tmp/b.c3".copy(tmem), .name = "b.c3".copy(tmem) });
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
			}
		);
		p.cards.push(
			{
				.path = (Path)"/tmp/b".copy(tmem),
				.rect = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f },
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