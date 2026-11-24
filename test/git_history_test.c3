module yun::git @test;

import std::collections::list;
import std::io::file;
import std::io::path;
import std::os::process;
import yun::git_test_helpers;

fn void test_history_parsers()
{
	List{GitCommit} commits;
	commits.init(mem);
	defer
	{
		for (sz i = 0; i < commits.len(); i++) commits[i].destroy(mem);
		commits.free();
	}
	String log_data = "abc123\0abc\0Alice\02026-01-02\0Fix bug\0\n" "def456\0def\0Bob\02026-01-01\0Initial\0\n";
	assert(parse_log(mem, log_data, &commits));
	assert(commits.len() == 2);
	assert(commits[0].hash.compare_to("abc123") == 0);
	assert(commits[0].short_hash.compare_to("abc") == 0);
	assert(commits[0].author.compare_to("Alice") == 0);
	assert(commits[0].date.compare_to("2026-01-02") == 0);
	assert(commits[0].subject.compare_to("Fix bug") == 0);

	List{GitCommitFile} files;
	files.init(mem);
	defer
	{
		for (sz i = 0; i < files.len(); i++) files[i].destroy(mem);
		files.free();
	}
	String file_data = "M\0src/main.c3\0R100\0old.c3\0new.c3\0A\0new.c3\0";
	assert(parse_commit_files(mem, file_data, &files));
	assert(files.len() == 3);
	assert(files[0].state == GitFileState.MODIFIED);
	assert(files[1].state == GitFileState.RENAMED);
	assert(files[1].orig_path.compare_to("old.c3") == 0);
	assert(files[2].state == GitFileState.ADDED);
}

fn void test_history_commands()
{
	String[] log = git_log_argv(mem, "git", "/repo", "src/main.c3");
	defer git_free_argv(mem, log);
	assert(log.len == 11);
	assert(log[4].compare_to("log") == 0);
	assert(log[7].contains("%H"));
	assert(log[8].compare_to("--follow") == 0);
	assert(log[9].compare_to("--") == 0);
	assert(log[10].compare_to("src/main.c3") == 0);
	String[] files = git_commit_files_argv(mem, "git", "/repo", "abc123");
	defer git_free_argv(mem, files);
	assert(files.len == 9);
	assert(files[3].compare_to("diff-tree") == 0);
	assert(files[8].compare_to("abc123") == 0);
}

fn void test_history_integration()
{
	String[] probe = { "git", "--version" };
	if (catch excuse = process::run(probe, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE))
	{
		return;
	}
	String dir = git_test_helpers::temp_dir("yun_git_history_test");
	defer dir.free(mem);
	if (catch excuse = path::mkdir(dir, recursive: true)) return;
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
	String[] commit1 = { "git", "-C", dir, "commit", "-q", "-m", "first" };
	assert(git_test_helpers::run_git(commit1));
	assert(git_test_helpers::save_file(file, "module test;\nint value = 2;\n"));
	assert(git_test_helpers::run_git(add));
	String[] commit2 = { "git", "-C", dir, "commit", "-q", "-m", "second" };
	assert(git_test_helpers::run_git(commit2));

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
	ulong revision = state.commits_revision;
	state.request_history("");
	assert(git_test_helpers::wait_history(&state, dir, revision, 5000));
	assert(state.commits.len() >= 2);
	assert(state.commits[0].subject.contains("second"));
	String hash = state.commits[0].hash.copy(tmem);

	revision = state.commit_files_revision;
	state.request_commit_files(hash);
	assert(git_test_helpers::wait_commit_files(&state, dir, revision, 5000));
	assert(state.commit_files.len() == 1);
	assert(state.commit_files[0].path.compare_to("file.c3") == 0);

	assert(git_test_helpers::wait_idle(&state, dir, 5000));
	revision = state.diff_revision;
	assert(state.request_commit_diff(hash, "file.c3", ""));
	assert(git_test_helpers::wait_diff(&state, dir, revision, 5000));
	assert(state.diff.output.contains("int value = 2;"));
	assert(state.diff.rev.compare_to(hash) == 0);
}