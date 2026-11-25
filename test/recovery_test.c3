module yun::recovery @test;

import std::io::file;
import std::io::path;
import yun::canvas;
import yun::editor;
import yun::project;

fn void test_recovery_roundtrip()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_recovery");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "a.c3");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "fn int main() { return 0; }\n")) return;

		project::Project p;
		p.init(mem);
		if (p.root.len) p.root.free(mem);
		p.root = (Path)((String)dir).copy(mem);
		(void)p.append_card((String)f, { 0.0f, 0.0f });
		editor::restore_buffer(&p.cards[0], "recovered text\n", mem);

		canvas::Canvas canvas;
		canvas.init();
		assert(available(&p) == false);
		assert(begin(&p));
		assert(journal(&p, &canvas, null));
		assert(available(&p));

		project::Project restored;
		restored.init(mem);
		if (restored.root.len) restored.root.free(mem);
		restored.root = (Path)((String)dir).copy(mem);
		(void)restored.append_card((String)f, { 0.0f, 0.0f });

		RecoveryResult result;
		assert(restore(&restored, &canvas, null, &result));
		assert(result.restored == 1);
		assert(result.layout);
		assert(restored.cards[0].buffer != null);
		assert(restored.cards[0].buffer.length() == 15);
		assert(restored.cards[0].dirty);
		clear(&restored);
		assert(available(&restored) == false);

		restored.destroy();
		p.destroy();
		(void)path::rmtree(dir);
	};
}