module yun::commands @test;

fn void test_command_defs()
{
	assert(command_count() == 3);

	CommandDef new_file = command_def(CommandId.NEW_FILE);
	assert(new_file.label.compare_to("New") == 0);
	assert(new_file.shortcut.compare_to("Ctrl+N") == 0);

	CommandDef open = command_def(CommandId.OPEN);
	assert(open.label.compare_to("Open") == 0);
	assert(open.shortcut.compare_to("Ctrl+O") == 0);

	CommandDef save = command_def(CommandId.SAVE);
	assert(save.label.compare_to("Save") == 0);
	assert(save.shortcut.compare_to("Ctrl+S") == 0);
}

fn void test_command_enabled()
{
	assert(command_enabled(CommandId.NEW_FILE, true, false));
	assert(!command_enabled(CommandId.NEW_FILE, false, false));

	assert(command_enabled(CommandId.OPEN, false, false));
	assert(command_enabled(CommandId.OPEN, true, true));

	assert(command_enabled(CommandId.SAVE, true, true));
	assert(!command_enabled(CommandId.SAVE, true, false));
	assert(command_enabled(CommandId.SAVE, false, true));
}