module yun::fonts @test;

fn void test_monospace_filter()
{
	assert(is_monospace_name("JetBrainsMono-Regular.ttf"));
	assert(is_monospace_name("FiraCode-Bold.otf"));
	assert(is_monospace_name("DejaVuSansMono.ttf"));
	assert(is_monospace_name("Consolas.ttf"));
	assert(!is_monospace_name("Arial.ttf"));
	assert(!is_monospace_name("Times New Roman.ttf"));
}

fn void test_font_filter_constant()
{
	assert(FONT_FILTER.compare_to(".ttf;.otf") == 0);
}

fn void test_strip_extension()
{
	@pool()
	{
		assert(strip_extension(tmem, "FiraCode-Regular.ttf").compare_to("FiraCode-Regular") == 0);
		assert(strip_extension(tmem, "DejaVuSansMono.otf").compare_to("DejaVuSansMono") == 0);
		assert(strip_extension(tmem, "NoExtension").compare_to("NoExtension") == 0);
	};
}