module yun::settings_panel @test;

import yun::commands;
import yun::config;
import yun::keymap;
import yun::settings;

fn void test_command_descriptions()
{
	for (usz i = 0; i < commands::command_count(); i++)
	{
		String description = commands::command_description((commands::CommandId)i);
		assert(description.len > 0);
		for (usz c = 0; c < description.len; c++) assert(description[c] != '\n');
	}
}

fn void test_command_groups()
{
	assert(commands::COMMAND_GROUPS.len == 7);
	bool[7] used;
	for (usz i = 0; i < commands::command_count(); i++)
	{
		String group =  commands::command_group((commands::CommandId)i);
		int found    = -1;
		for (usz g = 0; g < commands::COMMAND_GROUPS.len; g++)
		{
			if (commands::COMMAND_GROUPS[g].compare_to(group) == 0) found = (int)g;
		}
		assert(found >= 0);
		used[found] = true;
	}
	for (usz g = 0; g < commands::COMMAND_GROUPS.len; g++) assert(used[g]);
	assert(commands::command_group(commands::CommandId.SAVE).compare_to("General") == 0);
	assert(commands::command_group(commands::CommandId.PAN_LEFT).compare_to("Canvas") == 0);
	assert(commands::command_group(commands::CommandId.UNDO).compare_to("Editor") == 0);
	assert(commands::command_group(commands::CommandId.CONSOLE_RUN).compare_to("Console") == 0);
	assert(commands::command_group(commands::CommandId.LIST_UP).compare_to("Overlays") == 0);
	assert(commands::command_group(commands::CommandId.SETTINGS_RESET).compare_to("Settings") == 0);
	assert(commands::command_group(commands::CommandId.TOPBAR_LEFT).compare_to("Top bar") == 0);
	assert(commands::command_group(commands::CommandId.TOGGLE_CONSOLE).compare_to("Console") == 0);
	assert(commands::command_group(commands::CommandId.TOGGLE_SETTINGS).compare_to("Settings") == 0);
	assert(commands::command_group(commands::CommandId.FOCUS_TOP_BAR).compare_to("Top bar") == 0);
}

fn void test_keys_grouped_rows()
{
	@pool()
	{
		Panel p;
		p.init(tmem);
		p.show();
		p.set_page(settings::SettingPage.KEYS);

		assert(p.rows.len() == (sz)commands::command_count() + (sz)commands::COMMAND_GROUPS.len + 1);
		String current    = "";
		int command_rows  = 0;
		int headers       = 0;
		bool found_action = false;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			Row row = p.rows[i];
			if (row.kind == RowKind.HEADER)
			{
				current = row.section;
				headers++;
				bool known = false;
				for (usz g = 0; g < commands::COMMAND_GROUPS.len; g++)
				{
					if (commands::COMMAND_GROUPS[g].compare_to(current) == 0) known = true;
				}
				assert(known);
			}
			if (row.kind == RowKind.COMMAND)
			{
				command_rows++;
				assert(current.len > 0);
				assert(commands::command_group(row.command).compare_to(current) == 0);
			}
			if (row.kind == RowKind.ACTION) found_action = true;
		}
		assert(command_rows == (int)commands::command_count());
		assert(headers == (int)commands::COMMAND_GROUPS.len);
		assert(found_action);
		assert(p.selected_row() >= 0);
		assert(p.rows[p.rows.len() - 1].kind == RowKind.ACTION);

		p.layout_keys(2);
		int first  = -1;
		int second = -1;
		int third  = -1;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			if (p.rows[i].kind != RowKind.COMMAND) continue;
			if (first < 0)
			{
				first = (int)i;
			}
			else if (second < 0)
			{
				second = (int)i;
			}
			else if (third < 0)
			{
				third = (int)i;
				break;
			}
		}
		assert(first >= 0 && second >= 0 && third >= 0);
		assert(p.rows[first].grid_col == 0);
		assert(p.rows[second].grid_col == 1);
		assert(p.rows[first].grid_y == p.rows[second].grid_y);
		assert(p.rows[third].grid_y > p.rows[first].grid_y);
		p.destroy();
	};
}

fn void test_key_search_description_and_group()
{
	assert(command_matches(commands::CommandId.SAVE, "disk"));
	assert(!command_matches(commands::CommandId.QUIT, "disk"));
	assert(command_matches(commands::CommandId.LIST_UP, "overlays"));
	assert(command_matches(commands::CommandId.SAVE, "general"));
	assert(command_matches(commands::CommandId.SAVE, "save"));
	assert(command_matches(commands::CommandId.SAVE, "save_file") == false);
	assert(!command_matches(commands::CommandId.SAVE, "zzzzz"));
}

fn void test_key_filters()
{
	@pool()
	{
		config::Config cfg;
		cfg.init(tmem);
		cfg.set_key_binding("save", "Ctrl+O", settings::SettingLayer.GLOBAL);
		cfg.set_key_binding("quit", "", settings::SettingLayer.GLOBAL);

		keymap::Keymap km;
		km.init(tmem);
		km.build(&cfg);

		Panel p;
		p.init(tmem);
		p.set_sources(&km, &cfg);
		p.show();
		p.set_page(settings::SettingPage.KEYS);

		p.set_key_filter(KeyFilter.ALL);
		int all_rows = 0;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			if (p.rows[i].kind == RowKind.COMMAND) all_rows++;
		}
		assert(all_rows == (int)commands::command_count());

		p.set_key_filter(KeyFilter.CONFLICTS);
		bool conflict_save = false;
		bool conflict_open = false;
		bool conflict_quit = false;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			if (p.rows[i].kind != RowKind.COMMAND) continue;
			if (p.rows[i].command == commands::CommandId.SAVE) conflict_save = true;
			if (p.rows[i].command == commands::CommandId.OPEN) conflict_open = true;
			if (p.rows[i].command == commands::CommandId.QUIT) conflict_quit = true;
		}
		assert(conflict_save);
		assert(conflict_open);
		assert(!conflict_quit);

		p.set_key_filter(KeyFilter.MODIFIED);
		bool modified_save = false;
		bool modified_quit = false;
		bool modified_open = false;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			if (p.rows[i].kind != RowKind.COMMAND) continue;
			if (p.rows[i].command == commands::CommandId.SAVE) modified_save = true;
			if (p.rows[i].command == commands::CommandId.QUIT) modified_quit = true;
			if (p.rows[i].command == commands::CommandId.OPEN) modified_open = true;
		}
		assert(modified_save);
		assert(modified_quit);
		assert(!modified_open);

		p.set_key_filter(KeyFilter.UNBOUND);
		bool unbound_quit       = false;
		bool unbound_new_folder = false;
		bool unbound_save       = false;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			if (p.rows[i].kind != RowKind.COMMAND) continue;
			if (p.rows[i].command == commands::CommandId.QUIT) unbound_quit = true;
			if (p.rows[i].command == commands::CommandId.NEW_FOLDER) unbound_new_folder = true;
			if (p.rows[i].command == commands::CommandId.SAVE) unbound_save = true;
		}
		assert(unbound_quit);
		assert(unbound_new_folder);
		assert(!unbound_save);

		p.destroy();
		km.destroy();
		cfg.destroy();
	};
}

fn void test_key_selection_movement()
{
	@pool()
	{
		Panel p;
		p.init(tmem);
		p.show();
		p.set_page(settings::SettingPage.KEYS);
		p.layout_keys(2);

		int first  = -1;
		int second = -1;
		int third  = -1;
		int last   = -1;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			if (p.rows[i].kind != RowKind.COMMAND) continue;
			if (first < 0)
			{
				first = (int)i;
			}
			else if (second < 0)
			{
				second = (int)i;
			}
			else if (third < 0)
			{
				third = (int)i;
			}
			last = (int)i;
		}
		assert(first >= 0 && second >= 0 && third >= 0 && last >= 0);

		p.selected = first;
		p.move_keys_horizontal(1);
		assert(p.selected == second);
		p.move_keys_horizontal(-1);
		assert(p.selected == first);
		p.move_keys_vertical(1);
		assert(p.selected == third);
		p.move_keys_edge(true);
		assert(p.selected == last);
		p.move_keys_edge(false);
		assert(p.selected == first);
		p.move_keys_page(1);
		assert(p.selected != first);
		p.destroy();
	};
}

fn void test_keys_filter()
{
	@pool()
	{
		Panel p;
		p.init(tmem);
		p.show();
		p.append_query('s');
		p.append_query('a');
		p.append_query('v');
		p.append_query('e');
		p.rebuild();

		bool found_save = false;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			if (p.rows[i].kind == RowKind.COMMAND && p.rows[i].command == commands::CommandId.SAVE) found_save = true;
		}
		assert(found_save);
		p.destroy();
	};
}

fn void test_step_int_clamps()
{
	settings::SettingSpec s = settings::SETTINGS[(int)settings::SettingId.EDITOR_FONT_SIZE];
	assert(step_int(s, 16, 1) == 17);
	assert(step_int(s, 16, -1) == 15);
	assert(step_int(s, 48, 1) == 48);
	assert(step_int(s, 8, -1) == 8);
}

fn void test_step_float_clamps()
{
	settings::SettingSpec s = {
		.kind = settings::SettingKind.FLOAT,
		.min = 0.5,
		.max = 2.0,
		.step = 0.25,
	};
	assert(step_float(s, 1.0, 1) == 1.25);
	assert(step_float(s, 2.0, 1) == 2.0);
	assert(step_float(s, 0.5, -1) == 0.5);
}

fn void test_enum_next_wraps()
{
	String[] options = settings::SETTINGS[(int)settings::SettingId.APP_THEME].options;
	assert(enum_next(options, "yun_dark", 1).compare_to("yun_light") == 0);
	assert(enum_next(options, "yun_dark", -1).compare_to("catppuccin_latte") == 0);
	assert(enum_next(options, "catppuccin_latte", 1).compare_to("yun_dark") == 0);
	assert(enum_next(options, "unknown", 1).compare_to("yun_dark") == 0);
	assert(enum_next(options, "unknown", -1).compare_to("catppuccin_latte") == 0);
}

fn void test_matches()
{
	assert(matches("editor", "Font size", "font_size", "Editor font size in pixels.", ""));
	assert(matches("editor", "Font size", "font_size", "Editor font size in pixels.", "font"));
	assert(matches("editor", "Font size", "font_size", "Editor font size in pixels.", "edf"));
	assert(!matches("editor", "Font size", "font_size", "Editor font size in pixels.", "zzz"));
}
fn void test_page_mapping()
{
	assert(settings::page_for(settings::SettingId.APP_THEME) == settings::SettingPage.APPEARANCE);
	assert(settings::page_for(settings::SettingId.EDITOR_FONT_SIZE) == settings::SettingPage.EDITOR);
	assert(settings::page_for(settings::SettingId.CANVAS_GRID_CELL) == settings::SettingPage.CANVAS);
	assert(settings::page_for(settings::SettingId.SEARCH_MAX_RESULTS) == settings::SettingPage.ADVANCED);
	assert(settings::page_for(settings::SettingId.CANVAS_SNAP_TO_GRID) == settings::SettingPage.CANVAS);
	assert(settings::page_for(settings::SettingId.CANVAS_SNAP_STEP) == settings::SettingPage.CANVAS);
	assert(settings::page_for(settings::SettingId.CONSOLE_MAX_LINES) == settings::SettingPage.CONSOLE);
	assert(settings::page_for(settings::SettingId.CONSOLE_NOTIFY) == settings::SettingPage.CONSOLE);
	assert(settings::page_for(settings::SettingId.CONSOLE_RESTORE_SESSIONS) == settings::SettingPage.CONSOLE);
	assert(settings::page_for(settings::SettingId.CONSOLE_AUTO_SCROLL) == settings::SettingPage.CONSOLE);
	assert(settings::page_for(settings::SettingId.CONSOLE_AUTOCOMPLETE) == settings::SettingPage.CONSOLE);
	assert(settings::page_for(settings::SettingId.LSP_ENABLED) == settings::SettingPage.INTEGRATIONS);
	assert(settings::page_for(settings::SettingId.APP_SKIP_SUBMODULES) == settings::SettingPage.GENERAL);
}

fn void test_page_rows()
{
	@pool()
	{
		Panel p;
		p.init(tmem);
		p.show();
		p.set_page(settings::SettingPage.APPEARANCE);

		bool found_setting = false;
		bool found_reset   = false;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			if (p.rows[i].kind == RowKind.SETTING) found_setting = true;
			if (p.rows[i].kind == RowKind.PAGE_RESET) found_reset = true;
			assert(p.rows[i].kind != RowKind.COMMAND);
		}
		assert(found_setting);
		assert(found_reset);
		p.destroy();
	};
}

fn void test_cross_page_search()
{
	@pool()
	{
		Panel p;
		p.init(tmem);
		p.show();
		p.append_query('w');
		p.append_query('o');
		p.append_query('r');
		p.append_query('k');
		p.append_query('e');
		p.append_query('r');
		p.append_query('s');
		p.rebuild();

		bool found_advanced = false;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			if (p.rows[i].kind == RowKind.SETTING
				&& p.rows[i].page == settings::SettingPage.ADVANCED) found_advanced = true;
		}
		assert(found_advanced);
		p.destroy();
	};
}