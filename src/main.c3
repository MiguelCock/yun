module yun;

import raylib6::rl;
import std::math;
import yun::canvas;
import yun::notify;
import yun::project;

fn int main()
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

	while (!rl::window_should_close())
	{
		float dt        = math::min(rl::get_frame_time(), canvas::MAX_FRAME_DT);
		RLVector2 mouse = rl::get_mouse_position();
		RLVector2 world = canvas.screen_to_world(mouse);

		canvas.pointer_over_ui = project.pointer_over_ui(world);

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
		notifier.update(dt);

		rl::@drawing()
		{
			canvas.draw();
			rl::@mode2d(canvas.camera)
			{
				project.draw();
			};
			notifier.draw();
			rl::draw_fps(10, 10);
		};
	}
	return 0;
}