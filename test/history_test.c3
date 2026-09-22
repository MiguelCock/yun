module yun::text @test;

fn void test_undo_insert_and_delete()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "hello");
		History h;
		h.init(tmem);

		usz cursor = h.insert(&t, 5, " world", 1.0);
		assert(cursor == 11);
		assert(t.slice(0, t.length(), tmem).compare_to("hello world") == 0);

		usz after = 999;
		assert(h.undo(&t, &after));
		assert(after == 5);
		assert(t.slice(0, t.length(), tmem).compare_to("hello") == 0);

		usz back = h.backspace(&t, 5, 2.0);
		assert(back == 4);
		assert(t.slice(0, t.length(), tmem).compare_to("hell") == 0);
		assert(h.undo(&t, &after));
		assert(t.slice(0, t.length(), tmem).compare_to("hello") == 0);

		t.destroy();
		h.free();
	};
}

fn void test_typing_coalesces()
{
	@pool()
	{
		PieceTable t;
		t.init_empty(tmem);
		History h;
		h.init(tmem);

		usz cursor = 0;
		cursor = h.insert(&t, cursor, "a", 1.0);
		cursor = h.insert(&t, cursor, "b", 1.1);
		cursor = h.insert(&t, cursor, "c", 1.2);
		assert(t.slice(0, t.length(), tmem).compare_to("abc") == 0);
		assert(h.commands.len() == 1);

		usz after = 0;
		assert(h.undo(&t, &after));
		assert(after == 0);
		assert(t.length() == 0);

		t.destroy();
		h.free();
	};
}

fn void test_time_gap_splits()
{
	@pool()
	{
		PieceTable t;
		t.init_empty(tmem);
		History h;
		h.init(tmem);

		usz cursor = 0;
		cursor = h.insert(&t, cursor, "a", 0.0);
		cursor = h.insert(&t, cursor, "b", 1.0);
		assert(h.commands.len() == 2);

		usz after = 0;
		assert(h.undo(&t, &after));
		assert(t.slice(0, t.length(), tmem).compare_to("a") == 0);

		t.destroy();
		h.free();
	};
}

fn void test_backspaces_coalesce()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abcd");
		History h;
		h.init(tmem);

		usz cursor = 4;
		cursor = h.backspace(&t, cursor, 1.0);
		cursor = h.backspace(&t, cursor, 1.1);
		cursor = h.backspace(&t, cursor, 1.2);
		assert(cursor == 1);
		assert(t.slice(0, t.length(), tmem).compare_to("a") == 0);
		assert(h.commands.len() == 1);

		usz after = 0;
		assert(h.undo(&t, &after));
		assert(after == 4);
		assert(t.slice(0, t.length(), tmem).compare_to("abcd") == 0);

		t.destroy();
		h.free();
	};
}

fn void test_noop_and_empty_history()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abc");
		History h;
		h.init(tmem);

		usz after = 0;
		assert(!h.undo(&t, &after));

		(void)h.insert(&t, 3, "", 1.0);
		assert(h.commands.len() == 0);
		assert(h.delete_forward(&t, 3, 1.1) == 3);
		assert(h.commands.len() == 0);

		t.destroy();
		h.free();
	};
}

fn void test_budget_eviction()
{
	@pool()
	{
		PieceTable t;
		t.init_empty(tmem);
		History h;
		h.init(tmem);
		h.budget = 8;

		usz cursor = 0;
		h.break_coalescing();
		cursor = h.insert(&t, cursor, "aaaa", 1.0);
		h.break_coalescing();
		cursor = h.insert(&t, cursor, "bbbb", 2.0);
		assert(h.commands.len() == 2);

		h.break_coalescing();
		cursor = h.insert(&t, cursor, "cccc", 3.0);
		assert(h.commands.len() == 2);
		assert(h.index == 2);
		assert(h.memory <= 8);

		t.destroy();
		h.free();
	};
}