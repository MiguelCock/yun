module yun::workspace;

import libc;
import std::collections::list;
import std::encoding::json;
import std::io::file;
import std::io::path;
import std::math;
import yun::canvas;
import yun::card;
import yun::console;
import yun::project;
import yun::ui;

const String WORKSPACE_VERSION = "5";
const String WORKSPACE_DIR     = ".yun";
const String WORKSPACE_FILE    = "workspace.json";
const String WORKSPACE_TMP     = "workspace.tmp";
bool g_migrated;

struct CameraState
{
	float target_x;
	float target_y;
	float zoom;
}

struct CardState
{
	String path;
	float x;
	float y;
	float w;
	float h;
	bool open;
	bool preview;
}

struct FolderState
{
	String path;
	bool collapsed;
	float x;
	float y;
	float w;
	float h;
}

struct ConsoleSessionState
{
	String title;
	String[] history;
}

struct ConsoleState
{
	bool visible;
	float height;
	int active;
	ConsoleSessionState[] sessions;
}

struct WorkspaceState
{
	String version;
	CameraState camera;
	CardState[] cards;
	FolderState[] folders;
	ConsoleState console;
}

fn String relative_path(Allocator allocator, String root, String abs)
{
	if (!project::path_is_inside(root, abs)) return abs.copy(allocator);
	if (abs.len <= root.len) return "".copy(allocator);
	return abs[root.len + 1..].copy(allocator);
}

fn Path? absolute_path(Allocator allocator, String root, String rel)
{
	if (rel.len == 0) return (Path)root.copy(allocator);
	return ((Path)root).append(allocator, rel);
}

fn bool save(project::Project* project, canvas::Canvas* canvas, console::ConsoleManager* console_manager = null)
{
	if (project.root.len == 0) return false;
	@pool()
	{
		Path? dir = ((Path)(String)project.root).append(tmem, WORKSPACE_DIR);
		if (catch excuse = dir) return false;
		return save_at(project, canvas, console_manager, dir);
	};
}

fn bool save_at(project::Project* project, canvas::Canvas* canvas, console::ConsoleManager* console_manager, Path dir)
{
	if (project.root.len == 0) return false;

	@pool()
	{
		WorkspaceState state;
		state.version = WORKSPACE_VERSION;
		state.camera = {
			.target_x = canvas.camera.target[0],
			.target_y = canvas.camera.target[1],
			.zoom = canvas.camera.zoom,
		};

		List{CardState} cards;
		cards.init(tmem);
		for (sz i = 0; i < project.cards.len(); i++)
		{
			FileCard card = project.cards[i];
			cards.push(
				{
					.path = relative_path(tmem, (String)project.root, (String)card.path),
					.x = card.rect.x,
					.y = card.rect.y,
					.w = card.rect.width,
					.h = card.rect.height,
					.open = card.open,
					.preview = card.preview,
				}
			);
		}
		state.cards = cards.entries[0:cards.len()];

		List{FolderState} folders;
		folders.init(tmem);
		for (sz i = 0; i < project.folders.len(); i++)
		{
			Rect body = project.folders[i].body;
			folders.push(
				{
					.path = relative_path(tmem, (String)project.root, (String)project.folders[i].path),
					.collapsed = project.folders[i].collapsed,
					.x = body.x,
					.y = body.y,
					.w = body.width,
					.h = body.height,
				}
			);
		}
		state.folders = folders.entries[0:folders.len()];

		ConsoleState console_state;
		console_state.visible = false;
		console_state.height = 220.0f;
		console_state.active = 0;
		console_state.sessions = alloc::new_array(tmem, ConsoleSessionState, 0);
		if (console_manager && console_manager.sessions.len() > 0)
		{
			console_state.visible = console_manager.visible;
			console_state.height = console_manager.height;
			console_state.active = console_manager.active;
			bool restore_sessions = console::settings().restore_sessions;
			bool persist_history  = console::settings().persist_history;
			if (restore_sessions)
			{
				ConsoleSessionState[] sessions = alloc::new_array(
					tmem,
					ConsoleSessionState,
					(usz)console_manager.sessions.len()
				);
				for (sz i = 0; i < console_manager.sessions.len(); i++)
				{
					ConsoleSession* session = console_manager.sessions[i];
					usz history_count       = persist_history ? (usz)session.console.history.entries.len() : 0;
					String[] history        = alloc::new_array(tmem, String, (sz)history_count);
					for (usz h = 0; h < history_count; h++)
					{
						history[h] = session.console.history.entries[(sz)h];
					}
					sessions[(usz)i] = { .title = session.title, .history = history };
				}
				console_state.sessions = sessions;
			}
		}
		state.console = console_state;

		String json = json::marshal(tmem, state, JsonIndent.SPACE_2);

		if (catch excuse = path::mkdir(dir, recursive: true)) return false;

		Path? tmp = dir.append(tmem, WORKSPACE_TMP);
		if (catch excuse = tmp) return false;
		Path? target = dir.append(tmem, WORKSPACE_FILE);
		if (catch excuse = target) return false;

		if (catch excuse = file::save(tmp, json.ptr[0:json.len])) return false;
		if (libc::rename((ZString)tmp.ptr, (ZString)target.ptr) != 0) return false;
	};
	return true;
}

fn bool migrated()
{
	return g_migrated;
}

fn bool load(project::Project* project, canvas::Canvas* canvas, console::ConsoleManager* console_manager = null)
{
	if (project.root.len == 0) return false;
	@pool()
	{
		Path? dir = ((Path)(String)project.root).append(tmem, WORKSPACE_DIR);
		if (catch excuse = dir) return false;
		return load_at(project, canvas, console_manager, dir);
	};
}

fn bool load_at(project::Project* project, canvas::Canvas* canvas, console::ConsoleManager* console_manager, Path dir)
{
	g_migrated = false;
	if (project.root.len == 0) return false;
	@pool()
	{
		Path? file_path = dir.append(tmem, WORKSPACE_FILE);
		if (catch excuse = file_path) return false;
		if (!path::exists(file_path)) return false;

		char[]? data = file::load(tmem, file_path);
		if (catch excuse = data) return false;

		WorkspaceState? parsed = json::unmarshal(tmem, (String)data, WorkspaceState);
		if (catch excuse = parsed) return false;
		WorkspaceState state = parsed;
		if (state.version.compare_to(
			"3"
		) != 0 && state.version.compare_to("4") != 0 && state.version.compare_to(WORKSPACE_VERSION) != 0) return false;

		for (usz i = 0; i < state.cards.len; i++)
		{
			Path? abs = absolute_path(tmem, (String)project.root, state.cards[i].path);
			if (catch excuse = abs) continue;
			int index = project.find_card((String)abs);
			if (index < 0) continue;
			project.cards[index].rect = {
				.x = state.cards[i].x,
				.y = state.cards[i].y,
				.width = state.cards[i].w,
				.height = state.cards[i].h,
			};
			project.cards[index].open = state.cards[i].open;
			project.cards[index].preview = state.cards[i].preview;
			project.cards[index].restored = true;
		}

		bool body_version = state.version.compare_to(WORKSPACE_VERSION) == 0;
		for (usz i = 0; i < state.folders.len; i++)
		{
			Path? abs = absolute_path(tmem, (String)project.root, state.folders[i].path);
			if (catch excuse = abs) continue;
			int index = project.folder_by_path((String)abs);
			if (index >= 0)
			{
				project.folders[index].collapsed = state.folders[i].collapsed;
				project.folders[index].body = {
					.x = state.folders[i].x,
					.y = state.folders[i].y,
					.width = body_version && state.folders[i].w > 0.0f ? state.folders[i].w
						: ui::pxf(project::CLUSTER_COLLAPSED_WIDTH),
					.height = body_version && state.folders[i].h > 0.0f ? state.folders[i].h
						: ui::pxf(project::CLUSTER_COLLAPSED_BODY),
				};
				project.folders[index].bounds_valid = false;
			}
		}

		canvas.camera.target = { state.camera.target_x, state.camera.target_y };
		canvas.camera.zoom = state.camera.zoom;
		canvas.target.target = canvas.camera.target;
		canvas.target.zoom = canvas.camera.zoom;

		if (console_manager && state.version.compare_to(WORKSPACE_VERSION) == 0)
		{
			bool restore_sessions = console::settings().restore_sessions;
			bool persist_history  = console::settings().persist_history;
			console_manager.clear_sessions();
			if (!restore_sessions || state.console.sessions.len == 0)
			{
				(void)console_manager.add_session();
			}
			else
			{
				for (usz i = 0; i < state.console.sessions.len; i++)
				{
					ConsoleSessionState session_state = state.console.sessions[i];
					int index                         = console_manager.add_session_named(session_state.title);
					Console* restored                 = &console_manager.sessions[index].console;
					if (persist_history)
					{
						for (usz h = 0; h < session_state.history.len; h++)
						{
							restored.history.add(session_state.history[h]);
						}
					}
				}
			}
			console_manager.visible = state.console.visible;
			console_manager.height = state.console.height;
			if (console_manager.height < console::MIN_HEIGHT) console_manager.height = console::DEFAULT_HEIGHT;
			if (restore_sessions && state.console.active >= 0
				&& state.console.active < (int)console_manager.sessions.len())
			{
				console_manager.active = state.console.active;
			}
			console_manager.next_title = (int)console_manager.sessions.len() + 1;
			console_manager.sync_active_panel();
		}
	};
	return true;
}