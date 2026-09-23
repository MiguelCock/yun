module yun;

import raylib6::rl;
import std::io::path;
import std::math;
import yun::browser;
import yun::canvas;
import yun::commands;
import yun::config;
import yun::context;
import yun::editor;
import yun::find;
import yun::findbar;
import yun::keymap;
import yun::menu;
import yun::minimap;
import yun::notify;
import yun::palette;
import yun::project;
import yun::prompt;
import yun::topbar;
import yun::workspace;

fn void set_project_title(project::Project* project)
{
	String name  = rl::get_file_name((ZString)project.root.ptr).str_view();
	String title = string::format(project.allocator, "Yun - %s", name);
	rl::set_window_title((ZString)title.ptr);
}

fn bool open_project(project::Project* project, canvas::Canvas* canvas, config::Config* config, String root)
{
	if (!project.open(root)) return false;
	workspace::load(project, canvas);
	config.load((String)project.root);
	return true;
}

fn bool open_from_cli(
	project::Project* project,
	canvas::Canvas* canvas,
	config::Config* config,
	notify::Notifier* notifier,
	String arg
)
{
	String? resolved = project::resolve_path(project.allocator, arg);
	if (catch excuse = resolved)
	{
		notifier.push("Could not resolve the given path");
		return false;
	}
	if (!path::is_dir((Path)resolved))
	{
		notifier.push("Not a directory");
		return false;
	}
	if (!open_project(project, canvas, config, resolved))
	{
		notifier.push("Could not open the folder");
		return false;
	}
	set_project_title(project);
	return true;
}

fn void push_config_warnings(config::Config* config, notify::Notifier* notifier)
{
	for (sz i = 0; i < config.warnings.len(); i++)
	{
		notifier.push(config.warnings[i]);
	}
}

fn void push_keymap_warnings(keymap::Keymap* keymap, notify::Notifier* notifier)
{
	for (sz i = 0; i < keymap.warnings.len(); i++)
	{
		notifier.push(keymap.warnings[i]);
	}
}

struct App
{
	project::Project* project;
	canvas::Canvas* canvas;
	browser::Browser* browser;
	notify::Notifier* notifier;
	prompt::Prompt* name_prompt;
	palette::Palette* palette;
	findbar::FindBar* find_bar;
	editor::EditorMetrics metrics;
	bool* project_open;
	int* pending_kind;
	int* pending_parent;
	RLVector2* pending_world;
}

fn bool has_focused_buffer(project::Project* project)
{
	int index = project.focused;
	return index >= 0 && index < (int)project.cards.len() && project.cards[index].buffer != null;
}

fn void run_command(commands::CommandId id, App* app)
{
	project::Project* project = app.project;
	switch (id)
	{
		case commands::CommandId.NEW_FILE:

			{
				if (!*app.project_open)
				{
					app.notifier.push("No project open");
					return;
				}
				RLVector2 center = {
					(float)rl::get_screen_width() / 2.0f,
					(float)rl::get_screen_height() / 2.0f,
				};
				RLVector2 world = app.canvas.screen_to_world(center);
				*app.pending_kind = 0;
				*app.pending_parent = project.folder_at(world);
				*app.pending_world = world;
				app.name_prompt.open_with("New file", "");
				return;
			}
		case commands::CommandId.NEW_FOLDER:

			{
				if (!*app.project_open)
				{
					app.notifier.push("No project open");
					return;
				}
				RLVector2 center = {
					(float)rl::get_screen_width() / 2.0f,
					(float)rl::get_screen_height() / 2.0f,
				};
				RLVector2 world = app.canvas.screen_to_world(center);
				*app.pending_kind = 1;
				*app.pending_parent = project.folder_at(world);
				*app.pending_world = world;
				app.name_prompt.open_with("New folder", "");
				return;
			}
		case commands::CommandId.OPEN:

			{
				app.browser.open_at((String)project.root);
				return;
			}
		case commands::CommandId.SAVE:

			{
				if (!*app.project_open)
				{
					app.notifier.push("No project open");
					return;
				}
				int index = project.focused;
				if (index < 0 || index >= (int)project.cards.len() || !project.cards[index].buffer)
				{
					app.notifier.push("No file to save");
					return;
				}
				if (editor::save_buffer(&project.cards[index], project.allocator))
				{
					app.notifier.push("Saved");
				}
				else
				{
					app.notifier.push("Could not save");
				}
				return;
			}
		case commands::CommandId.SHOW_PALETTE:

			{
				app.palette.show();
				while (rl::get_char_pressed() != 0)
				{
				}
				return;
			}
		case commands::CommandId.FIND:
		case commands::CommandId.REPLACE:

			{
				int index = project.focused;
				if (!*app.project_open || index < 0 || index >= (int)project.cards.len()
					|| !project.cards[index].buffer)
				{
					app.notifier.push("No file to search");
					return;
				}
				find::FindField field = id == commands::CommandId.REPLACE ? find::FindField.REPLACE
					: find::FindField.QUERY;
				app.find_bar.open_for(field);
				while (rl::get_char_pressed() != 0)
				{
				}
				return;
			}
		case commands::CommandId.COPY:

			{
				if (project.copy_selection())
				{
					app.notifier.push("Copied");
				}
				return;
			}
		case commands::CommandId.CUT:

			{
				if (project.cut_selection(rl::get_time()))
				{
					mark_buffer_changed(project, app.find_bar, app.metrics);
				}
				return;
			}
		case commands::CommandId.PASTE:

			{
				if (project.paste_clipboard(rl::get_time()))
				{
					mark_buffer_changed(project, app.find_bar, app.metrics);
				}
				return;
			}
		case commands::CommandId.SELECT_ALL:

			{
				project.select_all();
				project.reveal_focused(app.metrics);
				return;
			}
	}
}

fn void mark_buffer_changed(project::Project* project, findbar::FindBar* find_bar, editor::EditorMetrics metrics)
{
	FileCard* card = project.focused_card();
	if (!card) return;
	card.dirty = true;
	if (card.highlight) card.highlight.mark_dirty();
	project.reveal_focused(metrics);
	find_bar.mark_dirty();
}

fn int main(String[] args)
{
	rl::set_config_flags((RLConfigFlag)(rl::RLConfigFlag.WINDOW_RESIZABLE | rl::RLConfigFlag.VSYNC_HINT));
	rl::init_window(1280, 720, "Yun");
	defer rl::close_window();
	rl::set_target_fps(60);
	rl::set_exit_key(rl::RLKeyboardKey.NONE);

	RLFont font = rl::load_font_ex("assets/fonts/JetBrainsMono-Regular.ttf", 16, null, 0);
	defer rl::unload_font(font);
	editor::EditorMetrics metrics = editor::metrics_for_font(font, 16.0f);

	canvas::Canvas canvas;
	canvas.init();
	canvas.top_inset = topbar::TOP_BAR_HEIGHT;

	project::Project project;
	project.init(mem);

	notify::Notifier notifier;
	notifier.init(mem);

	config::Config config;
	config.init(mem);
	defer config.destroy();

	browser::Browser browser;
	browser.init(mem);

	menu::Menu context_menu;
	context_menu.init(mem);

	menu::Menu reload_menu;
	reload_menu.init(mem);

	menu::Menu close_menu;
	close_menu.init(mem);

	menu::Menu delete_menu;
	delete_menu.init(mem);

	prompt::Prompt name_prompt;
	name_prompt.init();

	topbar::TopBar bar;
	bar.init();

	palette::Palette palette;
	palette.init(mem);

	findbar::FindBar find_bar;
	find_bar.init(mem);

	keymap::Keymap keymap;
	keymap.init(mem);
	defer keymap.destroy();

	int pending_kind        = 0;
	int pending_parent      = project::ROOT_FOLDER;
	RLVector2 pending_world = { 0.0f, 0.0f };

	context::ContextItem[context::CONTEXT_MAX_ITEMS] context_items;
	usz context_item_count  =  0;
	int context_card        = -1;
	int context_parent      =  project::ROOT_FOLDER;
	RLVector2 context_world =  { 0.0f, 0.0f };
	int pending_rename_card = -1;
	int pending_delete_card = -1;

	bool project_open = false;
	if (args.len > 1)
	{
		project_open = open_from_cli(&project, &canvas, &config, &notifier, args[1]);
	}
	else
	{
		config.load("");
	}
	keymap.build(&config);
	push_config_warnings(&config, &notifier);
	push_keymap_warnings(&keymap, &notifier);

	App app = {
		.project = &project,
		.canvas = &canvas,
		.browser = &browser,
		.notifier = &notifier,
		.name_prompt = &name_prompt,
		.palette = &palette,
		.find_bar = &find_bar,
		.metrics = metrics,
		.project_open = &project_open,
		.pending_kind = &pending_kind,
		.pending_parent = &pending_parent,
		.pending_world = &pending_world,
	};

	while (!rl::window_should_close())
	{
		float dt = math::min(rl::get_frame_time(), canvas::MAX_FRAME_DT);

		if (browser.open)
		{
			if (browser.update())
			{
				if (open_project(&project, &canvas, &config, (String)browser.dir))
				{
					project_open = true;
					set_project_title(&project);
					keymap.build(&config);
					push_config_warnings(&config, &notifier);
					push_keymap_warnings(&keymap, &notifier);
				}
				else
				{
					notifier.push("Could not open the folder");
				}
			}
		}
		else if (palette.open)
		{
			int chosen = palette.update(project_open, has_focused_buffer(&project));
			if (chosen >= 0)
			{
				palette.record((commands::CommandId)chosen);
				run_command((commands::CommandId)chosen, &app);
			}
		}
		else if (name_prompt.open)
		{
			if (name_prompt.update())
			{
				String name = name_prompt.text_view();
				if (!project::is_valid_name(name))
				{
					notifier.push("Invalid name");
				}
				else if (pending_kind == 2)
				{
					if (project.rename_card(pending_rename_card, name))
					{
						name_prompt.close();
					}
					else
					{
						notifier.push("Could not rename");
					}
				}
				else
				{
					int result = pending_kind == 0 ? project.create_file(pending_parent, name, pending_world)
						: project.create_folder_on_disk(pending_parent, name, pending_world);
					if (result < 0)
					{
						notifier.push("Could not create");
					}
					else
					{
						name_prompt.close();
					}
				}
			}
		}
		else if (close_menu.open)
		{
			int chosen = close_menu.update();
			if (chosen >= 0)
			{
				int index = project.pending_close;
				if (chosen == 0 && index >= 0 && index < (int)project.cards.len())
				{
					(void)editor::unload_buffer(&project.cards[index], project.allocator);
				}
				project.pending_close = -1;
			}
		}
		else if (delete_menu.open)
		{
			int chosen = delete_menu.update();
			if (chosen >= 0)
			{
				if (chosen == 0 && pending_delete_card >= 0 && pending_delete_card < (int)project.cards.len())
				{
					if (project.delete_card_file(pending_delete_card))
					{
						notifier.push("Deleted");
					}
					else
					{
						notifier.push("Could not delete");
					}
				}
				pending_delete_card = -1;
			}
		}
		else if (reload_menu.open)
		{
			int chosen = reload_menu.update();
			if (chosen >= 0)
			{
				int index = project.pending_reload;
				if (index >= 0 && index < (int)project.cards.len())
				{
					if (chosen == 0)
					{
						editor::reload_buffer(&project.cards[index], project.allocator);
					}
					else
					{
						editor::stamp_file(&project.cards[index]);
					}
				}
				project.pending_reload = -1;
			}
		}
		else if (context_menu.open)
		{
			int chosen = context_menu.update();
			if (chosen >= 0 && chosen < (int)context_item_count)
			{
				context::ContextAction action = context_items[chosen].action;
				switch (action)
				{
					case context::ContextAction.NEW_FILE:
					case context::ContextAction.NEW_FOLDER:

						{
							pending_kind = action == context::ContextAction.NEW_FILE ? 0 : 1;
							pending_parent = context_parent;
							pending_world = context_world;
							name_prompt.open_with(pending_kind == 0 ? "New file" : "New folder", "");
							break;
						}
					case context::ContextAction.OPEN_PROJECT:
						run_command(commands::CommandId.OPEN, &app);
						break;
					case context::ContextAction.TOGGLE_CARD:

						{
							if (context_card >= 0 && context_card < (int)project.cards.len())
							{
								project.cards[context_card].open = !project.cards[context_card].open;
							}
							break;
						}
					case context::ContextAction.RENAME_CARD:

						{
							if (context_card >= 0 && context_card < (int)project.cards.len())
							{
								pending_rename_card = context_card;
								pending_kind = 2;
								name_prompt.open_with("Rename", project.cards[context_card].name);
							}
							break;
						}
					case context::ContextAction.DUPLICATE_CARD:

						{
							if (project.duplicate_card(context_card, context_world) < 0)
							{
								notifier.push("Could not duplicate");
							}
							else
							{
								notifier.push("Duplicated");
							}
							break;
						}
					case context::ContextAction.COPY_PATH:

						{
							if (context_card >= 0 && context_card < (int)project.cards.len())
							{
								@pool()
								{
									rl::set_clipboard_text(((String)project.cards[context_card].path).zstr_tcopy());
								};
								notifier.push("Path copied");
							}
							break;
						}
					case context::ContextAction.DELETE_CARD:

						{
							if (context_card >= 0 && context_card < (int)project.cards.len())
							{
								pending_delete_card = context_card;
								RLVector2 center = {
									(float)rl::get_screen_width() / 2.0f,
									(float)rl::get_screen_height() / 2.0f,
								};
								delete_menu.open_at(center, { "Delete", "Cancel" });
							}
							break;
						}
				}
			}
		}
		else if (find_bar.open)
		{
			int focus = project.focused;
			if (focus < 0 || focus >= (int)project.cards.len() || !project.cards[focus].buffer)
			{
				find_bar.close();
			}
			else
			{
				usz reveal    = 0;
				bool replaced = false;
				int result = find_bar.update(
					project.cards[focus].buffer,
					project.cards[focus].history,
					false,
					&reveal,
					&replaced
				);
				if (result >= 0)
				{
					FileCard* card = &project.cards[focus];
					Rect text      = editor::text_rect(card.rect, metrics, card.buffer.line_count());
					if (result > 0)
					{
						card.scroll = editor::scroll_to_reveal(card.buffer, metrics, text.height, reveal, card.scroll);
						card.scroll_x = editor::scroll_x_to_reveal(
							card.buffer,
							metrics,
							text.width,
							reveal,
							card.scroll_x
						);
					}
					if (replaced) card.dirty = true;
				}
			}
		}
		else
		{
			RLVector2 mouse = rl::get_mouse_position();
			RLVector2 world = canvas.screen_to_world(mouse);
			bool over_top   = topbar::contains_screen(mouse);
			bool has_buffer = has_focused_buffer(&project);

			int key_cmd = keymap.poll();
			if (key_cmd >= 0) run_command((commands::CommandId)key_cmd, &app);

			int bar_cmd = bar.update(mouse, project_open, has_buffer);
			if (bar_cmd >= 0) run_command((commands::CommandId)bar_cmd, &app);

			canvas.pointer_over_ui = over_top || project.pointer_over_ui(
				world
			) || minimap::contains_screen(&project, &canvas, mouse);
			minimap::update(&project, &canvas);

			if (!over_top && rl::is_mouse_button_pressed(
				rl::RLMouseButton.RIGHT
			) && !minimap::contains_screen(&project, &canvas, mouse))
			{
				int card   = project.hit_test(world);
				int folder = project.cluster_hit(world);
				context_card = card;
				context_parent = folder;
				context_world = world;

				context::ContextTarget target = context::ContextTarget.CANVAS;
				if (card >= 0)
				{
					target = context::ContextTarget.CARD;
				}
				else if (folder >= 0)
				{
					target = context::ContextTarget.CLUSTER;
				}

				bool card_open    = card >= 0 && project.cards[card].open;
				bool card_missing = card >= 0 && project.cards[card].missing;
				context_item_count = context::build(
					target,
					card_open,
					card_missing,
					project_open,
					context_items[0:context::CONTEXT_MAX_ITEMS]
				);

				String[context::CONTEXT_MAX_ITEMS] labels;
				bool[context::CONTEXT_MAX_ITEMS] enabled;
				for (usz i = 0; i < context_item_count; i++)
				{
					labels[i] = context_items[i].label;
					enabled[i] = context_items[i].enabled;
				}
				context_menu.open_with(mouse, labels[0:context_item_count], enabled[0:context_item_count]);
			}

			if (!over_top && rl::is_file_dropped())
			{
				RLFilePathList files = rl::load_dropped_files();
				for (uint i = 0; i < files.count; i++)
				{
					String path = files.paths[i].str_view().copy(mem);
					if (!rl::is_path_file(files.paths[i]))
					{
						if (project.add_folder_from_disk(path, world) < 0)
						{
							notifier.push("Drop folders from inside the project root");
						}
						continue;
					}
					if (project.add_card(path, world) < 0)
					{
						notifier.push("Could not add dropped file");
					}
				}
				rl::unload_dropped_files(files);
			}

			bool content_changed = false;
			project.update(&canvas, metrics, over_top, &content_changed);
			if (over_top) canvas.block_zoom = true;
			canvas.update();
			if (content_changed) find_bar.mark_dirty();

			if (project.pending_reload >= 0 && !reload_menu.open)
			{
				RLVector2 center = {
					(float)rl::get_screen_width() / 2.0f,
					(float)rl::get_screen_height() / 2.0f,
				};
				notifier.push("File changed on disk");
				reload_menu.open_at(center, { "Reload", "Keep" });
			}
			if (project.pending_close >= 0 && !close_menu.open)
			{
				RLVector2 center = {
					(float)rl::get_screen_width() / 2.0f,
					(float)rl::get_screen_height() / 2.0f,
				};
				notifier.push("Unsaved changes");
				close_menu.open_at(center, { "Discard", "Keep" });
			}
		}

		notifier.update(dt);

		rl::@drawing()
		{
			canvas.draw();
			rl::@mode2d(canvas.camera)
			{
				project.draw(canvas.camera, font, metrics, &find_bar);
			};
			minimap::draw(&project, &canvas);
			String project_name = "";
			if (project_open) project_name = rl::get_file_name((ZString)project.root.ptr).str_view();
			bar.draw(project_open, has_focused_buffer(&project), project_name, canvas.camera.zoom, font);
			browser.draw();
			close_menu.draw();
			delete_menu.draw();
			reload_menu.draw();
			context_menu.draw();
			name_prompt.draw();
			palette.draw(project_open, has_focused_buffer(&project), &keymap, font);
			notifier.draw();
			rl::draw_fps(10, (int)topbar::TOP_BAR_HEIGHT + 10);
		};
	}

	if (project_open) workspace::save(&project, &canvas);
	return 0;
}