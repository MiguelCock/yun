module yun::input @test;

fn void test_repeat_state()
{
	RepeatState state;
	state.start(1, 10.0);
	assert(state.dir == 1);
	assert(state.tick(1, 10.1) == 0);
	assert(state.tick(1, 10.29) == 0);
	assert(state.tick(1, 10.31) == 1);
	assert(state.tick(1, 10.35) == 0);
	assert(state.tick(1, 10.40) == 1);

	assert(state.tick(2, 10.5) == 0);
	assert(state.tick(2, 10.81) == 2);

	state.reset();
	assert(state.dir == 0);
	assert(state.tick(1, 20.0) == 0);
	assert(state.tick(1, 20.31) == 1);

	state.start(1, 30.0);
	assert(state.tick(1, 30.29) == 0);
	state.reset();
}

fn void test_word_class()
{
	assert(word_class(' ') == WordClass.SPACE);
	assert(word_class('\t') == WordClass.SPACE);
	assert(word_class('a') == WordClass.WORD);
	assert(word_class('Z') == WordClass.WORD);
	assert(word_class('0') == WordClass.WORD);
	assert(word_class('_') == WordClass.WORD);
	assert(word_class('(') == WordClass.PUNCT);
	assert(word_class((char)0xC3) == WordClass.WORD);
}