module yun::settings;

import std::collections::list;
import std::collections::object;
import std::core::dstring;

enum SettingKind : int
{
	INT,
	FLOAT,
	BOOL,
	STRING,
	ENUM,
}

enum SettingLayer : int
{
	DEFAULT,
	GLOBAL,
	PROJECT,
}

enum SettingPage : int
{
	GENERAL,
	APPEARANCE,
	EDITOR,
	CANVAS,
	INTEGRATIONS,
	KEYS,
	CONSOLE,
	ADVANCED,
	COUNT,
}

enum SettingId : int
{
	APP_THEME,
	APP_UI_FONT_FAMILY,
	APP_UI_FONT_SIZE,
	APP_UI_SCALE,
	APP_CORNER_RADIUS,
	APP_UI_ICON_THEME,
	APP_FILE_ICON_THEME,
	APP_NOTIFICATIONS_TTL,
	APP_NOTIFICATIONS_MAX,
	APP_NOTIFICATIONS_POSITION,
	APP_TOPBAR_POSITION,
	APP_ANIMATIONS,
	APP_JUMP_HIGHLIGHT_MS,
	APP_EXTERNAL_RELOAD,
	APP_RELOAD_POLL,
	APP_SLEEP_EDITORS,
	APP_SKIP_SUBMODULES,
	EDITOR_FONT_SIZE,
	EDITOR_FONT_FAMILY,
	EDITOR_LINE_HEIGHT,
	EDITOR_PADDING_X,
	EDITOR_PADDING_Y,
	EDITOR_INDENT_STYLE,
	EDITOR_INDENT_WIDTH,
	EDITOR_AUTO_INDENT,
	EDITOR_CARET_BLINK_MS,
	EDITOR_SCROLL_MARGIN_LINES,
	EDITOR_WHEEL_SCROLL_LINES,
	EDITOR_SHOW_LINE_NUMBERS,
	EDITOR_VIM_MODE,
	EDITOR_AUTOSAVE,
	EDITOR_AUTOSAVE_INTERVAL,
	EDITOR_UNDO_MB,
	EDITOR_DIAGNOSTIC_SEGMENTS,
	EDITOR_HIGHLIGHT_MAX_MB,
	CANVAS_ZOOM_MIN,
	CANVAS_ZOOM_MAX,
	CANVAS_ZOOM_STEP,
	CANVAS_KEY_PAN_STEP,
	CANVAS_PAN_SMOOTHING,
	CANVAS_ZOOM_SMOOTHING,
	CANVAS_SMOOTHING,
	CANVAS_FOLLOW_SELECTION,
	CANVAS_INERTIA_FRICTION,
	CANVAS_INERTIA_MIN_SPEED,
	CANVAS_DRAG_THRESHOLD,
	CANVAS_MAX_PAN_DELTA,
	CANVAS_GRID,
	CANVAS_GRID_CELL,
	CANVAS_GRID_MIN_PX,
	CANVAS_GRID_MAX_PX,
	CANVAS_SNAP_TO_GRID,
	CANVAS_SNAP_STEP,
	CANVAS_JUMP_ZOOM_MIN,
	CANVAS_JUMP_ZOOM_TARGET,
	CANVAS_FIT_ON_OPEN,
	CANVAS_FIT_MIN_ZOOM,
	MINIMAP_ENABLED,
	MINIMAP_SIZE,
	MINIMAP_ZOOM_THRESHOLD,
	ARROWS_ENABLED,
	ARROWS_RELATED_ONLY,
	ARROWS_LABELS,
	ARROWS_LINE_THICKNESS,
	ARROWS_HOVER_THICKNESS,
	ARROWS_ARROWHEAD_SIZE,
	ARROWS_HIT_TOLERANCE,
	ARROWS_RESCAN_DEBOUNCE,
	ARROWS_SCAN_WORKERS,
	ARROWS_INTERNAL_STYLE,
	ARROWS_DASH_LENGTH,
	ARROWS_DASH_GAP,
	SEARCH_MAX_FILE_MB,
	SEARCH_MAX_MATCHES_PER_FILE,
	SEARCH_MAX_RESULTS,
	SEARCH_WORKERS,
	SEARCH_DEBOUNCE_MS,
	SEARCH_PREVIEW_MAX,
	CONSOLE_MAX_LINES,
	CONSOLE_MAX_OUTPUT_KB,
	CONSOLE_HISTORY_SIZE,
	CONSOLE_PANEL_HEIGHT,
	CONSOLE_AUTO_SCROLL,
	CONSOLE_AUTOCOMPLETE,
	CONSOLE_WHEEL_LINES,
	CONSOLE_ANSI_COLORS,
	CONSOLE_SHOW_HEADERS,
	CONSOLE_CLEAR_ON_RUN,
	CONSOLE_KILL_ON_CLOSE,
	CONSOLE_NOTIFY,
	CONSOLE_PERSIST_HISTORY,
	CONSOLE_RESTORE_SESSIONS,
	CONSOLE_PTY,
	GIT_BINARY,
	GIT_AUTO_REFRESH,
	GIT_DEBOUNCE_MS,
	GIT_CONFIRM_DISCARD,
	GIT_DEFAULT_REMOTE,
	LSP_ENABLED,
	MODS_ENABLED,
	MODS_ALLOW_RENDER,
	MODS_ALLOW_INPUT,
	COUNT,
}

const int SETTING_COUNT = (int)SettingId.COUNT;

struct SettingValue
{
	long i;
	double f;
	bool b;
	String s;
}

struct SettingSpec
{
	String section;
	String key;
	String label;
	String description;
	SettingKind kind;
	SettingValue fallback;
	double min;
	double max;
	double step;
	String[] options;
}

const SettingSpec[] SETTINGS = {
	{
		.section = "app",
		.key = "theme",
		.label = "Theme",
		.description = "Colour theme name.",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "dark" },
		.min = 0.0,
		.max = 0.0,
		.step = 0.0,
		.options = {
			"yun_dark",
			"yun_light",
			"dracula",
			"one_dark",
			"gruvbox_dark",
			"gruvbox_light",
			"nord",
			"catppuccin_mocha",
			"catppuccin_latte",
		},
	},
	{
		.section = "app",
		.key = "ui_font_family",
		.label = "UI font",
		.description = "Font used for the interface (monospace fonts on the system).",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "JetBrains Mono" },
		.options = { "JetBrains Mono" },
	},
	{
		.section = "app",
		.key = "ui_font_size",
		.label = "UI font size",
		.description = "Interface font size in pixels.",
		.kind = SettingKind.INT,
		.fallback = { .i = 16 },
		.min = 8.0,
		.max = 32.0,
		.step = 1.0,
	},
	{
		.section = "app",
		.key = "ui_scale",
		.label = "UI scale",
		.description = "Scale factor for the whole interface (geometry and text).",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 1.0 },
		.min = 0.5,
		.max = 2.0,
		.step = 0.05,
	},
	{
		.section = "app",
		.key = "corner_radius",
		.label = "Corner radius",
		.description = "Rounded corner radius for cards, panels, and controls. 0 keeps sharp corners.",
		.kind = SettingKind.INT,
		.fallback = { .i = 6 },
		.min = 0.0,
		.max = 16.0,
		.step = 1.0,
	},
	{
		.section = "app",
		.key = "ui_icon_theme",
		.label = "UI icon theme",
		.description = "Icon style for buttons and panels: Codicons (VS Code) or the built-in vector set.",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "codicons" },
		.options = { "codicons", "vector" },
	},
	{
		.section = "app",
		.key = "file_icon_theme",
		.label = "File icon theme",
		.description = "Language/file icon pack: Material Icon Theme, vscode-icons, or none.",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "material" },
		.options = { "material", "vscode", "none" },
	},
	{
		.section = "app",
		.key = "notifications_ttl",
		.label = "Notification TTL",
		.description = "Seconds a notification stays visible.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 4.0 },
		.min = 0.5,
		.max = 30.0,
		.step = 0.5,
	},
	{
		.section = "app",
		.key = "notifications_max",
		.label = "Max notifications",
		.description = "Maximum notifications kept on screen.",
		.kind = SettingKind.INT,
		.fallback = { .i = 5 },
		.min = 1.0,
		.max = 20.0,
		.step = 1.0,
	},
	{
		.section = "app",
		.key = "notifications_position",
		.label = "Notification position",
		.description = "Where notifications appear on screen.",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "bottom_left" },
		.options = { "top_left", "top_right", "bottom_left", "bottom_right" },
	},
	{
		.section = "app",
		.key = "topbar_position",
		.label = "Top bar position",
		.description = "Dock the top bar to any screen edge.",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "top" },
		.options = { "top", "bottom", "left", "right" },
	},
	{
		.section = "app",
		.key = "animations",
		.label = "Animations",
		.description = "Enable short panel and camera transitions.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "app",
		.key = "jump_highlight_ms",
		.label = "Jump highlight",
		.description = "Duration of the jump-to-line highlight in milliseconds. 0 disables it.",
		.kind = SettingKind.INT,
		.fallback = { .i = 1000 },
		.min = 0.0,
		.max = 5000.0,
		.step = 100.0,
	},
	{
		.section = "app",
		.key = "external_reload",
		.label = "External reload",
		.description = "Detect files changed outside Yun and prompt to reload.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "app",
		.key = "reload_poll",
		.label = "Reload poll",
		.description = "Seconds between external file-change checks.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 1.0 },
		.min = 0.25,
		.max = 10.0,
		.step = 0.25,
	},
	{
		.section = "app",
		.key = "sleep_editors",
		.label = "Sleep editors",
		.description = "Free off-screen editor buffers and reload them when visible.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "app",
		.key = "skip_submodules",
		.label = "Skip submodules",
		.description = "Do not scan nested git repositories (submodules, vendored deps) as project files.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "editor",
		.key = "font_size",
		.label = "Font size",
		.description = "Editor font size in pixels.",
		.kind = SettingKind.INT,
		.fallback = { .i = 16 },
		.min = 8.0,
		.max = 48.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "font_family",
		.label = "Font family",
		.description = "Editor font (monospace fonts found on the system).",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "JetBrains Mono" },
		.options = { "JetBrains Mono" },
	},
	{
		.section = "editor",
		.key = "line_height",
		.label = "Line height",
		.description = "Line height multiplier.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 1.25 },
		.min = 1.0,
		.max = 2.5,
		.step = 0.05,
	},
	{
		.section = "editor",
		.key = "padding_x",
		.label = "Padding X",
		.description = "Horizontal editor padding in pixels.",
		.kind = SettingKind.INT,
		.fallback = { .i = 8 },
		.min = 0.0,
		.max = 40.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "padding_y",
		.label = "Padding Y",
		.description = "Vertical editor padding in pixels.",
		.kind = SettingKind.INT,
		.fallback = { .i = 6 },
		.min = 0.0,
		.max = 40.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "indent_style",
		.label = "Indent style",
		.description = "Indent with tabs or spaces.",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "tabs" },
		.options = { "tabs", "spaces" },
	},
	{
		.section = "editor",
		.key = "indent_width",
		.label = "Indent width",
		.description = "Columns per indent level (and spaces when using spaces).",
		.kind = SettingKind.INT,
		.fallback = { .i = 4 },
		.min = 1.0,
		.max = 16.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "auto_indent",
		.label = "Auto indent",
		.description = "Match the previous line's indentation on Enter.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "editor",
		.key = "caret_blink_ms",
		.label = "Caret blink (ms)",
		.description = "Caret blink interval in milliseconds (0 = steady).",
		.kind = SettingKind.INT,
		.fallback = { .i = 500 },
		.min = 0.0,
		.max = 2000.0,
		.step = 50.0,
	},
	{
		.section = "editor",
		.key = "scroll_margin_lines",
		.label = "Scroll margin",
		.description = "Lines kept visible around the caret.",
		.kind = SettingKind.INT,
		.fallback = { .i = 1 },
		.min = 0.0,
		.max = 10.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "wheel_scroll_lines",
		.label = "Wheel scroll",
		.description = "Lines scrolled per mouse-wheel notch.",
		.kind = SettingKind.INT,
		.fallback = { .i = 3 },
		.min = 1.0,
		.max = 20.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "show_line_numbers",
		.label = "Line numbers",
		.description = "Show the line-number gutter.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "editor",
		.key = "vim_mode",
		.label = "Vim mode",
		.description = "Enable optional Vim modal editing (Normal, Insert, Visual).",
		.kind = SettingKind.BOOL,
		.fallback = { .b = false },
	},
	{
		.section = "editor",
		.key = "autosave",
		.label = "Autosave",
		.description = "Save dirty buffers automatically.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = false },
	},
	{
		.section = "editor",
		.key = "autosave_interval",
		.label = "Autosave interval",
		.description = "Seconds between autosave passes.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 30.0 },
		.min = 1.0,
		.max = 600.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "undo_mb",
		.label = "Undo history",
		.description = "Approximate undo-history budget in megabytes.",
		.kind = SettingKind.INT,
		.fallback = { .i = 4 },
		.min = 1.0,
		.max = 256.0,
		.step = 1.0,
	},
	{
		.section = "editor",
		.key = "diagnostic_segments",
		.label = "Diagnostic segments",
		.description = "Maximum diagnostic underline segments per draw pass.",
		.kind = SettingKind.INT,
		.fallback = { .i = 512 },
		.min = 64.0,
		.max = 4096.0,
		.step = 64.0,
	},
	{
		.section = "editor",
		.key = "highlight_max_mb",
		.label = "Highlight max size",
		.description = "Skip syntax highlighting for files larger than this many megabytes; 0 disables the limit.",
		.kind = SettingKind.INT,
		.fallback = { .i = 4 },
		.min = 0.0,
		.max = 1024.0,
		.step = 1.0,
	},
	{
		.section = "canvas",
		.key = "zoom_min",
		.label = "Zoom min",
		.description = "Smallest canvas zoom factor.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 0.1 },
		.min = 0.01,
		.max = 4.0,
		.step = 0.05,
	},
	{
		.section = "canvas",
		.key = "zoom_max",
		.label = "Zoom max",
		.description = "Largest canvas zoom factor.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 8.0 },
		.min = 0.25,
		.max = 100.0,
		.step = 0.25,
	},
	{
		.section = "canvas",
		.key = "zoom_step",
		.label = "Zoom step",
		.description = "Multiplier applied per zoom notch (must be above 1.0).",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 1.1 },
		.min = 1.001,
		.max = 2.0,
		.step = 0.01,
	},
	{
		.section = "canvas",
		.key = "key_pan_step",
		.label = "Keyboard pan",
		.description = "Screen pixels moved per keyboard pan press.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 48.0 },
		.min = 4.0,
		.max = 512.0,
		.step = 4.0,
	},
	{
		.section = "canvas",
		.key = "pan_smoothing",
		.label = "Pan smoothing",
		.description = "How quickly the camera catches up while panning (higher is snappier).",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 20.0 },
		.min = 1.0,
		.max = 100.0,
		.step = 1.0,
	},
	{
		.section = "canvas",
		.key = "zoom_smoothing",
		.label = "Zoom smoothing",
		.description = "How quickly the camera catches up while zooming (higher is snappier).",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 16.0 },
		.min = 1.0,
		.max = 100.0,
		.step = 1.0,
	},
	{
		.section = "canvas",
		.key = "smoothing",
		.label = "Smoothing",
		.description = "Ease camera pan and zoom instead of snapping instantly.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "canvas",
		.key = "follow_selection",
		.label = "Center selected card",
		.description = "Keep the keyboard-selected card centered while navigating.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "canvas",
		.key = "inertia_friction",
		.label = "Inertia friction",
		.description = "Per-frame velocity decay after a fling (lower stops sooner).",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 0.9 },
		.min = 0.0,
		.max = 0.99,
		.step = 0.01,
	},
	{
		.section = "canvas",
		.key = "inertia_min_speed",
		.label = "Inertia min speed",
		.description = "Speed below which the fling stops.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 5.0 },
		.min = 0.0,
		.max = 200.0,
		.step = 1.0,
	},
	{
		.section = "canvas",
		.key = "drag_threshold",
		.label = "Drag threshold",
		.description = "Pixels of movement before a press becomes a drag.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 4.0 },
		.min = 0.0,
		.max = 64.0,
		.step = 1.0,
	},
	{
		.section = "canvas",
		.key = "max_pan_delta",
		.label = "Max pan delta",
		.description = "Largest screen-space movement accepted in one frame.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 200.0 },
		.min = 1.0,
		.max = 2000.0,
		.step = 10.0,
	},
	{
		.section = "canvas",
		.key = "grid",
		.label = "Grid",
		.description = "Draw the canvas grid.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "canvas",
		.key = "grid_cell",
		.label = "Grid cell",
		.description = "Base grid cell size in world units.",
		.kind = SettingKind.INT,
		.fallback = { .i = 64 },
		.min = 16.0,
		.max = 512.0,
		.step = 8.0,
	},
	{
		.section = "canvas",
		.key = "grid_min_px",
		.label = "Grid min spacing",
		.description = "Smallest on-screen grid spacing before the grid doubles.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 16.0 },
		.min = 4.0,
		.max = 128.0,
		.step = 2.0,
	},
	{
		.section = "canvas",
		.key = "grid_max_px",
		.label = "Grid max spacing",
		.description = "Largest on-screen grid spacing before the grid halves.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 64.0 },
		.min = 16.0,
		.max = 512.0,
		.step = 8.0,
	},
	{
		.section = "canvas",
		.key = "snap_to_grid",
		.label = "Snap to grid",
		.description = "Snap cards and folders to the canvas grid while dragging or resizing.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "canvas",
		.key = "snap_step",
		.label = "Snap step",
		.description = "Grid snap step in world units; 0 uses the visible grid step.",
		.kind = SettingKind.INT,
		.fallback = { .i = 0 },
		.min = 0.0,
		.max = 1024.0,
		.step = 8.0,
	},
	{
		.section = "canvas",
		.key = "jump_zoom_min",
		.label = "Jump zoom min",
		.description = "Zoom below which navigating to a card zooms in.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 0.6 },
		.min = 0.01,
		.max = 8.0,
		.step = 0.05,
	},
	{
		.section = "canvas",
		.key = "jump_zoom_target",
		.label = "Jump zoom target",
		.description = "Zoom applied when navigating to a card at low zoom.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 1.0 },
		.min = 0.01,
		.max = 8.0,
		.step = 0.05,
	},
	{
		.section = "canvas",
		.key = "fit_on_open",
		.label = "Fit on open",
		.description = "Zoom to fit the whole project when a project is first opened (no saved layout).",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "canvas",
		.key = "fit_min_zoom",
		.label = "Fit min zoom",
		.description = "Lowest zoom the fit-on-open may use; huge projects start here near the origin instead of zooming far out.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 0.4 },
		.min = 0.02,
		.max = 4.0,
		.step = 0.05,
	},
	{
		.section = "minimap",
		.key = "enabled",
		.label = "Minimap",
		.description = "Show the minimap when zoomed out.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "minimap",
		.key = "size",
		.label = "Minimap size",
		.description = "Scale factor for the minimap panel.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 1.0 },
		.min = 0.5,
		.max = 2.0,
		.step = 0.05,
	},
	{
		.section = "minimap",
		.key = "zoom_threshold",
		.label = "Minimap zoom threshold",
		.description = "Show the minimap only below this zoom.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 0.4 },
		.min = 0.0,
		.max = 8.0,
		.step = 0.05,
	},
	{
		.section = "arrows",
		.key = "enabled",
		.label = "Arrows",
		.description = "Draw import connections between cards.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "arrows",
		.key = "related_only",
		.label = "Related arrows only",
		.description = "Draw arrows only for the selected, focused, or hovered card.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "arrows",
		.key = "labels",
		.label = "Arrow labels",
		.description = "Show the import specifier label next to related arrows.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "arrows",
		.key = "line_thickness",
		.label = "Line thickness",
		.description = "Arrow line thickness in screen pixels.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 2.0 },
		.min = 0.5,
		.max = 12.0,
		.step = 0.5,
	},
	{
		.section = "arrows",
		.key = "hover_thickness",
		.label = "Hover thickness",
		.description = "Arrow line thickness while hovered, in screen pixels.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 3.6 },
		.min = 0.5,
		.max = 24.0,
		.step = 0.5,
	},
	{
		.section = "arrows",
		.key = "arrowhead_size",
		.label = "Arrowhead size",
		.description = "Arrowhead length in screen pixels.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 10.0 },
		.min = 2.0,
		.max = 40.0,
		.step = 1.0,
	},
	{
		.section = "arrows",
		.key = "hit_tolerance",
		.label = "Hover tolerance",
		.description = "Screen-pixel distance within which an arrow counts as hovered.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 6.0 },
		.min = 1.0,
		.max = 40.0,
		.step = 1.0,
	},
	{
		.section = "arrows",
		.key = "rescan_debounce",
		.label = "Rescan debounce",
		.description = "Seconds to wait after an edit before rescanning imports.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 0.15 },
		.min = 0.0,
		.max = 2.0,
		.step = 0.05,
	},
	{
		.section = "arrows",
		.key = "scan_workers",
		.label = "Scan workers",
		.description = "Import scan worker threads (0 = automatic from CPU count).",
		.kind = SettingKind.INT,
		.fallback = { .i = 0 },
		.min = 0.0,
		.max = 8.0,
		.step = 1.0,
	},
	{
		.section = "arrows",
		.key = "internal_style",
		.label = "Internal style",
		.description = "Line style for arrows to imports resolved inside the project.",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "solid" },
		.options = { "solid", "dashed", "dotted", "long-dash", "dash-dot" },
	},
	{
		.section = "arrows",
		.key = "dash_length",
		.label = "Dash length",
		.description = "Dash length in screen pixels for non-solid arrow styles.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 8.0 },
		.min = 1.0,
		.max = 64.0,
		.step = 1.0,
	},
	{
		.section = "arrows",
		.key = "dash_gap",
		.label = "Dash gap",
		.description = "Gap length in screen pixels for non-solid arrow styles.",
		.kind = SettingKind.FLOAT,
		.fallback = { .f = 6.0 },
		.min = 1.0,
		.max = 64.0,
		.step = 1.0,
	},
	{
		.section = "search",
		.key = "max_file_mb",
		.label = "Max file size",
		.description = "Skip project-search files larger than this many megabytes.",
		.kind = SettingKind.INT,
		.fallback = { .i = 2 },
		.min = 1.0,
		.max = 512.0,
		.step = 1.0,
	},
	{
		.section = "search",
		.key = "max_matches_per_file",
		.label = "Matches per file",
		.description = "Maximum matches kept per file.",
		.kind = SettingKind.INT,
		.fallback = { .i = 200 },
		.min = 10.0,
		.max = 1000.0,
		.step = 10.0,
	},
	{
		.section = "search",
		.key = "max_results",
		.label = "Max results",
		.description = "Maximum project-search results.",
		.kind = SettingKind.INT,
		.fallback = { .i = 2000 },
		.min = 50.0,
		.max = 10000.0,
		.step = 50.0,
	},
	{
		.section = "search",
		.key = "workers",
		.label = "Search workers",
		.description = "Worker threads used for project search (1-16).",
		.kind = SettingKind.INT,
		.fallback = { .i = 4 },
		.min = 1.0,
		.max = 16.0,
		.step = 1.0,
	},
	{
		.section = "search",
		.key = "debounce_ms",
		.label = "Search debounce",
		.description = "Delay before restarting a project search, in milliseconds.",
		.kind = SettingKind.INT,
		.fallback = { .i = 150 },
		.min = 50.0,
		.max = 2000.0,
		.step = 50.0,
	},
	{
		.section = "search",
		.key = "preview_length",
		.label = "Preview length",
		.description = "Characters shown in each match preview.",
		.kind = SettingKind.INT,
		.fallback = { .i = 120 },
		.min = 20.0,
		.max = 500.0,
		.step = 10.0,
	},
	{
		.section = "console",
		.key = "max_lines",
		.label = "Max output lines",
		.description = "Maximum output lines retained by the console.",
		.kind = SettingKind.INT,
		.fallback = { .i = 2000 },
		.min = 100.0,
		.max = 100000.0,
		.step = 100.0,
	},
	{
		.section = "console",
		.key = "max_output_kb",
		.label = "Max output size",
		.description = "Maximum console output retained, in kilobytes.",
		.kind = SettingKind.INT,
		.fallback = { .i = 1024 },
		.min = 16.0,
		.max = 1048576.0,
		.step = 64.0,
	},
	{
		.section = "console",
		.key = "history_size",
		.label = "History size",
		.description = "Number of commands kept in console history.",
		.kind = SettingKind.INT,
		.fallback = { .i = 100 },
		.min = 1.0,
		.max = 10000.0,
		.step = 10.0,
	},
	{
		.section = "console",
		.key = "panel_height",
		.label = "Panel height",
		.description = "Console panel height in logical pixels.",
		.kind = SettingKind.INT,
		.fallback = { .i = 220 },
		.min = 120.0,
		.max = 2000.0,
		.step = 10.0,
	},
	{
		.section = "console",
		.key = "auto_scroll",
		.label = "Auto-scroll",
		.description = "Follow new console output unless scrolled up.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "console",
		.key = "autocomplete",
		.label = "Autocomplete",
		.description = "Show previous commands as inline ghost text while typing.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "console",
		.key = "wheel_lines",
		.label = "Wheel scroll lines",
		.description = "Output lines scrolled per mouse-wheel notch.",
		.kind = SettingKind.INT,
		.fallback = { .i = 3 },
		.min = 1.0,
		.max = 20.0,
		.step = 1.0,
	},
	{
		.section = "console",
		.key = "ansi_colors",
		.label = "ANSI colors",
		.description = "Render ANSI colors from command output; off strips them.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "console",
		.key = "show_command_headers",
		.label = "Command headers",
		.description = "Show the $ command label before each run's output.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "console",
		.key = "clear_on_run",
		.label = "Clear on run",
		.description = "Clear previous output when a new command starts.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = false },
	},
	{
		.section = "console",
		.key = "kill_on_close",
		.label = "Kill on close",
		.description = "Kill a running command when the console panel is closed.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = false },
	},
	{
		.section = "console",
		.key = "notify",
		.label = "Notifications",
		.description = "Notify when a command finishes: never, failure, or always.",
		.kind = SettingKind.ENUM,
		.fallback = { .s = "failure" },
		.options = { "never", "failure", "always" },
	},
	{
		.section = "console",
		.key = "persist_history",
		.label = "Persist history",
		.description = "Save per-project command history in the workspace.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "console",
		.key = "restore_sessions",
		.label = "Restore sessions",
		.description = "Restore console session tabs on project open.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "console",
		.key = "pty",
		.label = "Interactive terminal",
		.description = "Use a persistent PTY shell instead of one-shot command runs.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = false },
	},
	{
		.section = "git",
		.key = "binary",
		.label = "Git binary",
		.description = "Git executable name or path. An empty value falls back to git.",
		.kind = SettingKind.STRING,
		.fallback = { .s = "git" },
	},
	{
		.section = "git",
		.key = "auto_refresh",
		.label = "Auto refresh",
		.description = "Refresh repository status after saves, file changes, focus changes, and periodically.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "git",
		.key = "debounce_ms",
		.label = "Refresh debounce",
		.description = "Delay before refreshing Git status, in milliseconds.",
		.kind = SettingKind.INT,
		.fallback = { .i = 250 },
		.min = 0.0,
		.max = 5000.0,
		.step = 50.0,
	},
	{
		.section = "git",
		.key = "confirm_discard",
		.label = "Confirm discard",
		.description = "Ask before discarding working-tree changes.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "git",
		.key = "default_remote",
		.label = "Default remote",
		.description = "Remote used for fetch, pull, and push actions.",
		.kind = SettingKind.STRING,
		.fallback = { .s = "origin" },
	},
	{
		.section = "lsp",
		.key = "enabled",
		.label = "Language servers",
		.description = "Start configured language servers.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "mods",
		.key = "enabled",
		.label = "Enable mods",
		.description = "Load Lua mods from the global mods folder and the project .yun/mods folder.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = true },
	},
	{
		.section = "mods",
		.key = "allow_render",
		.label = "Allow rendering",
		.description = "Let mods draw overlays with the yun.draw API. Community mods should stay off.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = false },
	},
	{
		.section = "mods",
		.key = "allow_input",
		.label = "Allow input",
		.description = "Let mods read keyboard and mouse input for on_update and on_input hooks.",
		.kind = SettingKind.BOOL,
		.fallback = { .b = false },
	},
};

struct Override
{
	SettingId id;
	SettingValue value;
}

struct Settings
{
	Allocator allocator;
	List{Override} global;
	List{Override} project;
	bool[SETTING_COUNT] changed;
}

fn SettingSpec spec(SettingId id)
{
	return SETTINGS[(int)id];
}

String[] g_font_options = { };

fn void set_font_options(String[] options)
{
	g_font_options = options;
}

fn String[] setting_options(SettingId id)
{
	if ((id == SettingId.EDITOR_FONT_FAMILY || id == SettingId.APP_UI_FONT_FAMILY) && g_font_options.len > 0)
	{
		return g_font_options;
	}
	return spec(id).options;
}

fn SettingPage page_for(SettingId id)
{
	SettingSpec s = spec(id);
	if (s.section.compare_to("editor") == 0)
	{
		if (s.key.compare_to(
			"undo_mb"
		) == 0 || s.key.compare_to("diagnostic_segments") == 0) return SettingPage.ADVANCED;
		return SettingPage.EDITOR;
	}
	if (s.section.compare_to(
		"canvas"
	) == 0 || s.section.compare_to("minimap") == 0 || s.section.compare_to("arrows") == 0) return SettingPage.CANVAS;
	if (s.section.compare_to("search") == 0) return SettingPage.ADVANCED;
	if (s.section.compare_to("console") == 0) return SettingPage.CONSOLE;
	if (s.section.compare_to("git") == 0) return SettingPage.INTEGRATIONS;
	if (s.section.compare_to("lsp") == 0) return SettingPage.INTEGRATIONS;
	if (s.section.compare_to("mods") == 0) return SettingPage.ADVANCED;
	if (s.section.compare_to("app") == 0)
	{
		if (s.key.compare_to("skip_submodules") == 0) return SettingPage.GENERAL;
		if (s.key.compare_to(
			"external_reload"
		) == 0 || s.key.compare_to(
			"reload_poll"
		) == 0 || s.key.compare_to("sleep_editors") == 0) return SettingPage.INTEGRATIONS;
		return SettingPage.APPEARANCE;
	}
	return SettingPage.GENERAL;
}

fn String page_label(SettingPage page)
{
	switch (page)
	{
		case SettingPage.GENERAL:
			return "General";
		case SettingPage.APPEARANCE:
			return "Appearance";
		case SettingPage.EDITOR:
			return "Editor";
		case SettingPage.CANVAS:
			return "Canvas";
		case SettingPage.INTEGRATIONS:
			return "Integrations";
		case SettingPage.KEYS:
			return "Keys";
		case SettingPage.CONSOLE:
			return "Console";
		case SettingPage.ADVANCED:
			return "Advanced";
		case SettingPage.COUNT:
			return "";
	}
}

fn String group_for(SettingId id)
{
	SettingSpec s = spec(id);
	if (s.section.compare_to("app") == 0)
	{
		if (s.key.starts_with("notifications_")) return "Notifications";
		if (s.key.compare_to("animations") == 0 || s.key.compare_to("jump_highlight_ms") == 0) return "Behavior";
		if (s.key.compare_to(
			"external_reload"
		) == 0 || s.key.compare_to("reload_poll") == 0 || s.key.compare_to("sleep_editors") == 0) return "Files";
		if (s.key.compare_to("skip_submodules") == 0) return "Project";
		return "Interface";
	}
	if (s.section.compare_to("editor") == 0)
	{
		if (s.key.compare_to("autosave") == 0 || s.key.compare_to("autosave_interval") == 0) return "Files";
		if (s.key.compare_to("undo_mb") == 0 || s.key.compare_to("diagnostic_segments") == 0) return "Advanced";
		if (s.key.compare_to(
			"show_line_numbers"
		) == 0 || s.key.starts_with(
			"caret"
		) || s.key.starts_with("scroll") || s.key.starts_with("wheel")) return "Editing";
		return "Text";
	}
	if (s.section.compare_to("canvas") == 0)
	{
		if (s.key.starts_with("grid") || s.key.starts_with("snap")) return "Grid";
		return "Navigation";
	}
	if (s.section.compare_to("minimap") == 0) return "Minimap";
	if (s.section.compare_to("arrows") == 0) return "Imports";
	if (s.section.compare_to("search") == 0) return "Search limits";
	if (s.section.compare_to("console") == 0)
	{
		if (s.key.compare_to("max_lines") == 0 || s.key.compare_to("max_output_kb") == 0) return "Limits";
		if (s.key.compare_to("history_size") == 0 || s.key.compare_to("persist_history") == 0) return "History";
		if (s.key.compare_to("autocomplete") == 0) return "Completion";
		if (s.key.compare_to(
			"ansi_colors"
		) == 0 || s.key.compare_to(
			"show_command_headers"
		) == 0 || s.key.compare_to("clear_on_run") == 0) return "Behavior";
		if (s.key.compare_to("notify") == 0) return "Notifications";
		if (s.key.compare_to("restore_sessions") == 0) return "Sessions";
		return "Panel";
	}
	if (s.section.compare_to("git") == 0) return "Git";
	if (s.section.compare_to("lsp") == 0) return "Language servers";
	if (s.section.compare_to("mods") == 0) return "Mods";
	return "General";
}

fn bool is_advanced(SettingId id)
{
	return page_for(id) == SettingPage.ADVANCED;
}

fn bool is_section(String name)
{
	foreach (SettingSpec s : SETTINGS)
	{
		if (s.section.compare_to(name) == 0) return true;
	}
	return false;
}

fn bool section_has_key(String section, String key)
{
	foreach (SettingSpec s : SETTINGS)
	{
		if (s.section.compare_to(section) == 0 && s.key.compare_to(key) == 0) return true;
	}
	return false;
}

fn bool section_is_first(usz index)
{
	String section = SETTINGS[index].section;
	for (usz j = 0; j < index; j++)
	{
		if (SETTINGS[j].section.compare_to(section) == 0) return false;
	}
	return true;
}

fn void append_json_string(DString* out, String s)
{
	out.append_char('"');
	for (usz i = 0; i < s.len; i++)
	{
		char c = s[i];
		if (c == '"' || c == '\\') out.append_char('\\');
		out.append_char(c);
	}
	out.append_char('"');
}

fn void free_value(Allocator allocator, SettingValue* value)
{
	if (value.s.ptr != null) value.s.free(allocator);
}

fn long clamp_int(SettingSpec s, long value)
{
	if (value < (long)s.min) return (long)s.min;
	if (value > (long)s.max) return (long)s.max;
	return value;
}

fn double clamp_float(SettingSpec s, double value)
{
	if (value < s.min) return s.min;
	if (value > s.max) return s.max;
	return value;
}

fn void Settings.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.global.init(allocator);
	self.project.init(allocator);
	for (int i = 0; i < SETTING_COUNT; i++) self.changed[i] = false;
}

fn void Settings.free_layer(&self, List{Override}* list)
{
	for (sz i = 0; i < list.len(); i++)
	{
		free_value(self.allocator, &list.get_ref(i).value);
	}
	list.clear();
}

fn void Settings.destroy(&self)
{
	self.free_layer(&self.global);
	self.free_layer(&self.project);
	self.global.free();
	self.project.free();
}

fn void Settings.reset(&self)
{
	self.free_layer(&self.global);
	self.free_layer(&self.project);
	for (int i = 0; i < SETTING_COUNT; i++) self.changed[i] = false;
}

fn void Settings.mark_all_changed(&self)
{
	for (int i = 0; i < SETTING_COUNT; i++) self.changed[i] = true;
}

fn bool Settings.consume_change(&self, SettingId id)
{
	int i        = (int)id;
	bool changed = self.changed[i];
	self.changed[i] = false;
	return changed;
}

fn List{Override}* Settings.layer_list(&self, SettingLayer layer)
{
	switch (layer)
	{
		case SettingLayer.GLOBAL:
			return &self.global;
		case SettingLayer.PROJECT:
			return &self.project;
		case SettingLayer.DEFAULT:
			return null;
	}
}

fn sz Settings.layer_index(&self, List{Override}* list, SettingId id)
{
	if (list == null) return -1;
	for (sz i = 0; i < list.len(); i++)
	{
		if (list.get(i).id == id) return i;
	}
	return -1;
}

fn SettingValue Settings.value_in(&self, SettingId id, SettingLayer layer)
{
	List{Override}* list = self.layer_list(layer);
	sz index             = self.layer_index(list, id);
	if (index >= 0) return list.get(index).value;
	return spec(id).fallback;
}

fn SettingValue Settings.effective(&self, SettingId id)
{
	sz project = self.layer_index(&self.project, id);
	if (project >= 0) return self.project.get(project).value;
	sz global = self.layer_index(&self.global, id);
	if (global >= 0) return self.global.get(global).value;
	return spec(id).fallback;
}

fn SettingLayer Settings.source(&self, SettingId id)
{
	if (self.layer_index(&self.project, id) >= 0) return SettingLayer.PROJECT;
	if (self.layer_index(&self.global, id) >= 0) return SettingLayer.GLOBAL;
	return SettingLayer.DEFAULT;
}

fn long Settings.get_int(&self, SettingId id)
{
	return self.effective(id).i;
}

fn double Settings.get_float(&self, SettingId id)
{
	return self.effective(id).f;
}

fn bool Settings.get_bool(&self, SettingId id)
{
	return self.effective(id).b;
}

fn String Settings.get_string(&self, SettingId id)
{
	return self.effective(id).s;
}

fn void Settings.set_value(&self, SettingId id, SettingValue value, SettingLayer layer)
{
	List{Override}* list = self.layer_list(layer);
	if (list == null) return;

	SettingKind kind    = spec(id).kind;
	SettingValue stored = value;
	if (kind == SettingKind.STRING || kind == SettingKind.ENUM)
	{
		stored.s = value.s.copy(self.allocator);
	}

	sz index = self.layer_index(list, id);
	if (index >= 0)
	{
		free_value(self.allocator, &list.get_ref(index).value);
		list.set(index, { .id = id, .value = stored });
	}
	else
	{
		list.push({ .id = id, .value = stored });
	}
	self.changed[(int)id] = true;
}

fn void Settings.clear(&self, SettingId id, SettingLayer layer)
{
	List{Override}* list = self.layer_list(layer);
	if (list == null) return;
	sz index = self.layer_index(list, id);
	if (index < 0) return;
	free_value(self.allocator, &list.get_ref(index).value);
	list.remove_at(index);
	self.changed[(int)id] = true;
}

fn void Settings.set_int(&self, SettingId id, long value, SettingLayer layer)
{
	self.set_value(id, { .i = value }, layer);
}

fn void Settings.set_float(&self, SettingId id, double value, SettingLayer layer)
{
	self.set_value(id, { .f = value }, layer);
}

fn void Settings.set_bool(&self, SettingId id, bool value, SettingLayer layer)
{
	self.set_value(id, { .b = value }, layer);
}

fn void Settings.set_string(&self, SettingId id, String value, SettingLayer layer)
{
	self.set_value(id, { .s = value }, layer);
}

fn void Settings.push_warning(&self, List{String}* warnings, String message)
{
	warnings.push(message);
}

fn void Settings.apply_key(&self, SettingId id, SettingSpec s, Object* obj, SettingLayer layer, List{String}* warnings)
{
	switch (s.kind)
	{
		case SettingKind.INT:

			{
				int? value = obj.get_int(s.key);
				if (catch excuse = value)
				{
					self.push_warning(
						warnings,
						string::format(self.allocator, "Config \"%s.%s\" must be an integer", s.section, s.key)
					);
				}
				else
				{
					self.set_int(id, clamp_int(s, (long)value), layer);
				}
				break;
			}
		case SettingKind.FLOAT:

			{
				double? value = obj.get_float(s.key);
				if (catch excuse = value)
				{
					self.push_warning(
						warnings,
						string::format(self.allocator, "Config \"%s.%s\" must be a number", s.section, s.key)
					);
				}
				else
				{
					self.set_float(id, clamp_float(s, value), layer);
				}
				break;
			}
		case SettingKind.BOOL:

			{
				bool? value = obj.get_bool(s.key);
				if (catch excuse = value)
				{
					self.push_warning(
						warnings,
						string::format(self.allocator, "Config \"%s.%s\" must be a boolean", s.section, s.key)
					);
				}
				else
				{
					self.set_bool(id, value, layer);
				}
				break;
			}
		case SettingKind.STRING:
		case SettingKind.ENUM:

			{
				String? value = obj.get_string(s.key);
				if (catch excuse = value)
				{
					self.push_warning(
						warnings,
						string::format(self.allocator, "Config \"%s.%s\" must be a string", s.section, s.key)
					);
				}
				else
				{
					self.set_string(id, value, layer);
				}
				break;
			}
	}
}

fn void Settings.apply_section(&self, String name, Object* obj, SettingLayer layer, List{String}* warnings)
{
	if (!obj.is_map())
	{
		self.push_warning(warnings, string::format(self.allocator, "Config \"%s\" must be an object", name));
		return;
	}

	obj.@each_entry(; String key, Object* value)
	{
		bool legacy_arrow = name.compare_to(
			"arrows"
		) == 0 && (key.compare_to(
			"aggregation"
		) == 0 || key.compare_to(
			"show_internal"
		) == 0 || key.compare_to("show_external") == 0 || key.compare_to("external_style") == 0);
		if (!legacy_arrow && !section_has_key(name, key))
		{
			self.push_warning(warnings, string::format(self.allocator, "Unknown config key: %s.%s", name, key));
		}
	};

	for (usz i = 0; i < SETTINGS.len; i++)
	{
		SettingSpec s = SETTINGS[i];
		if (s.section.compare_to(name) != 0) continue;
		if (!obj.has_key(s.key)) continue;
		self.apply_key((SettingId)i, s, obj, layer, warnings);
	}
}

fn bool Settings.section_has_output(&self, String section, SettingLayer scope)
{
	for (usz i = 0; i < SETTINGS.len; i++)
	{
		if (SETTINGS[i].section.compare_to(section) != 0) continue;
		if (scope == SettingLayer.PROJECT)
		{
			if (self.layer_index(&self.project, (SettingId)i) >= 0) return true;
		}
		else
		{
			return true;
		}
	}
	return false;
}

fn void write_value(DString* out, SettingValue value, SettingKind kind)
{
	switch (kind)
	{
		case SettingKind.INT:
			(void)out.appendf("%d", value.i);
		case SettingKind.FLOAT:
			(void)out.appendf("%f", value.f);
		case SettingKind.BOOL:
			out.append_string(value.b ? "true" : "false");
		case SettingKind.STRING:
		case SettingKind.ENUM:
			append_json_string(out, value.s);
	}
}

fn void Settings.write_sections(&self, DString* out, SettingLayer scope)
{
	for (usz i = 0; i < SETTINGS.len; i++)
	{
		String section = SETTINGS[i].section;
		if (!section_is_first(i)) continue;
		if (!self.section_has_output(section, scope)) continue;

		out.append_string("  ");
		append_json_string(out, section);
		out.append_string(": {\n");
		bool first = true;
		for (usz j = 0; j < SETTINGS.len; j++)
		{
			if (SETTINGS[j].section.compare_to(section) != 0) continue;
			if (scope == SettingLayer.PROJECT && self.layer_index(&self.project, (SettingId)j) < 0) continue;
			if (!first) out.append_string(",\n");
			first = false;
			out.append_string("    ");
			append_json_string(out, SETTINGS[j].key);
			out.append_string(": ");
			write_value(out, self.value_in((SettingId)j, scope), SETTINGS[j].kind);
		}
		out.append_string("\n  },\n");
	}
}