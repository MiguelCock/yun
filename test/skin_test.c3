module yun::skin @test;
import raylib6::rl;

fn void test_surface_names()
{
	assert(surface_from_name("app") == (int)SurfaceId.APP);
	assert(surface_from_name("card") == (int)SurfaceId.CARD);
	assert(surface_from_name("folder_title") == (int)SurfaceId.FOLDER_TITLE);
	assert(surface_from_name("focus_backdrop") == (int)SurfaceId.FOCUS_BACKDROP);
	assert(surface_from_name("nope") == -1);
}

fn void test_parse_color()
{
	RLColor c = parse_color("#112233", { 0, 0, 0, 0 });
	assert(c[0] == 0x11 && c[1] == 0x22 && c[2] == 0x33 && c[3] == 255);
	RLColor a = parse_color("#11223344", { 0, 0, 0, 0 });
	assert(a[3] == 0x44);
	RLColor fallback = { 1, 2, 3, 4 };
	RLColor bad      = parse_color("nope", fallback);
	assert(bad[0] == 1 && bad[3] == 4);
}