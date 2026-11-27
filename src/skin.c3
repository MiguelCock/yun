module yun::skin;

import raylib6::rl;
import std::collections::list;
import std::collections::object;
import std::io::path;
import std::math;
import yun::language;
import yun::settings;
import yun::theme;

enum SurfaceId : int
{
	APP,
	CARD,
	CARD_TITLE,
	CARD_EDITOR,
	CLOSED_CARD,
	FOLDER,
	FOLDER_TITLE,
	TOPBAR,
	PANEL,
	PANEL_HEADER,
	MINIMAP,
	FOCUS_BACKDROP,
	MENU,
	CONSOLE,
	COUNT,
}

enum SurfaceFit : int
{
	COVER,
	CONTAIN,
	STRETCH,
	TILE,
}

enum CardStyle : int
{
	FLAT,
	PAPER,
	GLASS,
}

enum FolderStyle : int
{
	CLASSIC,
	EXPLORER,
	TRAY,
}

const int MAX_GIF_FRAMES = 120;
const int MAX_GIF_DIM    = 1024;
const float DEFAULT_FPS  = 12.0f;

struct SurfaceConfig
{
	String image;
	String path;
	SurfaceFit fit;
	float opacity;
	RLColor tint;
	RLColor scrim;
	float speed;
	float fps;
}

struct Asset
{
	String path;
	RLTexture2D texture;
	int frame_count;
	int frame_height;
	bool ok;
}

struct Skin
{
	SurfaceConfig[SurfaceId.COUNT] surfaces;
	CardStyle card_style;
	FolderStyle folder_style;
	float closed_height;
	bool language_colors;
	String preset;
}

Allocator g_allocator;
Skin g_skin;
List{Asset} g_assets;
RLShader g_clip;
bool g_clip_valid;
bool g_ready;
int g_clip_rect;
int g_clip_radius;

fn void init(Allocator allocator)
{
	g_allocator = allocator;
	g_assets.init(allocator);
	g_ready = true;
	reset();
	ZString vs = "#version 330\n"
		"in vec3 vertexPosition;\n"
		"in vec2 vertexTexCoord;\n"
		"in vec4 vertexColor;\n"
		"uniform mat4 mvp;\n"
		"out vec2 fragTexCoord;\n"
		"out vec4 fragColor;\n"
		"out vec2 fragPos;\n"
		"void main() {\n"
		"  fragTexCoord = vertexTexCoord;\n"
		"  fragColor = vertexColor;\n"
		"  fragPos = vertexPosition.xy;\n"
		"  gl_Position = mvp * vec4(vertexPosition, 1.0);\n"
		"}\n";
	ZString fs = "#version 330\n"
		"in vec2 fragTexCoord;\n"
		"in vec4 fragColor;\n"
		"in vec2 fragPos;\n"
		"uniform sampler2D texture0;\n"
		"uniform vec4 colDiffuse;\n"
		"uniform vec4 u_rect;\n"
		"uniform float u_radius;\n"
		"out vec4 finalColor;\n"
		"void main() {\n"
		"  if (u_radius > 0.0) {\n"
		"    vec2 halfSize = u_rect.zw * 0.5;\n"
		"    vec2 p = fragPos - u_rect.xy - halfSize;\n"
		"    vec2 q = abs(p) - (halfSize - vec2(u_radius));\n"
		"    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - u_radius;\n"
		"    if (d > 0.0) discard;\n"
		"  }\n"
		"  finalColor = texture(texture0, fragTexCoord) * fragColor * colDiffuse;\n"
		"}\n";
	g_clip = rl::load_shader_from_memory(vs, fs);
	g_clip_valid = g_clip.is_valid();
	if (g_clip_valid)
	{
		g_clip_rect = g_clip.get_location("u_rect");
		g_clip_radius = g_clip.get_location("u_radius");
	}
}

fn void free_surface(SurfaceConfig* cfg)
{
	if (cfg.image.len) cfg.image.free(g_allocator);
	if (cfg.path.len) cfg.path.free(g_allocator);
	cfg.image = "";
	cfg.path = "";
}

fn void clear_assets()
{
	if (!g_ready) return;
	for (sz i = 0; i < g_assets.len(); i++)
	{
		Asset* entry = &g_assets[i];
		if (entry.texture.is_valid()) rl::unload_texture(entry.texture);
		if (entry.path.len) entry.path.free(g_allocator);
	}
	g_assets.clear();
}

fn void reset()
{
	for (int i = 0; i < (int)SurfaceId.COUNT; i++) free_surface(&g_skin.surfaces[i]);
	for (int i = 0; i < (int)SurfaceId.COUNT; i++)
	{
		g_skin.surfaces[i] = {
			.image = "",
			.path = "",
			.fit = SurfaceFit.COVER,
			.opacity = 1.0f,
			.tint = { 255, 255, 255, 255 },
			.scrim = { 0, 0, 0, 0 },
			.speed = 1.0f,
			.fps = DEFAULT_FPS,
		};
	}
	g_skin.card_style = CardStyle.FLAT;
	g_skin.folder_style = FolderStyle.CLASSIC;
	g_skin.closed_height = 96.0f;
	g_skin.language_colors = true;
	if (g_skin.preset.len) g_skin.preset.free(g_allocator);
	g_skin.preset = g_ready ? "classic".copy(g_allocator) : "";
	clear_assets();
}

fn void shutdown()
{
	if (!g_ready) return;
	clear_assets();
	g_assets.free();
	for (int i = 0; i < (int)SurfaceId.COUNT; i++) free_surface(&g_skin.surfaces[i]);
	if (g_skin.preset.len) g_skin.preset.free(g_allocator);
	g_skin.preset = "";
	if (g_clip_valid) rl::unload_shader(g_clip);
	g_clip_valid = false;
	g_ready = false;
}

fn int surface_from_name(String name)
{
	if (name.compare_to("app") == 0) return (int)SurfaceId.APP;
	if (name.compare_to("card") == 0) return (int)SurfaceId.CARD;
	if (name.compare_to("card_title") == 0) return (int)SurfaceId.CARD_TITLE;
	if (name.compare_to("card_editor") == 0) return (int)SurfaceId.CARD_EDITOR;
	if (name.compare_to("closed_card") == 0) return (int)SurfaceId.CLOSED_CARD;
	if (name.compare_to("folder") == 0) return (int)SurfaceId.FOLDER;
	if (name.compare_to("folder_title") == 0) return (int)SurfaceId.FOLDER_TITLE;
	if (name.compare_to("topbar") == 0) return (int)SurfaceId.TOPBAR;
	if (name.compare_to("panel") == 0) return (int)SurfaceId.PANEL;
	if (name.compare_to("panel_header") == 0) return (int)SurfaceId.PANEL_HEADER;
	if (name.compare_to("minimap") == 0) return (int)SurfaceId.MINIMAP;
	if (name.compare_to("focus_backdrop") == 0) return (int)SurfaceId.FOCUS_BACKDROP;
	if (name.compare_to("menu") == 0) return (int)SurfaceId.MENU;
	if (name.compare_to("console") == 0) return (int)SurfaceId.CONSOLE;
	return -1;
}

fn SurfaceFit parse_fit(String value)
{
	if (value.compare_to("contain") == 0) return SurfaceFit.CONTAIN;
	if (value.compare_to("stretch") == 0) return SurfaceFit.STRETCH;
	if (value.compare_to("tile") == 0) return SurfaceFit.TILE;
	return SurfaceFit.COVER;
}

fn char hex_value(char c)
{
	if (c >= '0' && c <= '9') return (char)(c - '0');
	if (c >= 'a' && c <= 'f') return (char)(10 + c - 'a');
	if (c >= 'A' && c <= 'F') return (char)(10 + c - 'A');
	return 0;
}

fn RLColor parse_color(String value, RLColor fallback)
{
	if (value.len < 7 || value[0] != '#') return fallback;
	char r = (char)((hex_value(value[1]) << 4) | hex_value(value[2]));
	char g = (char)((hex_value(value[3]) << 4) | hex_value(value[4]));
	char b = (char)((hex_value(value[5]) << 4) | hex_value(value[6]));
	char a = 255;
	if (value.len >= 9) a = (char)((hex_value(value[7]) << 4) | hex_value(value[8]));
	return { r, g, b, a };
}

fn void set_image(SurfaceConfig* cfg, String image, String base)
{
	if (cfg.image.len) cfg.image.free(g_allocator);
	if (cfg.path.len) cfg.path.free(g_allocator);
	cfg.image = "";
	cfg.path = "";
	if (image.len == 0) return;
	cfg.image = image.copy(g_allocator);
	if (image[0] == '/' || (image.len > 1 && image[1] == ':'))
	{
		cfg.path = image.copy(g_allocator);
		return;
	}
	@pool()
	{
		Path? resolved = ((Path)base).append(tmem, image);
		if (catch excuse = resolved)
		{
			cfg.path = image.copy(g_allocator);
			return;
		}
		cfg.path = ((String)resolved).copy(g_allocator);
	};
}

fn void apply_surface(SurfaceConfig* cfg, Object* value, String base)
{
	if (!value.is_map()) return;
	if (try image = value.get_string("image")) set_image(cfg, image, base);
	if (try fit = value.get_string("fit")) cfg.fit = parse_fit(fit);
	if (try opacity = value.get_float("opacity")) cfg.opacity = math::clamp((float)opacity, 0.0f, 1.0f);
	if (try tint = value.get_string("tint")) cfg.tint = parse_color(tint, cfg.tint);
	if (try scrim = value.get_string("scrim")) cfg.scrim = parse_color(scrim, cfg.scrim);
	if (try speed = value.get_float("speed")) cfg.speed = math::max(0.0f, (float)speed);
	if (try fps = value.get_float("fps")) cfg.fps = math::max(1.0f, (float)fps);
}

fn void apply_preset(String name)
{
	if (g_skin.preset.len) g_skin.preset.free(g_allocator);
	g_skin.preset = name.copy(g_allocator);
	g_skin.card_style = CardStyle.FLAT;
	g_skin.folder_style = FolderStyle.CLASSIC;
	g_skin.closed_height = 96.0f;
	if (name.compare_to("paper") == 0)
	{
		g_skin.card_style = CardStyle.PAPER;
		g_skin.folder_style = FolderStyle.EXPLORER;
		g_skin.closed_height = 112.0f;
	}
	else if (name.compare_to("glass") == 0)
	{
		g_skin.card_style = CardStyle.GLASS;
		g_skin.folder_style = FolderStyle.EXPLORER;
	}
}

fn void apply_object(Object* obj, String base, settings::SettingLayer layer)
{
	if (!g_ready || !obj.is_map()) return;
	if (try preset = obj.get_string("preset")) apply_preset(preset);
	if (obj.has_key("surfaces"))
	{
		Object*? surfaces = obj.get("surfaces");
		if (try list = surfaces)
		{
			if (list.is_map())
			{
				list.@each_entry(; String key, Object* value)
				{
					int id = surface_from_name(key);
					if (id >= 0) apply_surface(&g_skin.surfaces[id], value, base);
				};
			}
		}
	}
	if (try cards = obj.get("cards"))
	{
		if (try style = cards.get_string("style"))
		{
			if (style.compare_to("paper") == 0)
			{
				g_skin.card_style = CardStyle.PAPER;
			}
			else if (style.compare_to("glass") == 0)
			{
				g_skin.card_style = CardStyle.GLASS;
			}
			else
			{
				g_skin.card_style = CardStyle.FLAT;
			}
		}
		if (try closed = cards.get_float(
			"closed_height"
		)) g_skin.closed_height = math::clamp((float)closed, 40.0f, 240.0f);
		if (try language = cards.get_bool("language_colors")) g_skin.language_colors = language;
	}
	if (try folders = obj.get("folders"))
	{
		if (try style = folders.get_string("style"))
		{
			if (style.compare_to("explorer") == 0)
			{
				g_skin.folder_style = FolderStyle.EXPLORER;
			}
			else if (style.compare_to("tray") == 0)
			{
				g_skin.folder_style = FolderStyle.TRAY;
			}
			else
			{
				g_skin.folder_style = FolderStyle.CLASSIC;
			}
		}
	}
	if (layer == settings::SettingLayer.PROJECT) clear_assets();
}


fn RLColor adjust_language_color(RLColor c)
{
	RLColor bg = theme::current().window_bg;
	float lum  = (0.2126f * (float)(int)bg[0] + 0.7152f * (float)(int)bg[1] + 0.0722f * (float)(int)bg[2]) / 255.0f;
	if (lum > 0.5f)
	{
		c[0] = (char)((int)c[0] * 55 / 100);
		c[1] = (char)((int)c[1] * 55 / 100);
		c[2] = (char)((int)c[2] * 55 / 100);
	}
	return c;
}

fn RLColor language_color(String path)
{
	RLColor c = { 138, 143, 152, 255 };
	switch (language::language_for_path(path))
	{
		case language::Language.C3:
			c = { 108, 182, 255, 255 };
		case language::Language.C:
		case language::Language.CPP:
			c = { 122, 162, 247, 255 };
		case language::Language.PYTHON:
			c = { 247, 201, 72, 255 };
		case language::Language.JAVASCRIPT:
			c = { 247, 223, 30, 255 };
		case language::Language.TYPESCRIPT:
		case language::Language.TSX:
			c = { 74, 163, 255, 255 };
		case language::Language.GO:
			c = { 0, 173, 216, 255 };
		case language::Language.RUST:
			c = { 222, 165, 132, 255 };
		case language::Language.ZIG:
			c = { 247, 164, 29, 255 };
		case language::Language.ODIN:
			c = { 199, 125, 255, 255 };
		case language::Language.V:
			c = { 93, 156, 236, 255 };
		case language::Language.NIM:
			c = { 255, 230, 102, 255 };
		case language::Language.JAVA:
			c = { 231, 111, 0, 255 };
		case language::Language.KOTLIN:
			c = { 169, 123, 255, 255 };
		case language::Language.SCALA:
			c = { 194, 45, 64, 255 };
		case language::Language.C_SHARP:
			c = { 81, 43, 212, 255 };
		case language::Language.CSS:
		case language::Language.SCSS:
		case language::Language.SASS:
		case language::Language.LESS:
			c = { 86, 61, 124, 255 };
		case language::Language.HTML:
		case language::Language.XML:
		case language::Language.VUE:
			c = { 227, 76, 38, 255 };
		case language::Language.LUA:
			c = { 81, 160, 255, 255 };
		case language::Language.PHP:
			c = { 119, 123, 180, 255 };
		case language::Language.RUBY:
			c = { 204, 52, 45, 255 };
		case language::Language.R:
			c = { 39, 109, 195, 255 };
		case language::Language.JULIA:
			c = { 149, 88, 178, 255 };
		case language::Language.HASKELL:
			c = { 93, 79, 133, 255 };
		case language::Language.GLEAM:
			c = { 255, 175, 189, 255 };
		case language::Language.ERLANG:
			c = { 169, 5, 51, 255 };
		case language::Language.ELIXIR:
			c = { 110, 74, 126, 255 };
		case language::Language.DART:
			c = { 0, 180, 171, 255 };
		case language::Language.MARKDOWN:
		case language::Language.MARKDOWN_INLINE:
			c = { 138, 180, 248, 255 };
		case language::Language.SOL:
			c = { 240, 160, 80, 255 };
		case language::Language.JSON:
			c = { 203, 203, 65, 255 };
		case language::Language.YAML:
			c = { 203, 23, 30, 255 };
		case language::Language.TOML:
			c = { 156, 66, 33, 255 };
		case language::Language.SQL:
			c = { 227, 140, 0, 255 };
		case language::Language.BASH:
		case language::Language.DOCKERFILE:
			c = { 137, 224, 81, 255 };
		case language::Language.NIX:
			c = { 126, 211, 247, 255 };
		case language::Language.GRAPHQL:
			c = { 225, 0, 152, 255 };
		case language::Language.LATEX:
			c = { 0, 128, 0, 255 };
		case language::Language.DIFF:
			c = { 100, 200, 140, 255 };
		default:
			break;
	}
	return adjust_language_color(c);
}

fn SurfaceConfig surface(SurfaceId id)
{
	return g_skin.surfaces[(int)id];
}

fn CardStyle card_style()
{
	return g_skin.card_style;
}

fn FolderStyle folder_style()
{
	return g_skin.folder_style;
}

fn float closed_height()
{
	return g_skin.closed_height > 0.0f ? g_skin.closed_height : 96.0f;
}

fn bool language_colors()
{
	return g_skin.language_colors;
}

fn Asset*? asset_for(String path)
{
	for (sz i = 0; i < g_assets.len(); i++)
	{
		if (g_assets[i].path.compare_to(path) == 0) return &g_assets[i];
	}
	Asset entry = {
		.path = path.copy(g_allocator),
		.texture = { },
		.frame_count = 1,
		.frame_height = 0,
		.ok = false,
	};
	int frames    = 0;
	RLImage image = rl::load_image_anim(path.zstr_tcopy(), &frames);
	if (!image.is_valid())
	{
		image = rl::load_image(path.zstr_tcopy());
		frames = 1;
	}
	if (image.is_valid())
	{
		if (frames < 1) frames = 1;
		if (image.width > MAX_GIF_DIM || image.height > 8192)
		{
			float scale = math::min((float)MAX_GIF_DIM / (float)image.width, 8192.0f / (float)image.height);
			rl::image_resize(&image, (int)((float)image.width * scale), (int)((float)image.height * scale));
		}
		RLTexture2D texture = rl::load_texture_from_image(image);
		if (texture.is_valid())
		{
			texture.set_filter(rl::RLTextureFilter.BILINEAR);
			entry.texture = texture;
			entry.frame_count = frames;
			entry.frame_height = image.height / frames;
			entry.ok = entry.frame_height > 0;
		}
		rl::unload_image(image);
	}
	g_assets.push(entry);
	return &g_assets[g_assets.len() - 1];
}

fn Rect cover_source(int width, int height, Rect dest)
{
	float dest_aspect = dest.height > 0.0f ? dest.width / dest.height : 1.0f;
	float tex_aspect  = (float)width / (float)height;
	float sw          = (float)width;
	float sh          = (float)height;
	float sx          = 0.0f;
	float sy          = 0.0f;
	if (tex_aspect > dest_aspect)
	{
		sw = (float)height * dest_aspect;
		sx = ((float)width - sw) * 0.5f;
	}
	else
	{
		sh = (float)width / dest_aspect;
		sy = ((float)height - sh) * 0.5f;
	}
	return { .x = sx, .y = sy, .width = sw, .height = sh };
}

fn void draw_texture(RLTexture2D tex, Rect dest, Rect source, RLColor tint)
{
	rl::draw_texture_pro(tex, source, dest, { 0.0f, 0.0f }, 0.0f, tint);
}

fn bool draw_surface(SurfaceId id, Rect dest, float radius)
{
	SurfaceConfig cfg = g_skin.surfaces[(int)id];
	if (cfg.path.len == 0 || dest.width <= 0.0f || dest.height <= 0.0f) return false;
	Asset*? loaded = asset_for(cfg.path);
	if (catch excuse = loaded)
	{
		return false;
	}
	return draw_asset(cfg, loaded, dest, radius);
}

fn bool draw_asset(SurfaceConfig cfg, Asset* entry, Rect dest, float radius)
{
	if (!entry.ok || !entry.texture.is_valid()) return false;
	int frame = 0;
	if (entry.frame_count > 1 && cfg.fps > 0.0f && cfg.speed > 0.0f)
	{
		double t = rl::get_time() * (double)cfg.fps * (double)cfg.speed;
		frame = (int)(t) % entry.frame_count;
		if (frame < 0) frame = 0;
	}
	RLTexture2D tex  = entry.texture;
	int frame_height = entry.frame_height > 0 ? entry.frame_height : tex.height;
	RLColor tint     = cfg.tint;
	tint.a = (char)((float)((int)tint.a & 0xFF) * cfg.opacity);
	Rect source = { 0.0f, (float)(frame * frame_height), (float)tex.width, (float)frame_height };
	Rect draw   = dest;
	if (cfg.fit == SurfaceFit.COVER)
	{
		Rect crop = cover_source(tex.width, frame_height, dest);
		source = { crop.x, (float)(frame * frame_height) + crop.y, crop.width, crop.height };
	}
	else if (cfg.fit == SurfaceFit.CONTAIN)
	{
		float scale = math::min(dest.width / (float)tex.width, dest.height / (float)frame_height);
		float w     = (float)tex.width * scale;
		float h     = (float)frame_height * scale;
		draw = {
			.x = dest.x + (dest.width - w) * 0.5f,
			.y = dest.y + (dest.height - h) * 0.5f,
			.width = w,
			.height = h
		};
	}
	if (g_clip_valid)
	{
		rl::begin_shader_mode(g_clip);
		float[4] rect = { dest.x, dest.y, dest.width, dest.height };
		g_clip.set_value(g_clip_rect, &rect, rl::RLShaderUniformDataType.VEC4);
		float rad = radius;
		g_clip.set_value(g_clip_radius, &rad, rl::RLShaderUniformDataType.FLOAT);
	}
	if (cfg.fit == SurfaceFit.TILE)
	{
		float step_x = (float)tex.width;
		float step_y = (float)frame_height;
		if (step_x < 1.0f || step_y < 1.0f)
		{
			step_x = dest.width;
			step_y = dest.height;
		}
		for (float y = dest.y; y < dest.y + dest.height; y += step_y)
		{
			for (float x = dest.x; x < dest.x + dest.width; x += step_x)
			{
				rl::draw_texture_pro(
					tex,
					source,
					{ .x = x, .y = y, .width = step_x, .height = step_y },
					{ 0.0f, 0.0f },
					0.0f,
					tint
				);
			}
		}
	}
	else
	{
		draw_texture(tex, draw, source, tint);
	}
	if (g_clip_valid) rl::end_shader_mode();
	if (cfg.scrim.a > 0)
	{
		rl::draw_rectangle_rounded(
			dest,
			radius > 0.0f ? math::min(1.0f, radius / math::min(dest.width, dest.height) * 2.0f) : 0.0f,
			16,
			cfg.scrim
		);
	}
	return true;
}

fn bool draw_screen(SurfaceId id, Rect dest, float radius)
{
	return draw_surface(id, dest, radius);
}

fn bool draw_world(SurfaceId id, Rect dest, float zoom, float radius)
{
	return draw_surface(id, dest, radius / (zoom > 0.0f ? zoom : 1.0f));
}