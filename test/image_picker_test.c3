module yun::image_picker @test;

import raylib6::rl;
import std::io::file;
import std::io::path;
import std::math;

fn void test_image_filtering()
{
	assert(image_path_supported("photo.png"));
	assert(image_path_supported("photo.PNG"));
	assert(image_path_supported("photo.jpg"));
	assert(image_path_supported("photo.jpeg"));
	assert(image_path_supported("photo.jfif"));
	assert(image_path_supported("anim.gif"));
	assert(image_path_supported("icon.bmp"));
	assert(image_path_supported("/tmp/deep/folder/photo.png"));
	assert(!image_path_supported("photo.webp"));
	assert(!image_path_supported("notes.txt"));
	assert(!image_path_supported("archive.png.txt"));
	assert(!image_path_supported("noext"));
}

fn void test_image_picker_scan_and_order()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_image_picker_test");
		if (catch excuse = d) return;
		Path root = d;
		(void)path::rmtree(root);
		if (catch excuse = path::mkdir(root, recursive: true)) return;

		Path? pics = root.append(tmem, "pics");
		if (catch excuse = pics) return;
		if (catch excuse = path::mkdir(pics)) return;
		Path? alpha = root.append(tmem, "alpha");
		if (catch excuse = alpha) return;
		if (catch excuse = path::mkdir(alpha)) return;

		char[] content = { 'x' };
		Path? png      = root.append(tmem, "b.png");
		if (catch excuse = png) return;
		if (catch excuse = file::save(png, content)) return;
		Path? gif = root.append(tmem, "a.GIF");
		if (catch excuse = gif) return;
		if (catch excuse = file::save(gif, content)) return;
		Path? txt = root.append(tmem, "note.txt");
		if (catch excuse = txt) return;
		if (catch excuse = file::save(txt, content)) return;

		ImagePicker picker;
		picker.init(tmem);
		assert(picker.open_at((String)root));
		assert(picker.open);
		assert(picker.entries.len() == 5);
		assert(picker.entries[0].parent);
		assert(file_name(picker.entries[1].path).compare_to("alpha") == 0);
		assert(picker.entries[1].dir);
		assert(file_name(picker.entries[2].path).compare_to("pics") == 0);
		assert(picker.entries[2].dir);
		assert(file_name(picker.entries[3].path).compare_to("a.GIF") == 0);
		assert(!picker.entries[3].dir);
		assert(file_name(picker.entries[4].path).compare_to("b.png") == 0);
		assert(!picker.entries[4].dir);

		picker.destroy();
		(void)path::rmtree(root);
	};
}

fn void test_image_picker_navigation()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_image_picker_nav_test");
		if (catch excuse = d) return;
		Path root = d;
		(void)path::rmtree(root);
		if (catch excuse = path::mkdir(root, recursive: true)) return;

		Path? sub = root.append(tmem, "sub");
		if (catch excuse = sub) return;
		if (catch excuse = path::mkdir(sub)) return;
		char[] content = { 'x' };
		Path? png      = root.append(tmem, "photo.png");
		if (catch excuse = png) return;
		if (catch excuse = file::save(png, content)) return;

		ImagePicker picker;
		picker.init(tmem);
		assert(picker.open_at((String)root));
		assert(picker.selected == 1);
		assert(file_name(picker.selected_path()).compare_to("sub") == 0);

		picker.move_selection(1);
		assert(picker.selected == 2);
		picker.move_selection(100);
		assert(picker.selected == 2);
		picker.move_selection(-100);
		assert(picker.selected == 0);
		assert(picker.selected_parent());
		picker.move_selection(1);
		assert(picker.selected == 1);

		assert(picker.activate_selected() == PickerAction.NONE);
		assert(file_name(picker.dir).compare_to("sub") == 0);
		assert(picker.entries.len() == 1);
		assert(picker.entries[0].parent);
		assert(picker.selected == 0);

		assert(picker.navigate_parent());
		assert(picker.dir.compare_to((String)root) == 0);
		assert(picker.entries.len() == 3);
		assert(file_name(picker.selected_path()).compare_to("sub") == 0);

		picker.destroy();
		(void)path::rmtree(root);
	};
}

fn void test_image_picker_selection_and_cancel()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_image_picker_select_test");
		if (catch excuse = d) return;
		Path root = d;
		(void)path::rmtree(root);
		if (catch excuse = path::mkdir(root, recursive: true)) return;

		char[] content = { 'x' };
		Path? png      = root.append(tmem, "photo.png");
		if (catch excuse = png) return;
		if (catch excuse = file::save(png, content)) return;
		Path? gif = root.append(tmem, "anim.gif");
		if (catch excuse = gif) return;
		if (catch excuse = file::save(gif, content)) return;

		ImagePicker picker;
		picker.init(tmem);
		assert(picker.open_at((String)root));
		picker.select_path((String)gif);
		assert(file_name(picker.selected_path()).compare_to("anim.gif") == 0);
		assert(picker.activate_selected() == PickerAction.SELECTED);
		assert(!picker.open);
		assert(picker.result.compare_to((String)gif) == 0);

		String taken = picker.take_result(tmem);
		assert(taken.compare_to((String)gif) == 0);
		assert(picker.result.len == 0);

		assert(picker.open_at((String)root));
		picker.move_selection(1);
		assert(file_name(picker.selected_path()).compare_to("photo.png") == 0);
		picker.cancel();
		assert(!picker.open);
		assert(picker.result.len == 0);

		picker.destroy();
		(void)path::rmtree(root);
	};
}

fn void test_contain_rect()
{
	Rect area = { .x = 10.0f, .y = 20.0f, .width = 200.0f, .height = 100.0f };
	Rect wide = contain_rect(400, 100, area);
	assert(math::abs(wide.width - 200.0f) < 0.01f);
	assert(math::abs(wide.height - 50.0f) < 0.01f);
	assert(math::abs(wide.x - 10.0f) < 0.01f);
	assert(math::abs(wide.y - 45.0f) < 0.01f);
	Rect tall = contain_rect(100, 400, area);
	assert(math::abs(tall.width - 25.0f) < 0.01f);
	assert(math::abs(tall.height - 100.0f) < 0.01f);
	assert(math::abs(tall.x - 97.5f) < 0.01f);
	assert(math::abs(tall.y - 20.0f) < 0.01f);
}
fn void test_image_picker_preview_state()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? d = tmp.append(tmem, "yun_image_picker_preview_test");
		if (catch excuse = d) return;
		Path root = d;
		(void)path::rmtree(root);
		if (catch excuse = path::mkdir(root, recursive: true)) return;
		Path? sub = root.append(tmem, "sub");
		if (catch excuse = sub) return;
		if (catch excuse = path::mkdir(sub)) return;
		char[] content = { 'x' };
		Path? png      = root.append(tmem, "photo.png");
		if (catch excuse = png) return;
		if (catch excuse = file::save(png, content)) return;

		ImagePicker picker;
		picker.init(tmem);
		assert(picker.open_at((String)root));
		picker.sync_preview(1.0);
		assert(picker.preview.kind == PreviewKind.FOLDER);
		assert(file_name(picker.preview.path).compare_to("sub") == 0);

		picker.select_path((String)png);
		picker.sync_preview(1.0);
		assert(picker.preview.kind == PreviewKind.LOADING);
		assert(math::abs(picker.preview.due - (1.0 + PREVIEW_DELAY)) < 0.0001);

		picker.selected = 0;
		picker.sync_preview(2.0);
		assert(picker.preview.kind == PreviewKind.PARENT);

		picker.destroy();
		(void)path::rmtree(root);
	};
}