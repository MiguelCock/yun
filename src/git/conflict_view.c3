module yun::git;

import raylib6::rl;
import std::collections::list;
import std::core::mem::alloc;
import std::io::file;
import std::math;
import yun::canvas;
import yun::theme;
import yun::ui;

struct ConflictView
{
	Allocator allocator;
	bool open;
	bool close_requested;
	bool confirm_abort;
	bool stage_pending;
	bool abort_pending;
	ulong action_seen;
	String path_rel;
	String path_abs;
	String content;
	String error;
	List{ConflictBlock} blocks;
	List{ConflictChoice} choices;
	int selected;
}

fn void ConflictView.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.open = false;
	self.close_requested = false;
	self.confirm_abort = false;
	self.stage_pending = false;
	self.abort_pending = false;
	self.action_seen = 0;
	self.path_rel = "";
	self.path_abs = "";
	self.content = "";
	self.error = "";
	self.blocks.init(allocator);
	self.choices.init(allocator);
	self.selected = 0;
}

fn void ConflictView.destroy(&self)
{
	for (sz i = 0; i < self.blocks.len(); i++) self.blocks[i].destroy(self.allocator);
	self.blocks.free();
	self.choices.free();
	if (self.path_rel.len > 0) self.path_rel.free(self.allocator);
	if (self.path_abs.len > 0) self.path_abs.free(self.allocator);
	if (self.content.len > 0) self.content.free(self.allocator);
	if (self.error.len > 0) self.error.free(self.allocator);
}

fn void ConflictView.clear(&self)
{
	for (sz i = 0; i < self.blocks.len(); i++) self.blocks[i].destroy(self.allocator);
	self.blocks.clear();
	self.choices.clear();
	if (self.path_rel.len > 0) self.path_rel.free(self.allocator);
	if (self.path_abs.len > 0) self.path_abs.free(self.allocator);
	if (self.content.len > 0) self.content.free(self.allocator);
	if (self.error.len > 0) self.error.free(self.allocator);
	self.path_rel = "";
	self.path_abs = "";
	self.content = "";
	self.error = "";
	self.selected = 0;
	self.stage_pending = false;
	self.abort_pending = false;
	self.confirm_abort = false;
}

fn void ConflictView.open_file(&self, String rel, String abs)
{
	self.clear();
	self.open = true;
	self.close_requested = false;
	self.path_rel = rel.copy(self.allocator);
	self.path_abs = abs.copy(self.allocator);
	char[]? data = file::load(self.allocator, abs);
	if (catch excuse = data)
	{
		self.error = "Could not read the conflicted file.".copy(self.allocator);
		return;
	}
	self.content = (String)data;
	if (!parse_conflicts(self.allocator, self.content, &self.blocks))
	{
		self.error = "No conflict markers found. Open the file in the editor.".copy(self.allocator);
		return;
	}
	for (sz i = 0; i < self.blocks.len(); i++) self.choices.push(ConflictChoice.UNSET);
}

fn int ConflictView.resolved_count(&self)
{
	int count = 0;
	for (sz i = 0; i < self.choices.len(); i++)
	{
		if (self.choices.get(i) != ConflictChoice.UNSET) count++;
	}
	return count;
}

fn void ConflictView.sync_action(&self, State* git)
{
	if (git.action_revision == self.action_seen) return;
	self.action_seen = git.action_revision;
	if (self.stage_pending)
	{
		self.stage_pending = false;
		if (git.action.success)
		{
			self.open = false;
			self.close_requested = true;
		}
		else
		{
			if (self.error.len > 0) self.error.free(self.allocator);
			self.error = git.action.error.copy(self.allocator);
		}
	}
	if (self.abort_pending)
	{
		self.abort_pending = false;
		if (git.action.success)
		{
			self.open = false;
			self.close_requested = true;
		}
		else
		{
			if (self.error.len > 0) self.error.free(self.allocator);
			self.error = git.action.error.copy(self.allocator);
		}
	}
}

fn void ConflictView.choose(&self, ConflictChoice choice)
{
	if (self.blocks.len() == 0) return;
	if (self.selected < 0 || self.selected >= (int)self.blocks.len()) return;
	self.choices.set(self.selected, choice);
	if (self.selected + 1 < (int)self.blocks.len() && self.choices.get((sz)(self.selected + 1)) == ConflictChoice.UNSET)
	{
		self.selected++;
	}
}

fn void ConflictView.save(&self, State* git)
{
	if (self.stage_pending || self.abort_pending) return;
	if (self.resolved_count() != (int)self.blocks.len())
	{
		if (self.error.len > 0) self.error.free(self.allocator);
		self.error = "Choose a resolution for every conflict.".copy(self.allocator);
		return;
	}
	String resolved = "";
	if (!resolve_conflicts(self.allocator, self.content, &self.blocks, &self.choices, &resolved))
	{
		return;
	}
	if (catch excuse = file::save(self.path_abs, resolved))
	{
		resolved.free(self.allocator);
		if (self.error.len > 0) self.error.free(self.allocator);
		self.error = "Could not save the resolved file.".copy(self.allocator);
		return;
	}
	resolved.free(self.allocator);
	String[] paths = alloc::new_array(tmem, String, 1);
	paths[0] = self.path_rel;
	self.action_seen = git.action_revision;
	if (!git.stage(paths))
	{
		if (self.error.len > 0) self.error.free(self.allocator);
		self.error = "Resolved file saved, but staging failed. Retry from the panel.".copy(self.allocator);
		return;
	}
	self.stage_pending = true;
}

fn void ConflictView.abort(&self, State* git)
{
	self.confirm_abort = false;
	self.action_seen = git.action_revision;
	if (git.abort_merge()) self.abort_pending = true;
}

fn void ConflictView.update(&self, State* git, Canvas* canvas, double now)
{
	if (!self.open) return;
	self.sync_action(git);
	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		if (self.confirm_abort)
		{
			self.confirm_abort = false;
		}
		else
		{
			self.open = false;
			self.close_requested = true;
		}
		return;
	}
	if (self.confirm_abort)
	{
		if (rl::is_key_pressed(rl::RLKeyboardKey.Y)) self.abort(git);
		return;
	}
	if (self.blocks.len() == 0) return;
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP)) self.selected--;
	if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN)) self.selected++;
	if (rl::is_key_pressed(rl::RLKeyboardKey.HOME)) self.selected = 0;
	if (rl::is_key_pressed(rl::RLKeyboardKey.END)) self.selected = (int)self.blocks.len() - 1;
	if (self.selected < 0) self.selected = 0;
	if (self.selected >= (int)self.blocks.len()) self.selected = (int)self.blocks.len() - 1;
	if (rl::is_key_pressed(rl::RLKeyboardKey.ONE) || rl::is_key_pressed(rl::RLKeyboardKey.C))
	{
		self.choose(ConflictChoice.CURRENT);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.TWO) || rl::is_key_pressed(rl::RLKeyboardKey.I))
	{
		self.choose(ConflictChoice.INCOMING);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.THREE) || rl::is_key_pressed(rl::RLKeyboardKey.B))
	{
		self.choose(ConflictChoice.BOTH);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.S)) self.save(git);
	if (rl::is_key_pressed(rl::RLKeyboardKey.A)) self.confirm_abort = true;
	RLVector2 mouse = rl::get_mouse_position();
	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		Rect panel     = self.panel_rect(canvas);
		float button_y = panel.y + panel.height - ui::pxf(64.0f);
		float button_w = (panel.width - ui::pxf(48.0f)) / 3.0f;
		Rect current   = { .x = panel.x + ui::pxf(16.0f), .y = button_y, .width = button_w, .height = ui::pxf(26.0f) };
		Rect incoming = {
			.x = current.x + button_w + ui::pxf(8.0f),
			.y = button_y,
			.width = button_w,
			.height = current.height
		};
		Rect both = {
			.x = incoming.x + button_w + ui::pxf(8.0f),
			.y = button_y,
			.width = button_w,
			.height = current.height
		};
		if (rect_contains(current, mouse)) self.choose(ConflictChoice.CURRENT);
		if (rect_contains(incoming, mouse)) self.choose(ConflictChoice.INCOMING);
		if (rect_contains(both, mouse)) self.choose(ConflictChoice.BOTH);
	}
}

fn Rect ConflictView.panel_rect(&self, Canvas* canvas)
{
	float width  = (float)rl::get_screen_width() * 0.94f;
	float height = (float)rl::get_screen_height() * 0.9f;
	return {
		.x = ((float)rl::get_screen_width() - width) / 2.0f,
		.y = ((float)rl::get_screen_height() - height) / 2.0f,
		.width = width,
		.height = height,
	};
}

fn void draw_conflict_pane(Rect rect, String label, String text, bool chosen, RLColor accent, float text_size)
{
	ui::rounded_rect(rect, ui::corner_radius(), theme::current().panel_bg);
	ui::rounded_rect_lines(rect, ui::corner_radius(), chosen ? 2.0f : 1.0f, chosen ? accent : theme::current()
		.panel_border);
	rl::draw_text_ex(
		ui::font(),
		label.zstr_tcopy(),
		{ rect.x + ui::pxf(10.0f), rect.y + ui::pxf(8.0f) },
		(float)ui::tpx(12),
		0.0f,
		theme::current()
		.panel_header);
	float line_h = ui::tpxf(16.0f);
	float y      = rect.y + ui::pxf(28.0f);
	rl::begin_scissor_mode(
		(int)rect.x + 2,
		(int)(rect.y + ui::pxf(26.0f)),
		(int)rect.width - 4,
		(int)(rect.height - ui::pxf(30.0f))
	);
	usz pos   = 0;
	int lines = 0;
	while (pos < text.len && lines < 40)
	{
		usz end = pos;
		while (end < text.len && text[end] != '\n') end++;
		String line = text[pos:end - pos];
		@pool()
		{
			rl::draw_text_ex(
				ui::font(),
				line.zstr_tcopy(),
				{ rect.x + ui::pxf(10.0f), y },
				text_size,
				0.0f,
				theme::current()
				.panel_text);
		};
		y += line_h;
		lines++;
		if (end >= text.len) break;
		pos = end + 1;
	}
	rl::end_scissor_mode();
}

fn void ConflictView.draw(&self, Canvas* canvas)
{
	if (!self.open) return;
	Rect screen = {
		.x = 0.0f,
		.y = 0.0f,
		.width = (float)rl::get_screen_width(),
		.height = (float)rl::get_screen_height(),
	};
	rl::draw_rectangle_rec(screen, { 0, 0, 0, 170 });
	Rect panel = self.panel_rect(canvas);
	ui::rounded_rect(panel, ui::corner_radius(), theme::current().panel_bg);
	ui::rounded_rect_lines(panel, ui::corner_radius(), 1.0f, theme::current().panel_border);
	Rect header = { .x = panel.x, .y = panel.y, .width = panel.width, .height = ui::pxf(42.0f) };
	ui::rounded_top(header, ui::corner_radius(), theme::current().panel_bg_alt);
	@pool()
	{
		String title = string::format(
			tmem,
			"Resolve conflicts  %s  (%d/%d)",
			diff_basename(self.path_rel),
			(long)self.resolved_count(),
			(long)self.blocks.len()
		);
		rl::draw_text_ex(
			ui::font(),
			title.zstr_tcopy(),
			{ header.x + ui::pxf(14.0f), header.y + ui::pxf(11.0f) },
			(float)ui::tpx(15),
			0.0f,
			theme::current()
			.panel_text);
	};
	rl::draw_rectangle_rec(
		{ .x = header.x, .y = header.y + header.height - 1.0f, .width = header.width, .height = 1.0f },
		theme::current()
		.panel_border);

	if (self.error.len > 0)
	{
		rl::draw_text_ex(
			ui::font(),
			self.error.zstr_tcopy(),
			{ panel.x + ui::pxf(16.0f), header.y + header.height + ui::pxf(12.0f) },
			(float)ui::tpx(13),
			0.0f,
			theme::current()
			.git_conflict);
	}
	if (self.blocks.len() == 0)
	{
		rl::draw_text_ex(
			ui::font(),
			"Esc: close",
			{ panel.x + ui::pxf(16.0f), panel.y + panel.height - ui::pxf(28.0f) },
			(float)ui::tpx(12),
			0.0f,
			theme::current()
			.panel_dim);
		return;
	}

	ConflictBlock* block  = &self.blocks[self.selected];
	ConflictChoice choice = self.choices.get(self.selected);
	float body_y          = header.y + header.height + ui::pxf(42.0f);
	float body_h          = panel.height - ui::pxf(42.0f) - ui::pxf(42.0f) - ui::pxf(104.0f);
	if (body_h < ui::pxf(80.0f)) body_h = ui::pxf(80.0f);
	float gap     = ui::pxf(10.0f);
	float pane_w  = (panel.width - ui::pxf(32.0f) - gap * 2.0f) / 3.0f;
	Rect current  = { .x = panel.x + ui::pxf(16.0f), .y = body_y, .width = pane_w, .height = body_h };
	Rect base     = { .x = current.x + pane_w + gap, .y = body_y, .width = pane_w, .height = body_h };
	Rect incoming = { .x = base.x + pane_w + gap, .y = body_y, .width = pane_w, .height = body_h };
	draw_conflict_pane(
		current,
		block.ours_label,
		block.ours,
		choice == ConflictChoice.CURRENT || choice == ConflictChoice.BOTH,
		theme::current()
		.git_added, (float)ui::tpx(12));
	draw_conflict_pane(base, "Base", block.base, false, theme::current().panel_border, (float)ui::tpx(12));
	draw_conflict_pane(
		incoming,
		block.theirs_label,
		block.theirs,
		choice == ConflictChoice.INCOMING || choice == ConflictChoice.BOTH,
		theme::current()
		.git_deleted, (float)ui::tpx(12));

	float button_y = panel.y + panel.height - ui::pxf(64.0f);
	float button_w = (panel.width - ui::pxf(48.0f)) / 3.0f;
	Rect current_button = {
		.x = panel.x + ui::pxf(16.0f),
		.y = button_y,
		.width = button_w,
		.height = ui::pxf(26.0f),
	};
	Rect incoming_button = {
		.x = current_button.x + button_w + ui::pxf(8.0f),
		.y = button_y,
		.width = button_w,
		.height = current_button.height,
	};
	Rect both_button = {
		.x = incoming_button.x + button_w + ui::pxf(8.0f),
		.y = button_y,
		.width = button_w,
		.height = current_button.height,
	};
	draw_button(current_button, "Use Current (1)", true, (float)ui::tpx(12));
	draw_button(incoming_button, "Use Incoming (2)", true, (float)ui::tpx(12));
	draw_button(both_button, "Use Both (3)", true, (float)ui::tpx(12));

	@pool()
	{
		String hint = string::format(tmem, "Up/Down: conflict    S: save + stage all    A: abort merge    Esc: close");
		rl::draw_text_ex(
			ui::font(),
			hint.zstr_tcopy(),
			{ panel.x + ui::pxf(16.0f), panel.y + panel.height - ui::pxf(28.0f) },
			(float)ui::tpx(12),
			0.0f,
			theme::current()
			.panel_dim);
	};

	if (self.confirm_abort)
	{
		rl::draw_rectangle_rec(screen, { 0, 0, 0, 120 });
		Rect modal = {
			.x = panel.x + panel.width / 2.0f - ui::pxf(170.0f),
			.y = panel.y + panel.height / 2.0f - ui::pxf(55.0f),
			.width = ui::pxf(340.0f),
			.height = ui::pxf(110.0f),
		};
		ui::rounded_rect(modal, ui::corner_radius(), theme::current().panel_bg_alt);
		ui::rounded_rect_lines(modal, ui::corner_radius(), 1.0f, theme::current().panel_border);
		rl::draw_text_ex(
			ui::font(),
			"Abort the merge?",
			{ modal.x + ui::pxf(16.0f), modal.y + ui::pxf(18.0f) },
			(float)ui::tpx(15),
			0.0f,
			theme::current()
			.panel_text);
		rl::draw_text_ex(
			ui::font(),
			"Y: abort merge    Esc: cancel",
			{ modal.x + ui::pxf(16.0f), modal.y + ui::pxf(48.0f) },
			(float)ui::tpx(12),
			0.0f,
			theme::current()
			.panel_dim);
	}
}