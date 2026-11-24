module yun::git @test;

fn void test_diff_view_side_by_side_alignment()
{
	DiffView view;
	view.init(mem);
	defer view.destroy();
	String data = "diff --git a/file b/file\n"
		"--- a/file\n"
		"+++ b/file\n"
		"@@ -1,2 +1,3 @@\n"
		"-old\n"
		"+new\n"
		"+extra\n"
		" context\n";
	assert(view.diff.parse(data));
	view.mode = DiffMode.SIDE_BY_SIDE;
	view.rebuild();
	assert(view.rows.len() == 4);
	assert(view.rows[0].header);
	assert(view.rows[1].has_left && view.rows[1].has_right);
	assert(view.rows[1].left_kind == DiffLineKind.DELETE);
	assert(view.rows[1].right_kind == DiffLineKind.ADD);
	assert(!view.rows[2].has_left && view.rows[2].has_right);
	assert(view.rows[2].right_kind == DiffLineKind.ADD);
	assert(view.rows[3].has_left && view.rows[3].has_right);

	view.mode = DiffMode.INLINE;
	view.rebuild();
	assert(view.rows.len() == 5);
	assert(view.rows[1].left_kind == DiffLineKind.DELETE);
	assert(view.rows[2].left_kind == DiffLineKind.ADD);
}