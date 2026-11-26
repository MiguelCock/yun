module yun::search @test;

import std::collections::list;
import std::io::file;
import std::io::path;
import yun::editor;
import yun::project;

fn void test_find_in_line_case_insensitive()
{
	usz[8] cols;
	String line = "Foo foo FOO";
	usz n       = find_in_line(line, "foo", false, false, cols[0:8], 8);
	assert(n == 3);
	assert(cols[0] == 0 && cols[1] == 4 && cols[2] == 8);
}

fn void test_find_in_line_case_sensitive()
{
	usz[8] cols;
	String line = "Foo foo FOO";
	usz n       = find_in_line(line, "foo", true, false, cols[0:8], 8);
	assert(n == 1);
	assert(cols[0] == 4);
}

fn void test_find_in_line_whole_word()
{
	usz[8] cols;
	String line = "foo foobar foo";
	usz n       = find_in_line(line, "foo", true, true, cols[0:8], 8);
	assert(n == 2);
	assert(cols[0] == 0 && cols[1] == 11);
}

fn void test_find_in_line_empty_query()
{
	usz[4] cols;
	assert(find_in_line("abc", "", false, false, cols[0:4], 4) == 0);
}

fn void test_find_in_line_cap()
{
	usz[2] cols;
	String line = "a a a a";
	assert(find_in_line(line, "a", false, false, cols[0:2], 2) == 2);
}

fn void test_scan_file_path()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_search_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "a.txt");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "hello world\nsecond hello\n")) return;

		List{SearchMatch} out;
		out.init(mem);
		scan_file_path(mem, (String)f, "hello", false, false, &out);
		assert(out.len() == 2);
		assert(out[0].line == 0 && out[0].column == 0);
		assert(out[1].line == 1 && out[1].column == 7);

		for (sz i = 0; i < out.len(); i++) out[i].preview.free(mem);
		out.free();
		(void)path::rmtree(dir);
	};
}
fn void test_hold_repeats_after_delay()
{
	Search s = { };
	s.total_matches = 3;
	s.selected = 0;

	s.begin_hold(1, 10.0);
	s.hold_tick(true, false, 10.29);
	assert(s.selected == 0);
	s.hold_tick(true, false, 10.31);
	assert(s.selected == 1);
	s.hold_tick(true, false, 10.34);
	assert(s.selected == 1);
	s.hold_tick(true, false, 10.36);
	assert(s.selected == 2);
	s.hold_tick(true, false, 10.50);
	assert(s.selected == 2);
}

fn void test_hold_stops_on_release()
{
	Search s = { };
	s.total_matches = 3;
	s.selected = 2;

	s.begin_hold(-1, 0.0);
	s.hold_tick(false, true, 0.31);
	assert(s.selected == 1);
	s.hold_tick(false, false, 0.32);
	assert(s.hold_dir == 0);
	s.hold_tick(false, true, 5.0);
	assert(s.selected == 1);
	assert(s.hold_dir == 0);
}
fn void test_replace_closed_file_on_disk()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_search_replace");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "a.txt");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "foo bar\nfoo baz\n")) return;

		project::Project p;
		p.init(mem);
		if (p.root.len) p.root.free(mem);
		p.root = (Path)((String)dir).copy(mem);
		int card = p.append_card((String)f, { 0.0f, 0.0f });
		assert(card == 0);
		assert(p.cards[0].buffer == null);

		Search s;
		s.init(mem);
		s.query_len = 3;
		s.query[0] = 'f';
		s.query[1] = 'o';
		s.query[2] = 'o';
		s.query[3] = 0;
		s.replace_len = 3;
		s.replacement[0] = 'b';
		s.replacement[1] = 'a';
		s.replacement[2] = 'r';
		s.replacement[3] = 0;

		SearchGroup group;
		group.path = ((String)f).copy(mem);
		group.matches.init(mem);
		group.matches.push({ .line = 0, .column = 0, .preview = "" });
		group.matches.push({ .line = 1, .column = 0, .preview = "" });
		s.groups.push(group);
		s.group_index.set(group.path, 0);
		s.total_matches = 2;

		String error = "";
		int files    = 0;
		int replaced = s.replace_all_matches(&p, 0.0, &error, &files);
		assert(replaced == 2);
		assert(files == 1);
		assert(error.len == 0);
		assert(p.cards[0].buffer == null);

		char[]? data = file::load(tmem, (String)f);
		if (catch excuse = data) return;
		assert(((String)data).compare_to("bar bar\nbar baz\n") == 0);
		s.destroy();
		p.destroy();
		(void)path::rmtree(dir);
	};
}
fn void test_replace_keeps_open_file_dirty()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_search_replace_open");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "a.txt");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "foo\n")) return;

		project::Project p;
		p.init(mem);
		if (p.root.len) p.root.free(mem);
		p.root = (Path)((String)dir).copy(mem);
		int card = p.append_card((String)f, { 0.0f, 0.0f });
		editor::ensure_buffer(&p.cards[card], p.allocator);
		assert(p.cards[card].buffer != null);

		Search s;
		s.init(mem);
		s.query_len = 3;
		s.query[0] = 'f';
		s.query[1] = 'o';
		s.query[2] = 'o';
		s.query[3] = 0;
		s.replace_len = 3;
		s.replacement[0] = 'b';
		s.replacement[1] = 'a';
		s.replacement[2] = 'r';
		s.replacement[3] = 0;

		SearchGroup group;
		group.path = ((String)f).copy(mem);
		group.matches.init(mem);
		group.matches.push({ .line = 0, .column = 0, .preview = "" });
		s.groups.push(group);
		s.group_index.set(group.path, 0);
		s.total_matches = 1;

		String error = "";
		int files    = 0;
		int replaced = s.replace_all_matches(&p, 0.0, &error, &files);
		assert(replaced == 1);
		assert(error.len == 0);
		assert(p.cards[card].dirty);
		assert(p.cards[card].buffer != null);
		assert(p.cards[card].buffer.slice(0, p.cards[card].buffer.length(), tmem).compare_to("bar\n") == 0);

		char[]? data = file::load(tmem, (String)f);
		if (catch excuse = data) return;
		assert(((String)data).compare_to("foo\n") == 0);

		s.destroy();
		p.destroy();
		(void)path::rmtree(dir);
	};
}