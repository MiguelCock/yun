module yun::project;

import libc;
import raylib6::rl;
import std::collections::list;
import std::collections::map;
import std::core::mem::alloc;
import std::io::file;
import std::io::path;
import std::math;
import yun::canvas;
import yun::card;
import yun::commands;
import yun::completion;
import yun::editor;
import yun::findbar;
import yun::gitignore;
import yun::highlight;
import yun::keymap;
import yun::lsp;
import yun::markdown;
import yun::spatial;
import yun::text;
import yun::theme;
import yun::ui;

const int ROOT_FOLDER               = -1;
const double POLL_SECONDS           =  1.0;
const float CLUSTER_PADDING         =  24.0f;
const float CLUSTER_TITLE_HEIGHT    =  26.0f;
const float CLUSTER_COLLAPSED_WIDTH =  240.0f;
const float CLUSTER_GAP             =  16.0f;
const float CARD_GAP                =  16.0f;
const int CLUSTER_COLUMNS           =  3;
const String[] IGNORED_NAMES        =  { ".git", ".yun", "build", "out", "node_modules" };
const float DRAW_CULL_MARGIN        =  64.0f;
const float CARD_MIN_DRAW_PX        =  3.0f;
const double DOUBLE_CLICK_SECONDS   =  0.35;
const float DOUBLE_CLICK_DIST       =  6.0f;
const usz OPEN_SCAN_BUDGET          =  64;
const usz OPEN_BUILD_BUDGET         =  4096;
const double JUMP_HIGHLIGHT_SECONDS =  1.0;
const int JUMP_HIGHLIGHT_ALPHA      =  80;

enum OpenPhase : int
{
	SCAN,
	SORT,
	BUILD_FOLDERS,
	BUILD_CARDS,
	LAYOUT,
	DONE,
	FAILED,
}

enum Dir : int
{
	LEFT,
	RIGHT,
	UP,
	DOWN,
}

struct NavItem
{
	bool folder;
	int index;
}

struct OpenJob
{
	Allocator allocator;
	Project* project;
	Path root;
	PathList entries;
	List{Path} pending;
	gitignore::Gitignore ignore;
	OpenPhase phase;
	bool cancelled;
	usz scanned_dirs;
	usz build_cursor;
}

faultdef COPY_FAILED;
faultdef RESOLVE_FAILED;

struct FolderCluster
{
	Path path;
	Rect bounds;
	bool collapsed;
	int parent;
	bool bounds_valid;
}

struct Project
{
	Path root;
	List{FileCard} cards;
	List{FolderCluster} folders;
	HashMap{String, int} folder_index;
	Allocator allocator;
	int focused;
	int selected;
	int selected_cluster;
	int current_folder;
	bool grabbing;
	int hover_card;
	bool drag_card;
	int drag_index;
	bool drag_cluster;
	int drag_cluster_index;
	bool drag_cluster_title;
	bool cluster_moved;
	RLVector2 drag_world;
	double last_input_time;
	double last_poll;
	int pending_reload;
	int pending_close;
	bool resizing;
	int resize_card;
	int resize_handle;
	int last_cursor;
	bool selecting;
	double last_click_time;
	RLVector2 last_click_pos;
	String jump_path;
	usz jump_line;
	double jump_until;
	int awake_count;
	int asleep_count;
	int cards_revision;
	spatial::Grid grid;
	bool grid_dirty;
	bool content_bounds_valid;
	Rect content_bounds_cache;
	int hover_cluster;
}

fn void Project.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.cards.init(allocator);
	self.folders.init(allocator);
	self.folder_index.init(allocator);
	self.focused = -1;
	self.selected = -1;
	self.selected_cluster = -1;
	self.current_folder = ROOT_FOLDER;
	self.grabbing = false;
	self.drag_card = false;
	self.drag_cluster = false;
	self.drag_cluster_title = false;
	self.last_poll = 0.0;
	self.pending_reload = -1;
	self.pending_close = -1;
	self.resizing = false;
	self.last_cursor = -1;
	self.selecting = false;
	self.last_click_time = -1000.0;
	self.last_click_pos = { 0.0f, 0.0f };
	self.jump_path = "";
	self.jump_line = 0;
	self.jump_until = 0.0;
	self.awake_count = 0;
	self.asleep_count = 0;
	self.cards_revision = 0;
	self.grid.init(allocator, spatial::CELL_SIZE);
	self.grid_dirty = true;
	self.content_bounds_valid = false;
	self.hover_cluster = -1;
	Path? cwd = path::cwd(allocator);
	if (catch excuse = cwd)
	{
		self.root = (Path)"";
		return;
	}
	self.root = cwd;
}

fn void Project.destroy_card(&self, FileCard* card)
{
	editor::destroy_buffer(card, self.allocator);
	if (((String)card.path).len) ((String)card.path).free(self.allocator);
	if (card.name.len) card.name.free(self.allocator);
}

fn void Project.destroy_cards(&self)
{
	for (sz i = 0; i < self.cards.len(); i++)
	{
		self.destroy_card(&self.cards[i]);
	}
	self.cards.clear();
}

fn void Project.destroy_folders(&self)
{
	for (sz i = 0; i < self.folders.len(); i++)
	{
		if (((String)self.folders[i].path).len) ((String)self.folders[i].path).free(self.allocator);
	}
	self.folders.clear();
	self.folder_index.clear();
}

fn void Project.destroy(&self)
{
	self.destroy_cards();
	self.destroy_folders();
	self.cards.free();
	self.folders.free();
	self.folder_index.free();
	self.grid.destroy();
	self.clear_jump();
	if (((String)self.root).len) ((String)self.root).free(self.allocator);
}

fn void Project.reset(&self)
{
	self.discard_ephemeral(-1);
	self.destroy_cards();
	self.destroy_folders();
	self.cards_revision++;
	self.focused = -1;
	self.selected = -1;
	self.selected_cluster = -1;
	self.current_folder = ROOT_FOLDER;
	self.grabbing = false;
	self.drag_card = false;
	self.drag_cluster = false;
	self.drag_cluster_title = false;
	self.cluster_moved = false;
	self.selecting = false;
	self.grid_dirty = true;
	self.content_bounds_valid = false;
	self.clear_jump();
}

fn float jump_fade(double now, double until, double duration)
{
	if (duration <= 0.0) return 0.0f;
	float t = (float)((until - now) / duration);
	if (t < 0.0f) t = 0.0f;
	if (t > 1.0f) t = 1.0f;
	return t;
}

fn void Project.mark_jump(&self, String path, usz line, double now)
{
	if (self.jump_path.len) self.jump_path.free(self.allocator);
	self.jump_path = path.copy(self.allocator);
	self.jump_line = line;
	self.jump_until = now + JUMP_HIGHLIGHT_SECONDS;
}

fn void Project.clear_jump(&self)
{
	if (self.jump_path.len) self.jump_path.free(self.allocator);
	self.jump_path = "";
	self.jump_line = 0;
	self.jump_until = 0.0;
}

fn void Project.discard_ephemeral(&self, int keep)
{
	for (sz i = self.cards.len(); i > 0; i--)
	{
		sz index = i - 1;
		if (!self.cards[index].ephemeral) continue;
		if ((int)index == keep) continue;
		FileCard card = self.cards[index];
		editor::destroy_buffer(&self.cards[index], self.allocator);
		@pool()
		{
			(void)libc::remove(((String)card.path).zstr_tcopy());
		};
		self.cards.remove_at(index);
		if (((String)card.path).len) ((String)card.path).free(self.allocator);
		if (card.name.len) card.name.free(self.allocator);
		if (self.focused > (int)index)
		{
			self.focused--;
		}
		else if (self.focused == (int)index)
		{
			self.focused = -1;
			self.hover_card = -1;
		}
		if (self.selected > (int)index)
		{
			self.selected--;
		}
		else if (self.selected == (int)index)
		{
			self.selected = -1;
		}
	}
	self.invalidate_bounds();
}

fn bool path_is_inside(String root, String abs)
{
	if (root.len == 0 || abs.len < root.len) return false;
	if (abs[0:root.len].compare_to(root) != 0) return false;
	if (abs.len == root.len) return true;
	char next = abs[root.len];
	return next == '/' || next == '\\';
}

fn bool basename_is_ignored(String path)
{
	usz start = 0;
	for (usz i = 0; i < path.len; i++)
	{
		if (path[i] == '/' || path[i] == '\\') start = i + 1;
	}
	String component = path[start:path.len - start];
	foreach (String ignored : IGNORED_NAMES)
	{
		if (component.compare_to(ignored) == 0) return true;
	}
	return false;
}

fn int path_compare(void* a, void* b)
{
	Path pa = *(Path*)a;
	Path pb = *(Path*)b;
	return ((String)pa).compare_to((String)pb);
}

fn bool rect_contains(Rect r, RLVector2 point)
{
	return point[0] >= r.x && point[0] <= r.x + r.width && point[1] >= r.y && point[1] <= r.y + r.height;
}

fn bool rect_intersects(Rect a, Rect b)
{
	return a.x <= b.x + b.width && a.x + a.width >= b.x && a.y <= b.y + b.height && a.y + a.height >= b.y;
}

fn Rect expand_rect(Rect r, float margin)
{
	return {
		.x = r.x - margin,
		.y = r.y - margin,
		.width = r.width + margin * 2.0f,
		.height = r.height + margin * 2.0f
	};
}

fn Rect visible_world_rect(RLCamera2D camera)
{
	RLVector2 min = canvas::screen_to_world_camera(camera, { 0.0f, 0.0f });
	RLVector2 max = canvas::screen_to_world_camera(
		camera,
		{ (float)rl::get_screen_width(), (float)rl::get_screen_height() }
	);
	return { .x = min[0], .y = min[1], .width = max[0] - min[0], .height = max[1] - min[1] };
}

fn String collision_name(Allocator allocator, String stem, String ext, int index)
{
	if (index <= 0) return string::format(allocator, "%s%s", stem, ext);
	return string::format(allocator, "%s (%d)%s", stem, index, ext);
}

fn String file_stem(String path_str)
{
	return rl::get_file_name_without_ext((ZString)path_str.ptr).str_view();
}

fn String file_ext(String path_str)
{
	return rl::get_file_extension((ZString)path_str.ptr).str_view();
}

fn int Project.find_card(&self, String abs)
{
	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (((String)self.cards[i].path).compare_to(abs) == 0) return (int)i;
	}
	return -1;
}

fn int Project.folder_for(&self, String file)
{
	usz cut = file.len;
	while (cut > 0)
	{
		cut--;
		if (file[cut] == '/' || file[cut] == '\\') break;
	}
	while (cut > 0)
	{
		int found = self.folder_by_path(file[0:cut]);
		if (found >= 0) return found;
		while (cut > 0)
		{
			cut--;
			if (file[cut] == '/' || file[cut] == '\\') break;
		}
	}
	return ROOT_FOLDER;
}

fn int Project.folder_by_path(&self, String path)
{
	int*? found = self.folder_index.get_ref(path);
	if (catch excuse = found) return ROOT_FOLDER;
	return *found;
}

fn void Project.rebuild_folder_index(&self)
{
	self.folder_index.clear();
	for (sz i = 0; i < self.folders.len(); i++)
	{
		self.folder_index.set((String)self.folders[i].path, (int)i);
	}
}

fn int Project.ensure_folder(&self, String dir)
{
	if (dir.compare_to((String)self.root) == 0) return ROOT_FOLDER;
	int existing = self.folder_by_path(dir);
	if (existing >= 0) return existing;

	String parent = rl::get_prev_directory_path((ZString)dir.ptr).str_view().copy(self.allocator);
	if (parent.compare_to(dir) == 0) return ROOT_FOLDER;
	int parent_index = self.ensure_folder(parent);
	return self.add_folder(dir, parent_index);
}

fn bool Project.folder_collapsed(&self, int index)
{
	int current = index;
	while (current != ROOT_FOLDER)
	{
		if (self.folders[current].collapsed) return true;
		current = self.folders[current].parent;
	}
	return false;
}

fn bool Project.card_visible(&self, int card_index)
{
	return !self.folder_collapsed(self.cards[card_index].folder);
}

fn bool Project.cluster_visible(&self, int index)
{
	return !self.folder_collapsed(self.folders[index].parent);
}

fn void Project.invalidate_bounds(&self)
{
	for (sz i = 0; i < self.folders.len(); i++)
	{
		self.folders[i].bounds_valid = false;
	}
	self.grid_dirty = true;
	self.content_bounds_valid = false;
}

fn void Project.invalidate_bounds_for_card(&self, int card_index)
{
	if (card_index < 0 || card_index >= (int)self.cards.len()) return;
	int current = self.cards[card_index].folder;
	while (current != ROOT_FOLDER)
	{
		self.folders[current].bounds_valid = false;
		current = self.folders[current].parent;
	}
	self.grid_dirty = true;
	self.content_bounds_valid = false;
}

fn int Project.add_folder(&self, String folder_path, int parent)
{
	FolderCluster cluster = {
		.path = (Path)folder_path.copy(self.allocator),
		.bounds = { .x = 0.0f, .y = 0.0f, .width = ui::pxf(320.0f), .height = ui::pxf(220.0f) },
		.collapsed = false,
		.parent = parent,
		.bounds_valid = false,
	};
	self.folders.push(cluster);
	int index = (int)(self.folders.len() - 1);
	self.folder_index.set((String)self.folders[index].path, index);
	return index;
}

fn Rect Project.cluster_bounds(&self, int index)
{
	if (self.folders[index].bounds_valid) return self.folders[index].bounds;
	Rect bounds = self.compute_cluster_bounds(index);
	self.folders[index].bounds = bounds;
	self.folders[index].bounds_valid = true;
	return bounds;
}

fn Rect Project.compute_cluster_bounds(&self, int index)
{
	bool found  = false;
	float min_x = 0.0f;
	float min_y = 0.0f;
	float max_x = 0.0f;
	float max_y = 0.0f;

	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (self.cards[i].folder != index) continue;
		Rect r = self.cards[i].rect;
		if (!found)
		{
			min_x = r.x;
			min_y = r.y;
			max_x = r.x + r.width;
			max_y = r.y + r.height;
			found = true;
		}
		else
		{
			min_x = math::min(min_x, r.x);
			min_y = math::min(min_y, r.y);
			max_x = math::max(max_x, r.x + r.width);
			max_y = math::max(max_y, r.y + r.height);
		}
	}

	for (sz i = 0; i < self.folders.len(); i++)
	{
		if (self.folders[i].parent != index) continue;
		Rect r = self.cluster_visual_bounds((int)i);
		if (!found)
		{
			min_x = r.x;
			min_y = r.y;
			max_x = r.x + r.width;
			max_y = r.y + r.height;
			found = true;
		}
		else
		{
			min_x = math::min(min_x, r.x);
			min_y = math::min(min_y, r.y);
			max_x = math::max(max_x, r.x + r.width);
			max_y = math::max(max_y, r.y + r.height);
		}
	}

	if (!found) return self.folders[index].bounds;
	return {
		.x = min_x - ui::pxf(CLUSTER_PADDING),
		.y = min_y - ui::pxf(CLUSTER_PADDING) - ui::pxf(CLUSTER_TITLE_HEIGHT),
		.width = (max_x - min_x) + ui::pxf(CLUSTER_PADDING) * 2.0f,
		.height = (max_y - min_y) + ui::pxf(CLUSTER_PADDING) * 2.0f + ui::pxf(CLUSTER_TITLE_HEIGHT),
	};
}

fn Rect Project.cluster_visual_bounds(&self, int index)
{
	Rect full = self.cluster_bounds(index);
	if (!self.folders[index].collapsed) return full;
	return {
		.x = full.x,
		.y = full.y,
		.width = ui::pxf(CLUSTER_COLLAPSED_WIDTH),
		.height = ui::pxf(CLUSTER_TITLE_HEIGHT),
	};
}

fn Rect Project.cluster_title_rect(&self, int index)
{
	Rect bounds = self.cluster_visual_bounds(index);
	return {
		.x = bounds.x,
		.y = bounds.y,
		.width = bounds.width,
		.height = ui::pxf(CLUSTER_TITLE_HEIGHT),
	};
}

fn bool Project.cluster_title_hit(&self, int index, RLVector2 world)
{
	return rect_contains(self.cluster_title_rect(index), world);
}

fn bool Project.content_bounds(&self, Rect* out)
{
	if (self.content_bounds_valid)
	{
		*out = self.content_bounds_cache;
		return true;
	}
	bool found  = false;
	float min_x = 0.0f;
	float min_y = 0.0f;
	float max_x = 0.0f;
	float max_y = 0.0f;

	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (!self.card_visible((int)i)) continue;
		Rect r = self.cards[i].rect;
		if (!found)
		{
			min_x = r.x;
			min_y = r.y;
			max_x = r.x + r.width;
			max_y = r.y + r.height;
			found = true;
		}
		else
		{
			min_x = math::min(min_x, r.x);
			min_y = math::min(min_y, r.y);
			max_x = math::max(max_x, r.x + r.width);
			max_y = math::max(max_y, r.y + r.height);
		}
	}

	for (sz i = 0; i < self.folders.len(); i++)
	{
		if (!self.cluster_visible((int)i)) continue;
		Rect r = self.cluster_visual_bounds((int)i);
		if (!found)
		{
			min_x = r.x;
			min_y = r.y;
			max_x = r.x + r.width;
			max_y = r.y + r.height;
			found = true;
		}
		else
		{
			min_x = math::min(min_x, r.x);
			min_y = math::min(min_y, r.y);
			max_x = math::max(max_x, r.x + r.width);
			max_y = math::max(max_y, r.y + r.height);
		}
	}

	if (!found) return false;
	*out = { .x = min_x, .y = min_y, .width = max_x - min_x, .height = max_y - min_y };
	self.content_bounds_cache = *out;
	self.content_bounds_valid = true;
	return true;
}

fn void Project.ensure_grid(&self)
{
	if (!self.grid_dirty) return;
	self.grid.clear();
	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (!self.card_visible((int)i)) continue;
		self.grid.insert(self.cards[i].rect, (int)i);
	}
	self.grid_dirty = false;
}

fn void Project.visible_cards(&self, Rect visible, List{int}* out)
{
	self.ensure_grid();
	self.grid.query_rect(visible, out);
	if (out.len() > 1) libc::qsort(out.entries, (usz)out.size, (usz)int::size, &int_compare);
}

fn int int_compare(void* a, void* b)
{
	int va = *(int*)a;
	int vb = *(int*)b;
	return va < vb ? -1 : (va > vb ? 1 : 0);
}

fn int Project.cluster_hit(&self, RLVector2 world)
{
	int best     = ROOT_FOLDER;
	usz best_len = 0;
	for (sz i = 0; i < self.folders.len(); i++)
	{
		if (!self.cluster_visible((int)i)) continue;
		if (!rect_contains(self.cluster_visual_bounds((int)i), world)) continue;
		String fp = (String)self.folders[i].path;
		if (fp.len >= best_len)
		{
			best = (int)i;
			best_len = fp.len;
		}
	}
	return best;
}

fn int Project.folder_at(&self, RLVector2 world)
{
	int best     = ROOT_FOLDER;
	usz best_len = 0;
	for (sz i = 0; i < self.folders.len(); i++)
	{
		if (!self.cluster_visible((int)i)) continue;
		if (!rect_contains(self.cluster_visual_bounds((int)i), world)) continue;
		String fp = (String)self.folders[i].path;
		if (fp.len >= best_len)
		{
			best = (int)i;
			best_len = fp.len;
		}
	}
	return best;
}

fn String? Project.copy_into_root(&self, String abs)
{
	String name    = collision_name(self.allocator, file_stem(abs), file_ext(abs), 0);
	Path? appended = self.root.append(self.allocator, name);
	if (catch excuse = appended) return COPY_FAILED~;
	Path dest = appended;

	int index = 1;
	while (path::exists(dest))
	{
		String alt = collision_name(self.allocator, file_stem(abs), file_ext(abs), index);
		Path? next = self.root.append(self.allocator, alt);
		if (catch excuse = next) return COPY_FAILED~;
		dest = next;
		index++;
	}

	char[]? data = file::load(self.allocator, abs);
	if (catch excuse = data) return COPY_FAILED~;
	if (catch excuse = file::save(dest, data)) return COPY_FAILED~;
	return (String)dest;
}

fn String? Project.external_copy(&self, String abs)
{
	Path? base = self.root.append(self.allocator, ".yun");
	if (catch excuse = base) return COPY_FAILED~;
	Path? dir = base.append(self.allocator, "external");
	if (catch excuse = dir) return COPY_FAILED~;
	if (catch excuse = path::mkdir(dir, recursive: true)) return COPY_FAILED~;

	String name    = rl::get_file_name((ZString)abs.ptr).str_view();
	Path? appended = dir.append(self.allocator, name);
	if (catch excuse = appended) return COPY_FAILED~;
	Path dest = appended;

	int index = 1;
	while (path::exists(dest))
	{
		String alt = string::format(self.allocator, "%d_%s", index, name);
		Path? next = dir.append(self.allocator, alt);
		if (catch excuse = next) return COPY_FAILED~;
		dest = next;
		index++;
	}

	char[]? data = file::load(self.allocator, abs);
	if (catch excuse = data) return COPY_FAILED~;
	if (catch excuse = file::save((String)dest, data)) return COPY_FAILED~;
	return (String)dest;
}

fn int Project.append_card(&self, String abs, RLVector2 world_pos)
{
	FileCard card = {
		.path = (Path)abs.copy(self.allocator),
		.name = rl::get_file_name((ZString)abs.ptr)
		.str_view()
		.copy(
			self.allocator
		), .rect = {
			.x = world_pos[0] - ui::pxf(card::CARD_WIDTH) / 2.0f,
			.y = world_pos[1] - ui::pxf(card::CARD_HEIGHT) / 2.0f,
			.width = ui::pxf(card::CARD_WIDTH),
			.height = ui::pxf(card::CARD_HEIGHT),
		}, .open = true, .dirty = false, .folder = self.folder_for(abs), };
	self.cards.push(card);
	int index = (int)(self.cards.len() - 1);
	self.cards_revision++;
	self.invalidate_bounds();
	return index;
}

fn int Project.add_card(&self, String abs, RLVector2 world_pos)
{
	int existing = self.find_card(abs);
	if (existing >= 0)
	{
		self.focused = existing;
		return existing;
	}

	String final = abs;
	if (!path_is_inside((String)self.root, abs))
	{
		String? copied = self.copy_into_root(abs);
		if (catch excuse = copied) return -1;
		final = copied;
	}

	self.focused = self.append_card(final, world_pos);
	return self.focused;
}

fn int Project.add_folder_from_disk(&self, String dir, RLVector2 world_pos)
{
	if (!path_is_inside((String)self.root, dir)) return -1;
	int parent = self.folder_for(dir);
	int index  = self.add_folder(dir, parent);
	self.folders[index].bounds = {
		.x = world_pos[0],
		.y = world_pos[1],
		.width = ui::pxf(320.0f),
		.height = ui::pxf(220.0f),
	};
	self.invalidate_bounds();

	PathList? entries = path::ls(self.allocator, (Path)dir, no_dirs: true, recursive: false, relative: false);
	if (catch excuse = entries) return index;

	float x = world_pos[0] + ui::pxf(CLUSTER_PADDING);
	float y = world_pos[1] + ui::pxf(CLUSTER_TITLE_HEIGHT) + ui::pxf(CLUSTER_PADDING);
	int col = 0;
	foreach (Path entry : entries)
	{
		self.add_card((String)entry, { x + ui::pxf(card::CARD_WIDTH) / 2.0f, y + ui::pxf(card::CARD_HEIGHT) / 2.0f });
		x += ui::pxf(card::CARD_WIDTH) + ui::pxf((float)CARD_GAP);
		col++;
		if (col >= CLUSTER_COLUMNS)
		{
			col = 0;
			x = world_pos[0] + ui::pxf(CLUSTER_PADDING);
			y += ui::pxf(card::CARD_HEIGHT) + ui::pxf((float)CARD_GAP);
		}
	}
	return index;
}

fn void Project.place_cards_grid(&self, List{int}* cards, float base_x, float base_y, float cw, float ch, float cg)
{
	int count = (int)cards.len();
	int cols  = count < CLUSTER_COLUMNS ? (count < 1 ? 1 : count) : CLUSTER_COLUMNS;
	for (int k = 0; k < count; k++)
	{
		int col = k % cols;
		int row = k / cols;
		self.cards[(*cards)[k]].rect = {
			.x = base_x + (float)col * (cw + cg),
			.y = base_y + (float)row * (ch + cg),
			.width = cw,
			.height = ch,
		};
	}
}

fn RLVector2 Project.card_block_size(&self, int count, float cw, float ch, float cg)
{
	int cols = count < CLUSTER_COLUMNS ? (count < 1 ? 1 : count) : CLUSTER_COLUMNS;
	int rows = count == 0 ? 0 : (count + cols - 1) / cols;
	return { count == 0 ? 0.0f : (float)cols * (cw + cg) - cg, rows == 0 ? 0.0f : (float)rows * (ch + cg) - cg };
}

fn RLVector2 Project.flow_pack(&self, List{RLVector2}* items, float gap, float target_w, RLVector2[] positions)
{
	RLVector2 cursor = { 0.0f, 0.0f };
	float row_h      = 0.0f;
	float max_x      = 0.0f;
	for (sz i = 0; i < items.len(); i++)
	{
		RLVector2 it = (*items)[i];
		if (cursor[0] > 0.0f && cursor[0] + it[0] > target_w)
		{
			cursor[0] = 0.0f;
			cursor[1] += row_h + gap;
			row_h = 0.0f;
		}
		if ((usz)i < positions.len) positions[(usz)i] = cursor;
		cursor[0] += it[0] + gap;
		row_h = math::max(row_h, it[1]);
		max_x = math::max(max_x, cursor[0] - gap);
	}
	return { max_x, cursor[1] + row_h };
}

fn RLVector2 Project.chip_size(&self)
{
	return { ui::pxf(CLUSTER_COLLAPSED_WIDTH), ui::pxf(CLUSTER_TITLE_HEIGHT) };
}

fn void Project.place_level(&self, int index, RLVector2 origin, List{int}[]* cards_by, List{int}[]* children_by)
{
	float pad      = ui::pxf(CLUSTER_PADDING);
	float title    = ui::pxf(CLUSTER_TITLE_HEIGHT);
	float cw       = ui::pxf(card::CARD_WIDTH);
	float ch       = ui::pxf(card::CARD_HEIGHT);
	float cg       = ui::pxf((float)CARD_GAP);
	float gap      = ui::pxf(CLUSTER_GAP);
	RLVector2 chip = self.chip_size();

	float content_x = origin[0] + pad;
	float content_y = origin[1] + title + pad;

	List{int} cards = (*cards_by)[(usz)(index + 1)];
	List{int} kids  = (*children_by)[(usz)index];

	List{RLVector2} items;
	items.init(tmem);
	if (cards.len() > 0) items.push(self.card_block_size((int)cards.len(), cw, ch, cg));
	for (sz i = 0; i < kids.len(); i++) items.push(chip);

	RLVector2[] positions = alloc::new_array(tmem, RLVector2, (usz)(items.len() == 0 ? 1 : items.len()));
	float area            = 0.0f;
	for (sz i = 0; i < items.len(); i++) area += items[i][0] * items[i][1];
	self.flow_pack(&items, gap, math::sqrt(area), positions);
	items.free();

	int base = cards.len() > 0 ? 1 : 0;
	if (cards.len() > 0)
	{
		self.place_cards_grid(&cards, content_x + positions[0][0], content_y + positions[0][1], cw, ch, cg);
	}
	for (sz i = 0; i < kids.len(); i++)
	{
		RLVector2 p = positions[(usz)(base + (int)i)];
		self.place_level(kids[i], { content_x + p[0], content_y + p[1] }, cards_by, children_by);
	}

	if (cards.len() == 0 && kids.len() == 0)
	{
		self.folders[index].bounds = { .x = origin[0], .y = origin[1], .width = chip[0], .height = chip[1] };
		self.folders[index].bounds_valid = true;
	}
	else
	{
		self.folders[index].bounds_valid = false;
	}
}

fn void Project.layout(&self)
{
	int nf         = (int)self.folders.len();
	float cw       = ui::pxf(card::CARD_WIDTH);
	float ch       = ui::pxf(card::CARD_HEIGHT);
	float cg       = ui::pxf((float)CARD_GAP);
	float gap      = ui::pxf(CLUSTER_GAP);
	RLVector2 chip = self.chip_size();

	@pool()
	{
		List{int}[] cards_by = alloc::new_array(tmem, List{int}, (usz)(nf + 1));
		for (usz i = 0; i < cards_by.len; i++) cards_by[i].init(tmem);
		for (sz i = 0; i < self.cards.len(); i++) cards_by[(usz)(self.cards[i].folder + 1)].push((int)i);

		List{int}[] children_by = { };
		if (nf > 0)
		{
			children_by = alloc::new_array(tmem, List{int}, (usz)nf);
			for (usz i = 0; i < children_by.len; i++) children_by[i].init(tmem);
			for (sz i = 0; i < self.folders.len(); i++)
			{
				int p = self.folders[i].parent;
				if (p >= 0 && p < nf) children_by[(usz)p].push((int)i);
			}
		}

		List{int} root_cards = cards_by[0];
		List{int} tops;
		tops.init(tmem);
		for (sz i = 0; i < self.folders.len(); i++)
		{
			if (self.folders[i].parent == ROOT_FOLDER) tops.push((int)i);
		}

		List{RLVector2} items;
		items.init(tmem);
		if (root_cards.len() > 0) items.push(self.card_block_size((int)root_cards.len(), cw, ch, cg));
		for (sz i = 0; i < tops.len(); i++) items.push(chip);

		if (items.len() > 0)
		{
			RLVector2[] positions = alloc::new_array(tmem, RLVector2, (usz)items.len());
			float area            = 0.0f;
			for (sz i = 0; i < items.len(); i++) area += items[i][0] * items[i][1];
			self.flow_pack(&items, gap, math::sqrt(area), positions);

			int base = root_cards.len() > 0 ? 1 : 0;
			if (root_cards.len() > 0)
			{
				self.place_cards_grid(&root_cards, positions[0][0], positions[0][1], cw, ch, cg);
			}
			for (sz i = 0; i < tops.len(); i++)
			{
				RLVector2 p = positions[(usz)(base + (int)i)];
				self.place_level(tops[i], p, &cards_by, &children_by);
			}
		}
	};
}

fn void Project.place_unrestored(&self)
{
	@pool()
	{
		HashMap{int, int} counts;
		counts.init(tmem);
		for (sz i = 0; i < self.cards.len(); i++)
		{
			FileCard* card = &self.cards[i];
			if (card.restored) continue;
			Rect anchor = { .x = 0.0f, .y = 0.0f, .width = 0.0f, .height = 0.0f };
			if (card.folder >= 0) anchor = self.folders[card.folder].bounds;
			int slot       = 0;
			int*? existing = counts.get_ref(card.folder);
			if (try v = existing) slot = *v;
			counts.set(card.folder, slot + 1);
			int col = slot % CLUSTER_COLUMNS;
			int row = slot / CLUSTER_COLUMNS;
			card.rect = {
				.x = anchor.x + ui::pxf(
					CLUSTER_PADDING
				) + (float)col * (ui::pxf(card::CARD_WIDTH) + ui::pxf((float)CARD_GAP)),
				.y = anchor.y + anchor.height + ui::pxf(
					(float)CARD_GAP
				) + (float)row * (ui::pxf(card::CARD_HEIGHT) + ui::pxf((float)CARD_GAP)),
				.width = ui::pxf(card::CARD_WIDTH),
				.height = ui::pxf(card::CARD_HEIGHT),
			};
			card.restored = true;
		}
		counts.free();
	};
	self.invalidate_bounds();
}

fn void Project.scale_geometry(&self, float factor)
{
	if (factor == 1.0f) return;
	for (sz i = 0; i < self.cards.len(); i++)
	{
		self.cards[i].rect.x *= factor;
		self.cards[i].rect.y *= factor;
		self.cards[i].rect.width *= factor;
		self.cards[i].rect.height *= factor;
	}
	for (sz i = 0; i < self.folders.len(); i++)
	{
		self.folders[i].bounds.x *= factor;
		self.folders[i].bounds.y *= factor;
		self.folders[i].bounds.width *= factor;
		self.folders[i].bounds.height *= factor;
		self.folders[i].bounds_valid = false;
	}
	self.invalidate_bounds();
}

fn OpenJob* open_job_create(Allocator allocator, Project* project, String root)
{
	OpenJob* job = alloc::new(allocator, OpenJob);
	job.allocator = allocator;
	job.project = project;
	job.root = (Path)root;
	job.entries.init(allocator);
	job.pending.init(allocator);
	job.ignore.init(allocator);
	job.phase = OpenPhase.SCAN;
	job.cancelled = false;
	job.scanned_dirs = 0;
	job.build_cursor = 0;
	job.pending.push((Path)root);
	return job;
}

fn void open_job_destroy(OpenJob* job)
{
	if (!job) return;
	job.entries.free();
	job.pending.free();
	job.ignore.free();
	alloc::free(job.allocator, job);
}

fn void OpenJob.cancel(&self)
{
	if (self.phase != OpenPhase.SCAN) return;
	self.cancelled = true;
	self.phase = OpenPhase.FAILED;
}

fn bool OpenJob.scan_dir(&self, Path dir)
{
	@pool()
	{
		Path? gitignore_file = dir.append(tmem, ".gitignore");
		if (catch excuse = gitignore_file) return true;
		self.ignore.load_file(gitignore_file, (String)dir);
	};

	PathList? listing = path::ls(self.allocator, dir, no_dirs: false, recursive: false, relative: false);
	if (catch excuse = listing) return true;
	foreach (Path entry : listing)
	{
		bool is_dir = path::is_dir(entry);
		if (basename_is_ignored((String)entry)) continue;
		if (self.ignore.is_ignored((String)entry, is_dir)) continue;
		self.entries.push(entry);
		if (is_dir) self.pending.push(entry);
	}
	return true;
}

fn bool OpenJob.step(&self, usz budget)
{
	switch (self.phase)
	{
		case OpenPhase.SCAN:
			usz scanned = 0;
			while (self.pending.len() > 0 && scanned < budget)
			{
				Path dir = self.pending[self.pending.len() - 1];
				self.pending.remove_at(self.pending.len() - 1);
				scanned++;
				self.scanned_dirs++;
				self.scan_dir(dir);
			}
			if (self.pending.len() > 0) return false;
			if (self.entries.len() == 0 && !path::exists(self.root))
			{
				self.phase = OpenPhase.FAILED;
				return true;
			}
			self.phase = OpenPhase.SORT;
			return false;
		case OpenPhase.SORT:
			self.project.reset();
			self.project.root = (Path)self.root.copy(self.allocator);
			if (self.entries.len() > 1)
			{
				libc::qsort(self.entries.entries, (usz)self.entries.size, Path::size, &path_compare);
			}
			self.build_cursor = 0;
			self.phase = OpenPhase.BUILD_FOLDERS;
			return false;
		case OpenPhase.BUILD_FOLDERS:
			usz processed = 0;
			while (self.build_cursor < (usz)self.entries.len() && processed < budget)
			{
				Path entry = self.entries[(sz)self.build_cursor];
				self.build_cursor++;
				processed++;
				if (!path::is_dir(entry)) continue;
				self.project.ensure_folder((String)entry);
			}
			if (self.build_cursor >= (usz)self.entries.len())
			{
				self.build_cursor = 0;
				self.phase = OpenPhase.BUILD_CARDS;
			}
			return false;
		case OpenPhase.BUILD_CARDS:
			usz processed = 0;
			while (self.build_cursor < (usz)self.entries.len() && processed < budget)
			{
				Path entry = self.entries[(sz)self.build_cursor];
				self.build_cursor++;
				processed++;
				if (path::is_dir(entry)) continue;
				self.project.append_card((String)entry, { 0.0f, 0.0f });
			}
			if (self.build_cursor >= (usz)self.entries.len())
			{
				self.build_cursor = 0;
				self.phase = OpenPhase.LAYOUT;
			}
			return false;
		case OpenPhase.LAYOUT:
			self.project.rebuild_folder_index();
			self.project.focused = -1;
			self.phase = OpenPhase.DONE;
			return true;
		case OpenPhase.DONE:
		case OpenPhase.FAILED:
			return true;
	}
}

fn bool Project.open(&self, String new_root)
{
	OpenJob* job = open_job_create(self.allocator, self, new_root);
	while (!job.step(OPEN_BUILD_BUDGET))
	{
	}
	bool ok = job.phase == OpenPhase.DONE;
	open_job_destroy(job);
	if (ok)
	{
		self.layout();
		for (sz i = 0; i < self.folders.len(); i++) self.folders[i].collapsed = true;
	}
	return ok;
}

fn String? resolve_path(Allocator allocator, String arg)
{
	if (arg.len == 0) return RESOLVE_FAILED~;
	if (arg[0] == '~')
	{
		Path? home = path::home_directory(allocator);
		if (catch excuse = home) return RESOLVE_FAILED~;
		if (arg.len == 1) return (String)home;
		return ((Path)home).append(allocator, arg[2..]);
	}
	if (arg[0] == '/' || (arg.len > 1 && arg[1] == ':')) return arg.copy(allocator);
	Path? cwd = path::cwd(allocator);
	if (catch excuse = cwd) return RESOLVE_FAILED~;
	return cwd.append(allocator, arg);
}

fn bool is_valid_name(String name)
{
	if (name.len == 0 || name.len > 255) return false;
	if (name.compare_to(".") == 0 || name.compare_to("..") == 0) return false;
	for (usz i = 0; i < name.len; i++)
	{
		char c = name[i];
		if ((int)c < 32) return false;
		if (c == '/' || c == '\\' || c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|')
		{
			return false;
		}
	}
	return rl::is_file_name_valid((ZString)name.ptr);
}

fn String Project.folder_path(&self, int folder_index)
{
	if (folder_index < 0 || folder_index >= (int)self.folders.len()) return (String)self.root;
	return (String)self.folders[folder_index].path;
}

fn int Project.create_file(&self, int folder_index, String name, RLVector2 world_pos)
{
	if (!is_valid_name(name)) return -1;
	String dir = self.folder_path(folder_index);

	String candidate = collision_name(self.allocator, file_stem(name), file_ext(name), 0);
	Path? appended   = ((Path)dir).append(self.allocator, candidate);
	if (catch excuse = appended) return -1;
	Path dest = appended;

	int index = 1;
	while (path::exists(dest))
	{
		String alt = collision_name(self.allocator, file_stem(name), file_ext(name), index);
		Path? next = ((Path)dir).append(self.allocator, alt);
		if (catch excuse = next) return -1;
		dest = next;
		index++;
	}

	File? created = file::open(dest, "w");
	if (catch excuse = created) return -1;
	(void)created.close();

	self.focused = self.append_card((String)dest, world_pos);
	return self.focused;
}

fn int Project.create_folder_on_disk(&self, int parent_index, String name, RLVector2 world_pos)
{
	if (!is_valid_name(name)) return -1;
	String dir = self.folder_path(parent_index);

	Path? appended = ((Path)dir).append(self.allocator, name);
	if (catch excuse = appended) return -1;
	Path dest = appended;
	if (path::exists(dest)) return -1;
	if (catch excuse = path::mkdir(dest, recursive: false)) return -1;

	int index = self.add_folder((String)dest, parent_index);
	self.folders[index].bounds = {
		.x = world_pos[0],
		.y = world_pos[1],
		.width = ui::pxf(CLUSTER_COLLAPSED_WIDTH),
		.height = ui::pxf(CLUSTER_TITLE_HEIGHT),
	};
	return index;
}

fn void Project.remove_card(&self, int index)
{
	if (index < 0 || index >= (int)self.cards.len()) return;
	FileCard* card = &self.cards[index];
	editor::destroy_buffer(card, self.allocator);
	((String)card.path).free(self.allocator);
	card.name.free(self.allocator);
	self.cards.remove_at(index);
	self.cards_revision++;
	if (self.focused == index)
	{
		self.focused = -1;
	}
	else if (self.focused > index)
	{
		self.focused--;
	}
	if (self.selected == index)
	{
		self.selected = -1;
	}
	else if (self.selected > index)
	{
		self.selected--;
	}
}

fn bool Project.rename_card(&self, int index, String new_name)
{
	if (index < 0 || index >= (int)self.cards.len()) return false;
	if (!is_valid_name(new_name)) return false;

	FileCard* card = &self.cards[index];
	String dir     = rl::get_prev_directory_path((ZString)((String)card.path).ptr).str_view().copy(self.allocator);
	defer dir.free(self.allocator);

	Path? appended = ((Path)dir).append(self.allocator, new_name);
	if (catch excuse = appended) return false;
	Path dest = appended;
	defer ((String)dest).free(self.allocator);
	if (path::exists(dest)) return false;

	bool renamed = false;
	@pool()
	{
		renamed = libc::rename(((String)card.path).zstr_tcopy(), ((String)dest).zstr_tcopy()) == 0;
	};
	if (!renamed) return false;

	((String)card.path).free(self.allocator);
	card.path = (Path)((String)dest).copy(self.allocator);
	card.name.free(self.allocator);
	card.name = new_name.copy(self.allocator);
	card.folder = self.folder_for((String)card.path);
	self.cards_revision++;
	self.invalidate_bounds();
	editor::stamp_file(card);
	return true;
}

fn int Project.duplicate_card(&self, int index, RLVector2 world_pos)
{
	if (index < 0 || index >= (int)self.cards.len()) return -1;

	String src = (String)self.cards[index].path;
	String dir = rl::get_prev_directory_path((ZString)src.ptr).str_view().copy(self.allocator);
	defer dir.free(self.allocator);
	String stem = file_stem(src).copy(self.allocator);
	defer stem.free(self.allocator);
	String ext = file_ext(src).copy(self.allocator);
	defer ext.free(self.allocator);

	String name    = collision_name(self.allocator, stem, ext, 0);
	Path? appended = ((Path)dir).append(self.allocator, name);
	name.free(self.allocator);
	if (catch excuse = appended) return -1;
	Path dest = appended;

	int counter = 1;
	while (path::exists(dest))
	{
		String alt = collision_name(self.allocator, stem, ext, counter);
		Path? next = ((Path)dir).append(self.allocator, alt);
		alt.free(self.allocator);
		if (catch excuse = next)
		{
			((String)dest).free(self.allocator);
			return -1;
		}
		((String)dest).free(self.allocator);
		dest = next;
		counter++;
	}

	char[]? data = file::load(self.allocator, src);
	if (catch excuse = data)
	{
		((String)dest).free(self.allocator);
		return -1;
	}
	defer alloc::free(self.allocator, data.ptr);
	if (catch excuse = file::save(dest, data))
	{
		((String)dest).free(self.allocator);
		return -1;
	}

	RLVector2 offset = { world_pos[0] + 24.0f, world_pos[1] + 24.0f };
	int result       = self.append_card((String)dest, offset);
	((String)dest).free(self.allocator);
	return result;
}

fn bool Project.delete_card_file(&self, int index)
{
	if (index < 0 || index >= (int)self.cards.len()) return false;
	Path path = self.cards[index].path;
	if (catch excuse = path::delete(path)) return false;
	self.remove_card(index);
	return true;
}

fn int Project.focus(&self, int index)
{
	if (index < 0 || index >= (int)self.cards.len()) return self.focused;
	if (index == self.focused) return index;
	FileCard card = self.cards[index];
	self.cards.remove_at(index);
	self.cards.push(card);
	self.focused = (int)(self.cards.len() - 1);
	self.cards[self.focused].selection_anchor = self.cards[self.focused].cursor;
	return self.focused;
}

fn FileCard* Project.focused_card(&self)
{
	if (self.focused < 0 || self.focused >= (int)self.cards.len()) return null;
	return &self.cards[self.focused];
}

fn int Project.next_visible_card(&self, int from, int dir)
{
	int count = (int)self.cards.len();
	if (count == 0) return -1;
	int step    = dir >= 0 ? 1 : -1;
	int current = from;
	for (int i = 0; i < count; i++)
	{
		current += step;
		if (current < 0) current = count - 1;
		if (current >= count) current = 0;
		if (self.card_visible(current)) return current;
	}
	return -1;
}

fn FileCard* Project.selected_card(&self)
{
	if (self.selected < 0 || self.selected >= (int)self.cards.len()) return null;
	return &self.cards[self.selected];
}

fn void Project.select_card(&self, int index)
{
	self.selected = index;
	self.selected_cluster = -1;
}

fn void Project.select_folder(&self, int index)
{
	self.selected = -1;
	self.selected_cluster = index;
}

fn void Project.clear_selection(&self)
{
	self.selected = -1;
	self.selected_cluster = -1;
}

fn void Project.select_nav_item(&self, NavItem item)
{
	if (item.folder)
	{
		self.select_folder(item.index);
	}
	else
	{
		self.select_card(item.index);
	}
}

fn bool Project.is_selected_item(&self, NavItem item)
{
	if (item.folder) return self.selected_cluster == item.index;
	return self.selected_cluster < 0 && self.selected == item.index;
}

fn RLVector2 Project.nav_item_center(&self, NavItem item)
{
	if (item.folder)
	{
		Rect r = self.cluster_visual_bounds(item.index);
		return { r.x + r.width / 2.0f, r.y + r.height / 2.0f };
	}
	return self.cards[item.index].center();
}

fn void Project.nav_items(&self, List{NavItem}* out)
{
	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (self.cards[i].folder != self.current_folder) continue;
		if (!self.card_visible((int)i)) continue;
		out.push({ .folder = false, .index = (int)i });
	}
	for (sz i = 0; i < self.folders.len(); i++)
	{
		if (self.folders[i].parent != self.current_folder) continue;
		if (!self.cluster_visible((int)i)) continue;
		out.push({ .folder = true, .index = (int)i });
	}
}

fn Rect Project.selected_item_rect(&self)
{
	if (self.selected_cluster >= 0 && self.selected_cluster < (int)self.folders.len())
	{
		return self.cluster_visual_bounds(self.selected_cluster);
	}
	FileCard* card = self.selected_card();
	if (card) return card.rect;
	return { .x = 0.0f, .y = 0.0f, .width = 0.0f, .height = 0.0f };
}

fn void Project.ensure_selection(&self)
{
	if (self.current_folder != ROOT_FOLDER)
	{
		if (self.current_folder < 0 || self.current_folder >= (int)self.folders.len() || !self.cluster_visible(
			self.current_folder
		))
		{
			self.current_folder = ROOT_FOLDER;
		}
	}
	if (self.selected_cluster >= 0 && self.selected_cluster < (int)self.folders.len() && self.cluster_visible(
		self.selected_cluster
	))
	{
		return;
	}
	if (self.selected >= 0 && self.selected < (int)self.cards.len() && self.card_visible(self.selected))
	{
		self.selected_cluster = -1;
		return;
	}
	if (self.focused >= 0 && self.focused < (int)self.cards.len() && self.card_visible(self.focused))
	{
		self.current_folder = self.cards[self.focused].folder;
		self.select_card(self.focused);
		return;
	}
	@pool()
	{
		List{NavItem} items;
		items.init(tmem);
		self.nav_items(&items);
		if (items.len() > 0)
		{
			self.select_nav_item(items[0]);
		}
		else
		{
			self.clear_selection();
		}
	};
}

fn bool Project.item_in_direction(&self, Dir dir, NavItem* out)
{
	RLVector2 origin;
	bool have_origin = false;
	if (self.selected_cluster >= 0 && self.selected_cluster < (int)self.folders.len())
	{
		Rect r = self.cluster_visual_bounds(self.selected_cluster);
		origin = { r.x + r.width / 2.0f, r.y + r.height / 2.0f };
		have_origin = true;
	}
	else if (self.selected >= 0 && self.selected < (int)self.cards.len())
	{
		origin = self.cards[self.selected].center();
		have_origin = true;
	}
	if (!have_origin) return false;

	bool best        = false;
	float best_score = 0.0f;
	@pool()
	{
		List{NavItem} items;
		items.init(tmem);
		self.nav_items(&items);
		for (sz i = 0; i < items.len(); i++)
		{
			NavItem item = items[i];
			if (self.is_selected_item(item)) continue;
			RLVector2 c = self.nav_item_center(item);
			float dx    = c[0] - origin[0];
			float dy    = c[1] - origin[1];
			float primary;
			float secondary;
			if (dir == Dir.LEFT)
			{
				if (dx >= -0.5f) continue;
				primary = -dx;
				secondary = math::abs(dy);
			}
			else if (dir == Dir.RIGHT)
			{
				if (dx <= 0.5f) continue;
				primary = dx;
				secondary = math::abs(dy);
			}
			else if (dir == Dir.UP)
			{
				if (dy >= -0.5f) continue;
				primary = -dy;
				secondary = math::abs(dx);
			}
			else
			{
				if (dy <= 0.5f) continue;
				primary = dy;
				secondary = math::abs(dx);
			}
			float score = primary + secondary * 2.0f;
			if (!best || score < best_score)
			{
				best = true;
				best_score = score;
				*out = item;
			}
		}
	};
	return best;
}

fn bool Project.cycle_nav_item(&self, int dir, NavItem* out)
{
	bool found = false;
	@pool()
	{
		List{NavItem} items;
		items.init(tmem);
		self.nav_items(&items);
		if (items.len() == 0) return false;
		int current = -1;
		for (sz i = 0; i < items.len(); i++)
		{
			if (self.is_selected_item(items[i]))
			{
				current = (int)i;
				break;
			}
		}
		int count = (int)items.len();
		int next;
		if (current < 0)
		{
			next = dir >= 0 ? 0 : count - 1;
		}
		else
		{
			next = (current + (dir >= 0 ? 1 : -1) + count) % count;
		}
		*out = items[(usz)next];
		found = true;
	};
	return found;
}

fn void Project.enter_folder(&self, int index)
{
	if (index < 0 || index >= (int)self.folders.len()) return;
	self.folders[index].collapsed = false;
	self.current_folder = index;
	self.grabbing = false;
	self.selected = -1;
	self.selected_cluster = -1;
	@pool()
	{
		List{NavItem} items;
		items.init(tmem);
		self.nav_items(&items);
		if (items.len() > 0) self.select_nav_item(items[0]);
	};
	self.invalidate_bounds();
}

fn bool Project.leave_folder(&self)
{
	self.grabbing = false;
	if (self.current_folder == ROOT_FOLDER)
	{
		bool had = self.selected >= 0 || self.selected_cluster >= 0;
		self.clear_selection();
		return had;
	}
	int child = self.current_folder;
	self.current_folder = self.folders[child].parent;
	self.select_folder(child);
	return true;
}

fn void Project.move_selected(&self, RLVector2 delta)
{
	if (self.selected_cluster >= 0 && self.selected_cluster < (int)self.folders.len())
	{
		self.move_cluster(self.selected_cluster, delta);
		return;
	}
	if (self.selected >= 0 && self.selected < (int)self.cards.len())
	{
		self.cards[self.selected].move_by(delta);
		self.invalidate_bounds();
	}
}

fn bool Project.has_selected_item(&self)
{
	return self.selected >= 0 || self.selected_cluster >= 0;
}

fn void Project.minimize_selected(&self, EditorMetrics metrics)
{
	if (self.selected_cluster >= 0) return;
	if (self.selected < 0 || self.selected >= (int)self.cards.len()) return;
	FileCard* card = &self.cards[self.selected];
	card.rect.width = editor::min_card_width(metrics);
	card.rect.height = editor::min_card_height(metrics);
	self.invalidate_bounds();
}

fn bool is_double_click(double now, RLVector2 pos, double last_time, RLVector2 last_pos)
{
	double delta = now - last_time;
	if (delta < 0.0 || delta > DOUBLE_CLICK_SECONDS) return false;
	float dx = pos[0] - last_pos[0];
	float dy = pos[1] - last_pos[1];
	return dx * dx + dy * dy <= DOUBLE_CLICK_DIST * DOUBLE_CLICK_DIST;
}

fn bool Project.register_click(&self, double now, RLVector2 pos)
{
	bool double_click = is_double_click(now, pos, self.last_click_time, self.last_click_pos);
	self.last_click_time = now;
	self.last_click_pos = pos;
	return double_click;
}

fn void Project.reveal_focused(&self, EditorMetrics metrics)
{
	FileCard* card = self.focused_card();
	if (!card || !card.buffer) return;
	Rect text = editor::text_rect(card.rect, metrics, card.buffer.line_count());
	card.scroll = editor::scroll_to_reveal(card.buffer, metrics, text.height, card.cursor, card.scroll);
	card.scroll_x = editor::scroll_x_to_reveal(card.buffer, metrics, text.width, card.cursor, card.scroll_x);
}

fn bool Project.has_selection(&self)
{
	FileCard* card = self.focused_card();
	if (!card || !card.buffer) return false;
	return editor::has_selection(card.selection_anchor, card.cursor);
}

fn void Project.select_all(&self)
{
	FileCard* card = self.focused_card();
	if (!card || !card.buffer) return;
	card.selection_anchor = 0;
	card.cursor = card.buffer.length();
	usz line = card.buffer.line_of(card.cursor);
	card.preferred_column = editor::column_for_offset(card.buffer, line, card.cursor);
}

fn bool Project.copy_selection(&self)
{
	FileCard* card = self.focused_card();
	if (!card || !card.buffer) return false;
	usz start = 0;
	usz end   = 0;
	editor::selection_range(card.selection_anchor, card.cursor, &start, &end);
	if (start >= end) return false;
	@pool()
	{
		String text = card.buffer.slice(start, end - start, tmem);
		rl::set_clipboard_text(text.zstr_tcopy());
	};
	return true;
}

fn bool Project.cut_selection(&self, double now)
{
	FileCard* card = self.focused_card();
	if (!card || !card.buffer || !card.history) return false;
	usz start = 0;
	usz end   = 0;
	editor::selection_range(card.selection_anchor, card.cursor, &start, &end);
	if (start >= end) return false;
	if (!self.copy_selection()) return false;
	card.cursor = card.history.replace(card.buffer, start, end - start, "", now);
	card.selection_anchor = card.cursor;
	return true;
}

fn bool Project.paste_clipboard(&self, double now)
{
	FileCard* card = self.focused_card();
	if (!card || !card.buffer || !card.history) return false;
	ZString clip = rl::get_clipboard_text();
	if (!clip) return false;
	String text = clip.str_view();
	if (text.len == 0) return false;
	usz start = 0;
	usz end   = 0;
	editor::selection_range(card.selection_anchor, card.cursor, &start, &end);
	card.cursor = card.history.replace(card.buffer, start, end - start, text, now);
	card.selection_anchor = card.cursor;
	return true;
}

fn int Project.hit_test(&self, RLVector2 world)
{
	self.ensure_grid();
	int best = -1;
	@pool()
	{
		List{int} candidates;
		candidates.init(tmem);
		self.grid.query_point(world, &candidates);
		for (sz i = 0; i < candidates.len(); i++)
		{
			int index = candidates[i];
			if (!self.card_visible(index)) continue;
			if (!self.cards[index].contains(world)) continue;
			if (index > best) best = index;
		}
	};
	return best;
}

fn void Project.toggle_collapse(&self, int index)
{
	if (index < 0 || index >= (int)self.folders.len()) return;
	if (!self.folders[index].collapsed)
	{
		self.folders[index].bounds = self.cluster_bounds(index);
	}
	self.folders[index].collapsed = !self.folders[index].collapsed;
	self.grid_dirty = true;
	self.content_bounds_valid = false;
}

fn void Project.move_cluster(&self, int index, RLVector2 delta)
{
	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (path_is_inside((String)self.folders[index].path, (String)self.cards[i].path))
		{
			self.cards[i].move_by(delta);
		}
	}
	for (sz i = 0; i < self.folders.len(); i++)
	{
		if (path_is_inside((String)self.folders[index].path, (String)self.folders[i].path))
		{
			self.folders[i].bounds.x += delta[0];
			self.folders[i].bounds.y += delta[1];
		}
	}
	self.invalidate_bounds();
}

fn bool Project.move_card_to_folder(&self, int card_index, int folder_index)
{
	String from = (String)self.cards[card_index].path;
	String dir  = folder_index < 0 ? (String)self.root : (String)self.folders[folder_index].path;

	String name    = collision_name(self.allocator, file_stem(from), file_ext(from), 0);
	Path? appended = ((Path)dir).append(self.allocator, name);
	if (catch excuse = appended) return false;
	Path dest = appended;

	int index = 1;
	while (path::exists(dest))
	{
		String alt = collision_name(self.allocator, file_stem(from), file_ext(from), index);
		Path? next = ((Path)dir).append(self.allocator, alt);
		if (catch excuse = next) return false;
		dest = next;
		index++;
	}

	if (libc::rename((ZString)from.ptr, (ZString)dest.ptr) != 0)
	{
		char[]? data = file::load(self.allocator, from);
		if (catch excuse = data) return false;
		if (catch excuse = file::save(dest, data)) return false;
		if (catch excuse = file::delete(from)) return false;
	}

	String dest_str = (String)dest;
	self.cards[card_index].path = (Path)dest_str.copy(self.allocator);
	self.cards[card_index].name = rl::get_file_name((ZString)dest_str.ptr).str_view().copy(self.allocator);
	self.cards[card_index].folder = self.folder_for(dest_str);
	self.cards_revision++;
	self.invalidate_bounds();
	return true;
}

fn void Project.end_card_drag(&self)
{
	self.drag_card = false;
	int current = self.folder_for((String)self.cards[self.drag_index].path);
	int target  = self.folder_at(self.cards[self.drag_index].center());
	if (target != current)
	{
		self.move_card_to_folder(self.drag_index, target);
	}
}

fn bool Project.pointer_over_ui(&self, RLVector2 world)
{
	return self.drag_card || self.drag_cluster || self.hit_test(world) >= 0 || self.cluster_hit(world) >= 0;
}

fn void Project.update(
	&self,
	Canvas* canvas,
	keymap::Keymap* keymap,
	bool suppress_input,
	EditorMetrics metrics,
	bool pointer_blocked,
	bool* out_changed
)
{
	RLVector2 mouse = rl::get_mouse_position();
	RLVector2 world = canvas.screen_to_world(mouse);
	canvas.block_zoom = false;
	self.hover_card = pointer_blocked ? -1 : self.hit_test(world);

	float wheel = rl::get_mouse_wheel_move();
	if (wheel != 0.0f && !pointer_blocked)
	{
		int wheel_hit = self.hit_test(world);
		if (wheel_hit >= 0 && self.cards[wheel_hit].open)
		{
			int index = self.focus(wheel_hit);
			editor::ensure_buffer(&self.cards[index], self.allocator);
			if (self.cards[index].preview && markdown::is_markdown_path((String)self.cards[index].path))
			{
				Rect area = editor::inner_rect(self.cards[index].rect, metrics);
				float height = markdown::view_content_height(
					self.cards[index].view,
					self.cards[index].buffer,
					area.width,
					metrics.char_width,
					metrics.font_size,
					metrics.line_height
				);
				float max = height - area.height;
				if (max < 0.0f) max = 0.0f;
				float value = self.cards[index].preview_scroll - wheel * metrics.line_height * (float)editor::settings()
					.wheel_scroll_lines;
				if (value < 0.0f) value = 0.0f;
				if (value > max) value = max;
				self.cards[index].preview_scroll = value;
			}
			else if (self.cards[index].buffer)
			{
				usz line_count = self.cards[index].buffer.line_count();
				Rect text      = editor::text_rect(self.cards[index].rect, metrics, line_count);
				float max      = editor::max_scroll(line_count, metrics, text.height);
				float value    = self.cards[index].scroll - wheel * metrics.line_height * (float)editor::settings()
					.wheel_scroll_lines;
				if (value < 0.0f) value = 0.0f;
				if (value > max) value = max;
				self.cards[index].scroll = value;
			}
			canvas.block_zoom = true;
		}
	}

	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT) && canvas.pointer_over_ui && !pointer_blocked)
	{
		completion::completion_close();
		int card_hit = self.hit_test(world);
		if (card_hit >= 0)
		{
			bool double_click         = self.register_click(rl::get_time(), world);
			editor::CardRegion region = editor::region_at(&self.cards[card_hit], world, metrics, canvas.camera);
			if (region == editor::CardRegion.HANDLE)
			{
				int handle = self.cards[card_hit].resize_handle_at(world, canvas.camera);
				self.resizing = true;
				self.resize_card = self.focus(card_hit);
				self.resize_handle = handle;
				self.drag_world = world;
			}
			else if (region == editor::CardRegion.CLOSE)
			{
				FileCard* card = &self.cards[card_hit];
				if (card.ephemeral)
				{
					self.discard_ephemeral(-1);
				}
				else if (card.buffer)
				{
					if (card.dirty)
					{
						self.pending_close = self.focus(card_hit);
					}
					else
					{
						(void)editor::unload_buffer(card, self.allocator);
					}
				}
			}
			else if (region == editor::CardRegion.MARKER)
			{
				self.cards[card_hit].open = !self.cards[card_hit].open;
			}
			else if (region == editor::CardRegion.PREVIEW)
			{
				self.toggle_preview(card_hit);
			}
			else if (region == editor::CardRegion.BODY)
			{
				int index      = self.focus(card_hit);
				FileCard* card = &self.cards[index];
				editor::ensure_buffer(card, self.allocator);
				if (card.preview)
				{
					if (card.buffer && card.view)
					{
						Rect area     = editor::inner_rect(card.rect, metrics);
						float local_y = world[1] - area.y + card.preview_scroll;
						usz offset    = markdown::view_block_offset_at(card.view, local_y);
						if (offset > card.buffer.length()) offset = card.buffer.length();
						card.preview = false;
						card.cursor = offset;
						card.selection_anchor = offset;
						usz line = card.buffer.line_of(card.cursor);
						card.preferred_column = editor::column_for_offset(card.buffer, line, card.cursor);
						Rect text = editor::text_rect(card.rect, metrics, card.buffer.line_count());
						card.scroll = editor::scroll_to_reveal(
							card.buffer,
							metrics,
							text.height,
							card.cursor,
							card.scroll
						);
						card.scroll_x = editor::scroll_x_to_reveal(
							card.buffer,
							metrics,
							text.width,
							card.cursor,
							card.scroll_x
						);
						if (card.history) card.history.break_coalescing();
						self.last_input_time = rl::get_time();
					}
					else
					{
						card.preview = false;
					}
				}
				else if (card.buffer)
				{
					Rect text       = editor::text_rect(card.rect, metrics, card.buffer.line_count());
					RLVector2 local = { world[0] - text.x, world[1] - text.y };
					usz offset = editor::offset_for_point(
						card.buffer,
						local[0],
						local[1],
						card.scroll,
						card.scroll_x,
						metrics
					);
					if (double_click)
					{
						usz start = 0;
						usz end   = 0;
						editor::word_range(card.buffer, offset, &start, &end);
						card.selection_anchor = start;
						card.cursor = end;
					}
					else
					{
						card.cursor = offset;
						card.selection_anchor = offset;
					}
					usz line = card.buffer.line_of(card.cursor);
					card.preferred_column = editor::column_for_offset(card.buffer, line, card.cursor);
					if (card.history) card.history.break_coalescing();
					self.last_input_time = rl::get_time();
					if (ctrl_down())
					{
						lsp::lsp_request_definition((String)card.path, card.buffer, offset);
					}
					if (!ctrl_down()) self.selecting = true;
				}
				else
				{
					if (!ctrl_down()) self.selecting = true;
				}
			}
			else
			{
				int index      = self.focus(card_hit);
				FileCard* card = &self.cards[index];
				if (double_click) card.open = !card.open;
				self.drag_index = index;
				self.drag_card = true;
				self.drag_world = world;
			}
		}
		else
		{
			int cluster_hit = self.cluster_hit(world);
			if (cluster_hit >= 0)
			{
				self.drag_cluster = true;
				self.drag_cluster_index = cluster_hit;
				self.drag_cluster_title = self.cluster_title_hit(cluster_hit, world);
				self.cluster_moved = false;
				self.drag_world = world;
			}
		}
	}

	if (self.selecting)
	{
		if (!rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
		{
			self.selecting = false;
		}
		else
		{
			FileCard* card = self.focused_card();
			if (card && card.buffer)
			{
				Rect text       = editor::text_rect(card.rect, metrics, card.buffer.line_count());
				RLVector2 local = { world[0] - text.x, world[1] - text.y };
				card.cursor = editor::offset_for_point(
					card.buffer,
					local[0],
					local[1],
					card.scroll,
					card.scroll_x,
					metrics
				);
				usz line = card.buffer.line_of(card.cursor);
				card.preferred_column = editor::column_for_offset(card.buffer, line, card.cursor);
			}
		}
	}

	if (self.drag_card)
	{
		if (!rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
		{
			self.end_card_drag();
		}
		else
		{
			RLVector2 delta = { world[0] - self.drag_world[0], world[1] - self.drag_world[1] };
			self.cards[self.drag_index].move_by(delta);
			self.invalidate_bounds_for_card(self.drag_index);
			self.drag_world = world;
		}
	}

	if (self.drag_cluster)
	{
		if (!rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
		{
			if (!self.cluster_moved && self.drag_cluster_title) self.toggle_collapse(self.drag_cluster_index);
			self.drag_cluster = false;
		}
		else
		{
			RLVector2 delta = { world[0] - self.drag_world[0], world[1] - self.drag_world[1] };
			if (math::abs(delta[0]) > 0.01f || math::abs(delta[1]) > 0.01f) self.cluster_moved = true;
			if (self.cluster_moved)
			{
				self.move_cluster(self.drag_cluster_index, delta);
				self.drag_world = world;
			}
		}
	}

	if (self.resizing)
	{
		if (!rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
		{
			self.resizing = false;
		}
		else
		{
			RLVector2 delta = { world[0] - self.drag_world[0], world[1] - self.drag_world[1] };
			float min_w     = editor::min_card_width(metrics);
			float min_h     = editor::min_card_height(metrics);
			self.cards[self.resize_card].resize_from(self.resize_handle, delta, min_w, min_h);
			self.invalidate_bounds_for_card(self.resize_card);
			self.drag_world = world;
		}
	}

	if (!pointer_blocked && !self.resizing && !rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
	{
		int hover  = self.hit_test(world);
		int handle = hover >= 0 ? self.cards[hover].resize_handle_at(world, canvas.camera) : -1;
		int cursor = (int)(handle < 0 ? rl::RLMouseCursor.DEFAULT : cursor_for_handle(handle));
		if (cursor != self.last_cursor)
		{
			rl::set_mouse_cursor((RLMouseCursor)cursor);
			self.last_cursor = cursor;
		}
	}

	self.refresh_sleep(expand_rect(visible_world_rect(canvas.camera), DRAW_CULL_MARGIN), canvas.camera.zoom);
	self.poll_external(rl::get_time());
	self.handle_keyboard(keymap, suppress_input, metrics, out_changed);
}

fn RLMouseCursor cursor_for_handle(int handle)
{
	if (handle == 0 || handle == 4) return rl::RLMouseCursor.RESIZE_NWSE;
	if (handle == 2 || handle == 6) return rl::RLMouseCursor.RESIZE_NESW;
	if (handle == 1 || handle == 5) return rl::RLMouseCursor.RESIZE_NS;
	if (handle == 3 || handle == 7) return rl::RLMouseCursor.RESIZE_EW;
	return rl::RLMouseCursor.DEFAULT;
}

fn void Project.refresh_sleep(&self, Rect visible, float zoom)
{
	int awake  = 0;
	int asleep = 0;
	for (sz i = 0; i < self.cards.len(); i++)
	{
		bool is_focused = (int)i == self.focused;
		bool big_enough = self.cards[i].rect.width * zoom >= CARD_MIN_DRAW_PX;
		bool on_screen  = self.card_visible(
			(int)i
		) && self.cards[i].open && big_enough && rect_intersects(self.cards[i].rect, visible);
		bool wake       = is_focused || on_screen;
		self.cards[i].sleeping = !wake;
		if (wake)
		{
			awake++;
		}
		else
		{
			asleep++;
		}
	}
	self.awake_count = awake;
	self.asleep_count = asleep;
}

fn void Project.poll_external(&self, double now)
{
	if (self.pending_reload >= 0) return;
	if (now - self.last_poll < POLL_SECONDS) return;
	self.last_poll = now;
	for (sz i = 0; i < self.cards.len(); i++)
	{
		FileCard* card = &self.cards[i];
		if (!card.buffer || card.missing || card.sleeping) continue;
		if (editor::file_changed(card))
		{
			self.pending_reload = (int)i;
			return;
		}
	}
}

enum EditorMove : int
{
	LEFT,
	RIGHT,
	UP,
	DOWN,
	LINE_START,
	LINE_END,
	PAGE_UP,
	PAGE_DOWN,
}

fn FileCard* Project.focused_editable_card(&self)
{
	if (self.focused < 0 || self.focused >= (int)self.cards.len()) return null;
	FileCard* card = &self.cards[self.focused];
	if (!card.open) return null;
	editor::ensure_buffer(card, self.allocator);
	if (!card.buffer) return null;
	return card;
}

fn void Project.finish_edit(&self, EditorMetrics metrics)
{
	FileCard* card = self.focused_editable_card();
	if (!card) return;
	card.dirty = true;
	if (card.highlight) card.highlight.mark_dirty();
	if (card.view) markdown::view_mark_dirty(card.view);
	lsp::lsp_did_change((String)card.path, card.buffer);
	self.last_input_time = rl::get_time();
	self.reveal_focused(metrics);
}

fn bool Project.editor_undo(&self)
{
	FileCard* card = self.focused_editable_card();
	if (!card) return false;
	usz cursor = card.cursor;
	if (!card.history.undo(card.buffer, &cursor)) return false;
	card.cursor = cursor;
	card.selection_anchor = cursor;
	return true;
}

fn bool Project.editor_redo(&self)
{
	FileCard* card = self.focused_editable_card();
	if (!card) return false;
	usz cursor = card.cursor;
	if (!card.history.redo(card.buffer, &cursor)) return false;
	card.cursor = cursor;
	card.selection_anchor = cursor;
	return true;
}

fn bool Project.editor_newline(&self)
{
	FileCard* card = self.focused_editable_card();
	if (!card) return false;
	editor::EditorSettings es = editor::settings();
	usz start                 = 0;
	usz end                   = 0;
	editor::selection_range(card.selection_anchor, card.cursor, &start, &end);
	card.history.break_coalescing();
	String text = editor::newline_text(
		card.buffer,
		start,
		es.auto_indent,
		es.indent_spaces,
		es.indent_width,
		self.allocator
	);
	card.cursor = card.history.replace(card.buffer, start, end - start, text, rl::get_time());
	text.free(self.allocator);
	card.selection_anchor = card.cursor;
	return true;
}

fn bool Project.editor_indent(&self)
{
	FileCard* card = self.focused_editable_card();
	if (!card) return false;
	editor::EditorSettings es = editor::settings();
	usz start                 = 0;
	usz end                   = 0;
	editor::selection_range(card.selection_anchor, card.cursor, &start, &end);
	card.history.break_coalescing();
	String unit = editor::indent_unit(self.allocator, es.indent_spaces, es.indent_width);
	card.cursor = card.history.replace(card.buffer, start, end - start, unit, rl::get_time());
	unit.free(self.allocator);
	card.selection_anchor = card.cursor;
	return true;
}

fn bool Project.editor_outdent(&self)
{
	FileCard* card = self.focused_editable_card();
	if (!card) return false;
	editor::EditorSettings es = editor::settings();
	usz start                 = card.buffer.line_start(card.buffer.line_of(card.cursor));
	usz count                 = editor::outdent_count(card.buffer, card.cursor, es.indent_spaces, es.indent_width);
	if (count == 0) return false;
	card.history.break_coalescing();
	card.cursor = card.history.replace(card.buffer, start, count, "", rl::get_time());
	card.selection_anchor = card.cursor;
	return true;
}

fn bool Project.editor_delete(&self, bool back)
{
	FileCard* card = self.focused_editable_card();
	if (!card) return false;
	PieceTable* table = card.buffer;
	History* history  = card.history;
	double now        = rl::get_time();
	usz start         = 0;
	usz end           = 0;
	editor::selection_range(card.selection_anchor, card.cursor, &start, &end);
	if (start < end)
	{
		card.cursor = history.replace(table, start, end - start, "", now);
	}
	else if (back)
	{
		card.cursor = history.backspace(table, card.cursor, now);
	}
	else
	{
		card.cursor = history.delete_forward(table, card.cursor, now);
	}
	card.selection_anchor = card.cursor;
	return true;
}

fn void Project.editor_move(&self, EditorMove move, EditorMetrics metrics)
{
	FileCard* card = self.focused_editable_card();
	if (!card) return;
	PieceTable* table = card.buffer;
	History* history  = card.history;
	bool shift        = shift_down();
	bool vertical     = false;
	history.break_coalescing();
	switch (move)
	{
		case EditorMove.LEFT:
			card.cursor = editor::cursor_prev(table, card.cursor);
			break;
		case EditorMove.RIGHT:
			card.cursor = editor::cursor_next(table, card.cursor);
			break;
		case EditorMove.LINE_START:
			card.cursor = editor::cursor_home(table, card.cursor);
			break;
		case EditorMove.LINE_END:
			card.cursor = editor::cursor_end(table, card.cursor);
			break;
		case EditorMove.UP:
			card.cursor = editor::cursor_up(table, card.cursor, card.preferred_column, &card.preferred_column);
			vertical = true;
			break;
		case EditorMove.DOWN:
			card.cursor = editor::cursor_down(table, card.cursor, card.preferred_column, &card.preferred_column);
			vertical = true;
			break;
		case EditorMove.PAGE_UP:

			{
				Rect page_text = editor::text_rect(card.rect, metrics, table.line_count());
				sz rows        = (sz)(page_text.height / metrics.line_height);
				if (rows < 1) rows = 1;
				card.cursor = editor::cursor_page(
					table,
					card.cursor,
					-rows,
					card.preferred_column,
					&card.preferred_column
				);
				vertical = true;
				break;
			}
		case EditorMove.PAGE_DOWN:

			{
				Rect page_text = editor::text_rect(card.rect, metrics, table.line_count());
				sz rows        = (sz)(page_text.height / metrics.line_height);
				if (rows < 1) rows = 1;
				card.cursor = editor::cursor_page(
					table,
					card.cursor,
					rows,
					card.preferred_column,
					&card.preferred_column
				);
				vertical = true;
				break;
			}
	}
	if (!shift) card.selection_anchor = card.cursor;
	if (!vertical)
	{
		usz line = table.line_of(card.cursor);
		card.preferred_column = editor::column_for_offset(table, line, card.cursor);
	}
	self.reveal_focused(metrics);
}

fn void Project.editor_exit(&self)
{
	self.focused = -1;
}

fn bool Project.completion_accept_cmd(&self, EditorMetrics metrics)
{
	FileCard* card = self.focused_editable_card();
	if (!card) return false;
	usz new_cursor = completion::completion_accept(card.buffer, card.history, card.cursor, rl::get_time());
	bool changed   = new_cursor != card.cursor;
	if (changed)
	{
		card.cursor = new_cursor;
		card.selection_anchor = new_cursor;
		self.finish_edit(metrics);
	}
	else
	{
		self.reveal_focused(metrics);
	}
	return changed;
}

fn bool ctrl_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_CONTROL) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_CONTROL);
}

fn bool shift_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_SHIFT) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SHIFT);
}

fn void Project.handle_keyboard(
	&self,
	keymap::Keymap* keymap,
	bool suppress_input,
	EditorMetrics metrics,
	bool* out_changed
)
{
	if (suppress_input) return;

	FileCard* card = self.focused_editable_card();
	if (!card) return;

	PieceTable* table = card.buffer;
	History* history  = card.history;
	double now        = rl::get_time();
	bool changed      = false;

	if (completion::completion_is_open())
	{
		if (keymap.pressed((int)commands::CommandId.COMPLETION_CLOSE, commands::CTX_COMPLETION))
		{
			completion::completion_close();
			return;
		}
		if (keymap.pressed_repeat(
			(int)commands::CommandId.COMPLETION_PREV,
			commands::CTX_COMPLETION
		) || (ctrl_down() && rl::is_key_pressed(rl::RLKeyboardKey.P)))
		{
			completion::completion_move(-1);
			return;
		}
		if (keymap.pressed_repeat(
			(int)commands::CommandId.COMPLETION_NEXT,
			commands::CTX_COMPLETION
		) || (ctrl_down() && rl::is_key_pressed(rl::RLKeyboardKey.N)))
		{
			completion::completion_move(1);
			return;
		}
		if (keymap.pressed_repeat(
			(int)commands::CommandId.COMPLETION_ACCEPT,
			commands::CTX_COMPLETION
		) || rl::is_key_pressed(rl::RLKeyboardKey.TAB) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.TAB))
		{
			if (self.completion_accept_cmd(metrics) && out_changed) *out_changed = true;
			return;
		}
	}

	if (keymap.pressed((int)commands::CommandId.EXIT_EDITOR, commands::CTX_EDIT))
	{
		self.focused = -1;
		return;
	}

	if (keymap.pressed((int)commands::CommandId.UNDO, commands::CTX_EDIT))
	{
		if (self.editor_undo()) changed = true;
	}
	if (keymap.pressed(
		(int)commands::CommandId.REDO,
		commands::CTX_EDIT
	) || (ctrl_down() && shift_down() && rl::is_key_pressed(rl::RLKeyboardKey.Z)))
	{
		if (self.editor_redo()) changed = true;
	}

	if (keymap.pressed_repeat((int)commands::CommandId.NEWLINE, commands::CTX_EDIT))
	{
		if (self.editor_newline()) changed = true;
	}
	if (keymap.pressed_repeat((int)commands::CommandId.INDENT, commands::CTX_EDIT))
	{
		if (self.editor_indent()) changed = true;
	}
	if (keymap.pressed_repeat((int)commands::CommandId.OUTDENT, commands::CTX_EDIT))
	{
		if (self.editor_outdent()) changed = true;
	}
	if (keymap.pressed_repeat((int)commands::CommandId.DELETE_BACK, commands::CTX_EDIT))
	{
		if (self.editor_delete(true)) changed = true;
	}
	if (keymap.pressed_repeat((int)commands::CommandId.DELETE_FORWARD, commands::CTX_EDIT))
	{
		if (self.editor_delete(false)) changed = true;
	}

	if (!ctrl_down())
	{
		usz start = 0;
		usz end   = 0;
		editor::selection_range(card.selection_anchor, card.cursor, &start, &end);

		char[64] typed;
		usz typed_len = 0;
		int codepoint = rl::get_char_pressed();
		while (codepoint != 0)
		{
			if (codepoint >= 32 && codepoint != 127)
			{
				char[4] encoded;
				int count = editor::utf8_encode(codepoint, &encoded[0]);
				if (typed_len + (usz)count <= typed.len)
				{
					for (int i = 0; i < count; i++) typed[typed_len + (usz)i] = encoded[i];
					typed_len += (usz)count;
				}
			}
			codepoint = rl::get_char_pressed();
		}
		if (typed_len > 0)
		{
			String text = (String)typed[0:typed_len];
			card.cursor = history.replace(table, start, end - start, text, now);
			card.selection_anchor = card.cursor;
			changed = true;
			if (!completion::completion_is_open())
			{
				String[] triggers = lsp::lsp_completion_triggers((String)card.path);
				for (usz t = 0; t < triggers.len; t++)
				{
					if (text.ends_with(triggers[t]))
					{
						completion::completion_request((String)card.path, table, card.cursor, 2, triggers[t]);
						break;
					}
				}
			}
		}
	}

	if (keymap.pressed_move((int)commands::CommandId.CURSOR_LEFT, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.LEFT, metrics);
	}
	if (keymap.pressed_move((int)commands::CommandId.CURSOR_RIGHT, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.RIGHT, metrics);
	}
	if (keymap.pressed_move((int)commands::CommandId.CURSOR_UP, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.UP, metrics);
	}
	if (keymap.pressed_move((int)commands::CommandId.CURSOR_DOWN, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.DOWN, metrics);
	}
	if (keymap.pressed((int)commands::CommandId.LINE_START, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.LINE_START, metrics);
	}
	if (keymap.pressed((int)commands::CommandId.LINE_END, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.LINE_END, metrics);
	}
	if (keymap.pressed_move((int)commands::CommandId.PAGE_UP, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.PAGE_UP, metrics);
	}
	if (keymap.pressed_move((int)commands::CommandId.PAGE_DOWN, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.PAGE_DOWN, metrics);
	}

	if (completion::completion_is_open()) completion::completion_refilter(table, card.cursor);

	if (changed)
	{
		self.finish_edit(metrics);
		if (out_changed) *out_changed = true;
	}
}

fn void Project.draw_cluster(&self, int index, float zoom)
{
	FolderCluster cluster = self.folders[index];
	Rect bounds           = self.cluster_visual_bounds(index);
	rl::draw_rectangle_rec(bounds, theme::current().cluster_body);
	Rect title = self.cluster_title_rect(index);
	rl::draw_rectangle_rec(title, theme::current().cluster_title);
	rl::draw_rectangle_lines_ex(bounds, card::screen_thickness(1.0f, zoom), theme::current().cluster_border);
	if ((int)index == self.current_folder)
	{
		rl::draw_rectangle_lines_ex(title, card::screen_thickness(1.0f, zoom), theme::current().card_focus);
	}
	if ((int)index == self.selected_cluster)
	{
		float thickness = card::screen_thickness(self.grabbing ? 3.0f : 2.0f, zoom);
		rl::draw_rectangle_lines_ex(bounds, thickness, theme::current().card_focus);
	}
	String name = rl::get_file_name((ZString)cluster.path.ptr).str_view();
	@pool()
	{
		rl::draw_text_ex(
			ui::font(),
			name.zstr_tcopy(),
			{ bounds.x + (float)ui::px(10), bounds.y + (float)ui::px(5) },
			(float)ui::tpx(16),
			0.0f,
			theme::current()
			.cluster_text);
	};
	rl::draw_text_ex(
		ui::font(),
		cluster.collapsed ? "+" : "-",
		{ bounds.x + bounds.width - (float)ui::px(20), bounds.y + (float)ui::px(5) },
		(float)ui::tpx(16),
		0.0f,
		theme::current()
		.cluster_text);
}

fn void Project.draw_folders(&self, RLCamera2D camera)
{
	Rect visible = expand_rect(visible_world_rect(camera), DRAW_CULL_MARGIN);
	for (sz i = 0; i < self.folders.len(); i++)
	{
		if (!self.cluster_visible((int)i)) continue;
		if (!rect_intersects(self.cluster_visual_bounds((int)i), visible)) continue;
		self.draw_cluster((int)i, camera.zoom);
	}
}

fn void Project.draw_cards(
	&self,
	RLCamera2D camera,
	RLFont font,
	RLFont editor_font,
	EditorMetrics metrics,
	findbar::FindBar* find_bar
)
{
	double elapsed = rl::get_time() - self.last_input_time;
	int blink_ms   = editor::settings().caret_blink_ms;
	bool caret_on  = true;
	if (blink_ms > 0)
	{
		float period = (float)blink_ms / 1000.0f;
		float phase  = (float)elapsed - math::floor((float)elapsed / period) * period;
		caret_on = phase < period * 0.5f;
	}
	Rect visible = expand_rect(visible_world_rect(camera), DRAW_CULL_MARGIN);

	@pool()
	{
		List{int} draw_list;
		draw_list.init(tmem);
		self.visible_cards(visible, &draw_list);
		for (sz c = 0; c < draw_list.len(); c++)
		{
			sz i = (sz)draw_list[c];
			if (!self.card_visible((int)i)) continue;
			FileCard* card  = &self.cards[i];
			bool is_focused = (int)i == self.focused;
			if (is_focused) editor::ensure_buffer(card, self.allocator);
			if (!rect_intersects(card.rect, visible)) continue;
			if (!is_focused && card.rect.width * camera.zoom < CARD_MIN_DRAW_PX) continue;
			card.draw(is_focused, camera.zoom);
			if (!is_focused && (int)i == self.selected)
			{
				rl::draw_rectangle_lines_ex(
					card.effective_rect(),
					card::screen_thickness(2.0f, camera.zoom),
					theme::current()
					.card_focus);
			}
			else if (!is_focused && self.selected != (int)i && (int)i == self.hover_card)
			{
				RLColor base  = theme::current().card_focus;
				RLColor hover = { base[0], base[1], base[2], (char)140 };
				rl::draw_rectangle_lines_ex(card.effective_rect(), card::screen_thickness(1.0f, camera.zoom), hover);
			}
			if (!card.open) continue;

			if (card.preview && markdown::is_markdown_path((String)card.path))
			{
				editor::ensure_buffer(card, self.allocator);
				Rect area = editor::inner_rect(card.rect, metrics);
				float max = 0.0f;
				if (card.buffer && card.view)
				{
					max = markdown::view_draw(
						card.view,
						card.buffer,
						area,
						card.preview_scroll,
						camera,
						editor_font,
						metrics.font_size,
						metrics.char_width,
						metrics.line_height,
						card.highlight
					);
					if (card.preview_scroll > max) card.preview_scroll = max;
					editor::draw_scrollbar(area, area.height + max, card.preview_scroll, camera, theme::current()
						.editor_scrollbar);
				}
				if (is_focused) card.draw_handles(camera, theme::current().editor_handle);
				continue;
			}

			if (!card.buffer)
			{
				editor::draw_placeholder(editor::inner_rect(card.rect, metrics), metrics, camera, theme::current()
					.editor_placeholder);
				continue;
			}

			usz line_count = card.buffer.line_count();
			Rect gutter    = editor::gutter_rect(card.rect, metrics, line_count);
			Rect text      = editor::text_rect(card.rect, metrics, line_count);

			if (self.jump_path.len > 0 && self.jump_path.compare_to((String)card.path) == 0)
			{
				double now = rl::get_time();
				if (now < self.jump_until)
				{
					float fade    = jump_fade(now, self.jump_until, JUMP_HIGHLIGHT_SECONDS);
					RLColor base  = theme::current().card_focus;
					RLColor color = { base[0], base[1], base[2], (char)(fade * (float)JUMP_HIGHLIGHT_ALPHA) };
					Rect line_rect = {
						.x = text.x,
						.y = text.y + editor::line_y(self.jump_line, card.scroll, metrics),
						.width = text.width,
						.height = metrics.line_height,
					};
					rl::draw_rectangle_rec(line_rect, color);
				}
				else
				{
					self.clear_jump();
				}
			}

			if (is_focused) editor::draw_current_line(
				card.buffer,
				text,
				card.scroll,
				metrics,
				camera,
				card.cursor,
				theme::current()
				.editor_current_line);
			if (is_focused && editor::has_selection(card.selection_anchor, card.cursor))
			{
				usz sel_start = 0;
				usz sel_end   = 0;
				editor::selection_range(card.selection_anchor, card.cursor, &sel_start, &sel_end);
				editor::draw_selection(
					card.buffer,
					text,
					card.scroll,
					card.scroll_x,
					metrics,
					camera,
					sel_start,
					sel_end,
					theme::current()
					.editor_selection);
			}
			if (is_focused && find_bar) find_bar.draw_matches(
				card.rect,
				card.buffer,
				card.scroll,
				card.scroll_x,
				metrics,
				camera
			);
			editor::draw_gutter(
				card.buffer,
				gutter,
				card.scroll,
				metrics,
				camera,
				editor_font,
				metrics.font_size,
				theme::current()
				.editor_gutter_text, theme::current().editor_gutter_bg);
			editor::draw_text_highlighted(
				card.highlight,
				card.buffer,
				text,
				card.scroll,
				card.scroll_x,
				metrics,
				camera,
				editor_font,
				metrics.font_size,
				theme::current()
				.editor_text);
			if (is_focused)
			{
				lsp::LspDiagnostic[] diags = lsp::lsp_diagnostics_for((String)card.path);
				if (diags.len > 0)
				{
					editor::draw_diagnostics(card.buffer, text, card.scroll, card.scroll_x, metrics, camera, diags);
				}
			}
			if (is_focused && caret_on)
			{
				editor::draw_caret(
					card.buffer,
					text,
					card.scroll,
					card.scroll_x,
					metrics,
					camera,
					card.cursor,
					theme::current()
					.editor_caret);
			}
			float content_height = (float)line_count * metrics.line_height + metrics.padding_y * 2.0f;
			editor::draw_scrollbar(text, content_height, card.scroll, camera, theme::current().editor_scrollbar);
			if (is_focused && find_bar) find_bar.draw(card.rect, metrics, font, null);
			if (is_focused) card.draw_handles(camera, theme::current().editor_handle);
		}
	};
}
fn void Project.toggle_preview(&self, int index)
{
	if (index < 0 || index >= (int)self.cards.len()) return;
	FileCard* card = &self.cards[index];
	if (!markdown::is_markdown_path((String)card.path)) return;
	card.preview = !card.preview;
	if (card.preview)
	{
		editor::ensure_buffer(card, self.allocator);
		card.preview_scroll = 0.0f;
	}
}