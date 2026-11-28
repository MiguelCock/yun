module yun::settings_panel @test;

import std::io::file;
import std::io::path;
import std::math;
import yun::commands;
import yun::config;
import yun::image_picker;
import yun::keymap;
import yun::settings;
import yun::skin;

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

fn void test_skin_page_registered()
{
	assert(settings::page_label(settings::SettingPage.SKIN).compare_to("Skin") == 0);
	@pool()
	{
		Panel p;
		p.init(tmem);
		p.show();
		p.set_page(settings::SettingPage.SKIN);
		assert(p.skin_row(SkinItem.PRESET) >= 0);
		assert(p.skin_row(SkinItem.CARD_STYLE) >= 0);
		assert(p.skin_row(SkinItem.FOLDER_STYLE) >= 0);
		assert(p.skin_row(SkinItem.CLOSED_HEIGHT) >= 0);
		assert(p.skin_row(SkinItem.LANGUAGE_COLORS) >= 0);
		assert(p.skin_row(SkinItem.IMAGE_SCOPE) >= 0);
		assert(p.skin_row(SkinItem.CARD_LAYOUT) >= 0);
		assert(p.skin_row(SkinItem.SURFACE) >= 0);
		assert(p.skin_row(SkinItem.IMAGE) >= 0);
		assert(p.skin_row(SkinItem.BROWSE) >= 0);
		assert(p.skin_row(SkinItem.FIT) >= 0);
		assert(p.skin_row(SkinItem.OPACITY) >= 0);
		assert(p.skin_row(SkinItem.TINT) >= 0);
		assert(p.skin_row(SkinItem.SCRIM) >= 0);
		assert(p.skin_row(SkinItem.SPEED) >= 0);
		assert(p.skin_row(SkinItem.FPS) >= 0);
		assert(p.skin_row(SkinItem.RELOAD) >= 0);
		assert(p.skin_row(SkinItem.RESET) >= 0);
		bool found_style   = false;
		bool found_surface = false;
		bool found_actions = false;
		for (sz i = 0; i < p.rows.len(); i++)
		{
			if (p.rows[i].kind != RowKind.HEADER) continue;
			if (p.rows[i].section.compare_to("Style") == 0) found_style = true;
			if (p.rows[i].section.compare_to("Surface") == 0) found_surface = true;
			if (p.rows[i].section.compare_to("Actions") == 0) found_actions = true;
		}
		assert(found_style && found_surface && found_actions);
		p.destroy();
	};
}

fn void test_skin_page_steps_and_persists()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? dir = tmp.append(tmem, "yun_skin_panel_test");
		if (catch excuse = dir) return;
		Path root = dir;
		(void)path::rmtree(root);
		if (catch excuse = path::mkdir(root, recursive: true)) return;

		skin::init_headless(tmem);
		config::Config cfg;
		cfg.init(tmem);
		cfg.reset();
		skin::set_base(string::format(tmem, "%s/.yun", (String)root), settings::SettingLayer.PROJECT);

		Panel p;
		p.init(tmem);
		p.show();
		p.set_page(settings::SettingPage.SKIN);
		p.scope = settings::SettingLayer.PROJECT;

		p.selected = p.skin_row(SkinItem.PRESET);
		assert(p.selected >= 0);
		p.change_skin(&cfg, 1, true, (String)root, null);
		assert(skin::preset().compare_to("paper") == 0);

		Path? cfg_path = root.append(tmem, ".yun/config.json");
		if (catch excuse = cfg_path) return;
		assert(path::exists(cfg_path));
		char[]? saved = file::load(tmem, cfg_path);
		if (catch excuse = saved) return;
		String raw = (String)saved;
		assert(raw.contains("\"skin\""));
		assert(raw.contains("\"preset\":\"paper\""));

		p.selected = p.skin_row(SkinItem.OPACITY);
		float before = skin::surface(skin::SurfaceId.APP).opacity;
		p.change_skin(&cfg, -1, true, (String)root, null);
		assert(skin::surface(skin::SurfaceId.APP).opacity < before);

		p.selected = p.skin_row(SkinItem.FIT);
		p.change_skin(&cfg, 1, true, (String)root, null);
		assert(skin::surface(skin::SurfaceId.APP).fit == skin::SurfaceFit.CONTAIN);

		p.selected = p.skin_row(SkinItem.SURFACE);
		p.change_skin(&cfg, 1, true, (String)root, null);
		assert(p.skin_surface == skin::SurfaceId.CARD);

		p.selected = p.skin_row(SkinItem.CLOSED_HEIGHT);
		p.change_skin(&cfg, 1, true, (String)root, null);
		assert(skin::closed_height() > 96.0f);

		p.selected = p.skin_row(SkinItem.IMAGE_SCOPE);
		p.change_skin(&cfg, 1, true, (String)root, null);
		assert(skin::image_scope() == skin::ImageScope.ALL);

		p.destroy();
		cfg.destroy();
		(void)path::rmtree(root);
	};
}

fn void test_skin_page_text_edit_validation()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? dir = tmp.append(tmem, "yun_skin_panel_edit_test");
		if (catch excuse = dir) return;
		Path root = dir;
		(void)path::rmtree(root);
		if (catch excuse = path::mkdir(root, recursive: true)) return;

		skin::init_headless(tmem);
		config::Config cfg;
		cfg.init(tmem);
		cfg.reset();
		skin::set_base(string::format(tmem, "%s/.yun", (String)root), settings::SettingLayer.PROJECT);

		Panel p;
		p.init(tmem);
		p.show();
		p.set_page(settings::SettingPage.SKIN);
		p.scope = settings::SettingLayer.PROJECT;

		p.selected = p.skin_row(SkinItem.TINT);
		p.start_skin_edit(&cfg);
		assert(p.skin_editing);
		String invalid = "#zzzzzz";
		p.skin_edit_len = (int)invalid.len;
		for (usz i = 0; i < invalid.len; i++) p.skin_edit_buf[i] = invalid[i];
		p.skin_edit_buf[p.skin_edit_len] = 0;
		assert(!p.commit_skin_edit(&cfg, true, (String)root, null));
		assert(p.skin_editing);

		String valid = "#11223344";
		p.skin_edit_len = (int)valid.len;
		for (usz i = 0; i < valid.len; i++) p.skin_edit_buf[i] = valid[i];
		p.skin_edit_buf[p.skin_edit_len] = 0;
		assert(p.commit_skin_edit(&cfg, true, (String)root, null));
		assert(!p.skin_editing);
		assert(skin::surface(skin::SurfaceId.APP).tint[0] == 0x11);
		assert(skin::surface(skin::SurfaceId.APP).tint[1] == 0x22);
		assert(skin::surface(skin::SurfaceId.APP).tint[2] == 0x33);
		assert(skin::surface(skin::SurfaceId.APP).tint[3] == 0x44);

		p.selected = p.skin_row(SkinItem.IMAGE);
		p.start_skin_edit(&cfg);
		String unsupported = "notes.txt";
		p.skin_edit_len = (int)unsupported.len;
		for (usz i = 0; i < unsupported.len; i++) p.skin_edit_buf[i] = unsupported[i];
		p.skin_edit_buf[p.skin_edit_len] = 0;
		assert(!p.commit_skin_edit(&cfg, true, (String)root, null));
		assert(p.skin_editing);

		String image = "pics/card.png";
		p.skin_edit_len = (int)image.len;
		for (usz i = 0; i < image.len; i++) p.skin_edit_buf[i] = image[i];
		p.skin_edit_buf[p.skin_edit_len] = 0;
		assert(p.commit_skin_edit(&cfg, true, (String)root, null));
		assert(skin::surface(skin::SurfaceId.APP).image.compare_to("pics/card.png") == 0);
		String expected = string::format(tmem, "%s/.yun/pics/card.png", (String)root);
		assert(skin::surface(skin::SurfaceId.APP).path.compare_to(expected) == 0);

		p.destroy();
		cfg.destroy();
		(void)path::rmtree(root);
	};
}

fn void test_skin_image_filter_and_paste()
{
	assert(image_path_supported("card.png"));
	assert(image_path_supported("card.PNG"));
	assert(!image_path_supported("card.txt"));
	assert(!image_path_supported("card"));

	char[SKIN_EDIT_MAX + 1] buf;
	buf[0] = 0;
	int len = skin_paste_text(&buf[0], 0, "  #112233\n");
	assert(len == 7);
	assert(((String)buf[0:len]).compare_to("#112233") == 0);
	assert(buf[len] == 0);

	len = skin_paste_text(&buf[0], len, " #445566\n");
	assert(((String)buf[0:len]).compare_to("#112233#445566") == 0);
	assert(buf[len] == 0);

	char[SKIN_EDIT_MAX + 1] control;
	control[0] = 0;
	int control_len = skin_paste_text(&control[0], 0, "a\tb\nc");
	assert(control_len == 3);
	assert(((String)control[0:control_len]).compare_to("abc") == 0);

	char[600] long_text;
	for (usz i = 0; i < 600; i++) long_text[i] = 'x';
	char[SKIN_EDIT_MAX + 1] limited;
	limited[0] = 0;
	int limited_len = skin_paste_text(&limited[0], 0, (String)long_text[0:600]);
	assert(limited_len == SKIN_EDIT_MAX);
	assert(limited[SKIN_EDIT_MAX] == 0);
}

fn void test_skin_browse_row_opens_picker()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? dir = tmp.append(tmem, "yun_skin_panel_browse_test");
		if (catch excuse = dir) return;
		Path root = dir;
		(void)path::rmtree(root);
		if (catch excuse = path::mkdir(root, recursive: true)) return;
		Path? yun = root.append(tmem, ".yun");
		if (catch excuse = yun) return;
		if (catch excuse = path::mkdir(yun, recursive: true)) return;
		char[] content = { 'x' };
		Path? image    = root.append(tmem, "card.png");
		if (catch excuse = image) return;
		if (catch excuse = file::save(image, content)) return;

		skin::init_headless(tmem);
		config::Config cfg;
		cfg.init(tmem);
		cfg.reset();
		skin::set_base(string::format(tmem, "%s/.yun", (String)root), settings::SettingLayer.PROJECT);
		skin::set_surface_image(skin::SurfaceId.APP, (String)image, settings::SettingLayer.PROJECT);

		Panel p;
		p.init(tmem);
		p.show();
		p.set_page(settings::SettingPage.SKIN);
		p.scope = settings::SettingLayer.PROJECT;
		p.selected = p.skin_row(SkinItem.BROWSE);
		assert(p.selected >= 0);

		p.open_image_picker(true);
		assert(p.image_picker.open);
		assert(p.image_picker.dir.compare_to((String)root) == 0);
		int image_index = -1;
		for (sz i = 0; i < p.image_picker.entries.len(); i++)
		{
			if (p.image_picker.entries[i].path.compare_to((String)image) == 0) image_index = (int)i;
		}
		assert(image_index >= 0);
		p.image_picker.selected = image_index;
		assert(p.image_picker.activate_selected() == image_picker::PickerAction.SELECTED);
		p.accept_image_picker(&cfg, true, (String)root, null);
		assert(skin::surface(skin::SurfaceId.APP).image.compare_to((String)image) == 0);

		skin::set_surface_image(skin::SurfaceId.APP, "", settings::SettingLayer.PROJECT);
		p.open_image_picker(true);
		assert(p.image_picker.open);
		assert(p.image_picker.dir.compare_to((String)yun) == 0);
		p.image_picker.cancel();

		p.destroy();
		cfg.destroy();
		(void)path::rmtree(root);
	};
}

fn void test_skin_page_reload_and_reset_actions()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? dir = tmp.append(tmem, "yun_skin_panel_actions_test");
		if (catch excuse = dir) return;
		Path root = dir;
		(void)path::rmtree(root);
		if (catch excuse = path::mkdir(root, recursive: true)) return;
		Path? yun = root.append(tmem, ".yun");
		if (catch excuse = yun) return;
		if (catch excuse = path::mkdir(yun, recursive: true)) return;
		Path? cfg_path = yun.append(tmem, "config.json");
		if (catch excuse = cfg_path) return;
		if (catch excuse = file::save(
			cfg_path,
			"{\"skin\":{\"preset\":\"glass\",\"surfaces\":{\"card\":{\"image\":\"/tmp/reload-card.png\"}}}}"
		)) return;

		skin::init_headless(tmem);
		config::Config cfg;
		cfg.init(tmem);
		cfg.reset();

		Panel p;
		p.init(tmem);
		p.show();
		p.set_page(settings::SettingPage.SKIN);
		p.scope = settings::SettingLayer.PROJECT;

		p.selected = p.skin_row(SkinItem.RELOAD);
		assert(p.selected >= 0);
		p.change_skin(&cfg, 1, true, (String)root, null);
		assert(skin::preset().compare_to("glass") == 0);
		assert(skin::surface(skin::SurfaceId.CARD).image.compare_to("/tmp/reload-card.png") == 0);

		p.selected = p.skin_row(SkinItem.RESET);
		p.change_skin(&cfg, 1, true, (String)root, null);
		assert(skin::preset_source() != settings::SettingLayer.PROJECT);
		assert(skin::surface_source(skin::SurfaceId.CARD, skin::SurfaceField.IMAGE) != settings::SettingLayer.PROJECT);
		assert(!skin::has_output(settings::SettingLayer.PROJECT));

		p.destroy();
		cfg.destroy();
		(void)path::rmtree(root);
	};
}