module yun::icons;

import raylib6::rl;
import std::collections::list;
import std::io::file;
import std::io::path;
import std::math;
import std::math::geometry;
import std::os::env;
import yun::language;
import yun::ui;

enum IconKind : int
{
	NEW_FILE,
	OPEN,
	SAVE,
	SETTINGS,
	CONNECTIONS,
	QUIT,
	PREVIEW,
	MAXIMIZE,
	RESTORE,
	MINIMIZE,
	CLOSE,
	SEARCH,
	PROBLEMS,
	SYMBOLS,
	CONSOLE,
	KEYBOARD,
	THEME,
	PLAY,
	STOP,
	TRASH,
	CHEVRON_DOWN,
	CHEVRON_RIGHT,
	GIT,
	ARROWS,
	COUNT,
}

enum UiIconTheme : int
{
	VECTOR,
	CODICONS,
}

enum FileIconTheme : int
{
	NONE,
	MATERIAL,
	VSCODE,
}

const int ICON_COUNT = (int)IconKind.COUNT;

struct FileIconCacheEntry
{
	String theme;
	String name;
	RLTexture2D texture;
	bool valid;
}

Allocator g_allocator;
UiIconTheme g_ui_theme     = UiIconTheme.VECTOR;
FileIconTheme g_file_theme = FileIconTheme.NONE;
String g_override_dir      = "";
RLTexture2D[ICON_COUNT] g_ui_textures;
bool[ICON_COUNT] g_ui_loaded;
List{FileIconCacheEntry} g_file_icons;

fn void init(Allocator allocator)
{
	g_allocator = allocator;
	g_file_icons.init(allocator);
	@pool()
	{
		Path? config_dir = env::get_config_dir(tmem);
		if (catch err = config_dir) return;
		Path? dir = config_dir.append(tmem, "yun/icons");
		if (catch err = dir) return;
		g_override_dir = ((String)dir).copy(allocator);
	};
}

fn void clear_ui_cache()
{
	for (int i = 0; i < ICON_COUNT; i++)
	{
		if (g_ui_loaded[i] && g_ui_textures[i].is_valid()) rl::unload_texture(g_ui_textures[i]);
		g_ui_loaded[i] = false;
	}
}

fn void clear_file_cache()
{
	for (sz i = 0; i < g_file_icons.len(); i++)
	{
		if (g_file_icons[i].valid && g_file_icons[i].texture.is_valid()) rl::unload_texture(g_file_icons[i].texture);
	}
	g_file_icons.clear();
}

fn void shutdown()
{
	clear_ui_cache();
	clear_file_cache();
	g_file_icons.free();
	if (g_override_dir.len) g_override_dir.free(g_allocator);
	g_override_dir = "";
}

fn void set_ui_theme(UiIconTheme theme)
{
	if (theme == g_ui_theme) return;
	clear_ui_cache();
	g_ui_theme = theme;
}

fn void set_file_theme(FileIconTheme theme)
{
	if (theme == g_file_theme) return;
	clear_file_cache();
	g_file_theme = theme;
}

fn float icon_size(int logical)
{
	return ui::pxf((float)logical);
}

fn Rect icon_box(Rect button, int logical)
{
	float size = icon_size(logical);
	return {
		.x = button.x + (button.width - size) * 0.5f,
		.y = button.y + (button.height - size) * 0.5f,
		.width = size,
		.height = size,
	};
}

fn String codicon_name(IconKind icon)
{
	switch (icon)
	{
		case IconKind.NEW_FILE:
			return "new-file";
		case IconKind.OPEN:
			return "open";
		case IconKind.SAVE:
			return "save";
		case IconKind.SETTINGS:
			return "settings";
		case IconKind.CONNECTIONS:
			return "connections";
		case IconKind.QUIT:
			return "quit";
		case IconKind.PREVIEW:
			return "preview";
		case IconKind.MAXIMIZE:
			return "maximize";
		case IconKind.RESTORE:
			return "restore";
		case IconKind.MINIMIZE:
			return "minimize";
		case IconKind.CLOSE:
			return "close";
		case IconKind.SEARCH:
			return "search";
		case IconKind.PROBLEMS:
			return "problems";
		case IconKind.SYMBOLS:
			return "symbols";
		case IconKind.CONSOLE:
			return "console";
		case IconKind.KEYBOARD:
			return "keyboard";
		case IconKind.THEME:
			return "theme";
		case IconKind.PLAY:
			return "play";
		case IconKind.STOP:
			return "stop";
		case IconKind.TRASH:
			return "trash";
		case IconKind.CHEVRON_DOWN:
			return "chevron-down";
		case IconKind.CHEVRON_RIGHT:
			return "chevron-right";
		case IconKind.GIT:
			return "source-control";
		case IconKind.ARROWS:
			return "references";
		case IconKind.COUNT:
			return "";
	}
}

fn String file_icon_theme_name(FileIconTheme theme)
{
	if (theme == FileIconTheme.MATERIAL) return "material";
	if (theme == FileIconTheme.VSCODE) return "vscode";
	return "";
}

fn String ui_icon_theme_name()
{
	return g_ui_theme == UiIconTheme.CODICONS ? "codicons" : "vector";
}

fn String file_icon_theme_current_name()
{
	String name = file_icon_theme_name(g_file_theme);
	return name.len > 0 ? name : "none";
}

fn RLTexture2D load_texture_from(String path)
{
	RLTexture2D texture = { };
	if (!file::exists(path)) return texture;
	texture = rl::load_texture(path.zstr_tcopy());
	if (texture.is_valid()) texture.set_filter(RLTextureFilter.BILINEAR);
	return texture;
}

fn String file_icon_name(FileIconTheme theme, String path)
{
	language::Language lang = language::language_for_path(path);
	String fallback         = theme == FileIconTheme.VSCODE ? "default_file" : "file";
	switch (lang)
	{
		case language::Language.C3:
			return theme == FileIconTheme.VSCODE ? "file_type_c3" : "c3";
		case language::Language.C:
			return theme == FileIconTheme.VSCODE ? "file_type_c" : "c";
		case language::Language.PYTHON:
			return theme == FileIconTheme.VSCODE ? "file_type_python" : "python";
		case language::Language.JAVASCRIPT:
			return theme == FileIconTheme.VSCODE ? "file_type_js" : "javascript";
		case language::Language.GO:
			return theme == FileIconTheme.VSCODE ? "file_type_go" : "go";
		case language::Language.RUST:
			return theme == FileIconTheme.VSCODE ? "file_type_rust" : "rust";
		case language::Language.ZIG:
			return theme == FileIconTheme.VSCODE ? "file_type_zig" : "zig";
		case language::Language.ODIN:
			return theme == FileIconTheme.VSCODE ? "default_file" : "odin";
		case language::Language.V:
			return fallback;
		case language::Language.NIM:
			return theme == FileIconTheme.VSCODE ? "file_type_nim" : "nim";
		case language::Language.CPP:
			return theme == FileIconTheme.VSCODE ? "file_type_cpp" : "cpp";
		case language::Language.JAVA:
			return theme == FileIconTheme.VSCODE ? "file_type_java" : "java";
		case language::Language.KOTLIN:
			return theme == FileIconTheme.VSCODE ? "file_type_kotlin" : "kotlin";
		case language::Language.SCALA:
			return theme == FileIconTheme.VSCODE ? "file_type_scala" : "scala";
		case language::Language.C_SHARP:
			return theme == FileIconTheme.VSCODE ? "file_type_csharp" : "csharp";
		case language::Language.TYPESCRIPT:
		case language::Language.TSX:
			return theme == FileIconTheme.VSCODE ? "file_type_typescript" : "typescript";
		case language::Language.CSS:
			return theme == FileIconTheme.VSCODE ? "file_type_css" : "css";
		case language::Language.HTML:
			return theme == FileIconTheme.VSCODE ? "file_type_html" : "html";
		case language::Language.LUA:
			return theme == FileIconTheme.VSCODE ? "file_type_lua" : "lua";
		case language::Language.PHP:
			return theme == FileIconTheme.VSCODE ? "file_type_php" : "php";
		case language::Language.RUBY:
			return theme == FileIconTheme.VSCODE ? "file_type_ruby" : "ruby";
		case language::Language.R:
			return theme == FileIconTheme.VSCODE ? "file_type_r" : "r";
		case language::Language.JULIA:
			return theme == FileIconTheme.VSCODE ? "file_type_julia" : "julia";
		case language::Language.HASKELL:
			return theme == FileIconTheme.VSCODE ? "file_type_haskell" : "haskell";
		case language::Language.GLEAM:
			return theme == FileIconTheme.VSCODE ? "file_type_gleam" : "gleam";
		case language::Language.ERLANG:
			return theme == FileIconTheme.VSCODE ? "file_type_erlang" : "erlang";
		case language::Language.ELIXIR:
			return theme == FileIconTheme.VSCODE ? "file_type_elixir" : "elixir";
		case language::Language.DART:
			return theme == FileIconTheme.VSCODE ? "file_type_dartlang" : "dart";
		case language::Language.MARKDOWN:
		case language::Language.MARKDOWN_INLINE:
			return theme == FileIconTheme.VSCODE ? "file_type_markdown" : "markdown";
		default:
			return fallback;
	}
}

fn RLTexture2D load_icon_texture(String theme, String name)
{
	RLTexture2D texture = { };
	@pool()
	{
		if (g_override_dir.len > 0)
		{
			String path = string::format(tmem, "%s/%s/%s.png", g_override_dir, theme, name);
			texture = load_texture_from(path);
		}
		if (!texture.is_valid())
		{
			String path = string::format(tmem, "assets/icons/%s/%s.png", theme, name);
			texture = load_texture_from(path);
		}
		if (!texture.is_valid())
		{
			String exe  = rl::get_application_directory().str_view();
			String path = string::format(tmem, "%sassets/icons/%s/%s.png", exe, theme, name);
			texture = load_texture_from(path);
		}
	};
	return texture;
}

fn RLTexture2D ui_texture(IconKind icon)
{
	int index = (int)icon;
	if (index < 0 || index >= ICON_COUNT) return { };
	if (g_ui_loaded[index]) return g_ui_textures[index];
	g_ui_loaded[index] = true;
	String name = codicon_name(icon);
	if (name.len > 0) g_ui_textures[index] = load_icon_texture("codicons", name);
	return g_ui_textures[index];
}

fn RLTexture2D file_texture(FileIconTheme theme, String name)
{
	if (g_file_theme == FileIconTheme.NONE || name.len == 0) return { };
	String theme_name = file_icon_theme_name(theme);
	for (sz i = 0; i < g_file_icons.len(); i++)
	{
		FileIconCacheEntry entry = g_file_icons[i];
		if (entry.theme.compare_to(theme_name) == 0 && entry.name.compare_to(name) == 0) return entry.texture;
	}
	RLTexture2D texture = load_icon_texture(theme_name, name);
	g_file_icons.push({ .theme = theme_name, .name = name, .texture = texture, .valid = texture.is_valid() });
	return texture;
}

fn bool draw_file(String path, Rect box, RLColor tint)
{
	if (g_file_theme == FileIconTheme.NONE) return false;
	String name         = file_icon_name(g_file_theme, path);
	RLTexture2D texture = file_texture(g_file_theme, name);
	if (!texture.is_valid()) return false;
	rl::draw_texture_pro(
		texture,
		{ .x = 0.0f, .y = 0.0f, .width = (float)texture.width, .height = (float)texture.height },
		box,
		{ 0.0f, 0.0f },
		0.0f,
		tint
	);
	return true;
}

fn String folder_icon_name(FileIconTheme theme, bool open)
{
	if (theme == FileIconTheme.NONE) return "";
	if (theme == FileIconTheme.VSCODE) return open ? "default_folder_opened" : "default_folder";
	return open ? "folder-open" : "folder";
}

fn bool draw_folder(bool open, Rect box, RLColor tint)
{
	if (g_file_theme == FileIconTheme.NONE) return false;
	String name         = folder_icon_name(g_file_theme, open);
	RLTexture2D texture = file_texture(g_file_theme, name);
	if (!texture.is_valid()) return false;
	rl::draw_texture_pro(
		texture,
		{ .x = 0.0f, .y = 0.0f, .width = (float)texture.width, .height = (float)texture.height },
		box,
		{ 0.0f, 0.0f },
		0.0f,
		tint
	);
	return true;
}

fn void seg(Rect b, float x1, float y1, float x2, float y2, float stroke, RLColor color)
{
	rl::draw_line_ex(
		{ b.x + b.width * x1, b.y + b.height * y1 },
		{ b.x + b.width * x2, b.y + b.height * y2 },
		stroke,
		color
	);
}

fn void draw(IconKind icon, Rect b, RLColor color)
{
	if (g_ui_theme == UiIconTheme.CODICONS)
	{
		RLTexture2D texture = ui_texture(icon);
		if (texture.is_valid())
		{
			rl::draw_texture_pro(
				texture,
				{ .x = 0.0f, .y = 0.0f, .width = (float)texture.width, .height = (float)texture.height },
				b,
				{ 0.0f, 0.0f },
				0.0f,
				color
			);
			return;
		}
	}
	float stroke = math::max(1.0f, b.width * 0.09f);
	switch (icon)
	{
		case IconKind.NEW_FILE:
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.25f, b.y + b.height * 0.12f, b.width * 0.5f, b.height * 0.76f },
				stroke,
				color
			);
			seg(b, 0.5f, 0.35f, 0.5f, 0.65f, stroke, color);
			seg(b, 0.35f, 0.5f, 0.65f, 0.5f, stroke, color);
		case IconKind.OPEN:
			seg(b, 0.15f, 0.3f, 0.45f, 0.3f, stroke, color);
			seg(b, 0.45f, 0.3f, 0.55f, 0.4f, stroke, color);
			seg(b, 0.55f, 0.4f, 0.85f, 0.4f, stroke, color);
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.15f, b.y + b.height * 0.4f, b.width * 0.7f, b.height * 0.4f },
				stroke,
				color
			);
		case IconKind.SAVE:
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.18f, b.y + b.height * 0.15f, b.width * 0.64f, b.height * 0.7f },
				stroke,
				color
			);
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.33f, b.y + b.height * 0.5f, b.width * 0.34f, b.height * 0.35f },
				stroke,
				color
			);
			rl::draw_rectangle_rec(
				{ b.x + b.width * 0.35f, b.y + b.height * 0.18f, b.width * 0.3f, b.height * 0.22f },
				color
			);
		case IconKind.SETTINGS:
			rl::draw_ring_lines(
				{ b.x + b.width * 0.5f, b.y + b.height * 0.5f },
				b.width * 0.18f,
				b.width * 0.28f,
				0.0f,
				360.0f,
				24,
				color
			);
			for (int i = 0; i < 4; i++)
			{
				float a = (float)i * math::PI * 0.5f;
				seg(
					b,
					0.5f + math::cos(a) * 0.28f,
					0.5f + math::sin(a) * 0.28f,
					0.5f + math::cos(a) * 0.42f,
					0.5f + math::sin(a) * 0.42f,
					stroke,
					color
				);
			}
		case IconKind.CONNECTIONS:
			rl::draw_circle_lines_v({ b.x + b.width * 0.25f, b.y + b.height * 0.35f }, b.width * 0.12f, color);
			rl::draw_circle_lines_v({ b.x + b.width * 0.75f, b.y + b.height * 0.65f }, b.width * 0.12f, color);
			seg(b, 0.34f, 0.42f, 0.66f, 0.58f, stroke, color);
		case IconKind.ARROWS:
			seg(b, 0.2f, 0.25f, 0.8f, 0.25f, stroke, color);
			seg(b, 0.2f, 0.5f, 0.65f, 0.5f, stroke, color);
			seg(b, 0.2f, 0.75f, 0.5f, 0.75f, stroke, color);
			rl::draw_circle_v({ b.x + b.width * 0.86f, b.y + b.height * 0.25f }, stroke * 0.7f, color);
			rl::draw_circle_v({ b.x + b.width * 0.71f, b.y + b.height * 0.5f }, stroke * 0.7f, color);
			rl::draw_circle_v({ b.x + b.width * 0.56f, b.y + b.height * 0.75f }, stroke * 0.7f, color);
		case IconKind.QUIT:
			rl::draw_ring_lines(
				{ b.x + b.width * 0.5f, b.y + b.height * 0.52f },
				b.width * 0.28f,
				b.width * 0.38f,
				40.0f,
				320.0f,
				24,
				color
			);
			seg(b, 0.5f, 0.12f, 0.5f, 0.5f, stroke, color);
		case IconKind.PREVIEW:
			rl::draw_ring_lines(
				{ b.x + b.width * 0.5f, b.y + b.height * 0.5f },
				b.width * 0.1f,
				b.width * 0.34f,
				0.0f,
				360.0f,
				24,
				color
			);
			rl::draw_circle_v({ b.x + b.width * 0.5f, b.y + b.height * 0.5f }, b.width * 0.08f, color);
		case IconKind.MAXIMIZE:
			seg(b, 0.2f, 0.4f, 0.2f, 0.2f, stroke, color);
			seg(b, 0.2f, 0.2f, 0.4f, 0.2f, stroke, color);
			seg(b, 0.8f, 0.4f, 0.8f, 0.2f, stroke, color);
			seg(b, 0.8f, 0.2f, 0.6f, 0.2f, stroke, color);
			seg(b, 0.2f, 0.6f, 0.2f, 0.8f, stroke, color);
			seg(b, 0.2f, 0.8f, 0.4f, 0.8f, stroke, color);
			seg(b, 0.8f, 0.6f, 0.8f, 0.8f, stroke, color);
			seg(b, 0.8f, 0.8f, 0.6f, 0.8f, stroke, color);
		case IconKind.RESTORE:
			seg(b, 0.38f, 0.38f, 0.2f, 0.2f, stroke, color);
			seg(b, 0.2f, 0.2f, 0.2f, 0.42f, stroke, color);
			seg(b, 0.38f, 0.38f, 0.42f, 0.2f, stroke, color);
			seg(b, 0.62f, 0.38f, 0.8f, 0.2f, stroke, color);
			seg(b, 0.8f, 0.2f, 0.8f, 0.42f, stroke, color);
			seg(b, 0.62f, 0.38f, 0.58f, 0.2f, stroke, color);
			seg(b, 0.38f, 0.62f, 0.2f, 0.8f, stroke, color);
			seg(b, 0.2f, 0.8f, 0.2f, 0.58f, stroke, color);
			seg(b, 0.38f, 0.62f, 0.42f, 0.8f, stroke, color);
			seg(b, 0.62f, 0.62f, 0.8f, 0.8f, stroke, color);
			seg(b, 0.8f, 0.8f, 0.8f, 0.58f, stroke, color);
			seg(b, 0.62f, 0.62f, 0.58f, 0.8f, stroke, color);
		case IconKind.MINIMIZE:
			seg(b, 0.3f, 0.5f, 0.5f, 0.7f, stroke, color);
			seg(b, 0.5f, 0.7f, 0.7f, 0.5f, stroke, color);
		case IconKind.CLOSE:
			seg(b, 0.25f, 0.25f, 0.75f, 0.75f, stroke, color);
			seg(b, 0.75f, 0.25f, 0.25f, 0.75f, stroke, color);
		case IconKind.SEARCH:
			rl::draw_ring_lines(
				{ b.x + b.width * 0.42f, b.y + b.height * 0.42f },
				b.width * 0.18f,
				b.width * 0.28f,
				0.0f,
				360.0f,
				24,
				color
			);
			seg(b, 0.62f, 0.62f, 0.82f, 0.82f, stroke, color);
		case IconKind.PROBLEMS:
			seg(b, 0.5f, 0.15f, 0.15f, 0.82f, stroke, color);
			seg(b, 0.15f, 0.82f, 0.85f, 0.82f, stroke, color);
			seg(b, 0.85f, 0.82f, 0.5f, 0.15f, stroke, color);
			seg(b, 0.5f, 0.38f, 0.5f, 0.62f, stroke, color);
			rl::draw_circle_v({ b.x + b.width * 0.5f, b.y + b.height * 0.72f }, stroke * 0.55f, color);
		case IconKind.SYMBOLS:
			seg(b, 0.38f, 0.15f, 0.28f, 0.22f, stroke, color);
			seg(b, 0.28f, 0.22f, 0.28f, 0.78f, stroke, color);
			seg(b, 0.28f, 0.78f, 0.38f, 0.85f, stroke, color);
			seg(b, 0.62f, 0.15f, 0.72f, 0.22f, stroke, color);
			seg(b, 0.72f, 0.22f, 0.72f, 0.78f, stroke, color);
			seg(b, 0.72f, 0.78f, 0.62f, 0.85f, stroke, color);
		case IconKind.CONSOLE:
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.1f, b.y + b.height * 0.18f, b.width * 0.8f, b.height * 0.64f },
				stroke,
				color
			);
			seg(b, 0.28f, 0.42f, 0.4f, 0.5f, stroke, color);
			seg(b, 0.4f, 0.5f, 0.28f, 0.58f, stroke, color);
			seg(b, 0.52f, 0.62f, 0.7f, 0.62f, stroke, color);
		case IconKind.KEYBOARD:
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.08f, b.y + b.height * 0.25f, b.width * 0.84f, b.height * 0.5f },
				stroke,
				color
			);
			for (int i = 0; i < 3; i++)
			{
				rl::draw_circle_v(
					{ b.x + b.width * (0.25f + (float)i * 0.25f), b.y + b.height * 0.48f },
					stroke * 0.45f,
					color
				);
			}
			seg(b, 0.3f, 0.62f, 0.7f, 0.62f, stroke, color);
		case IconKind.THEME:
			rl::draw_ring_lines(
				{ b.x + b.width * 0.5f, b.y + b.height * 0.5f },
				b.width * 0.34f,
				b.width * 0.42f,
				0.0f,
				360.0f,
				24,
				color
			);
			rl::draw_circle_sector(
				{ b.x + b.width * 0.5f, b.y + b.height * 0.5f },
				b.width * 0.33f,
				270.0f,
				90.0f,
				16,
				color
			);
		case IconKind.PLAY:
			rl::draw_triangle(
				{ b.x + b.width * 0.35f, b.y + b.height * 0.2f },
				{ b.x + b.width * 0.35f, b.y + b.height * 0.8f },
				{ b.x + b.width * 0.8f, b.y + b.height * 0.5f },
				color
			);
		case IconKind.STOP:
			rl::draw_rectangle_rec(
				{ b.x + b.width * 0.28f, b.y + b.height * 0.28f, b.width * 0.44f, b.height * 0.44f },
				color
			);
		case IconKind.TRASH:
			seg(b, 0.25f, 0.28f, 0.75f, 0.28f, stroke, color);
			seg(b, 0.4f, 0.18f, 0.6f, 0.18f, stroke, color);
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.3f, b.y + b.height * 0.3f, b.width * 0.4f, b.height * 0.55f },
				stroke,
				color
			);
		case IconKind.CHEVRON_DOWN:
			seg(b, 0.25f, 0.4f, 0.5f, 0.65f, stroke, color);
			seg(b, 0.5f, 0.65f, 0.75f, 0.4f, stroke, color);
		case IconKind.CHEVRON_RIGHT:
			seg(b, 0.4f, 0.25f, 0.65f, 0.5f, stroke, color);
			seg(b, 0.65f, 0.5f, 0.4f, 0.75f, stroke, color);
		case IconKind.GIT:
			rl::draw_circle_lines_v({ b.x + b.width * 0.3f, b.y + b.height * 0.22f }, b.width * 0.1f, color);
			rl::draw_circle_lines_v({ b.x + b.width * 0.7f, b.y + b.height * 0.22f }, b.width * 0.1f, color);
			rl::draw_circle_lines_v({ b.x + b.width * 0.5f, b.y + b.height * 0.8f }, b.width * 0.1f, color);
			seg(b, 0.3f, 0.32f, 0.3f, 0.58f, stroke, color);
			seg(b, 0.3f, 0.58f, 0.5f, 0.72f, stroke, color);
			seg(b, 0.7f, 0.32f, 0.7f, 0.48f, stroke, color);
			seg(b, 0.7f, 0.48f, 0.5f, 0.62f, stroke, color);
		case IconKind.COUNT:
			break;
	}
}