module yun::git;

import raylib6::rl;
import std::math;
import yun::canvas;
import yun::theme;
import yun::ui;

const int HISTORY_MAX_VISIBLE = 40;

struct HistoryView
{
	Allocator allocator;
	bool open;
	bool close_requested;
	String path;
	String requested_hash;
	int selected;
	int scroll;
	int file_selected;
	int file_scroll;
	bool file_focus;
	ulong commits_seen;
	ulong files_seen;
}

fn void HistoryView.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.open = false;
	self.close_requested = false;
	self.path = "";
	self.requested_hash = "";
	self.selected = 0;
	self.scroll = 0;
	self.file_selected = 0;
	self.file_scroll = 0;
	self.file_focus = false;
	self.commits_seen = 0;
	self.files_seen = 0;
}

fn void HistoryView.destroy(&self)
{
	if (self.path.len > 0) self.path.free(self.allocator);
	if (self.requested_hash.len > 0) self.requested_hash.free(self.allocator);
}

fn void HistoryView.open_history(&self, State* git, String path)
{
	if (self.path.len > 0) self.path.free(self.allocator);
	self.path = path.len > 0 ? path.copy(self.allocator) : "";
	self.open = true;
	self.close_requested = false;
	self.selected = 0;
	self.scroll = 0;
	self.file_selected = 0;
	self.file_scroll = 0;
	self.file_focus = false;
	if (self.requested_hash.len > 0) self.requested_hash.free(self.allocator);
	self.requested_hash = "";
	self.commits_seen = 0;
	self.files_seen = 0;
	git.request_history(path);
}

fn void HistoryView.request_selected_files(&self, State* git)
{
	if (self.selected < 0 || self.selected >= (int)git.commits.len()) return;
	GitCommit* commit = git.commits.get_ref(self.selected);
	if (self.requested_hash.len > 0 && self.requested_hash.compare_to(commit.hash) == 0) return;
	if (self.requested_hash.len > 0) self.requested_hash.free(self.allocator);
	self.requested_hash = commit.hash.copy(self.allocator);
	self.file_selected = 0;
	self.file_scroll = 0;
	git.request_commit_files(commit.hash);
}

fn void HistoryView.sync(&self, State* git)
{
	if (git.commits_revision != self.commits_seen)
	{
		self.commits_seen = git.commits_revision;
		if (self.selected >= (int)git.commits.len()) self.selected = (int)git.commits.len() - 1;
		if (self.selected < 0) self.selected = 0;
		if (self.requested_hash.len > 0)
		{
			self.requested_hash.free(self.allocator);
			self.requested_hash = "";
		}
	}
	if (git.commit_files_revision != self.files_seen)
	{
		self.files_seen = git.commit_files_revision;
		if (self.file_selected >= (int)git.commit_files.len()) self.file_selected = (int)git.commit_files.len() - 1;
		if (self.file_selected < 0) self.file_selected = 0;
	}
	if (git.commits.len() > 0) self.request_selected_files(git);
}

fn void HistoryView.update(&self, State* git, Canvas* canvas, double now)
{
	if (!self.open) return;
	self.close_requested = false;
	self.sync(git);
	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		self.open = false;
		self.close_requested = true;
		return;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.TAB)) self.file_focus = !self.file_focus;
	if (rl::is_key_pressed(rl::RLKeyboardKey.R))
	{
		git.request_history(self.path);
		return;
	}
	if (self.file_focus)
	{
		if (rl::is_key_pressed(rl::RLKeyboardKey.UP)) self.file_selected--;
		if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN)) self.file_selected++;
		if (self.file_selected < 0) self.file_selected = 0;
		if (self.file_selected >= (int)git.commit_files.len())
		{
			self.file_selected = (int)git.commit_files.len() - 1;
		}
		int visible_files = self.visible_files(canvas);
		if (self.file_selected < self.file_scroll) self.file_scroll = self.file_selected;
		if (self.file_selected >= self.file_scroll + visible_files)
		{
			self.file_scroll = self.file_selected - visible_files + 1;
		}
		if (self.file_scroll < 0) self.file_scroll = 0;
		if ((rl::is_key_pressed(
			rl::RLKeyboardKey.ENTER
		) || rl::is_key_pressed(
			rl::RLKeyboardKey.KP_ENTER
		)) && self
			.selected >= 0 && self
				.selected < (int)git.commits
					.len() && self.file_selected >= 0 && self.file_selected < (int)git.commit_files.len())
		{
			GitCommit* commit   = git.commits.get_ref(self.selected);
			GitCommitFile* file = git.commit_files.get_ref((sz)self.file_selected);
			(void)git.request_commit_diff(commit.hash, file.path, file.orig_path);
		}
		return;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP)) self.selected--;
	if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN)) self.selected++;
	if (self.selected < 0) self.selected = 0;
	if (self.selected >= (int)git.commits.len()) self.selected = (int)git.commits.len() - 1;
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_UP)) self.selected -= 10;
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_DOWN)) self.selected += 10;
	if (self.selected < 0) self.selected = 0;
	if (self.selected >= (int)git.commits.len()) self.selected = (int)git.commits.len() - 1;
	if (rl::is_key_pressed(rl::RLKeyboardKey.HOME)) self.selected = 0;
	if (rl::is_key_pressed(rl::RLKeyboardKey.END)) self.selected = (int)git.commits.len() - 1;
	self.request_selected_files(git);
	int visible = self.visible_commits(canvas);
	if (self.selected < self.scroll) self.scroll = self.selected;
	if (self.selected >= self.scroll + visible) self.scroll = self.selected - visible + 1;
	if (self.scroll < 0) self.scroll = 0;
}

fn Rect HistoryView.rect(&self, Canvas* canvas)
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

fn int HistoryView.visible_commits(&self, Canvas* canvas)
{
	Rect panel = self.rect(canvas);
	int rows   = (int)((panel.height - ui::pxf(80.0f)) / ui::pxf(34.0f));
	return rows < 1 ? 1 : rows;
}

fn int HistoryView.visible_files(&self, Canvas* canvas)
{
	Rect panel = self.rect(canvas);
	int rows   = (int)((panel.height - ui::pxf(150.0f)) / ui::pxf(21.0f));
	return rows < 1 ? 1 : rows;
}

fn void HistoryView.draw(&self, State* git, Canvas* canvas)
{
	if (!self.open) return;
	Rect screen = { .x = 0, .y = 0, .width = (float)rl::get_screen_width(), .height = (float)rl::get_screen_height() };
	rl::draw_rectangle_rec(screen, { 0, 0, 0, 170 });
	Rect panel = self.rect(canvas);
	ui::rounded_rect(panel, ui::corner_radius(), theme::current().panel_bg);
	ui::rounded_rect_lines(panel, ui::corner_radius(), 1.0f, theme::current().panel_border);
	Rect header = { .x = panel.x, .y = panel.y, .width = panel.width, .height = ui::pxf(42.0f) };
	ui::rounded_top(header, ui::corner_radius(), theme::current().panel_bg_alt);
	@pool()
	{
		String title = self.path.len > 0 ? string::format(tmem, "History  %s", self.path) : "History";
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

	float list_w = panel.width * 0.46f;
	float body_y = panel.y + header.height;
	float body_h = panel.height - header.height - ui::pxf(34.0f);
	Rect list    = { .x = panel.x, .y = body_y, .width = list_w, .height = body_h };
	Rect details = { .x = list.x + list_w, .y = body_y, .width = panel.width - list_w, .height = body_h };
	rl::draw_rectangle_rec({ .x = details.x, .y = details.y, .width = 1.0f, .height = details.height }, theme::current()
		.panel_border);

	if (git.commits.len() == 0)
	{
		draw_branch_text(list, "Loading history...", theme::current().panel_dim);
	}
	else
	{
		rl::begin_scissor_mode((int)list.x, (int)list.y, (int)list.width, (int)list.height);
		int visible = self.visible_commits(canvas);
		int last    = math::min(self.scroll + visible, (int)git.commits.len());
		for (int i = self.scroll; i < last; i++)
		{
			GitCommit* commit = git.commits.get_ref((sz)i);
			float y           = list.y + (float)(i - self.scroll) * ui::pxf(34.0f);
			if (i == self.selected && !self.file_focus)
			{
				ui::row(
					{
						.x = list.x + ui::pxf(4.0f),
						.y = y,
						.width = list.width - ui::pxf(8.0f),
						.height = ui::pxf(32.0f)
					},
					theme::current()
					.panel_selected);
			}
			@pool()
			{
				String short_hash = commit.short_hash;
				rl::draw_text_ex(
					ui::font(),
					short_hash.zstr_tcopy(),
					{ list.x + ui::pxf(10.0f), y + ui::pxf(2.0f) },
					(float)ui::tpx(11),
					0.0f,
					theme::current()
					.git_renamed);
				String meta = string::format(tmem, "%s  %s", commit.date, commit.subject);
				rl::draw_text_ex(
					ui::font(),
					meta.zstr_tcopy(),
					{ list.x + ui::pxf(68.0f), y + ui::pxf(2.0f) },
					(float)ui::tpx(11),
					0.0f,
					theme::current()
					.panel_text);
			};
		}
		rl::end_scissor_mode();
	}

	if (self.selected >= 0 && self.selected < (int)git.commits.len())
	{
		GitCommit* commit = git.commits.get_ref(self.selected);
		@pool()
		{
			String meta = string::format(tmem, "%s  %s  %s", commit.short_hash, commit.author, commit.date);
			rl::draw_text_ex(
				ui::font(),
				meta.zstr_tcopy(),
				{ details.x + ui::pxf(12.0f), details.y + ui::pxf(8.0f) },
				(float)ui::tpx(12),
				0.0f,
				theme::current()
				.panel_dim);
			rl::draw_text_ex(
				ui::font(),
				commit.subject.zstr_tcopy(),
				{ details.x + ui::pxf(12.0f), details.y + ui::pxf(28.0f) },
				(float)ui::tpx(13),
				0.0f,
				theme::current()
				.panel_text);
		};
		float files_y = details.y + ui::pxf(54.0f);
		rl::draw_text_ex(
			ui::font(),
			"Changed files",
			{ details.x + ui::pxf(12.0f), files_y },
			(float)ui::tpx(12),
			0.0f,
			theme::current()
			.panel_header);
		files_y += ui::pxf(20.0f);
		rl::begin_scissor_mode(
			(int)details.x,
			(int)files_y,
			(int)details.width,
			(int)(details.y + details.height - files_y)
		);
		for (sz i = 0; i < git.commit_files.len(); i++)
		{
			GitCommitFile* file = git.commit_files.get_ref(i);
			float y             = files_y + (float)i * ui::pxf(21.0f);
			if (i == (sz)self.file_selected && self.file_focus)
			{
				ui::row(
					{
						.x = details.x + ui::pxf(4.0f),
						.y = y,
						.width = details.width - ui::pxf(8.0f),
						.height = ui::pxf(20.0f)
					},
					theme::current()
					.panel_selected);
			}
			char[2] badge = { state_char(file.state), 0 };
			rl::draw_text_ex(
				ui::font(),
				(ZString)&badge[0],
				{ details.x + ui::pxf(12.0f), y + ui::pxf(2.0f) },
				(float)ui::tpx(12),
				0.0f,
				theme::current()
				.git_modified);
			@pool()
			{
				rl::draw_text_ex(
					ui::font(),
					file.path.zstr_tcopy(),
					{ details.x + ui::pxf(28.0f), y + ui::pxf(2.0f) },
					(float)ui::tpx(12),
					0.0f,
					theme::current()
					.panel_text);
			};
		}
		rl::end_scissor_mode();
	}

	@pool()
	{
		String hint = "Up/Down: commit    Tab: files    Enter: open diff    R: refresh    Esc: close";
		rl::draw_text_ex(
			ui::font(),
			hint.zstr_tcopy(),
			{ panel.x + ui::pxf(14.0f), panel.y + panel.height - ui::pxf(24.0f) },
			(float)ui::tpx(12),
			0.0f,
			theme::current()
			.panel_dim);
	};
}

fn void draw_branch_text(Rect area, String text, RLColor color)
{
	rl::draw_text_ex(
		ui::font(),
		text.zstr_tcopy(),
		{ area.x + ui::pxf(12.0f), area.y + ui::pxf(10.0f) },
		(float)ui::tpx(13),
		0.0f,
		color
	);
}