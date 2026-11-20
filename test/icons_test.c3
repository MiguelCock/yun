module yun::icons @test;

import raylib6::rl;
import std::math::geometry;
import yun::ui;

fn void test_icon_size_and_box()
{
	ui::set_ui_scale(1.0f);
	ui::set_dpi(1.0f, 1.0f);
	assert(icon_size(16) == 16.0f);

	Rect button = { .x = 10.0f, .y = 10.0f, .width = 100.0f, .height = 40.0f };
	Rect box    = icon_box(button, 16);
	assert(box.x == 52.0f);
	assert(box.y == 22.0f);
	assert(box.width == 16.0f);
	assert(box.height == 16.0f);
}
fn void test_language_icon_names()
{
	assert(file_icon_theme_name(FileIconTheme.MATERIAL).compare_to("material") == 0);
	assert(file_icon_theme_name(FileIconTheme.VSCODE).compare_to("vscode") == 0);
	assert(file_icon_name(FileIconTheme.MATERIAL, "src/main.c3").compare_to("c3") == 0);
	assert(file_icon_name(FileIconTheme.VSCODE, "src/main.c3").compare_to("file_type_c3") == 0);
	assert(file_icon_name(FileIconTheme.MATERIAL, "src/main.py").compare_to("python") == 0);
	assert(file_icon_name(FileIconTheme.VSCODE, "src/main.py").compare_to("file_type_python") == 0);
	assert(file_icon_name(FileIconTheme.MATERIAL, "unknown.xyz").compare_to("file") == 0);
	assert(file_icon_name(FileIconTheme.VSCODE, "unknown.xyz").compare_to("default_file") == 0);
}