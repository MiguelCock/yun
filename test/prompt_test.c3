module yun::prompt @test;

fn void test_prompt_editing()
{
	Prompt p;
	p.init();
	p.open_with("New file", "");
	assert(p.open);

	assert(p.append_codepoint('a'));
	assert(p.append_codepoint('b'));
	assert(p.append_codepoint('c'));
	assert(p.text_view().compare_to("abc") == 0);

	p.backspace();
	assert(p.text_view().compare_to("ab") == 0);
	p.backspace();
	p.backspace();
	assert(p.len == 0);
	assert(p.text_view().compare_to("") == 0);

	assert(!p.append_codepoint(0));
	p.close();
	assert(!p.open);
}

fn void test_prompt_backspace_removes_utf8()
{
	Prompt p;
	p.init();
	p.open_with("New file", "");

	assert(p.append_codepoint(0xE9)); // e-acute encodes to 2 bytes
	assert(p.len == 2);
	p.backspace();
	assert(p.len == 0);
}