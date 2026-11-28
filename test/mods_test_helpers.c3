module yun::mods_test_helpers;

import std::io::file;
import std::io::path;
import yun::mods;
import yun::notify;
import yun::project;

int g_temp_counter;

fn String temp_root(Allocator allocator)
{
	g_temp_counter++;
	return string::format(allocator, "/tmp/opencode/yun-mods-test-%d", g_temp_counter);
}

fn bool prepare_root(Allocator allocator, String root)
{
	(void)path::rmtree((Path)root);
	if (catch err = path::mkdir((Path)root, recursive: true)) return false;
	return true;
}

fn bool write_file(String root, String relative, String text)
{
	bool ok = true;
	@pool()
	{
		Path? dir = ((Path)root).append(tmem, ".yun");
		if (catch dir_excuse = dir)
		{
			ok = false;
		}
		else
		{
			Path? mods_dir = dir.append(tmem, "mods");
			if (catch mods_excuse = mods_dir)
			{
				ok = false;
			}
			else if (catch mkdir_excuse = path::mkdir(mods_dir, recursive: true))
			{
				ok = false;
			}
			else
			{
				Path? file_path = mods_dir.append(tmem, relative);
				if (catch file_excuse = file_path)
				{
					ok = false;
				}
				else if (catch save_excuse = file::save(file_path, text))
				{
					ok = false;
				}
			}
		}
	};
	return ok;
}

fn void cleanup_root(String root)
{
	(void)path::rmtree((Path)root);
}

fn void init_project(project::Project* project, String root)
{
	project.init(mem);
	if (((String)project.root).len) ((String)project.root).free(project.allocator);
	project.root = (Path)root.copy(project.allocator);
}

fn void init_mods(mods::Mods* mods, project::Project* project, notify::Notifier* notifier, bool* project_open)
{
	mods.init(
		mem,
		{
			.project = project,
			.notifier = notifier,
			.config = null,
			.project_open = project_open,
		}
	);
}

fn int notifier_count(notify::Notifier* notifier)
{
	return (int)notifier.items.len();
}

fn bool notifier_has(notify::Notifier* notifier, String text)
{
	for (sz i = 0; i < notifier.items.len(); i++)
	{
		if (notifier.items[i].text.compare_to(text) == 0) return true;
	}
	return false;
}

fn int notifier_count_text(notify::Notifier* notifier, String text)
{
	int count = 0;
	for (sz i = 0; i < notifier.items.len(); i++)
	{
		if (notifier.items[i].text.compare_to(text) == 0) count++;
	}
	return count;
}