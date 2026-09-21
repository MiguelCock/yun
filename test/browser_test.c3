module yun::browser @test;

import std::io::file;
import std::io::path;

fn void test_browser_lists_directories_only()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_browser_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;

		Path? alpha = dir.append(tmem, "alpha");
		if (catch excuse = alpha) return;
		if (catch excuse = path::mkdir(alpha)) return;
		Path? beta = dir.append(tmem, "beta");
		if (catch excuse = beta) return;
		if (catch excuse = path::mkdir(beta)) return;

		char[] content = { 'x' };
		Path? note     = dir.append(tmem, "note.txt");
		if (catch excuse = note) return;
		if (catch excuse = file::save(note, content)) return;

		Browser b;
		b.init(tmem);
		b.open_at((String)dir);
		assert(b.open);
		assert(b.entries.len() == 2);
		assert(b.rows() == 4);
		assert(b.selected == 0);

		b.move_selection(100);
		assert(b.selected == b.rows() - 1);
		b.move_selection(-100);
		assert(b.selected == 0);

		(void)path::rmtree(dir);
	};
}