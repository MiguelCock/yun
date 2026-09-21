module yun::editor @test;

import yun::text;

fn void test_visible_lines()
{
	VisibleRange r = visible_lines(100, 0.0f, 160.0f, 16.0f);
	assert(r.first == 0);
	assert(r.last == 11);

	VisibleRange scrolled = visible_lines(100, 160.0f, 160.0f, 16.0f);
	assert(scrolled.first == 10);
	assert(scrolled.last == 21);

	VisibleRange clamped = visible_lines(5, 0.0f, 160.0f, 16.0f);
	assert(clamped.first == 0);
	assert(clamped.last == 5);

	VisibleRange empty = visible_lines(0, 0.0f, 160.0f, 16.0f);
	assert(empty.first == 0 && empty.last == 0);
}

fn void test_line_text_and_length()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "ab\ncde\nf");
		assert(t.line_count() == 3);
		assert(line_length_bytes(&t, 0) == 2);
		assert(line_length_bytes(&t, 1) == 3);
		assert(line_length_bytes(&t, 2) == 1);
		assert(line_text(&t, 1, tmem).compare_to("cde") == 0);
		t.destroy();
	};
}

fn void test_columns_and_points()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "aé\nxy");
		EditorMetrics metrics = { .char_width = 10.0f, .line_height = 20.0f, .padding_x = 5.0f, .padding_y = 5.0f };

		usz end0 = t.line_start(0) + line_length_bytes(&t, 0);
		assert(column_for_offset(&t, 0, end0) == 2);
		assert(x_for_column(2, metrics) == 25.0f);

		usz off = offset_for_point(&t, x_for_column(1, metrics), line_y(1, 0.0f, metrics), 0.0f, metrics);
		assert(off == t.line_start(1) + 1);

		usz clamped = offset_for_point(&t, x_for_column(50, metrics), line_y(1, 0.0f, metrics), 0.0f, metrics);
		assert(clamped == t.line_start(1) + line_length_bytes(&t, 1));
		t.destroy();
	};
}

fn void test_gutter_and_content_width()
{
	EditorMetrics metrics = { .char_width = 8.0f, .line_height = 16.0f, .padding_x = 4.0f, .padding_y = 4.0f };
	assert(gutter_width(9, metrics) == 16.0f);
	assert(gutter_width(10, metrics) == 24.0f);
	assert(gutter_width(100, metrics) == 32.0f);

	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "ab\ncdef");
		VisibleRange range = { .first = 0, .last = 2 };
		assert(max_line_columns(&t, range) == 4);
		assert(content_width(&t, range, metrics) == 36.0f);
		t.destroy();
	};
}