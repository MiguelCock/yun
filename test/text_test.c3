module yun::text @test;

import std::io::file;
import std::io::path;

fn void test_insert_delete_slice()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "hello world");
		assert(t.length() == 11);
		assert(t.slice(0, 5, tmem).compare_to("hello") == 0);
		assert(t.slice(6, 5, tmem).compare_to("world") == 0);

		t.insert(5, ", brave");
		assert(t.slice(0, t.length(), tmem).compare_to("hello, brave world") == 0);

		t.delete(5, 7);
		assert(t.slice(0, t.length(), tmem).compare_to("hello world") == 0);
		t.destroy();
	};
}

fn void test_edit_offsets()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abc");
		Edit ins = t.insert(1, "XY");
		assert(ins.start_byte == 1 && ins.old_end_byte == 1 && ins.new_end_byte == 3);

		Edit del = t.delete(1, 2);
		assert(del.start_byte == 1 && del.old_end_byte == 3 && del.new_end_byte == 1);
		t.destroy();
	};
}

fn void test_piece_count_bounded()
{
	@pool()
	{
		PieceTable t;
		t.init_empty(tmem);
		for (int i = 0; i < 100; i++)
		{
			t.insert(t.length(), "a");
		}
		assert(t.length() == 100);
		assert(t.pieces.len() <= 2);
		assert(t.char_at(0) == 'a');
		assert(t.char_at(99) == 'a');
		t.destroy();
	};
}

fn void test_line_index()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "one\ntwo\nthree");
		assert(t.line_count() == 3);
		assert(t.line_of(0) == 0);
		assert(t.line_of(4) == 1);
		assert(t.line_of(8) == 2);
		assert(t.offset_of(1, 0) == 4);
		assert(t.offset_of(2, 2) == 10);

		t.insert(3, "\nX");
		assert(t.line_count() == 4);
		assert(t.line_of(4) == 1);
		assert(t.line_of(6) == 2);
		t.destroy();
	};
}

fn void test_utf8_boundaries()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "aé b");
		assert(t.length() == 5);
		assert(t.next_boundary(1) == 3);
		assert(t.prev_boundary(2) == 1);
		assert(t.slice(1, 2, tmem).compare_to("é") == 0);
		t.destroy();
	};
}

fn void test_mmap_file()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_text_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "text.txt");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "line1\nline2")) return;

		PieceTable t;
		assert(t.init_from_file(tmem, (String)f));
		assert(t.length() == 11);
		assert(t.line_count() == 2);
		t.insert(5, "!");
		assert(t.slice(0, t.length(), tmem).compare_to("line1!\nline2") == 0);
		t.destroy();

		(void)path::rmtree(dir);
	};
}
fn void test_save_to_file()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_text_save");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "save.txt");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "abc")) return;

		PieceTable t;
		assert(t.init_from_file(tmem, (String)f));
		t.insert(3, "def");
		assert(t.save_to_file((String)f, tmem));
		assert(t.slice(0, t.length(), tmem).compare_to("abcdef") == 0);
		t.destroy();

		PieceTable check;
		assert(check.init_from_file(tmem, (String)f));
		assert(check.slice(0, check.length(), tmem).compare_to("abcdef") == 0);
		check.destroy();

		(void)path::rmtree(dir);
	};
}