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