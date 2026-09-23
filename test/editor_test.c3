module yun::editor @test;

import raylib6::rl;
import std::io::file;
import std::io::path;
import std::math;
import yun::card;
import yun::lsp;
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

		usz off = offset_for_point(&t, x_for_column(1, metrics), line_y(1, 0.0f, metrics), 0.0f, 0.0f, metrics);
		assert(off == t.line_start(1) + 1);

		usz clamped = offset_for_point(&t, x_for_column(50, metrics), line_y(1, 0.0f, metrics), 0.0f, 0.0f, metrics);
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

fn void test_cursor_navigation()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "ab\ncde");
		assert(cursor_prev(&t, 0) == 0);
		assert(cursor_next(&t, 0) == 1);
		assert(cursor_next(&t, 2) == 3);
		assert(cursor_home(&t, 5) == 3);
		assert(cursor_end(&t, 0) == 2);
		assert(cursor_end(&t, 3) == 6);

		usz column = 0;
		assert(cursor_up(&t, 5, 5, &column) == 2);
		assert(column == 2);
		assert(cursor_down(&t, 0, 0, &column) == 3);
		assert(column == 0);
		t.destroy();
	};
}

fn void test_insert_backspace_delete()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "ab\ncde");

		usz cursor = insert_text(&t, 2, "X");
		assert(cursor == 3);
		assert(t.slice(0, t.length(), tmem).compare_to("abX\ncde") == 0);

		cursor = backspace(&t, cursor);
		assert(cursor == 2);
		assert(t.slice(0, t.length(), tmem).compare_to("ab\ncde") == 0);

		cursor = delete_forward(&t, 2);
		assert(cursor == 2);
		assert(t.slice(0, t.length(), tmem).compare_to("abcde") == 0);
		t.destroy();
	};
}

fn void test_utf8_and_cursor()
{
	@pool()
	{
		char[4] encoded;
		int count = utf8_encode(0xE9, &encoded[0]);
		assert(count == 2);
		assert((int)encoded[0] == 0xC3 && (int)encoded[1] == 0xA9);

		PieceTable t;
		t.init_from_buffer(tmem, "aé b");
		assert(t.length() == 5);
		usz cursor = insert_text(&t, 3, (String)encoded[0:count]);
		assert(t.length() == 7);
		cursor = backspace(&t, cursor);
		assert(t.length() == 5);
		assert(t.slice(0, t.length(), tmem).compare_to("aé b") == 0);
		t.destroy();
	};
}

fn void test_caret_rect_and_scroll()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "ab\ncdef");
		EditorMetrics metrics = { .char_width = 8.0f, .line_height = 16.0f, .padding_x = 0.0f, .padding_y = 0.0f };
		Rect area             = { .x = 10.0f, .y = 20.0f, .width = 100.0f, .height = 50.0f };

		usz cursor = 5;
		Rect caret = caret_rect(&t, area, 0.0f, 0.0f, metrics, cursor);
		assert(caret.x == 26.0f && caret.y == 36.0f);
		assert(caret.height == 16.0f);
		t.destroy();
	};
}

fn void test_scroll_to_reveal()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n10\n11\n12\n13\n14\n15\n16\n17\n18\n19");
		EditorMetrics metrics = { .char_width = 8.0f, .line_height = 16.0f, .padding_x = 0.0f, .padding_y = 0.0f };
		usz cursor            = t.line_start(10);
		// one line of scroll margin keeps context below the cursor (92 = 176 - 100 + 16)
		assert(scroll_to_reveal(&t, metrics, 100.0f, cursor, 0.0f) == 92.0f);
		assert(scroll_to_reveal(&t, metrics, 100.0f, cursor, 76.0f) == 92.0f);
		assert(scroll_to_reveal(&t, metrics, 100.0f, 0, 100.0f) == 0.0f);
		t.destroy();
	};
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
fn void test_gutter_and_text_rects()
{
	EditorMetrics metrics = { .char_width = 8.0f, .line_height = 16.0f, .padding_x = 8.0f, .padding_y = 6.0f };
	Rect card             = { .x = 10.0f, .y = 20.0f, .width = 240.0f, .height = 160.0f };
	Rect gutter           = gutter_rect(card, metrics, 9);
	Rect text             = text_rect(card, metrics, 9);
	assert(gutter.x == 18.0f && gutter.y == 54.0f);
	assert(gutter.width == 24.0f);
	assert(text.x == 42.0f);
	assert(text.width == 200.0f);
	assert(gutter_rect(card, metrics, 100).width == 40.0f);
}

fn void test_current_line_rect()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "a\nb\nc");
		EditorMetrics metrics = { .char_width = 8.0f, .line_height = 16.0f, .padding_x = 0.0f, .padding_y = 0.0f };
		Rect area             = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f };

		Rect r1 = current_line_rect(&t, area, 0.0f, metrics, t.line_start(1));
		assert(r1.y == 16.0f && r1.height == 16.0f);
		Rect r2 = current_line_rect(&t, area, 10.0f, metrics, t.line_start(2));
		assert(r2.y == 22.0f);
		t.destroy();
	};
}

fn void test_scrollbar_thumb()
{
	Rect area = { .x = 0.0f, .y = 0.0f, .width = 100.0f, .height = 100.0f };
	Rect full = scrollbar_thumb(area, 50.0f, 0.0f);
	assert(full.height == 100.0f && full.x == 96.0f);

	Rect top = scrollbar_thumb(area, 400.0f, 0.0f);
	assert(top.height == 25.0f && top.y == 0.0f);

	Rect bottom = scrollbar_thumb(area, 400.0f, 300.0f);
	assert(bottom.y == 75.0f);
}
fn void test_file_changed()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_ext_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "f.txt");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "abc")) return;

		FileCard card = { .path = (Path)((String)f).copy(tmem) };
		stamp_file(&card);
		assert(!card.missing);
		assert(!file_changed(&card));

		if (catch excuse = file::save(f, "abcdef")) return;
		assert(file_changed(&card));

		stamp_file(&card);
		assert(!file_changed(&card));

		(void)path::rmtree(dir);
	};
}

fn void test_reload_buffer()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_reload_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "g.txt");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "abc")) return;

		FileCard card = { .path = (Path)((String)f).copy(tmem) };
		ensure_buffer(&card, tmem);
		assert(card.buffer.length() == 3);

		usz cursor = card.history.insert(card.buffer, 3, "X", 1.0);
		assert(cursor == 4 && card.buffer.length() == 4);
		card.dirty = true;
		card.cursor = 4;

		reload_buffer(&card, tmem);
		assert(card.buffer.length() == 3);
		assert(line_text(card.buffer, 0, tmem).compare_to("abc") == 0);
		assert(card.history.commands.len() == 0);
		assert(!card.dirty);
		assert(card.cursor == 0);

		(void)path::rmtree(dir);
	};
}
fn void test_min_card_size()
{
	EditorMetrics metrics = { .char_width = 8.0f, .line_height = 16.0f, .padding_x = 8.0f, .padding_y = 6.0f };
	assert(min_card_width(metrics) == 704.0f);
	assert(min_card_height(metrics) == 520.0f);
}

fn void test_resize_handle_at()
{
	RLCamera2D camera = { .offset = { 0.0f, 0.0f }, .target = { 0.0f, 0.0f }, .rotation = 0.0f, .zoom = 1.0f };
	FileCard card     = { .rect = { .x = 0.0f, .y = 0.0f, .width = 200.0f, .height = 100.0f }, .open = true };
	assert(card.resize_handle_at({ 0.0f, 0.0f }, camera) == 0);
	assert(card.resize_handle_at({ 200.0f, 50.0f }, camera) == 3);
	assert(card.resize_handle_at({ 100.0f, 100.0f }, camera) == 5);
	assert(card.resize_handle_at({ 100.0f, 50.0f }, camera) == -1);
	assert(card.resize_handle_at({ 300.0f, 300.0f }, camera) == -1);

	card.open = false;
	assert(card.resize_handle_at({ 0.0f, 0.0f }, camera) == -1);
}

fn void test_resize_from()
{
	FileCard card = { .rect = { .x = 100.0f, .y = 100.0f, .width = 400.0f, .height = 300.0f }, .open = true };
	float min_w   = 200.0f;
	float min_h   = 150.0f;

	card.resize_from(3, { 50.0f, 0.0f }, min_w, min_h);
	assert(card.rect.x == 100.0f && card.rect.width == 450.0f);

	card.resize_from(7, { 50.0f, 0.0f }, min_w, min_h);
	assert(card.rect.x == 150.0f && card.rect.width == 400.0f);

	card.resize_from(5, { 0.0f, 50.0f }, min_w, min_h);
	assert(card.rect.y == 100.0f && card.rect.height == 350.0f);

	card.resize_from(1, { 0.0f, 50.0f }, min_w, min_h);
	assert(card.rect.y == 150.0f && card.rect.height == 300.0f);

	card.resize_from(7, { 10000.0f, 0.0f }, min_w, min_h);
	assert(card.rect.width == min_w);
}
fn void test_close_marker_hit()
{
	FileCard card = { .rect = { .x = 0.0f, .y = 0.0f, .width = 240.0f, .height = 160.0f }, .open = true };
	assert(card.close_marker_hit({ 210.0f, 10.0f }));
	assert(!card.close_marker_hit({ 225.0f, 10.0f }));
	assert(card.marker_hit({ 225.0f, 10.0f }));
	assert(!card.close_marker_hit({ 100.0f, 10.0f }));
}

fn void test_unload_buffer()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_close_test");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "h.txt");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "abc")) return;

		FileCard card = { .path = (Path)((String)f).copy(tmem) };
		ensure_buffer(&card, tmem);
		card.dirty = true;
		assert(!unload_buffer(&card, tmem));
		assert(card.buffer != null);

		card.dirty = false;
		assert(unload_buffer(&card, tmem));
		assert(card.buffer == null && card.history == null);
		assert(card.cursor == 0 && card.scroll == 0.0f);

		ensure_buffer(&card, tmem);
		assert(card.buffer != null);
		assert(line_text(card.buffer, 0, tmem).compare_to("abc") == 0);

		(void)path::rmtree(dir);
	};
}
fn void test_save_buffer()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_save_buffer");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "s.txt");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "one")) return;

		FileCard card = { .path = (Path)((String)f).copy(tmem) };
		ensure_buffer(&card, tmem);
		card.buffer.insert(card.buffer.length(), " two");
		card.dirty = true;
		assert(save_buffer(&card, tmem));
		assert(card.dirty == false);

		PieceTable check;
		assert(check.init_from_file(tmem, (String)f));
		assert(check.slice(0, check.length(), tmem).compare_to("one two") == 0);
		check.destroy();

		FileCard empty;
		assert(!save_buffer(&empty, tmem));

		(void)path::rmtree(dir);
	};
}
fn void test_destroy_buffer()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_destroy_buffer");
		if (catch excuse = d) return;
		Path dir = d;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? f = dir.append(tmem, "d.txt");
		if (catch excuse = f) return;
		if (catch excuse = file::save(f, "abc")) return;

		FileCard card = { .path = (Path)((String)f).copy(tmem) };
		ensure_buffer(&card, tmem);
		card.dirty = true;
		assert(card.buffer != null && card.history != null);

		destroy_buffer(&card, tmem);
		assert(card.buffer == null && card.history == null);
		assert(card.dirty == false && card.cursor == 0 && card.scroll == 0.0f);

		(void)path::rmtree(dir);
	};
}
fn void test_match_rect()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "hello\nworld");
		EditorMetrics metrics = { .char_width = 8.0f, .line_height = 20.0f, .padding_x = 8.0f, .padding_y = 6.0f };
		Rect area             = { .x = 100.0f, .y = 50.0f, .width = 400.0f, .height = 200.0f };

		Rect r = match_rect(&t, area, 0.0f, 0.0f, metrics, 0, 5);
		assert(r.x == 100.0f);
		assert(r.y == 50.0f);
		assert(r.width == 40.0f);

		Rect second = match_rect(&t, area, 0.0f, 0.0f, metrics, 6, 11);
		assert(second.x == 100.0f);
		assert(second.y == 70.0f);
		assert(second.width == 40.0f);
		t.destroy();
	};
}

fn void test_selection_range()
{
	usz start = 9;
	usz end   = 9;

	selection_range(2, 5, &start, &end);
	assert(start == 2 && end == 5);

	selection_range(5, 2, &start, &end);
	assert(start == 2 && end == 5);

	selection_range(4, 4, &start, &end);
	assert(start == 4 && end == 4);

	assert(has_selection(1, 3));
	assert(!has_selection(3, 3));
}

fn void test_cursor_page()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "a\nb\nc\nd\ne");

		usz column = 0;
		usz offset = cursor_page(&t, 0, 2, 0, &column);
		assert(offset == 4);
		assert(column == 0);

		offset = cursor_page(&t, 4, -2, 0, &column);
		assert(offset == 0);

		offset = cursor_page(&t, 0, 50, 0, &column);
		assert(offset == 8);

		offset = cursor_page(&t, 8, -50, 0, &column);
		assert(offset == 0);
		t.destroy();
	};
}

fn void test_word_range()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "hello world");

		usz start = 0;
		usz end   = 0;
		word_range(&t, 2, &start, &end);
		assert(start == 0 && end == 5);

		word_range(&t, 7, &start, &end);
		assert(start == 6 && end == 11);

		word_range(&t, 11, &start, &end);
		assert(start == 6 && end == 11);

		PieceTable empty;
		empty.init_from_buffer(tmem, "");
		word_range(&empty, 0, &start, &end);
		assert(start == 0 && end == 0);
		empty.destroy();
		t.destroy();
	};
}

fn void test_scroll_x_to_reveal()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abcdefghij");
		EditorMetrics metrics = { .char_width = 8.0f, .line_height = 16.0f, .padding_x = 0.0f, .padding_y = 0.0f };

		assert(scroll_x_to_reveal(&t, metrics, 40.0f, 0, 0.0f) == 0.0f);
		assert(scroll_x_to_reveal(&t, metrics, 40.0f, 9, 0.0f) == 72.0f);
		t.destroy();
	};
}

fn void test_selection_rect_for_line()
{
	EditorMetrics metrics = { .char_width = 8.0f, .line_height = 20.0f, .padding_x = 0.0f, .padding_y = 0.0f };
	Rect area             = { .x = 100.0f, .y = 50.0f, .width = 400.0f, .height = 200.0f };

	Rect r = selection_rect_for_line(1, 4, 2, area, 0.0f, 0.0f, metrics);
	assert(r.x == 108.0f && r.width == 24.0f);
	assert(r.y == 90.0f && r.height == 20.0f);

	Rect scrolled = selection_rect_for_line(0, 0, 0, area, 0.0f, 10.0f, metrics);
	assert(scrolled.x == 90.0f);
	assert(scrolled.width == metrics.char_width);
}

fn void test_region_at()
{
	EditorMetrics metrics = { .char_width = 8.0f, .line_height = 16.0f, .padding_x = 8.0f, .padding_y = 6.0f };
	RLCamera2D camera     = { .offset = { 0.0f, 0.0f }, .target = { 0.0f, 0.0f }, .rotation = 0.0f, .zoom = 1.0f };
	FileCard card         = { .rect = { .x = 0.0f, .y = 0.0f, .width = 240.0f, .height = 160.0f }, .open = true };

	assert(region_at(&card, { 100.0f, 10.0f }, metrics, camera) == CardRegion.TITLE);
	assert(region_at(&card, { 100.0f, 80.0f }, metrics, camera) == CardRegion.BODY);
	assert(region_at(&card, { 230.0f, 10.0f }, metrics, camera) == CardRegion.MARKER);
	assert(region_at(&card, { 205.0f, 10.0f }, metrics, camera) == CardRegion.CLOSE);
	assert(region_at(&card, { 5.0f, 5.0f }, metrics, camera) == CardRegion.HANDLE);
	assert(region_at(&card, { 400.0f, 400.0f }, metrics, camera) == CardRegion.NONE);

	card.open = false;
	assert(region_at(&card, { 100.0f, 80.0f }, metrics, camera) == CardRegion.NONE);
	assert(region_at(&card, { 100.0f, 10.0f }, metrics, camera) == CardRegion.TITLE);
}
fn void test_diagnostic_offsets()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "abc\ndef");

		usz start = 0;
		usz end   = 0;

		lsp::LspDiagnostic single = {
			.start_line = 0,
			.start_character = 1,
			.end_line = 0,
			.end_character = 3,
		};
		diagnostic_offsets(&t, single, &start, &end);
		assert(start == 1 && end == 3);

		lsp::LspDiagnostic multiline = {
			.start_line = 0,
			.start_character = 2,
			.end_line = 1,
			.end_character = 1,
		};
		diagnostic_offsets(&t, multiline, &start, &end);
		assert(start == 2 && end == 5);

		lsp::LspDiagnostic reversed = {
			.start_line = 1,
			.start_character = 2,
			.end_line = 0,
			.end_character = 1,
		};
		diagnostic_offsets(&t, reversed, &start, &end);
		assert(start == end);

		t.destroy();
	};
}