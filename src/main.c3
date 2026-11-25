module yun;

import raylib6::rl;
import std::collections::list;
import std::io;
import std::io::file;
import std::io::path;
import std::math;
import std::os::env;
import yun::browser;
import yun::canvas;
import yun::card;
import yun::commands;
import yun::completion;
import yun::connections;
import yun::config;
import yun::console;
import yun::context;
import yun::editor;
import yun::find;
import yun::findbar;
import yun::fonts;
import yun::git;
import yun::hover;
import yun::icons;
import yun::input;
import yun::imports;
import yun::keymap;
import yun::lsp;
import yun::markdown;
import yun::menu;
import yun::minimap;
import yun::notify;
import yun::palette;
import yun::problems;
import yun::project;
import yun::prompt;
import yun::search;
import yun::settings;
import yun::settings_panel;
import yun::symbols;
import yun::theme;
import yun::topbar;
import yun::ui;
import yun::workspace;

enum UiMode : int
{
	MOVE,
	EDIT,
	TOP_BAR,
	CONSOLE,
	SCM,
	DIFF,
	CONFLICT,
	HISTORY,
}

fn void set_project_title(project::Project* project)
{
	String name  = rl::get_file_name((ZString)project.root.ptr).str_view();
	String title = string::format(project.allocator, "Yun - %s", name);
	rl::set_window_title((ZString)title.ptr);
}

fn void notify_console_finishes(console::ConsoleManager* manager, notify::Notifier* notifier, bool console_focused)
{
	int mode = (int)console::settings().notify;
	for (sz i = 0; i < manager.sessions.len(); i++)
	{
		console::ConsoleSession* session = manager.sessions[i];
		int exit_code                    = 0;
		console::ConsoleStatus status;
		if (!session.console.take_notify(&exit_code, &status)) continue;
		if (console_focused) continue;
		if (!console::console_should_notify((console::ConsoleNotify)mode, status, exit_code)) continue;
		@pool()
		{
			String detail;
			if (status == console::ConsoleStatus.FAILED)
			{
				detail = "failed to start";
			}
			else if (status == console::ConsoleStatus.KILLED)
			{
				detail = "stopped";
			}
			else
			{
				detail = string::format(tmem, "exited %d", (long)exit_code);
			}
			notifier.push(string::format(tmem, "Console %s: %s", session.title, detail));
		};
	}
}

fn void set_git_settings(config::Config* config)
{
	git::GitSettings gs = {
		.binary = config.settings.get_string(settings::SettingId.GIT_BINARY),
		.auto_refresh = config.settings.get_bool(settings::SettingId.GIT_AUTO_REFRESH),
		.debounce_ms = (int)config.settings.get_int(settings::SettingId.GIT_DEBOUNCE_MS),
		.confirm_discard = config.settings.get_bool(settings::SettingId.GIT_CONFIRM_DISCARD),
		.default_remote = config.settings.get_string(settings::SettingId.GIT_DEFAULT_REMOTE),
	};
	git::set_settings(gs);
}

fn void set_console_settings(config::Config* config)
{
	String notify               = config.settings.get_string(settings::SettingId.CONSOLE_NOTIFY);
	console::ConsoleNotify mode = console::ConsoleNotify.FAILURE;
	if (notify.compare_to("never") == 0)
	{
		mode = console::ConsoleNotify.NEVER;
	}
	else if (notify.compare_to("always") == 0)
	{
		mode = console::ConsoleNotify.ALWAYS;
	}
	console::ConsoleSettings cs = {
		.max_lines = (int)config.settings.get_int(settings::SettingId.CONSOLE_MAX_LINES),
		.max_output_kb = (int)config.settings.get_int(settings::SettingId.CONSOLE_MAX_OUTPUT_KB),
		.history_size = (int)config.settings.get_int(settings::SettingId.CONSOLE_HISTORY_SIZE),
		.panel_height = (float)config.settings.get_int(settings::SettingId.CONSOLE_PANEL_HEIGHT),
		.auto_scroll = config.settings.get_bool(settings::SettingId.CONSOLE_AUTO_SCROLL),
		.autocomplete = config.settings.get_bool(settings::SettingId.CONSOLE_AUTOCOMPLETE),
		.wheel_lines = (int)config.settings.get_int(settings::SettingId.CONSOLE_WHEEL_LINES),
		.ansi_colors = config.settings.get_bool(settings::SettingId.CONSOLE_ANSI_COLORS),
		.show_headers = config.settings.get_bool(settings::SettingId.CONSOLE_SHOW_HEADERS),
		.clear_on_run = config.settings.get_bool(settings::SettingId.CONSOLE_CLEAR_ON_RUN),
		.kill_on_close = config.settings.get_bool(settings::SettingId.CONSOLE_KILL_ON_CLOSE),
		.notify = mode,
		.persist_history = config.settings.get_bool(settings::SettingId.CONSOLE_PERSIST_HISTORY),
		.restore_sessions = config.settings.get_bool(settings::SettingId.CONSOLE_RESTORE_SESSIONS),
	};
	console::set_settings(cs);
}

fn void finish_open(
	project::Project* project,
	canvas::Canvas* canvas,
	config::Config* config,
	keymap::Keymap* keymap,
	notify::Notifier* notifier,
	console::ConsoleManager* console_manager
)
{
	config.load((String)project.root);
	set_console_settings(config);
	set_git_settings(config);
	ui::set_ui_scale((float)config.settings.get_float(settings::SettingId.APP_UI_SCALE));
	bool restored = workspace::load(project, canvas, console_manager);
	if (restored)
	{
		project.place_unrestored();
		project.invalidate_bounds();
	}
	else
	{
		project.layout();
		for (sz i = 0; i < project.folders.len(); i++)
		{
			project.folders[i].collapsed = true;
		}
		if (config.settings.get_bool(settings::SettingId.CANVAS_FIT_ON_OPEN))
		{
			Rect bounds;
			if (project.content_bounds(&bounds))
			{
				float floor = (float)config.settings.get_float(settings::SettingId.CANVAS_FIT_MIN_ZOOM);
				canvas.fit_zoom_floor(bounds, rl::get_screen_width(), rl::get_screen_height(), floor);
			}
		}
	}
	set_project_title(project);
	keymap.build(config);
	push_config_warnings(config, notifier);
	push_keymap_warnings(keymap, notifier);
}

fn void apply_chrome_insets(canvas::Canvas* canvas, git::Panel* git_panel, bool console_visible, float console_height)
{
	topbar::TopBarPosition bar_position = topbar::position();
	float thickness                     = topbar::thickness_for(bar_position);
	canvas.top_inset = bar_position == topbar::TopBarPosition.TOP ? thickness : 0.0f;
	canvas.bottom_inset = bar_position == topbar::TopBarPosition.BOTTOM ? thickness : 0.0f;
	float bar_left = bar_position == topbar::TopBarPosition.LEFT ? thickness : 0.0f;
	canvas.right_inset = bar_position == topbar::TopBarPosition.RIGHT ? thickness : 0.0f;

	bool git_visible = git_panel != null && git_panel.visible;
	canvas.left_inset = bar_left + (git_visible ? git_panel.width(canvas) : 0.0f);
	if (git_panel != null)
	{
		git_panel.bottom_inset = (console_visible ? ui::pxf(console_height)
			: 0.0f) + (bar_position == topbar::TopBarPosition.BOTTOM ? thickness : 0.0f);
	}
}

fn void apply_settings(
	config::Config* config,
	fonts::Fonts* fonts,
	notify::Notifier* notifier,
	project::Project* project,
	canvas::Canvas* canvas,
	int* font_size,
	RLFont* editor_font,
	editor::EditorMetrics* metrics,
	int* ui_size,
	RLFont* ui_font,
	console::ConsoleManager* console_manager
)
{
	if (config.settings.consume_change(settings::SettingId.APP_THEME))
	{
		if (!theme::set_by_name(config.settings.get_string(settings::SettingId.APP_THEME)))
		{
			notifier.push("Unknown theme in config; using default");
		}
	}

	topbar::set_position(
		topbar::position_from_name(config.settings.get_string(settings::SettingId.APP_TOPBAR_POSITION))
	);
	ui::set_animations(config.settings.get_bool(settings::SettingId.APP_ANIMATIONS));

	bool ui_scale_changed = false;
	if (config.settings.consume_change(settings::SettingId.APP_UI_SCALE))
	{
		float next = (float)config.settings.get_float(settings::SettingId.APP_UI_SCALE);
		if (next < 0.5f) next = 0.5f;
		if (next > 2.0f) next = 2.0f;
		float current = ui::ui_scale();
		if (next != current)
		{
			float ratio = next / current;
			ui::set_ui_scale(next);
			project.scale_geometry(ratio);
			canvas.camera.target = { canvas.camera.target[0] * ratio, canvas.camera.target[1] * ratio };
			ui_scale_changed = true;
		}
	}

	bool ui_changed = false;
	if (config.settings.consume_change(settings::SettingId.APP_UI_FONT_SIZE))
	{
		int next = (int)config.settings.get_int(settings::SettingId.APP_UI_FONT_SIZE);
		if (next < 8) next = 8;
		if (next > 32) next = 32;
		if (next != *ui_size)
		{
			*ui_size = next;
			ui_changed = true;
		}
	}
	if (config.settings.consume_change(settings::SettingId.APP_UI_FONT_FAMILY))
	{
		ui_changed = true;
	}

	ui::set_corner_radius((float)config.settings.get_int(settings::SettingId.APP_CORNER_RADIUS));
	String notice_position = config.settings.get_string(settings::SettingId.APP_NOTIFICATIONS_POSITION);
	int notice_pos         = 3;
	if (notice_position.compare_to("top_left") == 0)
	{
		notice_pos = 0;
	}
	else if (notice_position.compare_to("top_right") == 0)
	{
		notice_pos = 1;
	}
	else if (notice_position.compare_to("bottom_left") == 0)
	{
		notice_pos = 2;
	}
	notifier.configure(
		(float)config.settings.get_float(settings::SettingId.APP_NOTIFICATIONS_TTL),
		(int)config.settings.get_int(settings::SettingId.APP_NOTIFICATIONS_MAX),
		notice_pos
	);
	project.external_reload = config.settings.get_bool(settings::SettingId.APP_EXTERNAL_RELOAD);
	project.poll_seconds = config.settings.get_float(settings::SettingId.APP_RELOAD_POLL);
	project.sleep_editors = config.settings.get_bool(settings::SettingId.APP_SLEEP_EDITORS);
	project.jump_highlight_seconds = (double)config.settings.get_int(
		settings::SettingId.APP_JUMP_HIGHLIGHT_MS
	) / 1000.0;
	config.lsp_enabled = config.settings.get_bool(settings::SettingId.LSP_ENABLED);
	project.autosave_enabled = config.settings.get_bool(settings::SettingId.EDITOR_AUTOSAVE);
	project.autosave_interval = config.settings.get_float(settings::SettingId.EDITOR_AUTOSAVE_INTERVAL);
	search::set_settings(
		{
			.max_file_mb = (int)config.settings.get_int(settings::SettingId.SEARCH_MAX_FILE_MB),
			.max_matches_per_file = (int)config.settings.get_int(settings::SettingId.SEARCH_MAX_MATCHES_PER_FILE),
			.max_results = (int)config.settings.get_int(settings::SettingId.SEARCH_MAX_RESULTS),
			.workers = (int)config.settings.get_int(settings::SettingId.SEARCH_WORKERS),
			.debounce_ms = (int)config.settings.get_int(settings::SettingId.SEARCH_DEBOUNCE_MS),
			.preview_length = (int)config.settings.get_int(settings::SettingId.SEARCH_PREVIEW_MAX),
		}
	);
	String ui_icon_theme = config.settings.get_string(settings::SettingId.APP_UI_ICON_THEME);
	icons::set_ui_theme(
		ui_icon_theme.compare_to("vector") == 0 ? icons::UiIconTheme.VECTOR : icons::UiIconTheme.CODICONS
	);
	String file_icon_theme          = config.settings.get_string(settings::SettingId.APP_FILE_ICON_THEME);
	icons::FileIconTheme file_theme = icons::FileIconTheme.MATERIAL;
	if (file_icon_theme.compare_to("vscode") == 0)
	{
		file_theme = icons::FileIconTheme.VSCODE;
	}
	else if (file_icon_theme.compare_to("none") == 0)
	{
		file_theme = icons::FileIconTheme.NONE;
	}
	icons::set_file_theme(file_theme);
	project.skip_nested_repos = config.settings.get_bool(settings::SettingId.APP_SKIP_SUBMODULES);

	editor::EditorSettings es = editor::settings();
	es.line_height = (float)config.settings.get_float(settings::SettingId.EDITOR_LINE_HEIGHT);
	es.padding_x = (float)config.settings.get_int(settings::SettingId.EDITOR_PADDING_X);
	es.padding_y = (float)config.settings.get_int(settings::SettingId.EDITOR_PADDING_Y);
	es.caret_blink_ms = (int)config.settings.get_int(settings::SettingId.EDITOR_CARET_BLINK_MS);
	es.scroll_margin_lines = (int)config.settings.get_int(settings::SettingId.EDITOR_SCROLL_MARGIN_LINES);
	es.wheel_scroll_lines = (int)config.settings.get_int(settings::SettingId.EDITOR_WHEEL_SCROLL_LINES);
	es.show_line_numbers = config.settings.get_bool(settings::SettingId.EDITOR_SHOW_LINE_NUMBERS);
	es.indent_width = (int)config.settings.get_int(settings::SettingId.EDITOR_INDENT_WIDTH);
	es.indent_spaces = config.settings.get_string(settings::SettingId.EDITOR_INDENT_STYLE).compare_to("spaces") == 0;
	es.auto_indent = config.settings.get_bool(settings::SettingId.EDITOR_AUTO_INDENT);
	es.history_budget = (usz)config.settings.get_int(settings::SettingId.EDITOR_UNDO_MB) * 1024u * 1024u;
	es.diagnostic_segments = (int)config.settings.get_int(settings::SettingId.EDITOR_DIAGNOSTIC_SEGMENTS);

	canvas::CanvasSettings cs = canvas::settings();
	cs.min_zoom = (float)config.settings.get_float(settings::SettingId.CANVAS_ZOOM_MIN);
	cs.max_zoom = (float)config.settings.get_float(settings::SettingId.CANVAS_ZOOM_MAX);
	cs.zoom_step = (float)config.settings.get_float(settings::SettingId.CANVAS_ZOOM_STEP);
	cs.key_pan_step = (float)config.settings.get_float(settings::SettingId.CANVAS_KEY_PAN_STEP);
	cs.pan_responsiveness = (float)config.settings.get_float(settings::SettingId.CANVAS_PAN_SMOOTHING);
	cs.zoom_responsiveness = (float)config.settings.get_float(settings::SettingId.CANVAS_ZOOM_SMOOTHING);
	cs.smoothing = config.settings.get_bool(settings::SettingId.CANVAS_SMOOTHING);
	cs.inertia_friction = (float)config.settings.get_float(settings::SettingId.CANVAS_INERTIA_FRICTION);
	cs.inertia_min_speed = (float)config.settings.get_float(settings::SettingId.CANVAS_INERTIA_MIN_SPEED);
	cs.drag_threshold = (float)config.settings.get_float(settings::SettingId.CANVAS_DRAG_THRESHOLD);
	cs.max_pan_delta = (float)config.settings.get_float(settings::SettingId.CANVAS_MAX_PAN_DELTA);
	cs.grid = config.settings.get_bool(settings::SettingId.CANVAS_GRID);
	cs.grid_cell = (float)config.settings.get_int(settings::SettingId.CANVAS_GRID_CELL);
	cs.grid_min_px = (float)config.settings.get_float(settings::SettingId.CANVAS_GRID_MIN_PX);
	cs.grid_max_px = (float)config.settings.get_float(settings::SettingId.CANVAS_GRID_MAX_PX);
	cs.snap_to_grid = config.settings.get_bool(settings::SettingId.CANVAS_SNAP_TO_GRID);
	cs.snap_step = (float)config.settings.get_int(settings::SettingId.CANVAS_SNAP_STEP);
	cs.jump_zoom_min = (float)config.settings.get_float(settings::SettingId.CANVAS_JUMP_ZOOM_MIN);
	cs.jump_zoom_target = (float)config.settings.get_float(settings::SettingId.CANVAS_JUMP_ZOOM_TARGET);
	canvas::set_settings(cs);

	minimap::MinimapSettings ms = minimap::settings();
	ms.enabled = config.settings.get_bool(settings::SettingId.MINIMAP_ENABLED);
	ms.size = (float)config.settings.get_float(settings::SettingId.MINIMAP_SIZE);
	ms.zoom_threshold = (float)config.settings.get_float(settings::SettingId.MINIMAP_ZOOM_THRESHOLD);
	minimap::set_settings(ms);

	imports::ImportSettings is = imports::settings();
	is.enabled = config.settings.get_bool(settings::SettingId.ARROWS_ENABLED);
	is.show_internal = config.settings.get_bool(settings::SettingId.ARROWS_SHOW_INTERNAL);
	is.show_external = config.settings.get_bool(settings::SettingId.ARROWS_SHOW_EXTERNAL);
	is.labels = config.settings.get_bool(settings::SettingId.ARROWS_LABELS);
	is.line_thickness = (float)config.settings.get_float(settings::SettingId.ARROWS_LINE_THICKNESS);
	is.hover_thickness = (float)config.settings.get_float(settings::SettingId.ARROWS_HOVER_THICKNESS);
	is.arrowhead_size = (float)config.settings.get_float(settings::SettingId.ARROWS_ARROWHEAD_SIZE);
	is.hit_tolerance = (float)config.settings.get_float(settings::SettingId.ARROWS_HIT_TOLERANCE);
	is.rescan_debounce = (float)config.settings.get_float(settings::SettingId.ARROWS_RESCAN_DEBOUNCE);
	is.scan_workers = (int)config.settings.get_int(settings::SettingId.ARROWS_SCAN_WORKERS);
	is.internal_style = imports::parse_arrow_style(
		config.settings.get_string(settings::SettingId.ARROWS_INTERNAL_STYLE)
	);
	is.external_style = imports::parse_arrow_style(
		config.settings.get_string(settings::SettingId.ARROWS_EXTERNAL_STYLE)
	);
	is.dash_length = (float)config.settings.get_float(settings::SettingId.ARROWS_DASH_LENGTH);
	is.dash_gap = (float)config.settings.get_float(settings::SettingId.ARROWS_DASH_GAP);
	imports::set_settings(is);

	set_console_settings(config);
	console_manager.apply_settings(console::settings());
	set_git_settings(config);

	bool font_changed    = false;
	bool metrics_changed = false;

	if (config.settings.consume_change(settings::SettingId.EDITOR_FONT_SIZE))
	{
		int next = editor::clamp_font_size((int)config.settings.get_int(settings::SettingId.EDITOR_FONT_SIZE));
		if (next != *font_size)
		{
			*font_size = next;
			font_changed = true;
		}
	}
	if (config.settings.consume_change(settings::SettingId.EDITOR_FONT_FAMILY))
	{
		font_changed = true;
		String family = config.settings.get_string(settings::SettingId.EDITOR_FONT_FAMILY);
		if (family.len > 0 && family.compare_to("JetBrains Mono") != 0 && fonts.path_for(family).len == 0)
		{
			notifier.push("Unknown font; using bundled font");
		}
	}
	if (config.settings.consume_change(
		settings::SettingId.EDITOR_LINE_HEIGHT
	) || config.settings.consume_change(
		settings::SettingId.EDITOR_PADDING_X
	) || config.settings.consume_change(settings::SettingId.EDITOR_PADDING_Y))
	{
		metrics_changed = true;
	}

	bool reload_editor = font_changed || ui_scale_changed;
	bool reload_ui     = ui_changed || ui_scale_changed;

	if (!reload_ui && !reload_editor && !metrics_changed)
	{
		editor::set_settings(es);
		for (sz i = 0; i < project.cards.len(); i++)
		{
			if (project.cards[i].history) project.cards[i].history.budget = es.history_budget;
		}
		return;
	}

	float old_lh = metrics.line_height;
	float old_cw = metrics.char_width;
	editor::set_settings(es);
	for (sz i = 0; i < project.cards.len(); i++)
	{
		if (project.cards[i].history) project.cards[i].history.budget = es.history_budget;
	}

	if (ui_changed)
	{
		String family = config.settings.get_string(settings::SettingId.APP_UI_FONT_FAMILY);
		if (family.len > 0 && family.compare_to("JetBrains Mono") != 0 && fonts.path_for(family).len == 0)
		{
			notifier.push("Unknown font; using bundled font");
		}
	}
	if (reload_ui)
	{
		rl::unload_font(*ui_font);
		*ui_font = load_editor_font(
			fonts,
			config.settings.get_string(settings::SettingId.APP_UI_FONT_FAMILY),
			ui::atlas_px(*ui_size)
		);
		ui::set_font(*ui_font, *ui_size);
	}

	float draw_size = (float)ui::draw_px(*font_size);
	if (reload_editor)
	{
		String family = config.settings.get_string(settings::SettingId.EDITOR_FONT_FAMILY);
		reload_editor_font(fonts, editor_font, ui::atlas_px(*font_size), draw_size, family, metrics);
	}
	else if (metrics_changed)
	{
		*metrics = editor::metrics_for_font(*editor_font, draw_size);
	}
	project.set_editor_metrics(*metrics);

	if (ui_scale_changed)
	{
		canvas.camera.offset = { canvas.usable_offset_x(), canvas.usable_offset_y() };
	}

	if (reload_editor || metrics_changed)
	{
		float lh_ratio = old_lh > 0.0f ? metrics.line_height / old_lh : 1.0f;
		float cw_ratio = old_cw > 0.0f ? metrics.char_width / old_cw : 1.0f;
		for (sz i = 0; i < project.cards.len(); i++)
		{
			project.cards[i].scroll *= lh_ratio;
			project.cards[i].scroll_x *= cw_ratio;
		}
		project.reveal_focused(*metrics);
	}
}

fn String open_phase_label(project::OpenPhase phase)
{
	switch (phase)
	{
		case project::OpenPhase.SCAN:
			return "Scanning folders";
		case project::OpenPhase.SORT:
			return "Sorting entries";
		case project::OpenPhase.BUILD_FOLDERS:
			return "Building folders";
		case project::OpenPhase.BUILD_CARDS:
			return "Building files";
		case project::OpenPhase.LAYOUT:
			return "Laying out";
		case project::OpenPhase.DONE:
			return "Done";
		case project::OpenPhase.FAILED:
			return "Failed";
	}
}

fn void draw_loading(project::OpenJob* job, RLFont font)
{
	int width  = rl::get_screen_width();
	int height = rl::get_screen_height();
	rl::draw_rectangle(0, 0, width, height, theme::current().loading_scrim);

	Rect panel = {
		.x = (float)width / 2.0f - 180.0f,
		.y = (float)height / 2.0f - 50.0f,
		.width = 360.0f,
		.height = 100.0f,
	};
	ui::panel(panel, theme::current().loading_panel, theme::current().loading_border);

	@pool()
	{
		String name  = rl::get_file_name((ZString)job.root.ptr).str_view();
		String title = string::format(tmem, "Opening %s", name);
		String status = string::format(
			tmem,
			"%s - %d folders, %d entries",
			open_phase_label(job.phase),
			(long)job.scanned_dirs,
			(long)job.entries.len()
		);
		rl::draw_text_ex(
			font,
			title.zstr_tcopy(),
			{ panel.x + (float)ui::px(20), panel.y + (float)ui::px(20) },
			(float)ui::tpx(18),
			0.0f,
			theme::current()
			.loading_title);
		rl::draw_text_ex(
			font,
			status.zstr_tcopy(),
			{ panel.x + (float)ui::px(20), panel.y + (float)ui::px(48) },
			(float)ui::tpx(14),
			0.0f,
			theme::current()
			.loading_status);
		if (job.phase == project::OpenPhase.SCAN)
		{
			rl::draw_text_ex(
				font,
				"Esc to cancel",
				{ panel.x + (float)ui::px(20), panel.y + (float)ui::px(70) },
				(float)ui::tpx(14),
				0.0f,
				theme::current()
				.loading_hint);
		}
	};
}

fn void push_config_warnings(config::Config* config, notify::Notifier* notifier)
{
	for (sz i = 0; i < config.warnings.len(); i++)
	{
		notifier.push(config.warnings[i]);
	}
}

fn void push_keymap_warnings(keymap::Keymap* keymap, notify::Notifier* notifier)
{
	for (sz i = 0; i < keymap.warnings.len(); i++)
	{
		notifier.push(keymap.warnings[i]);
	}
}

struct App
{
	project::Project* project;
	canvas::Canvas* canvas;
	config::Config* config;
	browser::Browser* browser;
	notify::Notifier* notifier;
	prompt::Prompt* name_prompt;
	palette::Palette* palette;
	settings_panel::Panel* settings_panel;
	findbar::FindBar* find_bar;
	problems::Problems* problems;
	connections::Connections* connections;
	menu::Menu* theme_menu;
	menu::Menu* profile_menu;
	menu::Menu* context_menu;
	menu::Menu* close_menu;
	menu::Menu* delete_menu;
	menu::Menu* reload_menu;
	menu::Menu* definition_menu;
	search::Search* search;
	symbols::Symbols* symbols;
	console::ConsoleManager* console_manager;
	console::Console* console;
	console::ConsolePanel* console_panel;
	git::State* git;
	git::Panel* git_panel;
	git::DiffView* diff_view;
	git::ConflictView* conflict_view;
	git::HistoryView* history_view;
	editor::EditorMetrics metrics;
	bool* project_open;
	bool* content_changed;
	bool* quit_requested;
	UiMode* ui_mode;
	UiMode* focus_saved_mode;
	UiMode* console_saved_mode;
	UiMode* scm_saved_mode;
	UiMode* diff_saved_mode;
	UiMode* conflict_saved_mode;
	UiMode* history_saved_mode;
	int* edit_grace_frames;
	topbar::TopBar* bar;
	keymap::Keymap* keymap;
	context::ContextItem[context::CONTEXT_MAX_ITEMS] context_items;
	usz context_item_count;
	int context_card;
	int context_parent;
	RLVector2 context_world;
	int context_offset;
	int pending_rename_card;
	int pending_delete_card;
	usz* pending_rename_offset;
	int* pending_kind;
	int* pending_parent;
	RLVector2* pending_world;
}

fn bool has_focused_buffer(project::Project* project)
{
	int index = project.focused;
	return index >= 0 && index < (int)project.cards.len() && project.cards[index].buffer != null;
}

fn void enter_edit_mode(
	project::Project* project,
	canvas::Canvas* canvas,
	editor::EditorMetrics metrics,
	UiMode* ui_mode,
	int* edit_grace_frames
)
{
	if (project.selected_cluster >= 0)
	{
		int folder = project.selected_cluster;
		project.enter_folder(folder);
		Rect r = project.cluster_visual_bounds(folder);
		if (r.width > 0.0f) canvas.target.target = { r.x + r.width / 2.0f, r.y + r.height / 2.0f };
		return;
	}

	bool enter = false;
	if (project.selected >= 0)
	{
		int idx = project.focus(project.selected);
		if (idx >= 0 && idx < (int)project.cards.len())
		{
			project.selected = idx;
			editor::ensure_buffer(&project.cards[idx], project.allocator);
			project.reveal_focused(metrics);
			enter = true;
		}
	}
	else if (project.focused >= 0)
	{
		project.selected = project.focused;
		enter = true;
	}
	if (enter && project.focused >= 0)
	{
		*ui_mode = UiMode.EDIT;
		*edit_grace_frames = 2;
		FileCard* card = project.focused_card();
		if (card) canvas.target.target = card.center();
	}
}

fn void close_overlays(App* app)
{
	app.palette.close();
	app.settings_panel.close();
	app.problems.close();
	app.name_prompt.close();
	app.theme_menu.close();
	app.profile_menu.close();
	app.context_menu.close();
	app.close_menu.close();
	app.delete_menu.close();
	app.reload_menu.close();
	app.definition_menu.close();
	app.search.close();
	app.symbols.close();
	app.find_bar.close();
}

fn void poll_global(keymap::Keymap* keymap, App* app)
{
	int cmd = keymap.poll(commands::CTX_GLOBAL);
	if (cmd >= 0) run_command((commands::CommandId)cmd, app);
}

const String[] VISUAL_STATE_NAMES = {
	"canvas",
	"settings",
	"connections",
	"source-control",
	"console",
	"problems",
	"search",
	"symbols",
	"palette",
	"browser",
	"topbar-bottom",
	"topbar-left",
	"topbar-right",
	"notifications",
};

const int VISUAL_STATE_COUNT = (int)VISUAL_STATE_NAMES.len;

struct VisualSuite
{
	bool active;
	String dir;
	int state;
	int frame;
}

VisualSuite g_visual;

fn String visual_shot_path(Allocator allocator, String dir, String name)
{
	if (dir.len > 0 && (dir[^1] == '/' || dir[^1] == '\\')) return string::format(allocator, "%s%s.png", dir, name);
	return string::format(allocator, "%s/%s.png", dir, name);
}

fn void visual_suite_close(App* app)
{
	close_overlays(app);
	app.connections.close();
	app.git_panel.close();
	app.console_manager.close();
	app.browser.open = false;
	*app.ui_mode = UiMode.MOVE;
}

fn void visual_suite_setup(App* app, project::Project* project, int state)
{
	visual_suite_close(app);
	app.config.settings.set_string(settings::SettingId.APP_TOPBAR_POSITION, "top", settings::SettingLayer.GLOBAL);
	topbar::set_position(topbar::TopBarPosition.TOP);
	switch (state)
	{
		case 0:
			if (project.cards.len() > 0)
			{
				int index = project.focus(0);
				project.selected = index;
				editor::ensure_buffer(&project.cards[index], project.allocator);
			}
		case 1:
			app.settings_panel.show();
		case 2:
			app.connections.show();
		case 3:
			app.git_panel.open();
		case 4:
			app.console_manager.open();
			focus_console(app);
		case 5:
			app.problems.show();
		case 6:
			app.search.show();
		case 7:
			app.symbols.show(project);
		case 8:
			app.palette.show();
		case 9:
			app.browser.open_at((String)project.root);
		case 10:
			app.config.settings.set_string(
				settings::SettingId.APP_TOPBAR_POSITION,
				"bottom",
				settings::SettingLayer.GLOBAL
			);
			topbar::set_position(topbar::TopBarPosition.BOTTOM);
		case 11:
			app.config.settings.set_string(
				settings::SettingId.APP_TOPBAR_POSITION,
				"left",
				settings::SettingLayer.GLOBAL
			);
			topbar::set_position(topbar::TopBarPosition.LEFT);
		case 12:
			app.config.settings.set_string(
				settings::SettingId.APP_TOPBAR_POSITION,
				"right",
				settings::SettingLayer.GLOBAL
			);
			topbar::set_position(topbar::TopBarPosition.RIGHT);
		case 13:
			app.notifier.push("Visual regression check");
	}
}

fn void visual_suite_begin(App* app, project::Project* project, String dir)
{
	if (g_visual.active) return;
	g_visual.active = true;
	g_visual.dir = dir.copy(mem);
	g_visual.state = 0;
	g_visual.frame = 0;
	@pool()
	{
		if (catch excuse = path::mkdir((Path)dir, recursive: true)) return;
		if (catch excuse = path::mkdir((Path)".yun/visual-tmp", recursive: true)) return;
		io::printfn("visual suite: writing to %s", dir.zstr_tcopy());
	};
	visual_suite_setup(app, project, 0);
}

fn void visual_suite_tick(App* app, project::Project* project)
{
	if (!g_visual.active) return;
	g_visual.frame++;
	int duration = 30;
	if (g_visual.state == 7 && app.symbols.scanning) duration = 240;
	if (g_visual.frame < duration) return;
	@pool()
	{
		String name     = VISUAL_STATE_NAMES[g_visual.state];
		String target   = visual_shot_path(tmem, g_visual.dir, name);
		String temp_rel = string::format(tmem, ".yun/visual-tmp/%s.png", name);
		String cwd      = rl::get_working_directory().str_view();
		String temp_abs = string::format(tmem, "%s/%s", cwd, temp_rel);
		io::printfn("visual suite: %s", target.zstr_tcopy());
		rl::gl_draw_render_batch_active();
		rl::take_screenshot(temp_rel.zstr_tcopy());
		char[]? shot = file::load(tmem, temp_abs);
		if (catch excuse = shot)
		{
			return;
		}
		(void)file::save((Path)target, shot);
		(void)file::delete(temp_abs);
	};
	g_visual.state++;
	g_visual.frame = 0;
	if (g_visual.state >= VISUAL_STATE_COUNT)
	{
		g_visual.active = false;
		if (g_visual.dir.len) g_visual.dir.free(mem);
		g_visual.dir = "";
		*app.quit_requested = true;
		return;
	}
	visual_suite_setup(app, project, g_visual.state);
}

fn bool is_select_command(int cmd)
{
	return cmd == (int)commands::CommandId.SELECT_LEFT || cmd == (int)commands::CommandId.SELECT_RIGHT
		|| cmd == (int)commands::CommandId.SELECT_UP
		|| cmd == (int)commands::CommandId.SELECT_DOWN;
}

fn int held_move_dir(keymap::Keymap* keymap)
{
	if (keymap.held(
		(int)commands::CommandId.SELECT_LEFT,
		commands::CTX_MOVE
	) || rl::is_key_down(rl::RLKeyboardKey.LEFT)) return (int)commands::CommandId.SELECT_LEFT;
	if (keymap.held(
		(int)commands::CommandId.SELECT_RIGHT,
		commands::CTX_MOVE
	) || rl::is_key_down(rl::RLKeyboardKey.RIGHT)) return (int)commands::CommandId.SELECT_RIGHT;
	if (keymap.held(
		(int)commands::CommandId.SELECT_UP,
		commands::CTX_MOVE
	) || rl::is_key_down(rl::RLKeyboardKey.UP)) return (int)commands::CommandId.SELECT_UP;
	if (keymap.held(
		(int)commands::CommandId.SELECT_DOWN,
		commands::CTX_MOVE
	) || rl::is_key_down(rl::RLKeyboardKey.DOWN)) return (int)commands::CommandId.SELECT_DOWN;
	return 0;
}

fn int target_card_index(project::Project* project)
{
	if (project.selected >= 0 && project.selected < (int)project.cards.len()) return project.selected;
	if (project.focused >= 0 && project.focused < (int)project.cards.len()) return project.focused;
	return -1;
}

fn int focus_mode_target(project::Project* project, UiMode mode)
{
	int index = mode == UiMode.EDIT ? project.focused : project.selected;
	if (index < 0 || index >= (int)project.cards.len())
	{
		index = mode == UiMode.EDIT ? project.selected : project.focused;
	}
	if (index < 0 || index >= (int)project.cards.len()) return -1;
	return index;
}

fn void focus_console(App* app)
{
	if (!app.console_manager.visible) app.console_manager.open();
	if (*app.ui_mode != UiMode.CONSOLE)
	{
		*app.console_saved_mode = *app.ui_mode;
		*app.ui_mode = UiMode.CONSOLE;
	}
	app.console_panel.focused = true;
	app.console_panel.focus_requested = false;
}

fn void leave_console(App* app)
{
	if (*app.ui_mode != UiMode.CONSOLE) return;
	*app.ui_mode = *app.console_saved_mode;
	app.console_panel.focused = false;
}

fn void run_profile(App* app, config::RunProfile* profile)
{
	if (!*app.project_open)
	{
		app.notifier.push("No project open");
		return;
	}
	sync_app_console(app);
	Console* console = app.console;
	if (!console) return;
	if (console.runner.running())
	{
		app.notifier.push("A command is already running");
		return;
	}
	focus_console(app);
	@pool()
	{
		List{console::ConsoleEnvVar} env;
		env.init(tmem);
		for (sz i = 0; i < profile.env.len(); i++)
		{
			env.push({ .key = profile.env[i].key, .value = profile.env[i].value });
		}
		String wrapped = console::console_profile_command(tmem, profile.cwd, env.entries[0:env.len()], profile.command);
		String display = string::format(tmem, "%s: %s", profile.name, profile.command);
		(void)console.run_display(display, wrapped);
	};
	app.console_panel.pinned = app.console_panel.auto_scroll;
}

fn void sync_app_console(App* app)
{
	app.console = app.console_manager.active_console();
	app.console_panel = app.console_manager.active_panel();
}

fn void open_context_menu(App* app, context::ContextTarget target, int card, int folder, RLVector2 world, int offset)
{
	project::Project* project = app.project;
	app.context_card = card;
	app.context_parent = folder;
	app.context_world = world;
	app.context_offset = offset;

	bool card_open    = card >= 0 && project.cards[card].open;
	bool card_missing = card >= 0 && project.cards[card].missing;
	app.context_item_count = context::build(
		target,
		card_open,
		card_missing,
		*app.project_open,
		offset >= 0,
		app.context_items[0:context::CONTEXT_MAX_ITEMS]
	);

	@pool()
	{
		String[context::CONTEXT_MAX_ITEMS] labels;
		bool[context::CONTEXT_MAX_ITEMS] enabled;
		for (usz i = 0; i < app.context_item_count; i++)
		{
			context::ContextItem item = app.context_items[i];
			int cmd                   = context::command_for(item.action);
			String hint               = cmd >= 0 ? app.keymap.shortcut((commands::CommandId)cmd) : "";
			labels[i] = hint.len > 0 ? string::format(tmem, "%s   %s", item.label, hint) : item.label;
			enabled[i] = item.enabled;
		}
		RLVector2 screen = rl::get_world_to_screen2d(world, app.canvas.camera);
		app.context_menu.open_with(screen, labels[0:app.context_item_count], enabled[0:app.context_item_count]);
	};
}

fn void run_command(commands::CommandId id, App* app)
{
	project::Project* project = app.project;
	switch (id)
	{
		case commands::CommandId.NEW_FILE:

			{
				if (!*app.project_open)
				{
					app.notifier.push("No project open");
					return;
				}
				RLVector2 center = {
					(float)rl::get_screen_width() / 2.0f,
					(float)rl::get_screen_height() / 2.0f,
				};
				RLVector2 world = app.canvas.screen_to_world(center);
				*app.pending_kind = 0;
				*app.pending_parent = project.folder_at(world);
				*app.pending_world = world;
				app.name_prompt.open_with("New file", "");
				return;
			}
		case commands::CommandId.NEW_FOLDER:

			{
				if (!*app.project_open)
				{
					app.notifier.push("No project open");
					return;
				}
				RLVector2 center = {
					(float)rl::get_screen_width() / 2.0f,
					(float)rl::get_screen_height() / 2.0f,
				};
				RLVector2 world = app.canvas.screen_to_world(center);
				*app.pending_kind = 1;
				*app.pending_parent = project.folder_at(world);
				*app.pending_world = world;
				app.name_prompt.open_with("New folder", "");
				return;
			}
		case commands::CommandId.OPEN:

			{
				close_overlays(app);
				app.browser.open_at((String)project.root);
				return;
			}
		case commands::CommandId.SAVE:

			{
				if (!*app.project_open)
				{
					app.notifier.push("No project open");
					return;
				}
				int index = project.focused;
				if (index < 0 || index >= (int)project.cards.len() || !project.cards[index].buffer)
				{
					app.notifier.push("No file to save");
					return;
				}
				if (editor::save_buffer(&project.cards[index], project.allocator))
				{
					app.git.mark_dirty(rl::get_time());
					app.notifier.push("Saved");
				}
				else
				{
					app.notifier.push("Could not save");
				}
				return;
			}
		case commands::CommandId.SHOW_PALETTE:

			{
				close_overlays(app);
				app.palette.show();
				while (rl::get_char_pressed() != 0)
				{
				}
				return;
			}
		case commands::CommandId.FIND:
		case commands::CommandId.REPLACE:

			{
				int index = project.focused;
				if (!*app.project_open || index < 0 || index >= (int)project.cards.len()
					|| !project.cards[index].buffer)
				{
					app.notifier.push("No file to search");
					return;
				}
				find::FindField field = id == commands::CommandId.REPLACE ? find::FindField.REPLACE
					: find::FindField.QUERY;
				close_overlays(app);
				app.find_bar.open_for(field);
				while (rl::get_char_pressed() != 0)
				{
				}
				return;
			}
		case commands::CommandId.COPY:

			{
				if (project.copy_selection())
				{
					app.notifier.push("Copied");
				}
				return;
			}
		case commands::CommandId.CUT:

			{
				if (project.cut_selection(rl::get_time()))
				{
					mark_buffer_changed(project, app.find_bar, app.metrics);
				}
				return;
			}
		case commands::CommandId.PASTE:

			{
				if (project.paste_clipboard(rl::get_time()))
				{
					mark_buffer_changed(project, app.find_bar, app.metrics);
				}
				return;
			}
		case commands::CommandId.SELECT_ALL:

			{
				project.select_all();
				project.reveal_focused(app.metrics);
				return;
			}
		case commands::CommandId.PROBLEMS:

			{
				close_overlays(app);
				app.problems.show();
				return;
			}
		case commands::CommandId.GO_TO_DEFINITION:

			{
				FileCard* card = project.focused_card();
				if (!card || !card.buffer)
				{
					app.notifier.push("No file to navigate");
					return;
				}
				if (!lsp::lsp_request_definition((String)card.path, card.buffer, card.cursor))
				{
					app.notifier.push("No definition provider");
				}
				return;
			}
		case commands::CommandId.COMPLETE:

			{
				FileCard* card = project.focused_card();
				if (!card || !card.buffer) return;
				completion::completion_request((String)card.path, card.buffer, card.cursor, 1, "");
				return;
			}
		case commands::CommandId.FORMAT_DOCUMENT:

			{
				FileCard* card = project.focused_card();
				if (!card || !card.buffer)
				{
					app.notifier.push("No file to format");
					return;
				}
				if (!lsp::lsp_request_formatting((String)card.path))
				{
					app.notifier.push("No formatter");
				}
				return;
			}
		case commands::CommandId.REFERENCES:

			{
				FileCard* card = project.focused_card();
				if (!card || !card.buffer)
				{
					app.notifier.push("No file to search");
					return;
				}
				if (!lsp::lsp_request_references((String)card.path, card.buffer, card.cursor))
				{
					app.notifier.push("No references provider");
				}
				return;
			}
		case commands::CommandId.RENAME_SYMBOL:

			{
				FileCard* card = project.focused_card();
				if (!card || !card.buffer)
				{
					app.notifier.push("No file to rename");
					return;
				}
				*app.pending_rename_offset = card.cursor;
				if (!lsp::lsp_request_prepare_rename((String)card.path, card.buffer, card.cursor))
				{
					app.notifier.push("No rename provider");
				}
				return;
			}
		case commands::CommandId.CODE_ACTIONS:

			{
				FileCard* card = project.focused_card();
				if (!card || !card.buffer)
				{
					app.notifier.push("No file for code actions");
					return;
				}
				if (!lsp::lsp_request_code_actions((String)card.path, card.buffer, card.cursor))
				{
					app.notifier.push("No code action provider");
				}
				return;
			}
		case commands::CommandId.SELECT_THEME:

			{
				RLVector2 center = {
					(float)rl::get_screen_width() / 2.0f,
					(float)rl::get_screen_height() / 2.0f,
				};
				close_overlays(app);
				@pool()
				{
					String[32] labels;
					int n = theme::count();
					if (n > 32) n = 32;
					for (int i = 0; i < n; i++) labels[i] = theme::label(i);
					app.theme_menu.open_at(center, labels[0:n]);
				};
				return;
			}
		case commands::CommandId.SEARCH_PROJECT:

			{
				if (!*app.project_open)
				{
					app.notifier.push("No project open");
					return;
				}
				close_overlays(app);
				app.search.show();
				while (rl::get_char_pressed() != 0)
				{
				}
				return;
			}
		case commands::CommandId.SYMBOLS_PROJECT:

			{
				if (!*app.project_open)
				{
					app.notifier.push("No project open");
					return;
				}
				close_overlays(app);
				(void)lsp::lsp_request_workspace_symbols("");
				app.symbols.show(project);
				while (rl::get_char_pressed() != 0)
				{
				}
				return;
			}
		case commands::CommandId.TOGGLE_SETTINGS:

			{
				bool was_open = app.settings_panel.open;
				close_overlays(app);
				if (!was_open) app.settings_panel.show();
				while (rl::get_char_pressed() != 0)
				{
				}
				return;
			}
		case commands::CommandId.UNDO:

			{
				if (project.editor_undo())
				{
					project.finish_edit(app.metrics);
					*app.content_changed = true;
				}
				return;
			}
		case commands::CommandId.REDO:

			{
				if (project.editor_redo())
				{
					project.finish_edit(app.metrics);
					*app.content_changed = true;
				}
				return;
			}
		case commands::CommandId.NEWLINE:

			{
				if (project.editor_newline())
				{
					project.finish_edit(app.metrics);
					*app.content_changed = true;
				}
				return;
			}
		case commands::CommandId.INDENT:

			{
				if (project.editor_indent())
				{
					project.finish_edit(app.metrics);
					*app.content_changed = true;
				}
				return;
			}
		case commands::CommandId.OUTDENT:

			{
				if (project.editor_outdent())
				{
					project.finish_edit(app.metrics);
					*app.content_changed = true;
				}
				return;
			}
		case commands::CommandId.DELETE_BACK:

			{
				if (project.editor_delete(true))
				{
					project.finish_edit(app.metrics);
					*app.content_changed = true;
				}
				return;
			}
		case commands::CommandId.DELETE_FORWARD:

			{
				if (project.editor_delete(false))
				{
					project.finish_edit(app.metrics);
					*app.content_changed = true;
				}
				return;
			}
		case commands::CommandId.CURSOR_LEFT:
			project.editor_move(project::EditorMove.LEFT, app.metrics);
			return;
		case commands::CommandId.CURSOR_RIGHT:
			project.editor_move(project::EditorMove.RIGHT, app.metrics);
			return;
		case commands::CommandId.CURSOR_UP:
			project.editor_move(project::EditorMove.UP, app.metrics);
			return;
		case commands::CommandId.CURSOR_DOWN:
			project.editor_move(project::EditorMove.DOWN, app.metrics);
			return;
		case commands::CommandId.LINE_START:
			project.editor_move(project::EditorMove.LINE_START, app.metrics);
			return;
		case commands::CommandId.LINE_END:
			project.editor_move(project::EditorMove.LINE_END, app.metrics);
			return;
		case commands::CommandId.PAGE_UP:
			project.editor_move(project::EditorMove.PAGE_UP, app.metrics);
			return;
		case commands::CommandId.PAGE_DOWN:
			project.editor_move(project::EditorMove.PAGE_DOWN, app.metrics);
			return;
		case commands::CommandId.EXIT_EDITOR:
			project.editor_exit();
			return;
		case commands::CommandId.PAN_LEFT:
			app.canvas.key_pan({ -canvas::settings().key_pan_step, 0.0f });
			return;
		case commands::CommandId.PAN_RIGHT:
			app.canvas.key_pan({ canvas::settings().key_pan_step, 0.0f });
			return;
		case commands::CommandId.PAN_UP:
			app.canvas.key_pan({ 0.0f, -canvas::settings().key_pan_step });
			return;
		case commands::CommandId.PAN_DOWN:
			app.canvas.key_pan({ 0.0f, canvas::settings().key_pan_step });
			return;
		case commands::CommandId.SELECT_LEFT:
		case commands::CommandId.SELECT_RIGHT:
		case commands::CommandId.SELECT_UP:
		case commands::CommandId.SELECT_DOWN:

			{
				project.ensure_selection();
				project::Dir dir = project::Dir.LEFT;
				if (id == commands::CommandId.SELECT_RIGHT) dir = project::Dir.RIGHT;
				if (id == commands::CommandId.SELECT_UP) dir = project::Dir.UP;
				if (id == commands::CommandId.SELECT_DOWN) dir = project::Dir.DOWN;
				project::NavItem item;
				if (project.item_in_direction(dir, &item)) project.select_nav_item(item);
				return;
			}
		case commands::CommandId.CYCLE_NEXT:

			{
				project::NavItem item;
				if (project.cycle_nav_item(1, &item)) project.select_nav_item(item);
				return;
			}
		case commands::CommandId.CYCLE_PREV:

			{
				project::NavItem item;
				if (project.cycle_nav_item(-1, &item)) project.select_nav_item(item);
				return;
			}
		case commands::CommandId.ZOOM_IN:
			app.canvas.key_zoom(1.0f);
			return;
		case commands::CommandId.ZOOM_OUT:
			app.canvas.key_zoom(-1.0f);
			return;
		case commands::CommandId.FOCUS_TOP_BAR:
			*app.ui_mode = UiMode.TOP_BAR;
			app.bar.clamp_selection(*app.project_open, has_focused_buffer(project));
			return;
		case commands::CommandId.FOCUS_EDITOR:
			enter_edit_mode(project, app.canvas, app.metrics, app.ui_mode, app.edit_grace_frames);
			return;
		case commands::CommandId.TOPBAR_LEFT:
		case commands::CommandId.TOPBAR_UP:
			app.bar.move_selection(-1, *app.project_open, has_focused_buffer(project));
			return;
		case commands::CommandId.TOPBAR_RIGHT:
		case commands::CommandId.TOPBAR_DOWN:
			app.bar.move_selection(1, *app.project_open, has_focused_buffer(project));
			return;
		case commands::CommandId.TOPBAR_ACTIVATE:

			{
				int cmd_id = app.bar.activate(*app.project_open, has_focused_buffer(project));
				if (cmd_id >= 0) run_command((commands::CommandId)cmd_id, app);
				return;
			}
		case commands::CommandId.FOCUS_CANVAS:
			*app.ui_mode = UiMode.MOVE;
			return;
		case commands::CommandId.LEAVE_FOLDER:

			{
				if (project.leave_folder())
				{
					Rect r = project.selected_item_rect();
					if (r.width > 0.0f)
					{
						app.canvas.target.target = { r.x + r.width / 2.0f, r.y + r.height / 2.0f };
					}
				}
				return;
			}
		case commands::CommandId.CYCLE_FOCUS:

			{
				if (*app.ui_mode == UiMode.TOP_BAR)
				{
					*app.ui_mode = UiMode.MOVE;
				}
				else if (project.grabbing)
				{
					project.snap_selected_to_grid(app.canvas.camera.zoom);
					project.grabbing = false;
					*app.ui_mode = UiMode.TOP_BAR;
					app.bar.clamp_selection(*app.project_open, has_focused_buffer(project));
				}
				else if (project.has_selected_item())
				{
					project.begin_grab();
					project.grabbing = true;
				}
				else
				{
					*app.ui_mode = UiMode.TOP_BAR;
					app.bar.clamp_selection(*app.project_open, has_focused_buffer(project));
				}
				return;
			}
		case commands::CommandId.MINIMIZE_CARD:
			project.minimize_selected(app.metrics);
			return;
		case commands::CommandId.TOGGLE_FOCUS_MODE:

			{
				if (project.focus_card >= 0)
				{
					project.end_focus(app.canvas);
					*app.ui_mode = *app.focus_saved_mode;
					return;
				}
				int index = focus_mode_target(project, *app.ui_mode);
				if (index < 0)
				{
					app.notifier.push("No file to focus");
					return;
				}
				if (!project.begin_focus(index, app.canvas))
				{
					app.notifier.push("Could not focus file");
					return;
				}
				*app.focus_saved_mode = *app.ui_mode;
				*app.ui_mode = UiMode.EDIT;
				*app.edit_grace_frames = 2;
				return;
			}
		case commands::CommandId.TOGGLE_CONSOLE:

			{
				if (app.console_manager.visible && *app.ui_mode == UiMode.CONSOLE)
				{
					app.console_manager.close();
					*app.ui_mode = *app.console_saved_mode;
				}
				else
				{
					focus_console(app);
				}
				return;
			}
		case commands::CommandId.TOGGLE_SCM:

			{
				if (app.git_panel.visible && *app.ui_mode == UiMode.SCM)
				{
					app.git_panel.close();
					*app.ui_mode = *app.scm_saved_mode;
				}
				else
				{
					if (*app.ui_mode != UiMode.SCM) *app.scm_saved_mode = *app.ui_mode;
					app.git_panel.open();
					*app.ui_mode = UiMode.SCM;
				}
				return;
			}
		case commands::CommandId.CONSOLE_RUN:

			{
				focus_console(app);
				(void)app.console.submit();
				app.console_panel.pinned = app.console_panel.auto_scroll;
				return;
			}
		case commands::CommandId.CONSOLE_HISTORY_PREV:

			{
				focus_console(app);
				(void)app.console.history.previous(&app.console.input);
				app.console_panel.input_scroll = 0.0f;
				return;
			}
		case commands::CommandId.CONSOLE_HISTORY_NEXT:

			{
				focus_console(app);
				(void)app.console.history.next(&app.console.input);
				app.console_panel.input_scroll = 0.0f;
				return;
			}
		case commands::CommandId.CONSOLE_CLEAR:

			{
				focus_console(app);
				app.console.clear();
				app.console_panel.scroll = 0;
				app.console_panel.output_scroll_x = 0.0f;
				app.console_panel.pinned = app.console_panel.auto_scroll;
				app.console_panel.clear_selection();
				app.console_panel.find_dirty = true;
				return;
			}
		case commands::CommandId.CONSOLE_KILL:

			{
				focus_console(app);
				app.console.kill();
				return;
			}
		case commands::CommandId.CONSOLE_COPY:

			{
				app.console_panel.copy_selection_or_all(app.console);
				return;
			}
		case commands::CommandId.CONSOLE_FIND:

			{
				focus_console(app);
				app.console_panel.find_open_panel();
				app.console_panel.find_refresh(app.console);
				return;
			}
		case commands::CommandId.CONSOLE_PASTE:

			{
				focus_console(app);
				app.console_panel.paste(app.console);
				return;
			}
		case commands::CommandId.CONSOLE_SCROLL_UP:

			{
				focus_console(app);
				app.console_panel.scroll_by(app.console, app.metrics, -app.console_panel.visible_rows(app.metrics));
				return;
			}
		case commands::CommandId.CONSOLE_SCROLL_DOWN:

			{
				focus_console(app);
				app.console_panel.scroll_by(app.console, app.metrics, app.console_panel.visible_rows(app.metrics));
				return;
			}
		case commands::CommandId.CONSOLE_LEAVE_FOCUS:

			{
				leave_console(app);
				return;
			}
		case commands::CommandId.CONSOLE_NEW_SESSION:

			{
				(void)app.console_manager.add_session();
				sync_app_console(app);
				focus_console(app);
				return;
			}
		case commands::CommandId.CONSOLE_CLOSE_SESSION:

			{
				(void)app.console_manager.close_session(app.console_manager.active);
				sync_app_console(app);
				if (!app.console_manager.visible)
				{
					*app.ui_mode = *app.console_saved_mode;
				}
				else
				{
					app.console_panel.focused = true;
				}
				return;
			}
		case commands::CommandId.CONSOLE_NEXT_SESSION:

			{
				int count = (int)app.console_manager.sessions.len();
				if (count > 1)
				{
					app.console_manager.select((app.console_manager.active + 1) % count);
				}
				sync_app_console(app);
				focus_console(app);
				return;
			}
		case commands::CommandId.CONSOLE_PREV_SESSION:

			{
				int count = (int)app.console_manager.sessions.len();
				if (count > 1)
				{
					int next = app.console_manager.active - 1;
					if (next < 0) next = count - 1;
					app.console_manager.select(next);
				}
				sync_app_console(app);
				focus_console(app);
				return;
			}
		case commands::CommandId.CONSOLE_RUN_PROFILE:

			{
				if (!*app.project_open)
				{
					app.notifier.push("No project open");
					return;
				}
				if (app.config.run_profiles.len() == 0)
				{
					app.notifier.push("No run profiles");
					return;
				}
				if (app.config.run_profiles.len() == 1)
				{
					run_profile(app, &app.config.run_profiles[0]);
					return;
				}
				@pool()
				{
					List{String} labels;
					labels.init(tmem);
					for (sz i = 0; i < app.config.run_profiles.len(); i++)
					{
						labels.push(app.config.run_profiles[i].name);
					}
					RLVector2 center = {
						(float)rl::get_screen_width() / 2.0f - 100.0f,
						(float)rl::get_screen_height() / 2.0f,
					};
					app.profile_menu.open_at(center, labels.entries[0:labels.len()]);
				};
				return;
			}
		case commands::CommandId.TOGGLE_CONNECTIONS:

			{
				if (!*app.project_open)
				{
					app.notifier.push("No project open");
					return;
				}
				if (app.connections.open)
				{
					app.connections.close();
				}
				else
				{
					app.connections.show();
				}
				return;
			}
		case commands::CommandId.QUIT:

			{
				*app.quit_requested = true;
				return;
			}
		case commands::CommandId.CLOSE_CARD:

			{
				int index = target_card_index(project);
				if (index < 0) return;
				FileCard* card = &project.cards[index];
				if (card.ephemeral)
				{
					project.discard_ephemeral(-1);
				}
				else if (card.buffer)
				{
					if (card.dirty)
					{
						project.pending_close = project.focus(index);
					}
					else
					{
						(void)editor::unload_buffer(card, project.allocator);
					}
				}
				return;
			}
		case commands::CommandId.TOGGLE_CARD:

			{
				int index = target_card_index(project);
				if (index < 0) return;
				project.cards[index].open = !project.cards[index].open;
				return;
			}
		case commands::CommandId.TOGGLE_PREVIEW:

			{
				int index = project.focus_card >= 0 ? project.focus_card : target_card_index(project);
				if (index < 0) return;
				project.toggle_preview(index);
				return;
			}
		case commands::CommandId.RENAME_CARD:

			{
				int index = target_card_index(project);
				if (index < 0) return;
				app.pending_rename_card = index;
				*app.pending_kind = 2;
				app.name_prompt.open_with("Rename", project.cards[index].name);
				return;
			}
		case commands::CommandId.DUPLICATE_CARD:

			{
				int index = target_card_index(project);
				if (index < 0) return;
				RLVector2 pos = project.cards[index].center();
				int duplicate = project.duplicate_card(index, pos);
				if (duplicate < 0)
				{
					app.notifier.push("Could not duplicate");
				}
				else
				{
					project.snap_card_to_grid(duplicate, app.canvas.camera.zoom);
					app.notifier.push("Duplicated");
				}
				return;
			}
		case commands::CommandId.COPY_PATH:

			{
				int index = target_card_index(project);
				if (index < 0) return;
				@pool()
				{
					rl::set_clipboard_text(((String)project.cards[index].path).zstr_tcopy());
				};
				app.notifier.push("Path copied");
				return;
			}
		case commands::CommandId.DELETE_CARD:

			{
				int index = target_card_index(project);
				if (index < 0) return;
				app.pending_delete_card = index;
				RLVector2 center = {
					(float)rl::get_screen_width() / 2.0f,
					(float)rl::get_screen_height() / 2.0f,
				};
				app.delete_menu.open_at(center, { "Delete", "Cancel" });
				return;
			}
		case commands::CommandId.OPEN_CONTEXT_MENU:

			{
				int index = target_card_index(project);
				if (index < 0) return;
				FileCard* card = &project.cards[index];
				open_context_menu(app, context::ContextTarget.CARD, index, project::ROOT_FOLDER, card.center(), -1);
				return;
			}
		case commands::CommandId.MINIMAP_FOCUS:

			{
				Rect bounds;
				if (project.content_bounds(&bounds))
				{
					app.canvas.target.target = {
						bounds.x + bounds.width / 2.0f,
						bounds.y + bounds.height / 2.0f,
					};
				}
				return;
			}
		case commands::CommandId.ZOOM_RESET:
			app.canvas.reset_zoom();
			return;
		case commands::CommandId.ZOOM_FIT:

			{
				Rect bounds;
				if (project.content_bounds(&bounds))
				{
					app.canvas.fit_zoom(bounds, rl::get_screen_width(), rl::get_screen_height());
				}
				return;
			}
		default:
			return;
	}
}

fn void focus_camera_on_line(
	project::Project* project,
	canvas::Canvas* canvas,
	editor::EditorMetrics metrics,
	FileCard* card,
	usz line
)
{
	Rect text        = editor::text_rect(card.rect, metrics, card.buffer.line_count());
	float world_y    = text.y + editor::line_y(line, card.scroll, metrics) + metrics.line_height * 0.5f;
	RLVector2 center = card.center();
	canvas.target.target = { center[0], world_y };
	if (canvas.target.zoom < canvas::settings().jump_zoom_min) canvas.target.zoom = canvas::settings().jump_zoom_target;
	project.mark_jump((String)card.path, line, rl::get_time());
}

fn void navigate_to_location(
	project::Project* project,
	canvas::Canvas* canvas,
	editor::EditorMetrics metrics,
	String path,
	uint line,
	uint character
)
{
	int index = project.find_card(path);
	if (index < 0)
	{
		bool ephemeral = false;
		String target  = path;
		if (!project::path_is_inside((String)project.root, path))
		{
			String? copied = project.external_copy(path);
			if (catch excuse = copied)
			{
				return;
			}
			target = copied;
			ephemeral = true;
		}
		RLVector2 center = {
			(float)rl::get_screen_width() / 2.0f,
			(float)rl::get_screen_height() / 2.0f,
		};
		RLVector2 world = canvas.screen_to_world(center);
		index = project.add_card(target, world);
		if (index >= 0 && ephemeral && project.focused >= 0)
		{
			project.cards[project.focused].ephemeral = true;
		}
	}
	if (index < 0) return;

	project.focus(index);
	FileCard* card = project.focused_card();
	if (!card) return;
	editor::ensure_buffer(card, project.allocator);
	if (!card.buffer) return;

	card.cursor = lsp::offset_from_position(card.buffer, line, character);
	card.selection_anchor = card.cursor;
	usz card_line = card.buffer.line_of(card.cursor);
	card.preferred_column = editor::column_for_offset(card.buffer, card_line, card.cursor);
	Rect text = editor::text_rect(card.rect, metrics, card.buffer.line_count());
	card.scroll = editor::scroll_to_reveal(card.buffer, metrics, text.height, card.cursor, card.scroll);
	card.scroll_x = editor::scroll_x_to_reveal(
		card.buffer,
		metrics,
		text.width,
		card.cursor,
		card.scroll_x,
		lsp::lsp_inlay_hints_for((String)card.path)
	);
	focus_camera_on_line(project, canvas, metrics, card, card_line);
}

fn void clear_definitions(List{lsp::DefinitionTarget}* list)
{
	for (sz i = 0; i < list.len(); i++)
	{
		if ((*list)[i].path.len) (*list)[i].path.free(list.allocator);
	}
	list.clear();
}

fn void clear_pending_definitions(List{lsp::DefinitionTarget}* list)
{
	clear_definitions(list);
	list.free();
}

fn void clear_actions(List{lsp::CodeActionItem}* list)
{
	for (sz i = 0; i < list.len(); i++)
	{
		lsp::lsp_code_action_free(&(*list)[i], mem);
	}
	list.clear();
}

fn void clear_pending_actions(List{lsp::CodeActionItem}* list)
{
	clear_actions(list);
	list.free();
}

fn bool draw_signature_help(
	project::Project* project,
	canvas::Canvas* canvas,
	editor::EditorMetrics metrics,
	RLFont font
)
{
	FileCard* card = project.focused_card();
	if (!card || !card.buffer) return false;
	if (!lsp::lsp_signature_valid((String)card.path, card.cursor)) return false;
	Rect text = editor::text_rect(card.rect, metrics, card.buffer.line_count());
	Rect caret = editor::caret_rect(
		card.buffer,
		text,
		card.scroll,
		card.scroll_x,
		metrics,
		card.cursor,
		lsp::lsp_inlay_hints_for((String)card.path)
	);
	Rect screen      = editor::world_rect_to_screen(caret, canvas.camera);
	RLVector2 anchor = { screen.x, screen.y + screen.height + 4.0f };
	hover::draw_hover(lsp::lsp_signature_message(), anchor, font);
	return true;
}

struct HoverInfo
{
	bool over;
	String path;
	PieceTable* table;
	usz offset;
	RLVector2 anchor;
	String diagnostic;
}

fn HoverInfo compute_hover(project::Project* project, canvas::Canvas* canvas, editor::EditorMetrics metrics)
{
	HoverInfo info = {
		.over = false,
		.path = "",
		.table = null,
		.offset = 0,
		.anchor = { 0.0f, 0.0f },
		.diagnostic = ""
	};
	if (project.drag_card || project.selecting || project.resizing) return info;

	FileCard* card = project.focused_card();
	if (!card || !card.buffer) return info;

	Rect text       = editor::text_rect(card.rect, metrics, card.buffer.line_count());
	RLVector2 mouse = rl::get_mouse_position();
	RLVector2 world = canvas.screen_to_world(mouse);
	bool over_text  = world[0] >= text.x && world[0] <= text.x + text.width && world[1] >= text.y
		&& world[1] <= text.y + text.height;

	if (over_text)
	{
		usz offset = editor::offset_for_point(
			card.buffer,
			world[0] - text.x,
			world[1] - text.y,
			card.scroll,
			card.scroll_x,
			metrics,
			lsp::lsp_inlay_hints_for((String)card.path)
		);
		lsp::LspDiagnostic[] diags = lsp::lsp_diagnostics_for((String)card.path);
		for (usz i = 0; i < diags.len; i++)
		{
			if (editor::diagnostic_contains(card.buffer, diags[i], offset))
			{
				info.diagnostic = diags[i].message;
				info.anchor = mouse;
				return info;
			}
		}
		info.over = true;
		info.path = (String)card.path;
		info.table = card.buffer;
		info.offset = offset;
		info.anchor = mouse;
		return info;
	}

	info.over = true;
	info.path = (String)card.path;
	info.table = card.buffer;
	info.offset = card.cursor;
	Rect caret = editor::caret_rect(
		card.buffer,
		text,
		card.scroll,
		card.scroll_x,
		metrics,
		card.cursor,
		lsp::lsp_inlay_hints_for((String)card.path)
	);
	Rect screen = editor::world_rect_to_screen(caret, canvas.camera);
	info.anchor = { screen.x, screen.y + screen.height };
	return info;
}

fn void mark_buffer_changed(project::Project* project, findbar::FindBar* find_bar, editor::EditorMetrics metrics)
{
	FileCard* card = project.focused_card();
	if (!card) return;
	card.dirty = true;
	if (card.highlight) card.highlight.mark_dirty();
	if (card.view) markdown::view_mark_dirty(card.view);
	project.reveal_focused(metrics);
	find_bar.mark_dirty();
}

const String FONT_PATH           = "assets/fonts/JetBrainsMono-Regular.ttf";
const float GRAB_MOVE_SPEED      = 700.0f;
const float GRAB_MOVE_FINE_SPEED = 250.0f;

fn RLFont finish_font(RLFont font)
{
	if (font.texture.id > 0)
	{
		rl::gen_texture_mipmaps(&font.texture);
		font.texture.set_filter(RLTextureFilter.TRILINEAR);
	}
	return font;
}

fn RLFont load_bundled_font(int size)
{
	if (file::exists(FONT_PATH)) return finish_font(rl::load_font_ex(FONT_PATH, size, null, 0));
	@pool()
	{
		String exe    = rl::get_application_directory().str_view();
		String joined = string::format(tmem, "%s%s", exe, FONT_PATH);
		if (file::exists(joined)) return finish_font(rl::load_font_ex((ZString)joined.ptr, size, null, 0));
	};
	return finish_font(rl::load_font_ex(FONT_PATH, size, null, 0));
}

fn RLFont load_editor_font(fonts::Fonts* fonts, String family, int size)
{
	if (family.len > 0 && family.compare_to("JetBrains Mono") != 0)
	{
		String path = fonts.path_for(family);
		if (path.len > 0 && file::exists(path))
		{
			@pool()
			{
				return finish_font(rl::load_font_ex(path.zstr_tcopy(), size, null, 0));
			};
		}
	}
	return load_bundled_font(size);
}

fn void reload_editor_font(
	fonts::Fonts* fonts,
	RLFont* font,
	int atlas_size,
	float draw_size,
	String family,
	editor::EditorMetrics* metrics
)
{
	rl::unload_font(*font);
	*font = load_editor_font(fonts, family, atlas_size);
	*metrics = editor::metrics_for_font(*font, draw_size);
	editor::set_font_size(draw_size);
}

fn bool debug_ui_enabled()
{
	@pool()
	{
		String? value = env::get_var(tmem, "YUN_DEBUG_UI");
		if (catch excuse = value) return false;
		return value.len > 0 && value[0] != '0';
	};
}

fn void log_ui_diagnostics(project::Project* project)
{
	if (!debug_ui_enabled()) return;
	@pool()
	{
		int monitor = rl::get_current_monitor();
		float scale = rl::get_window_scale_dpi()[0];
		String cwd  = rl::get_working_directory().str_view();
		String exe  = rl::get_application_directory().str_view();

		String platform = "linux";
		$if env::WIN32:
			platform = "windows";
		$else
			$if env::DARWIN:
				platform = "macos";
			$endif
		$endif

		String exe_icons = string::format(tmem, "%sassets/icons", exe);
		String exe_font  = string::format(tmem, "%s%s", exe, FONT_PATH);
		io::printfn(
			"yun ui: platform=%s window=%dx%d screen=%dx%d render=%dx%d monitor=%d %dx%d phys=%dx%dmm dpi_scale=%.2f ui_scale=%.2f layout=%.2f font=%.2f",
			platform,
			rl::get_screen_width(),
			rl::get_screen_height(),
			rl::get_screen_width(),
			rl::get_screen_height(),
			rl::get_render_width(),
			rl::get_render_height(),
			monitor,
			rl::get_monitor_width(monitor),
			rl::get_monitor_height(monitor),
			rl::get_monitor_physical_width(monitor),
			rl::get_monitor_physical_height(monitor),
			(double)scale,
			(double)ui::scale(),
			(double)ui::layout_scale(),
			(double)ui::font_scale()
		);
		io::printfn(
			"yun ui: theme=%s ui_icons=%s file_icons=%s cwd_icons=%s exe_icons=%s cwd_font=%s exe_font=%s cards=%d cwd=\"%s\" exe=\"%s\"",
			theme::current_name(),
			icons::ui_icon_theme_name(),
			icons::file_icon_theme_current_name(),
			file::exists("assets/icons") ? "yes" : "no",
			file::exists(exe_icons) ? "yes" : "no",
			file::exists(FONT_PATH) ? "yes" : "no",
			file::exists(exe_font) ? "yes" : "no",
			(int)project.cards.len(),
			cwd,
			exe
		);
	};
}

fn void update_dpi(
	fonts::Fonts* fonts,
	config::Config* config,
	canvas::Canvas* canvas,
	RLFont* ui_font,
	RLFont* editor_font,
	int ui_size,
	int font_size,
	editor::EditorMetrics* metrics,
	bool* ready,
	float* last_font_scale,
	float* last_layout_scale
)
{
	int monitor    = rl::get_current_monitor();
	float os_scale = rl::get_window_scale_dpi()[0];
	if (os_scale < 1.0f) os_scale = 1.0f;

	float ppi   = 1.0f;
	int phys_mm = rl::get_monitor_physical_width(monitor);
	int mon_w   = rl::get_monitor_width(monitor);
	if (phys_mm > 0 && mon_w > 0)
	{
		float dpi = (float)mon_w / ((float)phys_mm / 25.4f);
		ppi = dpi / 96.0f;
	}
	if (ppi < 1.0f) ppi = 1.0f;
	if (ppi > 3.0f) ppi = 3.0f;

	int sw             = rl::get_screen_width();
	int rw             = rl::get_render_width();
	float render_scale = (sw > 0 && rw > sw) ? (float)rw / (float)sw : 1.0f;

	float layout_scale = render_scale > 1.0f ? 1.0f : math::max(os_scale, ppi);
	float font_scale   = layout_scale * math::max(1.0f, render_scale);

	if (*ready && layout_scale == *last_layout_scale && font_scale == *last_font_scale) return;
	*ready = true;
	*last_font_scale = font_scale;
	*last_layout_scale = layout_scale;
	ui::set_dpi(font_scale, layout_scale);

	int atlas = ui::atlas_px(ui_size);
	rl::unload_font(*ui_font);
	*ui_font = load_editor_font(fonts, config.settings.get_string(settings::SettingId.APP_UI_FONT_FAMILY), atlas);
	ui::set_font(*ui_font, ui_size);

	reload_editor_font(
		fonts,
		editor_font,
		ui::atlas_px(font_size),
		(float)ui::draw_px(font_size),
		config.settings.get_string(settings::SettingId.EDITOR_FONT_FAMILY),
		metrics
	);

	apply_chrome_insets(canvas, null, false, 0.0f);
	canvas.camera.offset = { canvas.usable_offset_x(), canvas.usable_offset_y() };
}

fn int parse_int(String s)
{
	int value = 0;
	for (usz i = 0; i < s.len; i++)
	{
		char c = s[i];
		if (c < '0' || c > '9') break;
		value = value * 10 + (int)(c - '0');
	}
	return value;
}

fn int main(String[] args)
{
	rl::set_config_flags(
		(RLConfigFlag)(rl::RLConfigFlag.WINDOW_RESIZABLE | rl::RLConfigFlag.VSYNC_HINT
			| rl::RLConfigFlag.WINDOW_HIGHDPI)
	);
	rl::init_window(1280, 720, "Yun");
	defer rl::close_window();
	rl::set_target_fps(60);
	rl::set_exit_key(rl::RLKeyboardKey.NONE);

	RLFont font = load_bundled_font(16);
	defer rl::unload_font(font);
	ui::set_font(font, 16);

	int ui_size                   = 16;
	bool dpi_ready                = false;
	float dpi_font_scale          = 1.0f;
	float dpi_layout_scale        = 1.0f;
	int font_size                 = editor::FONT_SIZE_DEFAULT;
	RLFont editor_font            = load_bundled_font(font_size);
	editor::EditorMetrics metrics = editor::metrics_for_font(editor_font, (float)font_size);
	editor::set_font_size((float)font_size);

	canvas::Canvas canvas;
	canvas.init();
	apply_chrome_insets(&canvas, null, false, 0.0f);

	project::Project project;
	project.init(mem);
	project.set_editor_metrics(metrics);

	notify::Notifier notifier;
	notifier.init(mem);

	config::Config config;
	config.init(mem);

	lsp::Lsp lsp;
	lsp.init(mem, &config);
	lsp::lsp_set_active(&lsp);
	completion::completion_init(mem);
	imports::ImportIndex import_index;
	import_index.init(mem);

	browser::Browser browser;
	browser.init(mem);

	menu::Menu context_menu;
	context_menu.init(mem);

	menu::Menu reload_menu;
	reload_menu.init(mem);

	menu::Menu theme_menu;
	theme_menu.init(mem);

	menu::Menu profile_menu;
	profile_menu.init(mem);

	menu::Menu close_menu;
	close_menu.init(mem);

	menu::Menu delete_menu;
	delete_menu.init(mem);

	prompt::Prompt name_prompt;
	name_prompt.init();

	topbar::TopBar bar;
	bar.init();

	palette::Palette palette;
	palette.init(mem);

	findbar::FindBar find_bar;
	find_bar.init(mem);

	problems::Problems problems;
	problems.init(mem);

	connections::Connections connections;
	connections.init(mem);

	settings_panel::Panel settings_panel;
	settings_panel.init(mem);

	search::Search search;
	search.init(mem);

	symbols::Symbols symbols;
	symbols.init(mem);

	console::ConsoleManager console_manager;
	console_manager.init(mem);
	defer console_manager.destroy();

	git::State git_state;
	git_state.init(mem);
	defer git_state.destroy();

	git::Panel git_panel;
	git_panel.init(mem);
	defer git_panel.destroy();

	git::DiffView diff_view;
	diff_view.init(mem);
	defer diff_view.destroy();

	git::ConflictView conflict_view;
	conflict_view.init(mem);
	defer conflict_view.destroy();

	git::HistoryView history_view;
	history_view.init(mem);
	defer history_view.destroy();
	console::Console* console            = console_manager.active_console();
	console::ConsolePanel* console_panel = console_manager.active_panel();

	keymap::Keymap keymap;
	keymap.init(mem);

	fonts::Fonts fonts;
	fonts.init(mem);

	icons::init(mem);
	settings::set_font_options(fonts.labels());

	int pending_kind          = 0;
	int pending_parent        = project::ROOT_FOLDER;
	usz pending_rename_offset = 0;
	RLVector2 pending_world   = { 0.0f, 0.0f };

	menu::Menu definition_menu;
	definition_menu.init(mem);
	List{lsp::DefinitionTarget} pending_definitions;
	pending_definitions.init(mem);
	List{lsp::CodeActionItem} pending_actions;
	pending_actions.init(mem);
	int definition_menu_kind = 0;

	// Teardown: registered here so LIFO order is exactly the reverse of this list.
	defer rl::unload_font(editor_font);
	defer config.destroy();
	defer keymap.destroy();
	defer settings_panel.destroy();
	defer icons::shutdown();
	defer fonts.destroy();
	defer language::shutdown_grammars();
	defer highlight::shutdown();
	defer imports::shutdown_queries();
	defer search.destroy();
	defer symbols.destroy();
	defer import_index.destroy();
	defer lsp.destroy();
	defer clear_pending_definitions(&pending_definitions);
	defer clear_pending_actions(&pending_actions);
	defer notifier.destroy();
	defer context_menu.destroy();
	defer reload_menu.destroy();
	defer theme_menu.destroy();
	defer profile_menu.destroy();
	defer close_menu.destroy();
	defer delete_menu.destroy();
	defer definition_menu.destroy();
	defer browser.destroy();
	defer palette.destroy();
	defer find_bar.destroy();
	defer problems.destroy();
	defer connections.destroy();
	defer completion::completion_destroy();
	defer project.destroy();

	bool project_open           = false;
	bool quit_requested         = false;
	project::OpenJob* open_job  = null;
	bool opening                = false;
	bool content_changed        = false;
	double font_indicator_until = 0.0;
	UiMode ui_mode              = UiMode.MOVE;
	UiMode focus_saved_mode     = UiMode.MOVE;
	UiMode console_saved_mode   = UiMode.MOVE;
	UiMode scm_saved_mode       = UiMode.MOVE;
	UiMode diff_saved_mode      = UiMode.MOVE;
	UiMode conflict_saved_mode  = UiMode.MOVE;
	UiMode history_saved_mode   = UiMode.MOVE;
	int edit_grace_frames       = 0;
	bool selftest               = false;
	String visual_dir           = "";
	bool benchmark_on           = false;
	bool benchmark_synthetic    = false;
	int benchmark_cards         = 0;
	int benchmark_frames        = 240;
	for (usz i = 1; i < args.len; i++)
	{
		String arg = args[i];
		if (arg.compare_to("--selftest") == 0)
		{
			selftest = true;
		}
		else if (arg.starts_with("--visual-suite="))
		{
			visual_dir = arg[15..].copy(mem);
		}
		else if (arg.starts_with("--benchmark-frames="))
		{
			benchmark_on = true;
			benchmark_frames = parse_int(arg[19..]);
		}
		else if (arg.compare_to("--benchmark") == 0)
		{
			benchmark_on = true;
			if (benchmark_cards == 0) benchmark_cards = 200;
		}
		else if (arg.starts_with("--benchmark="))
		{
			benchmark_on = true;
			benchmark_cards = parse_int(arg[12..]);
		}
	}
	if (benchmark_frames < 1) benchmark_frames = 1;
	bool open_path = !selftest && args.len > 1 && !args[1].starts_with("--");
	if (open_path)
	{
		String? resolved = project::resolve_path(project.allocator, args[1]);
		if (catch excuse = resolved)
		{
			notifier.push("Could not resolve the given path");
		}
		else if (!path::is_dir((Path)resolved))
		{
			notifier.push("Not a directory");
		}
		else
		{
			config.load((String)resolved);
			apply_settings(
				&config,
				&fonts,
				&notifier,
				&project,
				&canvas,
				&font_size,
				&editor_font,
				&metrics,
				&ui_size,
				&font,
				&console_manager
			);
			open_job = project::open_job_create(project.allocator, &project, resolved);
			opening = true;
		}
	}
	else
	{
		config.load("");
		apply_settings(
			&config,
			&fonts,
			&notifier,
			&project,
			&canvas,
			&font_size,
			&editor_font,
			&metrics,
			&ui_size,
			&font,
			&console_manager
		);
		if (benchmark_cards > 0)
		{
			benchmark_synthetic = true;
			int cols = 1;
			while (cols * cols < benchmark_cards) cols++;
			RLVector2 card_size = project.default_card_size();
			float cw            = card_size[0] + ui::pxf(32.0f);
			float ch            = card_size[1] + ui::pxf(32.0f);
			for (int k = 0; k < benchmark_cards; k++)
			{
				String path = string::format(project.allocator, "%s/bench_%d.c3", (String)project.root, k);
				int index   = project.append_card(path, { 0.0f, 0.0f });
				project.cards[index].rect = {
					.x = (float)(k % cols) * cw,
					.y = (float)(k / cols) * ch,
					.width = card_size[0],
					.height = card_size[1],
				};
			}
			project.invalidate_bounds();
			float span = (float)cols * cw;
			canvas.camera.target = { span / 2.0f, span / 2.0f };
			canvas.target.target = canvas.camera.target;
			canvas.camera.zoom = 0.5f;
			canvas.target.zoom = 0.5f;
		}
	}
	keymap.build(&config);
	push_config_warnings(&config, &notifier);
	push_keymap_warnings(&keymap, &notifier);

	App app = {
		.project = &project,
		.canvas = &canvas,
		.config = &config,
		.browser = &browser,
		.notifier = &notifier,
		.name_prompt = &name_prompt,
		.palette = &palette,
		.settings_panel = &settings_panel,
		.find_bar = &find_bar,
		.problems = &problems,
		.connections = &connections,
		.theme_menu = &theme_menu,
		.profile_menu = &profile_menu,
		.context_menu = &context_menu,
		.close_menu = &close_menu,
		.delete_menu = &delete_menu,
		.reload_menu = &reload_menu,
		.definition_menu = &definition_menu,
		.search = &search,
		.symbols = &symbols,
		.console_manager = &console_manager,
		.console = console,
		.console_panel = console_panel,
		.git = &git_state,
		.git_panel = &git_panel,
		.diff_view = &diff_view,
		.conflict_view = &conflict_view,
		.history_view = &history_view,
		.metrics = metrics,
		.project_open = &project_open,
		.content_changed = &content_changed,
		.quit_requested = &quit_requested,
		.ui_mode = &ui_mode,
		.focus_saved_mode = &focus_saved_mode,
		.console_saved_mode = &console_saved_mode,
		.scm_saved_mode = &scm_saved_mode,
		.diff_saved_mode = &diff_saved_mode,
		.conflict_saved_mode = &conflict_saved_mode,
		.history_saved_mode = &history_saved_mode,
		.edit_grace_frames = &edit_grace_frames,
		.bar = &bar,
		.keymap = &keymap,
		.context_item_count = 0,
		.context_card = -1,
		.context_parent = project::ROOT_FOLDER,
		.context_world = { 0.0f, 0.0f },
		.context_offset = -1,
		.pending_rename_card = -1,
		.pending_delete_card = -1,
		.pending_rename_offset = &pending_rename_offset,
		.pending_kind = &pending_kind,
		.pending_parent = &pending_parent,
		.pending_world = &pending_world,
	};

	RLVector2 last_arrow_mouse     =  { -1.0f, -1.0f };
	RLVector2 last_arrow_target    =  { 0.0f, 0.0f };
	float last_arrow_zoom          = -1.0f;
	bool arrow_hovered_cache       =  false;
	bool diagnostics_logged        =  false;
	input::RepeatState move_repeat =  { };
	ulong last_git_error_revision  =  0;
	ulong last_git_action_revision =  0;

	int frame_count    = 0;
	double prof_update = 0.0;
	double prof_scan   = 0.0;
	double prof_draw   = 0.0;
	double prof_frame  = 0.0;
	double bench_sum   = 0.0;
	double bench_max   = 0.0;
	double bench_min   = 1.0e30;
	int bench_over     = 0;
	int bench_samples  = 0;
	int bench_warmup   = 30;
	while (!rl::window_should_close() && !quit_requested)
	{
		frame_count++;
		ui::reset_cursor();
		console = console_manager.active_console();
		console_panel = console_manager.active_panel();
		app.console = console;
		app.console_panel = console_panel;
		apply_chrome_insets(&canvas, &git_panel, console_manager.visible, console_panel.height);
		if (ui_mode == UiMode.CONSOLE && !console_manager.visible)
		{
			ui_mode = console_saved_mode;
			console_panel.focused = false;
		}
		if (ui_mode == UiMode.SCM && !git_panel.visible) ui_mode = scm_saved_mode;
		if (ui_mode == UiMode.DIFF && !diff_view.open) ui_mode = diff_saved_mode;
		if (ui_mode == UiMode.CONFLICT && !conflict_view.open) ui_mode = conflict_saved_mode;
		if (ui_mode == UiMode.HISTORY && !history_view.open) ui_mode = history_saved_mode;
		if (ui_mode != UiMode.MOVE || project.grabbing) move_repeat.reset();
		if (selftest && frame_count > 3) break;
		bool bench_ready = benchmark_on && (benchmark_synthetic || project_open);
		if (bench_ready)
		{
			float t = (float)frame_count;
			Rect bounds;
			if (project.content_bounds(&bounds))
			{
				float cx     = bounds.x + bounds.width / 2.0f;
				float cy     = bounds.y + bounds.height / 2.0f;
				float radius = math::max(bounds.width, bounds.height) * 0.5f;
				canvas.target.target = {
					cx + radius * math::sin(t * 0.02f),
					cy + radius * math::cos(t * 0.017f),
				};
			}
			canvas.target.zoom = 0.55f + 0.35f * math::sin(t * 0.013f);
		}
		double frame_start = rl::get_time();
		double scan_ms     = 0.0;
		double update_ms   = 0.0;
		double draw_ms     = 0.0;
		float dt           = math::min(rl::get_frame_time(), canvas::MAX_FRAME_DT);
		update_dpi(
			&fonts,
			&config,
			&canvas,
			&font,
			&editor_font,
			ui_size,
			font_size,
			&metrics,
			&dpi_ready,
			&dpi_font_scale,
			&dpi_layout_scale
		);
		HoverInfo hover    = { };
		bool arrow_hovered = arrow_hovered_cache;
		double scan_t0     = rl::get_time();
		search.pump(&project, rl::get_time());
		symbols.pump(&project, rl::get_time());
		if (project_open)
		{
			git_state.update((String)project.root, project.cards_revision, rl::get_time(), rl::is_window_focused());
		}
		if (diff_view.sync(&git_state))
		{
			if (ui_mode != UiMode.DIFF) diff_saved_mode = ui_mode;
			ui_mode = UiMode.DIFF;
		}
		if (git_state.error_revision != last_git_error_revision)
		{
			last_git_error_revision = git_state.error_revision;
			if (git_state.error.kind != git::GitErrorKind.NONE && !git_state.error_quiet)
			{
				notifier.push(git_state.error.message);
			}
		}
		if (git_state.action_revision != last_git_action_revision)
		{
			last_git_action_revision = git_state.action_revision;
			if (git_state.action.success)
			{
				switch (git_state.action.kind)
				{
					case git::GitRequestKind.FETCH:
						notifier.push("Fetched");
					case git::GitRequestKind.PULL:
						notifier.push("Pulled");
					case git::GitRequestKind.PUSH:
						notifier.push("Pushed");
					case git::GitRequestKind.PUBLISH:
						notifier.push("Published branch");
					case git::GitRequestKind.DETECT:
					case git::GitRequestKind.STATUS:
					case git::GitRequestKind.DIFF:
					case git::GitRequestKind.STAGE:
					case git::GitRequestKind.UNSTAGE:
					case git::GitRequestKind.DISCARD:
					case git::GitRequestKind.COMMIT:
					case git::GitRequestKind.BRANCH_LIST:
					case git::GitRequestKind.BRANCH_SWITCH:
					case git::GitRequestKind.BRANCH_CREATE:
					case git::GitRequestKind.MERGE_ABORT:
					case git::GitRequestKind.APPLY_PATCH:
					case git::GitRequestKind.LOG:
					case git::GitRequestKind.COMMIT_FILES:
						break;
				}
			}
		}
		console_manager.pump();
		notify_console_finishes(&console_manager, &notifier, ui_mode == UiMode.CONSOLE && console_manager.visible);
		scan_ms += (rl::get_time() - scan_t0) * 1000.0;

		apply_settings(
			&config,
			&fonts,
			&notifier,
			&project,
			&canvas,
			&font_size,
			&editor_font,
			&metrics,
			&ui_size,
			&font,
			&console_manager
		);
		if (!diagnostics_logged)
		{
			diagnostics_logged = true;
			log_ui_diagnostics(&project);
		}

		if (opening)
		{
			if (open_job.phase == project::OpenPhase.SCAN && rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
			{
				open_job.cancel();
			}
			usz budget = open_job.phase == project::OpenPhase.SCAN ? project::OPEN_SCAN_BUDGET
				: project::OPEN_BUILD_BUDGET;
			if (open_job.step(budget))
			{
				opening = false;
				if (open_job.phase == project::OpenPhase.DONE)
				{
					project_open = true;
					console_manager.reset((String)project.root);
					finish_open(&project, &canvas, &config, &keymap, &notifier, &console_manager);
					git_state.set_project((String)project.root);
					console = console_manager.active_console();
					console_panel = console_manager.active_panel();
					search.close();
					symbols.close();
					symbols.defer_project(&project);
					ui_mode = UiMode.MOVE;
					project.selected = -1;
					apply_settings(
						&config,
						&fonts,
						&notifier,
						&project,
						&canvas,
						&font_size,
						&editor_font,
						&metrics,
						&ui_size,
						&font,
						&console_manager
					);
					lsp.set_root((String)project.root);
					completion::completion_close();
					import_index.start_scan(&project);
					if (visual_dir.len > 0) visual_suite_begin(&app, &project, visual_dir);
				}
				else if (!open_job.cancelled)
				{
					notifier.push("Could not open the folder");
				}
				project::open_job_destroy(open_job);
				open_job = null;
			}
		}
		else if (browser.open)
		{
			if (browser.update(&keymap))
			{
				search.close();
				symbols.close();
				ui_mode = UiMode.MOVE;
				project.selected = -1;
				open_job = project::open_job_create(project.allocator, &project, (String)browser.dir);
				opening = true;
			}
			if (!browser.consumed) poll_global(&keymap, &app);
		}
		else if (palette.open)
		{
			int chosen = palette.update(&keymap, project_open, has_focused_buffer(&project));
			if (chosen >= 0)
			{
				palette.record((commands::CommandId)chosen);
				run_command((commands::CommandId)chosen, &app);
			}
			if (!palette.consumed) poll_global(&keymap, &app);
		}
		else if (settings_panel.open)
		{
			settings_panel.update(&keymap, &config, project_open, (String)project.root, &notifier);
			if (!settings_panel.consumed) poll_global(&keymap, &app);
		}
		else if (problems.open)
		{
			int chosen = problems.update(&keymap);
			if (chosen >= 0)
			{
				problems::ProblemEntry* entry = problems.entry_at(chosen);
				if (entry)
				{
					navigate_to_location(&project, &canvas, metrics, entry.path, entry.line, entry.character);
				}
			}
			if (!problems.consumed) poll_global(&keymap, &app);
		}
		else if (definition_menu.open)
		{
			int chosen = definition_menu.update(&keymap);
			if (chosen >= 0)
			{
				if (definition_menu_kind == 1)
				{
					if (chosen < (int)pending_actions.len())
					{
						lsp::CodeActionItem* action = &pending_actions[(sz)chosen];
						if (project.apply_workspace_edit(&action.edit, rl::get_time()))
						{
							notifier.push("Applied code action");
						}
						else
						{
							notifier.push("Code action needs all affected files open");
						}
					}
				}
				else if (chosen < (int)pending_definitions.len())
				{
					lsp::DefinitionTarget target = pending_definitions[(sz)chosen];
					navigate_to_location(&project, &canvas, metrics, target.path, target.line, target.character);
				}
			}
			if (!definition_menu.open)
			{
				clear_definitions(&pending_definitions);
				clear_actions(&pending_actions);
				definition_menu_kind = 0;
			}
			if (!definition_menu.consumed) poll_global(&keymap, &app);
		}
		else if (name_prompt.open)
		{
			if (name_prompt.update(&keymap))
			{
				String name = name_prompt.text_view();
				if (!project::is_valid_name(name))
				{
					notifier.push("Invalid name");
				}
				else if (pending_kind == 3)
				{
					if (app.pending_rename_card < 0 || app.pending_rename_card >= (int)project.cards.len())
					{
						notifier.push("No file to rename");
					}
					else
					{
						FileCard* rename_card = &project.cards[app.pending_rename_card];
						if (!rename_card.buffer)
						{
							notifier.push("No file to rename");
						}
						else if (!lsp::lsp_request_rename(
							(String)rename_card.path,
							rename_card.buffer,
							*app.pending_rename_offset,
							name
						))
						{
							notifier.push("No rename provider");
						}
						else
						{
							name_prompt.close();
						}
					}
				}
				else if (pending_kind == 2)
				{
					if (project.rename_card(app.pending_rename_card, name))
					{
						name_prompt.close();
					}
					else
					{
						notifier.push("Could not rename");
					}
				}
				else
				{
					int result = pending_kind == 0 ? project.create_file(pending_parent, name, pending_world)
						: project.create_folder_on_disk(pending_parent, name, pending_world);
					if (result < 0)
					{
						notifier.push("Could not create");
					}
					else
					{
						if (pending_kind == 0)
						{
							project.snap_card_to_grid(result, canvas.camera.zoom);
						}
						else
						{
							project.snap_cluster_to_grid(result, canvas.camera.zoom);
						}
						name_prompt.close();
					}
				}
			}
			if (!name_prompt.consumed) poll_global(&keymap, &app);
		}
		else if (close_menu.open)
		{
			int chosen = close_menu.update(&keymap);
			if (chosen >= 0)
			{
				int index = project.pending_close;
				if (chosen == 0 && index >= 0 && index < (int)project.cards.len())
				{
					(void)editor::unload_buffer(&project.cards[index], project.allocator);
				}
				project.pending_close = -1;
			}
			if (!close_menu.consumed) poll_global(&keymap, &app);
		}
		else if (delete_menu.open)
		{
			int chosen = delete_menu.update(&keymap);
			if (chosen >= 0)
			{
				if (chosen == 0 && app.pending_delete_card >= 0 && app.pending_delete_card < (int)project.cards.len())
				{
					if (project.delete_card_file(app.pending_delete_card))
					{
						notifier.push("Deleted");
					}
					else
					{
						notifier.push("Could not delete");
					}
				}
				app.pending_delete_card = -1;
			}
			if (!delete_menu.consumed) poll_global(&keymap, &app);
		}
		else if (reload_menu.open)
		{
			int chosen = reload_menu.update(&keymap);
			if (chosen >= 0)
			{
				int index = project.pending_reload;
				if (index >= 0 && index < (int)project.cards.len())
				{
					if (chosen == 0)
					{
						editor::reload_buffer(&project.cards[index], project.allocator);
						import_index.rescan(&project, index);
					}
					else
					{
						editor::stamp_file(&project.cards[index]);
					}
				}
				project.pending_reload = -1;
			}
			if (!reload_menu.consumed) poll_global(&keymap, &app);
		}
		else if (theme_menu.open)
		{
			int chosen = theme_menu.update(&keymap);
			if (chosen >= 0)
			{
				config.settings.set_string(
					settings::SettingId.APP_THEME,
					theme::name(chosen),
					settings::SettingLayer.GLOBAL
				);
				config.save_global();
				@pool()
				{
					notifier.push(string::format(tmem, "Theme: %s", theme::label(chosen)));
				};
			}
			if (!theme_menu.consumed) poll_global(&keymap, &app);
		}
		else if (profile_menu.open)
		{
			int chosen = profile_menu.update(&keymap);
			if (chosen >= 0 && chosen < (int)config.run_profiles.len())
			{
				run_profile(&app, &config.run_profiles[chosen]);
			}
			if (!profile_menu.consumed) poll_global(&keymap, &app);
		}
		else if (context_menu.open)
		{
			int chosen = context_menu.update(&keymap);
			if (chosen >= 0 && chosen < (int)app.context_item_count)
			{
				context::ContextAction action = app.context_items[chosen].action;
				switch (action)
				{
					case context::ContextAction.NEW_FILE:
					case context::ContextAction.NEW_FOLDER:

						{
							pending_kind = action == context::ContextAction.NEW_FILE ? 0 : 1;
							pending_parent = app.context_parent;
							pending_world = app.context_world;
							name_prompt.open_with(pending_kind == 0 ? "New file" : "New folder", "");
							break;
						}
					case context::ContextAction.OPEN_PROJECT:
						run_command(commands::CommandId.OPEN, &app);
						break;
					case context::ContextAction.TOGGLE_CARD:

						{
							if (app.context_card >= 0 && app.context_card < (int)project.cards.len())
							{
								project.cards[app.context_card].open = !project.cards[app.context_card].open;
							}
							break;
						}
					case context::ContextAction.RENAME_CARD:

						{
							if (app.context_card >= 0 && app.context_card < (int)project.cards.len())
							{
								app.pending_rename_card = app.context_card;
								pending_kind = 2;
								name_prompt.open_with("Rename", project.cards[app.context_card].name);
							}
							break;
						}
					case context::ContextAction.DUPLICATE_CARD:

						{
							int duplicate = project.duplicate_card(app.context_card, app.context_world);
							if (duplicate < 0)
							{
								notifier.push("Could not duplicate");
							}
							else
							{
								project.snap_card_to_grid(duplicate, canvas.camera.zoom);
								notifier.push("Duplicated");
							}
							break;
						}
					case context::ContextAction.COPY_PATH:

						{
							if (app.context_card >= 0 && app.context_card < (int)project.cards.len())
							{
								@pool()
								{
									rl::set_clipboard_text(((String)project.cards[app.context_card].path).zstr_tcopy());
								};
								notifier.push("Path copied");
							}
							break;
						}
					case context::ContextAction.DELETE_CARD:

						{
							if (app.context_card >= 0 && app.context_card < (int)project.cards.len())
							{
								app.pending_delete_card = app.context_card;
								RLVector2 center = {
									(float)rl::get_screen_width() / 2.0f,
									(float)rl::get_screen_height() / 2.0f,
								};
								delete_menu.open_at(center, { "Delete", "Cancel" });
							}
							break;
						}
					case context::ContextAction.MINIMIZE_CARD:

						{
							if (app.context_card >= 0 && app.context_card < (int)project.cards.len())
							{
								FileCard* mc = &project.cards[app.context_card];
								mc.rect.width = editor::min_card_width(app.metrics);
								mc.rect.height = editor::min_card_height(app.metrics);
								project.invalidate_bounds();
							}
							break;
						}
					case context::ContextAction.GO_TO_DEFINITION:

						{
							if (app.context_card >= 0 && app.context_card < (int)project.cards.len()
								&& app.context_offset >= 0)
							{
								int index    = project.focus(app.context_card);
								FileCard* cc = &project.cards[index];
								editor::ensure_buffer(cc, project.allocator);
								if (cc.buffer)
								{
									cc.cursor = (usz)app.context_offset;
									cc.selection_anchor = cc.cursor;
									if (!lsp::lsp_request_definition(
										(String)cc.path,
										cc.buffer,
										cc.cursor
									)) notifier.push("No definition provider");
								}
							}
							break;
						}
					case context::ContextAction.REFERENCES:

						{
							if (app.context_card >= 0 && app.context_card < (int)project.cards.len()
								&& app.context_offset >= 0)
							{
								int index    = project.focus(app.context_card);
								FileCard* cc = &project.cards[index];
								editor::ensure_buffer(cc, project.allocator);
								if (cc.buffer)
								{
									cc.cursor = (usz)app.context_offset;
									cc.selection_anchor = cc.cursor;
									if (!lsp::lsp_request_references(
										(String)cc.path,
										cc.buffer,
										cc.cursor
									)) notifier.push("No references provider");
								}
							}
							break;
						}
					case context::ContextAction.CODE_ACTIONS:

						{
							if (app.context_card >= 0 && app.context_card < (int)project.cards.len()
								&& app.context_offset >= 0)
							{
								int index    = project.focus(app.context_card);
								FileCard* cc = &project.cards[index];
								editor::ensure_buffer(cc, project.allocator);
								if (cc.buffer)
								{
									cc.cursor = (usz)app.context_offset;
									cc.selection_anchor = cc.cursor;
									if (!lsp::lsp_request_code_actions(
										(String)cc.path,
										cc.buffer,
										cc.cursor
									)) notifier.push("No code action provider");
								}
							}
							break;
						}
				}
			}
			if (!context_menu.consumed) poll_global(&keymap, &app);
		}
		else if (search.open)
		{
			search::SearchTarget target = search.update(&keymap, &project, rl::get_time());
			if (target.valid)
			{
				search.close();
				navigate_to_location(&project, &canvas, metrics, target.path, (uint)target.line, (uint)target.column);
			}
			if (!search.consumed) poll_global(&keymap, &app);
		}
		else if (symbols.open)
		{
			symbols::SymbolTarget target = symbols.update(&keymap, &project, rl::get_time());
			if (target.valid)
			{
				symbols.close();
				navigate_to_location(&project, &canvas, metrics, target.path, (uint)target.line, (uint)target.column);
			}
			if (!symbols.consumed) poll_global(&keymap, &app);
		}
		else if (find_bar.open)
		{
			int focus = project.focused;
			if (focus < 0 || focus >= (int)project.cards.len() || !project.cards[focus].buffer)
			{
				find_bar.close();
			}
			else
			{
				usz reveal    = 0;
				bool replaced = false;
				bool jumped   = false;
				int result = find_bar.update(
					&keymap,
					project.cards[focus].buffer,
					project.cards[focus].history,
					false,
					&reveal,
					&replaced,
					&jumped
				);
				if (result >= 0)
				{
					FileCard* card = &project.cards[focus];
					Rect text      = editor::text_rect(card.rect, metrics, card.buffer.line_count());
					if (result > 0)
					{
						card.scroll = editor::scroll_to_reveal(card.buffer, metrics, text.height, reveal, card.scroll);
						card.scroll_x = editor::scroll_x_to_reveal(
							card.buffer,
							metrics,
							text.width,
							reveal,
							card.scroll_x,
							lsp::lsp_inlay_hints_for((String)card.path)
						);
					}
					if (replaced) card.dirty = true;
					if (jumped)
					{
						usz line = card.buffer.line_of(reveal);
						focus_camera_on_line(&project, &canvas, metrics, card, line);
					}
				}
			}
			if (!find_bar.consumed) poll_global(&keymap, &app);
		}
		else
		{
			if (ui_mode == UiMode.EDIT && edit_grace_frames > 0)
			{
				while (rl::get_char_pressed() != 0)
				{
				}
				edit_grace_frames--;
			}
			RLVector2 mouse       = rl::get_mouse_position();
			RLVector2 world       = canvas.screen_to_world(mouse);
			bool over_connections = connections.contains_screen(mouse);
			if (diff_view.open)
			{
				diff_view.update(&git_state, &canvas, rl::get_time());
				if (diff_view.close_requested)
				{
					diff_view.close_requested = false;
					ui_mode = diff_saved_mode;
				}
			}
			if (conflict_view.open)
			{
				conflict_view.update(&git_state, &canvas, rl::get_time());
				if (conflict_view.close_requested)
				{
					conflict_view.close_requested = false;
					ui_mode = conflict_saved_mode;
				}
			}
			if (history_view.open && !diff_view.open && !conflict_view.open)
			{
				history_view.update(&git_state, &canvas, rl::get_time());
				if (history_view.close_requested)
				{
					history_view.close_requested = false;
					ui_mode = history_saved_mode;
				}
			}
			if (!diff_view.open && !conflict_view.open)
			{
				console_panel.update_mouse(&console_manager, console, metrics, mouse);
			}
			console_manager.sync_height();
			console = console_manager.active_console();
			console_panel = console_manager.active_panel();
			app.console = console;
			app.console_panel = console_panel;
			git_panel.bottom_inset = (console_manager.visible ? ui::pxf(console_panel.height)
				: 0.0f) + (topbar::position() == topbar::TopBarPosition.BOTTOM ? topbar::thickness_for(
					topbar::TopBarPosition.BOTTOM
				)
					: 0.0f);
			bool over_console  = console_panel.contains_screen(mouse);
			bool over_git      = git_panel.contains_screen(&canvas, mouse);
			bool editors_dirty = false;
			for (sz i = 0; i < project.cards.len(); i++)
			{
				if (project.cards[i].dirty)
				{
					editors_dirty = true;
					break;
				}
			}
			if (!diff_view.open && !conflict_view.open && !history_view.open)
			{
				git_panel.update(&git_state, &canvas, rl::get_time(), ui_mode == UiMode.SCM, editors_dirty);
			}
			if (git_panel.focus_requested)
			{
				if (ui_mode != UiMode.SCM) scm_saved_mode = ui_mode;
				ui_mode = UiMode.SCM;
				git_panel.focused = true;
				git_panel.focus_requested = false;
			}
			if (ui_mode == UiMode.SCM && git_panel.leave_requested)
			{
				ui_mode = scm_saved_mode;
				git_panel.focused = false;
			}
			if (ui_mode == UiMode.SCM && rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT) && !over_git)
			{
				ui_mode = scm_saved_mode;
				git_panel.focused = false;
			}
			String git_open_path = "";
			if (git_panel.take_open(&git_open_path))
			{
				navigate_to_location(&project, &canvas, metrics, git_open_path, 0, 0);
				git_open_path.free(mem);
				ui_mode = UiMode.EDIT;
				edit_grace_frames = 2;
			}
			String resolve_rel = "";
			String resolve_abs = "";
			if (git_panel.take_resolve(&resolve_rel, &resolve_abs))
			{
				conflict_view.open_file(resolve_rel, resolve_abs);
				resolve_rel.free(mem);
				resolve_abs.free(mem);
				if (ui_mode != UiMode.CONFLICT) conflict_saved_mode = ui_mode;
				ui_mode = UiMode.CONFLICT;
			}
			String history_path = "";
			if (git_panel.take_history(&history_path))
			{
				history_view.open_history(&git_state, history_path);
				if (history_path.len > 0) history_path.free(mem);
				if (ui_mode != UiMode.HISTORY) history_saved_mode = ui_mode;
				ui_mode = UiMode.HISTORY;
			}
			bool over_top   = diff_view.open || topbar::contains_screen(
				mouse
			) || over_connections || over_console || over_git;
			bool has_buffer = has_focused_buffer(&project);

			if (ui_mode == UiMode.CONSOLE && rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT) && !over_console)
			{
				ui_mode = console_saved_mode;
				console_panel.focused = false;
			}
			if (console_panel.focus_requested)
			{
				if (ui_mode != UiMode.CONSOLE) console_saved_mode = ui_mode;
				ui_mode = UiMode.CONSOLE;
				console_panel.focused = true;
				console_panel.focus_requested = false;
			}

			bool font_wheel = false;
			if (!over_top && project::ctrl_down())
			{
				float wheel = rl::get_mouse_wheel_move();
				if (wheel != 0.0f)
				{
					int step = wheel > 0.0f ? 1 : -1;
					int next = editor::clamp_font_size(font_size + step);
					if (next != font_size)
					{
						config.settings.set_int(
							settings::SettingId.EDITOR_FONT_SIZE,
							(long)next,
							settings::SettingLayer.GLOBAL
						);
						config.save_global();
						font_indicator_until = rl::get_time() + 1.2;
					}
					font_wheel = true;
				}
			}

			if (ui_mode == UiMode.EDIT)
			{
				if (keymap.pressed((int)commands::CommandId.FIND, commands::CTX_EDIT))
				{
					run_command(commands::CommandId.FIND, &app);
				}
				else if (keymap.pressed((int)commands::CommandId.REPLACE, commands::CTX_EDIT))
				{
					run_command(commands::CommandId.REPLACE, &app);
				}
			}

			int key_cmd = -1;
			if (!diff_view.open && !conflict_view.open && !history_view.open) key_cmd = keymap.poll(
				commands::CTX_GLOBAL
			);
			if (key_cmd >= 0) run_command((commands::CommandId)key_cmd, &app);

			int bar_cmd = -1;
			if (!diff_view.open && !conflict_view.open && !history_view.open) bar_cmd = bar.update(
				mouse,
				project_open,
				has_buffer
			);
			if (bar_cmd >= 0) run_command((commands::CommandId)bar_cmd, &app);

			if (ui_mode == UiMode.CONSOLE)
			{
				if (console_panel.update_input(console, &keymap, metrics))
				{
					ui_mode = console_saved_mode;
					console_panel.focused = false;
				}
			}
			else if (ui_mode == UiMode.TOP_BAR)
			{
				int bar_key_cmd = keymap.poll_exact(commands::CTX_TOP_BAR);
				if (bar_key_cmd < 0 && rl::is_key_pressed(rl::RLKeyboardKey.SPACE))
				{
					bar_key_cmd = (int)commands::CommandId.TOPBAR_ACTIVATE;
				}
				if (bar_key_cmd < 0 && rl::is_key_pressed(rl::RLKeyboardKey.TAB))
				{
					bar_key_cmd = (int)commands::CommandId.FOCUS_CANVAS;
				}
				if (bar_key_cmd >= 0) run_command((commands::CommandId)bar_key_cmd, &app);
				while (rl::get_char_pressed() != 0)
				{
				}
			}
			else if (ui_mode == UiMode.DIFF)
			{
				while (rl::get_char_pressed() != 0)
				{
				}
			}
			else if (ui_mode == UiMode.CONFLICT)
			{
				while (rl::get_char_pressed() != 0)
				{
				}
			}
			else if (ui_mode == UiMode.HISTORY)
			{
				while (rl::get_char_pressed() != 0)
				{
				}
			}
			else if (ui_mode == UiMode.SCM)
			{
				while (rl::get_char_pressed() != 0)
				{
				}
			}
			else if (ui_mode == UiMode.MOVE)
			{
				project.ensure_selection();

				if (project.grabbing)
				{
					if (keymap.pressed((int)commands::CommandId.CYCLE_FOCUS, commands::CTX_MOVE))
					{
						run_command(commands::CommandId.CYCLE_FOCUS, &app);
					}
					else if (rl::is_key_pressed(
						rl::RLKeyboardKey.ESCAPE
					) || rl::is_key_pressed(rl::RLKeyboardKey.ENTER) || rl::is_key_pressed(rl::RLKeyboardKey.KP_ENTER))
					{
						project.snap_selected_to_grid(canvas.camera.zoom);
						project.grabbing = false;
					}
					else
					{
						float zoom      = canvas.camera.zoom > 0.0f ? canvas.camera.zoom : 1.0f;
						float speed     = project::shift_down() ? GRAB_MOVE_FINE_SPEED : GRAB_MOVE_SPEED;
						float step      = speed * dt / zoom;
						RLVector2 delta = { 0.0f, 0.0f };
						if (rl::is_key_down(
							rl::RLKeyboardKey.LEFT
						) || rl::is_key_down(rl::RLKeyboardKey.H)) delta[0] -= step;
						if (rl::is_key_down(
							rl::RLKeyboardKey.RIGHT
						) || rl::is_key_down(rl::RLKeyboardKey.L)) delta[0] += step;
						if (rl::is_key_down(
							rl::RLKeyboardKey.UP
						) || rl::is_key_down(rl::RLKeyboardKey.K)) delta[1] -= step;
						if (rl::is_key_down(
							rl::RLKeyboardKey.DOWN
						) || rl::is_key_down(rl::RLKeyboardKey.J)) delta[1] += step;
						if (delta[0] != 0.0f || delta[1] != 0.0f)
						{
							project.apply_grab_delta(delta, project.grid_snap_step(&canvas));
						}

						Rect item = project.selected_item_rect();
						if (item.width > 0.0f && item.height > 0.0f)
						{
							RLVector2 a = rl::get_world_to_screen2d({ item.x, item.y }, canvas.camera);
							RLVector2 b = rl::get_world_to_screen2d(
								{ item.x + item.width, item.y + item.height },
								canvas.camera
							);
							Rect screen_item = {
								.x = math::min(a[0], b[0]),
								.y = math::min(a[1], b[1]),
								.width = math::abs(b[0] - a[0]),
								.height = math::abs(b[1] - a[1]),
							};
							float screen_w = (float)rl::get_screen_width();
							float screen_h = (float)rl::get_screen_height();
							float usable_w = screen_w - canvas.left_inset - canvas.right_inset;
							float usable_h = screen_h - canvas.top_inset - canvas.bottom_inset;
							float margin_x = math::max(
								canvas::GRAB_FOLLOW_MIN_X,
								usable_w * canvas::GRAB_FOLLOW_MARGIN_X
							);
							float margin_y = math::max(
								canvas::GRAB_FOLLOW_MIN_Y,
								usable_h * canvas::GRAB_FOLLOW_MARGIN_Y
							);
							Rect safe = {
								.x = canvas.left_inset + margin_x,
								.y = canvas.top_inset + margin_y,
								.width = usable_w - margin_x * 2.0f,
								.height = usable_h - margin_y * 2.0f,
							};
							RLVector2 follow = canvas::keep_item_in_view_delta(screen_item, safe, canvas.camera.zoom);
							canvas.target.target[0] += follow[0];
							canvas.target.target[1] += follow[1];
						}
					}
					while (rl::get_char_pressed() != 0)
					{
					}
				}
				else
				{
					int before         = project.selected;
					int before_cluster = project.selected_cluster;

					int move_cmd = keymap.poll_exact(commands::CTX_MOVE);
					if (move_cmd < 0 && rl::is_key_pressed(
						rl::RLKeyboardKey.LEFT
					)) move_cmd = (int)commands::CommandId.SELECT_LEFT;
					if (move_cmd < 0 && rl::is_key_pressed(
						rl::RLKeyboardKey.RIGHT
					)) move_cmd = (int)commands::CommandId.SELECT_RIGHT;
					if (move_cmd < 0 && rl::is_key_pressed(
						rl::RLKeyboardKey.UP
					)) move_cmd = (int)commands::CommandId.SELECT_UP;
					if (move_cmd < 0 && rl::is_key_pressed(
						rl::RLKeyboardKey.DOWN
					)) move_cmd = (int)commands::CommandId.SELECT_DOWN;
					if (move_cmd < 0 && rl::is_key_pressed(
						rl::RLKeyboardKey.I
					)) move_cmd = (int)commands::CommandId.FOCUS_EDITOR;
					if (move_cmd < 0 && rl::is_key_pressed(
						rl::RLKeyboardKey.ESCAPE
					)) move_cmd = (int)commands::CommandId.LEAVE_FOLDER;
					if (move_cmd < 0 && rl::is_key_pressed(
						rl::RLKeyboardKey.KP_ADD
					)) move_cmd = (int)commands::CommandId.ZOOM_IN;
					if (move_cmd < 0 && rl::is_key_pressed(
						rl::RLKeyboardKey.KP_SUBTRACT
					)) move_cmd = (int)commands::CommandId.ZOOM_OUT;
					int held_dir    = held_move_dir(&keymap);
					double move_now = rl::get_time();
					if (move_cmd >= 0)
					{
						run_command((commands::CommandId)move_cmd, &app);
						if (is_select_command(move_cmd))
						{
							move_repeat.start(held_dir, move_now);
						}
						else
						{
							move_repeat.reset();
						}
					}
					else
					{
						int repeat_cmd = move_repeat.tick(held_dir, move_now);
						if (repeat_cmd != 0) run_command((commands::CommandId)repeat_cmd, &app);
					}

					bool selection_changed = project.selected != before || project.selected_cluster != before_cluster;
					if (selection_changed)
					{
						Rect r    = project.selected_item_rect();
						Rect view = project::visible_world_rect(canvas.camera);
						if (r.width > 0.0f && !project::rect_intersects(r, view))
						{
							canvas.target.target = { r.x + r.width / 2.0f, r.y + r.height / 2.0f };
						}
					}

					while (rl::get_char_pressed() != 0)
					{
					}
				}
			}

			bool focus_active = project.focus_card >= 0;
			bool over_minimap = focus_active ? minimap::file_contains_screen(&project, mouse)
				: minimap::contains_screen(&project, &canvas, mouse);
			if (focus_active || over_top || over_minimap || project.hit_test(world) >= 0)
			{
				import_index.clear_hover();
				arrow_hovered = false;
			}
			else
			{
				bool moved          = mouse[0] != last_arrow_mouse[0] || mouse[1] != last_arrow_mouse[1];
				bool camera_changed = canvas.camera.zoom != last_arrow_zoom
					|| canvas.camera.target[0] != last_arrow_target[0]
					|| canvas.camera.target[1] != last_arrow_target[1];
				if (moved || camera_changed)
				{
					arrow_hovered = import_index.hit_test(&project, canvas.camera, world);
					last_arrow_mouse = mouse;
					last_arrow_zoom = canvas.camera.zoom;
					last_arrow_target = canvas.camera.target;
				}
				else
				{
					arrow_hovered = import_index.hover.valid;
				}
			}
			arrow_hovered_cache = arrow_hovered;
			connections::ConnectionTarget connection = connections.update_input(&project, &import_index);
			if (connection.valid)
			{
				navigate_to_location(
					&project,
					&canvas,
					metrics,
					connection.path,
					(uint)connection.line,
					(uint)connection.column
				);
			}
			canvas.pointer_over_ui = over_top || project.pointer_over_ui(world) || over_minimap || arrow_hovered;
			if (focus_active)
			{
				minimap::update_file(&project, metrics);
			}
			else
			{
				minimap::update(&project, &canvas);
			}

			if (!over_top && rl::is_mouse_button_pressed(
				rl::RLMouseButton.RIGHT
			) && !minimap::contains_screen(&project, &canvas, mouse))
			{
				int card   = project.hit_test(world);
				int folder = project.cluster_hit(world);

				context::ContextTarget target = context::ContextTarget.CANVAS;
				if (card >= 0)
				{
					target = context::ContextTarget.CARD;
				}
				else if (folder >= 0)
				{
					target = context::ContextTarget.CLUSTER;
				}

				int offset = -1;
				if (card >= 0 && project.cards[card].open && project.cards[card].buffer)
				{
					FileCard* cc = &project.cards[card];
					Rect text    = editor::text_rect(cc.rect, metrics, cc.buffer.line_count());
					if (world[0] >= text.x && world[0] <= text.x + text.width && world[1] >= text.y
						&& world[1] <= text.y + text.height)
					{
						offset = (int)editor::offset_for_point(
							cc.buffer,
							world[0] - text.x,
							world[1] - text.y,
							cc.scroll,
							cc.scroll_x,
							metrics,
							lsp::lsp_inlay_hints_for((String)cc.path)
						);
					}
				}
				open_context_menu(&app, target, card, folder, world, offset);
			}

			if (!over_top && rl::is_file_dropped())
			{
				RLFilePathList files = rl::load_dropped_files();
				for (uint i = 0; i < files.count; i++)
				{
					String path = files.paths[i].str_view().copy(mem);
					if (!rl::is_path_file(files.paths[i]))
					{
						int folder_index = project.add_folder_from_disk(path, world);
						if (folder_index < 0)
						{
							notifier.push("Drop folders from inside the project root");
						}
						else
						{
							project.snap_cluster_to_grid(folder_index, canvas.camera.zoom);
						}
						continue;
					}
					int card_index = project.add_card(path, world);
					if (card_index < 0)
					{
						notifier.push("Could not add dropped file");
					}
					else
					{
						project.snap_card_to_grid(card_index, canvas.camera.zoom);
					}
				}
				rl::unload_dropped_files(files);
			}

			if (project.focus_card >= 0) project.update_focus_rect(&canvas);

			content_changed = false;
			bool suppress_edit_input = (ui_mode == UiMode.EDIT && edit_grace_frames > 0) || ui_mode == UiMode.CONSOLE;
			double update_t0         = rl::get_time();
			project.update(&canvas, &keymap, suppress_edit_input, metrics, over_top || font_wheel, &content_changed);
			if (project.focus_toggle_requested)
			{
				project.focus_toggle_requested = false;
				run_command(commands::CommandId.TOGGLE_FOCUS_MODE, &app);
			}
			if (project.autosave_enabled && rl::get_time() - project.last_autosave >= project.autosave_interval)
			{
				project.last_autosave = rl::get_time();
				for (sz i = 0; i < project.cards.len(); i++)
				{
					if (project.cards[i].dirty && project.cards[i].buffer)
					{
						if (editor::save_buffer(&project.cards[i], project.allocator))
						{
							git_state.mark_dirty(rl::get_time());
						}
					}
				}
			}
			update_ms += (rl::get_time() - update_t0) * 1000.0;
			if (ui_mode == UiMode.EDIT && project.focused < 0)
			{
				ui_mode = UiMode.MOVE;
			}
			if (project.focus_card >= 0 && project.focused < 0)
			{
				project.end_focus(&canvas);
				ui_mode = focus_saved_mode;
			}
			project.discard_ephemeral(project.focused);
			if (content_changed)
			{
				find_bar.mark_dirty();
				if (project.focused >= 0 && project.focused < (int)project.cards.len())
				{
					import_index.note_edit((String)project.cards[project.focused].path, rl::get_time());
					symbols.note_edit((String)project.cards[project.focused].path, rl::get_time());
				}
			}
			import_index.flush_edits(&project, rl::get_time());
			import_index.sync(&project);
			double imports_t0 = rl::get_time();
			imports::ImportIndex.pump(&import_index, &project);
			scan_ms += (rl::get_time() - imports_t0) * 1000.0;
			if (over_top || font_wheel) canvas.block_zoom = true;
			canvas.block_pan = project.focus_card >= 0;
			if (project.focus_card >= 0) canvas.block_zoom = true;
			canvas.update();
			hover = compute_hover(&project, &canvas, metrics);

			if (arrow_hovered && rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
			{
				imports::ImportHit hit = import_index.hover;
				if (hit.valid && hit.source >= 0 && hit.source < (int)project.cards.len())
				{
					FileCard* src             = &project.cards[hit.source];
					imports::ImportRef[] refs = import_index.imports_for((String)src.path);
					if (hit.ref_index < refs.len)
					{
						imports::ImportRef ref = refs[hit.ref_index];
						navigate_to_location(
							&project,
							&canvas,
							metrics,
							(String)src.path,
							(uint)ref.line,
							(uint)ref.column
						);
						FileCard* focused = project.focused_card();
						if (focused) focused.open = true;
					}
				}
			}

			if (project.pending_reload >= 0 && !reload_menu.open)
			{
				RLVector2 center = {
					(float)rl::get_screen_width() / 2.0f,
					(float)rl::get_screen_height() / 2.0f,
				};
				notifier.push("File changed on disk");
				reload_menu.open_at(center, { "Reload", "Keep" });
			}
			if (project.pending_close >= 0 && !close_menu.open)
			{
				RLVector2 center = {
					(float)rl::get_screen_width() / 2.0f,
					(float)rl::get_screen_height() / 2.0f,
				};
				notifier.push("Unsaved changes");
				close_menu.open_at(center, { "Discard", "Keep" });
			}
		}

		lsp.update(rl::get_time());

		List{lsp::FormattingEdit} formatting_edits = { };
		String formatting_path                     = "";
		if (lsp::lsp_take_formatting(&formatting_edits, &formatting_path))
		{
			if (project.apply_formatting(formatting_path, &formatting_edits, rl::get_time()))
			{
				notifier.push("Formatted");
			}
			else
			{
				notifier.push("Could not apply formatting");
			}
			for (sz i = 0; i < formatting_edits.len(); i++)
			{
				if (formatting_edits[i].new_text.len) formatting_edits[i].new_text.free(project.allocator);
			}
			formatting_edits.free();
			if (formatting_path.len) formatting_path.free(project.allocator);
		}

		FileCard* completion_card = project.focused_card();
		if (completion_card && completion_card.buffer)
		{
			completion::completion_poll(completion_card.buffer, completion_card.cursor);
		}

		lsp.update_hover(rl::get_time(), hover.over && !arrow_hovered, hover.path, hover.table, hover.offset);

		List{lsp::DefinitionTarget} definitions = { };
		if (lsp::lsp_take_definition(&definitions))
		{
			if (definitions.len() == 0)
			{
				notifier.push("No definition found");
				definitions.free();
			}
			else if (definitions.len() == 1)
			{
				lsp::DefinitionTarget target = definitions[0];
				navigate_to_location(&project, &canvas, metrics, target.path, target.line, target.character);
				clear_definitions(&definitions);
				definitions.free();
			}
			else
			{
				clear_definitions(&pending_definitions);
				pending_definitions = definitions;
				definition_menu_kind = 0;
				@pool()
				{
					String[32] labels;
					bool[32] enabled;
					int shown = (int)pending_definitions.len();
					if (shown > 32) shown = 32;
					for (int i = 0; i < shown; i++)
					{
						lsp::DefinitionTarget target = pending_definitions[(sz)i];
						String base                  = rl::get_file_name((ZString)target.path.ptr).str_view();
						labels[i] = string::format(
							tmem,
							"%s:%d:%d",
							base,
							(long)(target.line + 1),
							(long)(target.character + 1)
						);
						enabled[i] = true;
					}
					definition_menu.open_with(rl::get_mouse_position(), labels[0:shown], enabled[0:shown]);
				};
			}
		}

		List{lsp::DefinitionTarget} references = { };
		if (lsp::lsp_take_references(&references))
		{
			if (references.len() == 0)
			{
				notifier.push("No references found");
				references.free();
			}
			else if (references.len() == 1)
			{
				lsp::DefinitionTarget target = references[0];
				navigate_to_location(&project, &canvas, metrics, target.path, target.line, target.character);
				clear_definitions(&references);
				references.free();
			}
			else
			{
				clear_definitions(&pending_definitions);
				pending_definitions = references;
				definition_menu_kind = 0;
				@pool()
				{
					String[32] labels;
					bool[32] enabled;
					int shown = (int)pending_definitions.len();
					if (shown > 32) shown = 32;
					for (int i = 0; i < shown; i++)
					{
						lsp::DefinitionTarget target = pending_definitions[(sz)i];
						String base                  = rl::get_file_name((ZString)target.path.ptr).str_view();
						labels[i] = string::format(
							tmem,
							"%s:%d:%d",
							base,
							(long)(target.line + 1),
							(long)(target.character + 1)
						);
						enabled[i] = true;
					}
					definition_menu.open_with(rl::get_mouse_position(), labels[0:shown], enabled[0:shown]);
				};
			}
		}

		String rename_placeholder = "";
		if (lsp::lsp_take_prepare_rename(&rename_placeholder))
		{
			FileCard* rename_card = project.focused_card();
			if (!rename_card || !rename_card.buffer)
			{
				notifier.push("No file to rename");
			}
			else
			{
				*app.pending_kind = 3;
				app.pending_rename_card = project.focused;
				*app.pending_rename_offset = rename_card.cursor;
				name_prompt.open_with("Rename Symbol", rename_placeholder);
			}
			if (rename_placeholder.len) rename_placeholder.free(mem);
		}

		lsp::WorkspaceEdit rename_edit = { };
		if (lsp::lsp_take_rename(&rename_edit))
		{
			if (project.apply_workspace_edit(&rename_edit, rl::get_time()))
			{
				notifier.push("Renamed");
			}
			else
			{
				notifier.push("Could not apply rename; open all affected files");
			}
			lsp::lsp_workspace_edit_free(&rename_edit, mem);
		}

		List{lsp::CodeActionItem} code_actions = { };
		if (lsp::lsp_take_code_actions(&code_actions))
		{
			if (code_actions.len() == 0)
			{
				notifier.push("No code actions");
				code_actions.free();
			}
			else
			{
				clear_actions(&pending_actions);
				pending_actions = code_actions;
				definition_menu_kind = 1;
				@pool()
				{
					String[32] labels;
					bool[32] enabled;
					int shown = (int)pending_actions.len();
					if (shown > 32) shown = 32;
					for (int i = 0; i < shown; i++)
					{
						labels[i] = pending_actions[(sz)i].title;
						enabled[i] = true;
					}
					definition_menu.open_with(rl::get_mouse_position(), labels[0:shown], enabled[0:shown]);
				};
			}
		}

		String document_path                  = "";
		List{lsp::LspSymbol} document_symbols = { };
		if (lsp::lsp_take_document_symbols(&document_path, &document_symbols))
		{
			symbols.merge_lsp(&document_symbols);
			lsp::lsp_symbols_free(&document_symbols, mem);
			if (document_path.len) document_path.free(mem);
		}

		List{lsp::LspSymbol} workspace_symbols = { };
		if (lsp::lsp_take_workspace_symbols(&workspace_symbols))
		{
			symbols.merge_lsp(&workspace_symbols);
			lsp::lsp_symbols_free(&workspace_symbols, mem);
		}

		String semantic_path                     = "";
		List{lsp::SemanticToken} semantic_tokens = { };
		if (lsp::lsp_take_semantic_tokens(&semantic_path, &semantic_tokens))
		{
			int semantic_index = project.find_card(semantic_path);
			if (semantic_index >= 0)
			{
				FileCard* semantic_card = &project.cards[semantic_index];
				if (semantic_card.highlight && semantic_card.buffer)
				{
					List{highlight::Span} spans;
					spans.init(project.allocator);
					for (sz i = 0; i < semantic_tokens.len(); i++)
					{
						lsp::SemanticToken token   = semantic_tokens.get(i);
						String token_type          = lsp::lsp_semantic_token_type(semantic_path, token.token_type);
						highlight::SyntaxRole role = highlight::role_for_semantic_token(token_type);
						if (role == highlight::SyntaxRole.NONE) continue;
						usz start = lsp::offset_from_position(semantic_card.buffer, token.line, token.character);
						usz end = lsp::offset_from_position(
							semantic_card.buffer,
							token.line,
							token.character + token.length
						);
						if (end > start)
						{
							spans.push({ .start = (uint)start, .end = (uint)end, .role = role });
						}
					}
					semantic_card.highlight.set_semantic_spans(&spans);
				}
			}
			semantic_tokens.free();
			if (semantic_path.len) semantic_path.free(mem);
		}

		FileCard* lsp_card = project.focused_card();
		if (lsp_card && lsp_card.buffer)
		{
			lsp::lsp_update_document_symbols((String)lsp_card.path);
			lsp::lsp_update_semantic_tokens(rl::get_time(), (String)lsp_card.path);
			lsp::lsp_update_signature(rl::get_time(), (String)lsp_card.path, lsp_card.buffer, lsp_card.cursor);
		}

		notifier.update(dt);

		rl::@drawing()
		{
			bool focus_active          = project.focus_card >= 0;
			git::GitStatus* git_status = git_state.has_status ? &git_state.status : null;
			if (focus_active)
			{
				rl::clear_background(theme::current().window_bg);
			}
			else
			{
				canvas.draw();
			}
			double draw_t0 = rl::get_time();
			rl::@mode2d(canvas.camera)
			{
				if (focus_active)
				{
					project.draw_cards(
						canvas.camera,
						font,
						editor_font,
						metrics,
						&find_bar,
						project.focus_card,
						git_status
					);
				}
				else
				{
					project.draw_folders(canvas.camera);
					import_index.draw(&project, canvas.camera, font);
					project.draw_cards(canvas.camera, font, editor_font, metrics, &find_bar, -1, git_status);
				}
			};
			if (focus_active)
			{
				minimap::draw_file(&project, metrics);
			}
			else
			{
				minimap::draw(&project, &canvas);
			}
			draw_ms += (rl::get_time() - draw_t0) * 1000.0;
			if (rl::get_time() < font_indicator_until)
			{
				@pool()
				{
					String label = string::format(tmem, "Font %d", (long)font_size);
					float width  = rl::measure_text_ex(font, label.zstr_tcopy(), (float)ui::tpx(16), 0.0f)[0];
					Rect content = topbar::content_rect();
					Rect panel = {
						.x = content.x + content.width / 2.0f - (width + (float)ui::px(24)) / 2.0f,
						.y = content.y + (float)ui::px(16),
						.width = width + (float)ui::px(24),
						.height = (float)ui::px(30),
					};
					ui::panel(panel, theme::current().panel_bg_alt, theme::current().panel_border);
					rl::draw_text_ex(
						font,
						label.zstr_tcopy(),
						{ panel.x + (float)ui::px(12), panel.y + (float)ui::px(7) },
						(float)ui::tpx(16),
						0.0f,
						theme::current()
						.panel_text);
				};
			}
			if (!problems.open && !palette.open && !opening && !settings_panel.open)
			{
				if (import_index.hover.valid)
				{
					import_index.draw_tooltip(&project, font);
				}
				else if (hover.diagnostic.len > 0)
				{
					problems::draw_tooltip(hover.diagnostic, hover.anchor, font);
				}
				else if (draw_signature_help(&project, &canvas, metrics, font))
				{
				}
				else if (hover.over && lsp.hover_is_valid())
				{
					hover::draw_hover(lsp.hover_message(), hover.anchor, font);
				}
			}
			if (completion::completion_is_open() && !problems.open && !palette.open && !definition_menu.open)
			{
				FileCard* completion_draw_card = project.focused_card();
				if (completion_draw_card && completion_draw_card.buffer)
				{
					completion::completion_draw(
						font,
						metrics,
						canvas.camera,
						completion_draw_card.buffer,
						completion_draw_card.rect,
						completion_draw_card.scroll,
						completion_draw_card.scroll_x,
						completion_draw_card.cursor
					);
				}
			}
			String project_name = "";
			if (project_open) project_name = rl::get_file_name((ZString)project.root.ptr).str_view();
			String mode_label   = "";
			String folder_label = "";
			if (project_open)
			{
				mode_label = "-- MOVE --";
				if (ui_mode == UiMode.EDIT)
				{
					mode_label = "-- EDIT --";
				}
				else if (ui_mode == UiMode.TOP_BAR)
				{
					mode_label = "-- TOP BAR --";
				}
				else if (ui_mode == UiMode.CONSOLE)
				{
					mode_label = "-- CONSOLE --";
				}
				else if (ui_mode == UiMode.SCM)
				{
					mode_label = "-- SOURCE CONTROL --";
				}
				else if (ui_mode == UiMode.DIFF)
				{
					mode_label = "-- DIFF --";
				}
				else if (ui_mode == UiMode.CONFLICT)
				{
					mode_label = "-- CONFLICT --";
				}
				else if (ui_mode == UiMode.HISTORY)
				{
					mode_label = "-- HISTORY --";
				}
				else if (project.grabbing)
				{
					mode_label = "-- GRAB --";
				}
				if (project.current_folder != project::ROOT_FOLDER
					&& project.current_folder < (int)project.folders.len())
				{
					String fp = (String)project.folders[project.current_folder].path;
					folder_label = fp.len > project.root.len + 1 ? fp[project.root.len + 1..] : fp;
				}
			}
			int lsp_errors   = 0;
			int lsp_warnings = 0;
			int lsp_infos    = 0;
			int lsp_hints    = 0;
			lsp::lsp_diagnostic_counts(&lsp_errors, &lsp_warnings, &lsp_infos, &lsp_hints);
			bar.draw(
				project_open,
				has_focused_buffer(&project),
				project_name,
				mode_label,
				folder_label,
				canvas.camera.zoom,
				lsp.status_text(),
				lsp_errors,
				lsp_warnings,
				font,
				ui_mode == UiMode.TOP_BAR
			);
			connections.draw(font, &project, &import_index);
			console = console_manager.active_console();
			console_panel = console_manager.active_panel();
			app.console = console;
			app.console_panel = console_panel;
			console_panel.focused = ui_mode == UiMode.CONSOLE;
			git_panel.draw(&git_state, &canvas, (float)ui::tpx(13));
			console_panel.draw(&console_manager, console, font, editor_font, metrics);
			browser.draw(git_status);
			close_menu.draw();
			delete_menu.draw();
			reload_menu.draw();
			theme_menu.draw();
			profile_menu.draw();
			context_menu.draw();
			name_prompt.draw(font);
			palette.draw(project_open, has_focused_buffer(&project), &keymap, font);
			settings_panel.draw(font, project_open, &keymap, &config);
			problems.draw(font);
			search.draw(font);
			symbols.draw(font);
			definition_menu.draw();
			history_view.draw(&git_state, &canvas);
			diff_view.draw(&canvas);
			conflict_view.draw(&canvas);
			notifier.draw();
			if (opening) draw_loading(open_job, font);
			if (rl::is_key_down(rl::RLKeyboardKey.F3))
			{
				Rect content = topbar::content_rect();
				rl::draw_fps((int)content.x + 10, (int)content.y + 10);
				if (project_open)
				{
					@pool()
					{
						String counter = string::format(
							tmem,
							"editors: %d awake / %d asleep",
							(long)project.awake_count,
							(long)project.asleep_count
						);
						rl::draw_text_ex(
							font,
							counter.zstr_tcopy(),
							{ content.x + (float)ui::px(10), content.y + (float)ui::px(54) },
							(float)ui::tpx(14),
							0.0f,
							theme::current()
							.panel_dim);
						String perf = string::format(
							tmem,
							"frame %.2fms  update %.2f  draw %.2f  scan %.2f",
							prof_frame,
							prof_update,
							prof_draw,
							prof_scan
						);
						rl::draw_text_ex(
							font,
							perf.zstr_tcopy(),
							{ content.x + (float)ui::px(10), content.y + (float)ui::px(74) },
							(float)ui::tpx(14),
							0.0f,
							theme::current()
							.panel_dim);
					};
				}
			}
			ui::draw_tooltip(font);
			visual_suite_tick(&app, &project);
		};
		ui::apply_cursor();
		prof_update += (update_ms - prof_update) * 0.1;
		prof_draw += (draw_ms - prof_draw) * 0.1;
		prof_scan += (scan_ms - prof_scan) * 0.1;
		prof_frame += ((rl::get_time() - frame_start) * 1000.0 - prof_frame) * 0.1;

		if (benchmark_on && !bench_ready && frame_count > 20000)
		{
			io::printn("benchmark: project did not finish opening; aborting");
			break;
		}
		if (bench_ready && frame_count > bench_warmup)
		{
			double ms = (rl::get_time() - frame_start) * 1000.0;
			bench_sum += ms;
			if (ms > bench_max) bench_max = ms;
			if (ms < bench_min) bench_min = ms;
			if (ms > 16.7) bench_over++;
			bench_samples++;
			if (bench_samples >= benchmark_frames)
			{
				double avg = bench_sum / (double)bench_samples;
				io::printfn(
					"benchmark: %d cards | %d folders | %d frames | avg %.2f ms  min %.2f  max %.2f  | over 16.7ms: %d  (%.1f fps)",
					(int)project.cards.len(),
					(int)project.folders.len(),
					(int)bench_samples,
					avg,
					bench_min,
					bench_max,
					(int)bench_over,
					1000.0 / avg
				);
				break;
			}
		}
	}

	if (project.focus_card >= 0) project.end_focus(&canvas);
	if (project_open)
	{
		if (import_index.cache_dirty) import_index.save_cache(&project);
		if (symbols.cache_dirty) symbols.save_cache(&project);
		workspace::save(&project, &canvas, &console_manager);
	}
	return 0;
}