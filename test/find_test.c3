module yun::find @test;

import std::collections::list;
import yun::text;

fn void test_match_at_case()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "Hello hello HELLO");

		assert(match_at(&t, 0, "Hello", true, false));
		assert(!match_at(&t, 0, "hello", true, false));
		assert(match_at(&t, 0, "hello", false, false));
		assert(match_at(&t, 6, "hello", true, false));
		assert(match_at(&t, 12, "hello", false, false));
		assert(!match_at(&t, 0, "xyz", false, false));
		t.destroy();
	};
}

fn void test_match_whole_word()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "cat category cat.");

		assert(match_at(&t, 0, "cat", true, true));
		assert(!match_at(&t, 4, "cat", true, true));
		assert(match_at(&t, 4, "cat", true, false));
		assert(match_at(&t, 13, "cat", true, true));
		t.destroy();
	};
}

fn void test_next_prev_wrap()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "aXbXcX");

		usz at = 0;
		assert(next_match(&t, 0, "X", true, false, &at));
		assert(at == 1);
		assert(next_match(&t, 2, "X", true, false, &at));
		assert(at == 3);
		assert(next_match(&t, 4, "X", true, false, &at));
		assert(at == 5);
		assert(next_match(&t, 6, "X", true, false, &at));
		assert(at == 1);

		assert(prev_match(&t, 5, "X", true, false, &at));
		assert(at == 3);
		assert(prev_match(&t, 1, "X", true, false, &at));
		assert(at == 5);
		t.destroy();
	};
}

fn void test_count_and_cap()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "aa aa aa aa");
		assert(count_matches(&t, "aa", true, false, MATCH_COUNT_CAP) == 4);
		assert(count_matches(&t, "aa", true, false, 2) == 2);
		assert(count_matches(&t, "", true, false, MATCH_COUNT_CAP) == 0);

		List{usz} starts;
		starts.init(tmem);
		usz found = collect_matches(&t, "aa", true, false, MATCH_COUNT_CAP, &starts);
		assert(found == 4);
		assert(starts.len() == 4);
		assert(starts[0] == 0 && starts[1] == 3 && starts[2] == 6 && starts[3] == 9);
		starts.free();
		t.destroy();
	};
}

fn void test_overlaps_are_skipped()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "aaaa");
		assert(count_matches(&t, "aa", true, false, MATCH_COUNT_CAP) == 2);
		t.destroy();
	};
}

fn void test_replace_at_undoable()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "hello world");
		History h;
		h.init(tmem);

		usz cursor = replace_at(&t, &h, 0, 5, "hi", 0.0);
		assert(t.slice(0, t.length(), tmem).compare_to("hi world") == 0);
		assert(cursor == 2);

		assert(h.undo(&t, &cursor));
		assert(t.slice(0, t.length(), tmem).compare_to("hello world") == 0);
		h.free();
		t.destroy();
	};
}

fn void test_replace_all_backwards()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "a b a b a");
		History h;
		h.init(tmem);

		usz replaced = replace_all(&t, &h, "a", "XY", true, false, MATCH_COUNT_CAP, 0.0);
		assert(replaced == 3);
		assert(t.slice(0, t.length(), tmem).compare_to("XY b XY b XY") == 0);

		usz cursor = 0;
		assert(h.undo(&t, &cursor));
		assert(t.slice(0, t.length(), tmem).compare_to("a b XY b XY") == 0);
		assert(h.undo(&t, &cursor));
		assert(h.undo(&t, &cursor));
		assert(t.slice(0, t.length(), tmem).compare_to("a b a b a") == 0);
		h.free();
		t.destroy();
	};
}