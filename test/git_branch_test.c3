module yun::git @test;

import std::collections::list;
import std::io::file;
import std::io::path;
import std::os::process;
import yun::git_test_helpers;

fn void test_branch_parser()
{
	List{GitBranch} branches;
	branches.init(mem);
	defer
	{
		for (sz i = 0; i < branches.len(); i++) branches[i].destroy(mem);
		branches.free();
	}
	String data = "main\0*\0origin/main\0\nfeature\0 \0\0\ndetached-ish\0 \0origin/other\0\n";
	assert(parse_branches(mem, data, &branches));
	assert(branches.len() == 3);
	assert(branches[0].name.compare_to("main") == 0);
	assert(branches[0].current);
	assert(branches[0].upstream.compare_to("origin/main") == 0);
	assert(branches[1].name.compare_to("feature") == 0);
	assert(!branches[1].current);
	assert(branches[1].upstream.len == 0);
	assert(branches[2].upstream.compare_to("origin/other") == 0);
}

fn void test_branch_commands()
{
	String[] list = git_branch_list_argv(mem, "git", "/repo");
	defer git_free_argv(mem, list);
	assert(list.len == 7);
	assert(list[4].compare_to("for-each-ref") == 0);
	assert(list[5].contains("refs/heads") == false);
	assert(list[6].compare_to("refs/heads") == 0);
	String[] switch_argv = git_branch_switch_argv(mem, "git", "/repo", "feature");
	defer git_free_argv(mem, switch_argv);
	assert(switch_argv[3].compare_to("switch") == 0);
	assert(switch_argv[4].compare_to("--") == 0);
	assert(switch_argv[5].compare_to("feature") == 0);
	String[] create = git_branch_create_argv(mem, "git", "/repo", "new-branch");
	defer git_free_argv(mem, create);
	assert(create[3].compare_to("switch") == 0);
	assert(create[4].compare_to("-c") == 0);
	assert(create[5].compare_to("new-branch") == 0);
}

fn void test_branch_integration()
{
	String[] probe = { "git", "--version" };
	if (catch excuse = process::run(probe, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE))
	{
		return;
	}
	String dir = git_test_helpers::temp_dir("yun_git_branches_test");
	defer dir.free(mem);
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
	assert(state.branches_loaded);
	String original = state.status.branch.copy(mem);
	defer original.free(mem);
	assert(original.len > 0);

	ulong revision = state.action_revision;
	assert(state.create_branch("feature"));
	assert(git_test_helpers::wait_action(&state, dir, revision, 5000));
	assert(state.action.success);
	assert(git_test_helpers::wait_branch(&state, dir, "feature", 5000));

	revision = state.action_revision;
	assert(state.switch_branch(original));
	assert(git_test_helpers::wait_action(&state, dir, revision, 5000));
	assert(state.action.success);
	assert(git_test_helpers::wait_branch(&state, dir, original, 5000));
	assert(git_test_helpers::wait_idle(&state, dir, 5000));
	revision = state.action_revision;
	assert(state.switch_branch("does-not-exist"));
	assert(git_test_helpers::wait_action(&state, dir, revision, 5000));
	assert(!state.action.success);
	assert(state.error.kind != GitErrorKind.NONE);
}