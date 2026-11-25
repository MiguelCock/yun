module yun::vim_command @test;

fn void test_parse_commands()
{
	@pool()
	{
		Command cmd = parse_command("w", tmem);
		assert(cmd.kind == Kind.WRITE);
		cmd = parse_command("write", tmem);
		assert(cmd.kind == Kind.WRITE);
		cmd = parse_command("q", tmem);
		assert(cmd.kind == Kind.QUIT);
		cmd = parse_command("wq", tmem);
		assert(cmd.kind == Kind.WRITE_QUIT);
		cmd = parse_command("e src/main.c3", tmem);
		assert(cmd.kind == Kind.EDIT);
		assert(cmd.arg.compare_to("src/main.c3") == 0);
		cmd = parse_command("edit README.md", tmem);
		assert(cmd.kind == Kind.EDIT);
		assert(cmd.arg.compare_to("README.md") == 0);
		cmd = parse_command("unknown", tmem);
		assert(cmd.kind == Kind.UNKNOWN);
		cmd = parse_command("  ", tmem);
		assert(cmd.kind == Kind.NONE);
	};
}

fn void test_history_navigation()
{
	CommandLine line;
	line.init(mem);
	line.show();
	line.add_history("w");
	line.add_history("e src/main.c3");
	line.add_history("w");
	assert(line.history.len() == 3);

	line.show();
	line.history_prev();
	assert(line.text_view().compare_to("w") == 0);
	line.history_prev();
	assert(line.text_view().compare_to("e src/main.c3") == 0);
	line.history_prev();
	assert(line.text_view().compare_to("w") == 0);
	line.history_prev();
	assert(line.text_view().compare_to("w") == 0);
	line.history_next();
	assert(line.text_view().compare_to("e src/main.c3") == 0);
	line.history_next();
	assert(line.text_view().compare_to("w") == 0);
	line.history_next();
	assert(line.text_view().len == 0);

	line.destroy();
}

fn void test_text_editing()
{
	CommandLine line;
	line.init(mem);
	line.show();
	line.append('w');
	line.append('q');
	assert(line.text_view().compare_to("wq") == 0);
	line.backspace();
	assert(line.text_view().compare_to("w") == 0);
	line.destroy();
}