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
import yun::git;
import yun::gitignore;
import yun::highlight;
import yun::icons;
import yun::keymap;
import yun::lsp;
import yun::markdown;
import yun::spatial;
import yun::text;
import yun::skin;
import yun::theme;
import yun::ui;
import yun::vim;

const int ROOT_FOLDER               = -1;
const double POLL_SECONDS           =  1.0;
const float CLUSTER_PADDING         =  24.0f;
const float CLUSTER_TITLE_HEIGHT    =  30.0f;
const float CLUSTER_COLLAPSED_WIDTH =  240.0f;
const float CLUSTER_COLLAPSED_BODY  =  140.0f;
const float CLUSTER_GAP             =  16.0f;
const float CARD_GAP                =  16.0f;
const int CLUSTER_COLUMNS           =  3;
const String[] IGNORED_NAMES        =  { ".git", ".gitmodules", ".yun", "build", "out", "node_modules" };
const float DRAW_CULL_MARGIN        =  64.0f;
const int STACK_CARDS               =  10;
const float STACK_GAP               =  6.0f;
const float STACK_DIAGONAL_X        =  22.0f;
const float STACK_FAN_X             =  40.0f;

enum CardLayout : int
{
	GRID,
	DECK,
	FAN,
}
const float CARD_MIN_DRAW_PX        = 3.0f;
const float CARD_LOD_MIN_PX         = 48.0f;
const float CARD_DETAIL_MIN_PX      = 180.0f;
const float CLUSTER_TEXT_MIN_ZOOM   = 0.45f;
const double DOUBLE_CLICK_SECONDS   = 0.35;
const float DOUBLE_CLICK_DIST       = 6.0f;
const usz OPEN_SCAN_BUDGET          = 64;
const usz OPEN_BUILD_BUDGET         = 4096;
const double JUMP_HIGHLIGHT_SECONDS = 1.0;
const int JUMP_HIGHLIGHT_ALPHA      = 80;

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
	List{Path} submodules;
	gitignore::Gitignore ignore;
	OpenPhase phase;
	bool cancelled;
	bool skip_nested;
	usz scanned_dirs;
	usz build_cursor;
}

faultdef COPY_FAILED;
faultdef RESOLVE_FAILED;

struct FolderCluster
{
	Path path;
	Rect bounds;
	Rect body;
	bool collapsed;
	int parent;
	bool bounds_valid;
	int card_count;
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
	bool grab_accum_valid;
	bool grab_moved;
	RLVector2 grab_accum;
	bool focus_toggle_requested;
	int hover_card;
	bool drag_card;
	int drag_index;
	bool drag_cluster;
	int drag_cluster_index;
	bool drag_cluster_title;
	bool cluster_moved;
	RLVector2 drag_world;
	RLVector2 drag_origin_world;
	Rect drag_origin_rect;
	Rect drag_cluster_origin_bounds;
	double last_input_time;
	double last_poll;
	double poll_seconds;
	double jump_highlight_seconds;
	bool external_reload;
	bool sleep_editors;
	bool autosave_enabled;
	double autosave_interval;
	double last_autosave;
	int pending_reload;
	int pending_close;
	bool resizing;
	int resize_card;
	int resize_handle;
	RLVector2 resize_origin_world;
	Rect resize_origin_rect;
	bool selecting;
	double last_click_time;
	RLVector2 last_click_pos;
	String jump_path;
	usz jump_line;
	double jump_until;
	int awake_count;
	int asleep_count;
	int stat_visible_cards;
	int stat_hidden_cards;
	int stat_culled_cards;
	int cards_revision;
	int order_revision;
	bool skip_nested_repos;
	CardLayout card_layout;
	bool editing;
	int focus_card;
	int focus_saved_focused;
	Rect focus_saved_rect;
	RLCamera2D focus_saved_camera;
	RLCamera2D focus_saved_target;
	float focus_screen_w;
	float focus_screen_h;
	spatial::Grid grid;
	bool grid_dirty;
	bool content_bounds_valid;
	Rect content_bounds_cache;
	int hover_cluster;
	EditorMetrics card_metrics;
	vim::State vim_state;
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
	self.grab_accum_valid = false;
	self.grab_moved = false;
	self.grab_accum = { 0.0f, 0.0f };
	self.focus_toggle_requested = false;
	self.drag_card = false;
	self.drag_cluster = false;
	self.drag_cluster_title = false;
	self.last_poll = 0.0;
	self.poll_seconds = POLL_SECONDS;
	self.jump_highlight_seconds = JUMP_HIGHLIGHT_SECONDS;
	self.external_reload = true;
	self.sleep_editors = true;
	self.autosave_enabled = false;
	self.autosave_interval = 30.0;
	self.last_autosave = 0.0;
	self.pending_reload = -1;
	self.pending_close = -1;
	self.resizing = false;
	self.selecting = false;
	self.last_click_time = -1000.0;
	self.last_click_pos = { 0.0f, 0.0f };
	self.jump_path = "";
	self.jump_line = 0;
	self.jump_until = 0.0;
	self.awake_count = 0;
	self.asleep_count = 0;
	self.stat_visible_cards = 0;
	self.stat_hidden_cards = 0;
	self.stat_culled_cards = 0;
	self.cards_revision = 0;
	self.order_revision = 0;
	self.skip_nested_repos = true;
	self.card_layout = CardLayout.DECK;
	self.editing = false;
	self.focus_card = -1;
	self.focus_saved_focused = -1;
	self.focus_screen_w = 0.0f;
	self.focus_screen_h = 0.0f;
	self.grid.init(allocator, spatial::CELL_SIZE);
	self.grid_dirty = true;
	self.content_bounds_valid = false;
	self.hover_card = -1;
	self.hover_cluster = -1;
	self.drag_index = -1;
	self.resize_card = -1;
	self.card_metrics = editor::default_metrics();
	self.vim_state.init(allocator);
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
	self.vim_state.destroy();
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
	self.order_revision = 0;
	self.focused = -1;
	self.selected = -1;
	self.selected_cluster = -1;
	self.current_folder = ROOT_FOLDER;
	self.focus_card = -1;
	self.focus_saved_focused = -1;
	self.grabbing = false;
	self.grab_accum_valid = false;
	self.grab_moved = false;
	self.grab_accum = { 0.0f, 0.0f };
	self.focus_toggle_requested = false;
	self.drag_card = false;
	self.drag_cluster = false;
	self.drag_cluster_title = false;
	self.cluster_moved = false;
	self.selecting = false;
	self.hover_card = -1;
	self.hover_cluster = -1;
	self.drag_index = -1;
	self.resize_card = -1;
	self.vim_state.reset();
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
	self.jump_until = now + self.jump_highlight_seconds;
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
	bool removed = false;
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
		removed = true;
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
	if (removed)
	{
		self.cards_revision++;
		self.order_revision++;
		self.invalidate_bounds();
	}
}

fn int Project.find_card(&self, String abs)
{
	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (((String)self.cards[i].path).compare_to(abs) == 0) return (int)i;
	}
	return -1;
}

fn int Project.add_folder(&self, String folder_path, int parent)
{
	FolderCluster cluster = {
		.path = (Path)folder_path.copy(self.allocator),
		.bounds = { .x = 0.0f, .y = 0.0f, .width = ui::pxf(320.0f), .height = ui::pxf(220.0f) },
		.body = {
			.x = 0.0f,
			.y = 0.0f,
			.width = ui::pxf(CLUSTER_COLLAPSED_WIDTH),
			.height = ui::pxf(CLUSTER_COLLAPSED_BODY)
		},
		.collapsed = false,
		.parent = parent,
		.bounds_valid = false,
		.card_count = 0,
	};
	self.folders.push(cluster);
	int index = (int)(self.folders.len() - 1);
	self.folder_index.set((String)self.folders[index].path, index);
	return index;
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

fn void Project.set_editor_metrics(&self, EditorMetrics metrics)
{
	self.card_metrics = metrics;
}

fn RLVector2 Project.default_card_size(&self)
{
	return editor::default_card_size(self.card_metrics);
}

fn void Project.adjust_folder_card_count(&self, int folder, int delta)
{
	int current = folder;
	while (current >= 0 && current < (int)self.folders.len())
	{
		self.folders[current].card_count += delta;
		current = self.folders[current].parent;
	}
}

fn int Project.append_card(&self, String abs, RLVector2 world_pos)
{
	RLVector2 size = editor::default_card_size(self.card_metrics);
	FileCard card = {
		.path = (Path)abs.copy(self.allocator),
		.name = rl::get_file_name((ZString)abs.ptr)
		.str_view()
		.copy(
			self.allocator
		), .rect = {
			.x = world_pos[0] - size[0] / 2.0f,
			.y = world_pos[1] - size[1] / 2.0f,
			.width = size[0],
			.height = size[1],
		}, .open = true, .dirty = false, .folder = self.folder_for(abs), };
	self.cards.push(card);
	int index = (int)(self.cards.len() - 1);
	self.adjust_folder_card_count(card.folder, 1);
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
		self.selected = existing;
		self.selected_cluster = -1;
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
	self.selected = self.focused;
	self.selected_cluster = -1;
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
	self.folders[index].body = {
		.x = world_pos[0],
		.y = world_pos[1],
		.width = ui::pxf(CLUSTER_COLLAPSED_WIDTH),
		.height = ui::pxf(CLUSTER_COLLAPSED_BODY),
	};
	self.invalidate_bounds();

	PathList? entries = path::ls(self.allocator, (Path)dir, no_dirs: true, recursive: false, relative: false);
	if (catch excuse = entries) return index;

	float x             = world_pos[0] + ui::pxf(CLUSTER_PADDING);
	float y             = world_pos[1] + ui::pxf(CLUSTER_TITLE_HEIGHT) + ui::pxf(CLUSTER_PADDING);
	RLVector2 card_size = editor::default_card_size(self.card_metrics);
	int col             = 0;
	foreach (Path entry : entries)
	{
		self.add_card((String)entry, { x + card_size[0] / 2.0f, y + card_size[1] / 2.0f });
		x += card_size[0] + ui::pxf((float)CARD_GAP);
		col++;
		if (col >= CLUSTER_COLUMNS)
		{
			col = 0;
			x = world_pos[0] + ui::pxf(CLUSTER_PADDING);
			y += card_size[1] + ui::pxf((float)CARD_GAP);
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


fn void Project.place_cards_block(&self, List{int}* cards, float base_x, float base_y, float cw, float ch, float cg)
{
	if (self.card_layout == CardLayout.GRID)
	{
		self.place_cards_grid(cards, base_x, base_y, cw, ch, cg);
		return;
	}
	int count = (int)cards.len();
	int per   = math::min(count, STACK_CARDS);
	if (per < 1) return;
	float step_y  = ui::pxf(card::CARD_TITLE_HEIGHT) + ui::pxf(STACK_GAP);
	float step_x  = self.card_layout == CardLayout.FAN ? ui::pxf(STACK_FAN_X)
		: self.card_layout == CardLayout.DECK ? ui::pxf(STACK_DIAGONAL_X)
		: 0.0f;
	float stack_w = cw + (float)(per - 1) * step_x;
	for (int k = 0; k < count; k++)
	{
		int stack = k / per;
		int pos   = k % per;
		self.cards[(*cards)[k]].rect = {
			.x = base_x + (float)stack * (stack_w + cg) + (float)pos * step_x,
			.y = base_y + (float)pos * step_y,
			.width = cw,
			.height = ch,
		};
	}
}

fn void Project.set_card_layout(&self, CardLayout layout)
{
	if ((int)layout < (int)CardLayout.GRID || (int)layout > (int)CardLayout.FAN) return;
	if (self.card_layout == layout) return;
	self.card_layout = layout;
	(void)self.layout_idle();
}
fn RLVector2 Project.card_block_size(&self, int count, float cw, float ch, float cg)
{
	if (count == 0) return { 0.0f, 0.0f };
	if (self.card_layout == CardLayout.GRID)
	{
		int cols = count < CLUSTER_COLUMNS ? count : CLUSTER_COLUMNS;
		int rows = (count + cols - 1) / cols;
		return { (float)cols * (cw + cg) - cg, (float)rows * (ch + cg) - cg };
	}
	int per       = math::min(count, STACK_CARDS);
	int stacks    = (count + per - 1) / per;
	float step_y  = ui::pxf(card::CARD_TITLE_HEIGHT) + ui::pxf(STACK_GAP);
	float step_x  = self.card_layout == CardLayout.FAN ? ui::pxf(STACK_FAN_X)
		: self.card_layout == CardLayout.DECK ? ui::pxf(STACK_DIAGONAL_X)
		: 0.0f;
	float stack_w = cw + (float)(per - 1) * step_x;
	float stack_h = ch + (float)(per - 1) * step_y;
	return { (float)stacks * (stack_w + cg) - cg, stack_h };
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
	return { ui::pxf(CLUSTER_COLLAPSED_WIDTH), ui::pxf(CLUSTER_COLLAPSED_BODY) };
}

fn RLVector2 Project.visual_size(&self, int index, RLVector2[] full_sizes)
{
	if (self.folders[index].collapsed) return self.chip_size();
	return full_sizes[(usz)index];
}

fn RLVector2 Project.measure_level(
	&self,
	int index,
	List{int}[]* cards_by,
	List{int}[]* children_by,
	RLVector2[] full_sizes,
	float cw,
	float ch,
	float cg,
	float gap
)
{
	if (full_sizes[(usz)index][0] > 0.0f) return full_sizes[(usz)index];

	List{int} folder_cards = (*cards_by)[(usz)(index + 1)];
	List{int} folder_kids  = (*children_by)[(usz)index];
	RLVector2 chip         = self.chip_size();
	if (folder_cards.len() == 0 && folder_kids.len() == 0)
	{
		full_sizes[(usz)index] = chip;
		return chip;
	}

	for (sz i = 0; i < folder_kids.len(); i++)
	{
		self.measure_level(folder_kids[i], cards_by, children_by, full_sizes, cw, ch, cg, gap);
	}
	List{RLVector2} items;
	items.init(tmem);
	for (sz i = 0; i < folder_kids.len(); i++) items.push(self.visual_size(folder_kids[i], full_sizes));
	if (folder_cards.len() > 0) items.push(self.card_block_size((int)folder_cards.len(), cw, ch, cg));

	RLVector2[] positions = alloc::new_array(tmem, RLVector2, items.len());
	float area            = 0.0f;
	for (sz i = 0; i < items.len(); i++) area += items[i][0] * items[i][1];
	RLVector2 content = self.flow_pack(&items, gap, math::sqrt(area), positions);
	items.free();

	float pad   = ui::pxf(CLUSTER_PADDING);
	float title = ui::pxf(CLUSTER_TITLE_HEIGHT);
	RLVector2 size = {
		.x = math::max(chip[0], content[0] + pad * 2.0f),
		.y = math::max(chip[1], title + content[1] + pad * 2.0f),
	};
	full_sizes[(usz)index] = size;
	return size;
}

fn void Project.place_level(
	&self,
	int index,
	RLVector2 origin,
	List{int}[]* cards_by,
	List{int}[]* children_by,
	RLVector2[] full_sizes
)
{
	RLVector2 body_size = self.chip_size();
	self.folders[index].body = {
		.x = origin[0],
		.y = origin[1],
		.width = body_size[0],
		.height = body_size[1],
	};
	float pad           = ui::pxf(CLUSTER_PADDING);
	float title         = ui::pxf(CLUSTER_TITLE_HEIGHT);
	RLVector2 card_size = editor::default_card_size(self.card_metrics);
	float cw            = card_size[0];
	float ch            = card_size[1];
	float cg            = ui::pxf((float)CARD_GAP);
	float gap           = ui::pxf(CLUSTER_GAP);

	float content_x = origin[0] + pad;
	float content_y = origin[1] + title + pad;

	List{int} folder_cards = (*cards_by)[(usz)(index + 1)];
	List{int} folder_kids  = (*children_by)[(usz)index];

	List{RLVector2} items;
	items.init(tmem);
	for (sz i = 0; i < folder_kids.len(); i++) items.push(self.visual_size(folder_kids[i], full_sizes));
	if (folder_cards.len() > 0) items.push(self.card_block_size((int)folder_cards.len(), cw, ch, cg));

	RLVector2[] positions = alloc::new_array(tmem, RLVector2, (usz)(items.len() == 0 ? 1 : items.len()));
	float area            = 0.0f;
	for (sz i = 0; i < items.len(); i++) area += items[i][0] * items[i][1];
	self.flow_pack(&items, gap, math::sqrt(area), positions);
	items.free();

	for (sz i = 0; i < folder_kids.len(); i++)
	{
		RLVector2 p = positions[i];
		self.place_level(folder_kids[i], { content_x + p[0], content_y + p[1] }, cards_by, children_by, full_sizes);
	}
	if (folder_cards.len() > 0)
	{
		RLVector2 p = positions[folder_kids.len()];
		self.place_cards_block(&folder_cards, content_x + p[0], content_y + p[1], cw, ch, cg);
	}

	if (folder_cards.len() == 0 && folder_kids.len() == 0)
	{
		self.folders[index].bounds = { .x = origin[0], .y = origin[1], .width = body_size[0], .height = body_size[1] };
		self.folders[index].bounds_valid = true;
	}
	else
	{
		self.folders[index].bounds_valid = false;
	}
}

fn void Project.layout(&self)
{
	int nf              = (int)self.folders.len();
	RLVector2 card_size = editor::default_card_size(self.card_metrics);
	float cw            = card_size[0];
	float ch            = card_size[1];
	float cg            = ui::pxf((float)CARD_GAP);
	float gap           = ui::pxf(CLUSTER_GAP);

	@pool()
	{
		List{int}[] cards_by = alloc::new_array(tmem, List{int}, (usz)(nf + 1));
		for (usz i = 0; i < cards_by.len; i++) cards_by[i].init(tmem);
		for (sz i = 0; i < self.cards.len(); i++) cards_by[(usz)(self.cards[i].folder + 1)].push((int)i);
		for (int i = 0; i < nf; i++) self.folders[i].card_count = (int)cards_by[(usz)(i + 1)].len();
		for (int i = nf - 1; i >= 0; i--)
		{
			int parent = self.folders[i].parent;
			if (parent >= 0 && parent < nf) self.folders[parent].card_count += self.folders[i].card_count;
		}

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

		RLVector2[] full_sizes = alloc::new_array(tmem, RLVector2, (usz)(nf == 0 ? 1 : nf));
		for (int i = 0; i < nf; i++)
		{
			self.measure_level(i, &cards_by, &children_by, full_sizes, cw, ch, cg, gap);
		}

		List{RLVector2} items;
		items.init(tmem);
		for (sz i = 0; i < tops.len(); i++) items.push(self.visual_size(tops[i], full_sizes));
		if (root_cards.len() > 0) items.push(self.card_block_size((int)root_cards.len(), cw, ch, cg));

		if (items.len() > 0)
		{
			RLVector2[] positions = alloc::new_array(tmem, RLVector2, (usz)items.len());
			float area            = 0.0f;
			for (sz i = 0; i < items.len(); i++) area += items[i][0] * items[i][1];
			self.flow_pack(&items, gap, math::sqrt(area), positions);

			for (sz i = 0; i < tops.len(); i++)
			{
				self.place_level(tops[i], positions[i], &cards_by, &children_by, full_sizes);
			}
			if (root_cards.len() > 0)
			{
				RLVector2 p = positions[tops.len()];
				self.place_cards_block(&root_cards, p[0], p[1], cw, ch, cg);
			}
		}
	};
	self.invalidate_bounds();
}

fn void Project.place_unrestored(&self)
{
	RLVector2 card_size = editor::default_card_size(self.card_metrics);
	@pool()
	{
		HashMap{int, int} counts;
		counts.init(tmem);
		for (sz i = 0; i < self.cards.len(); i++)
		{
			FileCard* card = &self.cards[i];
			if (card.restored) continue;
			Rect anchor = { .x = 0.0f, .y = 0.0f, .width = 0.0f, .height = 0.0f };
			if (card.folder >= 0) anchor = self.cluster_visual_bounds(card.folder);
			int slot       = 0;
			int*? existing = counts.get_ref(card.folder);
			if (try v = existing) slot = *v;
			counts.set(card.folder, slot + 1);
			int col = slot % CLUSTER_COLUMNS;
			int row = slot / CLUSTER_COLUMNS;
			card.rect = {
				.x = anchor.x + ui::pxf(CLUSTER_PADDING) + (float)col * (card_size[0] + ui::pxf((float)CARD_GAP)),
				.y = anchor.y + anchor.height + ui::pxf(
					(float)CARD_GAP
				) + (float)row * (card_size[1] + ui::pxf((float)CARD_GAP)),
				.width = card_size[0],
				.height = card_size[1],
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
		self.folders[i].body.x *= factor;
		self.folders[i].body.y *= factor;
		self.folders[i].body.width *= factor;
		self.folders[i].body.height *= factor;
		self.folders[i].bounds_valid = false;
	}
	self.invalidate_bounds();
}

fn bool is_submodule_path(OpenJob* job, String abs)
{
	for (sz i = 0; i < job.submodules.len(); i++)
	{
		if (((String)job.submodules[i]).compare_to(abs) == 0) return true;
	}
	return false;
}

fn void open_job_load_submodules(OpenJob* job, String root)
{
	@pool()
	{
		Path? file = ((Path)root).append(tmem, ".gitmodules");
		if (catch excuse = file) return;
		char[]? data = file::load(tmem, file);
		if (catch excuse = data) return;
		String text = (String)data;
		usz start   = 0;
		for (usz i = 0; i <= text.len; i++)
		{
			if (i != text.len && text[i] != '\n') continue;
			String raw = text[start:i - start];
			start = i + 1;
			if (raw.len > 0 && raw[raw.len - 1] == '\r') raw = raw[0:raw.len - 1];
			usz at = 0;
			while (at < raw.len && (raw[at] == ' ' || raw[at] == '\t')) at++;
			if (!raw[at:raw.len - at].starts_with("path")) continue;
			usz eq = at;
			while (eq < raw.len && raw[eq] != '=') eq++;
			if (eq >= raw.len) continue;
			usz value_at = eq + 1;
			while (value_at < raw.len && (raw[value_at] == ' ' || raw[value_at] == '\t')) value_at++;
			String value = raw[value_at:raw.len - value_at];
			if (value.len == 0) continue;
			job.submodules.push((Path)string::format(job.allocator, "%s/%s", root, value));
		}
	};
}

fn OpenJob* open_job_create(Allocator allocator, Project* project, String root)
{
	OpenJob* job = alloc::new(allocator, OpenJob);
	job.allocator = allocator;
	job.project = project;
	job.root = (Path)root;
	job.entries.init(allocator);
	job.pending.init(allocator);
	job.submodules.init(allocator);
	job.ignore.init(allocator);
	job.phase = OpenPhase.SCAN;
	job.cancelled = false;
	job.skip_nested = project.skip_nested_repos;
	job.scanned_dirs = 0;
	job.build_cursor = 0;
	job.pending.push((Path)root);
	if (job.skip_nested) open_job_load_submodules(job, root);
	return job;
}

fn void open_job_destroy(OpenJob* job)
{
	if (!job) return;
	for (sz i = 0; i < job.submodules.len(); i++)
	{
		if (((String)job.submodules[i]).len) ((String)job.submodules[i]).free(job.allocator);
	}
	job.submodules.free();
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
		if (is_dir && self.skip_nested)
		{
			if (is_submodule_path(self, (String)entry)) continue;
			if (is_nested_repo((String)entry)) continue;
		}
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
			self.project.selected = -1;
			self.project.selected_cluster = -1;
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
	self.selected = self.focused;
	self.selected_cluster = -1;
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
		.height = ui::pxf(CLUSTER_COLLAPSED_BODY),
	};
	self.folders[index].body = self.folders[index].bounds;
	return index;
}

fn void Project.remove_card(&self, int index)
{
	if (index < 0 || index >= (int)self.cards.len()) return;
	FileCard* card = &self.cards[index];
	self.adjust_folder_card_count(card.folder, -1);
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

fn bool Project.layout_idle(&self)
{
	if (self.focus_card >= 0 || self.editing || self.grabbing || self.drag_card || self.drag_cluster || self.resizing
		|| self.selecting)
	{
		return false;
	}
	self.layout();
	return true;
}

fn int Project.focus(&self, int index)
{
	if (index < 0 || index >= (int)self.cards.len()) return self.focused;
	self.focused = index;
	self.selected = index;
	self.selected_cluster = -1;
	self.cards[index].selection_anchor = self.cards[index].cursor;
	return index;
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
	bool was_collapsed = self.folders[index].collapsed;
	self.folders[index].collapsed = false;
	self.collapse_descendants(index);
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
	if (was_collapsed && self.layout_conflict(index)) self.layout();
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

fn void Project.begin_grab(&self)
{
	self.grab_moved = false;
	if (self.selected_cluster >= 0 && self.selected_cluster < (int)self.folders.len())
	{
		Rect bounds = self.cluster_visual_bounds(self.selected_cluster);
		self.grab_accum = { bounds.x, bounds.y };
		self.grab_accum_valid = true;
	}
	else if (self.selected >= 0 && self.selected < (int)self.cards.len())
	{
		self.grab_accum = { self.cards[self.selected].rect.x, self.cards[self.selected].rect.y };
		self.grab_accum_valid = true;
	}
	else
	{
		self.grab_accum_valid = false;
	}
}

fn void Project.apply_grab_delta(&self, RLVector2 delta, float step)
{
	if (!self.grab_accum_valid) self.begin_grab();
	if (!self.grab_accum_valid) return;
	if (!self.grab_moved && step > 0.0f)
	{
		if (self.selected_cluster >= 0 && self.selected_cluster < (int)self.folders.len())
		{
			Rect current = self.cluster_visual_bounds(self.selected_cluster);
			float sx     = canvas::snap_value(current.x, step);
			float sy     = canvas::snap_value(current.y, step);
			self.grab_accum = { sx, sy };
			if (sx != current.x || sy != current.y) self.move_cluster(
				self.selected_cluster,
				{ sx - current.x, sy - current.y }
			);
		}
		else if (self.selected >= 0 && self.selected < (int)self.cards.len())
		{
			FileCard* card = &self.cards[self.selected];
			card.rect.x = canvas::snap_value(card.rect.x, step);
			card.rect.y = canvas::snap_value(card.rect.y, step);
			self.grab_accum = { card.rect.x, card.rect.y };
			self.invalidate_bounds_for_card(self.selected);
		}
	}
	if (delta[0] != 0.0f || delta[1] != 0.0f) self.grab_moved = true;
	self.grab_accum[0] += delta[0];
	self.grab_accum[1] += delta[1];
	float target_x = step > 0.0f ? canvas::snap_value(self.grab_accum[0], step) : self.grab_accum[0];
	float target_y = step > 0.0f ? canvas::snap_value(self.grab_accum[1], step) : self.grab_accum[1];
	if (self.selected_cluster >= 0 && self.selected_cluster < (int)self.folders.len())
	{
		Rect current   = self.cluster_visual_bounds(self.selected_cluster);
		RLVector2 move = { target_x - current.x, target_y - current.y };
		if (move[0] != 0.0f || move[1] != 0.0f)
		{
			self.move_cluster(self.selected_cluster, move);
			self.grab_moved = true;
		}
	}
	else if (self.selected >= 0 && self.selected < (int)self.cards.len())
	{
		if (target_x != self.cards[self.selected].rect.x
			|| target_y != self.cards[self.selected].rect.y) self.grab_moved = true;
		self.cards[self.selected].rect.x = target_x;
		self.cards[self.selected].rect.y = target_y;
		self.invalidate_bounds_for_card(self.selected);
	}
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
	card.scroll_x = editor::scroll_x_to_reveal(
		card.buffer,
		metrics,
		text.width,
		card.cursor,
		card.scroll_x,
		lsp::lsp_inlay_hints_for((String)card.path)
	);
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

fn bool Project.focused_editor(&self)
{
	return self.focus_card >= 0;
}

fn void Project.apply_focus_rect(&self, Canvas* canvas)
{
	int index = self.focus_card;
	if (index < 0 || index >= (int)self.cards.len()) return;
	float width  = canvas.usable_width();
	float height = canvas.usable_height();
	if (width < 1.0f) width = 1.0f;
	if (height < 1.0f) height = 1.0f;
	RLVector2 center = canvas.target.target;
	self.cards[index].rect = {
		.x = center[0] - width / 2.0f,
		.y = center[1] - height / 2.0f,
		.width = width,
		.height = height,
	};
}

fn bool Project.begin_focus(&self, int index, Canvas* canvas)
{
	if (index < 0 || index >= (int)self.cards.len()) return false;
	int previous_focused          = self.focused;
	int previous_selected         = self.selected;
	int previous_selected_cluster = self.selected_cluster;
	int at                        = self.focus(index);
	if (at < 0 || at >= (int)self.cards.len()) return false;
	self.cards[at].open = true;
	editor::ensure_buffer(&self.cards[at], self.allocator);
	if (!self.cards[at].buffer)
	{
		self.focused = previous_focused;
		self.selected = previous_selected;
		self.selected_cluster = previous_selected_cluster;
		return false;
	}

	self.focus_saved_focused = previous_focused;
	self.focus_saved_rect = self.cards[at].rect;
	self.focus_saved_camera = canvas.camera;
	self.focus_saved_target = canvas.target;
	self.focus_screen_w = canvas.usable_width();
	self.focus_screen_h = canvas.usable_height();
	self.focus_card = at;

	RLVector2 center = self.cards[at].center();
	canvas.unfollow();
	canvas.target.target = center;
	canvas.target.zoom = 1.0f;
	canvas.camera.target = center;
	canvas.camera.zoom = 1.0f;
	self.apply_focus_rect(canvas);
	self.invalidate_bounds();
	return true;
}

fn bool Project.refocus(&self, int index, Canvas* canvas)
{
	if (self.focus_card < 0 || index < 0 || index >= (int)self.cards.len()) return false;
	if (index == self.focus_card)
	{
		self.apply_focus_rect(canvas);
		return true;
	}
	FileCard* card = &self.cards[index];
	card.open = true;
	editor::ensure_buffer(card, self.allocator);
	if (!card.buffer) return false;

	if (self.focus_card >= 0 && self.focus_card < (int)self.cards.len())
	{
		self.cards[self.focus_card].rect = self.focus_saved_rect;
		if (self.focus_saved_focused == self.focus_card) self.focus_saved_focused = index;
	}
	self.focus_saved_rect = self.cards[index].rect;
	self.focus_card = index;
	self.focused = index;
	self.selected = index;
	self.selected_cluster = -1;
	self.apply_focus_rect(canvas);
	self.invalidate_bounds();
	return true;
}

fn void Project.update_focus_rect(&self, Canvas* canvas)
{
	if (self.focus_card < 0) return;
	float width  = canvas.usable_width();
	float height = canvas.usable_height();
	if (width == self.focus_screen_w && height == self.focus_screen_h) return;
	self.focus_screen_w = width;
	self.focus_screen_h = height;
	self.apply_focus_rect(canvas);
	self.invalidate_bounds();
}

fn void Project.end_focus(&self, Canvas* canvas)
{
	if (self.focus_card < 0) return;
	if (self.focus_card >= 0 && self.focus_card < (int)self.cards.len())
	{
		self.cards[self.focus_card].rect = self.focus_saved_rect;
	}
	int restore = self.focus_saved_focused;
	if (restore < 0 || restore >= (int)self.cards.len()) restore = -1;
	self.focused = restore;
	self.focus_card = -1;
	self.focus_saved_focused = -1;
	canvas.camera = self.focus_saved_camera;
	canvas.target = self.focus_saved_target;
	self.invalidate_bounds();
}

fn int Project.hit_test(&self, RLVector2 world)
{
	if (self.focus_card >= 0)
	{
		int index = self.focus_card;
		if (index >= (int)self.cards.len()) return -1;
		return self.cards[index].contains(world) ? index : -1;
	}
	self.ensure_grid();
	bool stack      =  self.card_layout != CardLayout.GRID;
	bool focus_live =  self.editing || self.focus_card >= 0 || self.grabbing;
	int best        = -1;
	int best_rank   = -1;
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
			int rank = 0;
			if (!stack && index == self.selected) rank = 1;
			if (focus_live && index == self.focused) rank = 2;
			if (stack && self.grabbing && index == self.selected) rank = 3;
			if (self.drag_card && index == self.drag_index) rank = 4;
			if (self.resizing && index == self.resize_card) rank = 5;
			if (rank > best_rank || (rank == best_rank && index > best))
			{
				best = index;
				best_rank = rank;
			}
		}
	};
	return best;
}

fn bool Project.layout_conflict(&self, int index)
{
	Rect area   = self.cluster_bounds(index);
	String root = (String)self.folders[index].path;
	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (!self.card_visible((int)i)) continue;
		if (path_is_inside(root, (String)self.cards[i].path)) continue;
		if (rect_intersects(area, self.cards[i].rect)) return true;
	}
	for (sz i = 0; i < self.folders.len(); i++)
	{
		if ((int)i == index) continue;
		String path = (String)self.folders[i].path;
		if (path_is_inside(root, path) || path_is_inside(path, root)) continue;
		if (!self.cluster_visible((int)i)) continue;
		if (rect_intersects(area, self.cluster_visual_bounds((int)i))) return true;
	}
	return false;
}

fn void Project.toggle_collapse(&self, int index)
{
	if (index < 0 || index >= (int)self.folders.len()) return;
	if (!self.folders[index].collapsed)
	{
		Rect full = self.cluster_bounds(index);
		self.folders[index].body.x = full.x;
		self.folders[index].body.y = full.y;
	}
	if (self.folders[index].body.width <= 0.0f)
	{
		self.folders[index].body.width = ui::pxf(CLUSTER_COLLAPSED_WIDTH);
		self.folders[index].body.height = ui::pxf(CLUSTER_COLLAPSED_BODY);
	}
	bool expanding = self.folders[index].collapsed;
	self.folders[index].collapsed = !self.folders[index].collapsed;
	if (expanding) self.collapse_descendants(index);
	self.invalidate_bounds();
	if (expanding && self.layout_conflict(index)) self.layout();
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
			self.folders[i].body.x += delta[0];
			self.folders[i].body.y += delta[1];
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
	int old_folder  = self.cards[card_index].folder;
	int new_folder  = self.folder_for(dest_str);
	if (old_folder != new_folder)
	{
		self.adjust_folder_card_count(old_folder, -1);
		self.adjust_folder_card_count(new_folder, 1);
	}
	self.cards[card_index].path = (Path)dest_str.copy(self.allocator);
	self.cards[card_index].name = rl::get_file_name((ZString)dest_str.ptr).str_view().copy(self.allocator);
	self.cards[card_index].folder = new_folder;
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

fn void Project.edge_pan_during_drag(&self, Canvas* canvas)
{
	if (!self.drag_card && !self.drag_cluster) return;
	float dt = math::min(rl::get_frame_time(), canvas::MAX_FRAME_DT);
	RLVector2 delta = canvas::edge_pan_delta(
		rl::get_mouse_position(),
		(float)rl::get_screen_width(),
		(float)rl::get_screen_height(),
		canvas.top_inset,
		canvas::EDGE_PAN_MARGIN,
		canvas::EDGE_PAN_SPEED,
		canvas.camera.zoom,
		dt,
		canvas.bottom_inset,
		canvas.left_inset,
		canvas.right_inset
	);
	canvas.target.target[0] += delta[0];
	canvas.target.target[1] += delta[1];
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
			if (self.focus_card >= 0 && region != editor::CardRegion.BODY && region != editor::CardRegion.MAXIMIZE
				&& region != editor::CardRegion.PREVIEW)
			{
				region = editor::CardRegion.NONE;
			}
			if (region == editor::CardRegion.HANDLE)
			{
				int handle = self.cards[card_hit].resize_handle_at(world, canvas.camera);
				self.resizing = true;
				canvas.unfollow();
				self.resize_card = self.focus(card_hit);
				self.resize_handle = handle;
				self.drag_world = world;
				self.resize_origin_world = world;
				self.resize_origin_rect = self.cards[self.resize_card].rect;
			}
			else if (region == editor::CardRegion.MAXIMIZE)
			{
				self.focus(card_hit);
				self.focus_toggle_requested = true;
			}
			else if (region == editor::CardRegion.MINIMIZE)
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
							card.scroll_x,
							lsp::lsp_inlay_hints_for((String)card.path)
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
						metrics,
						lsp::lsp_inlay_hints_for((String)card.path)
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
			else if (region == editor::CardRegion.TITLE)
			{
				int index      = self.focus(card_hit);
				FileCard* card = &self.cards[index];
				if (double_click) card.open = !card.open;
				self.drag_index = index;
				self.drag_card = true;
				canvas.unfollow();
				self.drag_world = world;
				self.drag_origin_world = world;
				self.drag_origin_rect = card.rect;
			}
		}
		else
		{
			int cluster_hit = self.cluster_hit(world);
			if (cluster_hit >= 0)
			{
				self.drag_cluster = true;
				self.drag_cluster_index = cluster_hit;
				canvas.unfollow();
				self.drag_cluster_title = self.cluster_title_hit(cluster_hit, world);
				self.cluster_moved = false;
				self.drag_world = world;
				self.drag_origin_world = world;
				self.drag_cluster_origin_bounds = self.cluster_visual_bounds(cluster_hit);
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
					metrics,
					lsp::lsp_inlay_hints_for((String)card.path)
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
			float step = self.grid_snap_step(canvas);
			if (step > 0.0f)
			{
				RLVector2 total = { world[0] - self.drag_origin_world[0], world[1] - self.drag_origin_world[1] };
				self.cards[self.drag_index].rect.x = canvas::snap_value(self.drag_origin_rect.x + total[0], step);
				self.cards[self.drag_index].rect.y = canvas::snap_value(self.drag_origin_rect.y + total[1], step);
			}
			else
			{
				RLVector2 delta = { world[0] - self.drag_world[0], world[1] - self.drag_world[1] };
				self.cards[self.drag_index].move_by(delta);
			}
			self.invalidate_bounds_for_card(self.drag_index);
			self.drag_world = world;
		}
	}

	if (self.drag_cluster)
	{
		if (!rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
		{
			if (!self.cluster_moved)
			{
				self.select_folder(self.drag_cluster_index);
				if (self.drag_cluster_title) self.toggle_collapse(self.drag_cluster_index);
			}
			self.drag_cluster = false;
		}
		else
		{
			RLVector2 delta = { world[0] - self.drag_world[0], world[1] - self.drag_world[1] };
			if (math::abs(delta[0]) > 0.01f || math::abs(delta[1]) > 0.01f) self.cluster_moved = true;
			if (self.cluster_moved)
			{
				float step = self.grid_snap_step(canvas);
				if (step > 0.0f)
				{
					RLVector2 total = {
						world[0] - self.drag_origin_world[0],
						world[1] - self.drag_origin_world[1],
					};
					float target_x = canvas::snap_value(self.drag_cluster_origin_bounds.x + total[0], step);
					float target_y = canvas::snap_value(self.drag_cluster_origin_bounds.y + total[1], step);
					Rect current   = self.cluster_visual_bounds(self.drag_cluster_index);
					self.move_cluster(self.drag_cluster_index, { target_x - current.x, target_y - current.y });
				}
				else
				{
					self.move_cluster(self.drag_cluster_index, delta);
				}
				self.drag_world = world;
			}
		}
	}

	self.edge_pan_during_drag(canvas);

	if (self.resizing)
	{
		if (!rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
		{
			self.resizing = false;
		}
		else
		{
			float min_w = editor::min_card_width(metrics);
			float min_h = editor::min_card_height(metrics);
			float step  = self.grid_snap_step(canvas);
			if (step > 0.0f)
			{
				RLVector2 total = {
					world[0] - self.resize_origin_world[0],
					world[1] - self.resize_origin_world[1],
				};
				self.cards[self.resize_card].rect = self.resize_origin_rect;
				self.cards[self.resize_card].resize_from(self.resize_handle, total, min_w, min_h);
				self.cards[self.resize_card].rect = card::snap_resize_rect(
					self.cards[self.resize_card].rect,
					self.resize_handle,
					step,
					min_w,
					min_h
				);
			}
			else
			{
				RLVector2 delta = { world[0] - self.drag_world[0], world[1] - self.drag_world[1] };
				self.cards[self.resize_card].resize_from(self.resize_handle, delta, min_w, min_h);
			}
			self.invalidate_bounds_for_card(self.resize_card);
			self.drag_world = world;
		}
	}

	if (!pointer_blocked && !self.resizing && !rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
	{
		int hover  = self.hit_test(world);
		int handle = self.focus_card < 0 && hover >= 0 ? self.cards[hover].resize_handle_at(world, canvas.camera) : -1;
		if (handle >= 0)
		{
			ui::request_cursor(cursor_for_handle(handle), 10);
		}
		else if (hover >= 0)
		{
			FileCard* card = &self.cards[hover];
			if (card.maximize_marker_hit(world))
			{
				ui::request_cursor(rl::RLMouseCursor.POINTING_HAND, 5);
				ui::tooltip_shortcut(
					self.focus_card >= 0 ? "Exit focus mode" : "Focus card",
					commands::command_def(commands::CommandId.TOGGLE_FOCUS_MODE)
					.shortcut);
			}
			else if (card.preview_marker_hit(world) && markdown::is_markdown_path((String)card.path))
			{
				ui::request_cursor(rl::RLMouseCursor.POINTING_HAND, 5);
				ui::tooltip_shortcut(
					"Toggle Markdown preview",
					commands::command_def(commands::CommandId.TOGGLE_PREVIEW)
					.shortcut);
			}
			else if (self.focus_card < 0 && card.minimize_marker_hit(world))
			{
				ui::request_cursor(rl::RLMouseCursor.POINTING_HAND, 5);
				ui::tooltip_shortcut(
					card.open ? "Collapse card" : "Expand card",
					commands::command_def(commands::CommandId.MINIMIZE_CARD)
					.shortcut);
			}
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
	int awake         = 0;
	int asleep        = 0;
	int visible_cards = 0;
	int hidden_cards  = 0;
	int culled_cards  = 0;
	for (sz i = 0; i < self.cards.len(); i++)
	{
		bool in_area  = rect_intersects(self.cards[i].rect, visible);
		bool in_scope = self.card_visible((int)i);
		if (in_area)
		{
			if (in_scope)
			{
				visible_cards++;
			}
			else
			{
				hidden_cards++;
			}
		}
		else
		{
			culled_cards++;
		}
		if (!self.sleep_editors)
		{
			self.cards[i].sleeping = false;
			awake++;
			continue;
		}
		bool is_focused = (int)i == self.focused || (int)i == self.focus_card;
		bool big_enough = self.cards[i].rect.width * zoom >= CARD_MIN_DRAW_PX;
		bool on_screen  = in_scope && self.cards[i].open && big_enough && in_area;
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
	self.stat_visible_cards = visible_cards;
	self.stat_hidden_cards = hidden_cards;
	self.stat_culled_cards = culled_cards;
}

fn void Project.poll_external(&self, double now)
{
	if (!self.external_reload) return;
	if (self.pending_reload >= 0) return;
	if (now - self.last_poll < self.poll_seconds) return;
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
	WORD_LEFT,
	WORD_RIGHT,
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

fn bool formatting_edit_after(lsp::FormattingEdit a, lsp::FormattingEdit b)
{
	if (a.start_line != b.start_line) return a.start_line > b.start_line;
	return a.start_character > b.start_character;
}

fn bool Project.apply_formatting(&self, String path, List{lsp::FormattingEdit}* edits, double now)
{
	int index = self.find_card(path);
	if (index < 0) return false;
	FileCard* card = &self.cards[index];
	editor::ensure_buffer(card, self.allocator);
	if (!card.buffer || !card.history) return false;

	for (sz i = 0; i < edits.len(); i++)
	{
		for (sz j = i + 1; j < edits.len(); j++)
		{
			if (formatting_edit_after(edits.get(j), edits.get(i)))
			{
				lsp::FormattingEdit tmp = edits.get(i);
				edits.set(i, edits.get(j));
				edits.set(j, tmp);
			}
		}
	}

	card.history.break_coalescing();
	for (sz i = 0; i < edits.len(); i++)
	{
		lsp::FormattingEdit edit = edits.get(i);
		usz start                = lsp::offset_from_position(card.buffer, edit.start_line, edit.start_character);
		usz end                  = lsp::offset_from_position(card.buffer, edit.end_line, edit.end_character);
		if (end < start) end = start;
		card.cursor = card.history.replace(card.buffer, start, end - start, edit.new_text, now);
	}
	if (card.cursor > card.buffer.length()) card.cursor = card.buffer.length();
	card.selection_anchor = card.cursor;
	card.dirty = true;
	if (card.highlight) card.highlight.mark_dirty();
	if (card.view) markdown::view_mark_dirty(card.view);
	lsp::lsp_did_change((String)card.path, card.buffer);
	return true;
}

fn bool workspace_text_edit_after(lsp::WorkspaceTextEdit a, lsp::WorkspaceTextEdit b)
{
	if (a.start_line != b.start_line) return a.start_line > b.start_line;
	return a.start_character > b.start_character;
}

fn bool Project.apply_workspace_edit(&self, lsp::WorkspaceEdit* edit, double now)
{
	if (edit.files.len() == 0) return false;
	for (sz f = 0; f < edit.files.len(); f++)
	{
		lsp::WorkspaceFileEdit* file = &edit.files[f];
		if (self.find_card(file.path) < 0) return false;
	}

	bool applied = false;
	for (sz f = 0; f < edit.files.len(); f++)
	{
		lsp::WorkspaceFileEdit* file = &edit.files[f];
		int index                    = self.find_card(file.path);
		if (index < 0) return false;
		FileCard* card = &self.cards[index];
		editor::ensure_buffer(card, self.allocator);
		if (!card.buffer || !card.history) return false;

		for (sz i = 0; i < file.edits.len(); i++)
		{
			for (sz j = i + 1; j < file.edits.len(); j++)
			{
				if (workspace_text_edit_after(file.edits.get(j), file.edits.get(i)))
				{
					lsp::WorkspaceTextEdit tmp = file.edits.get(i);
					file.edits.set(i, file.edits.get(j));
					file.edits.set(j, tmp);
				}
			}
		}

		card.history.break_coalescing();
		for (sz e = 0; e < file.edits.len(); e++)
		{
			lsp::WorkspaceTextEdit text_edit = file.edits.get(e);
			usz start = lsp::offset_from_position(card.buffer, text_edit.start_line, text_edit.start_character);
			usz end = lsp::offset_from_position(card.buffer, text_edit.end_line, text_edit.end_character);
			if (end < start) end = start;
			card.cursor = card.history.replace(card.buffer, start, end - start, text_edit.new_text, now);
		}
		if (card.cursor > card.buffer.length()) card.cursor = card.buffer.length();
		card.selection_anchor = card.cursor;
		card.dirty = true;
		if (card.highlight) card.highlight.mark_dirty();
		if (card.view) markdown::view_mark_dirty(card.view);
		lsp::lsp_did_change((String)card.path, card.buffer);
		applied = true;
	}
	return applied;
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

fn bool Project.editor_delete_word(&self, bool back)
{
	FileCard* card = self.focused_editable_card();
	if (!card) return false;
	PieceTable* table = card.buffer;
	History* history  = card.history;
	double now        = rl::get_time();
	usz start         = 0;
	usz end           = 0;
	editor::selection_range(card.selection_anchor, card.cursor, &start, &end);
	if (start == end)
	{
		usz length = 0;
		editor::word_delete_range(table, card.cursor, back, &start, &length);
		end = start + length;
	}
	if (start == end) return false;
	card.cursor = history.replace(table, start, end - start, "", now);
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
	self.editor_move_select(move, metrics, shift_down());
}

fn void Project.editor_move_select(&self, EditorMove move, EditorMetrics metrics, bool select)
{
	FileCard* card = self.focused_editable_card();
	if (!card) return;
	PieceTable* table = card.buffer;
	History* history  = card.history;
	bool shift        = select;
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
		case EditorMove.WORD_LEFT:
			card.cursor = editor::cursor_word_left(table, card.cursor);
			break;
		case EditorMove.WORD_RIGHT:
			card.cursor = editor::cursor_word_right(table, card.cursor);
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
	self.vim_state.reset();
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

fn bool alt_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_ALT) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_ALT);
}

fn float Project.grid_snap_step(&self, canvas::Canvas* canvas)
{
	if (!canvas::settings().snap_to_grid || alt_down()) return 0.0f;
	return canvas::snap_step(canvas.camera.zoom);
}

fn void Project.snap_card_to_grid(&self, int index, float zoom)
{
	if (!canvas::settings().snap_to_grid || alt_down()) return;
	if (index < 0 || index >= (int)self.cards.len()) return;
	float step = canvas::snap_step(zoom);
	self.cards[index].rect.x = canvas::snap_value(self.cards[index].rect.x, step);
	self.cards[index].rect.y = canvas::snap_value(self.cards[index].rect.y, step);
	self.invalidate_bounds_for_card(index);
}

fn void Project.snap_selected_to_grid(&self, float zoom)
{
	if (self.selected_cluster >= 0)
	{
		self.snap_cluster_to_grid(self.selected_cluster, zoom);
	}
	else if (self.selected >= 0)
	{
		self.snap_card_to_grid(self.selected, zoom);
	}
}

fn void Project.snap_cluster_to_grid(&self, int index, float zoom)
{
	if (!canvas::settings().snap_to_grid || alt_down()) return;
	if (index < 0 || index >= (int)self.folders.len()) return;
	float step  = canvas::snap_step(zoom);
	Rect bounds = self.cluster_visual_bounds(index);
	float x     = canvas::snap_value(bounds.x, step);
	float y     = canvas::snap_value(bounds.y, step);
	self.move_cluster(index, { x - bounds.x, y - bounds.y });
}

fn bool shift_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_SHIFT) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SHIFT);
}

fn void Project.handle_vim_keyboard(&self, FileCard* card, EditorMetrics metrics, bool* out_changed)
{
	bool changed = false;
	bool handled = false;
	double now   = rl::get_time();
	if (completion::completion_is_open()) completion::completion_close();
	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		(void)self.vim_state.handle(card.buffer, card.history, &card.cursor, &card.selection_anchor, 27, now);
		handled = true;
	}
	else if (ctrl_down() && rl::is_key_pressed(rl::RLKeyboardKey.R))
	{
		if (self.vim_state.handle(card.buffer, card.history, &card.cursor, &card.selection_anchor, 18, now))
		{
			changed = true;
		}
		handled = true;
	}
	else
	{
		int codepoint = rl::get_char_pressed();
		while (codepoint != 0)
		{
			if (codepoint >= 32 && codepoint <= 126)
			{
				handled = true;
				if (self.vim_state.handle(
					card.buffer,
					card.history,
					&card.cursor,
					&card.selection_anchor,
					codepoint,
					now
				))
				{
					changed = true;
				}
				if (self.vim_state.mode == vim::Mode.INSERT) break;
			}
			codepoint = rl::get_char_pressed();
		}
	}

	if (changed)
	{
		self.finish_edit(metrics);
		if (out_changed) *out_changed = true;
	}
	else if (handled)
	{
		self.reveal_focused(metrics);
	}
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

	if (editor::settings().vim_mode)
	{
		if (self.vim_state.mode == vim::Mode.INSERT)
		{
			if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
			{
				(void)self.vim_state.handle(card.buffer, card.history, &card.cursor, &card.selection_anchor, 27, now);
				self.reveal_focused(metrics);
				return;
			}
		}
		else
		{
			self.handle_vim_keyboard(card, metrics, out_changed);
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
	if (keymap.pressed_repeat((int)commands::CommandId.DELETE_WORD_BACK, commands::CTX_EDIT))
	{
		if (self.editor_delete_word(true)) changed = true;
	}
	if (keymap.pressed_repeat((int)commands::CommandId.DELETE_WORD_FORWARD, commands::CTX_EDIT))
	{
		if (self.editor_delete_word(false)) changed = true;
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

	bool any_move = false;
	if (keymap.pressed_move((int)commands::CommandId.CURSOR_LEFT, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.LEFT, metrics);
		any_move = true;
	}
	if (keymap.pressed_move((int)commands::CommandId.CURSOR_RIGHT, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.RIGHT, metrics);
		any_move = true;
	}
	if (keymap.pressed_move((int)commands::CommandId.CURSOR_UP, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.UP, metrics);
		any_move = true;
	}
	if (keymap.pressed_move((int)commands::CommandId.CURSOR_DOWN, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.DOWN, metrics);
		any_move = true;
	}
	if (keymap.pressed_move((int)commands::CommandId.CURSOR_WORD_LEFT, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.WORD_LEFT, metrics);
		any_move = true;
	}
	if (keymap.pressed_move((int)commands::CommandId.CURSOR_WORD_RIGHT, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.WORD_RIGHT, metrics);
		any_move = true;
	}
	if (keymap.pressed_move((int)commands::CommandId.LINE_START, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.LINE_START, metrics);
		any_move = true;
	}
	if (keymap.pressed_move((int)commands::CommandId.LINE_END, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.LINE_END, metrics);
		any_move = true;
	}
	if (keymap.pressed_move((int)commands::CommandId.PAGE_UP, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.PAGE_UP, metrics);
		any_move = true;
	}
	if (keymap.pressed_move((int)commands::CommandId.PAGE_DOWN, commands::CTX_EDIT))
	{
		self.editor_move(EditorMove.PAGE_DOWN, metrics);
		any_move = true;
	}
	if (shift_down() && !any_move)
	{
		bool fallback_move  = false;
		EditorMove fallback = EditorMove.LEFT;
		if (rl::is_key_pressed(rl::RLKeyboardKey.LEFT) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.LEFT))
		{
			fallback = EditorMove.LEFT;
			fallback_move = true;
		}
		else if (rl::is_key_pressed(rl::RLKeyboardKey.RIGHT) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.RIGHT))
		{
			fallback = EditorMove.RIGHT;
			fallback_move = true;
		}
		else if (rl::is_key_pressed(rl::RLKeyboardKey.UP) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.UP))
		{
			fallback = EditorMove.UP;
			fallback_move = true;
		}
		else if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.DOWN))
		{
			fallback = EditorMove.DOWN;
			fallback_move = true;
		}
		if (fallback_move)
		{
			self.editor_move_select(fallback, metrics, true);
		}
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
	self.draw_cluster_at(index, self.cluster_visual_bounds(index), zoom);
}

fn void Project.draw_cluster_at(&self, int index, Rect bounds, float zoom)
{
	FolderCluster cluster = self.folders[index];
	float radius          = zoom > 0.0f ? ui::corner_radius() / zoom : ui::corner_radius();
	bool tray             = skin::folder_style() == skin::FolderStyle.TRAY;
	bool explorer         = skin::folder_style() == skin::FolderStyle.EXPLORER || tray;
	if (tray)
	{
		float off = zoom > 0.0f ? 5.0f / zoom : 5.0f;
		ui::rounded_rect(
			{ .x = bounds.x + off, .y = bounds.y + off, .width = bounds.width, .height = bounds.height },
			radius,
			{ 0, 0, 0, 35 }
		);
		ui::rounded_top(
			{
				.x = bounds.x + off,
				.y = bounds.y + off,
				.width = bounds.width,
				.height = ui::pxf(CLUSTER_TITLE_HEIGHT)
			},
			radius,
			theme::current()
			.cluster_title);
	}
	if (explorer)
	{
		float offset = zoom > 0.0f ? 2.0f / zoom : 2.0f;
		ui::rounded_rect(
			{ .x = bounds.x + offset, .y = bounds.y + offset, .width = bounds.width, .height = bounds.height },
			radius,
			{ 0, 0, 0, 40 }
		);
	}
	if (!skin::draw_world(
		skin::SurfaceId.FOLDER,
		bounds,
		zoom,
		ui::corner_radius()
	)) ui::rounded_rect(bounds, radius, theme::current()
		.cluster_body);
	Rect title = {
		.x = bounds.x,
		.y = bounds.y,
		.width = bounds.width,
		.height = ui::pxf(CLUSTER_TITLE_HEIGHT),
	};
	Rect tab = title;
	if (explorer)
	{
		tab.width = math::min(bounds.width - (float)ui::px(16), (float)ui::px(220));
		if (tab.width < (float)ui::px(60)) tab.width = bounds.width;
	}
	if (!skin::draw_world(
		skin::SurfaceId.FOLDER_TITLE,
		tab,
		zoom,
		ui::corner_radius()
	)) ui::rounded_top(tab, radius, theme::current()
		.cluster_title);
	ui::rounded_rect_lines(bounds, radius, card::screen_thickness(1.0f, zoom), theme::current().cluster_border);
	if ((int)index == self.current_folder)
	{
		ui::rounded_rect_lines(tab, radius, card::screen_thickness(1.0f, zoom), theme::current().card_focus);
	}
	if ((int)index == self.selected_cluster)
	{
		float thickness = card::screen_thickness(self.grabbing ? 3.0f : 2.0f, zoom);
		ui::rounded_rect_lines(bounds, radius, thickness, theme::current().card_focus);
	}
	if (cluster.collapsed && bounds.height > title.height)
	{
		float body_top = bounds.y + title.height;
		RLColor rule   = theme::current().cluster_border;
		rule.a = 70;
		float line_x = bounds.x + (float)ui::px(12);
		float line_w = bounds.width - (float)ui::px(24);
		for (int line = 0; line < 3; line++)
		{
			float y = body_top + (float)ui::px(14 + line * 16);
			if (y > bounds.y + bounds.height - (float)ui::px(28)) break;
			rl::draw_line_ex(
				{ line_x, y },
				{ line_x + line_w * (line == 2 ? 0.55f : 0.9f), y },
				1.0f / (zoom > 0.0f ? zoom : 1.0f),
				rule
			);
		}
		if (zoom >= CLUSTER_TEXT_MIN_ZOOM)
		{
			@pool()
			{
				String count = string::format(
					tmem,
					"%d %s",
					cluster.card_count,
					cluster.card_count == 1 ? "file" : "files"
				);
				rl::draw_text_ex(
					ui::font(),
					count.zstr_tcopy(),
					{ bounds.x + (float)ui::px(12), bounds.y + bounds.height - (float)ui::px(22) },
					(float)ui::tpx(13),
					0.0f,
					theme::current()
					.cluster_text);
			};
		}
	}
	if (zoom < CLUSTER_TEXT_MIN_ZOOM) return;
	float icon_size = (float)ui::px(18);
	bool has_icon = icons::draw_folder(
		!cluster.collapsed,
		{
			.x = bounds.x + (float)ui::px(8),
			.y = title.y + (title.height - icon_size) * 0.5f,
			.width = icon_size,
			.height = icon_size,
		},
		rl::WHITE
	);
	String name  = rl::get_file_name((ZString)cluster.path.ptr).str_view();
	float name_x = bounds.x + (float)ui::px(10);
	if (has_icon) name_x += icon_size + (float)ui::px(4);
	@pool()
	{
		rl::draw_text_ex(
			ui::font(),
			name.zstr_tcopy(),
			{ name_x, bounds.y + (float)ui::px(6) },
			(float)ui::tpx(18),
			0.0f,
			theme::current()
			.cluster_text);
	};
	rl::draw_text_ex(
		ui::font(),
		cluster.collapsed ? "+" : "-",
		{ bounds.x + bounds.width - (float)ui::px(22), bounds.y + (float)ui::px(6) },
		(float)ui::tpx(18),
		0.0f,
		theme::current()
		.cluster_text);
}

fn void Project.draw_folders(&self, RLCamera2D camera)
{
	Rect visible = expand_rect(visible_world_rect(camera), DRAW_CULL_MARGIN);
	for (sz i = 0; i < self.folders.len(); i++)
	{
		if ((int)i == self.selected_cluster) continue;
		if (!self.cluster_visible((int)i)) continue;
		if (!rect_intersects(self.cluster_visual_bounds((int)i), visible)) continue;
		self.draw_cluster((int)i, camera.zoom);
	}
	int selected = self.selected_cluster;
	if (selected < 0 || selected >= (int)self.folders.len()) return;
	if (!self.cluster_visible(selected)) return;
	if (!rect_intersects(self.cluster_visual_bounds(selected), visible)) return;
	self.draw_cluster(selected, camera.zoom);
}

fn void Project.draw_snap_guides(&self, RLCamera2D camera)
{
	if (!canvas::settings().snap_to_grid || alt_down()) return;
	if (!self.drag_card && !self.drag_cluster && !self.resizing && !self.grabbing) return;
	Rect r;
	if (self.resizing)
	{
		if (self.resize_card < 0 || self.resize_card >= (int)self.cards.len()) return;
		r = self.cards[self.resize_card].rect;
	}
	else if (self.drag_card)
	{
		if (self.drag_index < 0 || self.drag_index >= (int)self.cards.len()) return;
		r = self.cards[self.drag_index].rect;
	}
	else if (self.drag_cluster)
	{
		if (self.drag_cluster_index < 0 || self.drag_cluster_index >= (int)self.folders.len()) return;
		r = self.cluster_visual_bounds(self.drag_cluster_index);
	}
	else
	{
		r = self.selected_item_rect();
		if (r.width <= 0.0f) return;
	}
	Rect view       = visible_world_rect(camera);
	float thickness = card::screen_thickness(1.0f, camera.zoom);
	RLColor base    = theme::current().card_focus;
	RLColor guide   = { base[0], base[1], base[2], 150 };
	rl::draw_line_ex({ r.x, view.y }, { r.x, view.y + view.height }, thickness, guide);
	rl::draw_line_ex({ r.x + r.width, view.y }, { r.x + r.width, view.y + view.height }, thickness, guide);
	rl::draw_line_ex({ view.x, r.y }, { view.x + view.width, r.y }, thickness, guide);
	rl::draw_line_ex({ view.x, r.y + r.height }, { view.x + view.width, r.y + r.height }, thickness, guide);
}

fn void Project.draw_cards(
	&self,
	RLCamera2D camera,
	RLFont font,
	RLFont editor_font,
	EditorMetrics metrics,
	findbar::FindBar* find_bar,
	int only_card,
	bool editing,
	git::GitStatus* git_status
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
	Rect visible          = expand_rect(visible_world_rect(camera), DRAW_CULL_MARGIN);
	RLVector2 mouse_world = canvas::screen_to_world_camera(camera, rl::get_mouse_position());

	@pool()
	{
		List{int} draw_list;
		draw_list.init(tmem);
		if (only_card >= 0)
		{
			draw_list.push(only_card);
		}
		else
		{
			self.visible_cards(visible, &draw_list);
		}
		List{int} ordered;
		ordered.init(tmem);
		sz draw_count = draw_list.len();
		if (only_card < 0)
		{
			bool stack      = self.card_layout != CardLayout.GRID;
			bool focus_live = editing || self.focus_card >= 0;
			int[4] raised = {
				stack ? (self.grabbing ? self.selected : -1) : self.selected,
				focus_live ? self.focused : -1,
				self.drag_card ? self.drag_index : -1,
				self.resizing ? self.resize_card : -1,
			};
			for (sz c = 0; c < draw_list.len(); c++)
			{
				int index = draw_list[c];
				bool skip = false;
				for (int r = 0; r < 4; r++)
				{
					if (raised[r] == index)
					{
						skip = true;
						break;
					}
				}
				if (!skip) ordered.push(index);
			}
			for (int r = 0; r < 4; r++)
			{
				int index = raised[r];
				if (index < 0) continue;
				bool duplicate = false;
				for (int p = 0; p < r; p++)
				{
					if (raised[p] == index)
					{
						duplicate = true;
						break;
					}
				}
				if (!duplicate) ordered.push(index);
			}
			draw_count = ordered.len();
		}
		List{int}* order = only_card < 0 ? &ordered : &draw_list;
		for (sz c = 0; c < draw_count; c++)
		{
			sz i = (sz)(*order)[c];
			if (only_card < 0 && !self.card_visible((int)i)) continue;
			FileCard* card  = &self.cards[i];
			bool stack      = self.card_layout != CardLayout.GRID;
			bool focus_live = editing || self.focus_card >= 0;
			bool is_focused = (int)i == self.focused && (!stack || focus_live);
			bool is_editing = is_focused && editing;
			if (is_focused) editor::ensure_buffer(card, self.allocator);
			if (!rect_intersects(card.rect, visible)) continue;
			float on_screen_w = card.rect.width * camera.zoom;
			if (!is_focused && on_screen_w < CARD_MIN_DRAW_PX) continue;
			bool simple_lod = !is_focused && on_screen_w < CARD_LOD_MIN_PX;
			bool title_lod  = !is_focused && !simple_lod && on_screen_w < CARD_DETAIL_MIN_PX && (int)i != self.selected
				&& (int)i != self.hover_card;
			if (simple_lod)
			{
				card.draw_lod(camera.zoom);
			}
			else if (title_lod)
			{
				card.draw_lod_title(font, camera.zoom);
			}
			else
			{
				card.draw(is_focused, camera, mouse_world, self.focus_card >= 0, git_status);
			}
			if (!is_focused && (int)i == self.selected)
			{
				ui::rounded_rect_lines(
					card.effective_rect(),
					camera.zoom > 0.0f ? ui::corner_radius() / camera.zoom : ui::corner_radius(),
					card::screen_thickness(2.0f, camera.zoom),
					theme::current()
					.card_focus);
			}
			else if (!is_focused && self.selected != (int)i && (int)i == self.hover_card)
			{
				RLColor base  = theme::current().card_focus;
				RLColor hover = { base[0], base[1], base[2], (char)140 };
				ui::rounded_rect_lines(
					card.effective_rect(),
					camera.zoom > 0.0f ? ui::corner_radius() / camera.zoom : ui::corner_radius(),
					card::screen_thickness(1.0f, camera.zoom),
					hover
				);
			}
			if (!card.open || simple_lod || title_lod) continue;

			if (card.preview && markdown::is_markdown_path((String)card.path))
			{
				editor::ensure_buffer(card, self.allocator);
				Rect area = editor::inner_rect(card.rect, metrics);
				skin::draw_world(skin::SurfaceId.CARD_EDITOR, area, camera.zoom, 0.0f);
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
				if (is_focused && self.focus_card < 0) card.draw_handles(camera, theme::current().editor_handle);
				continue;
			}

			if (!card.buffer)
			{
				Rect area = editor::inner_rect(card.rect, metrics);
				skin::draw_world(skin::SurfaceId.CARD_EDITOR, area, camera.zoom, 0.0f);
				editor::draw_placeholder(area, metrics, camera, theme::current().editor_placeholder);
				continue;
			}

			usz line_count = card.buffer.line_count();
			skin::draw_world(skin::SurfaceId.CARD_EDITOR, editor::inner_rect(card.rect, metrics), camera.zoom, 0.0f);
			Rect gutter = editor::gutter_rect(card.rect, metrics, line_count);
			Rect text   = editor::text_rect(card.rect, metrics, line_count);

			if (self.jump_path.len > 0 && self.jump_path.compare_to((String)card.path) == 0)
			{
				double now = rl::get_time();
				if (now < self.jump_until)
				{
					float fade    = jump_fade(now, self.jump_until, self.jump_highlight_seconds);
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

			if (is_editing) editor::draw_current_line(
				card.buffer,
				text,
				card.scroll,
				metrics,
				camera,
				card.cursor,
				theme::current()
				.editor_current_line);
			lsp::InlayHint[] inlay_hints = lsp::lsp_inlay_hints_for((String)card.path);
			if (is_editing && editor::has_selection(card.selection_anchor, card.cursor))
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
					inlay_hints,
					theme::current()
					.editor_selection);
			}
			if (is_editing && find_bar) find_bar.draw_matches(
				card.rect,
				card.buffer,
				card.scroll,
				card.scroll_x,
				metrics,
				camera,
				inlay_hints
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
				inlay_hints,
				theme::current()
				.editor_text);
			if (is_focused)
			{
				lsp::LspDiagnostic[] diags = lsp::lsp_diagnostics_for((String)card.path);
				if (diags.len > 0)
				{
					editor::draw_diagnostics(
						card.buffer,
						text,
						card.scroll,
						card.scroll_x,
						metrics,
						camera,
						inlay_hints,
						diags
					);
				}
			}
			if (is_editing && caret_on)
			{
				editor::draw_caret(
					card.buffer,
					text,
					card.scroll,
					card.scroll_x,
					metrics,
					camera,
					card.cursor,
					inlay_hints,
					theme::current()
					.editor_caret);
			}
			float content_height = (float)line_count * metrics.line_height + metrics.padding_y * 2.0f;
			editor::draw_scrollbar(text, content_height, card.scroll, camera, theme::current().editor_scrollbar);
			if (is_editing && find_bar) find_bar.draw(card.rect, metrics, font, null);
			if (is_focused && self.focus_card < 0) card.draw_handles(camera, theme::current().editor_handle);
		}
	};
	self.draw_snap_guides(camera);
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