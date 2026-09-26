module yun::keymap;

import raylib6::rl;
import std::collections::list;
import std::core::dstring;
import std::os::env;
import yun::commands;
import yun::config;

const uint MOD_CTRL    = 1;
const uint MOD_SHIFT   = 2;
const uint MOD_ALT     = 4;
const uint MOD_SUPER   = 8;
const int MAX_COMMANDS = 256;

struct Chord
{
	uint mods;
	rl::RLKeyboardKey key;
	bool valid;
}

struct Keymap
{
	Allocator allocator;
	Chord[MAX_COMMANDS] chords;
	String[MAX_COMMANDS] display;
	bool[MAX_COMMANDS] bound;
	List{String} warnings;
}

fn char lower_ascii(char c)
{
	if (c >= 'A' && c <= 'Z') return (char)(c + 32);
	return c;
}

fn bool equals_ci(String a, String b)
{
	if (a.len != b.len) return false;
	for (usz i = 0; i < a.len; i++)
	{
		if (lower_ascii(a[i]) != lower_ascii(b[i])) return false;
	}
	return true;
}

fn bool is_macos()
{
	$if env::DARWIN:
		return true;
	$else
		return false;
	$endif
}

fn bool key_from_name(String token, rl::RLKeyboardKey* out)
{
	if (token.len == 1)
	{
		char c = token[0];
		if (c >= 'a' && c <= 'z') c = (char)(c - 32);
		if (c >= 33 && c <= 126)
		{
			*out = (rl::RLKeyboardKey)(int)c;
			return true;
		}
		return false;
	}

	if (equals_ci(token, "enter") || equals_ci(token, "return"))
	{
		*out = rl::RLKeyboardKey.ENTER;
		return true;
	}
	if (equals_ci(token, "esc") || equals_ci(token, "escape"))
	{
		*out = rl::RLKeyboardKey.ESCAPE;
		return true;
	}
	if (equals_ci(token, "tab"))
	{
		*out = rl::RLKeyboardKey.TAB;
		return true;
	}
	if (equals_ci(token, "space"))
	{
		*out = rl::RLKeyboardKey.SPACE;
		return true;
	}
	if (equals_ci(token, "backspace"))
	{
		*out = rl::RLKeyboardKey.BACKSPACE;
		return true;
	}
	if (equals_ci(token, "delete") || equals_ci(token, "del"))
	{
		*out = rl::RLKeyboardKey.DELETE;
		return true;
	}
	if (equals_ci(token, "up"))
	{
		*out = rl::RLKeyboardKey.UP;
		return true;
	}
	if (equals_ci(token, "down"))
	{
		*out = rl::RLKeyboardKey.DOWN;
		return true;
	}
	if (equals_ci(token, "left"))
	{
		*out = rl::RLKeyboardKey.LEFT;
		return true;
	}
	if (equals_ci(token, "right"))
	{
		*out = rl::RLKeyboardKey.RIGHT;
		return true;
	}
	if (equals_ci(token, "home"))
	{
		*out = rl::RLKeyboardKey.HOME;
		return true;
	}
	if (equals_ci(token, "end"))
	{
		*out = rl::RLKeyboardKey.END;
		return true;
	}
	if (equals_ci(token, "pageup") || equals_ci(token, "pgup"))
	{
		*out = rl::RLKeyboardKey.PAGE_UP;
		return true;
	}
	if (equals_ci(token, "pagedown") || equals_ci(token, "pgdn"))
	{
		*out = rl::RLKeyboardKey.PAGE_DOWN;
		return true;
	}

	if (equals_ci(token, "insert") || equals_ci(token, "ins"))
	{
		*out = rl::RLKeyboardKey.INSERT;
		return true;
	}
	if (equals_ci(token, "caps_lock") || equals_ci(token, "capslock"))
	{
		*out = rl::RLKeyboardKey.CAPS_LOCK;
		return true;
	}
	if (equals_ci(token, "scroll_lock"))
	{
		*out = rl::RLKeyboardKey.SCROLL_LOCK;
		return true;
	}
	if (equals_ci(token, "num_lock"))
	{
		*out = rl::RLKeyboardKey.NUM_LOCK;
		return true;
	}
	if (equals_ci(token, "print_screen") || equals_ci(token, "printscreen"))
	{
		*out = rl::RLKeyboardKey.PRINT_SCREEN;
		return true;
	}
	if (equals_ci(token, "pause"))
	{
		*out = rl::RLKeyboardKey.PAUSE;
		return true;
	}
	if (equals_ci(token, "kb_menu") || equals_ci(token, "menu"))
	{
		*out = rl::RLKeyboardKey.KB_MENU;
		return true;
	}
	if (equals_ci(token, "kp_decimal"))
	{
		*out = rl::RLKeyboardKey.KP_DECIMAL;
		return true;
	}
	if (equals_ci(token, "kp_divide"))
	{
		*out = rl::RLKeyboardKey.KP_DIVIDE;
		return true;
	}
	if (equals_ci(token, "kp_multiply"))
	{
		*out = rl::RLKeyboardKey.KP_MULTIPLY;
		return true;
	}
	if (equals_ci(token, "kp_subtract"))
	{
		*out = rl::RLKeyboardKey.KP_SUBTRACT;
		return true;
	}
	if (equals_ci(token, "kp_add"))
	{
		*out = rl::RLKeyboardKey.KP_ADD;
		return true;
	}
	if (equals_ci(token, "kp_enter"))
	{
		*out = rl::RLKeyboardKey.KP_ENTER;
		return true;
	}
	if (equals_ci(token, "kp_equal"))
	{
		*out = rl::RLKeyboardKey.KP_EQUAL;
		return true;
	}
	if (token.len == 3 && lower_ascii(
		token[0]
	) == 'k' && lower_ascii(token[1]) == 'p' && token[2] >= '0' && token[2] <= '9')
	{
		*out = (rl::RLKeyboardKey)((int)rl::RLKeyboardKey.KP_0 + (token[2] - '0'));
		return true;
	}
	if (token.len == 4 && lower_ascii(
		token[0]
	) == 'k' && lower_ascii(token[1]) == 'p' && token[2] == '_' && token[3] >= '0' && token[3] <= '9')
	{
		*out = (rl::RLKeyboardKey)((int)rl::RLKeyboardKey.KP_0 + (token[3] - '0'));
		return true;
	}

	if (lower_ascii(token[0]) == 'f')
	{
		int number  = 0;
		bool digits = token.len > 1;
		for (usz i = 1; i < token.len; i++)
		{
			if (token[i] < '0' || token[i] > '9')
			{
				digits = false;
				break;
			}
			number = number * 10 + (int)(token[i] - '0');
		}
		if (digits && number >= 1 && number <= 12)
		{
			*out = (rl::RLKeyboardKey)((int)rl::RLKeyboardKey.F1 + number - 1);
			return true;
		}
	}
	return false;
}

fn bool mod_from_token(String token, uint* out)
{
	if (equals_ci(token, "ctrl") || equals_ci(token, "control"))
	{
		*out = MOD_CTRL;
		return true;
	}
	if (equals_ci(token, "shift"))
	{
		*out = MOD_SHIFT;
		return true;
	}
	if (equals_ci(token, "alt") || equals_ci(token, "option"))
	{
		*out = MOD_ALT;
		return true;
	}
	if (equals_ci(token, "cmd") || equals_ci(token, "super") || equals_ci(token, "meta") || equals_ci(token, "win"))
	{
		*out = MOD_SUPER;
		return true;
	}
	return false;
}

fn Chord parse_chord(String text)
{
	Chord chord = { .valid = false };
	if (text.len == 0) return chord;

	uint mods             = 0;
	usz start             = 0;
	bool have_key         = false;
	rl::RLKeyboardKey key = rl::RLKeyboardKey.SPACE;

	for (usz i = 0; i <= text.len; i++)
	{
		if (i < text.len && text[i] != '+') continue;
		String token = text[start:i - start];
		start = i + 1;
		if (token.len == 0) return chord;

		uint mod;
		if (mod_from_token(token, &mod))
		{
			mods |= mod;
			continue;
		}
		if (have_key) return chord;
		if (!key_from_name(token, &key)) return chord;
		have_key = true;
	}
	if (!have_key) return chord;

	chord.mods = mods;
	chord.key = key;
	chord.valid = true;
	return chord;
}

fn String key_name(Allocator allocator, rl::RLKeyboardKey key)
{
	switch (key)
	{
		case rl::RLKeyboardKey.ENTER:
			return "Enter";
		case rl::RLKeyboardKey.ESCAPE:
			return "Esc";
		case rl::RLKeyboardKey.TAB:
			return "Tab";
		case rl::RLKeyboardKey.SPACE:
			return "Space";
		case rl::RLKeyboardKey.BACKSPACE:
			return "Backspace";
		case rl::RLKeyboardKey.DELETE:
			return "Delete";
		case rl::RLKeyboardKey.UP:
			return "Up";
		case rl::RLKeyboardKey.DOWN:
			return "Down";
		case rl::RLKeyboardKey.LEFT:
			return "Left";
		case rl::RLKeyboardKey.RIGHT:
			return "Right";
		case rl::RLKeyboardKey.HOME:
			return "Home";
		case rl::RLKeyboardKey.END:
			return "End";
		case rl::RLKeyboardKey.PAGE_UP:
			return "PageUp";
		case rl::RLKeyboardKey.PAGE_DOWN:
			return "PageDown";
		case rl::RLKeyboardKey.INSERT:
			return "Insert";
		case rl::RLKeyboardKey.CAPS_LOCK:
			return "CapsLock";
		case rl::RLKeyboardKey.SCROLL_LOCK:
			return "ScrollLock";
		case rl::RLKeyboardKey.NUM_LOCK:
			return "NumLock";
		case rl::RLKeyboardKey.PRINT_SCREEN:
			return "PrintScreen";
		case rl::RLKeyboardKey.PAUSE:
			return "Pause";
		case rl::RLKeyboardKey.KB_MENU:
			return "Menu";
		case rl::RLKeyboardKey.KP_DECIMAL:
			return "KP_Decimal";
		case rl::RLKeyboardKey.KP_DIVIDE:
			return "KP_Divide";
		case rl::RLKeyboardKey.KP_MULTIPLY:
			return "KP_Multiply";
		case rl::RLKeyboardKey.KP_SUBTRACT:
			return "KP_Subtract";
		case rl::RLKeyboardKey.KP_ADD:
			return "KP_Add";
		case rl::RLKeyboardKey.KP_ENTER:
			return "KP_Enter";
		case rl::RLKeyboardKey.KP_EQUAL:
			return "KP_Equal";
		default:
			break;
	}

	int k = (int)key;
	if (k >= 33 && k <= 126) return string::format(allocator, "%c", (char)k);
	if (k >= (int)rl::RLKeyboardKey.KP_0 && k <= (int)rl::RLKeyboardKey.KP_9)
	{
		return string::format(allocator, "KP_%d", k - (int)rl::RLKeyboardKey.KP_0);
	}
	if (k >= (int)rl::RLKeyboardKey.F1 && k <= (int)rl::RLKeyboardKey.F12)
	{
		return string::format(allocator, "F%d", k - (int)rl::RLKeyboardKey.F1 + 1);
	}
	return string::format(allocator, "Key%d", k);
}

fn void append_string(DString* out, String text)
{
	out.append_bytes(text.ptr[0:text.len]);
}

fn String format_chord(Allocator allocator, Chord chord, bool macos)
{
	if (!chord.valid) return "".copy(allocator);

	DString out;
	out.init(allocator, 16);
	if ((chord.mods & MOD_CTRL) != 0) append_string(&out, macos ? "Cmd+" : "Ctrl+");
	if ((chord.mods & MOD_SUPER) != 0) append_string(&out, "Super+");
	if ((chord.mods & MOD_SHIFT) != 0) append_string(&out, "Shift+");
	if ((chord.mods & MOD_ALT) != 0) append_string(&out, "Alt+");
	append_string(&out, key_name(allocator, chord.key));

	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn bool chord_equals(Chord a, Chord b)
{
	return a.valid && b.valid && a.mods == b.mods && a.key == b.key;
}

fn void mod_state(bool* ctrl, bool* shift, bool* alt, bool* super)
{
	$if env::DARWIN:
		*ctrl = rl::is_key_down(rl::RLKeyboardKey.LEFT_SUPER) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SUPER);
		*super = false;
	$else
		*ctrl = rl::is_key_down(rl::RLKeyboardKey.LEFT_CONTROL) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_CONTROL);
		*super = rl::is_key_down(rl::RLKeyboardKey.LEFT_SUPER) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SUPER);
	$endif
	*shift = rl::is_key_down(rl::RLKeyboardKey.LEFT_SHIFT) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SHIFT);
	*alt = rl::is_key_down(rl::RLKeyboardKey.LEFT_ALT) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_ALT);
}

fn bool chord_mods_ok(Chord chord)
{
	bool ctrl;
	bool shift;
	bool alt;
	bool super;
	mod_state(&ctrl, &shift, &alt, &super);

	if (((chord.mods & MOD_CTRL) != 0) != ctrl) return false;
	if (((chord.mods & MOD_SHIFT) != 0) != shift) return false;
	if (((chord.mods & MOD_ALT) != 0) != alt) return false;
	if (((chord.mods & MOD_SUPER) != 0) != super) return false;
	return true;
}

fn bool chord_pressed(Chord chord)
{
	if (!chord.valid) return false;
	if (!rl::is_key_pressed(chord.key)) return false;
	return chord_mods_ok(chord);
}

fn bool chord_pressed_repeat(Chord chord)
{
	if (!chord.valid) return false;
	if (!rl::is_key_pressed(chord.key) && !rl::is_key_pressed_repeat(chord.key)) return false;
	return chord_mods_ok(chord);
}

fn void Keymap.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.warnings.init(allocator);
	self.clear();
}

fn void Keymap.clear(&self)
{
	for (int i = 0; i < MAX_COMMANDS; i++)
	{
		if (self.display[i].len > 0) self.display[i].free(self.allocator);
		self.display[i] = "";
		self.chords[i] = { .valid = false };
		self.bound[i] = false;
	}
	for (sz i = 0; i < self.warnings.len(); i++)
	{
		self.warnings[i].free(self.allocator);
	}
	self.warnings.clear();
}

fn void Keymap.destroy(&self)
{
	self.clear();
	self.warnings.free();
}

fn void Keymap.push_warning(&self, String message)
{
	self.warnings.push(message);
}

fn void Keymap.unbind(&self, int id)
{
	if (id < 0 || id >= MAX_COMMANDS) return;
	if (self.display[id].len > 0) self.display[id].free(self.allocator);
	self.display[id] = "";
	self.chords[id] = { .valid = false };
	self.bound[id] = false;
}

fn void Keymap.set_chord(&self, int id, Chord chord)
{
	if (self.display[id].len > 0) self.display[id].free(self.allocator);
	self.chords[id] = chord;
	self.bound[id] = true;
	self.display[id] = format_chord(self.allocator, chord, is_macos());
}

fn bool contexts_overlap(ulong a, ulong b)
{
	if ((a & commands::CTX_GLOBAL) != 0 || (b & commands::CTX_GLOBAL) != 0) return true;
	return (a & b) != 0;
}

fn void Keymap.detect_conflicts(&self)
{
	for (usz i = 0; i < commands::command_count(); i++)
	{
		if (!self.bound[i]) continue;
		for (usz j = i + 1; j < commands::command_count(); j++)
		{
			if (!self.bound[j]) continue;
			if (!chord_equals(self.chords[i], self.chords[j])) continue;
			if (!contexts_overlap(commands::command_def((commands::CommandId)i)
				.contexts, commands::command_def((commands::CommandId)j).contexts)) continue;
			self.push_warning(
				string::format(
					self.allocator,
					"Shortcut %s is bound to both %s and %s",
					self.display[i],
					commands::command_def((commands::CommandId)i)
				.label, commands::command_def((commands::CommandId)j).label));
		}
	}
}

fn void Keymap.build(&self, config::Config* config)
{
	self.clear();

	for (usz i = 0; i < commands::command_count(); i++)
	{
		Chord chord = parse_chord(commands::command_def((commands::CommandId)i).shortcut);
		if (chord.valid) self.set_chord((int)i, chord);
	}

	for (sz i = 0; i < config.keymap.len(); i++)
	{
		String name = config.keymap[i].command;
		int id      = commands::command_from_name(name);
		if (id < 0)
		{
			self.push_warning(string::format(self.allocator, "Unknown command in keymap: %s", name));
			continue;
		}
		if (config.keymap[i].chord.len == 0)
		{
			self.unbind(id);
			continue;
		}
		Chord chord = parse_chord(config.keymap[i].chord);
		if (!chord.valid)
		{
			self.push_warning(
				string::format(self.allocator, "Invalid shortcut for %s: %s", name, config.keymap[i].chord)
			);
			continue;
		}
		self.set_chord(id, chord);
	}

	self.detect_conflicts();
}

fn String Keymap.shortcut(&self, commands::CommandId id)
{
	int i = (int)id;
	if (i < 0 || i >= MAX_COMMANDS || !self.bound[i]) return "";
	return self.display[i];
}

fn bool context_matches(ulong contexts, ulong context)
{
	return ((contexts & context) != 0) || ((contexts & commands::CTX_GLOBAL) != 0);
}

fn bool Keymap.active(&self, int id, ulong context)
{
	if (id < 0 || id >= MAX_COMMANDS) return false;
	if (!self.bound[id]) return false;
	return context_matches(commands::command_def((commands::CommandId)id).contexts, context);
}

fn bool Keymap.pressed(&self, int id, ulong context)
{
	if (!self.active(id, context)) return false;
	return chord_pressed(self.chords[id]);
}

fn bool Keymap.pressed_repeat(&self, int id, ulong context)
{
	if (!self.active(id, context)) return false;
	return chord_pressed_repeat(self.chords[id]);
}

fn bool chord_mods_ok_ignore_shift(Chord chord)
{
	bool ctrl;
	bool shift;
	bool alt;
	bool super;
	mod_state(&ctrl, &shift, &alt, &super);

	if (((chord.mods & MOD_CTRL) != 0) != ctrl) return false;
	if (((chord.mods & MOD_ALT) != 0) != alt) return false;
	if (((chord.mods & MOD_SUPER) != 0) != super) return false;
	return true;
}

fn bool Keymap.pressed_move(&self, int id, ulong context)
{
	if (!self.active(id, context)) return false;
	Chord chord = self.chords[id];
	if (!chord.valid) return false;
	if (!rl::is_key_pressed(chord.key) && !rl::is_key_pressed_repeat(chord.key)) return false;
	return chord_mods_ok_ignore_shift(chord);
}

fn int Keymap.poll(&self, ulong context)
{
	for (usz i = 0; i < commands::command_count(); i++)
	{
		if (!self.active((int)i, context)) continue;
		if (chord_pressed(self.chords[i])) return (int)i;
	}
	return -1;
}