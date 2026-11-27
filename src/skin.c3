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

enum SurfaceField : int
{
	IMAGE,
	FIT,
	OPACITY,
	TINT,
	SCRIM,
	SPEED,
	FPS,
	COUNT,
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

const int MAX_GIF_FRAMES          = 120;
const int MAX_GIF_DIM             = 1024;
const float DEFAULT_FPS           = 12.0f;
const float DEFAULT_CLOSED_HEIGHT = 96.0f;
const float MIN_CLOSED_HEIGHT     = 40.0f;
const float MAX_CLOSED_HEIGHT     = 240.0f;

const String[] SURFACE_NAMES = {
	"app",
	"card",
	"card_title",
	"card_editor",
	"closed_card",
	"folder",
	"folder_title",
	"topbar",
	"panel",
	"panel_header",
	"minimap",
	"focus_backdrop",
	"menu",
	"console",
};

const String[] PRESET_NAMES       = { "classic", "paper", "glass" };
const String[] FIT_NAMES          = { "cover", "contain", "stretch", "tile" };
const String[] CARD_STYLE_NAMES   = { "flat", "paper", "glass" };
const String[] FOLDER_STYLE_NAMES = { "classic", "explorer", "tray" };

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

struct SurfaceOverride
{
	bool image_set;
	String image;
	bool fit_set;
	SurfaceFit fit;
	bool opacity_set;
	float opacity;
	bool tint_set;
	RLColor tint;
	bool scrim_set;
	RLColor scrim;
	bool speed_set;
	float speed;
	bool fps_set;
	float fps;
}

struct SkinLayer
{
	String base;
	bool preset_set;
	String preset;
	bool card_style_set;
	CardStyle card_style;
	bool folder_style_set;
	FolderStyle folder_style;
	bool closed_height_set;
	float closed_height;
	bool language_colors_set;
	bool language_colors;
	SurfaceOverride[SurfaceId.COUNT] surfaces;
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
SkinLayer[2] g_layers;
List{Asset} g_assets;
RLShader g_clip;
bool g_clip_valid;
bool g_state_ready;
bool g_graphics_ready;
int g_clip_rect;
int g_clip_radius;

fn void init(Allocator allocator)
{
	g_allocator = allocator;
	g_assets.init(allocator);
	g_state_ready = true;
	g_graphics_ready = false;
	for (int i = 0; i < 2; i++) g_layers[i] = { };
	g_skin = { };
	rebuild();
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
	g_graphics_ready = true;
}

fn void init_headless(Allocator allocator)
{
	g_allocator = allocator;
	g_assets.init(allocator);
	g_state_ready = true;
	g_graphics_ready = false;
	for (int i = 0; i < 2; i++) g_layers[i] = { };
	g_skin = { };
	rebuild();
}

fn bool is_ready()
{
	return g_state_ready;
}

fn void free_surface(SurfaceConfig* cfg)
{
	if (cfg.image.len) cfg.image.free(g_allocator);
	if (cfg.path.len) cfg.path.free(g_allocator);
	cfg.image = "";
	cfg.path = "";
}

fn void free_skin(Skin* skin)
{
	for (int i = 0; i < (int)SurfaceId.COUNT; i++) free_surface(&skin.surfaces[i]);
	if (skin.preset.len) skin.preset.free(g_allocator);
	skin.preset = "";
}

fn void clear_assets()
{
	if (!g_state_ready) return;
	for (sz i = 0; i < g_assets.len(); i++)
	{
		Asset* entry = &g_assets[i];
		if (g_graphics_ready && entry.texture.is_valid()) rl::unload_texture(entry.texture);
		if (entry.path.len) entry.path.free(g_allocator);
	}
	g_assets.clear();
}

fn void free_layer(SkinLayer* layer)
{
	if (layer.base.len) layer.base.free(g_allocator);
	if (layer.preset.len) layer.preset.free(g_allocator);
	for (int i = 0; i < (int)SurfaceId.COUNT; i++)
	{
		if (layer.surfaces[i].image.len) layer.surfaces[i].image.free(g_allocator);
	}
	*layer = { };
}

fn int layer_index(settings::SettingLayer layer)
{
	if (layer == settings::SettingLayer.GLOBAL) return 0;
	if (layer == settings::SettingLayer.PROJECT) return 1;
	return -1;
}

fn SkinLayer* layer_for(settings::SettingLayer layer)
{
	int index = layer_index(layer);
	if (index < 0) return null;
	return &g_layers[index];
}

fn SurfaceConfig default_surface()
{
	return {
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

fn Skin default_skin()
{
	Skin skin;
	for (int i = 0; i < (int)SurfaceId.COUNT; i++) skin.surfaces[i] = default_surface();
	skin.card_style = CardStyle.FLAT;
	skin.folder_style = FolderStyle.CLASSIC;
	skin.closed_height = DEFAULT_CLOSED_HEIGHT;
	skin.language_colors = true;
	skin.preset = "classic".copy(g_allocator);
	return skin;
}

fn void apply_preset_to(Skin* skin, String name)
{
	if (skin.preset.len) skin.preset.free(g_allocator);
	skin.preset = name.copy(g_allocator);
	skin.card_style = CardStyle.FLAT;
	skin.folder_style = FolderStyle.CLASSIC;
	skin.closed_height = DEFAULT_CLOSED_HEIGHT;
	if (name.compare_to("paper") == 0)
	{
		skin.card_style = CardStyle.PAPER;
		skin.folder_style = FolderStyle.EXPLORER;
		skin.closed_height = 112.0f;
	}
	else if (name.compare_to("glass") == 0)
	{
		skin.card_style = CardStyle.GLASS;
		skin.folder_style = FolderStyle.EXPLORER;
	}
}

fn void apply_layer_to_skin(Skin* skin, SkinLayer* layer)
{
	if (layer.preset_set) apply_preset_to(skin, layer.preset);
	if (layer.card_style_set) skin.card_style = layer.card_style;
	if (layer.folder_style_set) skin.folder_style = layer.folder_style;
	if (layer.closed_height_set) skin.closed_height = math::clamp(
		layer.closed_height,
		MIN_CLOSED_HEIGHT,
		MAX_CLOSED_HEIGHT
	);
	if (layer.language_colors_set) skin.language_colors = layer.language_colors;
	for (int i = 0; i < (int)SurfaceId.COUNT; i++)
	{
		SurfaceOverride over = layer.surfaces[i];
		SurfaceConfig* cfg   = &skin.surfaces[i];
		if (over.image_set) set_image(cfg, over.image, layer.base);
		if (over.fit_set) cfg.fit = over.fit;
		if (over.opacity_set) cfg.opacity = math::clamp(over.opacity, 0.0f, 1.0f);
		if (over.tint_set) cfg.tint = over.tint;
		if (over.scrim_set) cfg.scrim = over.scrim;
		if (over.speed_set) cfg.speed = math::max(0.0f, over.speed);
		if (over.fps_set) cfg.fps = math::max(1.0f, over.fps);
	}
}

fn void rebuild()
{
	if (!g_state_ready) return;
	Skin next = default_skin();
	apply_layer_to_skin(&next, &g_layers[0]);
	apply_layer_to_skin(&next, &g_layers[1]);
	free_skin(&g_skin);
	g_skin = next;
}

fn void reset()
{
	if (!g_state_ready) return;
	for (int i = 0; i < 2; i++) free_layer(&g_layers[i]);
	rebuild();
	clear_assets();
}

fn void shutdown()
{
	if (!g_state_ready) return;
	clear_assets();
	g_assets.free();
	free_skin(&g_skin);
	for (int i = 0; i < 2; i++) free_layer(&g_layers[i]);
	if (g_clip_valid) rl::unload_shader(g_clip);
	g_clip_valid = false;
	g_graphics_ready = false;
	g_state_ready = false;
}

fn String surface_name(SurfaceId id)
{
	int index = (int)id;
	if (index < 0 || index >= (int)SURFACE_NAMES.len) return "";
	return SURFACE_NAMES[index];
}

fn int surface_from_name(String name)
{
	for (usz i = 0; i < SURFACE_NAMES.len; i++)
	{
		if (SURFACE_NAMES[i].compare_to(name) == 0) return (int)i;
	}
	return -1;
}

fn String fit_name(SurfaceFit fit)
{
	switch (fit)
	{
		case SurfaceFit.COVER:
			return "cover";
		case SurfaceFit.CONTAIN:
			return "contain";
		case SurfaceFit.STRETCH:
			return "stretch";
		case SurfaceFit.TILE:
			return "tile";
	}
}

fn SurfaceFit fit_for_name(String value)
{
	if (value.compare_to("contain") == 0) return SurfaceFit.CONTAIN;
	if (value.compare_to("stretch") == 0) return SurfaceFit.STRETCH;
	if (value.compare_to("tile") == 0) return SurfaceFit.TILE;
	return SurfaceFit.COVER;
}

fn String card_style_name(CardStyle style)
{
	switch (style)
	{
		case CardStyle.FLAT:
			return "flat";
		case CardStyle.PAPER:
			return "paper";
		case CardStyle.GLASS:
			return "glass";
	}
}

fn CardStyle card_style_for_name(String value)
{
	if (value.compare_to("paper") == 0) return CardStyle.PAPER;
	if (value.compare_to("glass") == 0) return CardStyle.GLASS;
	return CardStyle.FLAT;
}

fn String folder_style_name(FolderStyle style)
{
	switch (style)
	{
		case FolderStyle.CLASSIC:
			return "classic";
		case FolderStyle.EXPLORER:
			return "explorer";
		case FolderStyle.TRAY:
			return "tray";
	}
}

fn FolderStyle folder_style_for_name(String value)
{
	if (value.compare_to("explorer") == 0) return FolderStyle.EXPLORER;
	if (value.compare_to("tray") == 0) return FolderStyle.TRAY;
	return FolderStyle.CLASSIC;
}

fn char hex_value(char c)
{
	if (c >= '0' && c <= '9') return (char)(c - '0');
	if (c >= 'a' && c <= 'f') return (char)(10 + c - 'a');
	if (c >= 'A' && c <= 'F') return (char)(10 + c - 'A');
	return 0;
}

fn bool color_valid(String value)
{
	if (value.len != 7 && value.len != 9) return false;
	if (value[0] != '#') return false;
	for (usz i = 1; i < value.len; i++)
	{
		char c = value[i];
		if (!((c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F'))) return false;
	}
	return true;
}

fn RLColor parse_color(String value, RLColor fallback)
{
	if (!color_valid(value)) return fallback;
	char r = (char)((hex_value(value[1]) << 4) | hex_value(value[2]));
	char g = (char)((hex_value(value[3]) << 4) | hex_value(value[4]));
	char b = (char)((hex_value(value[5]) << 4) | hex_value(value[6]));
	char a = 255;
	if (value.len == 9) a = (char)((hex_value(value[7]) << 4) | hex_value(value[8]));
	return { r, g, b, a };
}

fn void append_color(DString* out, RLColor color)
{
	out.append_char('#');
	(void)out.appendf("%02x%02x%02x", (int)color[0] & 0xFF, (int)color[1] & 0xFF, (int)color[2] & 0xFF);
	if (color[3] != (char)255) (void)out.appendf("%02x", (int)color[3] & 0xFF);
}

fn String format_color(Allocator allocator, RLColor color)
{
	if (color[3] == (char)255)
	{
		return string::format(
			allocator,
			"#%02x%02x%02x",
			(int)color[0] & 0xFF,
			(int)color[1] & 0xFF,
			(int)color[2] & 0xFF
		);
	}
	return string::format(
		allocator,
		"#%02x%02x%02x%02x",
		(int)color[0] & 0xFF,
		(int)color[1] & 0xFF,
		(int)color[2] & 0xFF,
		(int)color[3] & 0xFF
	);
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

fn void set_layer_base(SkinLayer* layer, String base)
{
	if (layer.base.len) layer.base.free(g_allocator);
	layer.base = base.len > 0 ? base.copy(g_allocator) : "";
}

fn void set_base(String base, settings::SettingLayer layer)
{
	if (!g_state_ready) return;
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	set_layer_base(target, base);
	rebuild();
	clear_assets();
}

fn void apply_surface_override(SurfaceOverride* over, Object* value)
{
	if (!value.is_map()) return;
	if (try image = value.get_string("image"))
	{
		if (over.image.len) over.image.free(g_allocator);
		over.image = image.copy(g_allocator);
		over.image_set = true;
	}
	if (try fit = value.get_string("fit"))
	{
		over.fit = fit_for_name(fit);
		over.fit_set = true;
	}
	if (try opacity = value.get_float("opacity"))
	{
		over.opacity = math::clamp((float)opacity, 0.0f, 1.0f);
		over.opacity_set = true;
	}
	if (try tint = value.get_string("tint"))
	{
		if (color_valid(tint))
		{
			over.tint = parse_color(tint, { 255, 255, 255, 255 });
			over.tint_set = true;
		}
	}
	if (try scrim = value.get_string("scrim"))
	{
		if (color_valid(scrim))
		{
			over.scrim = parse_color(scrim, { 0, 0, 0, 0 });
			over.scrim_set = true;
		}
	}
	if (try speed = value.get_float("speed"))
	{
		over.speed = math::max(0.0f, (float)speed);
		over.speed_set = true;
	}
	if (try fps = value.get_float("fps"))
	{
		over.fps = math::max(1.0f, (float)fps);
		over.fps_set = true;
	}
}

fn void apply_object(Object* obj, String base, settings::SettingLayer layer)
{
	if (!g_state_ready || !obj.is_map()) return;
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	set_layer_base(target, base);
	bool image_changed = false;
	if (try preset = obj.get_string("preset"))
	{
		if (target.preset.len) target.preset.free(g_allocator);
		target.preset = preset.copy(g_allocator);
		target.preset_set = true;
	}
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
					if (id >= 0)
					{
						apply_surface_override(&target.surfaces[id], value);
						if (value.is_map() && value.has_key("image")) image_changed = true;
					}
				};
			}
		}
	}
	if (try cards = obj.get("cards"))
	{
		if (cards.is_map())
		{
			if (try style = cards.get_string("style"))
			{
				target.card_style = card_style_for_name(style);
				target.card_style_set = true;
			}
			if (try closed = cards.get_float("closed_height"))
			{
				target.closed_height = math::clamp((float)closed, MIN_CLOSED_HEIGHT, MAX_CLOSED_HEIGHT);
				target.closed_height_set = true;
			}
			if (try language = cards.get_bool("language_colors"))
			{
				target.language_colors = language;
				target.language_colors_set = true;
			}
		}
	}
	if (try folders = obj.get("folders"))
	{
		if (folders.is_map())
		{
			if (try style = folders.get_string("style"))
			{
				target.folder_style = folder_style_for_name(style);
				target.folder_style_set = true;
			}
		}
	}
	rebuild();
	if (image_changed) clear_assets();
}

fn String preset()
{
	return g_skin.preset.len > 0 ? g_skin.preset : "classic";
}

fn String source_label(settings::SettingLayer layer)
{
	switch (layer)
	{
		case settings::SettingLayer.DEFAULT:
			return "default";
		case settings::SettingLayer.GLOBAL:
			return "global";
		case settings::SettingLayer.PROJECT:
			return "project";
	}
}

fn bool surface_field_set(SkinLayer* layer, SurfaceId id, SurfaceField field)
{
	SurfaceOverride* over = &layer.surfaces[(int)id];
	switch (field)
	{
		case SurfaceField.IMAGE:
			return over.image_set;
		case SurfaceField.FIT:
			return over.fit_set;
		case SurfaceField.OPACITY:
			return over.opacity_set;
		case SurfaceField.TINT:
			return over.tint_set;
		case SurfaceField.SCRIM:
			return over.scrim_set;
		case SurfaceField.SPEED:
			return over.speed_set;
		case SurfaceField.FPS:
			return over.fps_set;
		case SurfaceField.COUNT:
			return false;
	}
}

fn settings::SettingLayer surface_source(SurfaceId id, SurfaceField field)
{
	if (surface_field_set(&g_layers[1], id, field)) return settings::SettingLayer.PROJECT;
	if (surface_field_set(&g_layers[0], id, field)) return settings::SettingLayer.GLOBAL;
	return settings::SettingLayer.DEFAULT;
}

fn bool surface_override_any(SurfaceOverride* over)
{
	return over.image_set || over.fit_set || over.opacity_set || over.tint_set || over.scrim_set || over.speed_set
		|| over.fps_set;
}

fn settings::SettingLayer surface_source_any(SurfaceId id)
{
	if (surface_override_any(&g_layers[1].surfaces[(int)id])) return settings::SettingLayer.PROJECT;
	if (surface_override_any(&g_layers[0].surfaces[(int)id])) return settings::SettingLayer.GLOBAL;
	return settings::SettingLayer.DEFAULT;
}

fn settings::SettingLayer preset_source()
{
	if (g_layers[1].preset_set) return settings::SettingLayer.PROJECT;
	if (g_layers[0].preset_set) return settings::SettingLayer.GLOBAL;
	return settings::SettingLayer.DEFAULT;
}

fn settings::SettingLayer preset_style_source()
{
	if (g_layers[1].preset_set) return settings::SettingLayer.PROJECT;
	if (g_layers[0].preset_set) return settings::SettingLayer.GLOBAL;
	return settings::SettingLayer.DEFAULT;
}

fn settings::SettingLayer card_style_source()
{
	if (g_layers[1].card_style_set) return settings::SettingLayer.PROJECT;
	settings::SettingLayer preset = preset_style_source();
	if (preset != settings::SettingLayer.DEFAULT) return preset;
	if (g_layers[0].card_style_set) return settings::SettingLayer.GLOBAL;
	return settings::SettingLayer.DEFAULT;
}

fn settings::SettingLayer folder_style_source()
{
	if (g_layers[1].folder_style_set) return settings::SettingLayer.PROJECT;
	settings::SettingLayer preset = preset_style_source();
	if (preset != settings::SettingLayer.DEFAULT) return preset;
	if (g_layers[0].folder_style_set) return settings::SettingLayer.GLOBAL;
	return settings::SettingLayer.DEFAULT;
}

fn settings::SettingLayer closed_height_source()
{
	if (g_layers[1].closed_height_set) return settings::SettingLayer.PROJECT;
	settings::SettingLayer preset = preset_style_source();
	if (preset != settings::SettingLayer.DEFAULT) return preset;
	if (g_layers[0].closed_height_set) return settings::SettingLayer.GLOBAL;
	return settings::SettingLayer.DEFAULT;
}

fn settings::SettingLayer language_colors_source()
{
	if (g_layers[1].language_colors_set) return settings::SettingLayer.PROJECT;
	if (g_layers[0].language_colors_set) return settings::SettingLayer.GLOBAL;
	return settings::SettingLayer.DEFAULT;
}

fn void set_preset(String name, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	if (target.preset.len) target.preset.free(g_allocator);
	target.preset = name.len > 0 ? name.copy(g_allocator) : "";
	target.preset_set = name.len > 0;
	rebuild();
}

fn void clear_preset(settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	if (target.preset.len) target.preset.free(g_allocator);
	target.preset = "";
	target.preset_set = false;
	rebuild();
}

fn void set_card_style(CardStyle style, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.card_style = style;
	target.card_style_set = true;
	rebuild();
}

fn void clear_card_style(settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.card_style_set = false;
	rebuild();
}

fn void set_folder_style(FolderStyle style, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.folder_style = style;
	target.folder_style_set = true;
	rebuild();
}

fn void clear_folder_style(settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.folder_style_set = false;
	rebuild();
}

fn void set_closed_height(float height, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.closed_height = math::clamp(height, MIN_CLOSED_HEIGHT, MAX_CLOSED_HEIGHT);
	target.closed_height_set = true;
	rebuild();
}

fn void clear_closed_height(settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.closed_height_set = false;
	rebuild();
}

fn void set_language_colors(bool enabled, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.language_colors = enabled;
	target.language_colors_set = true;
	rebuild();
}

fn void clear_language_colors(settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.language_colors_set = false;
	rebuild();
}

fn void set_surface_image(SurfaceId id, String image, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	SurfaceOverride* over = &target.surfaces[(int)id];
	if (over.image.len) over.image.free(g_allocator);
	over.image = "";
	over.image_set = false;
	if (image.len > 0)
	{
		over.image = image.copy(g_allocator);
		over.image_set = true;
	}
	rebuild();
	clear_assets();
}

fn void set_surface_fit(SurfaceId id, SurfaceFit fit, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.surfaces[(int)id].fit = fit;
	target.surfaces[(int)id].fit_set = true;
	rebuild();
}

fn void set_surface_opacity(SurfaceId id, float opacity, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.surfaces[(int)id].opacity = math::clamp(opacity, 0.0f, 1.0f);
	target.surfaces[(int)id].opacity_set = true;
	rebuild();
}

fn void set_surface_tint(SurfaceId id, RLColor tint, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.surfaces[(int)id].tint = tint;
	target.surfaces[(int)id].tint_set = true;
	rebuild();
}

fn void set_surface_scrim(SurfaceId id, RLColor scrim, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.surfaces[(int)id].scrim = scrim;
	target.surfaces[(int)id].scrim_set = true;
	rebuild();
}

fn void set_surface_speed(SurfaceId id, float speed, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.surfaces[(int)id].speed = math::max(0.0f, speed);
	target.surfaces[(int)id].speed_set = true;
	rebuild();
}

fn void set_surface_fps(SurfaceId id, float fps, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	target.surfaces[(int)id].fps = math::max(1.0f, fps);
	target.surfaces[(int)id].fps_set = true;
	rebuild();
}

fn void clear_surface_field(SurfaceId id, SurfaceField field, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	SurfaceOverride* over = &target.surfaces[(int)id];
	switch (field)
	{
		case SurfaceField.IMAGE:
			if (over.image.len) over.image.free(g_allocator);
			over.image = "";
			over.image_set = false;
		case SurfaceField.FIT:
			over.fit_set = false;
		case SurfaceField.OPACITY:
			over.opacity_set = false;
		case SurfaceField.TINT:
			over.tint_set = false;
		case SurfaceField.SCRIM:
			over.scrim_set = false;
		case SurfaceField.SPEED:
			over.speed_set = false;
		case SurfaceField.FPS:
			over.fps_set = false;
		case SurfaceField.COUNT:
			return;
	}
	rebuild();
	if (field == SurfaceField.IMAGE) clear_assets();
}

fn void clear_surface(SurfaceId id, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	SurfaceOverride* over = &target.surfaces[(int)id];
	if (over.image.len) over.image.free(g_allocator);
	*over = { };
	rebuild();
	clear_assets();
}

fn void clear_layer(settings::SettingLayer layer)
{
	if (layer == settings::SettingLayer.DEFAULT)
	{
		for (int i = 0; i < 2; i++) free_layer(&g_layers[i]);
	}
	else
	{
		SkinLayer* target = layer_for(layer);
		if (target == null) return;
		free_layer(target);
	}
	rebuild();
	clear_assets();
}

fn void append_json_string(DString* out, String text)
{
	out.append_char('"');
	for (usz i = 0; i < text.len; i++)
	{
		char c = text[i];
		if (c == '"' || c == '\\') out.append_char('\\');
		out.append_char(c);
	}
	out.append_char('"');
}

fn bool layer_has_output(SkinLayer* layer)
{
	if (layer.preset_set || layer.card_style_set || layer.folder_style_set || layer.closed_height_set
		|| layer.language_colors_set) return true;
	for (int i = 0; i < (int)SurfaceId.COUNT; i++)
	{
		if (surface_override_any(&layer.surfaces[i])) return true;
	}
	return false;
}

fn bool has_output(settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return false;
	return layer_has_output(target);
}

fn void write_json(DString* out, settings::SettingLayer layer)
{
	SkinLayer* target = layer_for(layer);
	if (target == null) return;
	out.append_char('{');
	bool first = true;
	if (target.preset_set)
	{
		append_json_string(out, "preset");
		out.append_char(':');
		append_json_string(out, target.preset);
		first = false;
	}
	if (target.card_style_set || target.closed_height_set || target.language_colors_set)
	{
		if (!first) out.append_char(',');
		first = false;
		out.append_string("\"cards\":{");
		bool card_first = true;
		if (target.card_style_set)
		{
			append_json_string(out, "style");
			out.append_char(':');
			append_json_string(out, card_style_name(target.card_style));
			card_first = false;
		}
		if (target.closed_height_set)
		{
			if (!card_first) out.append_char(',');
			card_first = false;
			append_json_string(out, "closed_height");
			(void)out.appendf(":%.1f", (double)target.closed_height);
		}
		if (target.language_colors_set)
		{
			if (!card_first) out.append_char(',');
			append_json_string(out, "language_colors");
			out.append_string(target.language_colors ? ":true" : ":false");
		}
		out.append_char('}');
	}
	if (target.folder_style_set)
	{
		if (!first) out.append_char(',');
		first = false;
		out.append_string("\"folders\":{");
		append_json_string(out, "style");
		out.append_char(':');
		append_json_string(out, folder_style_name(target.folder_style));
		out.append_char('}');
	}
	bool surfaces_any = false;
	for (int i = 0; i < (int)SurfaceId.COUNT; i++)
	{
		if (surface_override_any(&target.surfaces[i]))
		{
			surfaces_any = true;
			break;
		}
	}
	if (surfaces_any)
	{
		if (!first) out.append_char(',');
		out.append_string("\"surfaces\":{");
		bool surface_first = true;
		for (int i = 0; i < (int)SurfaceId.COUNT; i++)
		{
			SurfaceOverride* over = &target.surfaces[i];
			if (!surface_override_any(over)) continue;
			if (!surface_first) out.append_char(',');
			surface_first = false;
			append_json_string(out, SURFACE_NAMES[i]);
			out.append_string(":{");
			bool field_first = true;
			if (over.image_set)
			{
				append_json_string(out, "image");
				out.append_char(':');
				append_json_string(out, over.image);
				field_first = false;
			}
			if (over.fit_set)
			{
				if (!field_first) out.append_char(',');
				field_first = false;
				append_json_string(out, "fit");
				out.append_char(':');
				append_json_string(out, fit_name(over.fit));
			}
			if (over.opacity_set)
			{
				if (!field_first) out.append_char(',');
				field_first = false;
				append_json_string(out, "opacity");
				(void)out.appendf(":%.3f", (double)over.opacity);
			}
			if (over.tint_set)
			{
				if (!field_first) out.append_char(',');
				field_first = false;
				append_json_string(out, "tint");
				out.append_char(':');
				out.append_char('"');
				append_color(out, over.tint);
				out.append_char('"');
			}
			if (over.scrim_set)
			{
				if (!field_first) out.append_char(',');
				field_first = false;
				append_json_string(out, "scrim");
				out.append_char(':');
				out.append_char('"');
				append_color(out, over.scrim);
				out.append_char('"');
			}
			if (over.speed_set)
			{
				if (!field_first) out.append_char(',');
				field_first = false;
				append_json_string(out, "speed");
				(void)out.appendf(":%.3f", (double)over.speed);
			}
			if (over.fps_set)
			{
				if (!field_first) out.append_char(',');
				append_json_string(out, "fps");
				(void)out.appendf(":%.3f", (double)over.fps);
			}
			out.append_char('}');
		}
		out.append_char('}');
	}
	out.append_char('}');
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