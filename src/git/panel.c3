module yun::git;

import raylib6::rl;
import std::collections::list;
import std::core::mem::alloc;
import std::io::file;
import std::math;
import yun::canvas;
import yun::theme;
import yun::ui;

const float PANEL_WIDTH   = 286.0f;
const float HEADER_H      = 30.0f;
const float BRANCH_H      = 24.0f;
const float REMOTE_H      = 26.0f;
const float SECTION_H     = 21.0f;
const float ROW_H         = 23.0f;
const float COMMIT_H      = 112.0f;
const float PAD           = 8.0f;
const int COMMIT_MAX      = 2048;
const int BRANCH_NAME_MAX = 128;
const int SCROLL_LINES    = 3;

enum PanelRowKind : int
{
	CONFLICT_HEADER,
	STAGED_HEADER,
	CHANGES_HEADER,
	UNTRACKED_HEADER,
	FILE_CONFLICT,
	FILE_STAGED,
	FILE_UNSTAGED,
	FILE_UNTRACKED,
}

struct PanelRow
{
	PanelRowKind kind;
	int entry;
}

struct Panel
{
	Allocator allocator;
	bool visible;
	bool focused;
	float bottom_inset;
	List{PanelRow} rows;
	ulong rows_revision;
	int selected;
	int scroll;
	int conflicts;
	int staged;
	int changes;
	int untracked;
	char[COMMIT_MAX] message;
	int message_len;
	int message_cursor;
	int commit_scroll;
	bool commit_focus;
	ulong action_seen;
	bool confirm_open;
	int confirm_row;
	bool error_open;
	bool branch_open;
	bool branch_create;
	bool sync_pending;
	bool editors_dirty;
	String branch_warning;
	int branch_selected;
	int branch_scroll;
	char[BRANCH_NAME_MAX] branch_input;
	int branch_input_len;
	String pending_open;
	bool open_pending;
	String pending_resolve_rel;
	String pending_resolve_abs;
	bool resolve_pending;
	bool history_pending;
	String pending_history_path;
	bool leave_requested;
	bool focus_requested;
}

fn void Panel.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.visible = false;
	self.focused = false;
	self.bottom_inset = 0.0f;
	self.rows.init(allocator);
	self.rows_revision = 0;
	self.selected = -1;
	self.scroll = 0;
	self.conflicts = 0;
	self.staged = 0;
	self.changes = 0;
	self.untracked = 0;
	self.message[0] = 0;
	self.message_len = 0;
	self.message_cursor = 0;
	self.commit_scroll = 0;
	self.commit_focus = false;
	self.action_seen = 0;
	self.confirm_open = false;
	self.confirm_row = -1;
	self.error_open = false;
	self.branch_open = false;
	self.branch_create = false;
	self.sync_pending = false;
	self.editors_dirty = false;
	self.branch_warning = "";
	self.branch_selected = -1;
	self.branch_scroll = 0;
	self.branch_input[0] = 0;
	self.branch_input_len = 0;
	self.pending_open = "";
	self.open_pending = false;
	self.pending_resolve_rel = "";
	self.pending_resolve_abs = "";
	self.resolve_pending = false;
	self.history_pending = false;
	self.pending_history_path = "";
	self.leave_requested = false;
	self.focus_requested = false;
}

fn void Panel.destroy(&self)
{
	self.rows.free();
	if (self.pending_open.len > 0) self.pending_open.free(self.allocator);
	if (self.pending_resolve_rel.len > 0) self.pending_resolve_rel.free(self.allocator);
	if (self.pending_resolve_abs.len > 0) self.pending_resolve_abs.free(self.allocator);
	if (self.pending_history_path.len > 0) self.pending_history_path.free(self.allocator);
	if (self.branch_warning.len > 0) self.branch_warning.free(self.allocator);
}

fn void Panel.open(&self)
{
	self.visible = true;
	self.focus_requested = true;
	self.leave_requested = false;
}

fn void Panel.close(&self)
{
	self.visible = false;
	self.focused = false;
	self.bottom_inset = 0.0f;
	self.confirm_open = false;
	self.branch_open = false;
	self.branch_create = false;
}

fn float Panel.width(&self, Canvas* canvas)
{
	float width = ui::pxf(PANEL_WIDTH);
	float limit = (float)rl::get_screen_width() * 0.6f;
	if (width > limit) width = limit;
	if (width < ui::pxf(180.0f)) width = ui::pxf(180.0f);
	return width;
}

fn Rect Panel.rect(&self, Canvas* canvas)
{
	float width  = self.width(canvas);
	float height = (float)rl::get_screen_height() - canvas.top_inset - self.bottom_inset;
	if (height < 0.0f) height = 0.0f;
	return { .x = 0.0f, .y = canvas.top_inset, .width = width, .height = height };
}

fn bool Panel.contains_screen(&self, Canvas* canvas, RLVector2 point)
{
	return self.visible && rect_contains(self.rect(canvas), point);
}

fn Rect Panel.branch_rect(&self, Canvas* canvas)
{
	Rect header = self.header_rect(canvas);
	return {
		.x = header.x,
		.y = header.y + header.height,
		.width = header.width,
		.height = ui::pxf(BRANCH_H),
	};
}

fn Rect Panel.remote_rect(&self, Canvas* canvas)
{
	Rect branch = self.branch_rect(canvas);
	return {
		.x = branch.x,
		.y = branch.y + branch.height,
		.width = branch.width,
		.height = ui::pxf(REMOTE_H),
	};
}

fn Rect Panel.header_rect(&self, Canvas* canvas)
{
	Rect panel = self.rect(canvas);
	return { .x = panel.x, .y = panel.y, .width = panel.width, .height = ui::pxf(HEADER_H) };
}

fn Rect Panel.commit_rect(&self, Canvas* canvas)
{
	Rect panel = self.rect(canvas);
	float h    = ui::pxf(COMMIT_H);
	if (h > panel.height) h = panel.height;
	return { .x = panel.x, .y = panel.y + panel.height - h, .width = panel.width, .height = h };
}

fn Rect Panel.list_rect(&self, Canvas* canvas)
{
	Rect panel   = self.rect(canvas);
	Rect commit  = self.commit_rect(canvas);
	float top    = panel.y + ui::pxf(HEADER_H) + ui::pxf(BRANCH_H) + ui::pxf(REMOTE_H);
	float bottom = commit.y;
	if (bottom < top) bottom = top;
	return { .x = panel.x, .y = top, .width = panel.width, .height = bottom - top };
}

fn bool row_is_file(PanelRowKind kind)
{
	return kind == PanelRowKind.FILE_CONFLICT || kind == PanelRowKind.FILE_STAGED || kind == PanelRowKind.FILE_UNSTAGED
		|| kind == PanelRowKind.FILE_UNTRACKED;
}

fn void Panel.add_header(&self, PanelRowKind kind)
{
	self.rows.push({ .kind = kind, .entry = -1 });
}

fn void Panel.add_file(&self, PanelRowKind kind, int entry)
{
	self.rows.push({ .kind = kind, .entry = entry });
}

fn void Panel.rebuild(&self, State* git)
{
	self.rows.clear();
	self.conflicts = 0;
	self.staged = 0;
	self.changes = 0;
	self.untracked = 0;
	if (!git.has_status || !git.status.valid)
	{
		self.rows_revision = git.status_revision;
		self.selected = -1;
		self.scroll = 0;
		return;
	}
	for (sz i = 0; i < git.status.entries.len(); i++)
	{
		GitEntry* entry = &git.status.entries[i];
		if (entry.conflicted)
		{
			self.conflicts++;
		}
		else if (entry.untracked)
		{
			self.untracked++;
		}
		else
		{
			if (entry_has_staged(entry)) self.staged++;
			if (entry_has_unstaged(entry)) self.changes++;
		}
	}
	if (self.conflicts > 0)
	{
		self.add_header(PanelRowKind.CONFLICT_HEADER);
		for (sz i = 0; i < git.status.entries.len(); i++)
		{
			if (git.status.entries[i].conflicted) self.add_file(PanelRowKind.FILE_CONFLICT, (int)i);
		}
	}
	self.add_header(PanelRowKind.STAGED_HEADER);
	for (sz i = 0; i < git.status.entries.len(); i++)
	{
		GitEntry* entry = &git.status.entries[i];
		if (!entry.conflicted && entry_has_staged(entry)) self.add_file(PanelRowKind.FILE_STAGED, (int)i);
	}
	self.add_header(PanelRowKind.CHANGES_HEADER);
	for (sz i = 0; i < git.status.entries.len(); i++)
	{
		GitEntry* entry = &git.status.entries[i];
		if (!entry.conflicted && entry_has_unstaged(entry)) self.add_file(PanelRowKind.FILE_UNSTAGED, (int)i);
	}
	self.add_header(PanelRowKind.UNTRACKED_HEADER);
	for (sz i = 0; i < git.status.entries.len(); i++)
	{
		if (git.status.entries[i].untracked) self.add_file(PanelRowKind.FILE_UNTRACKED, (int)i);
	}
	self.rows_revision = git.status_revision;
	if (self.selected < 0 || self.selected >= (int)self.rows.len() || !row_is_file(self.rows[self.selected].kind))
	{
		self.select_first();
	}
}

fn void Panel.select_first(&self)
{
	for (sz i = 0; i < self.rows.len(); i++)
	{
		if (row_is_file(self.rows[i].kind))
		{
			self.selected = (int)i;
			return;
		}
	}
	self.selected = -1;
}

fn void Panel.move_selection(&self, int delta)
{
	if (self.rows.len() == 0) return;
	int start = self.selected;
	if (start < 0) start = delta > 0 ? -1 : (int)self.rows.len();
	int at = start;
	for (int i = 0; i < (int)self.rows.len(); i++)
	{
		at += delta;
		if (at < 0 || at >= (int)self.rows.len()) break;
		if (row_is_file(self.rows[at].kind))
		{
			self.selected = at;
			return;
		}
	}
}

fn void Panel.page_selection(&self, int direction, int visible)
{
	if (visible < 1) visible = 1;
	for (int i = 0; i < visible; i++) self.move_selection(direction);
}

fn int Panel.visible_rows(&self, Canvas* canvas)
{
	Rect list = self.list_rect(canvas);
	int rows  = (int)(list.height / ui::pxf(ROW_H));
	return rows < 1 ? 1 : rows;
}

fn void Panel.ensure_visible(&self, Canvas* canvas)
{
	if (self.selected < 0) return;
	int visible = self.visible_rows(canvas);
	if (self.selected < self.scroll) self.scroll = self.selected;
	if (self.selected >= self.scroll + visible) self.scroll = self.selected - visible + 1;
	int max = (int)self.rows.len() - visible;
	if (max < 0) max = 0;
	if (self.scroll > max) self.scroll = max;
	if (self.scroll < 0) self.scroll = 0;
}

fn PanelRow* Panel.selected_row(&self)
{
	if (self.selected < 0 || self.selected >= (int)self.rows.len()) return null;
	return &self.rows[self.selected];
}

fn GitEntry* Panel.entry_for(&self, State* git, int index)
{
	if (!git.has_status || index < 0 || index >= (int)git.status.entries.len()) return null;
	return &git.status.entries[index];
}

fn bool rect_contains(Rect rect, RLVector2 point)
{
	return point[0] >= rect.x && point[0] <= rect.x + rect.width && point[1] >= rect.y
		&& point[1] <= rect.y + rect.height;
}

fn bool ctrl_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_CONTROL) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_CONTROL);
}

fn bool shift_down()
{
	return rl::is_key_down(rl::RLKeyboardKey.LEFT_SHIFT) || rl::is_key_down(rl::RLKeyboardKey.RIGHT_SHIFT);
}

fn void Panel.set_message(&self, String text)
{
	self.message_len = 0;
	for (usz i = 0; i < text.len && self.message_len < COMMIT_MAX - 1; i++)
	{
		char c = text[i];
		if (c == '\r') continue;
		self.message[self.message_len] = c;
		self.message_len++;
	}
	self.message[self.message_len] = 0;
	self.message_cursor = self.message_len;
	self.commit_scroll = 0;
}

fn void Panel.clear_message(&self)
{
	self.message_len = 0;
	self.message_cursor = 0;
	self.commit_scroll = 0;
	self.message[0] = 0;
}

fn void Panel.insert_char(&self, char c)
{
	if (self.message_len >= COMMIT_MAX - 1) return;
	for (int i = self.message_len; i > self.message_cursor; i--)
	{
		self.message[i] = self.message[i - 1];
	}
	self.message[self.message_cursor] = c;
	self.message_cursor++;
	self.message_len++;
	self.message[self.message_len] = 0;
}

fn void Panel.insert_text(&self, String text)
{
	for (usz i = 0; i < text.len; i++)
	{
		char c = text[i];
		if (c == '\r') continue;
		self.insert_char(c);
	}
}

fn void Panel.backspace(&self)
{
	if (self.message_cursor <= 0) return;
	for (int i = self.message_cursor - 1; i < self.message_len - 1; i++)
	{
		self.message[i] = self.message[i + 1];
	}
	self.message_cursor--;
	self.message_len--;
	self.message[self.message_len] = 0;
}

fn void Panel.delete_forward(&self)
{
	if (self.message_cursor >= self.message_len) return;
	for (int i = self.message_cursor; i < self.message_len - 1; i++)
	{
		self.message[i] = self.message[i + 1];
	}
	self.message_len--;
	self.message[self.message_len] = 0;
}

fn int Panel.line_start(&self, int pos)
{
	if (pos > self.message_len) pos = self.message_len;
	while (pos > 0 && self.message[pos - 1] != '\n') pos--;
	return pos;
}

fn int Panel.line_end(&self, int pos)
{
	if (pos < 0) pos = 0;
	while (pos < self.message_len && self.message[pos] != '\n') pos++;
	return pos;
}

fn void Panel.move_vertical(&self, int direction)
{
	int line_start = self.line_start(self.message_cursor);
	int column     = self.message_cursor - line_start;
	if (direction < 0)
	{
		if (line_start == 0) return;
		int prev_end   = line_start - 1;
		int prev_start = self.line_start(prev_end);
		int target     = prev_start + math::min(column, prev_end - prev_start);
		self.message_cursor = target;
		return;
	}
	int line_end = self.line_end(self.message_cursor);
	if (line_end >= self.message_len) return;
	int next_start = line_end + 1;
	int next_end   = self.line_end(next_start);
	int target     = next_start + math::min(column, next_end - next_start);
	self.message_cursor = target;
}

fn String Panel.message_view(&self)
{
	return (String)self.message[0:self.message_len];
}

fn String Panel.selected_path(&self, State* git)
{
	PanelRow* row = self.selected_row();
	if (!row) return "";
	GitEntry* entry = self.entry_for(git, row.entry);
	return entry ? entry.path : "";
}

fn bool Panel.selected_staged(&self, State* git)
{
	PanelRow* row = self.selected_row();
	return row && row.kind == PanelRowKind.FILE_STAGED;
}

fn void Panel.request_open(&self, State* git)
{
	PanelRow* row = self.selected_row();
	if (!row) return;
	GitEntry* entry = self.entry_for(git, row.entry);
	if (!entry) return;
	if (self.pending_open.len > 0) self.pending_open.free(self.allocator);
	self.pending_open = entry.abs_path.copy(self.allocator);
	self.open_pending = true;
}

fn void Panel.request_resolve(&self, State* git)
{
	PanelRow* row = self.selected_row();
	if (!row || row.kind != PanelRowKind.FILE_CONFLICT) return;
	GitEntry* entry = self.entry_for(git, row.entry);
	if (!entry) return;
	if (self.pending_resolve_rel.len > 0) self.pending_resolve_rel.free(self.allocator);
	if (self.pending_resolve_abs.len > 0) self.pending_resolve_abs.free(self.allocator);
	self.pending_resolve_rel = entry.path.copy(self.allocator);
	self.pending_resolve_abs = entry.abs_path.copy(self.allocator);
	self.resolve_pending = true;
}

fn void Panel.request_diff(&self, State* git)
{
	PanelRow* row = self.selected_row();
	if (!row) return;
	GitEntry* entry = self.entry_for(git, row.entry);
	if (!entry) return;
	bool staged = row.kind == PanelRowKind.FILE_STAGED;
	(void)git.request_diff(entry.path, entry.orig_path, staged, row.kind == PanelRowKind.FILE_UNTRACKED);
}

fn void Panel.stage_selected(&self, State* git, double now)
{
	PanelRow* row = self.selected_row();
	if (!row) return;
	GitEntry* entry = self.entry_for(git, row.entry);
	if (!entry) return;
	String[] paths = alloc::new_array(tmem, String, 1);
	paths[0] = entry.path;
	if (row.kind == PanelRowKind.FILE_STAGED)
	{
		(void)git.unstage(paths);
	}
	else if (row.kind == PanelRowKind.FILE_UNSTAGED || row.kind == PanelRowKind.FILE_UNTRACKED)
	{
		(void)git.stage(paths);
	}
	git.mark_dirty(now);
}

fn String[] collect_paths(State* git, bool staged)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		for (sz i = 0; i < git.status.entries.len(); i++)
		{
			GitEntry* entry = &git.status.entries[i];
			if (entry.conflicted) continue;
			if (staged && entry_has_staged(entry)) list.push(entry.path);
			if (!staged && (entry_has_unstaged(entry) || entry.untracked)) list.push(entry.path);
		}
		return alloc::new_array(tmem, String, (sz)list.len());
	};
}

fn int count_paths(State* git, bool staged)
{
	int count = 0;
	for (sz i = 0; i < git.status.entries.len(); i++)
	{
		GitEntry* entry = &git.status.entries[i];
		if (entry.conflicted) continue;
		if (staged && entry_has_staged(entry)) count++;
		if (!staged && (entry_has_unstaged(entry) || entry.untracked)) count++;
	}
	return count;
}

fn void fill_paths(State* git, bool staged, String[] out)
{
	int at = 0;
	for (sz i = 0; i < git.status.entries.len(); i++)
	{
		GitEntry* entry = &git.status.entries[i];
		if (entry.conflicted) continue;
		if (staged && entry_has_staged(entry)) out[at++] = entry.path;
		if (!staged && (entry_has_unstaged(entry) || entry.untracked)) out[at++] = entry.path;
	}
}

fn void Panel.stage_all(&self, State* git, double now, bool staged)
{
	int count = count_paths(git, staged);
	if (count == 0) return;
	String[] paths = alloc::new_array(tmem, String, count);
	fill_paths(git, staged, paths);
	if (staged)
	{
		(void)git.unstage(paths);
	}
	else
	{
		(void)git.stage(paths);
	}
	git.mark_dirty(now);
}

fn bool Panel.can_commit(&self, State* git)
{
	if (git.busy_or_refreshing() || !git.has_status || self.message_len == 0) return false;
	for (sz i = 0; i < git.status.entries.len(); i++)
	{
		GitEntry* entry = &git.status.entries[i];
		if (!entry.conflicted && entry_has_staged(entry)) return true;
	}
	return false;
}

fn void Panel.commit(&self, State* git)
{
	if (!self.can_commit(git)) return;
	(void)git.commit(self.message_view(), false);
}

fn void Panel.amend(&self, State* git)
{
	if (git.busy || !git.has_status || git.status.initial || self.message_len == 0) return;
	(void)git.commit(self.message_view(), true);
}

fn void Panel.begin_discard(&self, State* git, double now)
{
	PanelRow* row = self.selected_row();
	if (!row) return;
	if (row.kind != PanelRowKind.FILE_UNSTAGED && row.kind != PanelRowKind.FILE_UNTRACKED) return;
	self.confirm_row = self.selected;
	if (!g_git_settings.confirm_discard)
	{
		self.confirm_open = true;
		self.confirm_discard(git, now);
		return;
	}
	self.confirm_open = true;
}

fn void Panel.confirm_discard(&self, State* git, double now)
{
	if (!self.confirm_open) return;
	if (self.confirm_row < 0 || self.confirm_row >= (int)self.rows.len())
	{
		self.confirm_open = false;
		return;
	}
	PanelRow row    = self.rows[self.confirm_row];
	GitEntry* entry = self.entry_for(git, row.entry);
	if (entry)
	{
		if (row.kind == PanelRowKind.FILE_UNTRACKED)
		{
			(void)git.discard_untracked(entry.abs_path, now);
		}
		else if (row.kind == PanelRowKind.FILE_UNSTAGED)
		{
			String[] paths = alloc::new_array(tmem, String, 1);
			paths[0] = entry.path;
			(void)git.discard(paths);
		}
	}
	self.confirm_open = false;
	self.confirm_row = -1;
	self.error_open = false;
	git.mark_dirty(now);
}

fn void Panel.sync_actions(&self, State* git)
{
	if (git.error.kind == GitErrorKind.NONE) self.error_open = false;
	if (git.action_revision == self.action_seen) return;
	self.action_seen = git.action_revision;
	if (git.action.success && git.action.kind == GitRequestKind.COMMIT) self.clear_message();
	if (git.action.success
		&& (git.action.kind == GitRequestKind.BRANCH_SWITCH || git.action.kind == GitRequestKind.BRANCH_CREATE))
	{
		self.branch_open = false;
		self.branch_create = false;
		self.branch_input_clear();
	}
	if (self.sync_pending)
	{
		if (git.action.kind == GitRequestKind.PULL)
		{
			self.sync_pending = false;
			if (git.action.success) (void)git.push(false);
		}
		else if (!git.action.success)
		{
			self.sync_pending = false;
		}
	}
}

fn Rect Panel.branch_modal_rect(&self, Canvas* canvas)
{
	Rect panel   = self.rect(canvas);
	float width  = panel.width - ui::pxf(24.0f);
	float height = panel.height - ui::pxf(80.0f);
	if (height > ui::pxf(380.0f)) height = ui::pxf(380.0f);
	if (height < ui::pxf(180.0f)) height = ui::pxf(180.0f);
	return {
		.x = panel.x + (panel.width - width) / 2.0f,
		.y = panel.y + (panel.height - height) / 2.0f,
		.width = width,
		.height = height,
	};
}

fn int Panel.branch_visible_rows(&self, Canvas* canvas)
{
	Rect modal   = self.branch_modal_rect(canvas);
	float list_h = modal.height - ui::pxf(92.0f);
	int rows     = (int)(list_h / ui::pxf(ROW_H));
	return rows < 1 ? 1 : rows;
}

fn void Panel.ensure_branch_visible(&self, Canvas* canvas)
{
	if (self.branch_selected < 0) return;
	int visible = self.branch_visible_rows(canvas);
	if (self.branch_selected < self.branch_scroll) self.branch_scroll = self.branch_selected;
	if (self.branch_selected >= self.branch_scroll + visible)
	{
		self.branch_scroll = self.branch_selected - visible + 1;
	}
}

fn void Panel.open_branch_picker(&self, State* git)
{
	self.branch_open = true;
	self.branch_create = false;
	self.branch_input_len = 0;
	self.branch_input[0] = 0;
	self.branch_scroll = 0;
	self.branch_selected = -1;
	if (self.branch_warning.len > 0)
	{
		self.branch_warning.free(self.allocator);
		self.branch_warning = "";
	}
	for (sz i = 0; i < git.branches.len(); i++)
	{
		if (git.branches[i].current)
		{
			self.branch_selected = (int)i;
			break;
		}
	}
	if (self.branch_selected < 0 && git.branches.len() > 0) self.branch_selected = 0;
	git.request_branches();
}

fn void Panel.branch_input_clear(&self)
{
	self.branch_input_len = 0;
	self.branch_input[0] = 0;
}

fn void Panel.branch_input_append(&self, char c)
{
	if (self.branch_input_len >= BRANCH_NAME_MAX - 1) return;
	self.branch_input[self.branch_input_len] = c;
	self.branch_input_len++;
	self.branch_input[self.branch_input_len] = 0;
}

fn void Panel.branch_input_backspace(&self)
{
	if (self.branch_input_len == 0) return;
	self.branch_input_len--;
	while (self.branch_input_len > 0 && (((int)self.branch_input[self.branch_input_len] & 0xC0) == 0x80))
	{
		self.branch_input_len--;
	}
	self.branch_input[self.branch_input_len] = 0;
}

fn String Panel.branch_input_view(&self)
{
	return (String)self.branch_input[0:self.branch_input_len];
}

fn void Panel.switch_selected_branch(&self, State* git)
{
	if (self.branch_selected < 0 || self.branch_selected >= (int)git.branches.len()) return;
	GitBranch* branch = &git.branches[self.branch_selected];
	if (branch.current) return;
	if (self.editors_dirty)
	{
		if (self.branch_warning.len > 0) self.branch_warning.free(self.allocator);
		self.branch_warning = "Save or discard unsaved editors first.".copy(self.allocator);
		return;
	}
	(void)git.switch_branch(branch.name);
}

fn void Panel.create_branch_from_input(&self, State* git)
{
	if (self.branch_input_len == 0) return;
	(void)git.create_branch(self.branch_input_view());
}

fn void Panel.handle_branch_key(&self, State* git, Canvas* canvas, double now)
{
	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		if (self.branch_create)
		{
			self.branch_create = false;
			self.branch_input_clear();
		}
		else
		{
			self.branch_open = false;
		}
		return;
	}
	if (self.branch_create)
	{
		if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER) || rl::is_key_pressed(rl::RLKeyboardKey.KP_ENTER))
		{
			self.create_branch_from_input(git);
			return;
		}
		if (rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE)) self.branch_input_backspace();
		bool ctrl = ctrl_down();
		if (ctrl && rl::is_key_pressed(rl::RLKeyboardKey.V))
		{
			ZString clip = rl::get_clipboard_text();
			if (clip)
			{
				String text = clip.str_view();
				for (usz i = 0; i < text.len; i++)
				{
					char c = text[i];
					if (c > 32 && c != '\n' && c != '\r') self.branch_input_append(c);
				}
			}
		}
		if (!ctrl)
		{
			int codepoint = rl::get_char_pressed();
			while (codepoint != 0)
			{
				if (codepoint > 32 && codepoint < 0x80)
				{
					char c = (char)codepoint;
					if (c != '/' && c != '\\' && c != '~' && c != '^' && c != ':' && c != '?' && c != '*' && c != '[')
					{
						self.branch_input_append(c);
					}
				}
				codepoint = rl::get_char_pressed();
			}
		}
		return;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP)) self.branch_selected--;
	if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN)) self.branch_selected++;
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_UP))
	{
		self.branch_selected -= self.branch_visible_rows(canvas);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_DOWN))
	{
		self.branch_selected += self.branch_visible_rows(canvas);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.HOME)) self.branch_selected = 0;
	if (rl::is_key_pressed(rl::RLKeyboardKey.END)) self.branch_selected = (int)git.branches.len() - 1;
	if (self.branch_selected < 0) self.branch_selected = 0;
	if (self.branch_selected >= (int)git.branches.len())
	{
		self.branch_selected = (int)git.branches.len() - 1;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.N))
	{
		self.branch_create = true;
		self.branch_input_clear();
		while (rl::get_char_pressed() != 0)
		{
		}
		return;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.R)) git.request_branches();
	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER) || rl::is_key_pressed(rl::RLKeyboardKey.KP_ENTER))
	{
		self.switch_selected_branch(git);
	}
	self.ensure_branch_visible(canvas);
}

fn bool Panel.can_remote(&self, State* git)
{
	return !git.busy_or_refreshing() && git.is_repo && git.has_status;
}

fn bool Panel.can_push(&self, State* git)
{
	return self.can_remote(git) && git.status.branch.len > 0;
}

fn bool Panel.needs_publish(&self, State* git)
{
	return git.has_status && git.status.upstream.len == 0;
}

fn bool Panel.can_pull(&self, State* git)
{
	return self.can_push(git) && git.status.upstream.len > 0 && !self.editors_dirty;
}

fn void Panel.start_sync(&self, State* git)
{
	if (!self.can_pull(git)) return;
	if (git.pull())
	{
		self.sync_pending = true;
	}
}

fn void Panel.handle_commit_key(&self, State* git)
{
	bool ctrl = ctrl_down();
	if (ctrl && (rl::is_key_pressed(rl::RLKeyboardKey.ENTER) || rl::is_key_pressed(rl::RLKeyboardKey.KP_ENTER)))
	{
		self.commit(git);
		return;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		self.commit_focus = false;
		return;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.TAB))
	{
		self.commit_focus = false;
		return;
	}
	if (rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE)) self.backspace();
	if (rl::is_key_pressed_repeat(rl::RLKeyboardKey.DELETE)) self.delete_forward();
	if (rl::is_key_pressed(rl::RLKeyboardKey.LEFT)) self.message_cursor--;
	if (rl::is_key_pressed(rl::RLKeyboardKey.RIGHT)) self.message_cursor++;
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP)) self.move_vertical(-1);
	if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN)) self.move_vertical(1);
	if (rl::is_key_pressed(rl::RLKeyboardKey.HOME)) self.message_cursor = self.line_start(self.message_cursor);
	if (rl::is_key_pressed(rl::RLKeyboardKey.END)) self.message_cursor = self.line_end(self.message_cursor);
	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER) || rl::is_key_pressed(rl::RLKeyboardKey.KP_ENTER))
	{
		self.insert_char('\n');
	}
	if (ctrl && rl::is_key_pressed(rl::RLKeyboardKey.V))
	{
		ZString clip = rl::get_clipboard_text();
		if (clip) self.insert_text(clip.str_view());
	}
	if (self.message_cursor < 0) self.message_cursor = 0;
	if (self.message_cursor > self.message_len) self.message_cursor = self.message_len;
	if (!ctrl)
	{
		int codepoint = rl::get_char_pressed();
		while (codepoint != 0)
		{
			if (codepoint == '\n' || codepoint == '\r') break;
			char[4] encoded;
			int count = 0;
			if (codepoint < 0x80)
			{
				encoded[0] = (char)codepoint;
				count = 1;
			}
			else if (codepoint < 0x800)
			{
				encoded[0] = (char)(0xC0 | (codepoint >> 6));
				encoded[1] = (char)(0x80 | (codepoint & 0x3F));
				count = 2;
			}
			else if (codepoint < 0x10000)
			{
				encoded[0] = (char)(0xE0 | (codepoint >> 12));
				encoded[1] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
				encoded[2] = (char)(0x80 | (codepoint & 0x3F));
				count = 3;
			}
			else
			{
				encoded[0] = (char)(0xF0 | (codepoint >> 18));
				encoded[1] = (char)(0x80 | ((codepoint >> 12) & 0x3F));
				encoded[2] = (char)(0x80 | ((codepoint >> 6) & 0x3F));
				encoded[3] = (char)(0x80 | (codepoint & 0x3F));
				count = 4;
			}
			for (int i = 0; i < count; i++) self.insert_char(encoded[i]);
			codepoint = rl::get_char_pressed();
		}
	}
}

fn void Panel.handle_list_key(&self, State* git, Canvas* canvas, double now)
{
	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE))
	{
		self.leave_requested = true;
		return;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.TAB))
	{
		self.commit_focus = true;
		return;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.UP)) self.move_selection(-1);
	if (rl::is_key_pressed(rl::RLKeyboardKey.DOWN)) self.move_selection(1);
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_UP)) self.page_selection(-1, self.visible_rows(canvas));
	if (rl::is_key_pressed(rl::RLKeyboardKey.PAGE_DOWN)) self.page_selection(1, self.visible_rows(canvas));
	if (rl::is_key_pressed(rl::RLKeyboardKey.HOME)) self.select_first();
	if (rl::is_key_pressed(rl::RLKeyboardKey.END))
	{
		for (int i = (int)self.rows.len() - 1; i >= 0; i--)
		{
			if (row_is_file(self.rows[i].kind))
			{
				self.selected = i;
				break;
			}
		}
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.ENTER) || rl::is_key_pressed(rl::RLKeyboardKey.KP_ENTER))
	{
		self.request_open(git);
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.SPACE)) self.stage_selected(git, now);
	if (rl::is_key_pressed(rl::RLKeyboardKey.D)) self.request_diff(git);
	if (rl::is_key_pressed(rl::RLKeyboardKey.C)) self.request_resolve(git);
	if (rl::is_key_pressed(rl::RLKeyboardKey.H))
	{
		PanelRow* row   = self.selected_row();
		GitEntry* entry = row ? self.entry_for(git, row.entry) : null;
		if (self.pending_history_path.len > 0) self.pending_history_path.free(self.allocator);
		self.pending_history_path = entry ? entry.path.copy(self.allocator) : "";
		self.history_pending = true;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.R)) git.refresh_now(now);
	if (rl::is_key_pressed(rl::RLKeyboardKey.B)) self.open_branch_picker(git);
	if (rl::is_key_pressed(rl::RLKeyboardKey.DELETE)) self.begin_discard(git, now);
}

fn void Panel.handle_confirm_key(&self, State* git, double now)
{
	if (rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE) || rl::is_key_pressed(rl::RLKeyboardKey.N))
	{
		self.confirm_open = false;
		self.confirm_row = -1;
		return;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.Y))
	{
		self.confirm_discard(git, now);
	}
}

fn bool Panel.update(&self, State* git, Canvas* canvas, double now, bool focused, bool editors_dirty)
{
	if (!self.visible) return false;
	self.focused = focused;
	self.editors_dirty = editors_dirty;
	self.focus_requested = false;
	self.leave_requested = false;
	self.sync_actions(git);
	if (self.rows_revision != git.status_revision)
	{
		self.rebuild(git);
		self.ensure_visible(canvas);
	}

	Rect panel      = self.rect(canvas);
	RLVector2 mouse = rl::get_mouse_position();
	bool inside     = rect_contains(panel, mouse);
	bool consumed   = inside;

	if (self.branch_open)
	{
		if (focused) self.handle_branch_key(git, canvas, now);
		if (self.branch_selected >= (int)git.branches.len())
		{
			self.branch_selected = (int)git.branches.len() - 1;
		}
		if (self.branch_selected < 0 && git.branches.len() > 0) self.branch_selected = 0;
		int max_scroll = (int)git.branches.len() - self.branch_visible_rows(canvas);
		if (max_scroll < 0) max_scroll = 0;
		if (self.branch_scroll > max_scroll) self.branch_scroll = max_scroll;
		if (self.branch_scroll < 0) self.branch_scroll = 0;
		Rect modal = self.branch_modal_rect(canvas);
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
		{
			if (!rect_contains(modal, mouse))
			{
				self.branch_open = false;
				self.branch_create = false;
				return true;
			}
			if (self.branch_create)
			{
				Rect create = {
					.x = modal.x + ui::pxf(14.0f),
					.y = modal.y + modal.height - ui::pxf(34.0f),
					.width = (modal.width - ui::pxf(36.0f)) / 2.0f,
					.height = ui::pxf(24.0f),
				};
				Rect cancel = {
					.x = create.x + create.width + ui::pxf(8.0f),
					.y = create.y,
					.width = create.width,
					.height = create.height,
				};
				if (rect_contains(create, mouse)) self.create_branch_from_input(git);
				if (rect_contains(cancel, mouse))
				{
					self.branch_create = false;
					self.branch_input_clear();
				}
				return true;
			}
			float list_y = modal.y + ui::pxf(38.0f);
			float list_h = modal.height - ui::pxf(92.0f);
			Rect list    = { .x = modal.x, .y = list_y, .width = modal.width, .height = list_h };
			if (rect_contains(list, mouse))
			{
				int row = self.branch_scroll + (int)((mouse[1] - list.y) / ui::pxf(ROW_H));
				if (row >= 0 && row < (int)git.branches.len()) self.branch_selected = row;
				return true;
			}
			Rect switch_button = {
				.x = modal.x + ui::pxf(14.0f),
				.y = modal.y + modal.height - ui::pxf(34.0f),
				.width = (modal.width - ui::pxf(36.0f)) / 2.0f,
				.height = ui::pxf(24.0f),
			};
			Rect new_button = {
				.x = switch_button.x + switch_button.width + ui::pxf(8.0f),
				.y = switch_button.y,
				.width = switch_button.width,
				.height = switch_button.height,
			};
			if (rect_contains(switch_button, mouse)) self.switch_selected_branch(git);
			if (rect_contains(new_button, mouse))
			{
				self.branch_create = true;
				self.branch_input_clear();
			}
			return true;
		}
		return true;
	}

	if (self.error_open)
	{
		if (focused && rl::is_key_pressed(rl::RLKeyboardKey.ESCAPE)) self.error_open = false;
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
		{
			Rect modal = {
				.x = panel.x + panel.width / 2.0f - ui::pxf(170.0f),
				.y = panel.y + panel.height / 2.0f - ui::pxf(90.0f),
				.width = ui::pxf(340.0f),
				.height = ui::pxf(180.0f),
			};
			if (!rect_contains(modal, mouse)) self.error_open = false;
		}
		return true;
	}

	if (self.confirm_open)
	{
		if (focused) self.handle_confirm_key(git, now);
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
		{
			Rect modal = {
				.x = panel.x + panel.width / 2.0f - ui::pxf(150.0f),
				.y = panel.y + panel.height / 2.0f - ui::pxf(50.0f),
				.width = ui::pxf(300.0f),
				.height = ui::pxf(100.0f),
			};
			Rect discard = {
				.x = modal.x + ui::pxf(16.0f),
				.y = modal.y + modal.height - ui::pxf(36.0f),
				.width = ui::pxf(110.0f),
				.height = ui::pxf(24.0f),
			};
			Rect cancel = {
				.x = modal.x + modal.width - ui::pxf(126.0f),
				.y = discard.y,
				.width = ui::pxf(110.0f),
				.height = ui::pxf(24.0f),
			};
			if (rect_contains(discard, mouse))
			{
				self.confirm_discard(git, now);
				return true;
			}
			if (rect_contains(cancel, mouse))
			{
				self.confirm_open = false;
				self.confirm_row = -1;
				return true;
			}
		}
		return consumed;
	}

	if (focused)
	{
		if (self.commit_focus)
		{
			self.handle_commit_key(git);
			self.ensure_visible(canvas);
			return true;
		}
		self.handle_list_key(git, canvas, now);
		self.ensure_visible(canvas);
		if (self.leave_requested) return true;
	}

	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		self.focus_requested = true;
		Rect header = self.header_rect(canvas);
		Rect refresh = {
			.x = header.x + header.width - ui::pxf(64.0f),
			.y = header.y + ui::pxf(5.0f),
			.width = ui::pxf(56.0f),
			.height = ui::pxf(20.0f),
		};
		if (rect_contains(refresh, mouse))
		{
			git.refresh_now(now);
			return true;
		}
		Rect branch = self.branch_rect(canvas);
		if (rect_contains(branch, mouse))
		{
			self.open_branch_picker(git);
			return true;
		}
		Rect remote = self.remote_rect(canvas);
		if (rect_contains(remote, mouse))
		{
			float gap         = ui::pxf(4.0f);
			float button_w    = (remote.width - ui::pxf(PAD) * 2.0f - gap * 3.0f) / 4.0f;
			float x           = remote.x + ui::pxf(PAD);
			Rect fetch_button = { .x = x, .y = remote.y + ui::pxf(2.0f), .width = button_w, .height = ui::pxf(21.0f) };
			x += button_w + gap;
			Rect pull_button = { .x = x, .y = fetch_button.y, .width = button_w, .height = fetch_button.height };
			x += button_w + gap;
			Rect push_button = { .x = x, .y = fetch_button.y, .width = button_w, .height = fetch_button.height };
			x += button_w + gap;
			Rect sync_button = { .x = x, .y = fetch_button.y, .width = button_w, .height = fetch_button.height };
			if (self.can_remote(git) && rect_contains(fetch_button, mouse)) (void)git.fetch();
			if (self.can_pull(git) && rect_contains(pull_button, mouse)) (void)git.pull();
			if (self.can_push(git) && rect_contains(push_button, mouse))
			{
				(void)git.push(self.needs_publish(git));
			}
			if (self.can_pull(git) && rect_contains(sync_button, mouse)) self.start_sync(git);
			return true;
		}
		Rect commit = self.commit_rect(canvas);
		Rect message = {
			.x = commit.x + ui::pxf(PAD),
			.y = commit.y + ui::pxf(6.0f),
			.width = commit.width - ui::pxf(PAD * 2.0f),
			.height = ui::pxf(46.0f),
		};
		if (rect_contains(message, mouse))
		{
			self.commit_focus = true;
			return true;
		}
		float button_y = commit.y + ui::pxf(58.0f);
		float button_w = (commit.width - ui::pxf(PAD * 2.0f) - ui::pxf(6.0f)) / 2.0f;
		Rect commit_button = {
			.x = commit.x + ui::pxf(PAD),
			.y = button_y,
			.width = button_w,
			.height = ui::pxf(22.0f),
		};
		Rect amend_button = {
			.x = commit_button.x + button_w + ui::pxf(6.0f),
			.y = button_y,
			.width = button_w,
			.height = ui::pxf(22.0f),
		};
		float row2_y = button_y + ui::pxf(28.0f);
		float third  = (commit.width - ui::pxf(PAD * 2.0f) - ui::pxf(12.0f)) / 3.0f;
		Rect stage_all = {
			.x = commit.x + ui::pxf(PAD),
			.y = row2_y,
			.width = third,
			.height = ui::pxf(22.0f),
		};
		Rect unstage_all = {
			.x = stage_all.x + third + ui::pxf(6.0f),
			.y = row2_y,
			.width = third,
			.height = ui::pxf(22.0f),
		};
		Rect refresh_button = {
			.x = unstage_all.x + third + ui::pxf(6.0f),
			.y = row2_y,
			.width = third,
			.height = ui::pxf(22.0f),
		};
		if (rect_contains(commit_button, mouse))
		{
			self.commit(git);
			return true;
		}
		if (rect_contains(amend_button, mouse))
		{
			self.amend(git);
			return true;
		}
		if (rect_contains(stage_all, mouse))
		{
			self.stage_all(git, now, false);
			return true;
		}
		if (rect_contains(unstage_all, mouse))
		{
			self.stage_all(git, now, true);
			return true;
		}
		if (rect_contains(refresh_button, mouse))
		{
			git.refresh_now(now);
			return true;
		}

		Rect list = self.list_rect(canvas);
		if (git.error.kind != GitErrorKind.NONE && rect_contains(
			{ .x = list.x, .y = list.y + list.height - ui::pxf(20.0f), .width = list.width, .height = ui::pxf(20.0f) },
			mouse
		))
		{
			self.error_open = true;
			return true;
		}
		if (rect_contains(list, mouse))
		{
			int row = self.scroll + (int)((mouse[1] - list.y) / ui::pxf(ROW_H));
			if (row >= 0 && row < (int)self.rows.len() && row_is_file(self.rows[row].kind))
			{
				self.selected = row;
				self.commit_focus = false;
			}
			return true;
		}
		return true;
	}

	if (inside && rl::get_mouse_wheel_move() != 0.0f)
	{
		Rect list = self.list_rect(canvas);
		if (rect_contains(list, mouse))
		{
			self.scroll -= (int)rl::get_mouse_wheel_move() * SCROLL_LINES;
			int max = (int)self.rows.len() - self.visible_rows(canvas);
			if (max < 0) max = 0;
			if (self.scroll < 0) self.scroll = 0;
			if (self.scroll > max) self.scroll = max;
			return true;
		}
	}
	return consumed;
}

fn void draw_section(Rect row, String label, int count, float text_size)
{
	rl::draw_text_ex(
		ui::font(),
		label.zstr_tcopy(),
		{ row.x + ui::pxf(PAD), row.y + (row.height - text_size) * 0.5f },
		text_size,
		0.0f,
		theme::current()
		.panel_header);
	@pool()
	{
		String count_text = string::format(tmem, "%d", (long)count);
		float width       = rl::measure_text_ex(ui::font(), count_text.zstr_tcopy(), text_size, 0.0f)[0];
		rl::draw_text_ex(
			ui::font(),
			count_text.zstr_tcopy(),
			{ row.x + row.width - ui::pxf(PAD) - width, row.y + (row.height - text_size) * 0.5f },
			text_size,
			0.0f,
			theme::current()
			.panel_dim);
	};
}

fn void draw_button(Rect rect, String label, bool enabled, float text_size)
{
	RLColor fill = enabled ? theme::current().panel_field : theme::current().panel_bg_alt;
	RLColor text = enabled ? theme::current().panel_text : theme::current().panel_disabled;
	ui::rounded_rect(rect, ui::row_radius(), fill);
	float width = rl::measure_text_ex(ui::font(), label.zstr_tcopy(), text_size, 0.0f)[0];
	rl::draw_text_ex(
		ui::font(),
		label.zstr_tcopy(),
		{ rect.x + (rect.width - width) * 0.5f, rect.y + (rect.height - text_size) * 0.5f },
		text_size,
		0.0f,
		text
	);
}

fn void Panel.draw_branch(&self, State* git, Rect header, float text_size)
{
	Rect row = {
		.x = header.x,
		.y = header.y + header.height,
		.width = header.width,
		.height = ui::pxf(BRANCH_H),
	};
	@pool()
	{
		String label;
		if (git.error.kind != GitErrorKind.NONE && !git.is_repo)
		{
			label = git.error.message;
		}
		else if (!git.is_repo)
		{
			label = "Not a Git repository";
		}
		else if (git.has_status && git.status.detached)
		{
			label = "HEAD detached";
		}
		else if (git.has_status && git.status.branch.len > 0)
		{
			if (git.status.upstream.len > 0)
			{
				label = string::format(
					tmem,
					"%s  [%s]  +%d -%d",
					git.status.branch,
					git.status.upstream,
					(long)git.status.ahead,
					(long)git.status.behind
				);
			}
			else
			{
				label = string::format(
					tmem,
					"%s  +%d -%d",
					git.status.branch,
					(long)git.status.ahead,
					(long)git.status.behind
				);
			}
		}
		else
		{
			label = "Loading status...";
		}
		rl::draw_text_ex(
			ui::font(),
			label.zstr_tcopy(),
			{ row.x + ui::pxf(PAD), row.y + (row.height - text_size) * 0.5f },
			text_size,
			0.0f,
			theme::current()
			.panel_dim);
	};
}

fn void Panel.draw_commit(&self, State* git, Canvas* canvas, float text_size)
{
	Rect commit = self.commit_rect(canvas);
	Rect message = {
		.x = commit.x + ui::pxf(PAD),
		.y = commit.y + ui::pxf(6.0f),
		.width = commit.width - ui::pxf(PAD * 2.0f),
		.height = ui::pxf(46.0f),
	};
	ui::rounded_rect(message, ui::row_radius(), theme::current().panel_field);
	RLColor border = self.commit_focus ? theme::current().card_focus : theme::current().panel_border;
	ui::rounded_rect_lines(message, ui::row_radius(), 1.0f, border);

	if (self.message_len == 0)
	{
		rl::draw_text_ex(
			ui::font(),
			"Commit message",
			{ message.x + ui::pxf(6.0f), message.y + ui::pxf(6.0f) },
			text_size,
			0.0f,
			theme::current()
			.panel_disabled);
	}
	else
	{
		int cursor_line = 0;
		for (int i = 0; i < self.message_cursor; i++)
		{
			if (self.message[i] == '\n') cursor_line++;
		}
		if (cursor_line < self.commit_scroll) self.commit_scroll = cursor_line;
		if (cursor_line >= self.commit_scroll + 2) self.commit_scroll = cursor_line - 1;
		int line       = 0;
		int line_start = 0;
		for (int i = 0; i <= self.message_len; i++)
		{
			bool end = i == self.message_len || self.message[i] == '\n';
			if (!end) continue;
			if (line >= self.commit_scroll && line < self.commit_scroll + 3)
			{
				float base_y = message.y + ui::pxf(5.0f);
				float line_y = (float)(line - self.commit_scroll) * (float)ui::tpx(15);
				int y        = (int)(base_y + line_y);
				String text  = (String)self.message[line_start:i - line_start];
				@pool()
				{
					rl::draw_text_ex(
						ui::font(),
						text.zstr_tcopy(),
						{ message.x + ui::pxf(6.0f), (float)y },
						text_size,
						0.0f,
						theme::current()
						.panel_text);
				};
				if (self.message_cursor >= line_start && self.message_cursor <= i)
				{
					int column = self.message_cursor - line_start;
					@pool()
					{
						String prefix = text[0:column];
						float width   = rl::measure_text_ex(ui::font(), prefix.zstr_tcopy(), text_size, 0.0f)[0];
						rl::draw_rectangle_rec(
							{
								.x = message.x + ui::pxf(6.0f) + width,
								.y = (float)y,
								.width = 1.0f,
								.height = text_size,
							},
							theme::current()
							.panel_caret);
					};
				}
			}
			line++;
			line_start = i + 1;
		}
	}

	float button_y = commit.y + ui::pxf(58.0f);
	float button_w = (commit.width - ui::pxf(PAD * 2.0f) - ui::pxf(6.0f)) / 2.0f;
	Rect commit_button = {
		.x = commit.x + ui::pxf(PAD),
		.y = button_y,
		.width = button_w,
		.height = ui::pxf(22.0f),
	};
	Rect amend_button = {
		.x = commit_button.x + button_w + ui::pxf(6.0f),
		.y = button_y,
		.width = button_w,
		.height = ui::pxf(22.0f),
	};
	draw_button(commit_button, "Commit", self.can_commit(git), text_size);
	draw_button(amend_button, "Amend", self.can_commit(git) && !git.status.initial, text_size);

	float row2_y = button_y + ui::pxf(28.0f);
	float third  = (commit.width - ui::pxf(PAD * 2.0f) - ui::pxf(12.0f)) / 3.0f;
	Rect stage_all = {
		.x = commit.x + ui::pxf(PAD),
		.y = row2_y,
		.width = third,
		.height = ui::pxf(22.0f),
	};
	Rect unstage_all = {
		.x = stage_all.x + third + ui::pxf(6.0f),
		.y = row2_y,
		.width = third,
		.height = ui::pxf(22.0f),
	};
	Rect refresh = {
		.x = unstage_all.x + third + ui::pxf(6.0f),
		.y = row2_y,
		.width = third,
		.height = ui::pxf(22.0f),
	};
	draw_button(stage_all, "Stage All", count_paths(git, false) > 0, text_size);
	draw_button(unstage_all, "Unstage", count_paths(git, true) > 0, text_size);
	draw_button(refresh, "Refresh", true, text_size);
}

fn void Panel.draw_branch_picker(&self, State* git, Canvas* canvas, float text_size)
{
	if (!self.branch_open) return;
	Rect panel = self.rect(canvas);
	Rect modal = self.branch_modal_rect(canvas);
	rl::draw_rectangle_rec(panel, { 0, 0, 0, 120 });
	ui::rounded_rect(modal, ui::corner_radius(), theme::current().panel_bg_alt);
	ui::rounded_rect_lines(modal, ui::corner_radius(), 1.0f, theme::current().panel_border);
	rl::draw_text_ex(
		ui::font(),
		self.branch_create ? "New branch" : "Switch branch",
		{ modal.x + ui::pxf(14.0f), modal.y + ui::pxf(10.0f) },
		(float)ui::tpx(15),
		0.0f,
		theme::current()
		.panel_text);
	if (self.branch_warning.len > 0)
	{
		rl::draw_text_ex(
			ui::font(),
			self.branch_warning.zstr_tcopy(),
			{ modal.x + ui::pxf(14.0f), modal.y + ui::pxf(30.0f) },
			(float)ui::tpx(11),
			0.0f,
			theme::current()
			.git_conflict);
	}

	if (self.branch_create)
	{
		@pool()
		{
			String current = git.has_status && git.status.branch.len > 0 ? git.status.branch : "HEAD";
			String hint    = string::format(tmem, "Create from %s", current);
			rl::draw_text_ex(
				ui::font(),
				hint.zstr_tcopy(),
				{ modal.x + ui::pxf(14.0f), modal.y + ui::pxf(34.0f) },
				(float)ui::tpx(12),
				0.0f,
				theme::current()
				.panel_dim);
		};
		Rect field = {
			.x = modal.x + ui::pxf(14.0f),
			.y = modal.y + ui::pxf(54.0f),
			.width = modal.width - ui::pxf(28.0f),
			.height = ui::pxf(28.0f),
		};
		ui::rounded_rect(field, ui::row_radius(), theme::current().panel_field);
		ui::rounded_rect_lines(field, ui::row_radius(), 1.0f, theme::current().card_focus);
		String input = self.branch_input_view();
		if (input.len == 0)
		{
			rl::draw_text_ex(
				ui::font(),
				"branch-name",
				{ field.x + ui::pxf(6.0f), field.y + ui::pxf(5.0f) },
				text_size,
				0.0f,
				theme::current()
				.panel_disabled);
		}
		else
		{
			@pool()
			{
				rl::draw_text_ex(
					ui::font(),
					input.zstr_tcopy(),
					{ field.x + ui::pxf(6.0f), field.y + ui::pxf(5.0f) },
					text_size,
					0.0f,
					theme::current()
					.panel_text);
				float width = rl::measure_text_ex(ui::font(), input.zstr_tcopy(), text_size, 0.0f)[0];
				rl::draw_rectangle_rec(
					{
						.x = field.x + ui::pxf(7.0f) + width,
						.y = field.y + ui::pxf(5.0f),
						.width = 1.0f,
						.height = text_size
					},
					theme::current()
					.panel_caret);
			};
		}
		Rect create = {
			.x = modal.x + ui::pxf(14.0f),
			.y = modal.y + modal.height - ui::pxf(34.0f),
			.width = (modal.width - ui::pxf(36.0f)) / 2.0f,
			.height = ui::pxf(24.0f),
		};
		Rect cancel = {
			.x = create.x + create.width + ui::pxf(8.0f),
			.y = create.y,
			.width = create.width,
			.height = create.height,
		};
		draw_button(create, "Create", self.branch_input_len > 0 && !git.busy_or_refreshing(), (float)ui::tpx(12));
		draw_button(cancel, "Cancel", true, (float)ui::tpx(12));
		return;
	}

	float list_y = modal.y + ui::pxf(38.0f);
	float list_h = modal.height - ui::pxf(92.0f);
	Rect list    = { .x = modal.x, .y = list_y, .width = modal.width, .height = list_h };
	rl::begin_scissor_mode((int)list.x, (int)list.y, (int)list.width, (int)list.height);
	if (git.branches.len() == 0)
	{
		rl::draw_text_ex(
			ui::font(),
			git.branches_loaded ? "No local branches" : "Loading branches...",
			{ list.x + ui::pxf(14.0f), list.y + ui::pxf(6.0f) },
			(float)ui::tpx(13),
			0.0f,
			theme::current()
			.panel_dim);
	}
	int last = math::min(self.branch_scroll + self.branch_visible_rows(canvas), (int)git.branches.len());
	for (int i = self.branch_scroll; i < last; i++)
	{
		GitBranch* branch = &git.branches[i];
		Rect row = {
			.x = list.x,
			.y = list.y + (float)(i - self.branch_scroll) * ui::pxf(ROW_H),
			.width = list.width,
			.height = ui::pxf(ROW_H),
		};
		if (i == self.branch_selected)
		{
			ui::row(
				{ .x = row.x + ui::pxf(4.0f), .y = row.y, .width = row.width - ui::pxf(8.0f), .height = row.height },
				theme::current()
				.panel_selected);
		}
		rl::draw_text_ex(
			ui::font(),
			branch.current ? "*" : " ",
			{ row.x + ui::pxf(10.0f), row.y + ui::pxf(2.0f) },
			(float)ui::tpx(13),
			0.0f,
			theme::current()
			.panel_dim);
		@pool()
		{
			rl::draw_text_ex(
				ui::font(),
				branch.name.zstr_tcopy(),
				{ row.x + ui::pxf(24.0f), row.y + ui::pxf(2.0f) },
				(float)ui::tpx(13),
				0.0f,
				theme::current()
				.panel_text);
		};
		if (branch.upstream.len > 0)
		{
			@pool()
			{
				float width = rl::measure_text_ex(
					ui::font(),
					branch.upstream.zstr_tcopy(),
					(float)ui::tpx(11),
					0.0f
				)[0];
				rl::draw_text_ex(
					ui::font(),
					branch.upstream.zstr_tcopy(),
					{ row.x + row.width - width - ui::pxf(10.0f), row.y + ui::pxf(4.0f) },
					(float)ui::tpx(11),
					0.0f,
					theme::current()
					.panel_dim);
			};
		}
	}
	rl::end_scissor_mode();

	Rect switch_button = {
		.x = modal.x + ui::pxf(14.0f),
		.y = modal.y + modal.height - ui::pxf(34.0f),
		.width = (modal.width - ui::pxf(36.0f)) / 2.0f,
		.height = ui::pxf(24.0f),
	};
	Rect new_button = {
		.x = switch_button.x + switch_button.width + ui::pxf(8.0f),
		.y = switch_button.y,
		.width = switch_button.width,
		.height = switch_button.height,
	};
	bool can_switch = self.branch_selected >= 0 && self.branch_selected < (int)git.branches.len()
		&& !git.branches[self.branch_selected].current
		&& !git.busy;
	draw_button(switch_button, "Switch", can_switch, (float)ui::tpx(12));
	draw_button(new_button, "New", !git.busy_or_refreshing(), (float)ui::tpx(12));
}

fn void Panel.draw(&self, State* git, Canvas* canvas, float text_size)
{
	if (!self.visible) return;
	Rect panel     = self.rect(canvas);
	Rect header    = self.header_rect(canvas);
	Rect list      = self.list_rect(canvas);
	RLColor border = self.focused ? theme::current().card_focus : theme::current().panel_border;
	rl::draw_rectangle_rec(panel, theme::current().panel_bg);
	rl::draw_rectangle_rec(
		{ .x = panel.x + panel.width - 1.0f, .y = panel.y, .width = 1.0f, .height = panel.height },
		border
	);
	rl::draw_rectangle_rec(
		{ .x = panel.x, .y = panel.y, .width = panel.width, .height = header.height },
		theme::current()
		.panel_bg_alt);
	rl::draw_text_ex(
		ui::font(),
		"SOURCE CONTROL",
		{ header.x + ui::pxf(PAD), header.y + (header.height - (float)ui::tpx(14)) * 0.5f },
		(float)ui::tpx(14),
		0.0f,
		theme::current()
		.panel_header);



	{
		Rect refresh = {
			.x = header.x + header.width - ui::pxf(64.0f),
			.y = header.y + ui::pxf(5.0f),
			.width = ui::pxf(56.0f),
			.height = ui::pxf(20.0f),
		};
		draw_button(refresh, "Refresh", true, (float)ui::tpx(12));
	}

	self.draw_branch(git, header, (float)ui::tpx(13));

	Rect remote = self.remote_rect(canvas);
	if (git.is_repo)
	{
		float gap         = ui::pxf(4.0f);
		float button_w    = (remote.width - ui::pxf(PAD) * 2.0f - gap * 3.0f) / 4.0f;
		float x           = remote.x + ui::pxf(PAD);
		float button_y    = remote.y + ui::pxf(2.0f);
		Rect fetch_button = { .x = x, .y = button_y, .width = button_w, .height = ui::pxf(21.0f) };
		x += button_w + gap;
		Rect pull_button = { .x = x, .y = button_y, .width = button_w, .height = fetch_button.height };
		x += button_w + gap;
		Rect push_button = { .x = x, .y = button_y, .width = button_w, .height = fetch_button.height };
		x += button_w + gap;
		Rect sync_button = { .x = x, .y = button_y, .width = button_w, .height = fetch_button.height };
		bool upstream    = self.needs_publish(git);
		draw_button(fetch_button, "Fetch", self.can_remote(git), (float)ui::tpx(11));
		draw_button(pull_button, "Pull", self.can_pull(git), (float)ui::tpx(11));
		draw_button(push_button, upstream ? "Publish" : "Push", self.can_push(git), (float)ui::tpx(11));
		draw_button(sync_button, self.sync_pending ? "Syncing" : "Sync", self.can_pull(git), (float)ui::tpx(11));
	}

	rl::begin_scissor_mode((int)list.x, (int)list.y, (int)list.width, (int)list.height);
	if (!git.is_repo)
	{
		String message = git.error.kind == GitErrorKind.NONE ? "Open a Git repository to see changes."
			: git.error.message;
		rl::draw_text_ex(
			ui::font(),
			message.zstr_tcopy(),
			{ list.x + ui::pxf(PAD), list.y + ui::pxf(PAD) },
			(float)ui::tpx(13),
			0.0f,
			theme::current()
			.panel_dim);
	}
	else if (!git.has_status)
	{
		rl::draw_text_ex(
			ui::font(),
			"Loading status...",
			{ list.x + ui::pxf(PAD), list.y + ui::pxf(PAD) },
			(float)ui::tpx(13),
			0.0f,
			theme::current()
			.panel_dim);
	}
	else if (self.rows.len() == 0
		|| (self.staged == 0 && self.changes == 0 && self.untracked == 0 && self.conflicts == 0))
	{
		rl::draw_text_ex(
			ui::font(),
			"No changes",
			{ list.x + ui::pxf(PAD), list.y + ui::pxf(PAD) },
			(float)ui::tpx(13),
			0.0f,
			theme::current()
			.panel_dim);
	}
	else
	{
		int last = math::min(self.scroll + self.visible_rows(canvas), (int)self.rows.len());
		for (int i = self.scroll; i < last; i++)
		{
			Rect row = {
				.x = list.x,
				.y = list.y + (float)(i - self.scroll) * ui::pxf(ROW_H),
				.width = list.width,
				.height = ui::pxf(ROW_H),
			};
			PanelRow current = self.rows[i];
			if (!row_is_file(current.kind))
			{
				Rect section = { .x = row.x, .y = row.y, .width = row.width, .height = ui::pxf(SECTION_H) };
				switch (current.kind)
				{
					case PanelRowKind.CONFLICT_HEADER:
						draw_section(section, "Merge Changes", self.conflicts, (float)ui::tpx(12));
					case PanelRowKind.STAGED_HEADER:
						draw_section(section, "Staged Changes", self.staged, (float)ui::tpx(12));
					case PanelRowKind.CHANGES_HEADER:
						draw_section(section, "Changes", self.changes, (float)ui::tpx(12));
					case PanelRowKind.UNTRACKED_HEADER:
						draw_section(section, "Untracked", self.untracked, (float)ui::tpx(12));
					case PanelRowKind.FILE_CONFLICT:
					case PanelRowKind.FILE_STAGED:
					case PanelRowKind.FILE_UNSTAGED:
					case PanelRowKind.FILE_UNTRACKED:
						break;
				}
				continue;
			}
			if (i == self.selected)
			{
				ui::row(
					{
						.x = row.x + ui::pxf(4.0f),
						.y = row.y,
						.width = row.width - ui::pxf(8.0f),
						.height = row.height
					},
					theme::current()
					.panel_selected);
			}
			GitEntry* entry = self.entry_for(git, current.entry);
			if (!entry) continue;
			char badge     = entry_badge(entry);
			char[2] letter = { badge, 0 };
			rl::draw_text_ex(
				ui::font(),
				(ZString)&letter[0],
				{ row.x + ui::pxf(8.0f), row.y + ui::pxf(3.0f) },
				(float)ui::tpx(13),
				0.0f,
				entry_color(entry)
			);
			@pool()
			{
				rl::draw_text_ex(
					ui::font(),
					entry.path.zstr_tcopy(),
					{ row.x + ui::pxf(26.0f), row.y + ui::pxf(3.0f) },
					(float)ui::tpx(13),
					0.0f,
					theme::current()
					.panel_text);
			};
		}
	}
	rl::end_scissor_mode();

	if (git.error.kind != GitErrorKind.NONE && git.is_repo)
	{
		rl::draw_text_ex(
			ui::font(),
			git.error.message.zstr_tcopy(),
			{ panel.x + ui::pxf(PAD), list.y + list.height - ui::pxf(18.0f) },
			(float)ui::tpx(12),
			0.0f,
			theme::current()
			.git_conflict);
	}

	self.draw_commit(git, canvas, (float)ui::tpx(13));

	if (self.confirm_open)
	{
		rl::draw_rectangle_rec(panel, { 0, 0, 0, 120 });
		Rect modal = {
			.x = panel.x + panel.width / 2.0f - ui::pxf(150.0f),
			.y = panel.y + panel.height / 2.0f - ui::pxf(50.0f),
			.width = ui::pxf(300.0f),
			.height = ui::pxf(100.0f),
		};
		ui::rounded_rect(modal, ui::corner_radius(), theme::current().panel_bg_alt);
		ui::rounded_rect_lines(modal, ui::corner_radius(), 1.0f, theme::current().panel_border);
		rl::draw_text_ex(
			ui::font(),
			"Discard changes?",
			{ modal.x + ui::pxf(16.0f), modal.y + ui::pxf(16.0f) },
			(float)ui::tpx(15),
			0.0f,
			theme::current()
			.panel_text);
		rl::draw_text_ex(
			ui::font(),
			"This cannot be undone.",
			{ modal.x + ui::pxf(16.0f), modal.y + ui::pxf(38.0f) },
			(float)ui::tpx(12),
			0.0f,
			theme::current()
			.panel_dim);
		Rect discard = {
			.x = modal.x + ui::pxf(16.0f),
			.y = modal.y + modal.height - ui::pxf(36.0f),
			.width = ui::pxf(110.0f),
			.height = ui::pxf(24.0f),
		};
		Rect cancel = {
			.x = modal.x + modal.width - ui::pxf(126.0f),
			.y = discard.y,
			.width = ui::pxf(110.0f),
			.height = ui::pxf(24.0f),
		};
		draw_button(discard, "Discard", true, (float)ui::tpx(12));
		draw_button(cancel, "Cancel", true, (float)ui::tpx(12));
	}

	if (self.error_open)
	{
		rl::draw_rectangle_rec(panel, { 0, 0, 0, 140 });
		Rect modal = {
			.x = panel.x + panel.width / 2.0f - ui::pxf(170.0f),
			.y = panel.y + panel.height / 2.0f - ui::pxf(90.0f),
			.width = ui::pxf(340.0f),
			.height = ui::pxf(180.0f),
		};
		ui::rounded_rect(modal, ui::corner_radius(), theme::current().panel_bg_alt);
		ui::rounded_rect_lines(modal, ui::corner_radius(), 1.0f, theme::current().panel_border);
		rl::draw_text_ex(
			ui::font(),
			git.error.message.zstr_tcopy(),
			{ modal.x + ui::pxf(14.0f), modal.y + ui::pxf(12.0f) },
			(float)ui::tpx(14),
			0.0f,
			theme::current()
			.panel_text);
		String detail = git.error.detail.len > 0 ? git.error.detail : "No additional details.";
		int line      = 0;
		usz start     = 0;
		for (usz i = 0; i <= detail.len && line < 8; i++)
		{
			if (i < detail.len && detail[i] != '\n') continue;
			if (i > start)
			{
				String row = detail[start:i - start];
				@pool()
				{
					rl::draw_text_ex(
						ui::font(),
						row.zstr_tcopy(),
						{ modal.x + ui::pxf(14.0f), modal.y + ui::pxf(38.0f + (float)line * 17.0f) },
						(float)ui::tpx(12),
						0.0f,
						theme::current()
						.panel_dim);
				};
			}
			line++;
			start = i + 1;
		}
		rl::draw_text_ex(
			ui::font(),
			"Esc: close",
			{ modal.x + modal.width - ui::pxf(70.0f), modal.y + modal.height - ui::pxf(24.0f) },
			(float)ui::tpx(11),
			0.0f,
			theme::current()
			.panel_disabled);
	}

	self.draw_branch_picker(git, canvas, text_size);
}

fn bool Panel.take_open(&self, String* path)
{
	if (!self.open_pending) return false;
	*path = self.pending_open;
	self.pending_open = "";
	self.open_pending = false;
	return true;
}
fn bool Panel.take_resolve(&self, String* rel, String* abs)
{
	if (!self.resolve_pending) return false;
	*rel = self.pending_resolve_rel;
	*abs = self.pending_resolve_abs;
	self.pending_resolve_rel = "";
	self.pending_resolve_abs = "";
	self.resolve_pending = false;
	return true;
}

fn bool Panel.take_history(&self, String* path)
{
	if (!self.history_pending) return false;
	*path = self.pending_history_path;
	self.pending_history_path = "";
	self.history_pending = false;
	return true;
}