module yun::settings_panel @test;

import yun::settings;

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
	settings::SettingSpec s = settings::SETTINGS[(int)settings::SettingId.APP_THEME];
	assert(enum_next(s, "yun_dark", 1).compare_to("yun_light") == 0);
	assert(enum_next(s, "yun_dark", -1).compare_to("catppuccin_latte") == 0);
	assert(enum_next(s, "catppuccin_latte", 1).compare_to("yun_dark") == 0);
	assert(enum_next(s, "unknown", 1).compare_to("yun_dark") == 0);
	assert(enum_next(s, "unknown", -1).compare_to("catppuccin_latte") == 0);
}

fn void test_matches()
{
	assert(matches("editor", "Font size", "font_size", "Editor font size in pixels.", ""));
	assert(matches("editor", "Font size", "font_size", "Editor font size in pixels.", "font"));
	assert(matches("editor", "Font size", "font_size", "Editor font size in pixels.", "edf"));
	assert(!matches("editor", "Font size", "font_size", "Editor font size in pixels.", "zzz"));
}