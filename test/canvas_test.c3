module yun::canvas @test;

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