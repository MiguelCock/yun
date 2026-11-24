module yun::git;

import raylib6::rl;
import std::collections::list;
import std::core::mem::alloc;
import std::math;
import yun::canvas;
import yun::theme;
import yun::ui;

enum DiffMode : int
{
	INLINE,
	SIDE_BY_SIDE,
}

struct DiffRowView
{
	bool header;
	String header_text;
	bool has_left;
	bool has_right;
	DiffLineKind left_kind;
	DiffLineKind right_kind;
	String left_text;
	String right_text;
	int left_no;
	int right_no;
}

struct DiffView
{
	Allocator allocator;
	bool open;
	bool close_requested;
	DiffMode mode;
	int scroll;
	float h_scroll;
	ulong diff_seen;
	String path;
	String orig_path;
	bool staged;
	DiffFile diff;
	String error;
	List{DiffRowView} rows;
	int max_columns;
	int max_line_no;
}

fn void DiffView.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.open = false;
	self.close_requested = false;
	self.mode = DiffMode.SIDE_BY_SIDE;
	self.scroll = 0;
	self.h_scroll = 0.0f;
	self.diff_seen = 0;
	self.path = "";
	self.orig_path = "";
	self.staged = false;
	self.diff.init(allocator);
	self.error = "";
	self.rows.init(allocator);
	self.max_columns = 0;
	self.max_line_no = 0;
}

fn void DiffView.destroy(&self)
{
	self.diff.destroy();
	self.rows.free();
	if (self.path.len > 0) self.path.free(self.allocator);
	if (self.orig_path.len > 0) self.orig_path.free(self.allocator);
	if (self.error.len > 0) self.error.free(self.allocator);
}

fn void DiffView.close(&self)
{
	self.open = false;
	self.close_requested = true;
}

fn String diff_basename(String path)
{
	for (sz i = (sz)path.len; i > 0; i--)
	{
		if (path[(usz)(i - 1)] == '/') return path[(usz)i:path.len - (usz)i];
	}
	return path;
}

fn void DiffView.add_header(&self, String text)
{
	self.rows.push({ .header = true, .header_text = text });
}

fn void DiffView.add_inline(&self, DiffLine* line)
{
	self.rows.push(
		{
			.has_left = true,
			.left_kind = line.kind,
			.left_text = line.text,
			.left_no = line.old_line > 0 ? line.old_line : line.new_line,
		}
	);
}

fn void DiffView.add_side(&self, DiffLine* left, DiffLine* right)
{
	DiffRowView row;
	row.header = false;
	row.header_text = "";
	row.has_left = left != null;
	row.has_right = right != null;
	row.left_kind = left ? left.kind : DiffLineKind.CONTEXT;
	row.right_kind = right ? right.kind : DiffLineKind.CONTEXT;
	row.left_text = left ? left.text : "";
	row.right_text = right ? right.text : "";
	row.left_no = left ? left.old_line : 0;
	row.right_no = right ? right.new_line : 0;
	self.rows.push(row);
}

fn void DiffView.add_side_hunk(&self, DiffHunk* hunk)
{
	sz i = 0;
	while (i < hunk.lines.len())
	{
		DiffLine* line = &hunk.lines[i];
		if (line.kind == DiffLineKind.CONTEXT)
		{
			self.add_side(line, line);
			i++;
			continue;
		}
		if (line.kind == DiffLineKind.DELETE)
		{
			sz del_start = i;
			while (i < hunk.lines.len() && hunk.lines[i].kind == DiffLineKind.DELETE) i++;
			sz add_start = i;
			while (i < hunk.lines.len() && hunk.lines[i].kind == DiffLineKind.ADD) i++;
			sz del_count = add_start - del_start;
			sz add_count = i - add_start;
			sz count     = del_count > add_count ? del_count : add_count;
			for (sz k = 0; k < count; k++)
			{
				DiffLine* left  = k < del_count ? &hunk.lines[del_start + k] : null;
				DiffLine* right = k < add_count ? &hunk.lines[add_start + k] : null;
				self.add_side(left, right);
			}
			continue;
		}
		if (line.kind == DiffLineKind.ADD)
		{
			self.add_side(null, line);
			i++;
			continue;
		}
		self.add_side(line, null);
		i++;
	}
}

fn void DiffView.rebuild(&self)
{
	self.rows.clear();
	self.max_columns = 0;
	self.max_line_no = 0;
	for (sz h = 0; h < self.diff.hunks.len(); h++)
	{
		DiffHunk* hunk = &self.diff.hunks[h];
		self.add_header(hunk.header);
		int old_end = hunk.old_start + hunk.old_count;
		int new_end = hunk.new_start + hunk.new_count;
		if (old_end > self.max_line_no) self.max_line_no = old_end;
		if (new_end > self.max_line_no) self.max_line_no = new_end;
		for (sz i = 0; i < hunk.lines.len(); i++)
		{
			DiffLine* line = &hunk.lines[i];
			if (line.text.len > (usz)self.max_columns) self.max_columns = (int)line.text.len;
			if (self.mode == DiffMode.INLINE)
			{
				self.add_inline(line);
			}
		}
		if (self.mode == DiffMode.SIDE_BY_SIDE) self.add_side_hunk(hunk);
	}
	if (self.scroll > (int)self.rows.len() - 1) self.scroll = (int)self.rows.len() - 1;
	if (self.scroll < 0) self.scroll = 0;
}

fn bool DiffView.sync(&self, State* git)
{
	if (git.diff_revision == self.diff_seen) return false;
	self.diff_seen = git.diff_revision;
	if (!git.diff.valid) return false;
	if (git.diff.exit_code != 0 && git.diff.output.len == 0)
	{
		self.diff.destroy();
		self.diff.init(self.allocator);
		if (self.error.len > 0) self.error.free(self.allocator);
		self.error = git.diff.error.len > 0 ? git.diff.error.copy(self.allocator)
			: "Could not load diff.".copy(self.allocator);
		self.rows.clear();
		self.open = true;
		self.scroll = 0;
		self.h_scroll = 0.0f;
		if (self.path.len > 0) self.path.free(self.allocator);
		if (self.orig_path.len > 0) self.orig_path.free(self.allocator);
		self.path = git.diff.path.len > 0 ? git.diff.path.copy(self.allocator) : "";
		self.orig_path = "";
		self.staged = git.diff.staged;
		return true;
	}
	self.diff.destroy();
	self.diff.init(self.allocator);
	self.diff.parse(git.diff.output);
	self.diff.truncated = git.diff.truncated;
	if (self.error.len > 0) self.error.free(self.allocator);
	self.error = "";
	if (self.path.len > 0) self.path.free(self.allocator);
	if (self.orig_path.len > 0) self.orig_path.free(self.allocator);
	self.path = git.diff.path.len > 0 ? git.diff.path.copy(self.allocator) : "";
	self.orig_path = git.diff.orig_path.len > 0 ? git.diff.orig_path.copy(self.allocator) : "";
	self.staged = git.diff.staged;
	self.open = true;
	self.scroll = 0;
	self.h_scroll = 0.0f;
	self.rebuild();
	return true;
}

fn Rect DiffView.rect(&self, Canvas* canvas)
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

fn float DiffView.line_height(&self)
{
	return ui::tpxf(18.0f);
}

fn int DiffView.visible_rows(&self, Canvas* canvas)
{
	Rect panel   = self.rect(canvas);
	float body_h = panel.height - ui::pxf(76.0f);
	int rows     = (int)(body_h / self.line_height());
	return rows < 1 ? 1 : rows;
}

fn void DiffView.ensure_visible(&self, Canvas* canvas)
{
	int visible = self.visible_rows(canvas);
	int max     = (int)self.rows.len() - visible;
	if (max < 0) max = 0;
	if (self.scroll > max) self.scroll = max;
	if (self.scroll < 0) self.scroll = 0;
}

fn void DiffView.update(&self, Canvas* canvas, double now)
{
	if (!self.open) return;
	self.close_requested = false;
	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		self.open = false;
		self.close_requested = true;
		return;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.TAB))
	{
		self.mode = self.mode == DiffMode.INLINE ? DiffMode.SIDE_BY_SIDE : DiffMode.INLINE;
		self.rebuild();
	}
	int visible = self.visible_rows(canvas);
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP)) self.scroll--;
	if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN)) self.scroll++;
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_UP)) self.scroll -= visible;
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_DOWN)) self.scroll += visible;
	if (rl::is_key_pressed(rl::RLKeyboardKey.HOME)) self.scroll = 0;
	if (rl::is_key_pressed(rl::RLKeyboardKey.END)) self.scroll = (int)self.rows.len() - visible;
	if (rl::is_key_pressed(rl::RLKeyboardKey.LEFT)) self.h_scroll -= ui::pxf(40.0f);
	if (rl::is_key_pressed(rl::RLKeyboardKey.RIGHT)) self.h_scroll += ui::pxf(40.0f);
	float wheel = rl::get_mouse_wheel_move();
	if (wheel != 0.0f)
	{
		if (rl::is_key_down(rl::RLKeyboardKey.LEFT_SHIFT) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SHIFT))
		{
			self.h_scroll -= wheel * ui::pxf(40.0f);
		}
		else
		{
			self.scroll -= (int)wheel * 3;
		}
	}
	if (self.h_scroll < 0.0f) self.h_scroll = 0.0f;
	float char_w     = rl::measure_text_ex(ui::font(), "M", (float)ui::tpx(14), 0.0f)[0];
	float max_scroll = (float)self.max_columns * char_w;
	if (self.h_scroll > max_scroll) self.h_scroll = max_scroll;
	self.ensure_visible(canvas);
}

fn void draw_line_number(float x, float width, float y, int line, float text_size, RLColor color)
{
	if (line <= 0) return;
	@pool()
	{
		String text    = string::format(tmem, "%d", (long)line);
		float measured = rl::measure_text_ex(ui::font(), text.zstr_tcopy(), text_size, 0.0f)[0];
		rl::draw_text_ex(
			ui::font(),
			text.zstr_tcopy(),
			{ x + width - measured - ui::pxf(4.0f), y },
			text_size,
			0.0f,
			color
		);
	};
}

fn void draw_row_text(float x, float y, String text, float text_size, RLColor color)
{
	if (text.len == 0) return;
	@pool()
	{
		rl::draw_text_ex(ui::font(), text.zstr_tcopy(), { x, y }, text_size, 0.0f, color);
	};
}

fn RLColor diff_text_color(DiffLineKind kind)
{
	switch (kind)
	{
		case DiffLineKind.ADD:
			return theme::current().git_added;
		case DiffLineKind.DELETE:
			return theme::current().git_deleted;
		case DiffLineKind.META:
			return theme::current().panel_disabled;
		case DiffLineKind.CONTEXT:
			break;
	}
	return theme::current().panel_text;
}

fn void DiffView.draw(&self, Canvas* canvas)
{
	if (!self.open) return;
	Rect screen = {
		.x = 0.0f,
		.y = 0.0f,
		.width = (float)rl::get_screen_width(),
		.height = (float)rl::get_screen_height(),
	};
	rl::draw_rectangle_rec(screen, { 0, 0, 0, 170 });
	Rect panel = self.rect(canvas);
	ui::rounded_rect(panel, ui::corner_radius(), theme::current().panel_bg);
	ui::rounded_rect_lines(panel, ui::corner_radius(), 1.0f, theme::current().panel_border);

	float text_size = (float)ui::tpx(14);
	float char_w    = rl::measure_text_ex(ui::font(), "M", text_size, 0.0f)[0];
	float line_h    = self.line_height();
	float header_h  = ui::pxf(38.0f);
	float footer_h  = ui::pxf(38.0f);
	Rect header = {
		.x = panel.x,
		.y = panel.y,
		.width = panel.width,
		.height = header_h,
	};
	ui::rounded_top(header, ui::corner_radius(), theme::current().panel_bg_alt);
	@pool()
	{
		String title = string::format(
			tmem,
			"%s  %s",
			self.staged ? "Staged" : "Working tree",
			diff_basename(self.path)
		);
		rl::draw_text_ex(
			ui::font(),
			title.zstr_tcopy(),
			{ header.x + ui::pxf(12.0f), header.y + ui::pxf(9.0f) },
			(float)ui::tpx(16),
			0.0f,
			theme::current()
			.panel_text);
		String stats  = string::format(tmem, "+%d  -%d", (long)self.diff.additions, (long)self.diff.deletions);
		float stats_w = rl::measure_text_ex(ui::font(), stats.zstr_tcopy(), (float)ui::tpx(13), 0.0f)[0];
		rl::draw_text_ex(
			ui::font(),
			stats.zstr_tcopy(),
			{ header.x + header.width - stats_w - ui::pxf(14.0f), header.y + ui::pxf(12.0f) },
			(float)ui::tpx(13),
			0.0f,
			theme::current()
			.panel_dim);
	};
	rl::draw_rectangle_rec(
		{ .x = header.x, .y = header.y + header.height - 1.0f, .width = header.width, .height = 1.0f },
		theme::current()
		.panel_border);

	Rect body = {
		.x = panel.x,
		.y = header.y + header.height,
		.width = panel.width,
		.height = panel.height - header_h - footer_h,
	};
	if (body.height < line_h) body.height = line_h;

	if (self.error.len > 0)
	{
		draw_row_text(body.x + ui::pxf(16.0f), body.y + ui::pxf(16.0f), self.error, (float)ui::tpx(13), theme::current()
			.git_conflict);
	}
	else if (self.diff.binary)
	{
		draw_row_text(
			body.x + ui::pxf(16.0f),
			body.y + ui::pxf(16.0f),
			"Binary file",
			(float)ui::tpx(13),
			theme::current()
			.panel_dim);
	}
	else if (self.rows.len() == 0)
	{
		draw_row_text(
			body.x + ui::pxf(16.0f),
			body.y + ui::pxf(16.0f),
			"No changes",
			(float)ui::tpx(13),
			theme::current()
			.panel_dim);
	}
	else
	{
		int visible = self.visible_rows(canvas);
		int last    = math::min(self.scroll + visible, (int)self.rows.len());
		int digits  = 1;
		int max_no  = self.max_line_no;
		while (max_no >= 10)
		{
			digits++;
			max_no /= 10;
		}
		float gutter    = (float)digits * char_w + ui::pxf(14.0f);
		bool side       = self.mode == DiffMode.SIDE_BY_SIDE;
		float half      = (body.width - 1.0f) / 2.0f;
		Rect left_rect  = { .x = body.x, .y = body.y, .width = half, .height = body.height };
		Rect right_rect = { .x = body.x + half + 1.0f, .y = body.y, .width = half, .height = body.height };

		rl::begin_scissor_mode((int)body.x, (int)body.y, (int)body.width, (int)body.height);
		for (int i = self.scroll; i < last; i++)
		{
			DiffRowView* row = &self.rows[i];
			float y          = body.y + (float)(i - self.scroll) * line_h;
			if (row.header)
			{
				rl::draw_rectangle_rec({ .x = body.x, .y = y, .width = body.width, .height = line_h }, theme::current()
					.panel_bg_alt);
				draw_row_text(
					body.x + ui::pxf(10.0f),
					y + ui::pxf(2.0f),
					row.header_text,
					(float)ui::tpx(13),
					theme::current()
					.panel_header);
				continue;
			}
			if (!side)
			{
				if (row.left_kind == DiffLineKind.ADD)
				{
					rl::draw_rectangle_rec(
						{ .x = body.x, .y = y, .width = body.width, .height = line_h },
						theme::with_alpha(theme::current()
						.git_added, 28));
				}
				else if (row.left_kind == DiffLineKind.DELETE)
				{
					rl::draw_rectangle_rec(
						{ .x = body.x, .y = y, .width = body.width, .height = line_h },
						theme::with_alpha(theme::current()
						.git_deleted, 28));
				}
				draw_line_number(body.x, gutter, y + ui::pxf(1.0f), row.left_no, (float)ui::tpx(13), theme::current()
					.panel_dim);
				if (row.left_kind == DiffLineKind.ADD)
				{
					draw_row_text(body.x + gutter, y + ui::pxf(1.0f), "+", text_size, theme::current().git_added);
				}
				else if (row.left_kind == DiffLineKind.DELETE)
				{
					draw_row_text(body.x + gutter, y + ui::pxf(1.0f), "-", text_size, theme::current().git_deleted);
				}
				continue;
			}
			if (row.has_left && row.left_kind == DiffLineKind.DELETE)
			{
				rl::draw_rectangle_rec(
					{ .x = left_rect.x, .y = y, .width = left_rect.width, .height = line_h },
					theme::with_alpha(theme::current()
					.git_deleted, 28));
			}
			if (row.has_right && row.right_kind == DiffLineKind.ADD)
			{
				rl::draw_rectangle_rec(
					{ .x = right_rect.x, .y = y, .width = right_rect.width, .height = line_h },
					theme::with_alpha(theme::current()
					.git_added, 28));
			}
			if (row.has_left)
			{
				draw_line_number(
					left_rect.x,
					gutter,
					y + ui::pxf(1.0f),
					row.left_no,
					(float)ui::tpx(13),
					theme::current()
					.panel_dim);
			}
			if (row.has_right)
			{
				draw_line_number(
					right_rect.x,
					gutter,
					y + ui::pxf(1.0f),
					row.right_no,
					(float)ui::tpx(13),
					theme::current()
					.panel_dim);
			}
		}
		rl::end_scissor_mode();

		if (side)
		{
			rl::draw_rectangle_rec(
				{ .x = body.x + half, .y = body.y, .width = 1.0f, .height = body.height },
				theme::current()
				.panel_border);
			rl::begin_scissor_mode(
				(int)(left_rect.x + gutter),
				(int)body.y,
				(int)(left_rect.width - gutter),
				(int)body.height
			);
			for (int i = self.scroll; i < last; i++)
			{
				DiffRowView* row = &self.rows[i];
				if (!row.has_left || row.header) continue;
				float y = body.y + (float)(i - self.scroll) * line_h + ui::pxf(1.0f);
				draw_row_text(
					left_rect.x + gutter - self.h_scroll,
					y,
					row.left_text,
					text_size,
					diff_text_color(row.left_kind)
				);
			}
			rl::end_scissor_mode();
			rl::begin_scissor_mode(
				(int)(right_rect.x + gutter),
				(int)body.y,
				(int)(right_rect.width - gutter),
				(int)body.height
			);
			for (int i = self.scroll; i < last; i++)
			{
				DiffRowView* row = &self.rows[i];
				if (!row.has_right || row.header) continue;
				float y = body.y + (float)(i - self.scroll) * line_h + ui::pxf(1.0f);
				draw_row_text(
					right_rect.x + gutter - self.h_scroll,
					y,
					row.right_text,
					text_size,
					diff_text_color(row.right_kind)
				);
			}
			rl::end_scissor_mode();
		}
		else
		{
			rl::begin_scissor_mode(
				(int)(body.x + gutter + char_w),
				(int)body.y,
				(int)(body.width - gutter - char_w),
				(int)body.height
			);
			for (int i = self.scroll; i < last; i++)
			{
				DiffRowView* row = &self.rows[i];
				if (row.header) continue;
				float y = body.y + (float)(i - self.scroll) * line_h + ui::pxf(1.0f);
				draw_row_text(
					body.x + gutter + char_w - self.h_scroll,
					y,
					row.left_text,
					text_size,
					diff_text_color(row.left_kind)
				);
			}
			rl::end_scissor_mode();
		}
	}

	Rect footer = {
		.x = panel.x,
		.y = panel.y + panel.height - footer_h,
		.width = panel.width,
		.height = footer_h,
	};
	rl::draw_rectangle_rec({ .x = footer.x, .y = footer.y, .width = footer.width, .height = 1.0f }, theme::current()
		.panel_border);
	String mode_label = self.mode == DiffMode.INLINE ? "Inline" : "Side by side";
	@pool()
	{
		String hint = string::format(tmem, "%s    Tab: mode    Esc: close    Up/Down: scroll", mode_label);
		rl::draw_text_ex(
			ui::font(),
			hint.zstr_tcopy(),
			{ footer.x + ui::pxf(12.0f), footer.y + ui::pxf(12.0f) },
			(float)ui::tpx(13),
			0.0f,
			theme::current()
			.panel_dim);
		if (self.diff.truncated)
		{
			String truncated = "truncated";
			float w          = rl::measure_text_ex(ui::font(), truncated.zstr_tcopy(), (float)ui::tpx(13), 0.0f)[0];
			rl::draw_text_ex(
				ui::font(),
				truncated.zstr_tcopy(),
				{ footer.x + footer.width - w - ui::pxf(12.0f), footer.y + ui::pxf(12.0f) },
				(float)ui::tpx(13),
				0.0f,
				theme::current()
				.panel_disabled);
		}
	};
}