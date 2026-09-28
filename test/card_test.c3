module yun::card @test;

fn void test_screen_thickness_constant()
{
	// world thickness scales with 1/zoom, so the on-screen thickness stays constant
	assert(screen_thickness(2.0f, 1.0f) == 2.0f);
	assert(screen_thickness(2.0f, 2.0f) == 1.0f);
	assert(screen_thickness(2.0f, 0.5f) == 4.0f);
	// guards: non-positive zoom, and a floor for extreme zoom-in
	assert(screen_thickness(2.0f, 0.0f) == 2.0f);
	assert(screen_thickness(2.0f, 1e9f) >= 0.01f);
}