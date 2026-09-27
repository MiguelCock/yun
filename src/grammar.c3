module yun::grammar;

import libc;
import raylib6::rl;
import std::core::dstring;
import std::os::env;
import std::os::win32;
import tree_sitter;

alias GrammarFn = fn TSLanguage*();

struct LoadedGrammar
{
	void* handle;
	TSLanguage* language;
}

fn String target_dir()
{
	$if env::WIN32:
		return "windows-x64";
	$else
		$if env::DARWIN:
			return "macos-aarch64";
		$else
			return "linux-x64";
		$endif
	$endif
}

fn String lib_file(Allocator allocator, String lib)
{
	$if env::WIN32:
		return string::format(allocator, "%s.dll", lib);
	$else
		$if env::DARWIN:
			return string::format(allocator, "lib%s.dylib", lib);
		$else
			return string::format(allocator, "lib%s.so", lib);
		$endif
	$endif
}

fn String stem_from_lib(Allocator allocator, String lib)
{
	String stem = lib;
	if (stem.starts_with("tree-sitter-")) stem = stem[12:stem.len - 12];
	DString out;
	out.init(allocator, stem.len);
	for (usz i = 0; i < stem.len; i++)
	{
		char c = stem[i];
		if (c == '-') c = '_';
		out.append_char(c);
	}
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn void* open_lib(ZString path)
{
	$if env::WIN32:
		return (void*)win32::loadLibraryA((win32::Win32_LPCSTR)path);
	$else
		return libc::dlopen(path, libc::RTLD_NOW | libc::RTLD_LOCAL);
	$endif
}

fn GrammarFn resolve_symbol(void* handle, ZString symbol)
{
	$if env::WIN32:
		return (GrammarFn)win32::getProcAddress(handle, (win32::Win32_LPCSTR)symbol);
	$else
		return (GrammarFn)libc::dlsym(handle, symbol);
	$endif
}

fn LoadedGrammar try_load(String path, String symbol)
{
	LoadedGrammar out = { };
	@pool()
	{
		void* handle = open_lib(path.zstr_tcopy());
		if (!handle) return out;
		GrammarFn resolved = resolve_symbol(handle, symbol.zstr_tcopy());
		if (!resolved) return out;
		out.handle = handle;
		out.language = resolved();
	};
	return out;
}

fn LoadedGrammar load(String lib, String symbol)
{
	LoadedGrammar out = { };
	@pool()
	{
		String file   = lib_file(tmem, lib);
		String target = target_dir();

		String? override = env::get_var(tmem, "YUN_GRAMMAR_DIR");
		if (catch excuse = override)
		{
		}
		else
		{
			out = try_load(string::format(tmem, "%s/%s", override, file), symbol);
			if (out.handle) return out;
		}

		String exe = rl::get_application_directory().str_view();
		out = try_load(string::format(tmem, "%sgrammars/%s", exe, file), symbol);
		if (out.handle) return out;
		out = try_load(string::format(tmem, "%s%s", exe, file), symbol);
		if (out.handle) return out;

		String stem = stem_from_lib(tmem, lib);
		out = try_load(string::format(tmem, "lib/tree_sitter_%s.c3l/linked-libs/%s/%s", stem, target, file), symbol);
	};
	return out;
}