module yun::git @test;

import std::io::file;
import std::io::path;
import std::os::process;
import yun::git_test_helpers;

fn void test_remote_commands()
{
	String[] fetch = git_fetch_argv(mem, "git", "/repo", "origin");
	defer git_free_argv(mem, fetch);
	assert(fetch.len == 8);
	assert(fetch[1].compare_to("-c") == 0);
	assert(fetch[2].compare_to("credential.interactive=false") == 0);
	assert(fetch[6].compare_to("fetch") == 0);
	assert(fetch[7].compare_to("origin") == 0);

	String[] pull = git_pull_argv(mem, "git", "/repo");
	defer git_free_argv(mem, pull);
	assert(pull.len == 8);
	assert(pull[6].compare_to("pull") == 0);
	assert(pull[7].compare_to("--ff-only") == 0);

	String[] push = git_push_argv(mem, "git", "/repo", "origin", "main", false);
	defer git_free_argv(mem, push);
	assert(push.len == 9);
	assert(push[6].compare_to("push") == 0);
	assert(push[7].compare_to("origin") == 0);
	assert(push[8].compare_to("main") == 0);
	for (sz i = 0; i < push.len; i++) assert(!push[i].contains("--force"));

	String[] publish = git_push_argv(mem, "git", "/repo", "origin", "topic", true);
	defer git_free_argv(mem, publish);
	assert(publish.len == 10);
	assert(publish[7].compare_to("-u") == 0);
}


fn void test_remote_integration()
{
	String[] probe = { "git", "--version" };
	if (catch err = process::run(probe, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE))
	{
		return;
	}
	String base = git_test_helpers::temp_dir("yun_git_remote_test");
	defer base.free(mem);
	String bare   = string::format(tmem, "%s/remote.git", base);
	String work   = string::format(tmem, "%s/work", base);
	String second = string::format(tmem, "%s/second", base);
	(void)path::mkdir(base, recursive: true);

	String[] init_bare = { "git", "init", "-q", "--bare", bare };
	assert(git_test_helpers::run_git(init_bare));
	String[] init_work = { "git", "init", "-q", work };
	assert(git_test_helpers::run_git(init_work));
	String[] name  = { "git", "-C", work, "config", "user.name", "Yun Test" };
	String[] email = { "git", "-C", work, "config", "user.email", "yun@example.com" };
	assert(git_test_helpers::run_git(name));
	assert(git_test_helpers::run_git(email));
	String file = string::format(tmem, "%s/file.c3", work);
	assert(git_test_helpers::save_file(file, "module test;\n"));
	String[] add = { "git", "-C", work, "add", "-A" };
	assert(git_test_helpers::run_git(add));
	String[] commit = { "git", "-C", work, "commit", "-q", "-m", "init" };
	assert(git_test_helpers::run_git(commit));
	String[] remote = { "git", "-C", work, "remote", "add", "origin", bare };
	assert(git_test_helpers::run_git(remote));
	String[] push_upstream = { "git", "-C", work, "push", "-q", "-u", "origin", "HEAD" };
	assert(git_test_helpers::run_git(push_upstream));

	GitSettings previous = settings();
	GitSettings fast     = previous;
	fast.debounce_ms = 0;
	set_settings(fast);
	defer set_settings(previous);

	State state;
	state.init(mem);
	defer state.destroy();
	state.set_project(work);
	assert(git_test_helpers::wait_for_status(&state, work, 5000));
	assert(state.branches_loaded);
	assert(state.status.upstream.len > 0);

	ulong revision = state.action_revision;
	assert(state.fetch());
	assert(git_test_helpers::wait_action(&state, work, revision, 10000));
	assert(state.action.success);

	// A second clone creates a commit that the first worktree can pull.
	String[] clone = { "git", "clone", "-q", bare, second };
	assert(git_test_helpers::run_git(clone));
	String[] name2  = { "git", "-C", second, "config", "user.name", "Yun Test" };
	String[] email2 = { "git", "-C", second, "config", "user.email", "yun@example.com" };
	assert(git_test_helpers::run_git(name2));
	assert(git_test_helpers::run_git(email2));
	String second_file = string::format(tmem, "%s/file.c3", second);
	assert(git_test_helpers::save_file(second_file, "module test;\n// remote change\n"));
	String[] add2 = { "git", "-C", second, "add", "-A" };
	assert(git_test_helpers::run_git(add2));
	String[] commit2 = { "git", "-C", second, "commit", "-q", "-m", "remote change" };
	assert(git_test_helpers::run_git(commit2));
	String[] push2 = { "git", "-C", second, "push", "-q" };
	assert(git_test_helpers::run_git(push2));

	assert(git_test_helpers::wait_idle(&state, work, 5000));
	revision = state.action_revision;
	assert(state.pull());
	assert(git_test_helpers::wait_action(&state, work, revision, 15000));
	assert(state.action.success);
	char[]? loaded = file::load(tmem, file);
	String pulled  = "";
	if (try data = loaded) pulled = (String)data;
	assert(pulled.contains("remote change"));

	assert(git_test_helpers::wait_idle(&state, work, 5000));
	assert(state.create_branch("topic"));
	assert(git_test_helpers::wait_branch(&state, work, "topic", 5000));
	assert(git_test_helpers::save_file(file, "module test;\n// topic\n"));
	String[] add3 = { "git", "-C", work, "add", "-A" };
	assert(git_test_helpers::run_git(add3));
	String[] commit3 = { "git", "-C", work, "commit", "-q", "-m", "topic" };
	assert(git_test_helpers::run_git(commit3));
	assert(git_test_helpers::wait_idle(&state, work, 5000));
	revision = state.action_revision;
	assert(state.push(true));
	assert(git_test_helpers::wait_action(&state, work, revision, 15000));
	assert(state.action.success);
	String[] verify = { "git", "-C", bare, "rev-parse", "--verify", "topic" };
	assert(git_test_helpers::run_git(verify));
}