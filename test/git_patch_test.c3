module yun::git @test;

import std::io::file;
import std::io::path;
import std::os::process;
import yun::git_test_helpers;

fn void test_hunk_patch_builder()
{
	DiffFile diff;
	diff.init(mem);
	defer diff.destroy();
	String data = "diff --git a/file.c3 b/file.c3\n"
		"--- a/file.c3\n"
		"+++ b/file.c3\n"
		"@@ -1,3 +1,3 @@\n"
		" module test;\n"
		"-int value = 1;\n"
		"+int value = 2;\n"
		" \n";
	assert(diff.parse(data));
	String patch = build_hunk_patch(mem, &diff, 0, "file.c3");
	defer patch.free(mem);
	assert(patch.contains("diff --git a/file.c3 b/file.c3\n"));
	assert(patch.contains("--- a/file.c3\n"));
	assert(patch.contains("+++ b/file.c3\n"));
	assert(patch.contains("@@ -1,3 +1,3 @@\n"));
	assert(patch.contains("-int value = 1;\n"));
	assert(patch.contains("+int value = 2;\n"));
}

fn void test_hunk_apply_integration()
{
	String[] probe = { "git", "--version" };
	if (catch err = process::run(probe, { }, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE))
	{
		return;
	}
	String dir = git_test_helpers::temp_dir("yun_git_patch_test");
	defer dir.free(mem);
	if (catch err = path::mkdir(dir, recursive: true)) return;
	String file    = string::format(tmem, "%s/file.c3", dir);
	String content = "module test;\n";
	for (int i = 0; i < 10; i++) content = string::format(tmem, "%sint line%d = 0;\n", content, i);
	content = string::format(tmem, "%sint top = 1;\n", content);
	for (int i = 0; i < 10; i++) content = string::format(tmem, "%sint more%d = 0;\n", content, i);
	content = string::format(tmem, "%sint bottom = 1;\n", content);
	assert(git_test_helpers::save_file(file, content));
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

	String modified = "module test;\n";
	for (int i = 0; i < 10; i++) modified = string::format(tmem, "%sint line%d = 0;\n", modified, i);
	modified = string::format(tmem, "%sint top = 2;\n", modified);
	for (int i = 0; i < 10; i++) modified = string::format(tmem, "%sint more%d = 0;\n", modified, i);
	modified = string::format(tmem, "%sint bottom = 2;\n", modified);
	assert(git_test_helpers::save_file(file, modified));

	String[] diff_argv = { "git", "-C", dir, "diff", "--no-color", "--no-ext-diff", "--unified=3", "--", "file.c3" };
	String diff_text   = git_test_helpers::capture_git(diff_argv);
	defer diff_text.free(mem);
	DiffFile diff;
	diff.init(mem);
	defer diff.destroy();
	assert(diff.parse(diff_text));
	assert(diff.hunks.len() == 2);
	String patch = build_hunk_patch(mem, &diff, 0, "file.c3");
	defer patch.free(mem);
	assert(patch.len > 0);
	String patch_file = string::format(tmem, "%s/selected.patch", dir);
	assert(git_test_helpers::save_file(patch_file, patch));
	String[] apply = { "git", "-C", dir, "apply", "--cached", patch_file };
	assert(git_test_helpers::run_git(apply));
	String staged = git_test_helpers::capture_git({ "git", "-C", dir, "diff", "--cached", "--", "file.c3" });
	defer staged.free(mem);
	assert(staged.contains("int top = 2;"));
	assert(!staged.contains("int bottom = 2;"));
	String unstaged = git_test_helpers::capture_git({ "git", "-C", dir, "diff", "--", "file.c3" });
	defer unstaged.free(mem);
	assert(unstaged.contains("int bottom = 2;"));
	assert(!unstaged.contains("int top = 2;"));
}