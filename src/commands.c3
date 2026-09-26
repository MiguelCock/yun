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

const ulong CTX_OVERLAY_CLOSE  = CTX_PALETTE | CTX_FIND | CTX_SEARCH | CTX_SYMBOLS | CTX_PROBLEMS | CTX_PROMPT
	| CTX_BROWSER
	| CTX_SETTINGS
	| CTX_MENU;
const ulong CTX_OVERLAY_LIST   = CTX_PALETTE | CTX_SEARCH | CTX_SYMBOLS | CTX_PROBLEMS | CTX_BROWSER | CTX_SETTINGS
	| CTX_MENU;
const ulong CTX_OVERLAY_PAGE   = CTX_SEARCH | CTX_SYMBOLS | CTX_PROBLEMS;
const ulong CTX_OVERLAY_ACCEPT = CTX_PALETTE | CTX_SEARCH | CTX_SYMBOLS | CTX_PROBLEMS | CTX_BROWSER | CTX_PROMPT
	| CTX_SETTINGS
	| CTX_MENU;

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
	PAN_LEFT,
	PAN_RIGHT,
	PAN_UP,
	PAN_DOWN,
	SELECT_LEFT,
	SELECT_RIGHT,
	SELECT_UP,
	SELECT_DOWN,
	CYCLE_NEXT,
	CYCLE_PREV,
	ZOOM_IN,
	ZOOM_OUT,
	FOCUS_TOP_BAR,
	FOCUS_EDITOR,
	TOPBAR_LEFT,
	TOPBAR_RIGHT,
	TOPBAR_ACTIVATE,
	FOCUS_CANVAS,
	OVERLAY_CLOSE,
	LIST_UP,
	LIST_DOWN,
	LIST_PAGE_UP,
	LIST_PAGE_DOWN,
	LIST_ACCEPT,
	FIND_NEXT,
	FIND_PREV,
	FIND_REPLACE,
	FIND_REPLACE_ALL,
	FIND_CYCLE_FIELD,
	SEARCH_TOGGLE_CASE,
	SEARCH_TOGGLE_WORD,
	SETTINGS_SCOPE_TOGGLE,
	SETTINGS_RESET,
	SETTINGS_VALUE_DEC,
	SETTINGS_VALUE_INC,
	BROWSER_PARENT,
}

struct CommandDef
{
	CommandId id;
	String label;
	String shortcut;
	bool in_top_bar;
	ulong contexts;
	bool repeat;
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
	{
		.id = CommandId.PAN_LEFT,
		.label = "Pan Left",
		.shortcut = "Shift+H",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
		.repeat = true,
	},
	{
		.id = CommandId.PAN_RIGHT,
		.label = "Pan Right",
		.shortcut = "Shift+L",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
		.repeat = true,
	},
	{
		.id = CommandId.PAN_UP,
		.label = "Pan Up",
		.shortcut = "Shift+K",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
		.repeat = true,
	},
	{
		.id = CommandId.PAN_DOWN,
		.label = "Pan Down",
		.shortcut = "Shift+J",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
		.repeat = true,
	},
	{
		.id = CommandId.SELECT_LEFT,
		.label = "Select Left",
		.shortcut = "H",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.SELECT_RIGHT,
		.label = "Select Right",
		.shortcut = "L",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.SELECT_UP,
		.label = "Select Up",
		.shortcut = "K",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.SELECT_DOWN,
		.label = "Select Down",
		.shortcut = "J",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.CYCLE_NEXT,
		.label = "Next Card",
		.shortcut = "]",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.CYCLE_PREV,
		.label = "Previous Card",
		.shortcut = "[",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{ .id = CommandId.ZOOM_IN, .label = "Zoom In", .shortcut = "=", .in_top_bar = false, .contexts = CTX_MOVE },
	{ .id = CommandId.ZOOM_OUT, .label = "Zoom Out", .shortcut = "-", .in_top_bar = false, .contexts = CTX_MOVE },
	{
		.id = CommandId.FOCUS_TOP_BAR,
		.label = "Focus Top Bar",
		.shortcut = "Tab",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.FOCUS_EDITOR,
		.label = "Focus Editor",
		.shortcut = "Enter",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.TOPBAR_LEFT,
		.label = "Top Bar Left",
		.shortcut = "Left",
		.in_top_bar = false,
		.contexts = CTX_TOP_BAR,
		.repeat = true,
	},
	{
		.id = CommandId.TOPBAR_RIGHT,
		.label = "Top Bar Right",
		.shortcut = "Right",
		.in_top_bar = false,
		.contexts = CTX_TOP_BAR,
		.repeat = true,
	},
	{
		.id = CommandId.TOPBAR_ACTIVATE,
		.label = "Top Bar Activate",
		.shortcut = "Enter",
		.in_top_bar = false,
		.contexts = CTX_TOP_BAR,
	},
	{
		.id = CommandId.FOCUS_CANVAS,
		.label = "Focus Canvas",
		.shortcut = "Esc",
		.in_top_bar = false,
		.contexts = CTX_TOP_BAR,
	},
	{
		.id = CommandId.OVERLAY_CLOSE,
		.label = "Close Overlay",
		.shortcut = "Esc",
		.in_top_bar = false,
		.contexts = CTX_OVERLAY_CLOSE,
	},
	{
		.id = CommandId.LIST_UP,
		.label = "List Up",
		.shortcut = "Up",
		.in_top_bar = false,
		.contexts = CTX_OVERLAY_LIST,
		.repeat = true,
	},
	{
		.id = CommandId.LIST_DOWN,
		.label = "List Down",
		.shortcut = "Down",
		.in_top_bar = false,
		.contexts = CTX_OVERLAY_LIST,
		.repeat = true,
	},
	{
		.id = CommandId.LIST_PAGE_UP,
		.label = "List Page Up",
		.shortcut = "PageUp",
		.in_top_bar = false,
		.contexts = CTX_OVERLAY_PAGE,
	},
	{
		.id = CommandId.LIST_PAGE_DOWN,
		.label = "List Page Down",
		.shortcut = "PageDown",
		.in_top_bar = false,
		.contexts = CTX_OVERLAY_PAGE,
	},
	{
		.id = CommandId.LIST_ACCEPT,
		.label = "List Accept",
		.shortcut = "Enter",
		.in_top_bar = false,
		.contexts = CTX_OVERLAY_ACCEPT,
	},
	{
		.id = CommandId.FIND_NEXT,
		.label = "Find Next",
		.shortcut = "Enter",
		.in_top_bar = false,
		.contexts = CTX_FIND,
	},
	{
		.id = CommandId.FIND_PREV,
		.label = "Find Previous",
		.shortcut = "Shift+Enter",
		.in_top_bar = false,
		.contexts = CTX_FIND,
	},
	{
		.id = CommandId.FIND_REPLACE,
		.label = "Replace Match",
		.shortcut = "Ctrl+H",
		.in_top_bar = false,
		.contexts = CTX_FIND,
	},
	{
		.id = CommandId.FIND_REPLACE_ALL,
		.label = "Replace All",
		.shortcut = "Ctrl+Enter",
		.in_top_bar = false,
		.contexts = CTX_FIND,
	},
	{
		.id = CommandId.FIND_CYCLE_FIELD,
		.label = "Find Field",
		.shortcut = "Tab",
		.in_top_bar = false,
		.contexts = CTX_FIND,
	},
	{
		.id = CommandId.SEARCH_TOGGLE_CASE,
		.label = "Match Case",
		.shortcut = "Alt+C",
		.in_top_bar = false,
		.contexts = CTX_SEARCH,
	},
	{
		.id = CommandId.SEARCH_TOGGLE_WORD,
		.label = "Whole Word",
		.shortcut = "Alt+W",
		.in_top_bar = false,
		.contexts = CTX_SEARCH,
	},
	{
		.id = CommandId.SETTINGS_SCOPE_TOGGLE,
		.label = "Toggle Scope",
		.shortcut = "Tab",
		.in_top_bar = false,
		.contexts = CTX_SETTINGS,
	},
	{
		.id = CommandId.SETTINGS_RESET,
		.label = "Reset Setting",
		.shortcut = "Del",
		.in_top_bar = false,
		.contexts = CTX_SETTINGS,
	},
	{
		.id = CommandId.SETTINGS_VALUE_DEC,
		.label = "Decrease Value",
		.shortcut = "Left",
		.in_top_bar = false,
		.contexts = CTX_SETTINGS,
		.repeat = true,
	},
	{
		.id = CommandId.SETTINGS_VALUE_INC,
		.label = "Increase Value",
		.shortcut = "Right",
		.in_top_bar = false,
		.contexts = CTX_SETTINGS,
		.repeat = true,
	},
	{
		.id = CommandId.BROWSER_PARENT,
		.label = "Parent Folder",
		.shortcut = "Backspace",
		.in_top_bar = false,
		.contexts = CTX_BROWSER,
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
		case CommandId.PAN_LEFT:
			return "pan_left";
		case CommandId.PAN_RIGHT:
			return "pan_right";
		case CommandId.PAN_UP:
			return "pan_up";
		case CommandId.PAN_DOWN:
			return "pan_down";
		case CommandId.SELECT_LEFT:
			return "select_left";
		case CommandId.SELECT_RIGHT:
			return "select_right";
		case CommandId.SELECT_UP:
			return "select_up";
		case CommandId.SELECT_DOWN:
			return "select_down";
		case CommandId.CYCLE_NEXT:
			return "cycle_next";
		case CommandId.CYCLE_PREV:
			return "cycle_prev";
		case CommandId.ZOOM_IN:
			return "zoom_in";
		case CommandId.ZOOM_OUT:
			return "zoom_out";
		case CommandId.FOCUS_TOP_BAR:
			return "focus_top_bar";
		case CommandId.FOCUS_EDITOR:
			return "focus_editor";
		case CommandId.TOPBAR_LEFT:
			return "topbar_left";
		case CommandId.TOPBAR_RIGHT:
			return "topbar_right";
		case CommandId.TOPBAR_ACTIVATE:
			return "topbar_activate";
		case CommandId.FOCUS_CANVAS:
			return "focus_canvas";
		case CommandId.OVERLAY_CLOSE:
			return "overlay_close";
		case CommandId.LIST_UP:
			return "list_up";
		case CommandId.LIST_DOWN:
			return "list_down";
		case CommandId.LIST_PAGE_UP:
			return "list_page_up";
		case CommandId.LIST_PAGE_DOWN:
			return "list_page_down";
		case CommandId.LIST_ACCEPT:
			return "list_accept";
		case CommandId.FIND_NEXT:
			return "find_next";
		case CommandId.FIND_PREV:
			return "find_prev";
		case CommandId.FIND_REPLACE:
			return "find_replace";
		case CommandId.FIND_REPLACE_ALL:
			return "find_replace_all";
		case CommandId.FIND_CYCLE_FIELD:
			return "find_cycle_field";
		case CommandId.SEARCH_TOGGLE_CASE:
			return "search_toggle_case";
		case CommandId.SEARCH_TOGGLE_WORD:
			return "search_toggle_word";
		case CommandId.SETTINGS_SCOPE_TOGGLE:
			return "settings_scope_toggle";
		case CommandId.SETTINGS_RESET:
			return "settings_reset";
		case CommandId.SETTINGS_VALUE_DEC:
			return "settings_value_dec";
		case CommandId.SETTINGS_VALUE_INC:
			return "settings_value_inc";
		case CommandId.BROWSER_PARENT:
			return "browser_parent";
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
		case CommandId.PAN_LEFT:
		case CommandId.PAN_RIGHT:
		case CommandId.PAN_UP:
		case CommandId.PAN_DOWN:
		case CommandId.SELECT_LEFT:
		case CommandId.SELECT_RIGHT:
		case CommandId.SELECT_UP:
		case CommandId.SELECT_DOWN:
		case CommandId.CYCLE_NEXT:
		case CommandId.CYCLE_PREV:
		case CommandId.ZOOM_IN:
		case CommandId.ZOOM_OUT:
		case CommandId.FOCUS_EDITOR:
			return has_project;
		case CommandId.FOCUS_TOP_BAR:
		case CommandId.TOPBAR_LEFT:
		case CommandId.TOPBAR_RIGHT:
		case CommandId.TOPBAR_ACTIVATE:
		case CommandId.FOCUS_CANVAS:
		case CommandId.OVERLAY_CLOSE:
		case CommandId.LIST_UP:
		case CommandId.LIST_DOWN:
		case CommandId.LIST_PAGE_UP:
		case CommandId.LIST_PAGE_DOWN:
		case CommandId.LIST_ACCEPT:
		case CommandId.FIND_NEXT:
		case CommandId.FIND_PREV:
		case CommandId.FIND_REPLACE:
		case CommandId.FIND_REPLACE_ALL:
		case CommandId.FIND_CYCLE_FIELD:
		case CommandId.SEARCH_TOGGLE_CASE:
		case CommandId.SEARCH_TOGGLE_WORD:
		case CommandId.SETTINGS_SCOPE_TOGGLE:
		case CommandId.SETTINGS_RESET:
		case CommandId.SETTINGS_VALUE_DEC:
		case CommandId.SETTINGS_VALUE_INC:
		case CommandId.BROWSER_PARENT:
			return true;
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