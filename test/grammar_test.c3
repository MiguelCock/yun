module yun::grammar @test;

fn void test_missing_library_falls_back()
{
	LoadedGrammar loaded = load("tree-sitter-nonexistent", "tree_sitter_nonexistent");
	assert(loaded.handle == null);
	assert(loaded.language == null);
}

fn void test_missing_symbol_falls_back()
{
	LoadedGrammar loaded = load("tree-sitter-c", "tree_sitter_not_a_symbol");
	assert(loaded.handle == null);
	assert(loaded.language == null);
}

fn void test_existing_library_loads()
{
	LoadedGrammar loaded = load("tree-sitter-c", "tree_sitter_c");
	assert(loaded.handle != null);
	assert(loaded.language != null);
}