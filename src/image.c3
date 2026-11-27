module yun::image;

faultdef IMAGE_FAILED;

import raylib6::rl;
import std::io::file;
import std::math;

extern fn char* yun_stbi_load_from_memory(
	char* buffer,
	int len,
	int* width,
	int* height,
	int* channels,
	int desired_channels
) @cname("yun_stbi_load_from_memory");
extern fn void yun_stbi_image_free(void* data) @cname("yun_stbi_image_free");

struct DecodedImage
{
	RLImage image;
	bool fallback;
}

struct Thumbnail
{
	RLTexture2D texture;
	int width;
	int height;
}

fn String extension(String path)
{
	usz start = 0;
	usz dot   = 0;
	bool has  = false;
	for (usz i = 0; i < path.len; i++)
	{
		if (path[i] == '/' || path[i] == '\\') start = i + 1;
	}
	for (usz i = start; i < path.len; i++)
	{
		if (path[i] == '.')
		{
			dot = i;
			has = true;
		}
	}
	if (!has || dot + 1 >= path.len) return "";
	return path[dot:path.len - dot];
}

fn bool supported(String path)
{
	String ext = extension(path);
	return ext.compare_to_ignore_case(
		".png"
	) == 0 || ext.compare_to_ignore_case(
		".jpg"
	) == 0 || ext.compare_to_ignore_case(
		".jpeg"
	) == 0 || ext.compare_to_ignore_case(
		".jfif"
	) == 0 || ext.compare_to_ignore_case(".gif") == 0 || ext.compare_to_ignore_case(".bmp") == 0;
}

fn bool is_jpeg(String path)
{
	String ext = extension(path);
	return ext.compare_to_ignore_case(
		".jpg"
	) == 0 || ext.compare_to_ignore_case(".jpeg") == 0 || ext.compare_to_ignore_case(".jfif") == 0;
}

fn DecodedImage? load_jpeg(String path)
{
	if (!is_jpeg(path)) return IMAGE_FAILED~;
	@pool()
	{
		char[]? data = file::load(tmem, path);
		if (catch excuse = data) return IMAGE_FAILED~;
		int width    = 0;
		int height   = 0;
		int channels = 0;
		char* pixels = yun_stbi_load_from_memory(data.ptr, (int)data.len, &width, &height, &channels, 4);
		if (pixels == null) return IMAGE_FAILED~;
		return {
			.image = {
				.data = pixels,
				.width = width,
				.height = height,
				.mipmaps = 1,
				.format = rl::RLPixelFormat.UNCOMPRESSED_R8G8B8A8,
			},
			.fallback = true,
		};
	};
}

fn DecodedImage? load_still(String path)
{
	if (is_jpeg(path)) return load_jpeg(path);
	RLImage image = rl::load_image(path.zstr_tcopy());
	if (image.is_valid()) return { .image = image, .fallback = false };
	return load_jpeg(path);
}

fn void free_stbi_data(RLImage image)
{
	if (image.data != null) yun_stbi_image_free(image.data);
}

fn void DecodedImage.free(&self)
{
	if (self.fallback)
	{
		if (self.image.data != null) yun_stbi_image_free(self.image.data);
		return;
	}
	if (self.image.data != null) rl::unload_image(self.image);
}

fn Thumbnail? load_thumbnail(String path, int max_dim)
{
	DecodedImage? decoded = load_still(path);
	if (catch excuse = decoded) return IMAGE_FAILED~;
	DecodedImage image = decoded;
	if (max_dim > 0 && (image.image.width > max_dim || image.image.height > max_dim))
	{
		float scale = math::min((float)max_dim / (float)image.image.width, (float)max_dim / (float)image.image.height);
		rl::image_resize(
			&image.image,
			math::max(1, (int)((float)image.image.width * scale)),
			math::max(1, (int)((float)image.image.height * scale))
		);
	}
	RLTexture2D texture = rl::load_texture_from_image(image.image);
	Thumbnail result = {
		.texture = texture,
		.width = image.image.width,
		.height = image.image.height,
	};
	image.free();
	if (!texture.is_valid()) return IMAGE_FAILED~;
	texture.set_filter(rl::RLTextureFilter.BILINEAR);
	result.texture = texture;
	return result;
}