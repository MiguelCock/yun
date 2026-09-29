module yun::minimap @test;

import raylib6::rl;
import std::math;
import yun::canvas;
import yun::project;

fn void test_minimap_scale_roundtrip()
{
	Rect content = { .x = -100.0f, .y = -50.0f, .width = 200.0f, .height = 100.0f };
	Rect panel   = { .x = 0.0f, .y = 0.0f, .width = 220.0f, .height = 160.0f };
	assert(minimap_scale(content, panel) > 0.0f);

	RLVector2 world = { 30.0f, 10.0f };
	RLVector2 point = world_to_minimap(world, content, panel);
	RLVector2 back  = minimap_to_world(point, content, panel);
	assert(math::is_approx(back[0], world[0], 0.001f));
	assert(math::is_approx(back[1], world[1], 0.001f));
}

fn void test_minimap_centers_content()
{
	Rect content     = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f };
	Rect panel       = { .x = 0.0f, .y = 0.0f, .width = 200.0f, .height = 200.0f };
	RLVector2 center = world_to_minimap({ 50.0f, 50.0f }, content, panel);
	assert(math::is_approx(center[0], 100.0f, 0.001f));
	assert(math::is_approx(center[1], 100.0f, 0.001f));
}

fn void test_panel_size_scales()
{
	MinimapSettings saved = settings();
	MinimapSettings ms    = saved;
	ms.size = 1.0f;
	set_settings(ms);
	Rect full = minimap_panel(1280, 720);
	assert(full.width == 220.0f && full.height == 160.0f);

	ms.size = 0.5f;
	set_settings(ms);
	Rect half = minimap_panel(1280, 720);
	assert(half.width == 110.0f && half.height == 80.0f);
	set_settings(saved);
}

fn void test_set_settings_clamps()
{
	MinimapSettings saved = settings();
	MinimapSettings ms    = saved;
	ms.size = 10.0f;
	ms.zoom_threshold = -1.0f;
	set_settings(ms);
	MinimapSettings got = settings();
	assert(got.size <= 4.0f);
	assert(got.zoom_threshold >= 0.0f);
	set_settings(saved);
}

fn void test_visible_gates()
{
	MinimapSettings saved = settings();
	MinimapSettings ms    = saved;
	canvas::Canvas c;
	c.camera.zoom = 0.1f;

	ms.enabled = false;
	set_settings(ms);
	assert(!visible(null, &c));

	ms.enabled = true;
	ms.zoom_threshold = 0.4f;
	set_settings(ms);
	c.camera.zoom = 1.0f;
	assert(!visible(null, &c));

	set_settings(saved);
}
fn void test_file_minimap_line_mapping()
{
	Rect panel = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 200.0f };
	assert(file_minimap_line_at(panel, 0.0f, 100) == 0);
	assert(file_minimap_line_at(panel, 100.0f, 100) == 50);
	assert(file_minimap_line_at(panel, 199.9f, 100) == 99);
	assert(file_minimap_line_at(panel, -50.0f, 100) == 0);
	assert(file_minimap_line_at(panel, 500.0f, 100) == 99);
	assert(file_minimap_line_at(panel, 10.0f, 0) == 0);
}

fn void test_file_minimap_band_and_viewport()
{
	Rect panel = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f };
	Rect band  = file_minimap_band(panel, 0, 100);
	assert(band.y == 0.0f);
	assert(band.height >= 1.0f);
	Rect last = file_minimap_band(panel, 99, 100);
	assert(last.y >= 99.0f && last.y < 100.0f);

	Rect vp = file_minimap_viewport(panel, 0, 10, 100);
	assert(vp.y == 0.0f);
	assert(vp.height >= 2.0f && vp.height <= panel.height);
	Rect mid = file_minimap_viewport(panel, 50, 10, 100);
	assert(mid.y >= 49.0f && mid.y <= 51.0f);
}