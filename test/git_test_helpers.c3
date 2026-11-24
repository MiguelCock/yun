module yun::git_test_helpers;

import std::thread;
import std::time::clock;
import yun::git;

fn double now_seconds()
{
	return (double)(clock::now().to_now().to_ms()) / 1000.0;
}

fn bool wait_for_status(State* state, String root, int timeout_ms)
{
	long start = clock::now().to_now().to_ms();
	while (clock::now().to_now().to_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (state.has_status) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}

fn bool wait_action(State* state, String root, ulong revision, int timeout_ms)
{
	long start = clock::now().to_now().to_ms();
	while (clock::now().to_now().to_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (state.action_revision > revision) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}

fn bool wait_diff(State* state, String root, ulong revision, int timeout_ms)
{
	long start = clock::now().to_now().to_ms();
	while (clock::now().to_now().to_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (state.diff_revision > revision) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}

fn bool wait_status_revision(State* state, String root, ulong revision, int timeout_ms)
{
	long start = clock::now().to_now().to_ms();
	while (clock::now().to_now().to_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (state.status_revision > revision) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}

fn bool wait_idle(State* state, String root, int timeout_ms)
{
	long start = clock::now().to_now().to_ms();
	while (clock::now().to_now().to_ms() - start < timeout_ms)
	{
		state.update(root, 0, now_seconds(), false);
		if (!state.busy_or_refreshing()) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}