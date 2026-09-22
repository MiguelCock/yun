module yun;

import raylib6::rl;
import std::io::path;
import std::math;
import yun::browser;
import yun::canvas;
import yun::editor;
import yun::menu;
import yun::minimap;
import yun::notify;
import yun::project;
import yun::prompt;
import yun::workspace;

fn void set_project_title(project::Project* project)
{
	String name  = rl::get_file_name((ZString)project.root.ptr).str_view();
	String title = string::format(project.allocator, "Yun - %s", name);
	rl::set_window_title((ZString)title.ptr);
}

fn bool open_project(project::Project* project, canvas::Canvas* canvas, String root)
{
	if (!project.open(root)) return false;
	workspace::load(project, canvas);
	return true;
}

fn bool open_from_cli(project::Project* project, canvas::Canvas* canvas, notify::Notifier* notifier, String arg)
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
	if (!open_project(project, canvas, resolved))
	{
		notifier.push("Could not open the folder");
		return false;
	}
	set_project_title(project);
	return true;
}

fn bool ctrl_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_CONTROL) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_CONTROL);
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

	project::Project project;
	project.init(mem);

	notify::Notifier notifier;
	notifier.init(mem);

	browser::Browser browser;
	browser.init(mem);

	menu::Menu context_menu;
	context_menu.init(mem);

	menu::Menu reload_menu;
	reload_menu.init(mem);

	prompt::Prompt name_prompt;
	name_prompt.init();

	int pending_kind        = 0;
	int pending_parent      = project::ROOT_FOLDER;
	RLVector2 pending_world = { 0.0f, 0.0f };

	bool project_open = false;
	if (args.len > 1) project_open = open_from_cli(&project, &canvas, &notifier, args[1]);

	while (!rl::window_should_close())
	{
		float dt = math::min(rl::get_frame_time(), canvas::MAX_FRAME_DT);

		if (browser.open)
		{
			if (browser.update())
			{
				if (open_project(&project, &canvas, (String)browser.dir))
				{
					project_open = true;
					set_project_title(&project);
				}
				else
				{
					notifier.push("Could not open the folder");
				}
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
			if (chosen >= 0)
			{
				pending_kind = chosen;
				name_prompt.open_with(chosen == 0 ? "New file" : "New folder", "");
			}
		}
		else
		{
			if (ctrl_down() && rl::is_key_pressed(rl::RLKeyboardKey.O)) browser.open_at((String)project.root);

			if (ctrl_down() && rl::is_key_pressed(rl::RLKeyboardKey.S))
			{
				if (!project_open)
				{
					notifier.push("No project open");
				}
				else if (workspace::save(&project, &canvas))
				{
					notifier.push("Saved workspace");
				}
				else
				{
					notifier.push("Could not save workspace");
				}
			}

			RLVector2 mouse = rl::get_mouse_position();
			RLVector2 world = canvas.screen_to_world(mouse);
			canvas.pointer_over_ui = project.pointer_over_ui(
				world
			) || minimap::contains_screen(&project, &canvas, mouse);
			minimap::update(&project, &canvas);

			if (rl::is_mouse_button_pressed(
				rl::RLMouseButton.RIGHT
			) && project.hit_test(world) < 0 && !minimap::contains_screen(&project, &canvas, mouse))
			{
				pending_parent = project.folder_at(world);
				pending_world = world;
				context_menu.open_at(mouse, { "New file", "New folder" });
			}

			if (rl::is_file_dropped())
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

			project.update(&canvas, metrics);
			canvas.update();

			if (project.pending_reload >= 0 && !reload_menu.open)
			{
				RLVector2 center = {
					(float)rl::get_screen_width() / 2.0f,
					(float)rl::get_screen_height() / 2.0f,
				};
				notifier.push("File changed on disk");
				reload_menu.open_at(center, { "Reload", "Keep" });
			}
		}

		notifier.update(dt);

		rl::@drawing()
		{
			canvas.draw();
			rl::@mode2d(canvas.camera)
			{
				project.draw(canvas.camera, font, metrics);
			};
			minimap::draw(&project, &canvas);
			browser.draw();
			reload_menu.draw();
			context_menu.draw();
			name_prompt.draw();
			notifier.draw();
			rl::draw_fps(10, 10);
		};
	}

	if (project_open) workspace::save(&project, &canvas);
	return 0;
}