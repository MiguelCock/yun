module yun::search @test;

import std::collections::list;
import std::io::file;
import std::io::path;

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