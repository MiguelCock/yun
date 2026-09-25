module yun::findbar @test;

import yun::find;
import yun::text;

fn void test_query_editing()
{
	@pool()
	{
		FindBar b;
		b.init(tmem);
		b.open_for(find::FindField.QUERY);
		assert(b.open);

		assert(b.append_codepoint('a'));
		assert(b.append_codepoint('b'));
		assert(b.query_view().compare_to("ab") == 0);
		b.backspace();
		assert(b.query_view().compare_to("a") == 0);

		b.cycle_field();
		assert(b.field == find::FindField.REPLACE);
		assert(b.append_codepoint('x'));
		assert(b.replace_view().compare_to("x") == 0);
		assert(b.query_view().compare_to("a") == 0);
		b.cycle_field();
		assert(b.field == find::FindField.QUERY);
		b.close();
		assert(!b.open);
	};
}

fn void test_navigation_wrap()
{
	@pool()
	{
		FindBar b;
		b.init(tmem);
		assert(!b.move_next());
		assert(!b.move_prev());
	};
}

fn void test_research_and_navigation()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "aXbXcX");

		FindBar b;
		b.init(tmem);
		b.open_for(find::FindField.QUERY);
		b.append_codepoint('X');
		b.research(&t);

		assert(b.total == 3);
		assert(b.current == 0);
		assert(b.current_start() == 1);

		assert(b.move_next());
		assert(b.current == 1 && b.current_start() == 3);
		assert(b.move_next());
		assert(b.current == 2 && b.current_start() == 5);
		assert(b.move_next());
		assert(b.current == 0 && b.current_start() == 1);
		assert(b.move_prev());
		assert(b.current == 2 && b.current_start() == 5);

		b.close();
		t.destroy();
	};
}