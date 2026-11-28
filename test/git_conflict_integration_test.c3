module yun::git @test;

import std::io::file;
import std::io::path;
import std::os::process;
import yun::git_test_helpers;

fn void test_conflict_resolution_integration()
{
	String[] probe = { "git", "--version" };
	if (catch err = process::run(probe, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE))
	{
		return;
	}
	String dir = git_test_helpers::temp_dir("yun_git_conflict_test");
	defer dir.free(mem);
	if (catch err = path::mkdir(dir, recursive: true)) return;
	String file = string::format(tmem, "%s/file.c3", dir);
	assert(git_test_helpers::save_file(file, "module test;\nint value = 1;\n"));
	String[] init = { "git", "init", "-q", dir };
	assert(git_test_helpers::run_git(init));
	String[] name  = { "git", "-C", dir, "config", "user.name", "Yun Test" };
	String[] email = { "git", "-C", dir, "config", "user.email", "yun@example.com" };
	assert(git_test_helpers::run_git(name));
	assert(git_test_helpers::run_git(email));
	String[] add = { "git", "-C", dir, "add", "-A" };
	assert(git_test_helpers::run_git(add));
	String[] commit = { "git", "-C", dir, "commit", "-q", "-m", "base" };
	assert(git_test_helpers::run_git(commit));
	String[] branch = { "git", "-C", dir, "switch", "-c", "other" };
	assert(git_test_helpers::run_git(branch));
	assert(git_test_helpers::save_file(file, "module test;\nint value = 2;\n"));
	assert(git_test_helpers::run_git(add));
	String[] commit_other = { "git", "-C", dir, "commit", "-q", "-m", "other" };
	assert(git_test_helpers::run_git(commit_other));
	String[] master = { "git", "-C", dir, "switch", "master" };
	if (!git_test_helpers::run_git(master))
	{
		String[] main = { "git", "-C", dir, "switch", "main" };
		assert(git_test_helpers::run_git(main));
	}
	assert(git_test_helpers::save_file(file, "module test;\nint value = 3;\n"));
	assert(git_test_helpers::run_git(add));
	String[] commit_main = { "git", "-C", dir, "commit", "-q", "-m", "main" };
	assert(git_test_helpers::run_git(commit_main));
	String[] merge = { "git", "-C", dir, "merge", "other" };
	(void)process::run(merge, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE);

	GitSettings previous = settings();
	GitSettings fast     = previous;
	fast.debounce_ms = 0;
	set_settings(fast);
	defer set_settings(previous);

	State state;
	state.init(mem);
	defer state.destroy();
	state.set_project(dir);
	assert(git_test_helpers::wait_for_status(&state, dir, 5000));
	GitEntry* entry = state.status.find_abs(file);
	assert(entry != null);
	assert(entry.conflicted);

	ConflictView view;
	view.init(mem);
	defer view.destroy();
	view.open_file(entry.path, entry.abs_path);
	assert(view.blocks.len() == 1);
	view.choices.set(0, ConflictChoice.CURRENT);
	ulong revision        = state.action_revision;
	ulong status_revision = state.status_revision;
	view.save(&state);
	assert(git_test_helpers::wait_action(&state, dir, revision, 5000));
	assert(state.action.success);
	view.sync_action(&state);
	assert(git_test_helpers::wait_status_revision(&state, dir, status_revision, 5000));
	for (sz i = 0; i < state.status.entries.len(); i++)
	{
		assert(!state.status.entries[i].conflicted);
	}

	assert(git_test_helpers::wait_idle(&state, dir, 5000));
	revision = state.action_revision;
	assert(state.abort_merge());
	assert(git_test_helpers::wait_action(&state, dir, revision, 5000));
	assert(state.action.success);
	assert(git_test_helpers::wait_idle(&state, dir, 5000));
	assert(git_test_helpers::wait_for_status(&state, dir, 5000));
	GitEntry* aborted = state.status.find_abs(file);
	assert(aborted == null || !aborted.conflicted);
}