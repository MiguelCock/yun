module yun::git @test;

fn void test_panel_groups_and_selection()
{
	State state;
	state.init(mem);
	defer state.destroy();
	state.is_repo = true;
	state.checked = true;
	state.has_status = true;
	String data = "1 .M N... 100644 100644 100644 a a changed.c3\0"
		"1 M. N... 100644 100644 100644 a a staged.c3\0"
		"? untracked.c3\0"
		"u UU N... 100644 100644 100644 100644 a b c conflict.c3\0";
	assert(state.status.parse("/repo", data));
	state.status_revision = 1;

	Panel panel;
	panel.init(mem);
	defer panel.destroy();
	panel.rebuild(&state);
	assert(panel.conflicts == 1);
	assert(panel.staged == 1);
	assert(panel.changes == 1);
	assert(panel.untracked == 1);
	assert(panel.rows.len() == 8);
	assert(panel.selected >= 1);
	assert(row_is_file(panel.rows[panel.selected].kind));

	int first = panel.selected;
	panel.move_selection(1);
	assert(panel.selected > first);
}

fn void test_panel_commit_editing()
{
	Panel panel;
	panel.init(mem);
	defer panel.destroy();
	panel.insert_char('f');
	panel.insert_char('i');
	panel.insert_char('x');
	panel.insert_char('\n');
	panel.insert_char('b');
	assert(panel.message_view().compare_to("fix\nb") == 0);
	assert(panel.message_cursor == 5);
	panel.move_vertical(-1);
	assert(panel.message_cursor == 1);
	panel.insert_char('o');
	assert(panel.message_view().compare_to("foix\nb") == 0);
	panel.backspace();
	assert(panel.message_view().compare_to("fix\nb") == 0);
	panel.clear_message();
	assert(panel.message_len == 0);
}