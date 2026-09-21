module yun::minimap @test;

import raylib6::rl;
import std::math;

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