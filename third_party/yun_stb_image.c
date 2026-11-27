#define STB_IMAGE_STATIC
#define STB_IMAGE_IMPLEMENTATION
#define STBI_ONLY_JPEG
#define STBI_NO_STDIO
#include "stb_image.h"

unsigned char *yun_stbi_load_from_memory(
	const unsigned char *buffer,
	int len,
	int *width,
	int *height,
	int *channels,
	int desired_channels
)
{
	return stbi_load_from_memory(buffer, len, width, height, channels, desired_channels);
}

void yun_stbi_image_free(void *data)
{
	stbi_image_free(data);
}

const char *yun_stbi_failure_reason(void)
{
	return stbi_failure_reason();
}
