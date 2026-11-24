module yun::card @test;

import std::math::geometry;

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
fn void test_snap_resize_rect()
{
	Rect r    = { .x = 10.0f, .y = 20.0f, .width = 100.0f, .height = 80.0f };
	Rect left = snap_resize_rect(r, 0, 16.0f, 10.0f, 10.0f);
	assert(left.x == 16.0f && left.y == 16.0f);
	assert(left.width == 94.0f && left.height == 84.0f);

	Rect right = snap_resize_rect(r, 4, 16.0f, 10.0f, 10.0f);
	assert(right.width == 102.0f && right.height == 76.0f);

	Rect small   = { .x = 0.0f, .y = 0.0f, .width = 10.0f, .height = 10.0f };
	Rect clamped = snap_resize_rect(small, 4, 16.0f, 20.0f, 20.0f);
	assert(clamped.width >= 20.0f && clamped.height >= 20.0f);
}