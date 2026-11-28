module yun::mods;

import libc;
import lua54::lua;
import raylib6::rl;
import std::collections::list;
import std::core::mem;
import std::io;
import std::io::path;
import std::math;
import std::os::env;
import yun::card;
import yun::config;
import yun::editor;
import yun::language;
import yun::notify;
import yun::project;
import yun::text;
import yun::ui;
import yun::version;

const int MOD_API_VERSION              =  1;
const int MOD_FAILURE_LIMIT            =  3;
const int MOD_FRAME_OVER_LIMIT         =  5;
const usz MOD_MEMORY_CAP               =  8 * 1024 * 1024;
const int MOD_INSTRUCTION_BUDGET       =  2_000_000;
const int MOD_FRAME_INSTRUCTION_BUDGET =  200_000;
const int MOD_HOOK_STEP                =  1000;
const int MOD_DRAW_LIMIT               =  4096;
const int MOD_TEXT_LIMIT               =  4096;
const int MOD_BUFFER_COPY_MAX          =  1024 * 1024;
const int MOD_SELECTION_COPY_MAX       =  4096;
const int MOD_MAX_LOADED               =  128;
const int MOD_MAX_TEXTURES             =  16;
const int MOD_MAX_HANDLERS             =  256;
const int MOD_MAX_COMMANDS             =  256;
const int MOD_MAX_MENU_ITEMS           =  32;
const double MOD_FRAME_TIME_BUDGET     =  0.008;
const int MOD_PALETTE_BASE             = -1000;

enum ModEvent : int
{
	STARTUP,
	FILE_OPEN,
	FILE_SAVE,
	FILE_CLOSE,
	COMMAND,
	SELECTION,
	UPDATE,
	DRAW,
	INPUT,
}

enum ModSource : int
{
	GLOBAL,
	PROJECT,
}

enum ModOverlay : int
{
	BELOW,
	ABOVE,
}

struct ModRuntime
{
	Mods* host;
	int mod_index;
	usz used;
	usz cap;
	bool alloc_failed;
	int hook_ticks;
	int hook_limit;
	int draw_calls;
	bool drawing;
}

struct ModTexture
{
	String path;
	RLTexture2D texture;
}

struct ModHandler
{
	ModEvent event;
	int ref;
}

struct LuaMod
{
	String name;
	String version;
	String path;
	String dir;
	ModSource source;
	LuaState* state;
	ModRuntime runtime;
	List{ModHandler} handlers;
	List{ModTexture} textures;
	int error_count;
	int over_budget;
	int frame_skip;
	bool disabled;
	bool started;
	ModOverlay overlay;
}

struct ModCommand
{
	String id;
	String label;
	int ref;
	int mod;
}

struct ModMenuItem
{
	String label;
	int ref;
	int mod;
}

struct ModsHost
{
	project::Project* project;
	notify::Notifier* notifier;
	config::Config* config;
	bool* project_open;
}

struct Mods
{
	Allocator allocator;
	ModsHost host;
	List{LuaMod*} mods;
	List{ModCommand} commands;
	List{ModMenuItem} menu_items;
	List{String} skipped;
	String project_root;
	bool enabled;
	bool allow_render;
	bool allow_input;
	bool loaded_global;
	bool loaded_project;
	bool in_dispatch;
	usz memory_cap;
	int instruction_budget;
	int frame_instruction_budget;
}

struct ModScanEntry
{
	String path;
	String name;
	int priority;
}

fn String mods_global_dir(Allocator allocator)
{
	Path? config_dir = env::get_config_dir(allocator);
	if (catch err = config_dir) return "";
	Path? dir = config_dir.append(allocator, "yun");
	if (catch err = dir) return "";
	Path? mods = dir.append(allocator, "mods");
	if (catch err = mods) return "";
	return (String)mods;
}

fn String path_parent(String path)
{
	usz slash  = 0;
	bool found = false;
	for (usz i = 0; i < path.len; i++)
	{
		if (path[i] == '/' || path[i] == '\\')
		{
			slash = i;
			found = true;
		}
	}
	if (!found) return ".";
	return path[0:slash];
}

fn void* mod_alloc(void* ud, void* ptr, usz osize, usz nsize)
{
	ModRuntime* runtime = (ModRuntime*)ud;
	if (!runtime) return null;
	if (nsize == 0)
	{
		if (ptr) libc::free(ptr);
		runtime.used = runtime.used >= osize ? runtime.used - osize : 0;
		return null;
	}
	usz base = ptr ? osize : 0;
	usz held = runtime.used >= base ? runtime.used - base : 0;
	if (nsize > runtime.cap || held > runtime.cap - nsize)
	{
		runtime.alloc_failed = true;
		return null;
	}
	void* result = ptr ? libc::realloc(ptr, nsize) : libc::malloc(nsize);
	if (!result)
	{
		runtime.alloc_failed = true;
		return null;
	}
	runtime.used = held + nsize;
	return result;
}

fn void mod_hook(LuaState* l, LuaDebug* ar)
{
	(void)ar;
	void* ud;
	lua::getallocf(l, &ud);
	ModRuntime* runtime = (ModRuntime*)ud;
	if (!runtime) return;
	runtime.hook_ticks++;
	if (runtime.hook_ticks > runtime.hook_limit)
	{
		runtime.hook_ticks = runtime.hook_limit;
		(void)lua::l_error(l, "instruction budget exceeded");
	}
}

fn int mod_traceback(LuaState* l)
{
	ZString message = lua::tostring(l, 1);
	if (!message) message = (ZString)"(error)";
	lua::l_traceback(l, l, message, 1);
	return 1;
}

fn ModRuntime* current_runtime(LuaState* l)
{
	void* ud;
	lua::getallocf(l, &ud);
	return (ModRuntime*)ud;
}

fn LuaMod* runtime_mod(ModRuntime* runtime)
{
	if (!runtime || !runtime.host) return null;
	if (runtime.mod_index < 0 || runtime.mod_index >= (int)runtime.host.mods.len()) return null;
	return runtime.host.mods[runtime.mod_index];
}

fn bool mod_render_allowed(ModRuntime* runtime)
{
	return runtime && runtime.host && runtime.host.allow_render;
}

fn bool mod_input_allowed(ModRuntime* runtime)
{
	return runtime && runtime.host && runtime.host.allow_input;
}

fn bool require_render(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	if (!runtime || !runtime.host || !runtime.host.allow_render)
	{
		(void)lua::l_error(l, "render capability is disabled (mods.allow_render)");
		return false;
	}
	if (!runtime.drawing)
	{
		(void)lua::l_error(l, "drawing is only allowed in on_draw");
		return false;
	}
	if (runtime.draw_calls >= MOD_DRAW_LIMIT)
	{
		(void)lua::l_error(l, "draw budget exceeded");
		return false;
	}
	runtime.draw_calls++;
	return true;
}

fn String lua_string(LuaState* l, int index, ZString what)
{
	usz len;
	ZString text = lua::tolstring(l, index, &len);
	if (!text)
	{
		(void)lua::l_error(l, what);
		return "";
	}
	return (String)text[0:len];
}

fn bool lua_number(LuaState* l, int index, ZString what, double* out)
{
	int is_number   = 0;
	LuaNumber value = lua::tonumberx(l, index, &is_number);
	if (!is_number || math::is_nan(value) || math::is_inf(value))
	{
		(void)lua::l_error(l, what);
		return false;
	}
	*out = value;
	return true;
}

fn float clamp_coordinate(double value)
{
	double clamped = value.clamp(-1000000.0, 1000000.0);
	return (float)clamped;
}

fn int color_byte(LuaState* l, int table, ZString field, int fallback)
{
	lua::getfield(l, table, field);
	int is_number    = 0;
	LuaInteger value = lua::tointegerx(l, -1, &is_number);
	lua::pop(l, 1);
	if (!is_number) return fallback;
	if (value < 0) return 0;
	if (value > 255) return 255;
	return (int)value;
}

fn RLColor color_arg(LuaState* l, int index)
{
	if (lua::type(l, index) == lua::TTABLE)
	{
		int table = lua::absindex(l, index);
		int r     = color_byte(l, table, "r", 255);
		int g     = color_byte(l, table, "g", 255);
		int b     = color_byte(l, table, "b", 255);
		int a     = color_byte(l, table, "a", 255);
		return { (char)r, (char)g, (char)b, (char)a };
	}
	int is_number     = 0;
	LuaInteger packed = lua::tointegerx(l, index, &is_number);
	if (!is_number)
	{
		(void)lua::l_error(l, "expected a color (0xRRGGBBAA or {r,g,b,a})");
		return { (char)255, (char)255, (char)255, (char)255 };
	}
	if (packed < 0) packed = 0;
	if (packed <= 0xFFFFFF)
	{
		return { (char)((packed >> 16) & 0xFF), (char)((packed >> 8) & 0xFF), (char)(packed & 0xFF), (char)255 };
	}
	return {
		(char)((packed >> 24) & 0xFF),
		(char)((packed >> 16) & 0xFF),
		(char)((packed >> 8) & 0xFF),
		(char)(packed & 0xFF),
	};
}

fn void push_string(LuaState* l, String text)
{
	if (text.len == 0)
	{
		lua::pushstring(l, (ZString)"");
		return;
	}
	lua::pushlstring(l, (ZString)text.ptr, text.len);
}

fn void push_card_table(LuaState* l, project::Project* project, int index)
{
	lua::createtable(l, 0, 14);
	if (!project || index < 0 || index >= (int)project.cards.len())
	{
		lua::pushboolean(l, 0);
		lua::setfield(l, -2, "valid");
		return;
	}
	FileCard* card = &project.cards[index];
	lua::pushboolean(l, 1);
	lua::setfield(l, -2, "valid");
	lua::pushinteger(l, index);
	lua::setfield(l, -2, "id");
	push_string(l, (String)card.path);
	lua::setfield(l, -2, "path");
	push_string(l, card.name);
	lua::setfield(l, -2, "name");
	language::Language lang = language::language_for_path((String)card.path);
	String lang_name        = language::LANGUAGES[(int)lang].name;
	push_string(l, lang_name);
	lua::setfield(l, -2, "language");
	lua::pushboolean(l, (int)(card.open));
	lua::setfield(l, -2, "open");
	lua::pushboolean(l, (int)(card.dirty));
	lua::setfield(l, -2, "dirty");
	lua::pushboolean(l, (int)(card.missing));
	lua::setfield(l, -2, "missing");
	lua::pushboolean(l, (int)(index == project.focused));
	lua::setfield(l, -2, "focused");
	lua::pushinteger(l, (LuaInteger)card.cursor);
	lua::setfield(l, -2, "cursor");
	lua::pushinteger(l, (LuaInteger)card.selection_anchor);
	lua::setfield(l, -2, "selection_anchor");
	if (card.buffer)
	{
		lua::pushinteger(l, (LuaInteger)card.buffer.line_count());
		lua::setfield(l, -2, "line_count");
		lua::pushinteger(l, (LuaInteger)card.buffer.length());
		lua::setfield(l, -2, "text_length");
	}
	else
	{
		lua::pushinteger(l, 0);
		lua::setfield(l, -2, "line_count");
		lua::pushinteger(l, 0);
		lua::setfield(l, -2, "text_length");
	}
}

fn void push_selection_table(LuaState* l, project::Project* project)
{
	lua::createtable(l, 0, 10);
	if (!project || project.focused < 0 || project.focused >= (int)project.cards.len())
	{
		lua::pushboolean(l, 0);
		lua::setfield(l, -2, "valid");
		return;
	}
	FileCard* card = &project.cards[project.focused];
	lua::pushboolean(l, 1);
	lua::setfield(l, -2, "valid");
	lua::pushinteger(l, project.focused);
	lua::setfield(l, -2, "card");
	push_string(l, (String)card.path);
	lua::setfield(l, -2, "path");
	usz start = 0;
	usz end   = 0;
	if (card.buffer)
	{
		editor::selection_range(card.selection_anchor, card.cursor, &start, &end);
	}
	lua::pushinteger(l, (LuaInteger)start);
	lua::setfield(l, -2, "start");
	lua::pushinteger(l, (LuaInteger)end);
	lua::setfield(l, -2, "end");
	lua::pushinteger(l, (LuaInteger)card.selection_anchor);
	lua::setfield(l, -2, "anchor");
	lua::pushinteger(l, (LuaInteger)card.cursor);
	lua::setfield(l, -2, "cursor");
	if (card.buffer && end > start)
	{
		usz take = math::min(end - start, (usz)MOD_SELECTION_COPY_MAX);
		@pool()
		{
			String slice = card.buffer.slice(start, take, tmem);
			push_string(l, slice);
		};
	}
	else
	{
		lua::pushstring(l, (ZString)"");
	}
	lua::setfield(l, -2, "text");
}

fn int api_project(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	if (!runtime || !runtime.host || !runtime.host.host.project || !runtime.host.host.project_open
		|| !*runtime.host.host.project_open)
	{
		lua::pushnil(l);
		return 1;
	}
	project::Project* project = runtime.host.host.project;
	lua::createtable(l, 0, 5);
	push_string(l, (String)project.root);
	lua::setfield(l, -2, "root");
	push_string(l, ((Path)project.root).basename());
	lua::setfield(l, -2, "name");
	lua::pushinteger(l, (LuaInteger)project.cards.len());
	lua::setfield(l, -2, "card_count");
	lua::pushinteger(l, project.focused);
	lua::setfield(l, -2, "focused");
	lua::pushinteger(l, project.selected);
	lua::setfield(l, -2, "selected");
	return 1;
}

fn int api_card(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	if (!runtime || !runtime.host || !runtime.host.host.project)
	{
		lua::pushnil(l);
		return 1;
	}
	int is_number    = 0;
	LuaInteger index = lua::tointegerx(l, 1, &is_number);
	if (!is_number)
	{
		(void)lua::l_error(l, "yun.card expects an integer id");
		return 0;
	}
	if (index < 0 || index >= (LuaInteger)runtime.host.host.project.cards.len())
	{
		lua::pushnil(l);
		return 1;
	}
	push_card_table(l, runtime.host.host.project, (int)index);
	return 1;
}

fn int api_cards(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	if (!runtime || !runtime.host || !runtime.host.host.project)
	{
		lua::createtable(l, 0, 0);
		return 1;
	}
	project::Project* project = runtime.host.host.project;
	int count                 = (int)project.cards.len();
	if (count > 512) count = 512;
	lua::createtable(l, count, 0);
	for (int i = 0; i < count; i++)
	{
		push_card_table(l, project, i);
		lua::rawseti(l, -2, (LuaInteger)(i + 1));
	}
	return 1;
}

fn int api_focused(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	if (!runtime || !runtime.host || !runtime.host.host.project || runtime.host.host.project.focused < 0)
	{
		lua::pushnil(l);
		return 1;
	}
	push_card_table(l, runtime.host.host.project, runtime.host.host.project.focused);
	return 1;
}

fn int api_buffer(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	if (!runtime || !runtime.host || !runtime.host.host.project)
	{
		lua::pushnil(l);
		return 1;
	}
	int is_number = 0;
	LuaInteger id = lua::tointegerx(l, 1, &is_number);
	if (!is_number)
	{
		(void)lua::l_error(l, "yun.buffer expects an integer card id");
		return 0;
	}
	project::Project* project = runtime.host.host.project;
	if (id < 0 || id >= (LuaInteger)project.cards.len())
	{
		lua::pushnil(l);
		return 1;
	}
	FileCard* card = &project.cards[(int)id];
	if (!card.buffer)
	{
		lua::pushnil(l);
		return 1;
	}
	LuaInteger start  = 0;
	LuaInteger length = (LuaInteger)MOD_BUFFER_COPY_MAX;
	if (lua::gettop(l) >= 2 && !lua::isnoneornil(l, 2))
	{
		start = lua::tointegerx(l, 2, &is_number);
		if (!is_number)
		{
			(void)lua::l_error(l, "buffer start must be an integer");
			return 0;
		}
	}
	if (lua::gettop(l) >= 3 && !lua::isnoneornil(l, 3))
	{
		length = lua::tointegerx(l, 3, &is_number);
		if (!is_number)
		{
			(void)lua::l_error(l, "buffer length must be an integer");
			return 0;
		}
	}
	if (start < 0) start = 0;
	if (length < 0) length = 0;
	usz total  = card.buffer.length();
	usz offset = (usz)start;
	if (offset > total) offset = total;
	usz requested = (usz)length;
	usz take      = math::min(requested, (usz)MOD_BUFFER_COPY_MAX);
	if (take > total - offset) take = total - offset;
	@pool()
	{
		String slice = card.buffer.slice(offset, take, tmem);
		push_string(l, slice);
	};
	lua::pushboolean(l, (int)(take < requested));
	return 2;
}

fn int api_buffer_length(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	if (!runtime || !runtime.host || !runtime.host.host.project)
	{
		lua::pushinteger(l, 0);
		return 1;
	}
	int is_number = 0;
	LuaInteger id = lua::tointegerx(l, 1, &is_number);
	if (!is_number)
	{
		(void)lua::l_error(l, "yun.buffer_length expects an integer card id");
		return 0;
	}
	project::Project* project = runtime.host.host.project;
	if (id < 0 || id >= (LuaInteger)project.cards.len())
	{
		lua::pushinteger(l, 0);
		return 1;
	}
	FileCard* card = &project.cards[(int)id];
	lua::pushinteger(l, card.buffer ? (LuaInteger)card.buffer.length() : 0);
	return 1;
}

fn int api_selection(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	push_selection_table(l, runtime && runtime.host ? runtime.host.host.project : null);
	return 1;
}

fn int api_notify(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	if (!runtime || !runtime.host || !runtime.host.host.notifier) return 0;
	String message = lua_string(l, 1, "yun.notify expects a message string");
	if (message.len > 4096)
	{
		(void)lua::l_error(l, "notification is too long");
		return 0;
	}
	runtime.host.host.notifier.push(message);
	return 0;
}

fn int api_log(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	LuaMod* mod         = runtime_mod(runtime);
	if (!mod) return 0;
	String level   = "info";
	String message = "";
	int top        = lua::gettop(l);
	if (top >= 2)
	{
		level = lua_string(l, 1, "yun.log level must be a string");
		message = lua_string(l, 2, "yun.log message must be a string");
	}
	else if (top == 1)
	{
		message = lua_string(l, 1, "yun.log message must be a string");
	}
	if (level.len > 16) level = (String)level[0:16];
	if (message.len > 8192) message = (String)message[0:8192];
	@pool()
	{
		io::printfn("mod %s [%s]: %s", mod.name.zstr_tcopy(), level.zstr_tcopy(), message.zstr_tcopy());
	};
	return 0;
}

fn int api_has_capability(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	String name         = lua_string(l, 1, "yun.has_capability expects a capability name");
	bool allowed        = false;
	if (name.compare_to("render") == 0)
	{
		allowed = mod_render_allowed(runtime);
	}
	else if (name.compare_to("input") == 0)
	{
		allowed = mod_input_allowed(runtime);
	}
	else if (name.compare_to("notify") == 0 || name.compare_to("read") == 0)
	{
		allowed = true;
	}
	lua::pushboolean(l, (int)allowed);
	return 1;
}

fn int api_capabilities(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	lua::createtable(l, 0, 4);
	lua::pushboolean(l, 1);
	lua::setfield(l, -2, "read");
	lua::pushboolean(l, 1);
	lua::setfield(l, -2, "notify");
	lua::pushboolean(l, (int)mod_render_allowed(runtime));
	lua::setfield(l, -2, "render");
	lua::pushboolean(l, (int)mod_input_allowed(runtime));
	lua::setfield(l, -2, "input");
	return 1;
}

fn int api_set_overlay(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	LuaMod* mod         = runtime_mod(runtime);
	if (!mod) return 0;
	String layer = lua_string(l, 1, "yun.set_overlay expects 'above' or 'below'");
	if (layer.compare_to("above") == 0)
	{
		mod.overlay = ModOverlay.ABOVE;
	}
	else if (layer.compare_to("below") == 0)
	{
		mod.overlay = ModOverlay.BELOW;
	}
	else
	{
		(void)lua::l_error(l, "overlay layer must be 'above' or 'below'");
		return 0;
	}
	return 0;
}

fn int api_overlay(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	LuaMod* mod         = runtime_mod(runtime);
	lua::pushstring(l, mod && mod.overlay == ModOverlay.BELOW ? (ZString)"below" : (ZString)"above");
	return 1;
}

fn int api_screen_size(LuaState* l)
{
	lua::createtable(l, 0, 2);
	lua::pushinteger(l, rl::get_screen_width());
	lua::setfield(l, -2, "width");
	lua::pushinteger(l, rl::get_screen_height());
	lua::setfield(l, -2, "height");
	return 1;
}

fn int api_mouse(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	if (!mod_input_allowed(runtime)) return 0;
	RLVector2 position = rl::get_mouse_position();
	lua::createtable(l, 0, 8);
	lua::pushnumber(l, position[0]);
	lua::setfield(l, -2, "x");
	lua::pushnumber(l, position[1]);
	lua::setfield(l, -2, "y");
	lua::pushnumber(l, rl::get_mouse_wheel_move());
	lua::setfield(l, -2, "wheel");
	lua::pushboolean(l, (int)(rl::is_mouse_button_down(rl::RLMouseButton.LEFT)));
	lua::setfield(l, -2, "left");
	lua::pushboolean(l, (int)(rl::is_mouse_button_down(rl::RLMouseButton.RIGHT)));
	lua::setfield(l, -2, "right");
	lua::pushboolean(l, (int)(rl::is_mouse_button_down(rl::RLMouseButton.MIDDLE)));
	lua::setfield(l, -2, "middle");
	lua::pushboolean(l, (int)(rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT)));
	lua::setfield(l, -2, "left_pressed");
	lua::pushboolean(l, (int)(rl::is_mouse_button_pressed(rl::RLMouseButton.RIGHT)));
	lua::setfield(l, -2, "right_pressed");
	return 1;
}

fn int key_from_arg(LuaState* l, int index)
{
	if (lua::type(l, index) == lua::TNUMBER)
	{
		int is_number    = 0;
		LuaInteger value = lua::tointegerx(l, index, &is_number);
		if (is_number) return value >= 0 && value < 512 ? (int)value : -1;
	}
	String name = lua_string(l, index, "key must be a name string or a raylib key code");
	if (name.len == 1)
	{
		char c = name[0];
		if (c >= 'a' && c <= 'z') return (int)c - 32;
		if (c >= 'A' && c <= 'Z') return (int)c;
		if (c >= '0' && c <= '9') return (int)c;
	}
	if (name.compare_to("space") == 0) return (int)rl::RLKeyboardKey.SPACE;
	if (name.compare_to("escape") == 0) return (int)rl::RLKeyboardKey.ESCAPE;
	if (name.compare_to("enter") == 0) return (int)rl::RLKeyboardKey.ENTER;
	if (name.compare_to("tab") == 0) return (int)rl::RLKeyboardKey.TAB;
	if (name.compare_to("backspace") == 0) return (int)rl::RLKeyboardKey.BACKSPACE;
	if (name.compare_to("delete") == 0) return (int)rl::RLKeyboardKey.DELETE;
	if (name.compare_to("insert") == 0) return (int)rl::RLKeyboardKey.INSERT;
	if (name.compare_to("home") == 0) return (int)rl::RLKeyboardKey.HOME;
	if (name.compare_to("end") == 0) return (int)rl::RLKeyboardKey.END;
	if (name.compare_to("page_up") == 0) return (int)rl::RLKeyboardKey.PAGE_UP;
	if (name.compare_to("page_down") == 0) return (int)rl::RLKeyboardKey.PAGE_DOWN;
	if (name.compare_to("left") == 0) return (int)rl::RLKeyboardKey.LEFT;
	if (name.compare_to("right") == 0) return (int)rl::RLKeyboardKey.RIGHT;
	if (name.compare_to("up") == 0) return (int)rl::RLKeyboardKey.UP;
	if (name.compare_to("down") == 0) return (int)rl::RLKeyboardKey.DOWN;
	if (name.compare_to("left_shift") == 0) return (int)rl::RLKeyboardKey.LEFT_SHIFT;
	if (name.compare_to("right_shift") == 0) return (int)rl::RLKeyboardKey.RIGHT_SHIFT;
	if (name.compare_to("left_control") == 0) return (int)rl::RLKeyboardKey.LEFT_CONTROL;
	if (name.compare_to("right_control") == 0) return (int)rl::RLKeyboardKey.RIGHT_CONTROL;
	if (name.compare_to("left_alt") == 0) return (int)rl::RLKeyboardKey.LEFT_ALT;
	if (name.compare_to("right_alt") == 0) return (int)rl::RLKeyboardKey.RIGHT_ALT;
	if (name.len >= 2 && name.len <= 3 && (name[0] == 'f' || name[0] == 'F'))
	{
		int number  = 0;
		bool digits = true;
		for (usz i = 1; i < name.len; i++)
		{
			char c = name[i];
			if (c < '0' || c > '9') digits = false;
			number = number * 10 + (int)(c - '0');
		}
		if (digits && number >= 1 && number <= 12) return (int)rl::RLKeyboardKey.F1 + number - 1;
	}
	return -1;
}

fn int api_is_key_down(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	if (!mod_input_allowed(runtime))
	{
		lua::pushboolean(l, 0);
		return 1;
	}
	int key = key_from_arg(l, 1);
	lua::pushboolean(l, (int)(key >= 0 && rl::is_key_down((rl::RLKeyboardKey)key)));
	return 1;
}

fn int api_is_key_pressed(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	if (!mod_input_allowed(runtime))
	{
		lua::pushboolean(l, 0);
		return 1;
	}
	int key = key_from_arg(l, 1);
	lua::pushboolean(l, (int)(key >= 0 && rl::is_key_pressed((rl::RLKeyboardKey)key)));
	return 1;
}

fn int api_add_menu_item(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	LuaMod* mod         = runtime_mod(runtime);
	if (!mod || !runtime.host) return 0;
	String label = lua_string(l, 1, "yun.add_menu_item expects a label string");
	if (label.len == 0 || label.len > 256)
	{
		(void)lua::l_error(l, "menu label must be between 1 and 256 bytes");
		return 0;
	}
	if (lua::type(l, 2) != lua::TFUNCTION)
	{
		(void)lua::l_error(l, "yun.add_menu_item expects a function");
		return 0;
	}
	if (runtime.host.menu_items.len() >= (sz)MOD_MAX_MENU_ITEMS)
	{
		(void)lua::l_error(l, "too many mod menu items");
		return 0;
	}
	lua::pushvalue(l, 2);
	int ref    = lua::l_ref(l, lua::REGISTRYINDEX);
	Mods* host = runtime.host;
	host.menu_items.push({ .label = label.copy(host.allocator), .ref = ref, .mod = runtime.mod_index });
	return 0;
}

fn int api_register_command(LuaState* l)
{
	ModRuntime* runtime = current_runtime(l);
	LuaMod* mod         = runtime_mod(runtime);
	if (!mod || !runtime.host) return 0;
	String id    = lua_string(l, 1, "yun.register_command expects an id string");
	String label = lua_string(l, 2, "yun.register_command expects a label string");
	if (id.len == 0 || id.len > 128)
	{
		(void)lua::l_error(l, "command id must be between 1 and 128 bytes");
		return 0;
	}
	if (label.len == 0) label = id;
	if (label.len > 256)
	{
		(void)lua::l_error(l, "command label must be at most 256 bytes");
		return 0;
	}
	if (lua::type(l, 3) != lua::TFUNCTION)
	{
		(void)lua::l_error(l, "yun.register_command expects a function");
		return 0;
	}
	Mods* host = runtime.host;
	if (host.commands.len() >= (sz)MOD_MAX_COMMANDS)
	{
		(void)lua::l_error(l, "too many mod commands");
		return 0;
	}
	for (sz i = 0; i < host.commands.len(); i++)
	{
		if (host.commands[i].id.compare_to(id) == 0)
		{
			(void)lua::l_error(l, "command id is already registered");
			return 0;
		}
	}
	lua::pushvalue(l, 3);
	int ref = lua::l_ref(l, lua::REGISTRYINDEX);
	host.commands.push(
		{
			.id = id.copy(host.allocator),
			.label = label.copy(host.allocator),
			.ref = ref,
			.mod = runtime.mod_index,
		}
	);
	return 0;
}

fn int register_handler(LuaState* l, ModEvent event)
{
	ModRuntime* runtime = current_runtime(l);
	LuaMod* mod         = runtime_mod(runtime);
	if (!mod) return 0;
	if (lua::type(l, 1) != lua::TFUNCTION)
	{
		(void)lua::l_error(l, "event handler must be a function");
		return 0;
	}
	if (mod.handlers.len() >= (sz)MOD_MAX_HANDLERS)
	{
		(void)lua::l_error(l, "too many event handlers");
		return 0;
	}
	lua::pushvalue(l, 1);
	int ref = lua::l_ref(l, lua::REGISTRYINDEX);
	mod.handlers.push({ .event = event, .ref = ref });
	return 0;
}

fn int api_on_startup(LuaState* l)
{
	return register_handler(l, ModEvent.STARTUP);
}
fn int api_on_file_open(LuaState* l)
{
	return register_handler(l, ModEvent.FILE_OPEN);
}
fn int api_on_file_save(LuaState* l)
{
	return register_handler(l, ModEvent.FILE_SAVE);
}
fn int api_on_file_close(LuaState* l)
{
	return register_handler(l, ModEvent.FILE_CLOSE);
}
fn int api_on_command(LuaState* l)
{
	return register_handler(l, ModEvent.COMMAND);
}
fn int api_on_selection(LuaState* l)
{
	return register_handler(l, ModEvent.SELECTION);
}
fn int api_on_update(LuaState* l)
{
	return register_handler(l, ModEvent.UPDATE);
}
fn int api_on_draw(LuaState* l)
{
	return register_handler(l, ModEvent.DRAW);
}
fn int api_on_input(LuaState* l)
{
	return register_handler(l, ModEvent.INPUT);
}

fn int api_read_only(LuaState* l)
{
	(void)lua::l_error(l, "the yun API table is read-only");
	return 0;
}

fn bool valid_asset_path(String path)
{
	if (path.len == 0) return false;
	if (path[0] == '/' || path[0] == '\\') return false;
	for (usz i = 0; i < path.len; i++)
	{
		char c = path[i];
		if (c == ':') return false;
		if (c == '.' && i + 1 < path.len && path[i + 1] == '.')
		{
			bool left  = i == 0 || path[i - 1] == '/' || path[i - 1] == '\\';
			bool right = i + 2 >= path.len || path[i + 2] == '/' || path[i + 2] == '\\';
			if (left && right) return false;
		}
	}
	return true;
}

fn RLTexture2D* texture_for(LuaState* l, ModRuntime* runtime, LuaMod* mod, int path_index)
{
	String requested = lua_string(l, path_index, "asset path must be a string");
	if (!valid_asset_path(requested))
	{
		(void)lua::l_error(l, "asset path must stay inside the mod folder");
		return null;
	}
	Path? resolved = ((Path)mod.dir).append(runtime.host.allocator, requested);
	if (catch err = resolved)
	{
		(void)lua::l_error(l, "invalid asset path");
		return null;
	}
	String full = (String)resolved;
	for (sz i = 0; i < mod.textures.len(); i++)
	{
		if (mod.textures[i].path.compare_to(full) == 0)
		{
			full.free(runtime.host.allocator);
			return &mod.textures[i].texture;
		}
	}
	if (mod.textures.len() >= (sz)MOD_MAX_TEXTURES)
	{
		full.free(runtime.host.allocator);
		(void)lua::l_error(l, "too many mod textures");
		return null;
	}
	if (!path::is_file((Path)full))
	{
		full.free(runtime.host.allocator);
		(void)lua::l_error(l, "asset not found");
		return null;
	}
	@pool()
	{
		RLTexture2D texture = rl::load_texture(full.zstr_tcopy());
		if (!texture.is_valid())
		{
			full.free(runtime.host.allocator);
			(void)lua::l_error(l, "could not load asset");
			return null;
		}
		texture.set_filter(RLTextureFilter.BILINEAR);
		mod.textures.push({ .path = full, .texture = texture });
	};
	return &mod.textures[mod.textures.len() - 1].texture;
}

fn Rect rect_args(LuaState* l, bool* ok)
{
	*ok = false;
	double x, y, w, h;
	if (!lua_number(l, 1, "x must be a number", &x)) return { };
	if (!lua_number(l, 2, "y must be a number", &y)) return { };
	if (!lua_number(l, 3, "width must be a number", &w)) return { };
	if (!lua_number(l, 4, "height must be a number", &h)) return { };
	if (w < 0)
	{
		x += w;
		w = -w;
	}
	if (h < 0)
	{
		y += h;
		h = -h;
	}
	*ok = true;
	return {
		.x = clamp_coordinate(x),
		.y = clamp_coordinate(y),
		.width = clamp_coordinate(w),
		.height = clamp_coordinate(h)
	};
}

fn int api_draw_clear(LuaState* l)
{
	if (!require_render(l)) return 0;
	RLColor color = color_arg(l, 1);
	rl::draw_rectangle(0, 0, rl::get_screen_width(), rl::get_screen_height(), color);
	return 0;
}

fn int api_draw_rect(LuaState* l)
{
	if (!require_render(l)) return 0;
	bool ok;
	Rect rect = rect_args(l, &ok);
	if (!ok) return 0;
	RLColor color = color_arg(l, 5);
	bool filled   = lua::gettop(l) >= 6 ? lua::toboolean(l, 6) != 0 : true;
	if (filled)
	{
		rl::draw_rectangle_rec(rect, color);
	}
	else
	{
		rl::draw_rectangle_lines_ex(rect, 1.0f, color);
	}
	return 0;
}

fn int api_draw_rect_lines(LuaState* l)
{
	if (!require_render(l)) return 0;
	bool ok;
	Rect rect = rect_args(l, &ok);
	if (!ok) return 0;
	RLColor color    = color_arg(l, 5);
	double thickness = 1.0;
	if (lua::gettop(l) >= 6 && !lua_number(l, 6, "thickness must be a number", &thickness)) return 0;
	float line = math::max(0.1f, clamp_coordinate(thickness));
	rl::draw_rectangle_lines_ex(rect, line, color);
	return 0;
}

fn int api_draw_line(LuaState* l)
{
	if (!require_render(l)) return 0;
	double x1, y1, x2, y2;
	if (!lua_number(l, 1, "x1 must be a number", &x1)) return 0;
	if (!lua_number(l, 2, "y1 must be a number", &y1)) return 0;
	if (!lua_number(l, 3, "x2 must be a number", &x2)) return 0;
	if (!lua_number(l, 4, "y2 must be a number", &y2)) return 0;
	RLColor color    = color_arg(l, 5);
	double thickness = 1.0;
	if (lua::gettop(l) >= 6 && !lua_number(l, 6, "thickness must be a number", &thickness)) return 0;
	float line = math::max(0.1f, clamp_coordinate(thickness));
	rl::draw_line_ex(
		{ clamp_coordinate(x1), clamp_coordinate(y1) },
		{ clamp_coordinate(x2), clamp_coordinate(y2) },
		line,
		color
	);
	return 0;
}

fn int api_draw_circle(LuaState* l)
{
	if (!require_render(l)) return 0;
	double x, y, radius;
	if (!lua_number(l, 1, "x must be a number", &x)) return 0;
	if (!lua_number(l, 2, "y must be a number", &y)) return 0;
	if (!lua_number(l, 3, "radius must be a number", &radius)) return 0;
	RLColor color = color_arg(l, 4);
	bool filled   = lua::gettop(l) >= 5 ? lua::toboolean(l, 5) != 0 : true;
	float r       = math::max(0.0f, clamp_coordinate(radius));
	if (filled)
	{
		rl::draw_circle_v({ clamp_coordinate(x), clamp_coordinate(y) }, r, color);
	}
	else
	{
		rl::draw_circle_lines_v({ clamp_coordinate(x), clamp_coordinate(y) }, r, color);
	}
	return 0;
}

fn int api_draw_text(LuaState* l)
{
	if (!require_render(l)) return 0;
	usz len;
	ZString raw = lua::tolstring(l, 1, &len);
	if (!raw)
	{
		(void)lua::l_error(l, "text must be a string");
		return 0;
	}
	if (len > MOD_TEXT_LIMIT)
	{
		(void)lua::l_error(l, "text is too long");
		return 0;
	}
	double x, y, size;
	if (!lua_number(l, 2, "x must be a number", &x)) return 0;
	if (!lua_number(l, 3, "y must be a number", &y)) return 0;
	if (!lua_number(l, 4, "size must be a number", &size)) return 0;
	RLColor color   = color_arg(l, 5);
	float font_size = (float)size.clamp(4.0, 256.0);
	@pool()
	{
		rl::draw_text_ex(
			ui::font(),
			((String)raw[0:len]).zstr_tcopy(),
			{ clamp_coordinate(x), clamp_coordinate(y) },
			(float)font_size,
			0.0f,
			color
		);
	};
	return 0;
}

fn int draw_texture_args(LuaState* l)
{
	if (!require_render(l)) return 0;
	ModRuntime* runtime = current_runtime(l);
	LuaMod* mod         = runtime_mod(runtime);
	if (!mod) return 0;
	RLTexture2D* texture = texture_for(l, runtime, mod, 1);
	if (!texture) return 0;
	double x, y, w, h;
	if (!lua_number(l, 2, "x must be a number", &x)) return 0;
	if (!lua_number(l, 3, "y must be a number", &y)) return 0;
	if (!lua_number(l, 4, "width must be a number", &w)) return 0;
	if (!lua_number(l, 5, "height must be a number", &h)) return 0;
	RLColor tint = { (char)255, (char)255, (char)255, (char)255 };
	if (lua::gettop(l) >= 6) tint = color_arg(l, 6);
	Rect dest = {
		.x = clamp_coordinate(x),
		.y = clamp_coordinate(y),
		.width = clamp_coordinate(w),
		.height = clamp_coordinate(h),
	};
	if (dest.width <= 0.0f || dest.height <= 0.0f) return 0;
	rl::draw_texture_pro(
		*texture,
		{ .x = 0.0f, .y = 0.0f, .width = (float)texture.width, .height = (float)texture.height },
		dest,
		{ 0.0f, 0.0f },
		0.0f,
		tint
	);
	return 0;
}

fn int api_draw_image(LuaState* l)
{
	return draw_texture_args(l);
}
fn int api_draw_texture(LuaState* l)
{
	return draw_texture_args(l);
}

fn void set_api_function(LuaState* l, ZString name, LuaCFunction function)
{
	lua::pushcclosure(l, function, 0);
	lua::setfield(l, -2, name);
}

fn void open_restricted_libs(LuaState* l)
{
	lua::open_base(l);
	lua::pop(l, 1);
	lua::open_string(l);
	lua::setglobal(l, "string");
	lua::open_table(l);
	lua::setglobal(l, "table");
	lua::open_math(l);
	lua::setglobal(l, "math");
	lua::open_utf8(l);
	lua::setglobal(l, "utf8");
	lua::pushnil(l);
	lua::setglobal(l, "io");
	lua::pushnil(l);
	lua::setglobal(l, "os");
	lua::pushnil(l);
	lua::setglobal(l, "package");
	lua::pushnil(l);
	lua::setglobal(l, "debug");
	lua::pushnil(l);
	lua::setglobal(l, "require");
	lua::pushnil(l);
	lua::setglobal(l, "dofile");
	lua::pushnil(l);
	lua::setglobal(l, "loadfile");
	lua::pushnil(l);
	lua::setglobal(l, "load");
	lua::pushnil(l);
	lua::setglobal(l, "print");
	lua::pushnil(l);
	lua::setglobal(l, "warn");
}

fn void register_api(LuaState* l, LuaMod* mod)
{
	lua::createtable(l, 0, 40);
	lua::pushinteger(l, MOD_API_VERSION);
	lua::setfield(l, -2, "api_version");
	push_string(l, version::APP_VERSION);
	lua::setfield(l, -2, "host_version");
	push_string(l, mod.name);
	lua::setfield(l, -2, "mod_name");
	set_api_function(l, "project", &api_project);
	set_api_function(l, "cards", &api_cards);
	set_api_function(l, "card", &api_card);
	set_api_function(l, "focused", &api_focused);
	set_api_function(l, "selection", &api_selection);
	set_api_function(l, "buffer", &api_buffer);
	set_api_function(l, "buffer_length", &api_buffer_length);
	set_api_function(l, "notify", &api_notify);
	set_api_function(l, "log", &api_log);
	set_api_function(l, "has_capability", &api_has_capability);
	set_api_function(l, "capabilities", &api_capabilities);
	set_api_function(l, "add_menu_item", &api_add_menu_item);
	set_api_function(l, "register_command", &api_register_command);
	set_api_function(l, "on_startup", &api_on_startup);
	set_api_function(l, "on_file_open", &api_on_file_open);
	set_api_function(l, "on_file_save", &api_on_file_save);
	set_api_function(l, "on_file_close", &api_on_file_close);
	set_api_function(l, "on_command", &api_on_command);
	set_api_function(l, "on_selection", &api_on_selection);
	set_api_function(l, "on_update", &api_on_update);
	set_api_function(l, "on_draw", &api_on_draw);
	set_api_function(l, "on_input", &api_on_input);
	set_api_function(l, "set_overlay", &api_set_overlay);
	set_api_function(l, "overlay", &api_overlay);
	set_api_function(l, "screen_size", &api_screen_size);
	set_api_function(l, "mouse", &api_mouse);
	set_api_function(l, "is_key_down", &api_is_key_down);
	set_api_function(l, "is_key_pressed", &api_is_key_pressed);

	lua::createtable(l, 0, 7);
	set_api_function(l, "clear", &api_draw_clear);
	set_api_function(l, "rect", &api_draw_rect);
	set_api_function(l, "rect_lines", &api_draw_rect_lines);
	set_api_function(l, "line", &api_draw_line);
	set_api_function(l, "circle", &api_draw_circle);
	set_api_function(l, "text", &api_draw_text);
	set_api_function(l, "image", &api_draw_image);
	set_api_function(l, "texture", &api_draw_texture);
	lua::setfield(l, -2, "draw");

	lua::createtable(l, 0, 2);
	set_api_function(l, "__newindex", &api_read_only);
	lua::pushboolean(l, 0);
	lua::setfield(l, -2, "__metatable");
	lua::setmetatable(l, -2);
	lua::setglobal(l, "yun");
}

fn void LuaMod.init(&self, Mods* owner, String name, String version_text, String path, ModSource source)
{
	self.name = name;
	self.version = version_text;
	self.path = path;
	self.dir = path_parent(path).copy(owner.allocator);
	self.source = source;
	self.handlers.init(owner.allocator);
	self.textures.init(owner.allocator);
	self.overlay = ModOverlay.ABOVE;
	self.runtime.cap = owner.memory_cap;
}

fn void LuaMod.destroy(&self, Mods* owner)
{
	if (self.state)
	{
		for (sz i = 0; i < self.textures.len(); i++)
		{
			if (self.textures[i].texture.is_valid()) rl::unload_texture(self.textures[i].texture);
			if (self.textures[i].path.len) self.textures[i].path.free(owner.allocator);
		}
		lua::sethook(self.state, null, 0, 0);
		lua::close(self.state);
		self.state = null;
	}
	self.textures.clear();
	self.textures.free();
	self.handlers.clear();
	self.handlers.free();
	if (self.runtime.used != 0)
	{
		@pool()
		{
			io::printfn("mods: %s leaked %d bytes after close", self.name.zstr_tcopy(), (long)self.runtime.used);
		};
	}
	if (self.name.len) self.name.free(owner.allocator);
	if (self.version.len) self.version.free(owner.allocator);
	if (self.path.len) self.path.free(owner.allocator);
	if (self.dir.len) self.dir.free(owner.allocator);
	mem::free(self);
}

fn void Mods.init(&self, Allocator allocator, ModsHost host)
{
	self.allocator = allocator;
	self.host = host;
	self.mods.init(allocator);
	self.commands.init(allocator);
	self.menu_items.init(allocator);
	self.skipped.init(allocator);
	self.project_root = "";
	self.enabled = true;
	self.allow_render = false;
	self.allow_input = false;
	self.loaded_global = false;
	self.loaded_project = false;
	self.in_dispatch = false;
	self.memory_cap = MOD_MEMORY_CAP;
	self.instruction_budget = MOD_INSTRUCTION_BUDGET;
	self.frame_instruction_budget = MOD_FRAME_INSTRUCTION_BUDGET;
}

fn void Mods.apply_settings(&self, bool enabled, bool allow_render, bool allow_input)
{
	self.enabled = enabled;
	self.allow_render = allow_render;
	self.allow_input = allow_input;
}

fn void Mods.add_skipped(&self, String message)
{
	self.skipped.push(message);
}

fn void Mods.clear_commands(&self)
{
	for (sz i = 0; i < self.commands.len(); i++)
	{
		if (self.commands[i].id.len) self.commands[i].id.free(self.allocator);
		if (self.commands[i].label.len) self.commands[i].label.free(self.allocator);
	}
	self.commands.clear();
	for (sz i = 0; i < self.menu_items.len(); i++)
	{
		if (self.menu_items[i].label.len) self.menu_items[i].label.free(self.allocator);
	}
	self.menu_items.clear();
}

fn void Mods.unload_all(&self)
{
	for (sz i = 0; i < self.mods.len(); i++)
	{
		self.mods[i].destroy(self);
	}
	self.mods.clear();
	self.clear_commands();
	if (self.project_root.len) self.project_root.free(self.allocator);
	self.project_root = "";
	self.loaded_global = false;
	self.loaded_project = false;
}

fn void Mods.destroy(&self)
{
	self.unload_all();
	for (sz i = 0; i < self.skipped.len(); i++)
	{
		if (self.skipped[i].len) self.skipped[i].free(self.allocator);
	}
	self.skipped.clear();
	self.skipped.free();
	self.mods.free();
	self.commands.free();
	self.menu_items.free();
}

fn void add_scan_entry(List{ModScanEntry}* entries, String path, String name, int priority)
{
	for (sz i = 0; i < entries.len(); i++)
	{
		if (entries.get(i).name.compare_to(name) == 0)
		{
			if (priority > entries.get(i).priority)
			{
				entries.get_ref(i).path = path;
				entries.get_ref(i).priority = priority;
			}
			return;
		}
	}
	sz insert = entries.len();
	for (sz i = 0; i < entries.len(); i++)
	{
		if (name.compare_to(entries.get(i).name) < 0)
		{
			insert = i;
			break;
		}
	}
	entries.insert_at(insert, { .path = path, .name = name, .priority = priority });
}

fn void scan_mod_dir(List{ModScanEntry}* entries, String dir, int priority, Allocator allocator)
{
	if (dir.len == 0 || !path::is_dir((Path)dir)) return;
	PathList? files = path::ls(allocator, (Path)dir, no_dirs: true, mask: "*.lua");
	if (catch err = files) return;
	defer files.free();
	foreach (Path file : files)
	{
		String name = ((String)file).ends_with(".lua") ? ((String)file)[0:(usz)file.len - 4] : (String)file;
		Path? full  = ((Path)dir).append(allocator, (String)file);
		if (catch err = full) continue;
		add_scan_entry(entries, (String)full, name, priority);
	}
}

fn int Mods.mod_index_by_name(&self, String name)
{
	for (sz i = 0; i < self.mods.len(); i++)
	{
		if (self.mods[i].name.compare_to(name) == 0) return (int)i;
	}
	return -1;
}

fn void Mods.load_scan_entries(&self, List{ModScanEntry}* entries)
{
	for (sz i = 0; i < entries.len(); i++)
	{
		String name = entries.get(i).name;
		if (self.mod_index_by_name(name) >= 0)
		{
			@pool()
			{
				io::printfn("mods: skipped duplicate %s (already loaded)", name.zstr_tcopy());
			};
			continue;
		}
		(void)self.load_mod(entries.get(i)
			.path, name, entries.get(i).priority == 1 ? ModSource.PROJECT : ModSource.GLOBAL);
	}
}

fn void Mods.drop_mod_entries(&self, int mod_index)
{
	for (sz i = self.commands.len(); i > 0; i--)
	{
		if (self.commands[i - 1].mod != mod_index) continue;
		if (self.commands[i - 1].id.len) self.commands[i - 1].id.free(self.allocator);
		if (self.commands[i - 1].label.len) self.commands[i - 1].label.free(self.allocator);
		self.commands.remove_at(i - 1);
	}
	for (sz i = self.menu_items.len(); i > 0; i--)
	{
		if (self.menu_items[i - 1].mod != mod_index) continue;
		if (self.menu_items[i - 1].label.len) self.menu_items[i - 1].label.free(self.allocator);
		self.menu_items.remove_at(i - 1);
	}
}

fn bool Mods.load_mod(&self, String path, String name, ModSource source)
{
	if (self.mods.len() >= (sz)MOD_MAX_LOADED)
	{
		@pool()
		{
			io::printfn("mods: skipped %s: too many mods", path.zstr_tcopy());
		};
		self.add_skipped(string::format(self.allocator, "%s: too many mods", path));
		return false;
	}
	LuaMod* mod = mem::new(LuaMod);
	mod.init(self, name.copy(self.allocator), "unknown".copy(self.allocator), path.copy(self.allocator), source);
	mod.runtime.host = self;
	mod.runtime.cap = self.memory_cap;
	mod.runtime.mod_index = (int)self.mods.len();
	self.mods.push(mod);

	mod.state = lua::newstate(&mod_alloc, &mod.runtime);
	if (!mod.state)
	{
		@pool()
		{
			String reason = "could not create Lua state";
			io::printfn("mods: skipped %s: %s", path.zstr_tcopy(), reason.zstr_tcopy());
			self.add_skipped(string::format(self.allocator, "%s: %s", path, reason));
			if (self.host.notifier)
			{
				self.host.notifier.push(string::format(tmem, "Mod skipped: %s", name));
			}
		};
		self.drop_mod_entries((int)self.mods.len() - 1);
		self.mods.remove_at(self.mods.len() - 1);
		mod.destroy(self);
		return false;
	}
	open_restricted_libs(mod.state);
	register_api(mod.state, mod);
	lua::sethook(mod.state, &mod_hook, lua::MASKCOUNT, MOD_HOOK_STEP);
	mod.runtime.hook_limit = self.instruction_budget / MOD_HOOK_STEP;

	int base = lua::gettop(mod.state);
	lua::pushcfunction(mod.state, &mod_traceback);
	int msgh = base + 1;
	int status;
	@pool()
	{
		status = lua::l_loadfilex(mod.state, path.zstr_tcopy(), null);
		if (status != lua::OK)
		{
			ZString raw_error = lua::tostring(mod.state, -1);
			String message    = raw_error ? raw_error.str_view() : (String)"unknown error";
			io::printfn("mods: skipped %s: %s", path.zstr_tcopy(), message.zstr_tcopy());
			self.add_skipped(string::format(self.allocator, "%s: %s", path, message));
			if (self.host.notifier)
			{
				self.host.notifier.push(string::format(tmem, "Mod skipped: %s", name));
			}
			lua::settop(mod.state, base);
			self.drop_mod_entries((int)self.mods.len() - 1);
			self.mods.remove_at(self.mods.len() - 1);
			mod.destroy(self);
			return false;
		}
		status = lua::pcall(mod.state, 0, 1, msgh);
		if (status != lua::OK)
		{
			usz len;
			ZString error  = lua::tolstring(mod.state, -1, &len);
			String message = error ? (String)error[0:len] : (String)"unknown error";
			io::printfn("mods: skipped %s: %s", path.zstr_tcopy(), message.zstr_tcopy());
			self.add_skipped(string::format(self.allocator, "%s: %s", path, message));
			if (self.host.notifier)
			{
				self.host.notifier.push(string::format(tmem, "Mod skipped: %s", name));
			}
			lua::settop(mod.state, base);
			self.drop_mod_entries((int)self.mods.len() - 1);
			self.mods.remove_at(self.mods.len() - 1);
			mod.destroy(self);
			return false;
		}
		if (lua::type(mod.state, -1) == lua::TTABLE)
		{
			int result = lua::absindex(mod.state, -1);
			lua::getfield(mod.state, result, "version");
			if (lua::isstring(mod.state, -1))
			{
				usz len;
				ZString text = lua::tolstring(mod.state, -1, &len);
				if (text && len > 0 && len <= 256)
				{
					if (mod.version.len) mod.version.free(self.allocator);
					mod.version = ((String)text[0:len]).copy(self.allocator);
				}
			}
			lua::pop(mod.state, 1);
			lua::getfield(mod.state, result, "name");
			if (lua::isstring(mod.state, -1))
			{
				usz len;
				ZString text = lua::tolstring(mod.state, -1, &len);
				if (text && len > 0 && len <= 256)
				{
					if (mod.name.len) mod.name.free(self.allocator);
					mod.name = ((String)text[0:len]).copy(self.allocator);
				}
			}
			lua::pop(mod.state, 1);
		}
		if (mod.version.compare_to("unknown") == 0)
		{
			lua::getglobal(mod.state, "MOD_VERSION");
			if (lua::isstring(mod.state, -1))
			{
				usz len;
				ZString text = lua::tolstring(mod.state, -1, &len);
				if (text && len > 0 && len <= 256)
				{
					if (mod.version.len) mod.version.free(self.allocator);
					mod.version = ((String)text[0:len]).copy(self.allocator);
				}
			}
			lua::pop(mod.state, 1);
		}
		lua::getglobal(mod.state, "MOD_NAME");
		if (lua::isstring(mod.state, -1))
		{
			usz len;
			ZString text = lua::tolstring(mod.state, -1, &len);
			if (text && len > 0 && len <= 256)
			{
				if (mod.name.len) mod.name.free(self.allocator);
				mod.name = ((String)text[0:len]).copy(self.allocator);
			}
		}
		lua::pop(mod.state, 1);
		lua::settop(mod.state, base);

		io::printfn("mods: loaded %s v%s (%s)", mod.name.zstr_tcopy(), mod.version.zstr_tcopy(), path.zstr_tcopy());
	};
	return true;
}

fn void Mods.load_global(&self)
{
	if (!self.enabled || self.loaded_global) return;
	@pool()
	{
		String dir = mods_global_dir(tmem);
		if (dir.len > 0 && path::is_dir((Path)dir))
		{
			List{ModScanEntry} entries;
			entries.init(tmem);
			scan_mod_dir(&entries, dir, 0, tmem);
			self.load_scan_entries(&entries);
			entries.free();
		}
		else
		{
			io::printfn("mods: global mods folder not found (%s)", dir.zstr_tcopy());
		}
	};
	self.loaded_global = true;
}

fn void Mods.load_project(&self, String root)
{
	if (!self.enabled || self.loaded_project || root.len == 0) return;
	if (self.project_root.len) self.project_root.free(self.allocator);
	self.project_root = root.copy(self.allocator);
	self.loaded_project = true;
	@pool()
	{
		Path? base = ((Path)root).append(tmem, ".yun");
		if (catch err = base) return;
		Path? dir = base.append(tmem, "mods");
		if (catch err = dir) return;
		String mods_dir = (String)dir;
		if (!path::is_dir((Path)mods_dir)) return;
		List{ModScanEntry} entries;
		entries.init(tmem);
		scan_mod_dir(&entries, mods_dir, 1, tmem);
		self.load_scan_entries(&entries);
		entries.free();
	};
}

fn void Mods.ensure_loaded(&self, project::Project* project, bool include_project)
{
	if (!self.enabled) return;
	self.load_global();
	if (!include_project || !project) return;
	String root = (String)project.root;
	if (root.len == 0) return;
	if (self.loaded_project && self.project_root.compare_to(root) != 0)
	{
		self.unload_all();
		self.load_global();
	}
	self.load_project(root);
}

fn bool Mods.mod_ready(&self, LuaMod* mod)
{
	return mod && !mod.disabled && mod.state;
}

fn void Mods.report_error(&self, LuaMod* mod, String what, String message)
{
	mod.error_count++;
	@pool()
	{
		io::printfn("mod %s: %s failed: %s", mod.name.zstr_tcopy(), what.zstr_tcopy(), message.zstr_tcopy());
	};
	if (mod.runtime.alloc_failed || message.starts_with(
		"not enough memory"
	) || message.starts_with("instruction budget exceeded"))
	{
		self.disable_mod(mod, "limit exceeded");
		return;
	}
	if (mod.error_count >= MOD_FAILURE_LIMIT) self.disable_mod(mod, "repeated errors");
}

fn void Mods.disable_mod(&self, LuaMod* mod, String reason)
{
	if (mod.disabled) return;
	mod.disabled = true;
	@pool()
	{
		io::printfn("mods: disabled %s (%s)", mod.name.zstr_tcopy(), reason.zstr_tcopy());
		if (self.host.notifier)
		{
			self.host.notifier.push(string::format(tmem, "Mod disabled: %s", mod.name));
		}
	};
}

fn void Mods.set_call_budget(&self, LuaMod* mod, int budget)
{
	int steps = budget / MOD_HOOK_STEP;
	if (steps < 1) steps = 1;
	mod.runtime.hook_ticks = 0;
	mod.runtime.hook_limit = steps;
}

fn bool Mods.invoke(&self, LuaMod* mod, int ref, int nargs, String what, int budget)
{
	if (!self.mod_ready(mod)) return false;
	self.set_call_budget(mod, budget);
	LuaState* l   = mod.state;
	int base      = lua::gettop(l);
	int args_from = base - nargs + 1;
	lua::pushcfunction(l, &mod_traceback);
	lua::rawgeti(l, lua::REGISTRYINDEX, ref);
	if (lua::type(l, -1) != lua::TFUNCTION)
	{
		lua::settop(l, base - nargs);
		return false;
	}
	lua::rotate(l, args_from, 2);
	int status = lua::pcall(l, nargs, 0, args_from);
	if (status != lua::OK)
	{
		usz len;
		ZString error  = lua::tolstring(l, -1, &len);
		String message = error ? (String)error[0:len] : (String)"unknown error";
		self.report_error(mod, what, message);
		lua::settop(l, base);
		return false;
	}
	lua::settop(l, base);
	return true;
}

fn void Mods.dispatch_startup(&self)
{
	if (!self.enabled || self.in_dispatch) return;
	self.in_dispatch = true;
	defer self.in_dispatch = false;
	for (sz m = 0; m < self.mods.len(); m++)
	{
		LuaMod* mod = self.mods[m];
		if (!self.mod_ready(mod) || mod.started) continue;
		mod.started = true;
		sz handler_count = mod.handlers.len();
		for (sz i = 0; i < handler_count; i++)
		{
			if (mod.handlers[i].event != ModEvent.STARTUP) continue;
			lua::createtable(mod.state, 0, 3);
			lua::pushinteger(mod.state, MOD_API_VERSION);
			lua::setfield(mod.state, -2, "api_version");
			push_string(mod.state, version::APP_VERSION);
			lua::setfield(mod.state, -2, "host_version");
			push_string(mod.state, mod.name);
			lua::setfield(mod.state, -2, "mod_name");
			self.invoke(mod, mod.handlers[i].ref, 1, "on_startup", self.instruction_budget);
			if (mod.disabled) break;
		}
	}
}

fn void Mods.dispatch_file(&self, ModEvent event, int card)
{
	if (!self.enabled || self.in_dispatch) return;
	self.in_dispatch = true;
	defer self.in_dispatch = false;
	String what = event == ModEvent.FILE_OPEN ? "on_file_open"
		: event == ModEvent.FILE_SAVE ? "on_file_save"
		: "on_file_close";
	for (sz m = 0; m < self.mods.len(); m++)
	{
		LuaMod* mod = self.mods[m];
		if (!self.mod_ready(mod)) continue;
		sz handler_count = mod.handlers.len();
		for (sz i = 0; i < handler_count; i++)
		{
			if (mod.handlers[i].event != event) continue;
			push_card_table(mod.state, self.host.project, card);
			self.invoke(mod, mod.handlers[i].ref, 1, what, self.instruction_budget);
			if (mod.disabled) break;
		}
	}
}

fn void Mods.dispatch_file_open(&self, int card)
{
	self.dispatch_file(ModEvent.FILE_OPEN, card);
}
fn void Mods.dispatch_file_save(&self, int card)
{
	self.dispatch_file(ModEvent.FILE_SAVE, card);
}
fn void Mods.dispatch_file_close(&self, int card)
{
	self.dispatch_file(ModEvent.FILE_CLOSE, card);
}

fn void Mods.dispatch_command(&self, int id, String name, String label, int card)
{
	if (!self.enabled || self.in_dispatch) return;
	self.in_dispatch = true;
	defer self.in_dispatch = false;
	for (sz m = 0; m < self.mods.len(); m++)
	{
		LuaMod* mod = self.mods[m];
		if (!self.mod_ready(mod)) continue;
		sz handler_count = mod.handlers.len();
		for (sz i = 0; i < handler_count; i++)
		{
			if (mod.handlers[i].event != ModEvent.COMMAND) continue;
			LuaState* l = mod.state;
			lua::createtable(l, 0, 5);
			lua::pushinteger(l, id);
			lua::setfield(l, -2, "id");
			push_string(l, name);
			lua::setfield(l, -2, "name");
			push_string(l, label);
			lua::setfield(l, -2, "label");
			lua::pushinteger(l, card);
			lua::setfield(l, -2, "card");
			self.invoke(mod, mod.handlers[i].ref, 1, "on_command", self.instruction_budget);
			if (mod.disabled) break;
		}
	}
}

fn void Mods.dispatch_selection(&self, int card, usz anchor, usz cursor)
{
	if (!self.enabled || self.in_dispatch) return;
	self.in_dispatch = true;
	defer self.in_dispatch = false;
	for (sz m = 0; m < self.mods.len(); m++)
	{
		LuaMod* mod = self.mods[m];
		if (!self.mod_ready(mod)) continue;
		sz handler_count = mod.handlers.len();
		for (sz i = 0; i < handler_count; i++)
		{
			if (mod.handlers[i].event != ModEvent.SELECTION) continue;
			LuaState* l = mod.state;
			lua::createtable(l, 0, 8);
			lua::pushinteger(l, card);
			lua::setfield(l, -2, "card");
			usz start = anchor < cursor ? anchor : cursor;
			usz end   = anchor < cursor ? cursor : anchor;
			lua::pushinteger(l, (LuaInteger)start);
			lua::setfield(l, -2, "start");
			lua::pushinteger(l, (LuaInteger)end);
			lua::setfield(l, -2, "end");
			lua::pushinteger(l, (LuaInteger)anchor);
			lua::setfield(l, -2, "anchor");
			lua::pushinteger(l, (LuaInteger)cursor);
			lua::setfield(l, -2, "cursor");
			if (self.host.project && card >= 0 && card < (int)self.host.project.cards.len())
			{
				FileCard* file = &self.host.project.cards[card];
				push_string(l, (String)file.path);
				lua::setfield(l, -2, "path");
				if (file.buffer && end > start)
				{
					usz take = math::min(end - start, (usz)MOD_SELECTION_COPY_MAX);
					@pool()
					{
						String slice = file.buffer.slice(start, take, tmem);
						push_string(l, slice);
					};
				}
				else
				{
					lua::pushstring(l, (ZString)"");
				}
				lua::setfield(l, -2, "text");
			}
			self.invoke(mod, mod.handlers[i].ref, 1, "on_selection", self.instruction_budget);
			if (mod.disabled) break;
		}
	}
}

fn void push_input_table(LuaState* l)
{
	lua::createtable(l, 0, 10);
	RLVector2 mouse = rl::get_mouse_position();
	lua::createtable(l, 0, 2);
	lua::pushnumber(l, mouse[0]);
	lua::setfield(l, -2, "x");
	lua::pushnumber(l, mouse[1]);
	lua::setfield(l, -2, "y");
	lua::setfield(l, -2, "mouse");
	lua::pushnumber(l, rl::get_mouse_wheel_move());
	lua::setfield(l, -2, "wheel");
	lua::pushboolean(l, (int)(rl::is_mouse_button_down(rl::RLMouseButton.LEFT)));
	lua::setfield(l, -2, "left_down");
	lua::pushboolean(l, (int)(rl::is_mouse_button_down(rl::RLMouseButton.RIGHT)));
	lua::setfield(l, -2, "right_down");
	lua::pushboolean(l, (int)(rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT)));
	lua::setfield(l, -2, "left_pressed");
	lua::pushboolean(l, (int)(rl::is_mouse_button_pressed(rl::RLMouseButton.RIGHT)));
	lua::setfield(l, -2, "right_pressed");
}

fn void Mods.dispatch_input(&self)
{
	if (!self.enabled || self.in_dispatch || !self.allow_input) return;
	self.in_dispatch = true;
	defer self.in_dispatch = false;
	for (sz m = 0; m < self.mods.len(); m++)
	{
		LuaMod* mod = self.mods[m];
		if (!self.mod_ready(mod)) continue;
		sz handler_count = mod.handlers.len();
		for (sz i = 0; i < handler_count; i++)
		{
			if (mod.handlers[i].event != ModEvent.INPUT) continue;
			push_input_table(mod.state);
			self.invoke(mod, mod.handlers[i].ref, 1, "on_input", self.frame_instruction_budget);
			if (mod.disabled) break;
		}
	}
}

fn void Mods.dispatch_update(&self, float dt)
{
	if (!self.enabled || self.in_dispatch) return;
	self.in_dispatch = true;
	defer self.in_dispatch = false;
	for (sz m = 0; m < self.mods.len(); m++)
	{
		LuaMod* mod = self.mods[m];
		if (!self.mod_ready(mod)) continue;
		if (mod.frame_skip > 0)
		{
			mod.frame_skip--;
			continue;
		}
		double start = rl::get_time();
		mod.runtime.draw_calls = 0;
		sz handler_count = mod.handlers.len();
		for (sz i = 0; i < handler_count; i++)
		{
			if (mod.handlers[i].event != ModEvent.UPDATE) continue;
			lua::pushnumber(mod.state, dt);
			self.invoke(mod, mod.handlers[i].ref, 1, "on_update", self.frame_instruction_budget);
			if (mod.disabled) break;
		}
		if (rl::get_time() - start > MOD_FRAME_TIME_BUDGET && !mod.disabled)
		{
			mod.over_budget++;
			mod.frame_skip = 2;
			@pool()
			{
				io::printfn(
					"mod %s: on_update over frame budget (%.2f ms)",
					mod.name.zstr_tcopy(),
					(rl::get_time() - start) * 1000.0
				);
			};
			if (mod.over_budget == 1 && self.host.notifier)
			{
				@pool()
				{
					self.host.notifier.push(string::format(tmem, "Mod %s is over its frame budget", mod.name));
				};
			}
			if (mod.over_budget >= MOD_FRAME_OVER_LIMIT) self.disable_mod(mod, "repeated frame overruns");
		}
	}
}

fn void Mods.frame(&self, float dt)
{
	if (!self.enabled || self.in_dispatch) return;
	if (self.allow_input) self.dispatch_input();
	if (self.allow_render || self.allow_input) self.dispatch_update(dt);
}

fn void Mods.draw(&self, ModOverlay layer)
{
	if (!self.enabled || !self.allow_render || self.in_dispatch) return;
	self.in_dispatch = true;
	defer self.in_dispatch = false;
	for (sz m = 0; m < self.mods.len(); m++)
	{
		LuaMod* mod = self.mods[m];
		if (!self.mod_ready(mod) || mod.overlay != layer) continue;
		if (mod.frame_skip > 0)
		{
			mod.frame_skip--;
			continue;
		}
		double start = rl::get_time();
		mod.runtime.draw_calls = 0;
		mod.runtime.drawing = true;
		sz handler_count = mod.handlers.len();
		for (sz i = 0; i < handler_count; i++)
		{
			if (mod.handlers[i].event != ModEvent.DRAW) continue;
			self.invoke(mod, mod.handlers[i].ref, 0, "on_draw", self.frame_instruction_budget);
			if (mod.disabled) break;
		}
		mod.runtime.drawing = false;
		if (rl::get_time() - start > MOD_FRAME_TIME_BUDGET && !mod.disabled)
		{
			mod.over_budget++;
			mod.frame_skip = 2;
			@pool()
			{
				io::printfn(
					"mod %s: on_draw over frame budget (%.2f ms)",
					mod.name.zstr_tcopy(),
					(rl::get_time() - start) * 1000.0
				);
			};
			if (mod.over_budget == 1 && self.host.notifier)
			{
				@pool()
				{
					self.host.notifier.push(string::format(tmem, "Mod %s is over its frame budget", mod.name));
				};
			}
			if (mod.over_budget >= MOD_FRAME_OVER_LIMIT) self.disable_mod(mod, "repeated frame overruns");
		}
	}
}

fn int palette_encoded(int index)
{
	return MOD_PALETTE_BASE - index;
}

fn int palette_index(int encoded)
{
	return MOD_PALETTE_BASE - encoded;
}

fn int Mods.palette_count(&self)
{
	return (int)self.commands.len();
}

fn bool Mods.palette_available(&self, int index)
{
	if (!self.enabled || index < 0 || index >= (int)self.commands.len()) return false;
	int mod_index = self.commands[index].mod;
	if (mod_index < 0 || mod_index >= (int)self.mods.len()) return false;
	return !self.mods[mod_index].disabled;
}

fn String Mods.palette_label(&self, int index)
{
	if (index < 0 || index >= (int)self.commands.len()) return "";
	return self.commands[index].label;
}

fn bool Mods.run_palette(&self, int encoded)
{
	int index = palette_index(encoded);
	if (!self.palette_available(index)) return false;
	ModCommand command = self.commands[index];
	LuaMod* mod        = self.mods[command.mod];
	if (!self.mod_ready(mod)) return false;
	self.dispatch_command(-1, command.id, command.label, self.host.project ? self.host.project.focused : -1);
	if (!self.invoke(mod, command.ref, 0, "command", self.instruction_budget)) return false;
	return true;
}

fn int Mods.menu_count(&self)
{
	return (int)self.menu_items.len();
}

fn bool Mods.menu_available(&self, int index)
{
	if (!self.enabled || index < 0 || index >= (int)self.menu_items.len()) return false;
	int mod_index = self.menu_items[index].mod;
	if (mod_index < 0 || mod_index >= (int)self.mods.len()) return false;
	return !self.mods[mod_index].disabled;
}

fn String Mods.menu_label(&self, int index)
{
	if (index < 0 || index >= (int)self.menu_items.len()) return "";
	return self.menu_items[index].label;
}

fn bool Mods.run_menu_item(&self, int index)
{
	if (!self.menu_available(index)) return false;
	ModMenuItem item = self.menu_items[index];
	LuaMod* mod      = self.mods[item.mod];
	if (!self.mod_ready(mod)) return false;
	return self.invoke(mod, item.ref, 0, "menu item", self.instruction_budget);
}

fn usz Mods.memory_used(&self)
{
	usz total = 0;
	for (sz i = 0; i < self.mods.len(); i++) total += self.mods[i].runtime.used;
	return total;
}