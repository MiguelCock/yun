module yun::language;

import std::atomic::types;
import tree_sitter;
import yun::grammar;

enum Language : int
{
	NONE,
	C3,
	C,
	PYTHON,
	JAVASCRIPT,
	GO,
	RUST,
	ZIG,
	ODIN,
	V,
	NIM,
	CPP,
	JAVA,
	KOTLIN,
	SCALA,
	C_SHARP,
	COUNT,
}

const int LANGUAGE_COUNT = (int)Language.COUNT;

struct LanguageSpec
{
	String name;
	String[] extensions;
	String lib;
	String symbol;
	String highlights_path;
	String import_query;
	String module_query;
	String symbols_query;
}

const LanguageSpec[] LANGUAGES = {
	{ },
	{
		.name = "c3",
		.extensions = { ".c3", ".c3i" },
		.lib = "tree-sitter-c3",
		.symbol = "tree_sitter_c3",
		.highlights_path = "lib/tree_sitter_c3.c3l/queries/highlights.scm",
		.import_query = "(import_declaration (import_path (path_ident) @path))",
		.module_query = "(module_declaration) @module",
		.symbols_query = "(func_definition (func_header name: (ident) @function))\n"
			"(func_declaration (func_header name: (ident) @function))\n"
			"(macro_declaration (macro_header name: (_) @function))\n"
			"(struct_declaration name: (type_ident) @type)\n"
			"(interface_declaration name: (type_ident) @type)\n"
			"(bitstruct_declaration name: (type_ident) @type)\n"
			"(typedef_declaration name: (type_ident) @type)\n"
			"(enum_declaration name: (type_ident) @enum)\n"
			"(constdef_declaration name: (type_ident) @const)",
	},
	{
		.name = "c",
		.extensions = { ".c", ".h" },
		.lib = "tree-sitter-c",
		.symbol = "tree_sitter_c",
		.highlights_path = "lib/tree_sitter_c.c3l/queries/highlights.scm",
		.import_query = "(preproc_include path: (_) @path)",
		.module_query = "",
		.symbols_query = "(function_definition declarator: (function_declarator declarator: (identifier) @function))\n"
			"(struct_specifier name: (type_identifier) @type)\n"
			"(enum_specifier name: (type_identifier) @enum)\n"
			"(type_definition declarator: (type_identifier) @type)\n"
			"(declaration declarator: (init_declarator declarator: (identifier) @variable))\n"
			"(declaration declarator: (identifier) @variable)",
	},
	{
		.name = "python",
		.extensions = { ".py" },
		.lib = "tree-sitter-python",
		.symbol = "tree_sitter_python",
		.highlights_path = "lib/tree_sitter_python.c3l/queries/highlights.scm",
		.import_query = "(import_statement name: (dotted_name) @path)\n"
			"(import_statement name: (aliased_import (dotted_name) @path))\n"
			"(import_from_statement module_name: (dotted_name) @path)\n"
			"(import_from_statement module_name: (relative_import) @path)",
		.module_query = "",
		.symbols_query = "(function_definition name: (identifier) @function)\n"
			"(class_definition name: (identifier) @class)",
	},
	{
		.name = "javascript",
		.extensions = { ".js", ".mjs", ".cjs" },
		.lib = "tree-sitter-javascript",
		.symbol = "tree_sitter_javascript",
		.highlights_path = "lib/tree_sitter_javascript.c3l/queries/highlights.scm",
		.import_query = "(import_statement source: (string) @path)\n"
			"(call_expression function: (identifier) @fn arguments: (arguments (string) @path))",
		.module_query = "",
		.symbols_query = "(function_declaration name: (identifier) @function)\n"
			"(class_declaration name: (identifier) @class)\n"
			"(method_definition name: (property_identifier) @method)\n"
			"(variable_declarator name: (identifier) @variable)",
	},
	{
		.name = "go",
		.extensions = { ".go" },
		.lib = "tree-sitter-go",
		.symbol = "tree_sitter_go",
		.highlights_path = "lib/tree_sitter_go.c3l/queries/highlights.scm",
		.import_query = "",
		.module_query = "",
		.symbols_query = "",
	},
	{
		.name = "rust",
		.extensions = { ".rs" },
		.lib = "tree-sitter-rust",
		.symbol = "tree_sitter_rust",
		.highlights_path = "lib/tree_sitter_rust.c3l/queries/highlights.scm",
		.import_query = "",
		.module_query = "",
		.symbols_query = "",
	},
	{
		.name = "zig",
		.extensions = { ".zig", ".zon" },
		.lib = "tree-sitter-zig",
		.symbol = "tree_sitter_zig",
		.highlights_path = "lib/tree_sitter_zig.c3l/queries/highlights.scm",
		.import_query = "",
		.module_query = "",
		.symbols_query = "",
	},
	{
		.name = "odin",
		.extensions = { ".odin" },
		.lib = "tree-sitter-odin",
		.symbol = "tree_sitter_odin",
		.highlights_path = "lib/tree_sitter_odin.c3l/queries/highlights.scm",
		.import_query = "",
		.module_query = "",
		.symbols_query = "",
	},
	{
		.name = "v",
		.extensions = { ".v" },
		.lib = "tree-sitter-v",
		.symbol = "tree_sitter_v",
		.highlights_path = "lib/tree_sitter_v.c3l/queries/highlights.scm",
		.import_query = "",
		.module_query = "",
		.symbols_query = "",
	},
	{
		.name = "nim",
		.extensions = { ".nim", ".nims" },
		.lib = "tree-sitter-nim",
		.symbol = "tree_sitter_nim",
		.highlights_path = "lib/tree_sitter_nim.c3l/queries/highlights.scm",
		.import_query = "",
		.module_query = "",
		.symbols_query = "",
	},
	{
		.name = "cpp",
		.extensions = { ".cpp", ".cc", ".cxx", ".hpp", ".hxx" },
		.lib = "tree-sitter-cpp",
		.symbol = "tree_sitter_cpp",
		.highlights_path = "lib/tree_sitter_cpp.c3l/queries/highlights.scm",
		.import_query = "",
		.module_query = "",
		.symbols_query = "",
	},
	{
		.name = "java",
		.extensions = { ".java" },
		.lib = "tree-sitter-java",
		.symbol = "tree_sitter_java",
		.highlights_path = "lib/tree_sitter_java.c3l/queries/highlights.scm",
		.import_query = "",
		.module_query = "",
		.symbols_query = "",
	},
	{
		.name = "kotlin",
		.extensions = { ".kt", ".kts" },
		.lib = "tree-sitter-kotlin",
		.symbol = "tree_sitter_kotlin",
		.highlights_path = "lib/tree_sitter_kotlin.c3l/queries/highlights.scm",
		.import_query = "",
		.module_query = "",
		.symbols_query = "",
	},
	{
		.name = "scala",
		.extensions = { ".scala", ".sc", ".sbt" },
		.lib = "tree-sitter-scala",
		.symbol = "tree_sitter_scala",
		.highlights_path = "lib/tree_sitter_scala.c3l/queries/highlights.scm",
		.import_query = "",
		.module_query = "",
		.symbols_query = "",
	},
	{
		.name = "c-sharp",
		.extensions = { ".cs" },
		.lib = "tree-sitter-c-sharp",
		.symbol = "tree_sitter_c_sharp",
		.highlights_path = "lib/tree_sitter_c_sharp.c3l/queries/highlights.scm",
		.import_query = "",
		.module_query = "",
		.symbols_query = "",
	},
};

fn String path_extension(String path)
{
	sz dot = -1;
	for (sz i = (sz)path.len; i > 0; i--)
	{
		char c = path[(usz)(i - 1)];
		if (c == '.')
		{
			dot = i - 1;
			break;
		}
		if (c == '/' || c == '\\') break;
	}
	if (dot < 0) return "";
	return path[(usz)dot:path.len - (usz)dot];
}

fn Language language_for_path(String path)
{
	String ext = path_extension(path);
	if (ext.len == 0) return Language.NONE;
	for (int i = 1; i < LANGUAGE_COUNT; i++)
	{
		foreach (String candidate : LANGUAGES[i].extensions)
		{
			if (ext.compare_to(candidate) == 0) return (Language)i;
		}
	}
	return Language.NONE;
}

TSLanguage*[LANGUAGE_COUNT] grammar_cache;
void*[LANGUAGE_COUNT] grammar_handles;
Atomic{bool}[LANGUAGE_COUNT] grammar_loaded;

fn TSLanguage* grammar_language(Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= LANGUAGE_COUNT) return null;
	if (grammar_loaded[index].load()) return grammar_cache[index];
	grammar::LoadedGrammar loaded = grammar::load(LANGUAGES[index].lib, LANGUAGES[index].symbol);
	grammar_handles[index] = loaded.handle;
	grammar_cache[index] = loaded.language;
	grammar_loaded[index].store(true);
	return grammar_cache[index];
}

fn String grammar_query_path(Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= LANGUAGE_COUNT) return "";
	return LANGUAGES[index].highlights_path;
}

fn String highlights_path_for_name(String name)
{
	foreach (LanguageSpec spec : LANGUAGES)
	{
		if (spec.name.compare_to(name) == 0) return spec.highlights_path;
	}
	return "";
}

fn String import_query_text(Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= LANGUAGE_COUNT) return "";
	return LANGUAGES[index].import_query;
}

fn String module_query_text(Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= LANGUAGE_COUNT) return "";
	return LANGUAGES[index].module_query;
}

fn String symbols_query_text(Language language)
{
	int index = (int)language;
	if (index <= 0 || index >= LANGUAGE_COUNT) return "";
	return LANGUAGES[index].symbols_query;
}

struct LspSpec
{
	String id;
	String[] extensions;
	String command;
}

const LspSpec[] LSP_LANGUAGES = {
	{
		.id = "c3",
		.extensions = { ".c3", ".c3i" },
		.command = "c3lsp",
	},
	{
		.id = "c",
		.extensions = { ".c", ".h" },
		.command = "clangd",
	},
	{
		.id = "cpp",
		.extensions = { ".cpp", ".cc", ".cxx", ".hpp", ".hh", ".hxx" },
		.command = "clangd",
	},
	{
		.id = "python",
		.extensions = { ".py" },
		.command = "pyright-langserver --stdio",
	},
	{
		.id = "javascript",
		.extensions = { ".js", ".mjs", ".cjs", ".jsx" },
		.command = "typescript-language-server --stdio",
	},
	{
		.id = "typescript",
		.extensions = { ".ts", ".tsx" },
		.command = "typescript-language-server --stdio",
	},
	{
		.id = "go",
		.extensions = { ".go" },
		.command = "gopls",
	},
	{
		.id = "rust",
		.extensions = { ".rs" },
		.command = "rust-analyzer",
	},
	{
		.id = "zig",
		.extensions = { ".zig", ".zon" },
		.command = "zls",
	},
	{
		.id = "odin",
		.extensions = { ".odin" },
		.command = "ols",
	},
	{
		.id = "v",
		.extensions = { ".v" },
		.command = "v-analyzer",
	},
	{
		.id = "nim",
		.extensions = { ".nim", ".nims" },
		.command = "nimlangserver",
	},
	{
		.id = "java",
		.extensions = { ".java" },
		.command = "jdtls",
	},
	{
		.id = "kotlin",
		.extensions = { ".kt", ".kts" },
		.command = "kotlin-language-server",
	},
	{
		.id = "scala",
		.extensions = { ".scala", ".sc", ".sbt" },
		.command = "metals",
	},
	{
		.id = "csharp",
		.extensions = { ".cs" },
		.command = "csharp-ls",
	},
};

fn String lsp_for_path(String path)
{
	String ext = path_extension(path);
	if (ext.len == 0) return "";
	foreach (LspSpec spec : LSP_LANGUAGES)
	{
		foreach (String candidate : spec.extensions)
		{
			if (ext.compare_to(candidate) == 0) return spec.id;
		}
	}
	return "";
}

fn String lsp_command(String id)
{
	foreach (LspSpec spec : LSP_LANGUAGES)
	{
		if (spec.id.compare_to(id) == 0) return spec.command;
	}
	return "";
}