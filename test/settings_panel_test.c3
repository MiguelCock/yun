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

		assert(p.rows.len() == 101);
		bool found_header = false;
		bool found_action = false;
		int command_rows  = 0;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			Row row = p.rows[i];
			if (row.kind == RowKind.HEADER && row.section.compare_to("keys") == 0) found_header = true;
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