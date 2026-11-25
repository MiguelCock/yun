module yun::vim @test;

import yun::text;

fn void test_normal_motions_and_counts()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "one two three\nfour five\nsix");
		History h;
		h.init(mem);
		State s;
		s.init(mem);
		usz cursor = 0;
		usz anchor = 0;

		(void)s.handle(&t, &h, &cursor, &anchor, 'w', 0);
		assert(cursor == 4);
		(void)s.handle(&t, &h, &cursor, &anchor, 'w', 0);
		assert(cursor == 8);
		(void)s.handle(&t, &h, &cursor, &anchor, '2', 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'b', 0);
		assert(cursor == 0);

		cursor = 0;
		(void)s.handle(&t, &h, &cursor, &anchor, 'e', 0);
		assert(cursor == 2);
		(void)s.handle(&t, &h, &cursor, &anchor, 'l', 0);
		assert(cursor == 3);
		(void)s.handle(&t, &h, &cursor, &anchor, '3', 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'l', 0);
		assert(cursor == 6);
		(void)s.handle(&t, &h, &cursor, &anchor, '$', 0);
		assert(cursor == 12);
		(void)s.handle(&t, &h, &cursor, &anchor, '0', 0);
		assert(cursor == 0);

		(void)s.handle(&t, &h, &cursor, &anchor, 'j', 0);
		assert(cursor == 14);
		(void)s.handle(&t, &h, &cursor, &anchor, 'G', 0);
		assert(cursor == t.line_start(2));
		(void)s.handle(&t, &h, &cursor, &anchor, '2', 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'g', 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'g', 0);
		assert(cursor == t.line_start(1));

		s.destroy();
		h.free();
		t.destroy();
	};
}

fn void test_insert_mode_transitions()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abc\ndef");
		History h;
		h.init(mem);
		State s;
		s.init(mem);
		usz cursor = 0;
		usz anchor = 0;

		(void)s.handle(&t, &h, &cursor, &anchor, 'i', 0);
		assert(s.mode == Mode.INSERT);
		(void)s.handle(&t, &h, &cursor, &anchor, 27, 0);
		assert(s.mode == Mode.NORMAL);
		assert(cursor == 0);

		(void)s.handle(&t, &h, &cursor, &anchor, 'a', 0);
		assert(s.mode == Mode.INSERT);
		assert(cursor == 1);
		(void)s.handle(&t, &h, &cursor, &anchor, 27, 0);
		assert(s.mode == Mode.NORMAL);

		(void)s.handle(&t, &h, &cursor, &anchor, 'I', 0);
		assert(cursor == 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 27, 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'A', 0);
		assert(cursor == 3);
		(void)s.handle(&t, &h, &cursor, &anchor, 27, 0);

		(void)s.handle(&t, &h, &cursor, &anchor, 'o', 0);
		assert(s.mode == Mode.INSERT);
		assert(t.line_count() == 3);
		(void)s.handle(&t, &h, &cursor, &anchor, 27, 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'O', 0);
		assert(s.mode == Mode.INSERT);
		assert(t.line_count() == 4);
		(void)s.handle(&t, &h, &cursor, &anchor, 27, 0);

		(void)s.handle(&t, &h, &cursor, &anchor, 'v', 0);
		assert(s.mode == Mode.VISUAL);
		(void)s.handle(&t, &h, &cursor, &anchor, 'v', 0);
		assert(s.mode == Mode.NORMAL);

		s.destroy();
		h.free();
		t.destroy();
	};
}

fn void test_operators_and_registers()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abc\ndef\nghi");
		History h;
		h.init(mem);
		State s;
		s.init(mem);
		usz cursor = 0;
		usz anchor = 0;

		assert(s.handle(&t, &h, &cursor, &anchor, 'x', 0));
		assert(t.slice(0, t.length(), tmem).compare_to("bc\ndef\nghi") == 0);
		assert(s.register_text.compare_to("a") == 0);
		assert(s.handle(&t, &h, &cursor, &anchor, 'u', 0));
		assert(t.slice(0, t.length(), tmem).compare_to("abc\ndef\nghi") == 0);
		assert(s.handle(&t, &h, &cursor, &anchor, 18, 0));
		assert(t.slice(0, t.length(), tmem).compare_to("bc\ndef\nghi") == 0);

		s.destroy();
		h.free();
		t.destroy();
	};

	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abc\ndef\nghi");
		History h;
		h.init(mem);
		State s;
		s.init(mem);
		usz cursor = 0;
		usz anchor = 0;

		(void)s.handle(&t, &h, &cursor, &anchor, 'd', 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'd', 0);
		assert(t.slice(0, t.length(), tmem).compare_to("def\nghi") == 0);
		assert(s.register_text.compare_to("abc") == 0);
		assert(s.register_linewise);

		(void)s.handle(&t, &h, &cursor, &anchor, 'y', 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'y', 0);
		assert(s.handle(&t, &h, &cursor, &anchor, 'p', 0));
		assert(t.slice(0, t.length(), tmem).compare_to("def\ndef\nghi") == 0);

		s.destroy();
		h.free();
		t.destroy();
	};

	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abc");
		History h;
		h.init(mem);
		State s;
		s.init(mem);
		usz cursor = 0;
		usz anchor = 0;

		(void)s.handle(&t, &h, &cursor, &anchor, '3', 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'x', 0);
		assert(t.length() == 0);

		s.destroy();
		h.free();
		t.destroy();
	};
}

fn void test_visual_selection()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abc\ndef");
		History h;
		h.init(mem);
		State s;
		s.init(mem);
		usz cursor = 0;
		usz anchor = 0;

		(void)s.handle(&t, &h, &cursor, &anchor, 'v', 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'l', 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'l', 0);
		assert(cursor == 2);
		assert(anchor == 0);
		assert(s.handle(&t, &h, &cursor, &anchor, 'd', 0));
		assert(t.slice(0, t.length(), tmem).compare_to("\ndef") == 0);
		assert(s.mode == Mode.NORMAL);
		assert(cursor == 0);

		s.destroy();
		h.free();
		t.destroy();
	};

	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abc\ndef");
		History h;
		h.init(mem);
		State s;
		s.init(mem);
		usz cursor = 0;
		usz anchor = 0;

		(void)s.handle(&t, &h, &cursor, &anchor, 'v', 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'l', 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'y', 0);
		assert(s.register_text.compare_to("ab") == 0);
		assert(s.mode == Mode.NORMAL);

		s.destroy();
		h.free();
		t.destroy();
	};
}

fn void test_change_line_enters_insert()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abc\ndef");
		History h;
		h.init(mem);
		State s;
		s.init(mem);
		usz cursor = 4;
		usz anchor = 4;

		(void)s.handle(&t, &h, &cursor, &anchor, 'c', 0);
		(void)s.handle(&t, &h, &cursor, &anchor, 'c', 0);
		assert(s.mode == Mode.INSERT);
		assert(t.slice(0, t.length(), tmem).compare_to("abc\n") == 0);
		assert(cursor == 4);

		s.destroy();
		h.free();
		t.destroy();
	};
}
fn void test_search_requests()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abc");
		History h;
		h.init(mem);
		State s;
		s.init(mem);
		usz cursor = 0;
		usz anchor = 0;

		assert(!s.handle(&t, &h, &cursor, &anchor, '/', 0));
		assert(s.take_request() == Request.SEARCH_FORWARD);
		assert(!s.handle(&t, &h, &cursor, &anchor, '?', 0));
		assert(s.take_request() == Request.SEARCH_BACKWARD);
		assert(!s.handle(&t, &h, &cursor, &anchor, ':', 0));
		assert(s.take_request() == Request.COMMAND);
		assert(!s.handle(&t, &h, &cursor, &anchor, 'n', 0));
		assert(s.take_request() == Request.SEARCH_NEXT);
		assert(!s.handle(&t, &h, &cursor, &anchor, 'N', 0));
		assert(s.take_request() == Request.SEARCH_PREV);
		assert(s.take_request() == Request.NONE);

		s.destroy();
		h.free();
		t.destroy();
	};
}