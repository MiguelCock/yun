module yun::settings_panel @test;

import yun::commands;
import yun::settings;

fn void test_keys_section_rows()
{
	@pool()
	{
		Panel p;
		p.init(tmem);
		p.show();
		p.set_page(settings::SettingPage.KEYS);

		assert(p.rows.len() == (sz)commands::command_count() + 2);
		bool found_header = false;
		bool found_action = false;
		int command_rows  = 0;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			Row row = p.rows[i];
			if (row.kind == RowKind.HEADER && row.section.compare_to("Keybindings") == 0) found_header = true;
			if (row.kind == RowKind.ACTION) found_action = true;
			if (row.kind == RowKind.COMMAND) command_rows++;
		}
		assert(found_header);
		assert(found_action);
		assert(command_rows == (int)commands::command_count());
		assert(p.selected_row() >= 0);
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