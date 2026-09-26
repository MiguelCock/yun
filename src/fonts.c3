module yun::fonts;

import raylib6::rl;
import std::collections::list;
import std::io::path;
import std::os::env;

const int MAX_FONTS = 200;

struct FontEntry
{
	String label;
	String path;
}

struct Fonts
{
	Allocator allocator;
	List{FontEntry} entries;
	List{String} names;
}

fn char lower_ascii(char c)
{
	if (c >= 'A' && c <= 'Z') return (char)(c + 32);
	return c;
}

fn bool contains_ci(String haystack, String needle)
{
	if (needle.len == 0 || needle.len > haystack.len) return false;
	for (usz i = 0; i + needle.len <= haystack.len; i++)
	{
		bool match = true;
		for (usz j = 0; j < needle.len; j++)
		{
			if (lower_ascii(haystack[i + j]) != lower_ascii(needle[j]))
			{
				match = false;
				break;
			}
		}
		if (match) return true;
	}
	return false;
}

fn bool is_monospace_name(String name)
{
	return contains_ci(
		name,
		"mono"
	) || contains_ci(
		name,
		"code"
	) || contains_ci(
		name,
		"consol"
	) || contains_ci(
		name,
		"menlo"
	) || contains_ci(
		name,
		"courier"
	) || contains_ci(name, "hack") || contains_ci(name, "inconsolata") || contains_ci(name, "fira");
}

fn String file_label(Allocator allocator, ZString path)
{
	@pool()
	{
		String base = path.str_view();
		usz end     = base.len;
		for (usz i = 0; i < base.len; i++)
		{
			if (base[i] == '.')
			{
				end = i;
				break;
			}
		}
		return base[0:end].copy(allocator);
	};
}

fn void Fonts.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.entries.init(allocator);
	self.names.init(allocator);
	String bundled = "JetBrains Mono";
	self.entries.push({ .label = bundled.copy(allocator), .path = "" });
	self.names.push(self.entries.get(0).label);
	self.scan_user();
	self.scan_os();
}

fn void Fonts.destroy(&self)
{
	for (sz i = 0; i < self.entries.len(); i++)
	{
		self.entries[i].label.free(self.allocator);
		self.entries[i].path.free(self.allocator);
	}
	self.entries.free();
	self.names.free();
}

fn bool Fonts.has_label(&self, String label)
{
	for (sz i = 0; i < self.entries.len(); i++)
	{
		if (self.entries[i].label.compare_to(label) == 0) return true;
	}
	return false;
}

fn void Fonts.add_path(&self, ZString path)
{
	if (self.entries.len() >= (sz)MAX_FONTS) return;
	String name = path.str_view();
	if (!is_monospace_name(name)) return;
	String label = file_label(self.allocator, path);
	if (self.has_label(label))
	{
		label.free(self.allocator);
		return;
	}
	self.entries.push({ .label = label, .path = name.copy(self.allocator) });
	self.names.push(label);
}

fn void Fonts.scan_dir(&self, String dir)
{
	@pool()
	{
		if (!path::is_dir((Path)dir)) return;
		RLFilePathList files = rl::load_directory_files_ex(dir.zstr_tcopy(), "*.ttf;*.otf", true);
		for (uint i = 0; i < files.count; i++)
		{
			self.add_path(files.paths[i]);
		}
		rl::unload_directory_files(files);
	};
}

fn void Fonts.scan_user(&self)
{
	@pool()
	{
		String? home = env::get_home_dir(tmem);
		if (catch excuse = home) return;
		self.scan_dir(string::format(tmem, "%s/.config/yun/fonts", home));
	};
}

fn void Fonts.scan_os(&self)
{
	$if env::WIN32:
		self.scan_dir("C:\\Windows\\Fonts");
	$endif
	$if env::DARWIN:
		self.scan_dir("/System/Library/Fonts");
		self.scan_dir("/Library/Fonts");
	$endif
	$if !env::WIN32 && !env::DARWIN:
		self.scan_dir("/usr/share/fonts");
		self.scan_dir("/usr/local/share/fonts");
		self.scan_dir("/usr/share/X11/fonts");
	$endif
}

fn String[] Fonts.labels(&self)
{
	return self.names.array_view();
}

fn String Fonts.path_for(&self, String label)
{
	for (sz i = 0; i < self.entries.len(); i++)
	{
		if (self.entries[i].label.compare_to(label) == 0) return self.entries[i].path;
	}
	return "";
}