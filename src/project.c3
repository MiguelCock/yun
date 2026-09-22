module yun::project;

import libc;
import raylib6::rl;
import std::collections::list;
import std::io::file;
import std::io::path;
import std::math;
import yun::canvas;
import yun::card;
import yun::editor;
import yun::text;

const int ROOT_FOLDER               = -1;
const float CLUSTER_PADDING         =  24.0f;
const float CLUSTER_TITLE_HEIGHT    =  26.0f;
const float CLUSTER_COLLAPSED_WIDTH =  240.0f;
const float CARD_GAP                =  16.0f;
const int CLUSTER_COLUMNS           =  3;
const RLColor CLUSTER_BODY          =  { 26, 28, 36, 200 };
const RLColor CLUSTER_BORDER        =  { 60, 70, 90, 255 };
const RLColor CLUSTER_TITLE         =  { 40, 46, 60, 255 };
const RLColor CLUSTER_TEXT          =  { 180, 200, 230, 255 };
const float LAYOUT_CELL_W           =  280.0f;
const float LAYOUT_CELL_H           =  60.0f;
const int LAYOUT_COLUMNS            =  6;
const String[] IGNORED_NAMES        =  { ".git", ".yun", "build", "out", "node_modules" };

faultdef COPY_FAILED;
faultdef RESOLVE_FAILED;

struct FolderCluster
{
	Path path;
	Rect bounds;
	bool collapsed;
	int parent;
}

struct Project
{
	Path root;
	List{FileCard} cards;
	List{FolderCluster} folders;
	Allocator allocator;
	int focused;
	bool drag_card;
	int drag_index;
	bool drag_cluster;
	int drag_cluster_index;
	bool cluster_moved;
	RLVector2 drag_world;
	double last_input_time;
}

fn void Project.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.cards.init(allocator);
	self.folders.init(allocator);
	self.focused = -1;
	self.drag_card = false;
	self.drag_cluster = false;
	Path? cwd = path::cwd(allocator);
	if (catch excuse = cwd)
	{
		self.root = (Path)"";
		return;
	}
	self.root = cwd;
}

fn void Project.reset(&self)
{
	self.cards.clear();
	self.folders.clear();
	self.focused = -1;
	self.drag_card = false;
	self.drag_cluster = false;
	self.cluster_moved = false;
}

fn bool path_is_inside(String root, String abs)
{
	if (root.len == 0 || abs.len < root.len) return false;
	if (abs[0:root.len].compare_to(root) != 0) return false;
	if (abs.len == root.len) return true;
	char next = abs[root.len];
	return next == '/' || next == '\\';
}

fn bool path_is_ignored(String path)
{
	usz start = 0;
	for (usz i = 0; i <= path.len; i++)
	{
		if (i != path.len && path[i] != '/' && path[i] != '\\') continue;
		String component = path[start:i - start];
		foreach (String ignored : IGNORED_NAMES)
		{
			if (component.compare_to(ignored) == 0) return true;
		}
		start = i + 1;
	}
	return false;
}

fn int path_compare(void* a, void* b)
{
	Path pa = *(Path*)a;
	Path pb = *(Path*)b;
	return ((String)pa).compare_to((String)pb);
}

fn RLVector2 layout_position(int index)
{
	int col = index % LAYOUT_COLUMNS;
	int row = index / LAYOUT_COLUMNS;
	return { (float)col * LAYOUT_CELL_W, (float)row * LAYOUT_CELL_H };
}

fn bool rect_contains(Rect r, RLVector2 point)
{
	return point[0] >= r.x && point[0] <= r.x + r.width && point[1] >= r.y && point[1] <= r.y + r.height;
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
	int best     = ROOT_FOLDER;
	usz best_len = 0;
	for (sz i = 0; i < self.folders.len(); i++)
	{
		String fp = (String)self.folders[i].path;
		if (path_is_inside(fp, file) && fp.len > best_len)
		{
			best = (int)i;
			best_len = fp.len;
		}
	}
	return best;
}

fn int Project.folder_by_path(&self, String path)
{
	for (sz i = 0; i < self.folders.len(); i++)
	{
		if (((String)self.folders[i].path).compare_to(path) == 0) return (int)i;
	}
	return ROOT_FOLDER;
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

fn int Project.add_folder(&self, String folder_path, int parent)
{
	FolderCluster cluster = {
		.path = (Path)folder_path.copy(self.allocator),
		.bounds = { .x = 0.0f, .y = 0.0f, .width = 320.0f, .height = 220.0f },
		.collapsed = false,
		.parent = parent,
	};
	self.folders.push(cluster);
	return (int)(self.folders.len() - 1);
}

fn Rect Project.cluster_bounds(&self, int index)
{
	bool found  = false;
	float min_x = 0.0f;
	float min_y = 0.0f;
	float max_x = 0.0f;
	float max_y = 0.0f;

	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (self.folder_for((String)self.cards[i].path) != index) continue;
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
		.x = min_x - CLUSTER_PADDING,
		.y = min_y - CLUSTER_PADDING - CLUSTER_TITLE_HEIGHT,
		.width = (max_x - min_x) + CLUSTER_PADDING * 2.0f,
		.height = (max_y - min_y) + CLUSTER_PADDING * 2.0f + CLUSTER_TITLE_HEIGHT,
	};
}

fn Rect Project.cluster_visual_bounds(&self, int index)
{
	if (!self.folders[index].collapsed) return self.cluster_bounds(index);
	Rect b = self.folders[index].bounds;
	return {
		.x = b.x,
		.y = b.y,
		.width = CLUSTER_COLLAPSED_WIDTH,
		.height = CLUSTER_TITLE_HEIGHT,
	};
}

fn bool Project.content_bounds(&self, Rect* out)
{
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
	return true;
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

fn int Project.append_card(&self, String abs, RLVector2 world_pos)
{
	FileCard card = {
		.path = (Path)abs.copy(self.allocator),
		.name = rl::get_file_name((ZString)abs.ptr)
		.str_view()
		.copy(
			self.allocator
		), .rect = {
			.x = world_pos[0] - card::CARD_WIDTH / 2.0f,
			.y = world_pos[1] - card::CARD_HEIGHT / 2.0f,
			.width = card::CARD_WIDTH,
			.height = card::CARD_HEIGHT,
		}, .open = true, .dirty = false, .folder = self.folder_for(abs), };
	self.cards.push(card);
	return (int)(self.cards.len() - 1);
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
		.width = 320.0f,
		.height = 220.0f,
	};

	PathList? entries = path::ls(self.allocator, (Path)dir, no_dirs: true, recursive: false, relative: false);
	if (catch excuse = entries) return index;

	float x = world_pos[0] + CLUSTER_PADDING;
	float y = world_pos[1] + CLUSTER_TITLE_HEIGHT + CLUSTER_PADDING;
	int col = 0;
	foreach (Path entry : entries)
	{
		self.add_card((String)entry, { x + card::CARD_WIDTH / 2.0f, y + card::CARD_HEIGHT / 2.0f });
		x += card::CARD_WIDTH + CARD_GAP;
		col++;
		if (col >= CLUSTER_COLUMNS)
		{
			col = 0;
			x = world_pos[0] + CLUSTER_PADDING;
			y += card::CARD_HEIGHT + CARD_GAP;
		}
	}
	return index;
}

fn void Project.place_cards(&self, int folder_index, RLVector2 origin)
{
	int col = 0;
	float x = origin[0] + CLUSTER_PADDING;
	float y = origin[1] + CLUSTER_TITLE_HEIGHT + CLUSTER_PADDING;
	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (self.cards[i].folder != folder_index) continue;
		self.cards[i].rect = {
			.x = x,
			.y = y,
			.width = card::CARD_WIDTH,
			.height = card::CARD_HEIGHT,
		};
		x += card::CARD_WIDTH + CARD_GAP;
		col++;
		if (col >= CLUSTER_COLUMNS)
		{
			col = 0;
			x = origin[0] + CLUSTER_PADDING;
			y += card::CARD_HEIGHT + CARD_GAP;
		}
	}
}

fn void Project.layout(&self)
{
	for (sz f = 0; f < self.folders.len(); f++)
	{
		RLVector2 origin = layout_position((int)f);
		self.folders[f].bounds = {
			.x = origin[0],
			.y = origin[1],
			.width = CLUSTER_COLLAPSED_WIDTH,
			.height = CLUSTER_TITLE_HEIGHT,
		};
		self.place_cards((int)f, origin);
	}
	self.place_cards(ROOT_FOLDER, layout_position((int)self.folders.len()));
}

fn bool Project.open(&self, String new_root)
{
	self.reset();
	self.root = (Path)new_root.copy(self.allocator);

	PathList? entries = path::ls(self.allocator, (Path)new_root, no_dirs: false, recursive: true, relative: false);
	if (catch excuse = entries) return false;

	libc::qsort(entries.entries, (usz)entries.size, Path::size, &path_compare);

	foreach (Path entry : entries)
	{
		String p = (String)entry;
		if (path_is_ignored(p)) continue;
		if (path::is_dir(entry)) self.ensure_folder(p);
	}
	foreach (Path entry : entries)
	{
		String p = (String)entry;
		if (path_is_ignored(p)) continue;
		if (path::is_dir(entry)) continue;
		self.append_card(p, { 0.0f, 0.0f });
	}
	self.layout();
	for (sz i = 0; i < self.folders.len(); i++)
	{
		self.folders[i].collapsed = true;
	}
	self.focused = -1;
	return true;
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
		.width = CLUSTER_COLLAPSED_WIDTH,
		.height = CLUSTER_TITLE_HEIGHT,
	};
	return index;
}

fn int Project.focus(&self, int index)
{
	if (index < 0 || index >= (int)self.cards.len()) return self.focused;
	if (index == self.focused) return index;
	FileCard card = self.cards[index];
	self.cards.remove_at(index);
	self.cards.push(card);
	self.focused = (int)(self.cards.len() - 1);
	return self.focused;
}

fn int Project.hit_test(&self, RLVector2 world)
{
	for (sz i = self.cards.len(); i > 0; i--)
	{
		if (self.card_visible((int)(i - 1)) && self.cards[i - 1].contains(world)) return (int)(i - 1);
	}
	return -1;
}

fn void Project.toggle_collapse(&self, int index)
{
	if (index < 0 || index >= (int)self.folders.len()) return;
	if (!self.folders[index].collapsed)
	{
		self.folders[index].bounds = self.cluster_bounds(index);
	}
	self.folders[index].collapsed = !self.folders[index].collapsed;
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

fn void Project.update(&self, Canvas* canvas, EditorMetrics metrics)
{
	RLVector2 mouse = rl::get_mouse_position();
	RLVector2 world = canvas.screen_to_world(mouse);
	canvas.block_zoom = false;

	float wheel = rl::get_mouse_wheel_move();
	if (wheel != 0.0f)
	{
		int wheel_hit = self.hit_test(world);
		if (wheel_hit >= 0 && self.cards[wheel_hit].open)
		{
			int index = self.focus(wheel_hit);
			editor::ensure_buffer(&self.cards[index], self.allocator);
			if (self.cards[index].buffer)
			{
				usz line_count = self.cards[index].buffer.line_count();
				Rect text      = editor::text_rect(self.cards[index].rect, metrics, line_count);
				float max      = editor::max_scroll(line_count, metrics, text.height);
				float value    = self.cards[index].scroll - wheel * metrics.line_height * 3.0f;
				if (value < 0.0f) value = 0.0f;
				if (value > max) value = max;
				self.cards[index].scroll = value;
			}
			canvas.block_zoom = true;
		}
	}

	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT) && canvas.pointer_over_ui)
	{
		int card_hit = self.hit_test(world);
		if (card_hit >= 0 && self.cards[card_hit].marker_hit(world))
		{
			self.cards[card_hit].open = !self.cards[card_hit].open;
		}
		else if (card_hit >= 0)
		{
			FileCard* card = &self.cards[card_hit];
			editor::ensure_buffer(card, self.allocator);
			if (card.buffer)
			{
				Rect text       = editor::text_rect(card.rect, metrics, card.buffer.line_count());
				RLVector2 local = { world[0] - text.x, world[1] - text.y };
				card.cursor = editor::offset_for_point(card.buffer, local[0], local[1], card.scroll, metrics);
				usz line = card.buffer.line_of(card.cursor);
				card.preferred_column = editor::column_for_offset(card.buffer, line, card.cursor);
				if (card.history) card.history.break_coalescing();
				self.last_input_time = rl::get_time();
			}
			self.drag_index = self.focus(card_hit);
			self.drag_card = true;
			self.drag_world = world;
		}
		else
		{
			int cluster_hit = self.cluster_hit(world);
			if (cluster_hit >= 0)
			{
				self.drag_cluster = true;
				self.drag_cluster_index = cluster_hit;
				self.cluster_moved = false;
				self.drag_world = world;
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
			self.drag_world = world;
		}
	}

	if (self.drag_cluster)
	{
		if (!rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
		{
			if (!self.cluster_moved) self.toggle_collapse(self.drag_cluster_index);
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

	self.handle_keyboard(metrics);
}

fn bool ctrl_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_CONTROL) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_CONTROL);
}

fn bool shift_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_SHIFT) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SHIFT);
}

fn void Project.handle_keyboard(&self, EditorMetrics metrics)
{
	if (self.focused < 0 || self.focused >= (int)self.cards.len()) return;
	FileCard* card = &self.cards[self.focused];
	if (!card.open) return;
	editor::ensure_buffer(card, self.allocator);
	if (!card.buffer) return;

	PieceTable* table = card.buffer;
	History* history  = card.history;
	double now        = rl::get_time();
	bool changed      = false;
	bool vertical     = false;

	if (ctrl_down() && !shift_down() && rl::is_key_pressed(rl::RLKeyboardKey.Z))
	{
		usz cursor = card.cursor;
		if (history.undo(table, &cursor))
		{
			card.cursor = cursor;
			changed = true;
		}
	}
	if (ctrl_down() && (rl::is_key_pressed(
		rl::RLKeyboardKey.Y
	) || (shift_down() && rl::is_key_pressed(rl::RLKeyboardKey.Z))))
	{
		usz cursor = card.cursor;
		if (history.redo(table, &cursor))
		{
			card.cursor = cursor;
			changed = true;
		}
	}

	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.ENTER))
	{
		history.break_coalescing();
		card.cursor = history.insert(table, card.cursor, "\n", now);
		changed = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.TAB) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.TAB))
	{
		history.break_coalescing();
		card.cursor = history.insert(table, card.cursor, "\t", now);
		changed = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		card.cursor = history.backspace(table, card.cursor, now);
		changed = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.DELETE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.DELETE))
	{
		card.cursor = history.delete_forward(table, card.cursor, now);
		changed = true;
	}

	if (!ctrl_down())
	{
		char[4] encoded;
		int codepoint = rl::get_char_pressed();
		while (codepoint != 0)
		{
			if (codepoint >= 32 && codepoint != 127)
			{
				int count   = editor::utf8_encode(codepoint, &encoded[0]);
				String text = (String)encoded[0:count];
				card.cursor = history.insert(table, card.cursor, text, now);
				changed = true;
			}
			codepoint = rl::get_char_pressed();
		}
	}

	if (rl::is_key_pressed(rl::RLKeyboardKey.LEFT) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.LEFT))
	{
		history.break_coalescing();
		card.cursor = editor::cursor_prev(table, card.cursor);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.RIGHT) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.RIGHT))
	{
		history.break_coalescing();
		card.cursor = editor::cursor_next(table, card.cursor);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.HOME))
	{
		history.break_coalescing();
		card.cursor = editor::cursor_home(table, card.cursor);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.END))
	{
		history.break_coalescing();
		card.cursor = editor::cursor_end(table, card.cursor);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.UP))
	{
		history.break_coalescing();
		card.cursor = editor::cursor_up(table, card.cursor, card.preferred_column, &card.preferred_column);
		vertical = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.DOWN))
	{
		history.break_coalescing();
		card.cursor = editor::cursor_down(table, card.cursor, card.preferred_column, &card.preferred_column);
		vertical = true;
	}

	if (!vertical)
	{
		usz line = table.line_of(card.cursor);
		card.preferred_column = editor::column_for_offset(table, line, card.cursor);
	}

	Rect text = editor::text_rect(card.rect, metrics, table.line_count());
	card.scroll = editor::scroll_to_reveal(table, metrics, text.height, card.cursor, card.scroll);

	if (changed)
	{
		card.dirty = true;
		self.last_input_time = rl::get_time();
	}
}

fn void Project.draw_cluster(&self, int index)
{
	FolderCluster cluster = self.folders[index];
	Rect bounds           = self.cluster_visual_bounds(index);
	rl::draw_rectangle_rec(bounds, CLUSTER_BODY);
	Rect title = {
		.x = bounds.x,
		.y = bounds.y,
		.width = bounds.width,
		.height = CLUSTER_TITLE_HEIGHT,
	};
	rl::draw_rectangle_rec(title, CLUSTER_TITLE);
	rl::draw_rectangle_lines_ex(bounds, 1.0f, CLUSTER_BORDER);
	String name = rl::get_file_name((ZString)cluster.path.ptr).str_view();
	rl::draw_text((ZString)name.ptr, (int)(bounds.x + 10.0f), (int)(bounds.y + 5.0f), 16, CLUSTER_TEXT);
	rl::draw_text(
		cluster.collapsed ? "+" : "-",
		(int)(bounds.x + bounds.width - 20.0f),
		(int)(bounds.y + 5.0f),
		16,
		CLUSTER_TEXT
	);
}

fn void Project.draw(&self, RLCamera2D camera, RLFont font, EditorMetrics metrics)
{
	double elapsed = rl::get_time() - self.last_input_time;
	bool caret_on  = (elapsed - math::floor(elapsed)) < 0.5;

	for (sz i = 0; i < self.folders.len(); i++)
	{
		if (self.cluster_visible((int)i)) self.draw_cluster((int)i);
	}
	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (!self.card_visible((int)i)) continue;
		FileCard* card  = &self.cards[i];
		bool is_focused = (int)i == self.focused;
		card.draw(is_focused);
		if (!card.open) continue;

		if (is_focused) editor::ensure_buffer(card, self.allocator);
		if (!card.buffer)
		{
			editor::draw_placeholder(
				editor::inner_rect(card.rect, metrics),
				metrics,
				camera,
				editor::EDITOR_PLACEHOLDER
			);
			continue;
		}

		usz line_count = card.buffer.line_count();
		Rect gutter    = editor::gutter_rect(card.rect, metrics, line_count);
		Rect text      = editor::text_rect(card.rect, metrics, line_count);

		if (is_focused)
		{
			editor::draw_current_line(
				card.buffer,
				text,
				card.scroll,
				metrics,
				camera,
				card.cursor,
				editor::EDITOR_CURRENT_LINE
			);
		}
		editor::draw_gutter(
			card.buffer,
			gutter,
			card.scroll,
			metrics,
			camera,
			font,
			16.0f,
			editor::EDITOR_GUTTER_TEXT,
			editor::EDITOR_GUTTER_BG
		);
		editor::draw_text(card.buffer, text, card.scroll, metrics, camera, font, 16.0f, editor::EDITOR_TEXT);
		if (is_focused && caret_on)
		{
			editor::draw_caret(card.buffer, text, card.scroll, metrics, camera, card.cursor, editor::EDITOR_CARET);
		}
		float content_height = (float)line_count * metrics.line_height + metrics.padding_y * 2.0f;
		editor::draw_scrollbar(text, content_height, card.scroll, camera, editor::EDITOR_SCROLLBAR);
	}
}