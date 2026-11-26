module yun::connection_details;

import std::collections::list;
import std::io::file;
import std::io::path;
import yun::project;
import yun::symbols;

fn void test_named_import_alias_and_usage() @test
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_connection_details");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? source_path = dir.append(tmem, "source.ts");
		if (catch excuse = source_path) return;
		Path? target_path = dir.append(tmem, "target.ts");
		if (catch excuse = target_path) return;
		if (catch excuse = file::save(source_path, "import { foo as bar } from \"target\";\nbar();\nfoo();\n")) return;
		if (catch excuse = file::save(target_path, "export function foo() {}\n")) return;

		project::Project p;
		p.init(mem);
		if (p.root.len) p.root.free(mem);
		p.root = (Path)((String)dir).copy(mem);
		(void)p.append_card((String)source_path, { 0.0f, 0.0f });
		(void)p.append_card((String)target_path, { 0.0f, 0.0f });

		symbols::Symbols index;
		index.init(mem);
		List{symbols::Symbol} target_symbols;
		target_symbols.init(mem);
		target_symbols.push({ .name = "foo".copy(mem), .kind = symbols::SymbolKind.FUNCTION, .line = 0, .column = 16 });
		index.store((String)target_path, &target_symbols);

		Details details;
		details.init(mem);
		details.build(mem, &p, &index, (String)source_path, (String)target_path, 0);
		assert(details.symbols.len() == 1);
		assert(details.symbols[0].name.compare_to("foo") == 0);
		assert(details.symbols[0].alias_name.compare_to("bar") == 0);
		assert(details.symbols[0].usages.len() == 1);
		assert(details.symbols[0].usages[0].line == 1);
		assert(details.total_usages == 1);

		details.destroy(mem);
		index.destroy();
		p.destroy();
		(void)path::rmtree(dir);
	};
}
fn void test_external_named_clause() @test
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_connection_details_external");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? source_path = dir.append(tmem, "source.ts");
		if (catch excuse = source_path) return;
		if (catch excuse = file::save(
			source_path,
			"import { foo, bar as baz } from \"pkg\";\nfoo();\nbaz();\n"
		)) return;

		project::Project p;
		p.init(mem);
		if (p.root.len) p.root.free(mem);
		p.root = (Path)((String)dir).copy(mem);
		(void)p.append_card((String)source_path, { 0.0f, 0.0f });

		symbols::Symbols index;
		index.init(mem);

		Details details;
		details.init(mem);
		details.build(mem, &p, &index, (String)source_path, "", 0);
		assert(details.external);
		assert(details.named);
		assert(details.symbols.len() == 2);
		assert(details.symbols[0].name.compare_to("foo") == 0);
		assert(details.symbols[0].kind.compare_to("import") == 0);
		assert(details.symbols[0].usages.len() == 1);
		assert(details.symbols[1].name.compare_to("bar") == 0);
		assert(details.symbols[1].alias_name.compare_to("baz") == 0);
		assert(details.symbols[1].usages.len() == 1);
		assert(details.total_usages == 2);

		details.destroy(mem);
		index.destroy();
		p.destroy();
		(void)path::rmtree(dir);
	};
}

fn void test_module_only_fallback() @test
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_connection_details_module");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? source_path = dir.append(tmem, "source.c3");
		if (catch excuse = source_path) return;
		Path? target_path = dir.append(tmem, "util.c3");
		if (catch excuse = target_path) return;
		if (catch excuse = file::save(
			source_path,
			"module app;\nimport util;\nfn void hello()\n{\n\tutil::add(1, 2);\n}\n"
		)) return;
		if (catch excuse = file::save(
			target_path,
			"module util;\n\nfn int add(int a, int b)\n{\n\treturn a + b;\n}\n"
		)) return;

		project::Project p;
		p.init(mem);
		if (p.root.len) p.root.free(mem);
		p.root = (Path)((String)dir).copy(mem);
		(void)p.append_card((String)source_path, { 0.0f, 0.0f });
		(void)p.append_card((String)target_path, { 0.0f, 0.0f });

		symbols::Symbols index;
		index.init(mem);
		List{symbols::Symbol} target_symbols;
		target_symbols.init(mem);
		target_symbols.push({ .name = "add".copy(mem), .kind = symbols::SymbolKind.FUNCTION, .line = 2, .column = 5 });
		target_symbols.push({ .name = "sub".copy(mem), .kind = symbols::SymbolKind.FUNCTION, .line = 7, .column = 5 });
		index.store((String)target_path, &target_symbols);

		Details details;
		details.init(mem);
		details.build(mem, &p, &index, (String)source_path, (String)target_path, 1);
		assert(!details.named);
		assert(details.indexed);
		assert(details.symbols.len() == 1);
		assert(details.symbols[0].name.compare_to("add") == 0);
		assert(details.symbols[0].has_target);
		assert(details.symbols[0].line == 2);
		assert(details.symbols[0].column == 5);
		assert(details.symbols[0].usages.len() == 1);
		assert(details.symbols[0].usages[0].line == 4);
		assert(details.total_usages == 1);

		details.destroy(mem);
		index.destroy();
		p.destroy();
		(void)path::rmtree(dir);
	};
}

fn void test_python_from_clause() @test
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_connection_details_python");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? source_path = dir.append(tmem, "source.py");
		if (catch excuse = source_path) return;
		if (catch excuse = file::save(source_path, "from pkg import foo as f\nf()\n")) return;

		project::Project p;
		p.init(mem);
		if (p.root.len) p.root.free(mem);
		p.root = (Path)((String)dir).copy(mem);
		(void)p.append_card((String)source_path, { 0.0f, 0.0f });

		symbols::Symbols index;
		index.init(mem);

		Details details;
		details.init(mem);
		details.build(mem, &p, &index, (String)source_path, "", 0);
		assert(details.external);
		assert(details.named);
		assert(details.symbols.len() == 1);
		assert(details.symbols[0].name.compare_to("foo") == 0);
		assert(details.symbols[0].alias_name.compare_to("f") == 0);
		assert(details.symbols[0].usages.len() == 1);

		details.destroy(mem);
		index.destroy();
		p.destroy();
		(void)path::rmtree(dir);
	};
}
fn void clear_clauses(Allocator allocator, List{ClauseName}* clauses)
{
	for (sz i = 0; i < clauses.len(); i++) clauses.get_ref(i).destroy(allocator);
	clauses.clear();
}

fn void test_clause_extraction_languages() @test
{
	@pool()
	{
		List{ClauseName} names;
		List{ClauseName} aliases;
		names.init(tmem);
		aliases.init(tmem);

		extract_clause_names(tmem, "import com.example.Foo;", "a.java", &names, &aliases);
		assert(names.len() == 1 && names[0].name.compare_to("Foo") == 0);
		clear_clauses(tmem, &names);
		clear_clauses(tmem, &aliases);

		extract_clause_names(tmem, "import com.example.Foo as Bar", "a.kt", &names, &aliases);
		assert(names.len() == 1 && names[0].name.compare_to("Foo") == 0);
		assert(names[0].local_name.compare_to("Bar") == 0);
		clear_clauses(tmem, &names);
		clear_clauses(tmem, &aliases);

		extract_clause_names(tmem, "using F = System.Foo;", "a.cs", &names, &aliases);
		assert(names.len() == 1 && names[0].name.compare_to("Foo") == 0);
		assert(names[0].local_name.compare_to("F") == 0);
		clear_clauses(tmem, &names);
		clear_clauses(tmem, &aliases);

		extract_clause_names(tmem, "import com.example.{Foo => F}", "a.scala", &names, &aliases);
		assert(names.len() == 1 && names[0].name.compare_to("Foo") == 0);
		assert(names[0].local_name.compare_to("F") == 0);
		clear_clauses(tmem, &names);
		clear_clauses(tmem, &aliases);

		extract_clause_names(tmem, "use crate::{foo, bar as baz};", "a.rs", &names, &aliases);
		assert(names.len() == 2 && names[0].name.compare_to("foo") == 0);
		assert(names[1].name.compare_to("bar") == 0);
		assert(names[1].local_name.compare_to("baz") == 0);
		clear_clauses(tmem, &names);
		clear_clauses(tmem, &aliases);

		extract_clause_names(tmem, "import f \"fmt\"", "a.go", &names, &aliases);
		assert(names.len() == 0 && aliases.len() == 1 && aliases[0].name.compare_to("f") == 0);
		clear_clauses(tmem, &names);
		clear_clauses(tmem, &aliases);

		extract_clause_names(tmem, "import numpy as np", "a.py", &names, &aliases);
		assert(names.len() == 0 && aliases.len() == 1 && aliases[0].name.compare_to("np") == 0);
		clear_clauses(tmem, &names);
		clear_clauses(tmem, &aliases);

		extract_clause_names(tmem, "import * as React from \"react\";", "a.tsx", &names, &aliases);
		assert(names.len() == 0 && aliases.len() == 1 && aliases[0].name.compare_to("React") == 0);
		clear_clauses(tmem, &names);
		clear_clauses(tmem, &aliases);

		names.free();
		aliases.free();
	};
}