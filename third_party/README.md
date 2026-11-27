# Third-party sources

## stb_image

- `stb_image.h` v2.29, public domain / MIT.
- Source: https://github.com/nothings/stb
- `yun_stb_image.c` compiles only the JPEG decoder and exposes a small
  memory-only API to `yun::image`.

The bundled raylib build disables JPEG decoding, so this decoder provides the
JPEG/JPEG-FIF fallback for skin surfaces and the image picker preview.
