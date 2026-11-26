module yun::recovery;

import libc;
import std::collections::list;
import std::core::mem::alloc;
import std::encoding::json;
import std::io::file;
import std::io::path;
import std::os;
import yun::canvas;
import yun::card;
import yun::console;
import yun::editor;
import yun::project;
import yun::workspace;

const String RECOVERY_DIR  = ".yun/recovery";
const String JOURNAL_FILE  = "journal.json";
const String MARKER_FILE   = "active";
const String JOURNAL_TMP   = "journal.tmp";
const String JOURNAL_VER   = "1";
const usz MAX_JOURNAL_TEXT = 32u * 1024u * 1024u;

struct RecoveryBuffer
{
	String path;
	String text;
	long mtime;
	long size;
}

struct RecoveryState
{
	String version;
	RecoveryBuffer[] buffers;
}

struct RecoveryResult
{
	int restored;
	int conflicts;
	bool layout;
}

fn Path? recovery_dir(Allocator allocator, String root)
{
	if (root.len == 0) return (Path)RECOVERY_DIR;
	return ((Path)root).append(allocator, RECOVERY_DIR);
}

fn String relative_path(Allocator allocator, String root, String absolute)
{
	if (!project::path_is_inside(root, absolute) || absolute.len <= root.len) return "";
	return absolute[root.len + 1..].copy(allocator);
}

fn bool begin(project::Project* project)
{
	if (project.root.len == 0) return false;
	@pool()
	{
		Path? dir = recovery_dir(tmem, (String)project.root);
		if (catch excuse = dir) return false;
		if (catch excuse = path::mkdir(dir, recursive: true)) return false;
		Path? marker = dir.append(tmem, MARKER_FILE);
		if (catch excuse = marker) return false;
		if (catch excuse = file::save(marker, "1")) return false;
	};
	return true;
}

fn bool available(project::Project* project)
{
	if (project.root.len == 0) return false;
	@pool()
	{
		Path? dir = recovery_dir(tmem, (String)project.root);
		if (catch excuse = dir) return false;
		Path? marker = dir.append(tmem, MARKER_FILE);
		if (catch excuse = marker) return false;
		if (!path::exists(marker)) return false;
		Path? journal = dir.append(tmem, JOURNAL_FILE);
		if (catch excuse = journal) return false;
		Path? layout = dir.append(tmem, workspace::WORKSPACE_FILE);
		if (catch excuse = layout) return false;
		return path::exists(journal) || path::exists(layout);
	};
}

fn bool journal(project::Project* project, canvas::Canvas* canvas, console::ConsoleManager* console_manager)
{
	if (project.root.len == 0) return false;
	@pool()
	{
		Path? dir = recovery_dir(tmem, (String)project.root);
		if (catch excuse = dir) return false;
		if (catch excuse = path::mkdir(dir, recursive: true)) return false;

		List{RecoveryBuffer} buffers;
		buffers.init(tmem);
		usz total = 0;
		for (sz i = 0; i < project.cards.len(); i++)
		{
			FileCard* card = &project.cards[i];
			if (!card.buffer || !card.dirty) continue;
			usz length = card.buffer.length();
			if (length > MAX_JOURNAL_TEXT - total) break;
			String relative = relative_path(tmem, (String)project.root, (String)card.path);
			if (relative.len == 0) continue;
			buffers.push(
				{
					.path = relative,
					.text = card.buffer.slice(0, length, tmem),
					.mtime = card.mtime,
					.size = card.size,
				}
			);
			total += length;
		}

		RecoveryState state = { .version = JOURNAL_VER, .buffers = buffers.entries[0:buffers.len()] };
		String json_text    = json::marshal(tmem, state, JsonIndent.SPACE_2);
		Path? tmp           = dir.append(tmem, JOURNAL_TMP);
		if (catch excuse = tmp) return false;
		Path? target = dir.append(tmem, JOURNAL_FILE);
		if (catch excuse = target) return false;
		if (catch excuse = file::save(tmp, json_text.ptr[0:json_text.len])) return false;
		if (libc::rename((ZString)tmp.ptr, (ZString)target.ptr) != 0) return false;

		(void)workspace::save_at(project, canvas, console_manager, dir);
	};
	return true;
}

fn bool restore(
	project::Project* project,
	canvas::Canvas* canvas,
	console::ConsoleManager* console_manager,
	RecoveryResult* result
)
{
	if (project.root.len == 0) return false;
	*result = { };
	@pool()
	{
		Path? dir = recovery_dir(tmem, (String)project.root);
		if (catch excuse = dir) return false;
		Path? journal_path = dir.append(tmem, JOURNAL_FILE);
		if (catch excuse = journal_path) return false;
		Path? layout_path = dir.append(tmem, workspace::WORKSPACE_FILE);
		if (catch excuse = layout_path) return false;

		if (path::exists(layout_path))
		{
			result.layout = workspace::load_at(project, canvas, console_manager, dir);
		}

		if (!path::exists(journal_path)) return true;
		char[]? data = file::load(tmem, journal_path);
		if (catch excuse = data) return false;
		RecoveryState? parsed = json::unmarshal(tmem, (String)data, RecoveryState);
		if (catch excuse = parsed) return false;
		RecoveryState state = parsed;
		if (state.version.compare_to(JOURNAL_VER) != 0) return false;

		for (usz i = 0; i < state.buffers.len; i++)
		{
			Path? absolute = ((Path)(String)project.root).append(tmem, state.buffers[i].path);
			if (catch excuse = absolute) continue;
			int index = project.find_card((String)absolute);
			if (index < 0) continue;
			FileCard* card = &project.cards[index];
			editor::stamp_file(card);
			if (card.mtime != state.buffers[i].mtime || card.size != state.buffers[i].size) result.conflicts++;
			editor::restore_buffer(card, state.buffers[i].text, project.allocator);
			result.restored++;
		}
	};
	clear(project);
	return true;
}

fn void clear(project::Project* project)
{
	if (project.root.len == 0) return;
	@pool()
	{
		Path? dir = recovery_dir(tmem, (String)project.root);
		if (catch excuse = dir) return;
		(void)path::rmtree(dir);
	};
}