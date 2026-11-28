module yun::project;

import raylib6::rl;
import std::core::mem::alloc;
import std::io::path;

fn bool path_is_inside(String root, String abs)
{
	if (root.len == 0 || abs.len < root.len) return false;
	if (abs[0:root.len].compare_to(root) != 0) return false;
	if (abs.len == root.len) return true;
	char next = abs[root.len];
	return next == '/' || next == '\\';
}

fn bool basename_is_ignored(String path)
{
	usz start = 0;
	for (usz i = 0; i < path.len; i++)
	{
		if (path[i] == '/' || path[i] == '\\') start = i + 1;
	}
	String component = path[start:path.len - start];
	foreach (String ignored : IGNORED_NAMES)
	{
		if (component.compare_to(ignored) == 0) return true;
	}
	return false;
}

fn int path_compare(void* a, void* b)
{
	Path pa = *(Path*)a;
	Path pb = *(Path*)b;
	return ((String)pa).compare_to((String)pb);
}

fn String collision_name(Allocator allocator, String stem, String ext, int index)
{
	if (index <= 0) return string::format(allocator, "%s%s", stem, ext);
	return string::format(allocator, "%s (%d)%s", stem, index, ext);
}

fn String file_stem(String path_str)
{
	return rl::get_file_name_without_ext((ZString)path_str.ptr).str_view();
}

fn String file_ext(String path_str)
{
	return rl::get_file_extension((ZString)path_str.ptr).str_view();
}

fn String? resolve_path(Allocator allocator, String arg)
{
	if (arg.len == 0) return RESOLVE_FAILED~;
	if (arg[0] == '~')
	{
		Path? home = path::home_directory(allocator);
		if (catch err = home) return RESOLVE_FAILED~;
		if (arg.len == 1) return (String)home;
		return ((Path)home).append(allocator, arg[2..]);
	}
	if (arg[0] == '/' || (arg.len > 1 && arg[1] == ':')) return arg.copy(allocator);
	Path? cwd = path::cwd(allocator);
	if (catch err = cwd) return RESOLVE_FAILED~;
	return cwd.append(allocator, arg);
}

fn bool is_valid_name(String name)
{
	if (name.len == 0 || name.len > 255) return false;
	if (name.compare_to(".") == 0 || name.compare_to("..") == 0) return false;
	for (usz i = 0; i < name.len; i++)
	{
		char c = name[i];
		if ((int)c < 32) return false;
		if (c == '/' || c == '\\' || c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|')
		{
			return false;
		}
	}
	return rl::is_file_name_valid((ZString)name.ptr);
}

fn bool is_nested_repo(String dir)
{
	@pool()
	{
		Path? git = ((Path)dir).append(tmem, ".git");
		if (catch err = git) return false;
		return path::exists(git);
	};
}