module yun::editor @test;

import raylib6::rl;
import std::io::file;
import std::io::path;
import std::math;
import yun::card;
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

fn void test_inner_rect()
{
	EditorMetrics metrics = { .char_width = 8.0f, .line_height = 16.0f, .padding_x = 8.0f, .padding_y = 6.0f };
	Rect card             = { .x = 10.0f, .y = 20.0f, .width = 240.0f, .height = 160.0f };
	Rect inner            = inner_rect(card, metrics);
	assert(inner.x == 18.0f);
	assert(inner.y == 54.0f);
	assert(inner.width == 224.0f);
	assert(inner.height == 120.0f);
}

fn void test_placeholder_bar_width()
{
	assert(placeholder_bar_width(0, 400.0f, 8.0f) == 256.0f);
	assert(placeholder_bar_width(1, 400.0f, 8.0f) == 160.0f);
	assert(placeholder_bar_width(3, 400.0f, 8.0f) == 96.0f);
	assert(placeholder_bar_width(0, 100.0f, 8.0f) == 96.0f);
	assert(placeholder_bar_width(0, 8.0f, 8.0f) == 8.0f);
}

fn void test_ensure_buffer()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_editor_buffer_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "x.txt");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "hello")) return;

		FileCard card = { .path = (Path)((String)f).copy(tmem) };
		ensure_buffer(&card, tmem);
		assert(card.buffer != null);
		assert(card.buffer.length() == 5);
		assert(line_text(card.buffer, 0, tmem).compare_to("hello") == 0);

		PieceTable* first = card.buffer;
		ensure_buffer(&card, tmem);
		assert(card.buffer == first);

		(void)path::rmtree(dir);
	};
}

fn void test_world_rect_to_screen()
{
	RLCamera2D camera = { .offset = { 0.0f, 0.0f }, .target = { 0.0f, 0.0f }, .rotation = 0.0f, .zoom = 1.0f };
	Rect area         = { .x = 10.0f, .y = 20.0f, .width = 100.0f, .height = 50.0f };
	Rect screen       = world_rect_to_screen(area, camera);
	assert(math::is_approx(screen.x, 10.0f, 0.001f));
	assert(math::is_approx(screen.y, 20.0f, 0.001f));
	assert(math::is_approx(screen.width, 100.0f, 0.001f));
	assert(math::is_approx(screen.height, 50.0f, 0.001f));

	RLCamera2D shifted_camera = {
		.offset = { 100.0f, 100.0f },
		.target = { 0.0f, 0.0f },
		.rotation = 0.0f,
		.zoom = 1.0f,
	};
	Rect shifted = world_rect_to_screen(area, shifted_camera);
	assert(math::is_approx(shifted.x, 110.0f, 0.001f));
	assert(math::is_approx(shifted.y, 120.0f, 0.001f));
}

fn void test_max_scroll()
{
	EditorMetrics metrics = { .char_width = 8.0f, .line_height = 16.0f, .padding_x = 8.0f, .padding_y = 6.0f };
	assert(max_scroll(10, metrics, 100.0f) == 72.0f);
	assert(max_scroll(1, metrics, 200.0f) == 0.0f);
}

fn void test_effective_rect_and_marker()
{
	FileCard card = { .rect = { .x = 0.0f, .y = 0.0f, .width = 240.0f, .height = 160.0f }, .open = true };
	assert(card.effective_rect().height == 160.0f);
	assert(card.marker_hit({ 230.0f, 10.0f }));

	card.open = false;
	assert(card.effective_rect().height == 28.0f);
	assert(!card.contains({ 50.0f, 100.0f }));
	assert(card.contains({ 50.0f, 10.0f }));
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