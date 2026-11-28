module yun::project;

import raylib6::rl;
import std::collections::map;
import std::math;
import yun::canvas;
import yun::ui;

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

fn int int_compare(void* a, void* b)
{
	int va = *(int*)a;
	int vb = *(int*)b;
	return va < vb ? -1 : (va > vb ? 1 : 0);
}

fn int Project.folder_by_path(&self, String path)
{
	int*? found = self.folder_index.get_ref(path);
	if (catch err = found) return ROOT_FOLDER;
	return *found;
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
	if (!self.folders[index].collapsed) return self.cluster_bounds(index);
	Rect body = self.folders[index].body;
	if (body.width <= 0.0f || body.height <= 0.0f)
	{
		Rect full = self.cluster_bounds(index);
		return {
			.x = full.x,
			.y = full.y,
			.width = ui::pxf(CLUSTER_COLLAPSED_WIDTH),
			.height = ui::pxf(CLUSTER_COLLAPSED_BODY),
		};
	}
	return body;
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

fn int Project.cluster_hit(&self, RLVector2 world)
{
	if (self.focus_card >= 0) return ROOT_FOLDER;
	int selected = self.selected_cluster;
	if (selected >= 0 && selected < (int)self.folders.len() && self.cluster_visible(
		selected
	) && rect_contains(self.cluster_visual_bounds(selected), world)) return selected;
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
	if (self.focus_card >= 0) return ROOT_FOLDER;
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
fn void Project.collapse_descendants(&self, int index)
{
	if (index < 0 || index >= (int)self.folders.len()) return;
	String root = (String)self.folders[index].path;
	for (sz i = 0; i < self.folders.len(); i++)
	{
		if ((int)i == index) continue;
		if (!path_is_inside(root, (String)self.folders[i].path)) continue;
		if (self.folders[i].collapsed) continue;
		Rect full = self.cluster_bounds((int)i);
		self.folders[i].body.x = full.x;
		self.folders[i].body.y = full.y;
		self.folders[i].collapsed = true;
	}
}