module yun::completion @test;

import yun::lsp;
import yun::text;

fn void test_prefix_start()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "foo bar");
		assert(prefix_start(&t, 7) == 4);
		assert(prefix_start(&t, 3) == 0);
		t.destroy();
	};
}

fn void test_refilter_and_accept()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "int x = pri");
		History h;
		h.init(tmem);

		Completion c;
		c.init(tmem);

		lsp::CompletionItem a = {
			.label = "print".copy(tmem),
			.filter_text = "print".copy(tmem),
			.sort_text = "print".copy(tmem),
			.insert_text = "print".copy(tmem),
		};
		lsp::CompletionItem b = {
			.label = "printf".copy(tmem),
			.filter_text = "printf".copy(tmem),
			.sort_text = "printf".copy(tmem),
			.insert_text = "printf".copy(tmem),
		};
		c.items.push(a);
		c.items.push(b);

		c.start = 8;
		c.refilter(&t, 11);
		assert(c.order.len() >= 2);

		// Deterministic accept: pick the first item directly.
		c.open = true;
		c.order.clear();
		c.scores.clear();
		c.order.push(0);
		c.scores.push(0);
		c.selected = 0;

		usz cursor = c.accept(&t, &h, 11, 1.0);
		assert(cursor == 13);
		assert(t.slice(0, t.length(), tmem).compare_to("int x = print") == 0);
		assert(!c.open);

		usz undo_cursor = cursor;
		assert(h.undo(&t, &undo_cursor));
		assert(t.slice(0, t.length(), tmem).compare_to("int x = pri") == 0);

		c.clear_items();
		c.items.free();
		c.order.free();
		c.scores.free();
		c.free_prefix();
		h.free();
		t.destroy();
	};
}