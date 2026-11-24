module yun::git;

import std::collections::list;
import std::core::mem::alloc;
import std::io::path;

fn bool git_marker_exists(String dir)
{
	Path? marker = ((Path)dir).append(tmem, ".git");
	if (catch excuse = marker) return false;
	return path::exists(marker);
}

fn bool git_find_marker(String start)
{
	if (start.len == 0) return false;
	Path dir = (Path)start;
	while (dir.len > 0)
	{
		if (git_marker_exists(dir)) return true;
		Path? parent = dir.parent();
		if (catch excuse = parent) break;
		if (parent.len >= dir.len) break;
		dir = parent;
	}
	return false;
}

fn String[] finish_argv(Allocator allocator, List{String}* list)
{
	String[] argv = alloc::new_array(allocator, String, (sz)list.len());
	for (sz i = 0; i < list.len(); i++)
	{
		argv[i] = list.entries[i].copy(allocator);
	}
	return argv;
}

fn String[] git_detect_argv(Allocator allocator, String binary, String root)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-C");
		list.push(root);
		list.push("rev-parse");
		list.push("--show-toplevel");
		return finish_argv(allocator, &list);
	};
}

fn String[] git_status_argv(Allocator allocator, String binary, String root)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("--no-pager");
		list.push("--no-optional-locks");
		list.push("-C");
		list.push(root);
		list.push("status");
		list.push("--porcelain=v2");
		list.push("-z");
		list.push("--branch");
		list.push("--untracked-files=all");
		list.push("--renames");
		return finish_argv(allocator, &list);
	};
}

fn String[] git_diff_argv(
	Allocator allocator,
	String binary,
	String root,
	String path,
	String orig_path,
	bool staged,
	bool untracked
)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("--no-pager");
		list.push("-C");
		list.push(root);
		list.push("diff");
		list.push("--no-color");
		list.push("--no-ext-diff");
		list.push("--no-textconv");
		list.push("--unified=3");
		if (untracked)
		{
			list.push("--no-index");
			list.push("--");
			list.push("/dev/null");
			String abs_path = path_join_alloc(tmem, root, path);
			list.push(abs_path);
		}
		else
		{
			list.push("-M");
			if (staged) list.push("--cached");
			list.push("--");
			list.push(path);
			if (orig_path.len > 0 && orig_path.compare_to(path) != 0) list.push(orig_path);
		}
		return finish_argv(allocator, &list);
	};
}

fn String[] git_stage_argv(Allocator allocator, String binary, String root, String[] paths)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-C");
		list.push(root);
		list.push("add");
		list.push("-A");
		list.push("--");
		foreach (String path : paths) list.push(path);
		return finish_argv(allocator, &list);
	};
}

fn String[] git_unstage_argv(Allocator allocator, String binary, String root, String[] paths, bool initial)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-C");
		list.push(root);
		if (initial)
		{
			list.push("rm");
			list.push("--cached");
		}
		else
		{
			list.push("restore");
			list.push("--staged");
		}
		list.push("--");
		foreach (String path : paths) list.push(path);
		return finish_argv(allocator, &list);
	};
}

fn String[] git_discard_argv(Allocator allocator, String binary, String root, String[] paths)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-C");
		list.push(root);
		list.push("restore");
		list.push("--worktree");
		list.push("--");
		foreach (String path : paths) list.push(path);
		return finish_argv(allocator, &list);
	};
}

fn String[] git_commit_argv(Allocator allocator, String binary, String root, String message, bool amend)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-C");
		list.push(root);
		list.push("commit");
		if (amend) list.push("--amend");
		list.push("-m");
		list.push(message);
		return finish_argv(allocator, &list);
	};
}
fn String[] git_fetch_argv(Allocator allocator, String binary, String root, String remote)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-c");
		list.push("credential.interactive=false");
		list.push("--no-pager");
		list.push("-C");
		list.push(root);
		list.push("fetch");
		list.push(remote);
		return finish_argv(allocator, &list);
	};
}

fn String[] git_pull_argv(Allocator allocator, String binary, String root)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-c");
		list.push("credential.interactive=false");
		list.push("--no-pager");
		list.push("-C");
		list.push(root);
		list.push("pull");
		list.push("--ff-only");
		return finish_argv(allocator, &list);
	};
}

fn String[] git_push_argv(Allocator allocator, String binary, String root, String remote, String branch, bool publish)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-c");
		list.push("credential.interactive=false");
		list.push("--no-pager");
		list.push("-C");
		list.push(root);
		list.push("push");
		if (publish) list.push("-u");
		list.push(remote);
		list.push(branch);
		return finish_argv(allocator, &list);
	};
}
fn String[] git_merge_abort_argv(Allocator allocator, String binary, String root)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-C");
		list.push(root);
		list.push("merge");
		list.push("--abort");
		return finish_argv(allocator, &list);
	};
}
fn String[] git_apply_patch_argv(Allocator allocator, String binary, String root, String patch_file, bool reverse)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-C");
		list.push(root);
		list.push("apply");
		list.push("--cached");
		list.push("--whitespace=nowarn");
		if (reverse) list.push("--reverse");
		list.push(patch_file);
		return finish_argv(allocator, &list);
	};
}