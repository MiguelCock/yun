module yun;

import raylib6::rl;
import std::io::path;
import std::math;
import yun::browser;
import yun::canvas;
import yun::minimap;
import yun::notify;
import yun::project;

fn void set_project_title(project::Project* project)
{
	String name  = rl::get_file_name((ZString)project.root.ptr).str_view();
	String title = string::format(project.allocator, "Yun - %s", name);
	rl::set_window_title((ZString)title.ptr);
}

fn void open_from_cli(project::Project* project, notify::Notifier* notifier, String arg)
{
	String? resolved = project::resolve_path(project.allocator, arg);
	if (catch excuse = resolved)
	{
		notifier.push("Could not resolve the given path");
		return;
	}
	if (!path::is_dir((Path)resolved))
	{
		notifier.push("Not a directory");
		return;
	}
	if (!project.open(resolved))
	{
		notifier.push("Could not open the folder");
		return;
	}
	set_project_title(project);
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

	canvas::Canvas canvas;
	canvas.init();

	project::Project project;
	project.init(mem);

	notify::Notifier notifier;
	notifier.init(mem);

	browser::Browser browser;
	browser.init(mem);

	if (args.len > 1) open_from_cli(&project, &notifier, args[1]);

	while (!rl::window_should_close())
	{
		float dt = math::min(rl::get_frame_time(), canvas::MAX_FRAME_DT);

		if (browser.open)
		{
			if (browser.update())
			{
				if (project.open((String)browser.dir))
				{
					set_project_title(&project);
				}
				else
				{
					notifier.push("Could not open the folder");
				}
			}
		}
		else
		{
			if (ctrl_down() && rl::is_key_pressed(rl::RLKeyboardKey.O)) browser.open_at((String)project.root);

			RLVector2 mouse = rl::get_mouse_position();
			RLVector2 world = canvas.screen_to_world(mouse);
			canvas.pointer_over_ui = project.pointer_over_ui(
				world
			) || minimap::contains_screen(&project, &canvas, mouse);
			minimap::update(&project, &canvas);

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

			canvas.update();
			project.update(&canvas);
		}

		notifier.update(dt);

		rl::@drawing()
		{
			canvas.draw();
			rl::@mode2d(canvas.camera)
			{
				project.draw();
			};
			minimap::draw(&project, &canvas);
			browser.draw();
			notifier.draw();
			rl::draw_fps(10, 10);
		};
	}
	return 0;
}