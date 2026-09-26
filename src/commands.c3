module yun::commands;

const ulong CTX_GLOBAL     = 1 << 0;
const ulong CTX_EDIT       = 1 << 1;
const ulong CTX_MOVE       = 1 << 2;
const ulong CTX_TOP_BAR    = 1 << 3;
const ulong CTX_PALETTE    = 1 << 4;
const ulong CTX_FIND       = 1 << 5;
const ulong CTX_SEARCH     = 1 << 6;
const ulong CTX_SYMBOLS    = 1 << 7;
const ulong CTX_PROBLEMS   = 1 << 8;
const ulong CTX_PROMPT     = 1 << 9;
const ulong CTX_BROWSER    = 1 << 10;
const ulong CTX_SETTINGS   = 1 << 11;
const ulong CTX_MENU       = 1 << 12;
const ulong CTX_COMPLETION = 1 << 13;

enum CommandId
{
	NEW_FILE,
	NEW_FOLDER,
	OPEN,
	SAVE,
	SHOW_PALETTE,
	FIND,
	REPLACE,
	COPY,
	CUT,
	PASTE,
	SELECT_ALL,
	PROBLEMS,
	GO_TO_DEFINITION,
	COMPLETE,
	SELECT_THEME,
	SEARCH_PROJECT,
	SYMBOLS_PROJECT,
	TOGGLE_SETTINGS,
	UNDO,
	REDO,
	INDENT,
	OUTDENT,
	NEWLINE,
	DELETE_BACK,
	DELETE_FORWARD,
	CURSOR_LEFT,
	CURSOR_RIGHT,
	CURSOR_UP,
	CURSOR_DOWN,
	LINE_START,
	LINE_END,
	PAGE_UP,
	PAGE_DOWN,
	EXIT_EDITOR,
	COMPLETION_NEXT,
	COMPLETION_PREV,
	COMPLETION_ACCEPT,
	COMPLETION_CLOSE,
}

struct CommandDef
{
	CommandId id;
	String label;
	String shortcut;
	bool in_top_bar;
	ulong contexts;
}

const CommandDef[] COMMAND_DEFS = {
	{ .id = CommandId.NEW_FILE, .label = "New", .shortcut = "Ctrl+N", .in_top_bar = true, .contexts = CTX_GLOBAL },
	{ .id = CommandId.NEW_FOLDER, .label = "New Folder", .shortcut = "", .in_top_bar = false, .contexts = CTX_GLOBAL },
	{ .id = CommandId.OPEN, .label = "Open", .shortcut = "Ctrl+O", .in_top_bar = true, .contexts = CTX_GLOBAL },
	{ .id = CommandId.SAVE, .label = "Save", .shortcut = "Ctrl+S", .in_top_bar = true, .contexts = CTX_GLOBAL },
	{
		.id = CommandId.SHOW_PALETTE,
		.label = "Command Palette",
		.shortcut = "Ctrl+Shift+P",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{ .id = CommandId.FIND, .label = "Find", .shortcut = "Ctrl+F", .in_top_bar = false, .contexts = CTX_GLOBAL },
	{ .id = CommandId.REPLACE, .label = "Replace", .shortcut = "Ctrl+H", .in_top_bar = false, .contexts = CTX_GLOBAL },
	{ .id = CommandId.COPY, .label = "Copy", .shortcut = "Ctrl+C", .in_top_bar = false, .contexts = CTX_GLOBAL },
	{ .id = CommandId.CUT, .label = "Cut", .shortcut = "Ctrl+X", .in_top_bar = false, .contexts = CTX_GLOBAL },
	{ .id = CommandId.PASTE, .label = "Paste", .shortcut = "Ctrl+V", .in_top_bar = false, .contexts = CTX_GLOBAL },
	{
		.id = CommandId.SELECT_ALL,
		.label = "Select All",
		.shortcut = "Ctrl+A",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.PROBLEMS,
		.label = "Problems",
		.shortcut = "Ctrl+Shift+M",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.GO_TO_DEFINITION,
		.label = "Go to Definition",
		.shortcut = "F12",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.COMPLETE,
		.label = "Complete",
		.shortcut = "Ctrl+Space",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.SELECT_THEME,
		.label = "Theme",
		.shortcut = "Ctrl+Shift+T",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.SEARCH_PROJECT,
		.label = "Search in Project",
		.shortcut = "Ctrl+Shift+F",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.SYMBOLS_PROJECT,
		.label = "Go to Symbol",
		.shortcut = "Ctrl+Shift+O",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.TOGGLE_SETTINGS,
		.label = "Settings",
		.shortcut = "Ctrl+Shift+S",
		.in_top_bar = true,
		.contexts = CTX_GLOBAL,
	},
	{ .id = CommandId.UNDO, .label = "Undo", .shortcut = "Ctrl+Z", .in_top_bar = false, .contexts = CTX_EDIT },
	{ .id = CommandId.REDO, .label = "Redo", .shortcut = "Ctrl+Y", .in_top_bar = false, .contexts = CTX_EDIT },
	{ .id = CommandId.INDENT, .label = "Indent", .shortcut = "Tab", .in_top_bar = false, .contexts = CTX_EDIT },
	{
		.id = CommandId.OUTDENT,
		.label = "Outdent",
		.shortcut = "Shift+Tab",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{ .id = CommandId.NEWLINE, .label = "New Line", .shortcut = "Enter", .in_top_bar = false, .contexts = CTX_EDIT },
	{
		.id = CommandId.DELETE_BACK,
		.label = "Delete Back",
		.shortcut = "Backspace",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{
		.id = CommandId.DELETE_FORWARD,
		.label = "Delete Forward",
		.shortcut = "Delete",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{
		.id = CommandId.CURSOR_LEFT,
		.label = "Cursor Left",
		.shortcut = "Left",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{
		.id = CommandId.CURSOR_RIGHT,
		.label = "Cursor Right",
		.shortcut = "Right",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{ .id = CommandId.CURSOR_UP, .label = "Cursor Up", .shortcut = "Up", .in_top_bar = false, .contexts = CTX_EDIT },
	{
		.id = CommandId.CURSOR_DOWN,
		.label = "Cursor Down",
		.shortcut = "Down",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{
		.id = CommandId.LINE_START,
		.label = "Line Start",
		.shortcut = "Home",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{ .id = CommandId.LINE_END, .label = "Line End", .shortcut = "End", .in_top_bar = false, .contexts = CTX_EDIT },
	{ .id = CommandId.PAGE_UP, .label = "Page Up", .shortcut = "PageUp", .in_top_bar = false, .contexts = CTX_EDIT },
	{
		.id = CommandId.PAGE_DOWN,
		.label = "Page Down",
		.shortcut = "PageDown",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{
		.id = CommandId.EXIT_EDITOR,
		.label = "Exit Editor",
		.shortcut = "Esc",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.COMPLETION_NEXT,
		.label = "Completion Next",
		.shortcut = "Down",
		.in_top_bar = false,
		.contexts = CTX_COMPLETION,
	},
	{
		.id = CommandId.COMPLETION_PREV,
		.label = "Completion Previous",
		.shortcut = "Up",
		.in_top_bar = false,
		.contexts = CTX_COMPLETION,
	},
	{
		.id = CommandId.COMPLETION_ACCEPT,
		.label = "Completion Accept",
		.shortcut = "Enter",
		.in_top_bar = false,
		.contexts = CTX_COMPLETION,
	},
	{
		.id = CommandId.COMPLETION_CLOSE,
		.label = "Completion Close",
		.shortcut = "Esc",
		.in_top_bar = false,
		.contexts = CTX_COMPLETION,
	},
};

fn usz command_count()
{
	return COMMAND_DEFS.len;
}

fn CommandDef command_def(CommandId id)
{
	return COMMAND_DEFS[(int)id];
}

fn String command_name(CommandId id)
{
	switch (id)
	{
		case CommandId.NEW_FILE:
			return "new_file";
		case CommandId.NEW_FOLDER:
			return "new_folder";
		case CommandId.OPEN:
			return "open";
		case CommandId.SAVE:
			return "save";
		case CommandId.SHOW_PALETTE:
			return "show_palette";
		case CommandId.FIND:
			return "find";
		case CommandId.REPLACE:
			return "replace";
		case CommandId.COPY:
			return "copy";
		case CommandId.CUT:
			return "cut";
		case CommandId.PASTE:
			return "paste";
		case CommandId.SELECT_ALL:
			return "select_all";
		case CommandId.PROBLEMS:
			return "problems";
		case CommandId.GO_TO_DEFINITION:
			return "go_to_definition";
		case CommandId.COMPLETE:
			return "complete";
		case CommandId.SELECT_THEME:
			return "select_theme";
		case CommandId.SEARCH_PROJECT:
			return "search_project";
		case CommandId.SYMBOLS_PROJECT:
			return "symbols_project";
		case CommandId.TOGGLE_SETTINGS:
			return "toggle_settings";
		case CommandId.UNDO:
			return "undo";
		case CommandId.REDO:
			return "redo";
		case CommandId.INDENT:
			return "indent";
		case CommandId.OUTDENT:
			return "outdent";
		case CommandId.NEWLINE:
			return "newline";
		case CommandId.DELETE_BACK:
			return "delete_back";
		case CommandId.DELETE_FORWARD:
			return "delete_forward";
		case CommandId.CURSOR_LEFT:
			return "cursor_left";
		case CommandId.CURSOR_RIGHT:
			return "cursor_right";
		case CommandId.CURSOR_UP:
			return "cursor_up";
		case CommandId.CURSOR_DOWN:
			return "cursor_down";
		case CommandId.LINE_START:
			return "line_start";
		case CommandId.LINE_END:
			return "line_end";
		case CommandId.PAGE_UP:
			return "page_up";
		case CommandId.PAGE_DOWN:
			return "page_down";
		case CommandId.EXIT_EDITOR:
			return "exit_editor";
		case CommandId.COMPLETION_NEXT:
			return "completion_next";
		case CommandId.COMPLETION_PREV:
			return "completion_prev";
		case CommandId.COMPLETION_ACCEPT:
			return "completion_accept";
		case CommandId.COMPLETION_CLOSE:
			return "completion_close";
	}
}

fn int command_from_name(String name)
{
	for (usz i = 0; i < command_count(); i++)
	{
		if (command_name((CommandId)i).compare_to(name) == 0) return (int)i;
	}
	return -1;
}

fn usz bar_command_count()
{
	usz count = 0;
	foreach (CommandDef def : COMMAND_DEFS)
	{
		if (def.in_top_bar) count++;
	}
	return count;
}

fn CommandDef bar_command(usz slot)
{
	usz seen = 0;
	foreach (CommandDef def : COMMAND_DEFS)
	{
		if (!def.in_top_bar) continue;
		if (seen == slot) return def;
		seen++;
	}
	return COMMAND_DEFS[0];
}

fn bool command_enabled(CommandId id, bool has_project, bool has_buffer)
{
	switch (id)
	{
		case CommandId.NEW_FILE:
			return has_project;
		case CommandId.NEW_FOLDER:
			return has_project;
		case CommandId.OPEN:
			return true;
		case CommandId.SAVE:
			return has_buffer;
		case CommandId.SHOW_PALETTE:
			return true;
		case CommandId.FIND:
			return has_buffer;
		case CommandId.REPLACE:
			return has_buffer;
		case CommandId.COPY:
			return has_buffer;
		case CommandId.CUT:
			return has_buffer;
		case CommandId.PASTE:
			return has_buffer;
		case CommandId.SELECT_ALL:
			return has_buffer;
		case CommandId.PROBLEMS:
			return true;
		case CommandId.GO_TO_DEFINITION:
			return has_buffer;
		case CommandId.COMPLETE:
			return has_buffer;
		case CommandId.SELECT_THEME:
			return true;
		case CommandId.SEARCH_PROJECT:
			return has_project;
		case CommandId.SYMBOLS_PROJECT:
			return has_project;
		case CommandId.TOGGLE_SETTINGS:
			return true;
		case CommandId.UNDO:
		case CommandId.REDO:
		case CommandId.INDENT:
		case CommandId.OUTDENT:
		case CommandId.NEWLINE:
		case CommandId.DELETE_BACK:
		case CommandId.DELETE_FORWARD:
		case CommandId.CURSOR_LEFT:
		case CommandId.CURSOR_RIGHT:
		case CommandId.CURSOR_UP:
		case CommandId.CURSOR_DOWN:
		case CommandId.LINE_START:
		case CommandId.LINE_END:
		case CommandId.PAGE_UP:
		case CommandId.PAGE_DOWN:
		case CommandId.EXIT_EDITOR:
		case CommandId.COMPLETION_NEXT:
		case CommandId.COMPLETION_PREV:
		case CommandId.COMPLETION_ACCEPT:
		case CommandId.COMPLETION_CLOSE:
			return has_buffer;
	}
}

fn char lower_ascii(char c)
{
	if (c >= 'A' && c <= 'Z') return (char)(c + 32);
	return c;
}

fn int fuzzy_match(String haystack, String needle, usz[] positions)
{
	if (needle.len == 0) return 0;
	if (needle.len > positions.len) return -1;

	usz at    =  0;
	int score =  0;
	sz prev   = -1;
	for (usz n = 0; n < needle.len; n++)
	{
		char want  = lower_ascii(needle[n]);
		bool found = false;
		while (at < haystack.len)
		{
			char c = lower_ascii(haystack[at]);
			if (c == want)
			{
				positions[n] = at;
				score += 1;
				if (prev >= 0 && (usz)(prev + 1) == at)
				{
					score += 8;
				}
				else if (at == 0 || haystack[at - 1] == ' ' || haystack[at - 1] == '_' || haystack[at - 1] == '-'
					|| haystack[at - 1] == '/')
				{
					score += 12;
				}
				prev = (sz)at;
				at++;
				found = true;
				break;
			}
			at++;
		}
		if (!found) return -1;
	}
	return score;
}