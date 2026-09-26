module yun::keymap @test;

import raylib6::rl;
import yun::commands;
import yun::config;
import yun::settings;

fn void test_parse_chord()
{
	Chord ctrl_s = parse_chord("Ctrl+S");
	assert(ctrl_s.valid);
	assert(ctrl_s.mods == MOD_CTRL);
	assert(ctrl_s.key == rl::RLKeyboardKey.S);

	Chord combo = parse_chord("ctrl+shift+p");
	assert(combo.valid);
	assert(combo.mods == (MOD_CTRL | MOD_SHIFT));
	assert(combo.key == rl::RLKeyboardKey.P);

	Chord f5 = parse_chord("F5");
	assert(f5.valid && f5.mods == 0 && f5.key == rl::RLKeyboardKey.F5);

	Chord escape = parse_chord("Escape");
	assert(escape.valid && escape.key == rl::RLKeyboardKey.ESCAPE);

	Chord del = parse_chord("Ctrl+Alt+Delete");
	assert(del.valid && del.mods == (MOD_CTRL | MOD_ALT) && del.key == rl::RLKeyboardKey.DELETE);
}

fn void test_parse_chord_invalid()
{
	assert(!parse_chord("").valid);
	assert(!parse_chord("Ctrl+").valid);
	assert(!parse_chord("+S").valid);
	assert(!parse_chord("Foo").valid);
	assert(!parse_chord("Ctrl+S+T").valid);
	assert(!parse_chord("F13").valid);
}

fn void test_format_chord()
{
	@pool()
	{
		Chord chord = parse_chord("Ctrl+Shift+P");
		assert(format_chord(tmem, chord, false).compare_to("Ctrl+Shift+P") == 0);
		assert(format_chord(tmem, chord, true).compare_to("Cmd+Shift+P") == 0);

		Chord plain = parse_chord("F5");
		assert(format_chord(tmem, plain, false).compare_to("F5") == 0);
	};
}

fn void test_chord_equals()
{
	assert(chord_equals(parse_chord("Ctrl+S"), parse_chord("ctrl+s")));
	assert(!chord_equals(parse_chord("Ctrl+S"), parse_chord("Ctrl+Shift+S")));
	assert(!chord_equals(parse_chord("Ctrl+S"), parse_chord("Ctrl+O")));
}

fn void test_defaults()
{
	@pool()
	{
		config::Config c;
		c.init(tmem);
		c.reset();

		Keymap k;
		k.init(tmem);
		k.build(&c);

		assert(k.shortcut(commands::CommandId.SAVE).compare_to("Ctrl+S") == 0);
		assert(k.shortcut(commands::CommandId.OPEN).compare_to("Ctrl+O") == 0);
		assert(k.shortcut(commands::CommandId.SHOW_PALETTE).compare_to("Ctrl+Shift+P") == 0);
		assert(k.shortcut(commands::CommandId.NEW_FOLDER).len == 0);
		assert(k.warnings.len() == 0);
	};
}

fn void test_override()
{
	@pool()
	{
		config::Config c;
		c.init(tmem);
		c.reset();
		assert(c.apply_json("{\"keymap\":{\"save\":\"Ctrl+Alt+S\"}}", settings::SettingLayer.GLOBAL));

		Keymap k;
		k.init(tmem);
		k.build(&c);

		assert(k.shortcut(commands::CommandId.SAVE).compare_to("Ctrl+Alt+S") == 0);
		assert(k.warnings.len() == 0);
	};
}

fn void test_unknown_command_warns()
{
	@pool()
	{
		config::Config c;
		c.init(tmem);
		c.reset();
		assert(c.apply_json("{\"keymap\":{\"nope\":\"Ctrl+K\"}}", settings::SettingLayer.GLOBAL));

		Keymap k;
		k.init(tmem);
		k.build(&c);

		assert(k.warnings.len() == 1);
		assert(k.warnings[0].compare_to("Unknown command in keymap: nope") == 0);
	};
}

fn void test_invalid_chord_warns()
{
	@pool()
	{
		config::Config c;
		c.init(tmem);
		c.reset();
		assert(c.apply_json("{\"keymap\":{\"save\":\"Ctrl+\"}}", settings::SettingLayer.GLOBAL));

		Keymap k;
		k.init(tmem);
		k.build(&c);

		assert(k.warnings.len() == 1);
		assert(k.warnings[0].compare_to("Invalid shortcut for save: Ctrl+") == 0);
		assert(k.shortcut(commands::CommandId.SAVE).compare_to("Ctrl+S") == 0);
	};
}

fn void test_conflict_warns()
{
	@pool()
	{
		config::Config c;
		c.init(tmem);
		c.reset();
		assert(c.apply_json("{\"keymap\":{\"save\":\"Ctrl+N\"}}", settings::SettingLayer.GLOBAL));

		Keymap k;
		k.init(tmem);
		k.build(&c);

		assert(k.warnings.len() == 1);
		assert(k.warnings[0].compare_to("Shortcut Ctrl+N is bound to both New and Save") == 0);
	};
}

fn void test_parse_punctuation()
{
	Chord comma = parse_chord("Ctrl+,");
	assert(comma.valid && comma.key == rl::RLKeyboardKey.COMMA && comma.mods == MOD_CTRL);

	Chord left = parse_chord("Ctrl+[");
	assert(left.valid && left.key == rl::RLKeyboardKey.LEFT_BRACKET);

	Chord right = parse_chord("]");
	assert(right.valid && right.key == rl::RLKeyboardKey.RIGHT_BRACKET && right.mods == 0);

	assert(parse_chord("Ctrl+-").key == rl::RLKeyboardKey.MINUS);
	assert(parse_chord("Ctrl+=").key == rl::RLKeyboardKey.EQUAL);
	assert(parse_chord("Ctrl+`").key == rl::RLKeyboardKey.GRAVE);
	assert(parse_chord("Ctrl+/").key == rl::RLKeyboardKey.SLASH);
	assert(parse_chord("Ctrl+.").key == rl::RLKeyboardKey.PERIOD);
}

fn void test_parse_named_and_keypad()
{
	assert(parse_chord("Insert").valid && parse_chord("Insert").key == rl::RLKeyboardKey.INSERT);
	assert(parse_chord("CapsLock").valid && parse_chord("CapsLock").key == rl::RLKeyboardKey.CAPS_LOCK);
	assert(parse_chord("PrintScreen").valid && parse_chord("PrintScreen").key == rl::RLKeyboardKey.PRINT_SCREEN);
	assert(parse_chord("KP_Add").valid && parse_chord("KP_Add").key == rl::RLKeyboardKey.KP_ADD);
	assert(parse_chord("KP_Subtract").valid && parse_chord("KP_Subtract").key == rl::RLKeyboardKey.KP_SUBTRACT);
	assert(parse_chord("KP_Enter").valid && parse_chord("KP_Enter").key == rl::RLKeyboardKey.KP_ENTER);
	assert(parse_chord("KP_5").valid && parse_chord("KP_5").key == rl::RLKeyboardKey.KP_5);
}

fn void test_format_punctuation_roundtrip()
{
	@pool()
	{
		assert(format_chord(tmem, parse_chord("Ctrl+,"), false).compare_to("Ctrl+,") == 0);
		assert(format_chord(tmem, parse_chord("Ctrl+["), false).compare_to("Ctrl+[") == 0);
		assert(format_chord(tmem, parse_chord("-"), false).compare_to("-") == 0);
		assert(format_chord(tmem, parse_chord("KP_Add"), false).compare_to("KP_Add") == 0);
		assert(format_chord(tmem, parse_chord("Insert"), false).compare_to("Insert") == 0);
	};
}

fn void test_context_matches()
{
	assert(context_matches(commands::CTX_GLOBAL, commands::CTX_MOVE));
	assert(context_matches(commands::CTX_GLOBAL, commands::CTX_SETTINGS));
	assert(context_matches(commands::CTX_EDIT, commands::CTX_EDIT));
	assert(!context_matches(commands::CTX_EDIT, commands::CTX_MOVE));
	assert(context_matches(commands::CTX_EDIT | commands::CTX_MOVE, commands::CTX_MOVE));
}

fn void test_contexts_overlap()
{
	assert(contexts_overlap(commands::CTX_GLOBAL, commands::CTX_MOVE));
	assert(contexts_overlap(commands::CTX_EDIT, commands::CTX_EDIT));
	assert(contexts_overlap(commands::CTX_EDIT | commands::CTX_MOVE, commands::CTX_MOVE));
	assert(!contexts_overlap(commands::CTX_EDIT, commands::CTX_COMPLETION));
	assert(!contexts_overlap(commands::CTX_EDIT, commands::CTX_MENU));
	assert(!contexts_overlap(commands::CTX_GLOBAL, commands::CTX_FIND));
	assert(!contexts_overlap(commands::CTX_FIND, commands::CTX_GLOBAL));
	assert(!contexts_overlap(commands::CTX_GLOBAL, commands::CTX_PALETTE));
	assert(contexts_overlap(commands::CTX_GLOBAL, commands::CTX_MOVE));
	assert(contexts_overlap(commands::CTX_GLOBAL, commands::CTX_GLOBAL));
}

fn void test_eligible_exact()
{
	@pool()
	{
		config::Config c;
		c.init(tmem);
		c.reset();

		Keymap k;
		k.init(tmem);
		k.build(&c);

		int save = (int)commands::CommandId.SAVE;
		int pan  = (int)commands::CommandId.PAN_LEFT;

		assert(k.eligible(save, commands::CTX_GLOBAL, false));
		assert(!k.eligible(save, commands::CTX_MOVE, true));
		assert(k.eligible(save, commands::CTX_MOVE, false));
		assert(k.eligible(pan, commands::CTX_MOVE, true));
		assert(!k.eligible(pan, commands::CTX_TOP_BAR, true));
		k.destroy();
	};
}

fn void test_active_by_context()
{
	@pool()
	{
		config::Config c;
		c.init(tmem);
		c.reset();

		Keymap k;
		k.init(tmem);
		k.build(&c);

		int save = (int)commands::CommandId.SAVE;
		assert(k.active(save, commands::CTX_MOVE));
		assert(k.active(save, commands::CTX_SETTINGS));
		k.unbind(save);
		assert(!k.active(save, commands::CTX_MOVE));
		assert(k.shortcut(commands::CommandId.SAVE).len == 0);
		k.destroy();
	};
}

fn void test_unbind_via_config()
{
	@pool()
	{
		config::Config c;
		c.init(tmem);
		c.reset();
		assert(c.apply_json("{\"keymap\":{\"save\":\"\"}}", settings::SettingLayer.GLOBAL));

		Keymap k;
		k.init(tmem);
		k.build(&c);

		assert(k.shortcut(commands::CommandId.SAVE).len == 0);
		assert(k.shortcut(commands::CommandId.OPEN).compare_to("Ctrl+O") == 0);
		assert(k.warnings.len() == 0);
		k.destroy();
	};
}