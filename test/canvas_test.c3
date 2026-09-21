module yun::canvas @test;

import raylib6::rl;
import std::math;

fn void test_grid_step_is_pow2_multiple()
{
	float[5] zooms = { 0.05f, 0.25f, 1.0f, 3.0f, 8.0f };
	foreach (float zoom : zooms)
	{
		float ratio = grid_step(zoom) / BASE_CELL;
		while (ratio >= 2.0f) ratio *= 0.5f;
		while (ratio < 1.0f) ratio *= 2.0f;
		assert(ratio == 1.0f);
	}
}

fn void test_grid_step_keeps_spacing_in_range()
{
	float[6] zooms = { 0.05f, 0.1f, 0.5f, 1.0f, 2.0f, 8.0f };
	foreach (float zoom : zooms)
	{
		float px = grid_step(zoom) * zoom;
		assert(px >= MIN_GRID_PX && px <= MAX_GRID_PX);
	}
}

fn void test_grid_step_shrinks_as_zoom_grows()
{
	assert(grid_step(4.0f) <= grid_step(1.0f));
	assert(grid_step(1.0f) <= grid_step(0.25f));
}

fn void test_pan_target_is_zoom_scaled()
{
	Canvas c;
	c.camera.zoom = 1.0f;
	c.pan_by({ 10.0f, 0.0f });
	assert(c.camera.target[0] == -10.0f);

	c.camera.zoom = 0.5f;
	c.camera.target = { 0.0f, 0.0f };
	c.pan_by({ 10.0f, 0.0f });
	assert(c.camera.target[0] == -20.0f);

	c.camera.zoom = 2.0f;
	c.camera.target = { 0.0f, 0.0f };
	c.pan_by({ 10.0f, 0.0f });
	assert(c.camera.target[0] == -5.0f);
}

fn void test_pan_keeps_grabbed_world_point_under_cursor()
{
	Canvas c;
	c.camera = {
		.offset = { 400.0f, 300.0f },
		.target = { 0.0f, 0.0f },
		.rotation = 0.0f,
		.zoom = 2.0f,
	};
	RLVector2 mouse0 = { 100.0f, 100.0f };
	RLVector2 world0 = c.screen_to_world(mouse0);
	RLVector2 delta  = { 13.0f, -7.0f };
	c.pan_by(delta);
	RLVector2 mouse1 = { mouse0[0] + delta[0], mouse0[1] + delta[1] };
	RLVector2 world1 = c.screen_to_world(mouse1);
	assert(math::is_approx(world0[0], world1[0], 0.001f));
	assert(math::is_approx(world0[1], world1[1], 0.001f));
}

fn void test_clamp_delta_caps_magnitude()
{
	Canvas c;
	RLVector2 large = c.clamp_delta({ 1000.0f, 0.0f });
	assert(math::is_approx(large[0], MAX_PAN_DELTA_PX, 0.001f));
	assert(large[1] == 0.0f);

	RLVector2 small = c.clamp_delta({ 1.0f, 2.0f });
	assert(small[0] == 1.0f && small[1] == 2.0f);
}