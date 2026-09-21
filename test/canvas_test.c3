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
	c.target.zoom = 1.0f;
	c.pan_by({ 10.0f, 0.0f });
	assert(c.target.target[0] == -10.0f);

	c.target.zoom = 0.5f;
	c.target.target = { 0.0f, 0.0f };
	c.pan_by({ 10.0f, 0.0f });
	assert(c.target.target[0] == -20.0f);

	c.target.zoom = 2.0f;
	c.target.target = { 0.0f, 0.0f };
	c.pan_by({ 10.0f, 0.0f });
	assert(c.target.target[0] == -5.0f);
}

fn void test_pan_keeps_grabbed_world_point_under_cursor()
{
	Canvas c;
	c.target = {
		.offset = { 400.0f, 300.0f },
		.target = { 0.0f, 0.0f },
		.rotation = 0.0f,
		.zoom = 2.0f,
	};
	RLVector2 mouse0 = { 100.0f, 100.0f };
	RLVector2 world0 = screen_to_world_camera(c.target, mouse0);
	RLVector2 delta  = { 13.0f, -7.0f };
	c.pan_by(delta);
	RLVector2 mouse1 = { mouse0[0] + delta[0], mouse0[1] + delta[1] };
	RLVector2 world1 = screen_to_world_camera(c.target, mouse1);
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

fn void test_zoom_preserves_world_point_under_cursor()
{
	Canvas c;
	c.camera = {
		.offset = { 400.0f, 300.0f },
		.target = { 0.0f, 0.0f },
		.rotation = 0.0f,
		.zoom = 1.0f,
	};
	c.target = c.camera;
	RLVector2 anchor = { 120.0f, 90.0f };
	RLVector2 before = screen_to_world_camera(c.target, anchor);
	c.zoom_at(1.0f, anchor);
	RLVector2 after = screen_to_world_camera(c.target, anchor);
	assert(math::is_approx(before[0], after[0], 0.001f));
	assert(math::is_approx(before[1], after[1], 0.001f));
}

fn void test_zoom_is_geometric()
{
	Canvas c;
	c.camera.offset = { 400.0f, 300.0f };
	c.camera.target = { 0.0f, 0.0f };
	c.camera.zoom = 1.0f;
	c.target = c.camera;
	c.zoom_at(1.0f, { 400.0f, 300.0f });
	assert(math::is_approx(c.target.zoom, ZOOM_STEP, 0.0001f));
	c.zoom_at(2.0f, { 400.0f, 300.0f });
	assert(math::is_approx(c.target.zoom, ZOOM_STEP * ZOOM_STEP * ZOOM_STEP, 0.0001f));
}

fn void test_zoom_clamps()
{
	Canvas c;
	c.camera.offset = { 400.0f, 300.0f };
	c.camera.target = { 0.0f, 0.0f };
	c.camera.zoom = 1.0f;
	c.target = c.camera;
	for (int i = 0; i < 100; i++)
	{
		c.zoom_at(10.0f, { 400.0f, 300.0f });
	}
	assert(c.target.zoom == MAX_ZOOM);
	for (int i = 0; i < 100; i++)
	{
		c.zoom_at(-10.0f, { 400.0f, 300.0f });
	}
	assert(c.target.zoom == MIN_ZOOM);
}

fn void test_zoom_at_zero_is_noop()
{
	Canvas c;
	c.target.offset = { 400.0f, 300.0f };
	c.target.target = { 5.0f, -3.0f };
	c.target.zoom = 2.0f;
	c.zoom_at(0.0f, { 10.0f, 10.0f });
	assert(c.target.target[0] == 5.0f && c.target.target[1] == -3.0f);
	assert(c.target.zoom == 2.0f);
}

fn void test_zoom_anchor_targets_rendered_cursor_point()
{
	Canvas c;
	c.target.offset = { 400.0f, 300.0f };
	c.target.target = { 12.0f, -8.0f };
	c.target.zoom = 1.0f;
	c.camera = c.target;
	RLVector2 anchor = { 250.0f, 180.0f };
	RLVector2 world  = screen_to_world_camera(c.camera, anchor);
	c.zoom_at(3.0f, anchor);
	RLVector2 end = screen_to_world_camera(c.target, anchor);
	assert(math::is_approx(world[0], end[0], 0.001f));
	assert(math::is_approx(world[1], end[1], 0.001f));
}

fn void test_ease_factor_is_frame_rate_independent()
{
	float t60 = ease_factor(PAN_RESPONSIVENESS, 1.0f / 60.0f);
	float t30 = ease_factor(PAN_RESPONSIVENESS, 1.0f / 30.0f);
	assert(math::is_approx((1.0f - t60) * (1.0f - t60), 1.0f - t30, 0.001f));
	assert(t60 > 0.0f && t60 < 1.0f);
}

fn void test_ease_camera_converges()
{
	Canvas c;
	c.target.target = { 100.0f, -50.0f };
	c.target.zoom = 2.0f;
	c.camera.target = { 0.0f, 0.0f };
	c.camera.zoom = 1.0f;
	for (int i = 0; i < 240; i++)
	{
		c.ease_camera(1.0f / 60.0f);
	}
	assert(math::is_approx(c.camera.target[0], 100.0f, 0.1f));
	assert(math::is_approx(c.camera.target[1], -50.0f, 0.1f));
	assert(math::is_approx(c.camera.zoom, 2.0f, 0.001f));
}

fn void test_inertia_decays_to_stop()
{
	Canvas c;
	c.target.zoom = 1.0f;
	c.target.target = { 0.0f, 0.0f };
	c.velocity = { 600.0f, 0.0f };
	for (int i = 0; i < 600; i++)
	{
		c.apply_inertia(1.0f / 60.0f);
	}
	assert(c.velocity[0] == 0.0f && c.velocity[1] == 0.0f);
	assert(c.target.target[0] < 0.0f);
}