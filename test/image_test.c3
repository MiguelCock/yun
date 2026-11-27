module yun::image @test;

import raylib6::rl;
import std::encoding::base64;
import std::io::file;
import std::io::path;

const String TINY_JPEG = "/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAACAAIDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAABgj/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCdABykX//Z";

fn void test_supported_extensions()
{
	assert(supported("photo.png"));
	assert(supported("photo.PNG"));
	assert(supported("photo.jpg"));
	assert(supported("photo.JPEG"));
	assert(supported("photo.jfif"));
	assert(supported("anim.gif"));
	assert(supported("icon.bmp"));
	assert(!supported("photo.webp"));
	assert(!supported("notes.txt"));
	assert(!supported("noext"));
}

fn void test_jpeg_fallback_decode()
{
	@pool()
	{
		char[]? bytes = base64::decode(tmem, (char[])TINY_JPEG);
		if (catch excuse = bytes)
		{
			assert(false);
			return;
		}
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? dir = tmp.append(tmem, "yun_image_jpeg_test");
		if (catch excuse = dir) return;
		Path root = dir;
		(void)path::rmtree(root);
		if (catch excuse = path::mkdir(root, recursive: true)) return;
		Path? file_path = root.append(tmem, "tiny.jpg");
		if (catch excuse = file_path) return;
		if (catch excuse = file::save(file_path, bytes)) return;

		DecodedImage? loaded = load_still((String)file_path);
		if (catch excuse = loaded)
		{
			assert(false);
			return;
		}
		DecodedImage image = loaded;
		assert(image.fallback);
		assert(image.image.width == 2);
		assert(image.image.height == 2);
		assert(image.image.format == rl::RLPixelFormat.UNCOMPRESSED_R8G8B8A8);
		image.free();
		(void)path::rmtree(root);
	};
}