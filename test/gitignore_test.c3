module yun::gitignore @test;

fn void test_glob_match()
{
	assert(glob_match("*.c3", "main.c3"));
	assert(!glob_match("*.c3", "main.c"));
	assert(glob_match("a?c", "abc"));
	assert(!glob_match("a?c", "ac"));
	assert(glob_match("a/*/c", "a/b/c"));
	assert(!glob_match("a/*/c", "a/b/d/c"));
	assert(glob_match("a/**/c", "a/b/d/c"));
	assert(glob_match("**/foo", "a/b/foo"));
}

fn void test_name_rule()
{
	@pool()
	{
		Gitignore g;
		g.init(tmem);
		g.add_line("/root", "env");
		assert(g.is_ignored("/root/env", true));
		assert(g.is_ignored("/root/a/b/env", true));
		assert(!g.is_ignored("/root/environment", true));
		g.free();
	};
}

fn void test_dir_only()
{
	@pool()
	{
		Gitignore g;
		g.init(tmem);
		g.add_line("/root", "build/");
		assert(g.is_ignored("/root/build", true));
		assert(!g.is_ignored("/root/build", false));
		g.free();
	};
}

fn void test_anchored()
{
	@pool()
	{
		Gitignore g;
		g.init(tmem);
		g.add_line("/root", "/env");
		assert(g.is_ignored("/root/env", true));
		assert(!g.is_ignored("/root/a/env", true));
		g.free();
	};
}

fn void test_suffix()
{
	@pool()
	{
		Gitignore g;
		g.init(tmem);
		g.add_line("/root", "*.pyc");
		assert(g.is_ignored("/root/a/b.pyc", false));
		assert(!g.is_ignored("/root/a/b.py", false));
		g.free();
	};
}

fn void test_glob_star_star()
{
	@pool()
	{
		Gitignore g;
		g.init(tmem);
		g.add_line("/root", "**/gen");
		assert(g.is_ignored("/root/a/b/gen", true));
		assert(g.is_ignored("/root/gen", true));
		g.free();
	};
}

fn void test_negation()
{
	@pool()
	{
		Gitignore g;
		g.init(tmem);
		g.add_line("/root", "*.log");
		g.add_line("/root", "!keep.log");
		assert(g.is_ignored("/root/a.log", false));
		assert(!g.is_ignored("/root/keep.log", false));
		g.free();
	};
}

fn void test_base_scoping_and_nesting()
{
	@pool()
	{
		Gitignore g;
		g.init(tmem);
		g.add_line("/root/a", "env");
		assert(g.is_ignored("/root/a/env", true));
		assert(!g.is_ignored("/root/env", true));

		g.add_line("/root", "sub");
		g.add_line("/root/sub", "!keep.txt");
		assert(g.is_ignored("/root/sub", true));
		assert(!g.is_ignored("/root/sub/keep.txt", false));
		g.free();
	};
}