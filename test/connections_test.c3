module yun::connections @test;

fn void test_file_name_view()
{
	assert(file_name_view("/home/me/project/src/main.c3").compare_to("main.c3") == 0);
	assert(file_name_view("C:\\project\\src\\main.c3").compare_to("main.c3") == 0);
	assert(file_name_view("main.c3").compare_to("main.c3") == 0);
}
import std::io::path;
import yun::card;
import yun::imports;
import yun::project;

fn void test_refresh_outgoing_and_incoming()
{
	@pool()
	{
		project::Project project;
		project.init(tmem);
		FileCard a;
		a.path = (Path)"/a.c3".copy(tmem);
		a.name = "a.c3";
		project.cards.push(a);
		FileCard b;
		b.path = (Path)"/b.c3".copy(tmem);
		b.name = "b.c3";
		project.cards.push(b);
		project.focused = 0;

		imports::ImportIndex index;
		index.files.init(tmem);
		index.file_index.init(tmem);
		CardImports ca;
		ca.path = "/a.c3".copy(tmem);
		ca.module_name = "a".copy(tmem);
		ca.is_test = false;
		ca.imports.init(tmem);
		ca.imports.push(
			{
				.specifier = "/b.c3".copy(tmem),
				.target_path = "/b.c3".copy(tmem),
				.kind = "import".copy(tmem),
				.resolved = true,
				.line = 2,
				.column = 0,
			}
		);
		index.files.push(ca);
		index.file_index.set("/a.c3", 0);
		CardImports cb;
		cb.path = "/b.c3".copy(tmem);
		cb.module_name = "b".copy(tmem);
		cb.is_test = false;
		cb.imports.init(tmem);
		cb.imports.push(
			{
				.specifier = "/a.c3".copy(tmem),
				.target_path = "/a.c3".copy(tmem),
				.kind = "import".copy(tmem),
				.resolved = true,
				.line = 4,
				.column = 0,
			}
		);
		index.files.push(cb);
		index.file_index.set("/b.c3", 1);

		Connections conns;
		conns.init(tmem);
		conns.show();
		conns.refresh(&project, &index);
		assert(conns.rows.len() == 2);
		assert(!conns.rows[0].incoming);
		assert(conns.rows[0].path.compare_to("/a.c3") == 0);
		assert(conns.rows[0].other.compare_to("/b.c3") == 0);
		assert(conns.rows[1].incoming);
		assert(conns.rows[1].path.compare_to("/b.c3") == 0);
		assert(conns.rows[1].other.compare_to("/a.c3") == 0);
		conns.destroy();
	};
}