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
import yun::editor;
import yun::findbar;
import yun::gitignore;
import yun::highlight;
import yun::text;

const int ROOT_FOLDER               = -1;
const double POLL_SECONDS           =  1.0;
const float CLUSTER_PADDING         =  24.0f;
const float CLUSTER_TITLE_HEIGHT    =  26.0f;
const float CLUSTER_COLLAPSED_WIDTH =  240.0f;
const float CLUSTER_GAP             =  16.0f;
const float CARD_GAP                =  16.0f;
const int CLUSTER_COLUMNS           =  3;
const RLColor CLUSTER_BODY          =  { 26, 28, 36, 200 };
const RLColor CLUSTER_BORDER        =  { 60, 70, 90, 255 };
const RLColor CLUSTER_TITLE         =  { 40, 46, 60, 255 };
const RLColor CLUSTER_TEXT          =  { 180, 200, 230, 255 };
const String[] IGNORED_NAMES        =  { ".git", ".yun", "build", "out", "node_modules" };
const float DRAW_CULL_MARGIN        =  64.0f;
const double DOUBLE_CLICK_SECONDS   =  0.35;
const float DOUBLE_CLICK_DIST       =  6.0f;
const usz OPEN_SCAN_BUDGET          =  64;
const usz OPEN_BUILD_BUDGET         =  4096;

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
	bool drag_card;
	int drag_index;
	bool drag_cluster;
	int drag_cluster_index;
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
}

fn void Project.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.cards.init(allocator);
	self.folders.init(allocator);
	self.folder_index.init(allocator);
	self.focused = -1;
	self.drag_card = false;
	self.drag_cluster = false;
	self.last_poll = 0.0;
	self.pending_reload = -1;
	self.pending_close = -1;
	self.resizing = false;
	self.last_cursor = -1;
	self.selecting = false;
	self.last_click_time = -1000.0;
	self.last_click_pos = { 0.0f, 0.0f };
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
	self.folder_index.clear();
	self.focused = -1;
	self.drag_card = false;
	self.drag_cluster = false;
	self.cluster_moved = false;
	self.selecting = false;
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

fn int layout_columns(int count)
{
	if (count <= 1) return 1;
	float cell_w = CLUSTER_COLLAPSED_WIDTH + CLUSTER_GAP;
	float cell_h = CLUSTER_TITLE_HEIGHT + CLUSTER_GAP;
	int columns  = (int)math::ceil(math::sqrt((float)count * cell_h / cell_w));
	if (columns < 1) columns = 1;
	if (columns > count) columns = count;
	return columns;
}

fn RLVector2 layout_slot(int index, int columns)
{
	int col = index % columns;
	int row = index / columns;
	return {
		(float)col * (CLUSTER_COLLAPSED_WIDTH + CLUSTER_GAP),
		(float)row * (CLUSTER_TITLE_HEIGHT + CLUSTER_GAP),
	};
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
}

fn int Project.add_folder(&self, String folder_path, int parent)
{
	FolderCluster cluster = {
		.path = (Path)folder_path.copy(self.allocator),
		.bounds = { .x = 0.0f, .y = 0.0f, .width = 320.0f, .height = 220.0f },
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
	int index = (int)(self.cards.len() - 1);
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
		.width = 320.0f,
		.height = 220.0f,
	};
	self.invalidate_bounds();

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

fn void Project.layout(&self)
{
	int folder_count = (int)self.folders.len();
	int columns      = layout_columns(folder_count + 1);
	for (sz f = 0; f < self.folders.len(); f++)
	{
		RLVector2 origin = layout_slot((int)f, columns);
		self.folders[f].bounds = {
			.x = origin[0],
			.y = origin[1],
			.width = CLUSTER_COLLAPSED_WIDTH,
			.height = CLUSTER_TITLE_HEIGHT,
		};
		self.folders[f].bounds_valid = false;
	}
	RLVector2 root_origin = layout_slot(folder_count, columns);

	@pool()
	{
		usz[] cursor = alloc::new_array(tmem, usz, self.folders.len() + 1);
		for (sz i = 0; i < self.cards.len(); i++)
		{
			int folder = self.cards[i].folder;
			usz slot   = cursor[(sz)(folder + 1)];
			cursor[(sz)(folder + 1)] = slot + 1;

			RLVector2 origin = root_origin;
			if (folder != ROOT_FOLDER) origin = { self.folders[folder].bounds.x, self.folders[folder].bounds.y };

			int col = (int)(slot % (usz)CLUSTER_COLUMNS);
			int row = (int)(slot / (usz)CLUSTER_COLUMNS);
			self.cards[i].rect = {
				.x = origin[0] + CLUSTER_PADDING + (float)col * (card::CARD_WIDTH + CARD_GAP),
				.y = origin[1] + CLUSTER_TITLE_HEIGHT + CLUSTER_PADDING + (float)row * (card::CARD_HEIGHT + CARD_GAP),
				.width = card::CARD_WIDTH,
				.height = card::CARD_HEIGHT,
			};
		}
	};
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
			self.project.layout();
			for (sz i = 0; i < self.project.folders.len(); i++)
			{
				self.project.folders[i].collapsed = true;
			}
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
		.width = CLUSTER_COLLAPSED_WIDTH,
		.height = CLUSTER_TITLE_HEIGHT,
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
	if (self.focused == index)
	{
		self.focused = -1;
	}
	else if (self.focused > index)
	{
		self.focused--;
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

fn void Project.update(&self, Canvas* canvas, EditorMetrics metrics, bool pointer_blocked, bool* out_changed)
{
	RLVector2 mouse = rl::get_mouse_position();
	RLVector2 world = canvas.screen_to_world(mouse);
	canvas.block_zoom = false;

	float wheel = rl::get_mouse_wheel_move();
	if (wheel != 0.0f && !pointer_blocked)
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

	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT) && canvas.pointer_over_ui && !pointer_blocked)
	{
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
				if (card.buffer)
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
			else if (region == editor::CardRegion.BODY)
			{
				int index      = self.focus(card_hit);
				FileCard* card = &self.cards[index];
				editor::ensure_buffer(card, self.allocator);
				if (card.buffer)
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
				}
				self.selecting = true;
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
			self.invalidate_bounds();
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
			self.invalidate_bounds();
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

	self.poll_external(rl::get_time());
	self.handle_keyboard(metrics, out_changed);
}

fn RLMouseCursor cursor_for_handle(int handle)
{
	if (handle == 0 || handle == 4) return rl::RLMouseCursor.RESIZE_NWSE;
	if (handle == 2 || handle == 6) return rl::RLMouseCursor.RESIZE_NESW;
	if (handle == 1 || handle == 5) return rl::RLMouseCursor.RESIZE_NS;
	if (handle == 3 || handle == 7) return rl::RLMouseCursor.RESIZE_EW;
	return rl::RLMouseCursor.DEFAULT;
}

fn void Project.poll_external(&self, double now)
{
	if (self.pending_reload >= 0) return;
	if (now - self.last_poll < POLL_SECONDS) return;
	self.last_poll = now;
	for (sz i = 0; i < self.cards.len(); i++)
	{
		FileCard* card = &self.cards[i];
		if (!card.buffer || card.missing) continue;
		if (editor::file_changed(card))
		{
			self.pending_reload = (int)i;
			return;
		}
	}
}

fn bool ctrl_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_CONTROL) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_CONTROL);
}

fn bool shift_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_SHIFT) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SHIFT);
}

fn void Project.handle_keyboard(&self, EditorMetrics metrics, bool* out_changed)
{
	if (self.focused < 0 || self.focused >= (int)self.cards.len()) return;
	FileCard* card = &self.cards[self.focused];
	if (!card.open) return;
	editor::ensure_buffer(card, self.allocator);
	if (!card.buffer) return;

	PieceTable* table = card.buffer;
	History* history  = card.history;
	double now        = rl::get_time();
	bool shift        = shift_down();
	bool changed      = false;
	bool moved        = false;
	bool vertical     = false;

	if (ctrl_down() && !shift && rl::is_key_pressed(rl::RLKeyboardKey.Z))
	{
		usz cursor = card.cursor;
		if (history.undo(table, &cursor))
		{
			card.cursor = cursor;
			card.selection_anchor = cursor;
			changed = true;
		}
	}
	if (ctrl_down() && (rl::is_key_pressed(rl::RLKeyboardKey.Y) || (shift && rl::is_key_pressed(rl::RLKeyboardKey.Z))))
	{
		usz cursor = card.cursor;
		if (history.redo(table, &cursor))
		{
			card.cursor = cursor;
			card.selection_anchor = cursor;
			changed = true;
		}
	}

	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.ENTER))
	{
		usz start = 0;
		usz end   = 0;
		editor::selection_range(card.selection_anchor, card.cursor, &start, &end);
		history.break_coalescing();
		card.cursor = history.replace(table, start, end - start, "\n", now);
		card.selection_anchor = card.cursor;
		changed = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.TAB) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.TAB))
	{
		usz start = 0;
		usz end   = 0;
		editor::selection_range(card.selection_anchor, card.cursor, &start, &end);
		history.break_coalescing();
		card.cursor = history.replace(table, start, end - start, "\t", now);
		card.selection_anchor = card.cursor;
		changed = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		usz start = 0;
		usz end   = 0;
		editor::selection_range(card.selection_anchor, card.cursor, &start, &end);
		if (start < end)
		{
			card.cursor = history.replace(table, start, end - start, "", now);
		}
		else
		{
			card.cursor = history.backspace(table, card.cursor, now);
		}
		card.selection_anchor = card.cursor;
		changed = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.DELETE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.DELETE))
	{
		usz start = 0;
		usz end   = 0;
		editor::selection_range(card.selection_anchor, card.cursor, &start, &end);
		if (start < end)
		{
			card.cursor = history.replace(table, start, end - start, "", now);
		}
		else
		{
			card.cursor = history.delete_forward(table, card.cursor, now);
		}
		card.selection_anchor = card.cursor;
		changed = true;
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
		}
	}

	if (rl::is_key_pressed(rl::RLKeyboardKey.LEFT) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.LEFT))
	{
		history.break_coalescing();
		card.cursor = editor::cursor_prev(table, card.cursor);
		if (!shift) card.selection_anchor = card.cursor;
		moved = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.RIGHT) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.RIGHT))
	{
		history.break_coalescing();
		card.cursor = editor::cursor_next(table, card.cursor);
		if (!shift) card.selection_anchor = card.cursor;
		moved = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.HOME))
	{
		history.break_coalescing();
		card.cursor = editor::cursor_home(table, card.cursor);
		if (!shift) card.selection_anchor = card.cursor;
		moved = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.END))
	{
		history.break_coalescing();
		card.cursor = editor::cursor_end(table, card.cursor);
		if (!shift) card.selection_anchor = card.cursor;
		moved = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.UP))
	{
		history.break_coalescing();
		card.cursor = editor::cursor_up(table, card.cursor, card.preferred_column, &card.preferred_column);
		if (!shift) card.selection_anchor = card.cursor;
		moved = true;
		vertical = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.DOWN))
	{
		history.break_coalescing();
		card.cursor = editor::cursor_down(table, card.cursor, card.preferred_column, &card.preferred_column);
		if (!shift) card.selection_anchor = card.cursor;
		moved = true;
		vertical = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_UP) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.PAGE_UP))
	{
		Rect page_text = editor::text_rect(card.rect, metrics, table.line_count());
		sz rows        = (sz)(page_text.height / metrics.line_height);
		if (rows < 1) rows = 1;
		history.break_coalescing();
		card.cursor = editor::cursor_page(table, card.cursor, -rows, card.preferred_column, &card.preferred_column);
		if (!shift) card.selection_anchor = card.cursor;
		moved = true;
		vertical = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_DOWN) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.PAGE_DOWN))
	{
		Rect page_text = editor::text_rect(card.rect, metrics, table.line_count());
		sz rows        = (sz)(page_text.height / metrics.line_height);
		if (rows < 1) rows = 1;
		history.break_coalescing();
		card.cursor = editor::cursor_page(table, card.cursor, rows, card.preferred_column, &card.preferred_column);
		if (!shift) card.selection_anchor = card.cursor;
		moved = true;
		vertical = true;
	}

	if (!vertical)
	{
		usz line = table.line_of(card.cursor);
		card.preferred_column = editor::column_for_offset(table, line, card.cursor);
	}

	if (changed || moved) self.reveal_focused(metrics);

	if (changed)
	{
		card.dirty = true;
		if (card.highlight) card.highlight.mark_dirty();
		self.last_input_time = rl::get_time();
		if (out_changed) *out_changed = true;
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

fn void Project.draw(&self, RLCamera2D camera, RLFont font, EditorMetrics metrics, findbar::FindBar* find_bar)
{
	double elapsed = rl::get_time() - self.last_input_time;
	bool caret_on  = (elapsed - math::floor(elapsed)) < 0.5;
	Rect visible   = expand_rect(visible_world_rect(camera), DRAW_CULL_MARGIN);

	for (sz i = 0; i < self.folders.len(); i++)
	{
		if (!self.cluster_visible((int)i)) continue;
		if (!rect_intersects(self.cluster_visual_bounds((int)i), visible)) continue;
		self.draw_cluster((int)i);
	}
	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (!self.card_visible((int)i)) continue;
		FileCard* card  = &self.cards[i];
		bool is_focused = (int)i == self.focused;
		if (is_focused) editor::ensure_buffer(card, self.allocator);
		if (!rect_intersects(card.rect, visible)) continue;
		card.draw(is_focused);
		if (!card.open) continue;

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

		if (is_focused) editor::draw_current_line(
			card.buffer,
			text,
			card.scroll,
			metrics,
			camera,
			card.cursor,
			editor::EDITOR_CURRENT_LINE
		);
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
				editor::EDITOR_SELECTION
			);
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
			font,
			16.0f,
			editor::EDITOR_GUTTER_TEXT,
			editor::EDITOR_GUTTER_BG
		);
		editor::draw_text_highlighted(
			card.highlight,
			card.buffer,
			text,
			card.scroll,
			card.scroll_x,
			metrics,
			camera,
			font,
			16.0f,
			editor::EDITOR_TEXT
		);
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
				editor::EDITOR_CARET
			);
		}
		float content_height = (float)line_count * metrics.line_height + metrics.padding_y * 2.0f;
		editor::draw_scrollbar(text, content_height, card.scroll, camera, editor::EDITOR_SCROLLBAR);
		if (is_focused && find_bar) find_bar.draw(card.rect, metrics, font, null);
		if (is_focused) card.draw_handles(camera, editor::EDITOR_HANDLE);
	}
}