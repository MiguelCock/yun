module yun::project;

import libc;
import raylib6::rl;
import std::collections::list;
import std::io::file;
import std::io::path;
import std::math;
import yun::canvas;
import yun::card;

const int ROOT_FOLDER            = -1;
const float CLUSTER_PADDING      =  24.0f;
const float CLUSTER_TITLE_HEIGHT =  26.0f;
const float CARD_GAP             =  16.0f;
const int CLUSTER_COLUMNS        =  3;
const RLColor CLUSTER_BODY       =  { 26, 28, 36, 200 };
const RLColor CLUSTER_BORDER     =  { 60, 70, 90, 255 };
const RLColor CLUSTER_TITLE      =  { 40, 46, 60, 255 };
const RLColor CLUSTER_TEXT       =  { 180, 200, 230, 255 };

faultdef COPY_FAILED;

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

fn bool path_is_inside(String root, String abs)
{
	if (root.len == 0 || abs.len < root.len) return false;
	if (abs[0:root.len].compare_to(root) != 0) return false;
	if (abs.len == root.len) return true;
	char next = abs[root.len];
	return next == '/' || next == '\\';
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
	return !self.folder_collapsed(self.folder_for((String)self.cards[card_index].path));
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
		Rect r = self.cluster_bounds((int)i);
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
	if (self.folders[index].collapsed) return self.folders[index].bounds;
	return self.cluster_bounds(index);
}

fn int Project.cluster_hit(&self, RLVector2 world)
{
	int best     = ROOT_FOLDER;
	usz best_len = 0;
	for (sz i = 0; i < self.folders.len(); i++)
	{
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
		if (self.folders[i].collapsed) continue;
		if (!rect_contains(self.cluster_bounds((int)i), world)) continue;
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

	FileCard card = {
		.path = (Path)final.copy(self.allocator),
		.name = rl::get_file_name((ZString)final.ptr)
		.str_view()
		.copy(
			self.allocator
		), .rect = {
			.x = world_pos[0] - card::CARD_WIDTH / 2.0f,
			.y = world_pos[1] - card::CARD_HEIGHT / 2.0f,
			.width = card::CARD_WIDTH,
			.height = card::CARD_HEIGHT,
		}, .open = false, .dirty = false, };
	self.cards.push(card);
	self.focused = (int)(self.cards.len() - 1);
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

fn void Project.update(&self, Canvas* canvas)
{
	RLVector2 mouse = rl::get_mouse_position();
	RLVector2 world = canvas.screen_to_world(mouse);

	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT) && canvas.pointer_over_ui)
	{
		int card_hit = self.hit_test(world);
		if (card_hit >= 0)
		{
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

fn void Project.draw(&self)
{
	for (sz i = 0; i < self.folders.len(); i++)
	{
		self.draw_cluster((int)i);
	}
	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (self.card_visible((int)i))
		{
			self.cards[i].draw((int)i == self.focused);
		}
	}
}