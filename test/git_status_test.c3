module yun::git @test;

import std::io::file;
import std::io::path;
import std::os::process;
import std::thread;
import yun::git_test_helpers;

fn void test_status_clean()
{
	GitStatus status;
	status.init(mem);
	defer status.destroy();
	String data = "# branch.oid abc123\0# branch.head main\0# branch.upstream origin/main\0# branch.ab +1 -2\0";
	assert(status.parse("/repo", data));
	assert(status.valid);
	assert(!status.initial);
	assert(!status.detached);
	assert(status.branch.compare_to("main") == 0);
	assert(status.upstream.compare_to("origin/main") == 0);
	assert(status.ahead == 1);
	assert(status.behind == 2);
	assert(status.entries.len() == 0);
}

fn void test_status_detached_initial()
{
	GitStatus status;
	status.init(mem);
	defer status.destroy();
	String data = "# branch.oid (initial)\0# branch.head (detached)\0";
	assert(status.parse("/repo", data));
	assert(status.initial);
	assert(status.detached);
	assert(status.branch.len == 0);
}

fn void test_status_modified_staged_and_unstaged()
{
	GitStatus status;
	status.init(mem);
	defer status.destroy();
	String data = "1 .M N... 100644 100644 100644 abc abc src/main.c3\0"
		"1 M. N... 100644 100644 100644 abc abc src/other.c3\0";
	assert(status.parse("/repo", data));
	assert(status.entries.len() == 2);
	GitEntry* modified = status.find_abs("/repo/src/main.c3");
	assert(modified != null);
	assert(modified.worktree == GitFileState.MODIFIED);
	assert(modified.index == GitFileState.UNMODIFIED);
	assert(entry_has_unstaged(modified));
	assert(!entry_has_staged(modified));
	GitEntry* staged = status.find_abs("/repo/src/other.c3");
	assert(staged != null);
	assert(staged.index == GitFileState.MODIFIED);
	assert(entry_has_staged(staged));
}

fn void test_status_untracked()
{
	GitStatus status;
	status.init(mem);
	defer status.destroy();
	String data = "? notes with space.txt\0";
	assert(status.parse("/repo", data));
	assert(status.entries.len() == 1);
	GitEntry* entry = status.find_abs("/repo/notes with space.txt");
	assert(entry != null);
	assert(entry.untracked);
	assert(entry_badge(entry) == '?');
}

fn void test_status_rename()
{
	GitStatus status;
	status.init(mem);
	defer status.destroy();
	String data = "2 R. N... 100644 100644 100644 abc abc R100 new name.c3\0old name.c3\0";
	assert(status.parse("/repo", data));
	assert(status.entries.len() == 1);
	GitEntry* entry = status.find_abs("/repo/new name.c3");
	assert(entry != null);
	assert(entry.index == GitFileState.RENAMED);
	assert(entry.orig_path.compare_to("old name.c3") == 0);
	assert(entry_badge(entry) == 'R');
}

fn void test_status_conflict()
{
	GitStatus status;
	status.init(mem);
	defer status.destroy();
	String data = "u UU N... 100644 100644 100644 100644 a b c conflict.c3\0";
	assert(status.parse("/repo", data));
	assert(status.entries.len() == 1);
	GitEntry* entry = status.find_abs("/repo/conflict.c3");
	assert(entry != null);
	assert(entry.conflicted);
	assert(entry_badge(entry) == 'U');
}

fn void test_status_unknown_records_are_ignored()
{
	GitStatus status;
	status.init(mem);
	defer status.destroy();
	String data = "! ignored.c3\0x future record\0? kept.c3\0";
	assert(status.parse("/repo", data));
	assert(status.entries.len() == 1);
	assert(status.find_abs("/repo/kept.c3") != null);
}

fn void test_status_args()
{
	String[] argv = git_status_argv(mem, "git", "/repo");
	defer git_free_argv(mem, argv);
	assert(argv.len == 11);
	assert(argv[0].compare_to("git") == 0);
	assert(argv[1].compare_to("--no-pager") == 0);
	assert(argv[2].compare_to("--no-optional-locks") == 0);
	assert(argv[3].compare_to("-C") == 0);
	assert(argv[4].compare_to("/repo") == 0);
	assert(argv[5].compare_to("status") == 0);
	assert(argv[6].compare_to("--porcelain=v2") == 0);
	assert(argv[7].compare_to("-z") == 0);
}

fn void test_status_integration()
{
	String[] probe = { "git", "--version" };
	if (catch excuse = process::run(probe, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE))
	{
		return;
	}

	String dir = "/tmp/yun_git_status_test";
	(void)path::delete((PathCommon)dir);
	if (catch excuse = path::mkdir(dir, recursive: true)) return;
	defer (void)path::delete((PathCommon)dir);

	String file = string::format(tmem, "%s/file.c3", dir);
	if (catch excuse = file::save(file, "module test;\n")) return;

	String[] init = { "git", "init", "-q", dir };
	if (catch excuse = process::run(init, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE))
	{
		return;
	}
	String[] name  = { "git", "-C", dir, "config", "user.name", "Yun Test" };
	String[] email = { "git", "-C", dir, "config", "user.email", "yun@example.com" };
	(void)process::run(name, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE);
	(void)process::run(email, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE);
	String[] add = { "git", "-C", dir, "add", "-A" };
	(void)process::run(add, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE);
	String[] commit = { "git", "-C", dir, "commit", "-q", "-m", "init" };
	(void)process::run(commit, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE);
	if (catch excuse = file::save(file, "module test;\n// changed\n")) return;

	GitSettings previous = settings();
	GitSettings fast     = previous;
	fast.debounce_ms = 0;
	set_settings(fast);
	defer set_settings(previous);

	State state;
	state.init(mem);
	defer state.destroy();
	state.set_project(dir);
	assert(git_find_marker(dir));
	assert(git_test_helpers::wait_for_status(&state, dir, 5000));
	assert(state.status.branch.len > 0);
	GitEntry* entry = state.status.find_abs(file);
	assert(entry != null);
	assert(entry.worktree == GitFileState.MODIFIED);
	assert(!entry.untracked);
}

fn void test_actions_integration()
{
	String[] probe = { "git", "--version" };
	if (catch excuse = process::run(probe, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE))
	{
		return;
	}

	String dir = "/tmp/yun_git_actions_test";
	(void)path::delete((PathCommon)dir);
	if (catch excuse = path::mkdir(dir, recursive: true)) return;
	defer (void)path::delete((PathCommon)dir);

	String file = string::format(tmem, "%s/file.c3", dir);
	if (catch excuse = file::save(file, "module test;\n")) return;
	String[] init = { "git", "init", "-q", dir };
	if (catch excuse = process::run(init, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE))
	{
		return;
	}
	String[] name  = { "git", "-C", dir, "config", "user.name", "Yun Test" };
	String[] email = { "git", "-C", dir, "config", "user.email", "yun@example.com" };
	(void)process::run(name, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE);
	(void)process::run(email, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE);
	String[] add = { "git", "-C", dir, "add", "-A" };
	(void)process::run(add, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE);
	String[] commit = { "git", "-C", dir, "commit", "-q", "-m", "init" };
	(void)process::run(commit, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE);
	if (catch excuse = file::save(file, "module test;\n// changed\n")) return;

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

	String[] paths        = { "file.c3" };
	ulong revision        = state.action_revision;
	ulong status_revision = state.status_revision;
	assert(state.stage(paths));
	assert(git_test_helpers::wait_action(&state, dir, revision, 5000));
	assert(state.action.success);
	assert(git_test_helpers::wait_status_revision(&state, dir, status_revision, 5000));
	GitEntry* staged = state.status.find_abs(file);
	assert(staged != null);
	assert(staged.index == GitFileState.MODIFIED);

	revision = state.action_revision;
	status_revision = state.status_revision;
	assert(state.commit("change", false));
	assert(git_test_helpers::wait_action(&state, dir, revision, 5000));
	assert(state.action.success);
	assert(git_test_helpers::wait_status_revision(&state, dir, status_revision, 5000));
	assert(state.status.entries.len() == 0);

	if (catch excuse = file::save(file, "module test;\n// changed again\n")) return;
	state.refresh_now(git_test_helpers::now_seconds());
	assert(git_test_helpers::wait_for_status(&state, dir, 5000));
	assert(git_test_helpers::wait_idle(&state, dir, 5000));
	revision = state.diff_revision;
	assert(state.request_diff("file.c3", "", false, false));
	assert(git_test_helpers::wait_diff(&state, dir, revision, 5000));
	assert(state.diff.output.contains("+// changed again"));

	String untracked = string::format(tmem, "%s/new.c3", dir);
	if (catch excuse = file::save(untracked, "module new;\n")) return;
	state.refresh_now(git_test_helpers::now_seconds());
	assert(git_test_helpers::wait_for_status(&state, dir, 5000));
	assert(git_test_helpers::wait_idle(&state, dir, 5000));
	revision = state.diff_revision;
	assert(state.request_diff("new.c3", "", false, true));
	assert(git_test_helpers::wait_diff(&state, dir, revision, 5000));
	assert(state.diff.output.contains("+module new;"));
}