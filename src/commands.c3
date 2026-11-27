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
const ulong CTX_CONSOLE    = 1 << 14;

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
	FORMAT_DOCUMENT,
	REFERENCES,
	RENAME_SYMBOL,
	CODE_ACTIONS,
	SELECT_THEME,
	SEARCH_PROJECT,
	SEARCH_REPLACE_PROJECT,
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
	CURSOR_WORD_LEFT,
	CURSOR_WORD_RIGHT,
	DELETE_WORD_BACK,
	DELETE_WORD_FORWARD,
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
	TOPBAR_UP,
	TOPBAR_DOWN,
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
	SEARCH_REPLACE,
	SEARCH_REPLACE_ALL,
	SETTINGS_SCOPE_TOGGLE,
	SETTINGS_RESET,
	SETTINGS_VALUE_DEC,
	SETTINGS_VALUE_INC,
	BROWSER_PARENT,
	CLOSE_CARD,
	TOGGLE_CARD,
	RENAME_CARD,
	DUPLICATE_CARD,
	COPY_PATH,
	DELETE_CARD,
	OPEN_CONTEXT_MENU,
	MINIMAP_FOCUS,
	ZOOM_RESET,
	ZOOM_FIT,
	RELAYOUT,
	TOGGLE_PREVIEW,
	LEAVE_FOLDER,
	CYCLE_FOCUS,
	MINIMIZE_CARD,
	TOGGLE_FOCUS_MODE,
	TOGGLE_CONSOLE,
	TOGGLE_SCM,
	CONSOLE_RUN,
	CONSOLE_HISTORY_PREV,
	CONSOLE_HISTORY_NEXT,
	CONSOLE_CLEAR,
	CONSOLE_KILL,
	CONSOLE_COPY,
	CONSOLE_FIND,
	CONSOLE_PASTE,
	CONSOLE_SCROLL_UP,
	CONSOLE_SCROLL_DOWN,
	CONSOLE_LEAVE_FOCUS,
	CONSOLE_NEW_SESSION,
	CONSOLE_CLOSE_SESSION,
	CONSOLE_NEXT_SESSION,
	CONSOLE_PREV_SESSION,
	CONSOLE_RUN_PROFILE,
	CONSOLE_WORD_LEFT,
	CONSOLE_WORD_RIGHT,
	CONSOLE_DELETE_WORD_BACK,
	CONSOLE_DELETE_WORD_FORWARD,
	TOGGLE_CONNECTIONS,
	TOGGLE_ARROWS_OVERLAY,
	PROJECT_DATA,
	QUIT,
}

struct CommandDef
{
	CommandId id;
	String label;
	String description;
	String shortcut;
	bool in_top_bar;
	bool icon_only;
	String bar_label;
	ulong contexts;
	bool repeat;
}

const CommandDef[] COMMAND_DEFS = {
	{
		.id = CommandId.NEW_FILE,
		.description = "Create a new file card on the canvas.",
		.label = "New",
		.shortcut = "Ctrl+N",
		.in_top_bar = true,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.NEW_FOLDER,
		.description = "Create a new folder in the project.",
		.label = "New Folder",
		.shortcut = "",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.OPEN,
		.description = "Open a folder as the current project.",
		.label = "Open",
		.shortcut = "Ctrl+O",
		.in_top_bar = true,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.SAVE,
		.description = "Save the focused file to disk.",
		.label = "Save",
		.shortcut = "Ctrl+S",
		.in_top_bar = true,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.SHOW_PALETTE,
		.description = "Search and run any command.",
		.label = "Command Palette",
		.shortcut = "Ctrl+Shift+P",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.FIND,
		.description = "Find text in the focused file.",
		.label = "Find",
		.shortcut = "Ctrl+F",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.REPLACE,
		.description = "Find and replace text in the focused file.",
		.label = "Replace",
		.shortcut = "Ctrl+H",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.COPY,
		.description = "Copy the selected text.",
		.label = "Copy",
		.shortcut = "Ctrl+C",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.CUT,
		.description = "Cut the selected text.",
		.label = "Cut",
		.shortcut = "Ctrl+X",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.PASTE,
		.description = "Paste clipboard text at the caret.",
		.label = "Paste",
		.shortcut = "Ctrl+V",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.SELECT_ALL,
		.description = "Select the whole focused file.",
		.label = "Select All",
		.shortcut = "Ctrl+A",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.PROBLEMS,
		.description = "Show workspace problems.",
		.label = "Problems",
		.shortcut = "Ctrl+Shift+M",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.GO_TO_DEFINITION,
		.description = "Jump to the symbol under the caret.",
		.label = "Go to Definition",
		.shortcut = "F12",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.COMPLETE,
		.description = "Request completion suggestions.",
		.label = "Complete",
		.shortcut = "Ctrl+Space",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.FORMAT_DOCUMENT,
		.description = "Format the focused document.",
		.label = "Format Document",
		.shortcut = "Ctrl+Alt+F",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.REFERENCES,
		.description = "List references to the symbol under the caret.",
		.label = "Find References",
		.shortcut = "Shift+F12",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.RENAME_SYMBOL,
		.description = "Rename a symbol across the project.",
		.label = "Rename Symbol",
		.shortcut = "F2",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.CODE_ACTIONS,
		.description = "Show available code actions.",
		.label = "Code Actions",
		.shortcut = "Ctrl+.",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.SELECT_THEME,
		.description = "Choose the interface theme.",
		.label = "Theme",
		.shortcut = "Ctrl+Shift+T",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.SEARCH_PROJECT,
		.description = "Search text across the project.",
		.label = "Search in Project",
		.shortcut = "Ctrl+Shift+F",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.SEARCH_REPLACE_PROJECT,
		.description = "Search and replace text across the project.",
		.label = "Search and Replace in Project",
		.bar_label = "Search",
		.shortcut = "Ctrl+Shift+H",
		.in_top_bar = true,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.SYMBOLS_PROJECT,
		.description = "Jump to a symbol in the project.",
		.label = "Go to Symbol",
		.shortcut = "Ctrl+Shift+O",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
	{
		.id = CommandId.TOGGLE_SETTINGS,
		.description = "Open or close settings.",
		.label = "Settings",
		.shortcut = "Ctrl+Shift+S",
		.in_top_bar = true,
		.icon_only = true,
		.contexts = CTX_GLOBAL,
	},
	{
		.id = CommandId.UNDO,
		.description = "Undo the last edit.",
		.label = "Undo",
		.shortcut = "Ctrl+Z",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.REDO,
		.description = "Redo the last undone edit.",
		.label = "Redo",
		.shortcut = "Ctrl+Y",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.INDENT,
		.description = "Indent the selected lines.",
		.label = "Indent",
		.shortcut = "Tab",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.OUTDENT,
		.description = "Outdent the selected lines.",
		.label = "Outdent",
		.shortcut = "Shift+Tab",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.NEWLINE,
		.description = "Insert a new line.",
		.label = "New Line",
		.shortcut = "Enter",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.DELETE_BACK,
		.description = "Delete the character before the caret.",
		.label = "Delete Back",
		.shortcut = "Backspace",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{
		.id = CommandId.DELETE_FORWARD,
		.description = "Delete the character after the caret.",
		.label = "Delete Forward",
		.shortcut = "Delete",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{
		.id = CommandId.CURSOR_LEFT,
		.description = "Move the caret one character left.",
		.label = "Cursor Left",
		.shortcut = "Left",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{
		.id = CommandId.CURSOR_RIGHT,
		.description = "Move the caret one character right.",
		.label = "Cursor Right",
		.shortcut = "Right",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{
		.id = CommandId.CURSOR_UP,
		.description = "Move the caret one line up.",
		.label = "Cursor Up",
		.shortcut = "Up",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.CURSOR_DOWN,
		.description = "Move the caret one line down.",
		.label = "Cursor Down",
		.shortcut = "Down",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{
		.id = CommandId.CURSOR_WORD_LEFT,
		.description = "Move the caret one word left.",
		.label = "Cursor Word Left",
		.shortcut = "Ctrl+Left",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
		.repeat = true,
	},
	{
		.id = CommandId.CURSOR_WORD_RIGHT,
		.description = "Move the caret one word right.",
		.label = "Cursor Word Right",
		.shortcut = "Ctrl+Right",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
		.repeat = true,
	},
	{
		.id = CommandId.DELETE_WORD_BACK,
		.description = "Delete the word before the caret.",
		.label = "Delete Word Back",
		.shortcut = "Ctrl+Backspace",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
		.repeat = true,
	},
	{
		.id = CommandId.DELETE_WORD_FORWARD,
		.description = "Delete the word after the caret.",
		.label = "Delete Word Forward",
		.shortcut = "Ctrl+Delete",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
		.repeat = true,
	},
	{
		.id = CommandId.LINE_START,
		.description = "Move the caret to the line start.",
		.label = "Line Start",
		.shortcut = "Home",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{
		.id = CommandId.LINE_END,
		.description = "Move the caret to the line end.",
		.label = "Line End",
		.shortcut = "End",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.PAGE_UP,
		.description = "Move the caret one page up.",
		.label = "Page Up",
		.shortcut = "PageUp",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.PAGE_DOWN,
		.description = "Move the caret one page down.",
		.label = "Page Down",
		.shortcut = "PageDown",
		.in_top_bar = false,
		.contexts = CTX_EDIT,
	},
	{
		.id = CommandId.EXIT_EDITOR,
		.description = "Leave the editor and return to the canvas.",
		.label = "Exit Editor",
		.shortcut = "Esc",
		.in_top_bar = false,
		.contexts = CTX_EDIT
	},
	{
		.id = CommandId.COMPLETION_NEXT,
		.description = "Select the next completion.",
		.label = "Completion Next",
		.shortcut = "Down",
		.in_top_bar = false,
		.contexts = CTX_COMPLETION,
	},
	{
		.id = CommandId.COMPLETION_PREV,
		.description = "Select the previous completion.",
		.label = "Completion Previous",
		.shortcut = "Up",
		.in_top_bar = false,
		.contexts = CTX_COMPLETION,
	},
	{
		.id = CommandId.COMPLETION_ACCEPT,
		.description = "Accept the selected completion.",
		.label = "Completion Accept",
		.shortcut = "Enter",
		.in_top_bar = false,
		.contexts = CTX_COMPLETION,
	},
	{
		.id = CommandId.COMPLETION_CLOSE,
		.description = "Dismiss the completion list.",
		.label = "Completion Close",
		.shortcut = "Esc",
		.in_top_bar = false,
		.contexts = CTX_COMPLETION,
	},
	{
		.id = CommandId.PAN_LEFT,
		.description = "Pan the canvas left.",
		.label = "Pan Left",
		.shortcut = "Shift+H",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
		.repeat = true,
	},
	{
		.id = CommandId.PAN_RIGHT,
		.description = "Pan the canvas right.",
		.label = "Pan Right",
		.shortcut = "Shift+L",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
		.repeat = true,
	},
	{
		.id = CommandId.PAN_UP,
		.description = "Pan the canvas up.",
		.label = "Pan Up",
		.shortcut = "Shift+K",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
		.repeat = true,
	},
	{
		.id = CommandId.PAN_DOWN,
		.description = "Pan the canvas down.",
		.label = "Pan Down",
		.shortcut = "Shift+J",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
		.repeat = true,
	},
	{
		.id = CommandId.SELECT_LEFT,
		.description = "Select the item to the left.",
		.label = "Select Left",
		.shortcut = "H",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.SELECT_RIGHT,
		.description = "Select the item to the right.",
		.label = "Select Right",
		.shortcut = "L",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.SELECT_UP,
		.description = "Select the item above.",
		.label = "Select Up",
		.shortcut = "K",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.SELECT_DOWN,
		.description = "Select the item below.",
		.label = "Select Down",
		.shortcut = "J",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.CYCLE_NEXT,
		.description = "Select the next item in the folder.",
		.label = "Next Card",
		.shortcut = "]",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.CYCLE_PREV,
		.description = "Select the previous item in the folder.",
		.label = "Previous Card",
		.shortcut = "[",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.ZOOM_IN,
		.description = "Zoom the canvas in.",
		.label = "Zoom In",
		.shortcut = "=",
		.in_top_bar = false,
		.contexts = CTX_MOVE
	},
	{
		.id = CommandId.ZOOM_OUT,
		.description = "Zoom the canvas out.",
		.label = "Zoom Out",
		.shortcut = "-",
		.in_top_bar = false,
		.contexts = CTX_MOVE
	},
	{
		.id = CommandId.FOCUS_TOP_BAR,
		.description = "Move focus to the top bar.",
		.label = "Focus Top Bar",
		.shortcut = "",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.FOCUS_EDITOR,
		.description = "Open the selected card in the editor.",
		.label = "Focus Editor",
		.shortcut = "Enter",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.TOPBAR_LEFT,
		.description = "Focus the previous top bar button.",
		.label = "Top Bar Left",
		.shortcut = "Left",
		.in_top_bar = false,
		.contexts = CTX_TOP_BAR,
		.repeat = true,
	},
	{
		.id = CommandId.TOPBAR_RIGHT,
		.description = "Focus the next top bar button.",
		.label = "Top Bar Right",
		.shortcut = "Right",
		.in_top_bar = false,
		.contexts = CTX_TOP_BAR,
		.repeat = true,
	},
	{
		.id = CommandId.TOPBAR_UP,
		.description = "Focus the top bar button above.",
		.label = "Top Bar Up",
		.shortcut = "Up",
		.in_top_bar = false,
		.contexts = CTX_TOP_BAR,
		.repeat = true,
	},
	{
		.id = CommandId.TOPBAR_DOWN,
		.description = "Focus the top bar button below.",
		.label = "Top Bar Down",
		.shortcut = "Down",
		.in_top_bar = false,
		.contexts = CTX_TOP_BAR,
		.repeat = true,
	},
	{
		.id = CommandId.TOPBAR_ACTIVATE,
		.description = "Activate the focused top bar button.",
		.label = "Top Bar Activate",
		.shortcut = "Enter",
		.in_top_bar = false,
		.contexts = CTX_TOP_BAR,
	},
	{
		.id = CommandId.FOCUS_CANVAS,
		.description = "Return focus from the top bar to the canvas.",
		.label = "Focus Canvas",
		.shortcut = "Esc",
		.in_top_bar = false,
		.contexts = CTX_TOP_BAR,
	},
	{
		.id = CommandId.OVERLAY_CLOSE,
		.description = "Close the active overlay.",
		.label = "Close Overlay",
		.shortcut = "Esc",
		.in_top_bar = false,
		.contexts = CTX_OVERLAY_CLOSE,
	},
	{
		.id = CommandId.LIST_UP,
		.description = "Select the previous item in a list.",
		.label = "List Up",
		.shortcut = "Up",
		.in_top_bar = false,
		.contexts = CTX_OVERLAY_LIST,
		.repeat = true,
	},
	{
		.id = CommandId.LIST_DOWN,
		.description = "Select the next item in a list.",
		.label = "List Down",
		.shortcut = "Down",
		.in_top_bar = false,
		.contexts = CTX_OVERLAY_LIST,
		.repeat = true,
	},
	{
		.id = CommandId.LIST_PAGE_UP,
		.description = "Scroll the list up one page.",
		.label = "List Page Up",
		.shortcut = "PageUp",
		.in_top_bar = false,
		.contexts = CTX_OVERLAY_PAGE,
	},
	{
		.id = CommandId.LIST_PAGE_DOWN,
		.description = "Scroll the list down one page.",
		.label = "List Page Down",
		.shortcut = "PageDown",
		.in_top_bar = false,
		.contexts = CTX_OVERLAY_PAGE,
	},
	{
		.id = CommandId.LIST_ACCEPT,
		.description = "Accept the selected list item.",
		.label = "List Accept",
		.shortcut = "Enter",
		.in_top_bar = false,
		.contexts = CTX_OVERLAY_ACCEPT,
	},
	{
		.id = CommandId.FIND_NEXT,
		.description = "Jump to the next find match.",
		.label = "Find Next",
		.shortcut = "Enter",
		.in_top_bar = false,
		.contexts = CTX_FIND,
	},
	{
		.id = CommandId.FIND_PREV,
		.description = "Jump to the previous find match.",
		.label = "Find Previous",
		.shortcut = "Shift+Enter",
		.in_top_bar = false,
		.contexts = CTX_FIND,
	},
	{
		.id = CommandId.FIND_REPLACE,
		.description = "Replace the current find match.",
		.label = "Replace Match",
		.shortcut = "Ctrl+H",
		.in_top_bar = false,
		.contexts = CTX_FIND,
	},
	{
		.id = CommandId.FIND_REPLACE_ALL,
		.description = "Replace every find match.",
		.label = "Replace All",
		.shortcut = "Ctrl+Enter",
		.in_top_bar = false,
		.contexts = CTX_FIND,
	},
	{
		.id = CommandId.FIND_CYCLE_FIELD,
		.description = "Move between find and replace fields.",
		.label = "Find Field",
		.shortcut = "Tab",
		.in_top_bar = false,
		.contexts = CTX_FIND,
	},
	{
		.id = CommandId.SEARCH_TOGGLE_CASE,
		.description = "Toggle case-sensitive search.",
		.label = "Match Case",
		.shortcut = "Alt+C",
		.in_top_bar = false,
		.contexts = CTX_SEARCH,
	},
	{
		.id = CommandId.SEARCH_TOGGLE_WORD,
		.description = "Toggle whole-word search.",
		.label = "Whole Word",
		.shortcut = "Alt+W",
		.in_top_bar = false,
		.contexts = CTX_SEARCH,
	},
	{
		.id = CommandId.SEARCH_REPLACE,
		.description = "Replace the selected project search match.",
		.label = "Replace Match",
		.shortcut = "Ctrl+Enter",
		.in_top_bar = false,
		.contexts = CTX_SEARCH,
	},
	{
		.id = CommandId.SEARCH_REPLACE_ALL,
		.description = "Replace every project search match.",
		.label = "Replace All in Project",
		.shortcut = "Ctrl+Shift+Enter",
		.in_top_bar = false,
		.contexts = CTX_SEARCH,
	},
	{
		.id = CommandId.SETTINGS_SCOPE_TOGGLE,
		.description = "Switch between global and project settings.",
		.label = "Toggle Scope",
		.shortcut = "Tab",
		.in_top_bar = false,
		.contexts = CTX_SETTINGS,
	},
	{
		.id = CommandId.SETTINGS_RESET,
		.description = "Reset the selected setting or binding.",
		.label = "Reset Setting",
		.shortcut = "Del",
		.in_top_bar = false,
		.contexts = CTX_SETTINGS,
	},
	{
		.id = CommandId.SETTINGS_VALUE_DEC,
		.description = "Decrease the selected setting.",
		.label = "Decrease Value",
		.shortcut = "Left",
		.in_top_bar = false,
		.contexts = CTX_SETTINGS,
		.repeat = true,
	},
	{
		.id = CommandId.SETTINGS_VALUE_INC,
		.description = "Increase the selected setting.",
		.label = "Increase Value",
		.shortcut = "Right",
		.in_top_bar = false,
		.contexts = CTX_SETTINGS,
		.repeat = true,
	},
	{
		.id = CommandId.BROWSER_PARENT,
		.description = "Go to the parent folder in the browser.",
		.label = "Parent Folder",
		.shortcut = "Backspace",
		.in_top_bar = false,
		.contexts = CTX_BROWSER,
	},
	{
		.id = CommandId.CLOSE_CARD,
		.description = "Close the selected card.",
		.label = "Close Card",
		.shortcut = "C",
		.in_top_bar = false,
		.contexts = CTX_MOVE
	},
	{
		.id = CommandId.TOGGLE_CARD,
		.description = "Open or collapse the selected card.",
		.label = "Toggle Card",
		.shortcut = "Space",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.RENAME_CARD,
		.description = "Rename the selected card.",
		.label = "Rename Card",
		.shortcut = "F2",
		.in_top_bar = false,
		.contexts = CTX_MOVE
	},
	{
		.id = CommandId.DUPLICATE_CARD,
		.description = "Duplicate the selected card.",
		.label = "Duplicate Card",
		.shortcut = "Ctrl+D",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.COPY_PATH,
		.description = "Copy the selected card's path.",
		.label = "Copy Path",
		.shortcut = "Ctrl+Shift+C",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.DELETE_CARD,
		.description = "Delete the selected card.",
		.label = "Delete Card",
		.shortcut = "Delete",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.OPEN_CONTEXT_MENU,
		.description = "Open the canvas context menu.",
		.label = "Context Menu",
		.shortcut = "Shift+F10",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.MINIMAP_FOCUS,
		.description = "Focus the content under the minimap.",
		.label = "Focus Content",
		.shortcut = "Shift+M",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.ZOOM_RESET,
		.description = "Reset canvas zoom to 100%.",
		.label = "Reset Zoom",
		.shortcut = "0",
		.in_top_bar = false,
		.contexts = CTX_MOVE
	},
	{
		.id = CommandId.ZOOM_FIT,
		.description = "Fit all content in view.",
		.label = "Fit Content",
		.shortcut = "F",
		.in_top_bar = false,
		.contexts = CTX_MOVE
	},
	{
		.id = CommandId.RELAYOUT,
		.description = "Re-arrange cards using the current card layout.",
		.label = "Relayout Canvas",
		.shortcut = "Ctrl+Alt+L",
		.in_top_bar = false,
		.contexts = CTX_MOVE | CTX_GLOBAL,
	},
	{
		.id = CommandId.TOGGLE_PREVIEW,
		.description = "Show or hide the Markdown preview.",
		.label = "Toggle Preview",
		.shortcut = "Ctrl+Shift+V",
		.in_top_bar = false,
		.contexts = CTX_MOVE | CTX_EDIT,
	},
	{
		.id = CommandId.LEAVE_FOLDER,
		.description = "Leave the current folder.",
		.label = "Leave Folder",
		.shortcut = "Backspace",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.CYCLE_FOCUS,
		.description = "Cycle between grab and top bar focus.",
		.label = "Grab / Focus",
		.shortcut = "Tab",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.MINIMIZE_CARD,
		.description = "Collapse the selected card to its title.",
		.label = "Minimize Card",
		.shortcut = "z",
		.in_top_bar = false,
		.contexts = CTX_MOVE,
	},
	{
		.id = CommandId.TOGGLE_FOCUS_MODE,
		.description = "Expand the focused card to fill the canvas.",
		.label = "Focus Mode",
		.shortcut = "Ctrl+Shift+Enter",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL,
	},
	{
		.id = CommandId.TOGGLE_CONSOLE,
		.description = "Open or close the console.",
		.label = "Console",
		.shortcut = "Ctrl+J",
		.in_top_bar = true,
		.contexts = CTX_GLOBAL,
	},
	{
		.id = CommandId.TOGGLE_SCM,
		.description = "Open or close the Source Control panel.",
		.label = "Source Control",
		.bar_label = "Git",
		.shortcut = "Ctrl+Shift+G",
		.in_top_bar = true,
		.contexts = CTX_GLOBAL,
	},
	{
		.id = CommandId.CONSOLE_RUN,
		.description = "Run the typed console command.",
		.label = "Run Command",
		.shortcut = "Enter",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_HISTORY_PREV,
		.description = "Recall the previous console command.",
		.label = "Console History Previous",
		.shortcut = "Up",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
		.repeat = true,
	},
	{
		.id = CommandId.CONSOLE_HISTORY_NEXT,
		.description = "Recall the next console command.",
		.label = "Console History Next",
		.shortcut = "Down",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
		.repeat = true,
	},
	{
		.id = CommandId.CONSOLE_CLEAR,
		.description = "Clear the console output.",
		.label = "Clear Console",
		.shortcut = "Ctrl+L",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_KILL,
		.description = "Stop the running console command.",
		.label = "Kill Command",
		.shortcut = "Ctrl+C",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_COPY,
		.description = "Copy the console selection or output.",
		.label = "Copy Console Output",
		.shortcut = "Ctrl+Shift+C",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_FIND,
		.description = "Search the console output.",
		.label = "Find in Console",
		.shortcut = "Ctrl+F",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_PASTE,
		.description = "Paste into the console input.",
		.label = "Paste Into Console",
		.shortcut = "Ctrl+V",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_SCROLL_UP,
		.description = "Scroll the console output up.",
		.label = "Console Scroll Up",
		.shortcut = "PageUp",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_SCROLL_DOWN,
		.description = "Scroll the console output down.",
		.label = "Console Scroll Down",
		.shortcut = "PageDown",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_LEAVE_FOCUS,
		.description = "Leave the console input.",
		.label = "Leave Console",
		.shortcut = "Esc",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_NEW_SESSION,
		.description = "Start a new console session.",
		.label = "New Console Session",
		.shortcut = "Ctrl+T",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_CLOSE_SESSION,
		.description = "Close the active console session.",
		.label = "Close Console Session",
		.shortcut = "Ctrl+W",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_NEXT_SESSION,
		.description = "Switch to the next console session.",
		.label = "Next Console Session",
		.shortcut = "Ctrl+Tab",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_PREV_SESSION,
		.description = "Switch to the previous console session.",
		.label = "Previous Console Session",
		.shortcut = "Ctrl+Shift+Tab",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
	},
	{
		.id = CommandId.CONSOLE_RUN_PROFILE,
		.description = "Run a project command profile.",
		.label = "Run Profile",
		.shortcut = "F5",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL,
	},
	{
		.id = CommandId.CONSOLE_WORD_LEFT,
		.description = "Move the console caret one word left.",
		.label = "Console Word Left",
		.shortcut = "Ctrl+Left",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
		.repeat = true,
	},
	{
		.id = CommandId.CONSOLE_WORD_RIGHT,
		.description = "Move the console caret one word right.",
		.label = "Console Word Right",
		.shortcut = "Ctrl+Right",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
		.repeat = true,
	},
	{
		.id = CommandId.CONSOLE_DELETE_WORD_BACK,
		.description = "Delete the word before the console caret.",
		.label = "Console Delete Word Back",
		.shortcut = "Ctrl+Backspace",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
		.repeat = true,
	},
	{
		.id = CommandId.CONSOLE_DELETE_WORD_FORWARD,
		.description = "Delete the word after the console caret.",
		.label = "Console Delete Word Forward",
		.shortcut = "Ctrl+Delete",
		.in_top_bar = false,
		.contexts = CTX_CONSOLE,
		.repeat = true,
	},
	{
		.id = CommandId.TOGGLE_CONNECTIONS,
		.description = "Open or close the connections panel.",
		.label = "Connections",
		.shortcut = "Ctrl+Shift+I",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL,
	},
	{
		.id = CommandId.TOGGLE_ARROWS_OVERLAY,
		.description = "Cycle import connections: off, related only, or all.",
		.label = "Cycle Connections",
		.bar_label = "Arrows",
		.shortcut = "Ctrl+Shift+A",
		.in_top_bar = true,
		.contexts = CTX_GLOBAL,
	},
	{
		.id = CommandId.PROJECT_DATA,
		.description = "Inspect or reset the .yun project data.",
		.label = "Project Data",
		.shortcut = "",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL,
	},
	{
		.id = CommandId.QUIT,
		.description = "Quit Yun.",
		.label = "Quit Yun",
		.shortcut = "Ctrl+Q",
		.in_top_bar = false,
		.contexts = CTX_GLOBAL
	},
};

const String[] COMMAND_GROUPS = {
	"General",
	"Canvas",
	"Editor",
	"Console",
	"Overlays",
	"Settings",
	"Top bar",
};

fn usz command_count()
{
	return COMMAND_DEFS.len;
}

fn String command_description(CommandId id)
{
	return COMMAND_DEFS[(int)id].description;
}

fn String command_group(CommandId id)
{
	switch (id)
	{
		case CommandId.FOCUS_TOP_BAR:
			return "Top bar";
		case CommandId.TOGGLE_SETTINGS:
			return "Settings";
		case CommandId.TOGGLE_CONSOLE:
		case CommandId.CONSOLE_RUN_PROFILE:
			return "Console";
		default:
			break;
	}

	ulong contexts = COMMAND_DEFS[(int)id].contexts;
	if ((contexts & (CTX_CONSOLE)) != 0) return "Console";
	if ((contexts & (CTX_EDIT | CTX_COMPLETION)) != 0) return "Editor";
	if ((contexts & CTX_MOVE) != 0) return "Canvas";
	if ((contexts & CTX_TOP_BAR) != 0) return "Top bar";
	ulong overlay = CTX_PALETTE | CTX_FIND | CTX_SEARCH | CTX_SYMBOLS | CTX_PROBLEMS | CTX_PROMPT | CTX_BROWSER
		| CTX_MENU;
	if ((contexts & overlay) != 0) return "Overlays";
	if ((contexts & (CTX_SETTINGS)) != 0) return "Settings";
	return "General";
}

const CommandId[] TOP_BAR_COMMANDS = {
	CommandId.NEW_FILE,
	CommandId.OPEN,
	CommandId.SAVE,
	CommandId.SEARCH_REPLACE_PROJECT,
	CommandId.TOGGLE_SCM,
	CommandId.TOGGLE_CONSOLE,
	CommandId.TOGGLE_ARROWS_OVERLAY,
	CommandId.TOGGLE_SETTINGS,
};

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
		case CommandId.FORMAT_DOCUMENT:
			return "format_document";
		case CommandId.REFERENCES:
			return "references";
		case CommandId.RENAME_SYMBOL:
			return "rename_symbol";
		case CommandId.CODE_ACTIONS:
			return "code_actions";
		case CommandId.SELECT_THEME:
			return "select_theme";
		case CommandId.SEARCH_PROJECT:
			return "search_project";
		case CommandId.SEARCH_REPLACE_PROJECT:
			return "search_replace_project";
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
		case CommandId.CURSOR_WORD_LEFT:
			return "cursor_word_left";
		case CommandId.CURSOR_WORD_RIGHT:
			return "cursor_word_right";
		case CommandId.DELETE_WORD_BACK:
			return "delete_word_back";
		case CommandId.DELETE_WORD_FORWARD:
			return "delete_word_forward";
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
		case CommandId.TOPBAR_UP:
			return "topbar_up";
		case CommandId.TOPBAR_DOWN:
			return "topbar_down";
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
		case CommandId.SEARCH_REPLACE:
			return "search_replace";
		case CommandId.SEARCH_REPLACE_ALL:
			return "search_replace_all";
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
		case CommandId.CLOSE_CARD:
			return "close_card";
		case CommandId.TOGGLE_CARD:
			return "toggle_card";
		case CommandId.RENAME_CARD:
			return "rename_card";
		case CommandId.DUPLICATE_CARD:
			return "duplicate_card";
		case CommandId.COPY_PATH:
			return "copy_path";
		case CommandId.DELETE_CARD:
			return "delete_card";
		case CommandId.OPEN_CONTEXT_MENU:
			return "open_context_menu";
		case CommandId.MINIMAP_FOCUS:
			return "minimap_focus";
		case CommandId.ZOOM_RESET:
			return "zoom_reset";
		case CommandId.ZOOM_FIT:
			return "zoom_fit";
		case CommandId.RELAYOUT:
			return "relayout";
		case CommandId.TOGGLE_PREVIEW:
			return "toggle_preview";
		case CommandId.LEAVE_FOLDER:
			return "leave_folder";
		case CommandId.CYCLE_FOCUS:
			return "cycle_focus";
		case CommandId.MINIMIZE_CARD:
			return "minimize_card";
		case CommandId.TOGGLE_FOCUS_MODE:
			return "toggle_focus_mode";
		case CommandId.TOGGLE_CONSOLE:
			return "toggle_console";
		case CommandId.TOGGLE_SCM:
			return "toggle_scm";
		case CommandId.CONSOLE_RUN:
			return "console_run";
		case CommandId.CONSOLE_HISTORY_PREV:
			return "console_history_prev";
		case CommandId.CONSOLE_HISTORY_NEXT:
			return "console_history_next";
		case CommandId.CONSOLE_CLEAR:
			return "console_clear";
		case CommandId.CONSOLE_KILL:
			return "console_kill";
		case CommandId.CONSOLE_COPY:
			return "console_copy";
		case CommandId.CONSOLE_FIND:
			return "console_find";
		case CommandId.CONSOLE_PASTE:
			return "console_paste";
		case CommandId.CONSOLE_SCROLL_UP:
			return "console_scroll_up";
		case CommandId.CONSOLE_SCROLL_DOWN:
			return "console_scroll_down";
		case CommandId.CONSOLE_LEAVE_FOCUS:
			return "console_leave_focus";
		case CommandId.CONSOLE_NEW_SESSION:
			return "console_new_session";
		case CommandId.CONSOLE_CLOSE_SESSION:
			return "console_close_session";
		case CommandId.CONSOLE_NEXT_SESSION:
			return "console_next_session";
		case CommandId.CONSOLE_PREV_SESSION:
			return "console_prev_session";
		case CommandId.CONSOLE_RUN_PROFILE:
			return "console_run_profile";
		case CommandId.CONSOLE_WORD_LEFT:
			return "console_word_left";
		case CommandId.CONSOLE_WORD_RIGHT:
			return "console_word_right";
		case CommandId.CONSOLE_DELETE_WORD_BACK:
			return "console_delete_word_back";
		case CommandId.CONSOLE_DELETE_WORD_FORWARD:
			return "console_delete_word_forward";
		case CommandId.TOGGLE_CONNECTIONS:
			return "toggle_connections";
		case CommandId.TOGGLE_ARROWS_OVERLAY:
			return "toggle_arrows_overlay";
		case CommandId.PROJECT_DATA:
			return "project_data";
		case CommandId.QUIT:
			return "quit";
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
	return TOP_BAR_COMMANDS.len;
}

fn CommandDef bar_command(usz slot)
{
	if (slot >= TOP_BAR_COMMANDS.len) return COMMAND_DEFS[0];
	return command_def(TOP_BAR_COMMANDS[slot]);
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
		case CommandId.FORMAT_DOCUMENT:
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
		case CommandId.TOGGLE_CONSOLE:
		case CommandId.TOGGLE_SCM:
		case CommandId.CONSOLE_RUN:
		case CommandId.CONSOLE_HISTORY_PREV:
		case CommandId.CONSOLE_HISTORY_NEXT:
		case CommandId.CONSOLE_CLEAR:
		case CommandId.CONSOLE_KILL:
		case CommandId.CONSOLE_COPY:
		case CommandId.CONSOLE_FIND:
		case CommandId.CONSOLE_PASTE:
		case CommandId.CONSOLE_SCROLL_UP:
		case CommandId.CONSOLE_SCROLL_DOWN:
		case CommandId.CONSOLE_LEAVE_FOCUS:
		case CommandId.CONSOLE_NEW_SESSION:
		case CommandId.CONSOLE_CLOSE_SESSION:
		case CommandId.CONSOLE_NEXT_SESSION:
		case CommandId.CONSOLE_PREV_SESSION:
		case CommandId.CONSOLE_RUN_PROFILE:
		case CommandId.CONSOLE_WORD_LEFT:
		case CommandId.CONSOLE_WORD_RIGHT:
		case CommandId.CONSOLE_DELETE_WORD_BACK:
		case CommandId.CONSOLE_DELETE_WORD_FORWARD:
		case CommandId.QUIT:
			return true;
		case CommandId.GO_TO_DEFINITION:
			return has_buffer;
		case CommandId.COMPLETE:
			return has_buffer;
		case CommandId.REFERENCES:
		case CommandId.RENAME_SYMBOL:
		case CommandId.CODE_ACTIONS:
			return has_buffer;
		case CommandId.SELECT_THEME:
			return true;
		case CommandId.SEARCH_PROJECT:
		case CommandId.SEARCH_REPLACE_PROJECT:
		case CommandId.SEARCH_REPLACE:
		case CommandId.SEARCH_REPLACE_ALL:
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
		case CommandId.CURSOR_WORD_LEFT:
		case CommandId.CURSOR_WORD_RIGHT:
		case CommandId.DELETE_WORD_BACK:
		case CommandId.DELETE_WORD_FORWARD:
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
		case CommandId.RELAYOUT:
		case CommandId.FOCUS_EDITOR:
		case CommandId.LEAVE_FOLDER:
		case CommandId.CYCLE_FOCUS:
		case CommandId.MINIMIZE_CARD:
		case CommandId.TOGGLE_FOCUS_MODE:
		case CommandId.TOGGLE_CONNECTIONS:
		case CommandId.PROJECT_DATA:
			return has_project;
		case CommandId.FOCUS_TOP_BAR:
		case CommandId.TOPBAR_LEFT:
		case CommandId.TOPBAR_RIGHT:
		case CommandId.TOPBAR_UP:
		case CommandId.TOPBAR_DOWN:
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
		case CommandId.TOGGLE_ARROWS_OVERLAY:
		case CommandId.SETTINGS_SCOPE_TOGGLE:
		case CommandId.SETTINGS_RESET:
		case CommandId.SETTINGS_VALUE_DEC:
		case CommandId.SETTINGS_VALUE_INC:
		case CommandId.BROWSER_PARENT:
		case CommandId.ZOOM_RESET:
			return true;
		case CommandId.CLOSE_CARD:
		case CommandId.TOGGLE_CARD:
		case CommandId.RENAME_CARD:
		case CommandId.DUPLICATE_CARD:
		case CommandId.COPY_PATH:
		case CommandId.DELETE_CARD:
		case CommandId.OPEN_CONTEXT_MENU:
		case CommandId.MINIMAP_FOCUS:
		case CommandId.ZOOM_FIT:
			return has_project;
		case CommandId.TOGGLE_PREVIEW:
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