module yun::symbols @test;

import std::collections::list;
import std::io::file;
import std::io::path;
import yun::highlight;

macro bool has_symbol(list, name)
{
	for (sz i = 0; i < (*list).len(); i++)
	{
		if ((*list)[i].name.compare_to(name) == 0) return true;
	}
	return false;
}

macro void free_symbols(list)
{
	for (sz i = 0; i < (*list).len(); i++) (*list)[i].name.free(mem);
	(*list).free();
}

fn void test_extract_c3()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_sym_c3");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "a.c3");
		if (catch excuse = f) return;
		String src = "module demo;\nstruct Foo { int x; }\nenum Bar { A, B }\nfn int add(int a, int b) { return a + b; }\n";
		if (catch excuse = file::save(f, src)) return;

		List{Symbol} out;
		out.init(mem);
		extract_file(mem, (String)f, highlight::Language.C3, &out);
		assert(has_symbol(&out, "Foo"));
		assert(has_symbol(&out, "Bar"));
		assert(has_symbol(&out, "add"));
		free_symbols(&out);
		(void)path::rmtree(dir);
	};
}

fn void test_extract_c()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_sym_c");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "a.c");
		if (catch excuse = f) return;
		String src = "int add(int a, int b) { return a + b; }\nstruct Foo { int x; };\nenum Bar { A, B };\nint g;\n";
		if (catch excuse = file::save(f, src)) return;

		List{Symbol} out;
		out.init(mem);
		extract_file(mem, (String)f, highlight::Language.C, &out);
		assert(has_symbol(&out, "add"));
		assert(has_symbol(&out, "Foo"));
		assert(has_symbol(&out, "Bar"));
		assert(has_symbol(&out, "g"));
		free_symbols(&out);
		(void)path::rmtree(dir);
	};
}

fn void test_extract_python()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_sym_py");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "a.py");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "def add(a, b):\n    return a + b\n\nclass Foo:\n    pass\n")) return;

		List{Symbol} out;
		out.init(mem);
		extract_file(mem, (String)f, highlight::Language.PYTHON, &out);
		assert(has_symbol(&out, "add"));
		assert(has_symbol(&out, "Foo"));
		free_symbols(&out);
		(void)path::rmtree(dir);
	};
}

fn void test_extract_javascript()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_sym_js");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "a.js");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "function add(a, b) { return a + b; }\nclass Foo {}\nconst g = 1;\n")) return;

		List{Symbol} out;
		out.init(mem);
		extract_file(mem, (String)f, highlight::Language.JAVASCRIPT, &out);
		assert(has_symbol(&out, "add"));
		assert(has_symbol(&out, "Foo"));
		assert(has_symbol(&out, "g"));
		free_symbols(&out);
		(void)path::rmtree(dir);
	};
}

fn void test_refilter_filters()
{
	@pool()
	{
		Symbols s;
		s.init(mem);
		List{Symbol} syms;
		syms.init(mem);
		syms.push({ .name = "alpha".copy(mem), .kind = SymbolKind.FUNCTION, .line = 0, .column = 0 });
		syms.push({ .name = "beta".copy(mem), .kind = SymbolKind.TYPE, .line = 0, .column = 0 });
		s.store("/root/a.c3", &syms);

		s.query[0] = 'b';
		s.query[1] = 'e';
		s.query[2] = 0;
		s.query_len = 2;
		s.refilter();
		assert(s.matches.len() == 1);
		Symbol* symbol = s.symbol_of(s.matches[0]);
		assert(symbol.name.compare_to("beta") == 0);
		s.destroy();
	};
}