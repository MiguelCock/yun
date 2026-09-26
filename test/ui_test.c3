module yun::ui @test;

import raylib6::rl;

fn void test_scale_and_px()
{
	set_font((RLFont) { }, 16);
	assert(scale() == 1.0f);
	assert(px(20) == 20);
	assert(pxf(20.0f) == 20.0f);

	set_font((RLFont) { }, 24);
	assert(scale() == 1.5f);
	assert(px(20) == 30);
	assert(pxf(20.0f) == 30.0f);
	assert(size() == 24);

	set_font((RLFont) { }, 0);
	assert(scale() == 1.0f);
	assert(size() == 16);
}