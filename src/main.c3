module yun;

import raylib6::rl;
import std::collections::list;
import std::io::path;
import std::math;
import yun::browser;
import yun::canvas;
import yun::card;
import yun::commands;
import yun::completion;
import yun::config;
import yun::context;
import yun::editor;
import yun::find;
import yun::findbar;
import yun::hover;
import yun::imports;
import yun::keymap;
import yun::lsp;
import yun::menu;
import yun::minimap;
import yun::notify;
import yun::palette;
import yun::problems;
import yun::project;
import yun::prompt;
import yun::search;
import yun::symbols;
import yun::theme;
import yun::topbar;
import yun::workspace;

enum UiMode : int
{
	MOVE,
	EDIT,
	TOP_BAR,
}

fn void set_project_title(project::Project* project)
{
	String name  = rl::get_file_name((ZString)project.root.ptr).str_view();
	String title = string::format(project.allocator, "Yun - %s", name);
	rl::set_window_title((ZString)title.ptr);
}

fn void finish_open(
	project::Project* project,
	canvas::Canvas* canvas,
	config::Config* config,
	keymap::Keymap* keymap,
	notify::Notifier* notifier
)
{
	workspace::load(project, canvas);
	config.load((String)project.root);
	apply_config_theme(config, notifier);
	set_project_title(project);
	keymap.build(config);
	push_config_warnings(config, notifier);
	push_keymap_warnings(keymap, notifier);
}

fn void apply_config_theme(config::Config* config, notify::Notifier* notifier)
{
	if (!theme::set_by_name(config.theme))
	{
		notifier.push("Unknown theme in config; using default");
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
	rl::draw_rectangle_rec(panel, theme::current().loading_panel);
	rl::draw_rectangle_lines_ex(panel, 1.0f, theme::current().loading_border);

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
		rl::draw_text_ex(font, title.zstr_tcopy(), { panel.x + 20.0f, panel.y + 20.0f }, 18.0f, 0.0f, theme::current()
			.loading_title);
		rl::draw_text_ex(font, status.zstr_tcopy(), { panel.x + 20.0f, panel.y + 48.0f }, 14.0f, 0.0f, theme::current()
			.loading_status);
		if (job.phase == project::OpenPhase.SCAN)
		{
			rl::draw_text_ex(font, "Esc to cancel", { panel.x + 20.0f, panel.y + 70.0f }, 14.0f, 0.0f, theme::current()
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
	browser::Browser* browser;
	notify::Notifier* notifier;
	prompt::Prompt* name_prompt;
	palette::Palette* palette;
	findbar::FindBar* find_bar;
	problems::Problems* problems;
	menu::Menu* theme_menu;
	search::Search* search;
	symbols::Symbols* symbols;
	editor::EditorMetrics metrics;
	bool* project_open;
	int* pending_kind;
	int* pending_parent;
	RLVector2* pending_world;
}

fn bool has_focused_buffer(project::Project* project)
{
	int index = project.focused;
	return index >= 0 && index < (int)project.cards.len() && project.cards[index].buffer != null;
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
		case commands::CommandId.SELECT_THEME:

			{
				RLVector2 center = {
					(float)rl::get_screen_width() / 2.0f,
					(float)rl::get_screen_height() / 2.0f,
				};
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
				app.symbols.show();
				while (rl::get_char_pressed() != 0)
				{
				}
				return;
			}
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
	if (canvas.target.zoom < JUMP_ZOOM_MIN) canvas.target.zoom = JUMP_ZOOM_TARGET;
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
	card.scroll_x = editor::scroll_x_to_reveal(card.buffer, metrics, text.width, card.cursor, card.scroll_x);
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
			metrics
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
	Rect caret  = editor::caret_rect(card.buffer, text, card.scroll, card.scroll_x, metrics, card.cursor);
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
	project.reveal_focused(metrics);
	find_bar.mark_dirty();
}

const String FONT_PATH       = "assets/fonts/JetBrainsMono-Regular.ttf";
const float JUMP_ZOOM_MIN    = 0.6f;
const float JUMP_ZOOM_TARGET = 1.0f;

fn void reload_editor_font(RLFont* font, int size, editor::EditorMetrics* metrics)
{
	rl::unload_font(*font);
	*font = rl::load_font_ex(FONT_PATH, size, null, 0);
	*metrics = editor::metrics_for_font(*font, (float)size);
	editor::set_font_size((float)size);
}

fn int main(String[] args)
{
	rl::set_config_flags((RLConfigFlag)(rl::RLConfigFlag.WINDOW_RESIZABLE | rl::RLConfigFlag.VSYNC_HINT));
	rl::init_window(1280, 720, "Yun");
	defer rl::close_window();
	rl::set_target_fps(60);
	rl::set_exit_key(rl::RLKeyboardKey.NONE);

	RLFont font = rl::load_font_ex(FONT_PATH, 16, null, 0);
	defer rl::unload_font(font);

	int font_size                 = editor::FONT_SIZE_DEFAULT;
	RLFont editor_font            = rl::load_font_ex(FONT_PATH, font_size, null, 0);
	editor::EditorMetrics metrics = editor::metrics_for_font(editor_font, (float)font_size);
	editor::set_font_size((float)font_size);

	canvas::Canvas canvas;
	canvas.init();
	canvas.top_inset = topbar::TOP_BAR_HEIGHT;

	project::Project project;
	project.init(mem);

	notify::Notifier notifier;
	notifier.init(mem);

	config::Config config;
	config.init(mem);
	defer config.destroy();

	lsp::Lsp lsp;
	lsp.init(mem, &config);
	lsp::lsp_set_active(&lsp);
	completion::completion_init(mem);
	imports::ImportIndex import_index;
	import_index.init(mem);
	defer import_index.destroy();

	browser::Browser browser;
	browser.init(mem);

	menu::Menu context_menu;
	context_menu.init(mem);

	menu::Menu reload_menu;
	reload_menu.init(mem);

	menu::Menu theme_menu;
	theme_menu.init(mem);

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

	search::Search search;
	search.init(mem);
	defer search.destroy();

	symbols::Symbols symbols;
	symbols.init(mem);
	defer symbols.destroy();

	keymap::Keymap keymap;
	keymap.init(mem);
	defer keymap.destroy();

	int pending_kind        = 0;
	int pending_parent      = project::ROOT_FOLDER;
	RLVector2 pending_world = { 0.0f, 0.0f };

	context::ContextItem[context::CONTEXT_MAX_ITEMS] context_items;
	usz context_item_count  =  0;
	int context_card        = -1;
	int context_parent      =  project::ROOT_FOLDER;
	RLVector2 context_world =  { 0.0f, 0.0f };
	int context_offset      = -1;
	int pending_rename_card = -1;
	int pending_delete_card = -1;

	menu::Menu definition_menu;
	definition_menu.init(mem);
	List{lsp::DefinitionTarget} pending_definitions;
	pending_definitions.init(mem);

	bool project_open           = false;
	project::OpenJob* open_job  = null;
	bool opening                = false;
	int pending_font_size       = 0;
	double font_indicator_until = 0.0;
	bool font_save_pending      = false;
	UiMode ui_mode              = UiMode.MOVE;
	if (args.len > 1)
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
			open_job = project::open_job_create(project.allocator, &project, resolved);
			opening = true;
		}
	}
	else
	{
		config.load("");
		apply_config_theme(&config, &notifier);
		pending_font_size = editor::clamp_font_size(config.font_size);
	}
	keymap.build(&config);
	push_config_warnings(&config, &notifier);
	push_keymap_warnings(&keymap, &notifier);

	App app = {
		.project = &project,
		.canvas = &canvas,
		.browser = &browser,
		.notifier = &notifier,
		.name_prompt = &name_prompt,
		.palette = &palette,
		.find_bar = &find_bar,
		.problems = &problems,
		.theme_menu = &theme_menu,
		.search = &search,
		.symbols = &symbols,
		.metrics = metrics,
		.project_open = &project_open,
		.pending_kind = &pending_kind,
		.pending_parent = &pending_parent,
		.pending_world = &pending_world,
	};

	while (!rl::window_should_close())
	{
		float dt           = math::min(rl::get_frame_time(), canvas::MAX_FRAME_DT);
		HoverInfo hover    = { };
		bool arrow_hovered = false;
		import_index.clear_hover();
		search.pump(&project, rl::get_time());
		symbols.pump(&project, rl::get_time());

		if (pending_font_size > 0)
		{
			font_size = editor::clamp_font_size(pending_font_size);
			reload_editor_font(&editor_font, font_size, &metrics);
			pending_font_size = 0;
		}
		if (font_save_pending && !project::ctrl_down())
		{
			config.font_size = font_size;
			config.save_global();
			font_save_pending = false;
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
					finish_open(&project, &canvas, &config, &keymap, &notifier);
					search.close();
					symbols.close();
					symbols.start_scan(&project);
					ui_mode = UiMode.MOVE;
					project.selected = -1;
					pending_font_size = editor::clamp_font_size(config.font_size);
					lsp.set_root((String)project.root);
					completion::completion_close();
					import_index.start_scan(&project);
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
			if (browser.update())
			{
				search.close();
				symbols.close();
				ui_mode = UiMode.MOVE;
				project.selected = -1;
				open_job = project::open_job_create(project.allocator, &project, (String)browser.dir);
				opening = true;
			}
		}
		else if (palette.open)
		{
			int chosen = palette.update(project_open, has_focused_buffer(&project));
			if (chosen >= 0)
			{
				palette.record((commands::CommandId)chosen);
				run_command((commands::CommandId)chosen, &app);
			}
		}
		else if (problems.open)
		{
			int chosen = problems.update();
			if (chosen >= 0)
			{
				problems::ProblemEntry* entry = problems.entry_at(chosen);
				if (entry)
				{
					navigate_to_location(&project, &canvas, metrics, entry.path, entry.line, entry.character);
				}
			}
		}
		else if (definition_menu.open)
		{
			int chosen = definition_menu.update();
			if (chosen >= 0 && chosen < (int)pending_definitions.len())
			{
				lsp::DefinitionTarget target = pending_definitions[(sz)chosen];
				navigate_to_location(&project, &canvas, metrics, target.path, target.line, target.character);
			}
			if (!definition_menu.open)
			{
				clear_definitions(&pending_definitions);
			}
		}
		else if (name_prompt.open)
		{
			if (name_prompt.update())
			{
				String name = name_prompt.text_view();
				if (!project::is_valid_name(name))
				{
					notifier.push("Invalid name");
				}
				else if (pending_kind == 2)
				{
					if (project.rename_card(pending_rename_card, name))
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
						name_prompt.close();
					}
				}
			}
		}
		else if (close_menu.open)
		{
			int chosen = close_menu.update();
			if (chosen >= 0)
			{
				int index = project.pending_close;
				if (chosen == 0 && index >= 0 && index < (int)project.cards.len())
				{
					(void)editor::unload_buffer(&project.cards[index], project.allocator);
				}
				project.pending_close = -1;
			}
		}
		else if (delete_menu.open)
		{
			int chosen = delete_menu.update();
			if (chosen >= 0)
			{
				if (chosen == 0 && pending_delete_card >= 0 && pending_delete_card < (int)project.cards.len())
				{
					if (project.delete_card_file(pending_delete_card))
					{
						notifier.push("Deleted");
					}
					else
					{
						notifier.push("Could not delete");
					}
				}
				pending_delete_card = -1;
			}
		}
		else if (reload_menu.open)
		{
			int chosen = reload_menu.update();
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
		}
		else if (theme_menu.open)
		{
			int chosen = theme_menu.update();
			if (chosen >= 0)
			{
				theme::set_index(chosen);
				config.set_theme(theme::name(chosen));
				config.save_global();
				@pool()
				{
					notifier.push(string::format(tmem, "Theme: %s", theme::label(chosen)));
				};
			}
		}
		else if (context_menu.open)
		{
			int chosen = context_menu.update();
			if (chosen >= 0 && chosen < (int)context_item_count)
			{
				context::ContextAction action = context_items[chosen].action;
				switch (action)
				{
					case context::ContextAction.NEW_FILE:
					case context::ContextAction.NEW_FOLDER:

						{
							pending_kind = action == context::ContextAction.NEW_FILE ? 0 : 1;
							pending_parent = context_parent;
							pending_world = context_world;
							name_prompt.open_with(pending_kind == 0 ? "New file" : "New folder", "");
							break;
						}
					case context::ContextAction.OPEN_PROJECT:
						run_command(commands::CommandId.OPEN, &app);
						break;
					case context::ContextAction.TOGGLE_CARD:

						{
							if (context_card >= 0 && context_card < (int)project.cards.len())
							{
								project.cards[context_card].open = !project.cards[context_card].open;
							}
							break;
						}
					case context::ContextAction.RENAME_CARD:

						{
							if (context_card >= 0 && context_card < (int)project.cards.len())
							{
								pending_rename_card = context_card;
								pending_kind = 2;
								name_prompt.open_with("Rename", project.cards[context_card].name);
							}
							break;
						}
					case context::ContextAction.DUPLICATE_CARD:

						{
							if (project.duplicate_card(context_card, context_world) < 0)
							{
								notifier.push("Could not duplicate");
							}
							else
							{
								notifier.push("Duplicated");
							}
							break;
						}
					case context::ContextAction.COPY_PATH:

						{
							if (context_card >= 0 && context_card < (int)project.cards.len())
							{
								@pool()
								{
									rl::set_clipboard_text(((String)project.cards[context_card].path).zstr_tcopy());
								};
								notifier.push("Path copied");
							}
							break;
						}
					case context::ContextAction.DELETE_CARD:

						{
							if (context_card >= 0 && context_card < (int)project.cards.len())
							{
								pending_delete_card = context_card;
								RLVector2 center = {
									(float)rl::get_screen_width() / 2.0f,
									(float)rl::get_screen_height() / 2.0f,
								};
								delete_menu.open_at(center, { "Delete", "Cancel" });
							}
							break;
						}
					case context::ContextAction.GO_TO_DEFINITION:

						{
							if (context_card >= 0 && context_card < (int)project.cards.len() && context_offset >= 0)
							{
								int index    = project.focus(context_card);
								FileCard* cc = &project.cards[index];
								editor::ensure_buffer(cc, project.allocator);
								if (cc.buffer)
								{
									cc.cursor = (usz)context_offset;
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
				}
			}
		}
		else if (search.open)
		{
			search::SearchTarget target = search.update(&project, rl::get_time());
			if (target.valid)
			{
				search.close();
				navigate_to_location(&project, &canvas, metrics, target.path, (uint)target.line, (uint)target.column);
			}
		}
		else if (symbols.open)
		{
			symbols::SymbolTarget target = symbols.update(&project, rl::get_time());
			if (target.valid)
			{
				symbols.close();
				navigate_to_location(&project, &canvas, metrics, target.path, (uint)target.line, (uint)target.column);
			}
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
							card.scroll_x
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
		}
		else
		{
			RLVector2 mouse = rl::get_mouse_position();
			RLVector2 world = canvas.screen_to_world(mouse);
			bool over_top   = topbar::contains_screen(mouse);
			bool has_buffer = has_focused_buffer(&project);

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
						float old_lh = metrics.line_height;
						float old_cw = metrics.char_width;
						font_size = next;
						reload_editor_font(&editor_font, font_size, &metrics);
						float lh_ratio = old_lh > 0.0f ? metrics.line_height / old_lh : 1.0f;
						float cw_ratio = old_cw > 0.0f ? metrics.char_width / old_cw : 1.0f;
						for (sz i = 0; i < project.cards.len(); i++)
						{
							project.cards[i].scroll *= lh_ratio;
							project.cards[i].scroll_x *= cw_ratio;
						}
						project.reveal_focused(metrics);
						font_indicator_until = rl::get_time() + 1.2;
						font_save_pending = true;
					}
					font_wheel = true;
				}
			}

			int key_cmd = keymap.poll();
			if (key_cmd >= 0) run_command((commands::CommandId)key_cmd, &app);

			int bar_cmd = bar.update(mouse, project_open, has_buffer);
			if (bar_cmd >= 0) run_command((commands::CommandId)bar_cmd, &app);

			if (rl::is_key_pressed(rl::RLKeyboardKey.TAB))
			{
				if (ui_mode == UiMode.TOP_BAR)
				{
					ui_mode = UiMode.MOVE;
				}
				else if (ui_mode == UiMode.MOVE)
				{
					bar.clamp_selection(project_open, has_buffer);
					ui_mode = UiMode.TOP_BAR;
				}
			}

			if (ui_mode == UiMode.TOP_BAR)
			{
				if (rl::is_key_pressed(
					rl::RLKeyboardKey.RIGHT
				) || rl::is_key_pressed_repeat(
					rl::RLKeyboardKey.RIGHT
				)) bar.move_selection(1, project_open, has_buffer);
				if (rl::is_key_pressed(
					rl::RLKeyboardKey.LEFT
				) || rl::is_key_pressed_repeat(
					rl::RLKeyboardKey.LEFT
				)) bar.move_selection(-1, project_open, has_buffer);
				if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER) || rl::is_key_pressed(rl::RLKeyboardKey.SPACE))
				{
					int id = bar.activate(project_open, has_buffer);
					if (id >= 0) run_command((commands::CommandId)id, &app);
				}
				if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE)) ui_mode = UiMode.MOVE;
			}
			else if (ui_mode == UiMode.MOVE)
			{
				int before = project.selected;
				project.ensure_selection();

				if (project::ctrl_down())
				{
					float step = 48.0f;
					if (rl::is_key_pressed(
						rl::RLKeyboardKey.L
					) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.L)) canvas.key_pan({ step, 0.0f });
					if (rl::is_key_pressed(
						rl::RLKeyboardKey.H
					) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.H)) canvas.key_pan({ -step, 0.0f });
					if (rl::is_key_pressed(
						rl::RLKeyboardKey.J
					) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.J)) canvas.key_pan({ 0.0f, step });
					if (rl::is_key_pressed(
						rl::RLKeyboardKey.K
					) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.K)) canvas.key_pan({ 0.0f, -step });
				}
				else
				{
					int direction = -1;
					if (rl::is_key_pressed(
						rl::RLKeyboardKey.H
					) || rl::is_key_pressed(rl::RLKeyboardKey.LEFT)) direction = (int)project::Dir.LEFT;
					if (rl::is_key_pressed(
						rl::RLKeyboardKey.J
					) || rl::is_key_pressed(rl::RLKeyboardKey.DOWN)) direction = (int)project::Dir.DOWN;
					if (rl::is_key_pressed(
						rl::RLKeyboardKey.K
					) || rl::is_key_pressed(rl::RLKeyboardKey.UP)) direction = (int)project::Dir.UP;
					if (rl::is_key_pressed(
						rl::RLKeyboardKey.L
					) || rl::is_key_pressed(rl::RLKeyboardKey.RIGHT)) direction = (int)project::Dir.RIGHT;

					if (direction >= 0)
					{
						int idx = project.card_in_direction(project.selected, (project::Dir)direction);
						if (idx >= 0) project.selected = idx;
					}
					else
					{
						int cycle = 0;
						if (rl::is_key_pressed(rl::RLKeyboardKey.RIGHT_BRACKET)) cycle = 1;
						if (rl::is_key_pressed(rl::RLKeyboardKey.LEFT_BRACKET)) cycle = -1;
						if (cycle != 0)
						{
							int idx = project.next_visible_card(project.selected, cycle);
							if (idx >= 0) project.selected = idx;
						}
					}
				}

				if (rl::is_key_pressed(
					rl::RLKeyboardKey.EQUAL
				) || rl::is_key_pressed(rl::RLKeyboardKey.KP_ADD)) canvas.key_zoom(1.0f);
				if (rl::is_key_pressed(
					rl::RLKeyboardKey.MINUS
				) || rl::is_key_pressed(rl::RLKeyboardKey.KP_SUBTRACT)) canvas.key_zoom(-1.0f);

				bool selection_changed  = project.selected != before;
				FileCard* selected_card = project.selected_card();
				if (selection_changed && selected_card)
				{
					Rect view = project::visible_world_rect(canvas.camera);
					if (!project::rect_intersects(selected_card.rect, view))
					{
						canvas.target.target = selected_card.center();
					}
				}

				if ((rl::is_key_pressed(
					rl::RLKeyboardKey.ENTER
				) || rl::is_key_pressed(rl::RLKeyboardKey.I)) && project.selected >= 0)
				{
					int idx = project.focus(project.selected);
					project.selected = idx;
					if (idx >= 0 && idx < (int)project.cards.len())
					{
						editor::ensure_buffer(&project.cards[idx], project.allocator);
						project.reveal_focused(metrics);
						ui_mode = UiMode.EDIT;
					}
				}
			}

			bool over_minimap = minimap::contains_screen(&project, &canvas, mouse);
			if (!over_top && !over_minimap && project.hit_test(world) < 0)
			{
				arrow_hovered = import_index.hit_test(&project, canvas.camera, world, imports::ARROW_HIT_PX);
			}
			else
			{
				import_index.clear_hover();
			}
			canvas.pointer_over_ui = over_top || project.pointer_over_ui(world) || over_minimap || arrow_hovered;
			minimap::update(&project, &canvas);

			if (!over_top && rl::is_mouse_button_pressed(
				rl::RLMouseButton.RIGHT
			) && !minimap::contains_screen(&project, &canvas, mouse))
			{
				int card   = project.hit_test(world);
				int folder = project.cluster_hit(world);
				context_card = card;
				context_parent = folder;
				context_world = world;

				context::ContextTarget target = context::ContextTarget.CANVAS;
				if (card >= 0)
				{
					target = context::ContextTarget.CARD;
				}
				else if (folder >= 0)
				{
					target = context::ContextTarget.CLUSTER;
				}

				bool card_open    = card >= 0 && project.cards[card].open;
				bool card_missing = card >= 0 && project.cards[card].missing;
				context_offset = -1;
				if (card >= 0 && project.cards[card].open && project.cards[card].buffer)
				{
					FileCard* cc = &project.cards[card];
					Rect text    = editor::text_rect(cc.rect, metrics, cc.buffer.line_count());
					if (world[0] >= text.x && world[0] <= text.x + text.width && world[1] >= text.y
						&& world[1] <= text.y + text.height)
					{
						context_offset = (int)editor::offset_for_point(
							cc.buffer,
							world[0] - text.x,
							world[1] - text.y,
							cc.scroll,
							cc.scroll_x,
							metrics
						);
					}
				}
				bool can_define = context_offset >= 0;
				context_item_count = context::build(
					target,
					card_open,
					card_missing,
					project_open,
					can_define,
					context_items[0:context::CONTEXT_MAX_ITEMS]
				);

				String[context::CONTEXT_MAX_ITEMS] labels;
				bool[context::CONTEXT_MAX_ITEMS] enabled;
				for (usz i = 0; i < context_item_count; i++)
				{
					labels[i] = context_items[i].label;
					enabled[i] = context_items[i].enabled;
				}
				context_menu.open_with(mouse, labels[0:context_item_count], enabled[0:context_item_count]);
			}

			if (!over_top && rl::is_file_dropped())
			{
				RLFilePathList files = rl::load_dropped_files();
				for (uint i = 0; i < files.count; i++)
				{
					String path = files.paths[i].str_view().copy(mem);
					if (!rl::is_path_file(files.paths[i]))
					{
						if (project.add_folder_from_disk(path, world) < 0)
						{
							notifier.push("Drop folders from inside the project root");
						}
						continue;
					}
					if (project.add_card(path, world) < 0)
					{
						notifier.push("Could not add dropped file");
					}
				}
				rl::unload_dropped_files(files);
			}

			bool content_changed = false;
			project.update(&canvas, metrics, over_top || font_wheel, &content_changed);
			if (ui_mode == UiMode.EDIT && project.focused < 0)
			{
				ui_mode = UiMode.MOVE;
			}
			else if (ui_mode == UiMode.MOVE && project.focused >= 0)
			{
				project.selected = project.focused;
				ui_mode = UiMode.EDIT;
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
			imports::ImportIndex.pump(&import_index, &project);
			if (over_top || font_wheel) canvas.block_zoom = true;
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
				pending_definitions.free();
				pending_definitions = definitions;
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
		notifier.update(dt);

		rl::@drawing()
		{
			canvas.draw();
			rl::@mode2d(canvas.camera)
			{
				project.draw_folders(canvas.camera);
				import_index.draw(&project, canvas.camera, editor_font);
				project.draw_cards(canvas.camera, font, editor_font, metrics, &find_bar);
			};
			minimap::draw(&project, &canvas);
			if (rl::get_time() < font_indicator_until)
			{
				@pool()
				{
					String label = string::format(tmem, "Font %d", (long)font_size);
					float width  = rl::measure_text_ex(font, label.zstr_tcopy(), 16.0f, 0.0f)[0];
					Rect panel = {
						.x = (float)rl::get_screen_width() / 2.0f - (width + 24.0f) / 2.0f,
						.y = topbar::TOP_BAR_HEIGHT + 16.0f,
						.width = width + 24.0f,
						.height = 30.0f,
					};
					rl::draw_rectangle_rec(panel, theme::current().panel_bg_alt);
					rl::draw_rectangle_lines_ex(panel, 1.0f, theme::current().panel_border);
					rl::draw_text_ex(
						font,
						label.zstr_tcopy(),
						{ panel.x + 12.0f, panel.y + 7.0f },
						16.0f,
						0.0f,
						theme::current()
						.panel_text);
				};
			}
			if (!problems.open && !palette.open && !opening)
			{
				if (import_index.hover.valid)
				{
					import_index.draw_tooltip(&project, editor_font);
				}
				else if (hover.diagnostic.len > 0)
				{
					problems::draw_tooltip(hover.diagnostic, hover.anchor, editor_font);
				}
				else if (hover.over && lsp.hover_is_valid())
				{
					hover::draw_hover(lsp.hover_message(), hover.anchor, editor_font);
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
			int lsp_errors   = 0;
			int lsp_warnings = 0;
			int lsp_infos    = 0;
			int lsp_hints    = 0;
			lsp::lsp_diagnostic_counts(&lsp_errors, &lsp_warnings, &lsp_infos, &lsp_hints);
			bar.draw(
				project_open,
				has_focused_buffer(&project),
				project_name,
				canvas.camera.zoom,
				lsp.status_text(),
				lsp_errors,
				lsp_warnings,
				font,
				ui_mode == UiMode.TOP_BAR
			);
			browser.draw();
			close_menu.draw();
			delete_menu.draw();
			reload_menu.draw();
			theme_menu.draw();
			context_menu.draw();
			name_prompt.draw();
			palette.draw(project_open, has_focused_buffer(&project), &keymap, font);
			problems.draw(editor_font);
			search.draw(editor_font);
			symbols.draw(editor_font);
			definition_menu.draw();
			notifier.draw();
			if (opening) draw_loading(open_job, font);
			rl::draw_fps(10, (int)topbar::TOP_BAR_HEIGHT + 10);
			if (project_open)
			{
				String mode_label = "-- MOVE --";
				if (ui_mode == UiMode.EDIT)
				{
					mode_label = "-- EDIT --";
				}
				else if (ui_mode == UiMode.TOP_BAR)
				{
					mode_label = "-- TOP BAR --";
				}
				rl::draw_text_ex(
					font,
					(ZString)mode_label.ptr,
					{ 10.0f, (float)topbar::TOP_BAR_HEIGHT + 34.0f },
					15.0f,
					0.0f,
					theme::current()
					.topbar_name);
			}
			if (project_open && rl::is_key_down(rl::RLKeyboardKey.F3))
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
						{ 10.0f, (float)topbar::TOP_BAR_HEIGHT + 54.0f },
						14.0f,
						0.0f,
						theme::current()
						.panel_dim);
				};
			}
		};
	}

	if (project_open) workspace::save(&project, &canvas);
	lsp.shutdown_all();
	rl::unload_font(editor_font);
	return 0;
}