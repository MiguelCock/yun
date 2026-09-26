module yun::commands @test;

fn void test_command_defs()
{
	assert(command_count() == 18);

	CommandDef new_file = command_def(CommandId.NEW_FILE);
	assert(new_file.label.compare_to("New") == 0);
	assert(new_file.shortcut.compare_to("Ctrl+N") == 0);
	assert(new_file.in_top_bar);

	CommandDef new_folder = command_def(CommandId.NEW_FOLDER);
	assert(new_folder.label.compare_to("New Folder") == 0);
	assert(new_folder.shortcut.len == 0);
	assert(!new_folder.in_top_bar);

	CommandDef open = command_def(CommandId.OPEN);
	assert(open.label.compare_to("Open") == 0);
	assert(open.shortcut.compare_to("Ctrl+O") == 0);

	CommandDef save = command_def(CommandId.SAVE);
	assert(save.label.compare_to("Save") == 0);
	assert(save.shortcut.compare_to("Ctrl+S") == 0);

	CommandDef palette = command_def(CommandId.SHOW_PALETTE);
	assert(palette.label.compare_to("Command Palette") == 0);
	assert(palette.shortcut.compare_to("Ctrl+Shift+P") == 0);
	assert(!palette.in_top_bar);

	CommandDef find = command_def(CommandId.FIND);
	assert(find.shortcut.compare_to("Ctrl+F") == 0);
	CommandDef replace = command_def(CommandId.REPLACE);
	assert(replace.shortcut.compare_to("Ctrl+H") == 0);

	CommandDef copy = command_def(CommandId.COPY);
	assert(copy.label.compare_to("Copy") == 0);
	assert(copy.shortcut.compare_to("Ctrl+C") == 0);
	assert(!copy.in_top_bar);
	assert(command_def(CommandId.CUT).shortcut.compare_to("Ctrl+X") == 0);
	assert(command_def(CommandId.PASTE).shortcut.compare_to("Ctrl+V") == 0);
	assert(command_def(CommandId.SELECT_ALL).shortcut.compare_to("Ctrl+A") == 0);
	assert(command_def(CommandId.PROBLEMS).shortcut.compare_to("Ctrl+Shift+M") == 0);
	assert(command_def(CommandId.GO_TO_DEFINITION).shortcut.compare_to("F12") == 0);
	assert(command_def(CommandId.COMPLETE).shortcut.compare_to("Ctrl+Space") == 0);
	assert(command_def(CommandId.SELECT_THEME).shortcut.compare_to("Ctrl+Shift+T") == 0);
	assert(!command_def(CommandId.SELECT_THEME).in_top_bar);
	assert(command_def(CommandId.SEARCH_PROJECT).shortcut.compare_to("Ctrl+Shift+F") == 0);
	assert(!command_def(CommandId.SEARCH_PROJECT).in_top_bar);
	assert(command_def(CommandId.SYMBOLS_PROJECT).shortcut.compare_to("Ctrl+Shift+O") == 0);
	assert(!command_def(CommandId.SYMBOLS_PROJECT).in_top_bar);

	CommandDef settings = command_def(CommandId.TOGGLE_SETTINGS);
	assert(settings.label.compare_to("Settings") == 0);
	assert(settings.bar_label.compare_to("Prefs") == 0);
	assert(settings.shortcut.compare_to("Ctrl+Shift+S") == 0);
	assert(settings.in_top_bar);
}

fn void test_command_from_name()
{
	assert(command_from_name("new_file") == (int)CommandId.NEW_FILE);
	assert(command_from_name("new_folder") == (int)CommandId.NEW_FOLDER);
	assert(command_from_name("open") == (int)CommandId.OPEN);
	assert(command_from_name("save") == (int)CommandId.SAVE);
	assert(command_from_name("show_palette") == (int)CommandId.SHOW_PALETTE);
	assert(command_from_name("copy") == (int)CommandId.COPY);
	assert(command_from_name("cut") == (int)CommandId.CUT);
	assert(command_from_name("paste") == (int)CommandId.PASTE);
	assert(command_from_name("select_all") == (int)CommandId.SELECT_ALL);
	assert(command_from_name("problems") == (int)CommandId.PROBLEMS);
	assert(command_from_name("go_to_definition") == (int)CommandId.GO_TO_DEFINITION);
	assert(command_from_name("complete") == (int)CommandId.COMPLETE);
	assert(command_from_name("select_theme") == (int)CommandId.SELECT_THEME);
	assert(command_from_name("search_project") == (int)CommandId.SEARCH_PROJECT);
	assert(command_from_name("symbols_project") == (int)CommandId.SYMBOLS_PROJECT);
	assert(command_from_name("toggle_settings") == (int)CommandId.TOGGLE_SETTINGS);
	assert(command_from_name("nope") == -1);
}

fn void test_bar_commands()
{
	assert(bar_command_count() == 4);
	assert(bar_command(0).id == CommandId.NEW_FILE);
	assert(bar_command(1).id == CommandId.OPEN);
	assert(bar_command(2).id == CommandId.SAVE);
	assert(bar_command(3).id == CommandId.TOGGLE_SETTINGS);
}

fn void test_command_enabled()
{
	assert(command_enabled(CommandId.NEW_FILE, true, false));
	assert(!command_enabled(CommandId.NEW_FILE, false, false));
	assert(command_enabled(CommandId.NEW_FOLDER, true, false));
	assert(!command_enabled(CommandId.NEW_FOLDER, false, false));

	assert(command_enabled(CommandId.OPEN, false, false));
	assert(command_enabled(CommandId.OPEN, true, true));

	assert(command_enabled(CommandId.SAVE, true, true));
	assert(!command_enabled(CommandId.SAVE, true, false));
	assert(command_enabled(CommandId.SAVE, false, true));
	assert(command_enabled(CommandId.SHOW_PALETTE, false, false));
	assert(command_enabled(CommandId.COPY, true, true));
	assert(!command_enabled(CommandId.COPY, true, false));
	assert(command_enabled(CommandId.SELECT_ALL, true, true));
	assert(command_enabled(CommandId.PROBLEMS, false, false));
	assert(command_enabled(CommandId.GO_TO_DEFINITION, true, true));
	assert(!command_enabled(CommandId.GO_TO_DEFINITION, true, false));
	assert(command_enabled(CommandId.COMPLETE, true, true));
	assert(command_enabled(CommandId.SELECT_THEME, false, false));
	assert(command_enabled(CommandId.SEARCH_PROJECT, true, false));
	assert(!command_enabled(CommandId.SEARCH_PROJECT, false, false));
	assert(command_enabled(CommandId.SYMBOLS_PROJECT, true, false));
	assert(!command_enabled(CommandId.SYMBOLS_PROJECT, false, false));
	assert(command_enabled(CommandId.TOGGLE_SETTINGS, false, false));
	assert(command_enabled(CommandId.TOGGLE_SETTINGS, true, true));
}

fn void test_fuzzy_exact_and_case()
{
	usz[8] positions;
	int exact = fuzzy_match("Open", "open", positions[0:8]);
	assert(exact > 0);
	assert(positions[0] == 0 && positions[1] == 1);

	int upper = fuzzy_match("Save", "SA", positions[0:8]);
	assert(upper > 0);
	assert(positions[0] == 0 && positions[1] == 1);
}

fn void test_fuzzy_contiguous_beats_gapped()
{
	usz[8] positions;
	int contiguous = fuzzy_match("Open", "op", positions[0:8]);
	int gapped     = fuzzy_match("Open", "oe", positions[0:8]);
	assert(contiguous > gapped);
}

fn void test_fuzzy_boundary_bonus()
{
	usz[8] positions;
	int boundary = fuzzy_match("New Folder", "nf", positions[0:8]);
	int inner    = fuzzy_match("New Folder", "ol", positions[0:8]);
	assert(boundary > inner);
}

fn void test_fuzzy_no_match()
{
	usz[8] positions;
	assert(fuzzy_match("Save", "xyz", positions[0:8]) == -1);
	assert(fuzzy_match("Save", "es", positions[0:8]) == -1);
}

fn void test_fuzzy_capacity_guard()
{
	usz[1] positions;
	assert(fuzzy_match("Open", "op", positions[0:1]) == -1);
}