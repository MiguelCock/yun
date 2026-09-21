module yun;

import raylib6::rl;
import yun::canvas;

fn int main()
{
	rl::set_config_flags((RLConfigFlag)(rl::RLConfigFlag.WINDOW_RESIZABLE | rl::RLConfigFlag.VSYNC_HINT));
	rl::init_window(1280, 720, "Yun");
	defer rl::close_window();
	rl::set_target_fps(60);

	canvas::Canvas canvas;
	canvas.init();

	while (!rl::window_should_close())
	{
		canvas.update();
		rl::@drawing()
		{
			canvas.draw();
			rl::draw_fps(10, 10);
		};
	}
	return 0;
}