module yun::git @test;

import std::collections::list;

fn void test_conflict_parse_and_resolve()
{
	String content = "before\n"
		"<<<<<<< HEAD\n"
		"ours 1\n"
		"||||||| base\n"
		"base 1\n"
		"=======\n"
		"theirs 1\n"
		">>>>>>> feature\n"
		"middle\n"
		"<<<<<<< HEAD\n"
		"ours 2\n"
		"=======\n"
		"theirs 2\n"
		">>>>>>> feature\n"
		"after\n";
	List{ConflictBlock} blocks;
	blocks.init(mem);
	defer
	{
		for (sz i = 0; i < blocks.len(); i++) blocks[i].destroy(mem);
		blocks.free();
	}
	assert(parse_conflicts(mem, content, &blocks));
	assert(blocks.len() == 2);
	assert(blocks[0].ours.compare_to("ours 1\n") == 0);
	assert(blocks[0].base.compare_to("base 1\n") == 0);
	assert(blocks[0].theirs.compare_to("theirs 1\n") == 0);
	assert(blocks[0].ours_label.compare_to("HEAD") == 0);
	assert(blocks[0].theirs_label.compare_to("feature") == 0);

	List{ConflictChoice} choices;
	choices.init(mem);
	defer choices.free();
	choices.push(ConflictChoice.CURRENT);
	choices.push(ConflictChoice.INCOMING);
	String resolved = "";
	assert(resolve_conflicts(mem, content, &blocks, &choices, &resolved));
	defer resolved.free(mem);
	assert(resolved.contains("before\nours 1\nmiddle\ntheirs 2\nafter\n"));
	assert(!resolved.contains("<<<<<<<"));

	choices.set(0, ConflictChoice.BOTH);
	choices.set(1, ConflictChoice.BOTH);
	String both = "";
	assert(resolve_conflicts(mem, content, &blocks, &choices, &both));
	defer both.free(mem);
	assert(both.contains("ours 1\ntheirs 1\n"));
	assert(both.contains("ours 2\ntheirs 2\n"));
}

fn void test_conflict_unset_is_rejected()
{
	String content = "<<<<<<< HEAD\nours\n=======\ntheirs\n>>>>>>> other\n";
	List{ConflictBlock} blocks;
	blocks.init(mem);
	defer
	{
		for (sz i = 0; i < blocks.len(); i++) blocks[i].destroy(mem);
		blocks.free();
	}
	assert(parse_conflicts(mem, content, &blocks));
	List{ConflictChoice} choices;
	choices.init(mem);
	defer choices.free();
	choices.push(ConflictChoice.UNSET);
	String resolved = "";
	assert(!resolve_conflicts(mem, content, &blocks, &choices, &resolved));
	assert(resolved.len == 0);
}

fn void test_conflict_no_markers()
{
	List{ConflictBlock} blocks;
	blocks.init(mem);
	defer blocks.free();
	assert(!parse_conflicts(mem, "module test;\n", &blocks));
}