module yun::git @test;

fn void test_diff_modified_file()
{
	DiffFile diff;
	diff.init(mem);
	defer diff.destroy();
	String data = "diff --git a/file.c3 b/file.c3\n"
		"index 111..222 100644\n"
		"--- a/file.c3\n"
		"+++ b/file.c3\n"
		"@@ -1,3 +1,4 @@\n"
		" module test;\n"
		"-int old = 1;\n"
		"+int old = 2;\n"
		"+int added = 3;\n"
		" \n";
	assert(diff.parse(data));
	assert(diff.valid);
	assert(!diff.binary);
	assert(diff.hunks.len() == 1);
	DiffHunk* hunk = &diff.hunks[0];
	assert(hunk.old_start == 1);
	assert(hunk.old_count == 3);
	assert(hunk.new_start == 1);
	assert(hunk.new_count == 4);
	assert(diff.additions == 2);
	assert(diff.deletions == 1);
	assert(hunk.lines.len() == 5);
	assert(hunk.lines[0].kind == DiffLineKind.CONTEXT);
	assert(hunk.lines[0].old_line == 1);
	assert(hunk.lines[0].new_line == 1);
	assert(hunk.lines[1].kind == DiffLineKind.DELETE);
	assert(hunk.lines[1].old_line == 2);
	assert(hunk.lines[2].kind == DiffLineKind.ADD);
	assert(hunk.lines[2].new_line == 2);
	assert(hunk.lines[3].kind == DiffLineKind.ADD);
	assert(hunk.lines[4].kind == DiffLineKind.CONTEXT);
}

fn void test_diff_new_file_and_binary()
{
	DiffFile added;
	added.init(mem);
	defer added.destroy();
	String add_data = "diff --git a/new.c3 b/new.c3\n"
		"new file mode 100644\n"
		"--- /dev/null\n"
		"+++ b/new.c3\n"
		"@@ -0,0 +1,2 @@\n"
		"+module new;\n"
		"+fn void main() {}\n";
	assert(added.parse(add_data));
	assert(added.hunks.len() == 1);
	assert(added.additions == 2);
	assert(added.deletions == 0);

	DiffFile binary;
	binary.init(mem);
	defer binary.destroy();
	assert(binary.parse("diff --git a/logo.png b/logo.png\nBinary files a/logo.png and b/logo.png differ\n"));
	assert(binary.binary);
	assert(binary.hunks.len() == 0);
}

fn void test_diff_no_newline_marker()
{
	DiffFile diff;
	diff.init(mem);
	defer diff.destroy();
	String data = "diff --git a/file b/file\n"
		"--- a/file\n"
		"+++ b/file\n"
		"@@ -1 +1 @@\n"
		"-old\n"
		"\\ No newline at end of file\n"
		"+new\n"
		"\\ No newline at end of file\n";
	assert(diff.parse(data));
	assert(diff.hunks.len() == 1);
	assert(diff.hunks[0].lines.len() == 4);
	assert(diff.hunks[0].lines[1].kind == DiffLineKind.META);
	assert(diff.hunks[0].lines[3].kind == DiffLineKind.META);
}

fn void test_diff_empty()
{
	DiffFile diff;
	diff.init(mem);
	defer diff.destroy();
	assert(diff.parse(""));
	assert(diff.valid);
	assert(diff.hunks.len() == 0);
	assert(diff.additions == 0);
}