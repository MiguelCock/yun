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

fn void test_prompt_buffer_is_terminated()
{
	Prompt p;
	p.init();
	p.open_with("New file", "");

	p.append_codepoint('a');
	p.append_codepoint('b');
	p.append_codepoint('c');
	assert(p.text[3] == 0);

	p.backspace();
	assert(p.len == 2);
	assert(p.text[2] == 0);
	assert(p.text_view().compare_to("ab") == 0);

	p.append_codepoint('d');
	assert(p.text_view().compare_to("abd") == 0);
	assert(p.text[3] == 0);
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