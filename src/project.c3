module yun::project;

import raylib6::rl;
import std::collections::list;
import std::io::file;
import std::io::path;
import yun::canvas;
import yun::card;

const int ROOT_FOLDER = -1;

faultdef COPY_FAILED;

struct Project
{
	Path root;
	List{FileCard} cards;
	Allocator allocator;
	int focused;
	bool drag_card;
	int drag_index;
	RLVector2 drag_world;
}

fn void Project.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.cards.init(allocator);
	self.focused = -1;
	self.drag_card = false;
	Path? cwd = path::cwd(allocator);
	if (catch excuse = cwd)
	{
		self.root = (Path)"";
		return;
	}
	self.root = cwd;
}

fn int Project.find_card(&self, String abs)
{
	for (sz i = 0; i < self.cards.len(); i++)
	{
		if (((String)self.cards[i].path).compare_to(abs) == 0) return (int)i;
	}
	return -1;
}

fn bool path_is_inside(String root, String abs)
{
	if (root.len == 0 || abs.len < root.len) return false;
	if (abs[0:root.len].compare_to(root) != 0) return false;
	if (abs.len == root.len) return true;
	char next = abs[root.len];
	return next == '/' || next == '\\';
}

fn String collision_name(Allocator allocator, String stem, String ext, int index)
{
	if (index <= 0) return string::format(allocator, "%s%s", stem, ext);
	return string::format(allocator, "%s (%d)%s", stem, index, ext);
}

fn String? Project.copy_into_root(&self, String abs)
{
	String stem = rl::get_file_name_without_ext((ZString)abs.ptr).str_view();
	String ext  = rl::get_file_extension((ZString)abs.ptr).str_view();

	String name    = collision_name(self.allocator, stem, ext, 0);
	Path? appended = self.root.append(self.allocator, name);
	if (catch excuse = appended) return COPY_FAILED~;
	Path dest = appended;

	int index = 1;
	while (path::exists(dest))
	{
		String alt = collision_name(self.allocator, stem, ext, index);
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
		}, .open = false, .dirty = false, .folder = ROOT_FOLDER, };
	self.cards.push(card);
	self.focused = (int)(self.cards.len() - 1);
	return self.focused;
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
		if (self.cards[i - 1].contains(world)) return (int)(i - 1);
	}
	return -1;
}

fn void Project.update(&self, Canvas* canvas)
{
	RLVector2 mouse = rl::get_mouse_position();
	RLVector2 world = canvas.screen_to_world(mouse);

	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT) && canvas.pointer_over_ui)
	{
		int hit = self.hit_test(world);
		if (hit >= 0)
		{
			self.drag_index = self.focus(hit);
			self.drag_card = true;
			self.drag_world = world;
		}
	}

	if (self.drag_card)
	{
		if (!rl::is_mouse_button_down(rl::RLMouseButton.LEFT))
		{
			self.drag_card = false;
		}
		else
		{
			RLVector2 delta = { world[0] - self.drag_world[0], world[1] - self.drag_world[1] };
			self.cards[self.drag_index].move_by(delta);
			self.drag_world = world;
		}
	}
}

fn void Project.draw(&self)
{
	for (sz i = 0; i < self.cards.len(); i++)
	{
		self.cards[i].draw((int)i == self.focused);
	}
}