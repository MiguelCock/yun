module yun::git_test_helpers;

import std::io::file;
import std::os::process;
import std::thread;
import std::time::clock;
import yun::git;

fn long now_ms()
{
	return (long)(clock::now() / 1_000_000);
}

fn double now_seconds()
{
	return (double)now_ms() / 1000.0;
}

fn bool wait_for_status(State* state, String root, int timeout_ms)
{
	long start = now_ms();
	while (now_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (state.has_status) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}

fn bool wait_action(State* state, String root, ulong revision, int timeout_ms)
{
	long start = now_ms();
	while (now_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (state.action_revision > revision) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}

fn bool wait_diff(State* state, String root, ulong revision, int timeout_ms)
{
	long start = now_ms();
	while (now_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (state.diff_revision > revision) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}

fn bool wait_status_revision(State* state, String root, ulong revision, int timeout_ms)
{
	long start = now_ms();
	while (now_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (state.status_revision > revision) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}

fn bool wait_idle(State* state, String root, int timeout_ms)
{
	long start = now_ms();
	while (now_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (!state.busy_or_refreshing()) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}
fn bool wait_branch(State* state, String root, String name, int timeout_ms)
{
	long start = now_ms();
	while (now_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (state.branches_loaded && state.has_status && state.status.branch.compare_to(name) == 0)
		{
			return true;
		}
		(void)thread::sleep_ms(10);
	}
	return false;
}

int g_temp_counter = 0;

fn String temp_dir(String name)
{
	g_temp_counter++;
	return string::format(mem, "/tmp/%s_%d_%d", name, g_temp_counter, now_ms());
}
fn bool save_file(String path, String content)
{
	if (catch excuse = std::io::file::save(path, content)) return false;
	return true;
}
fn bool run_git(String[] argv)
{
	int? code = std::os::process::run(
		argv,
		{ },
		{ },
		std::os::process::CAPTURE,
		std::os::process::CAPTURE,
		std::os::process::CAPTURE
	);
	int value = -1;
	if (try result = code) value = result;
	return value == 0;
}
fn String capture_git(String[] argv)
{
	char[65536] buffer;
	String? output = std::os::process::run_capture_stdout(&buffer, argv, std::os::process::SpawnOptions.INHERIT_ENV);
	if (catch excuse = output) return "".copy(mem);
	return ((String)output).copy(mem);
}
fn bool wait_history(State* state, String root, ulong revision, int timeout_ms)
{
	long start = now_ms();
	while (now_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (state.commits_revision > revision) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}

fn bool wait_commit_files(State* state, String root, ulong revision, int timeout_ms)
{
	long start = now_ms();
	while (now_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (state.commit_files_revision > revision) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}