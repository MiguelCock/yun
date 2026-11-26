module yun::search;

import raylib6::rl;
import std::atomic::types;
import std::collections::list;
import std::collections::map;
import std::core::mem::alloc;
import std::io::file;
import std::io::path;
import std::math::geometry;
import std::os;
import std::thread;
import std::thread::channel;
import yun::card;
import yun::commands;
import yun::editor;
import yun::find;
import yun::keymap;
import yun::lsp;
import yun::markdown;
import yun::project;
import yun::theme;
import yun::topbar;
import yun::ui;

const int MAX_MATCHES_PER_FILE = 200;
const int MAX_RESULTS          = 2000;
const long MAX_FILE_BYTES      = 2 * 1024 * 1024;
const int BINARY_SCAN_BYTES    = 8192;
const int PREVIEW_MAX          = 120;
const int MAX_SEARCH_WORKERS   = 4;
const int PUMP_BATCH_BUDGET    = 32;
const int QUERY_MAX            = 256;
const double RESTART_DEBOUNCE  = 0.15;
const double NAV_HOLD_DELAY    = 0.30;
const double NAV_HOLD_INTERVAL = 0.04;

struct SearchSettings
{
	int max_file_mb;
	int max_matches_per_file;
	int max_results;
	int workers;
	int debounce_ms;
	int preview_length;
}

SearchSettings g_search_settings = { 2, 200, 2000, 4, 150, 120 };

fn void set_settings(SearchSettings s)
{
	g_search_settings.max_file_mb = s.max_file_mb < 1 ? 1 : s.max_file_mb;
	g_search_settings.max_matches_per_file = s.max_matches_per_file < 1 ? 1 : s.max_matches_per_file;
	g_search_settings.max_results = s.max_results < 1 ? 1 : s.max_results;
	g_search_settings.workers = s.workers < 1 ? 1 : s.workers;
	g_search_settings.debounce_ms = s.debounce_ms < 1 ? 1 : s.debounce_ms;
	g_search_settings.preview_length = s.preview_length < 1 ? 1 : s.preview_length;
}
const float TOP_MARGIN = 24.0f;

struct SearchMatch
{
	usz line;
	usz column;
	String preview;
}

struct SearchGroup
{
	String path;
	List{SearchMatch} matches;
}

struct SearchBatch
{
	String path;
	List{SearchMatch} matches;
	uint generation;
}

struct SearchWork
{
	Search* search;
	String path;
	String query;
	bool case_sensitive;
	bool whole_word;
	uint generation;
}

struct SearchTarget
{
	bool valid;
	String path;
	usz line;
	usz column;
}

struct Search
{
	Allocator allocator;
	bool open;
	char[QUERY_MAX] query;
	usz query_len;
	char[QUERY_MAX] replacement;
	usz replace_len;
	bool replace_open;
	int field;
	bool pending_replace;
	bool pending_replace_all;
	bool case_sensitive;
	bool whole_word;
	List{SearchGroup} groups;
	HashMap{String, int} group_index;
	bool scanning;
	usz submitted;
	usz received;
	uint generation;
	ThreadPool pool;
	bool pool_ready;
	UnboundedChannel{SearchBatch}* results;
	Atomic{bool} cancel;
	int selected;
	int scroll;
	int hold_dir;
	double hold_next;
	usz total_matches;
	bool restart_pending;
	double restart_at;
	String root;
	bool consumed;
}

fn bool search_match_at(String line, usz at, String query, bool case_sensitive, bool whole_word)
{
	if (at + query.len > line.len) return false;
	for (usz i = 0; i < query.len; i++)
	{
		char a = line[at + i];
		char b = query[i];
		if (!case_sensitive)
		{
			a = find::fold_ascii(a);
			b = find::fold_ascii(b);
		}
		if (a != b) return false;
	}
	if (whole_word)
	{
		if (at > 0 && find::is_word_char(line[at - 1])) return false;
		usz end = at + query.len;
		if (end < line.len && find::is_word_char(line[end])) return false;
	}
	return true;
}

fn usz find_in_line(String line, String query, bool case_sensitive, bool whole_word, usz[] out, usz cap)
{
	usz count = 0;
	if (query.len == 0) return 0;
	usz pos = 0;
	while (pos + query.len <= line.len && count < cap)
	{
		if (search_match_at(line, pos, query, case_sensitive, whole_word))
		{
			out[count] = pos;
			count++;
			pos += query.len;
		}
		else
		{
			pos++;
		}
	}
	return count;
}

fn String preview_of(Allocator allocator, String line)
{
	usz start = 0;
	while (start < line.len && (line[start] == ' ' || line[start] == '\t')) start++;
	usz end = line.len;
	if (end - start > (usz)g_search_settings.preview_length) end = start + (usz)g_search_settings.preview_length;
	return line[start:end - start].copy(allocator);
}

fn void scan_content(
	Allocator allocator,
	String content,
	String query,
	bool case_sensitive,
	bool whole_word,
	List{SearchMatch}* out
)
{
	usz[MAX_MATCHES_PER_FILE] columns;
	usz line  = 0;
	usz start = 0;
	usz found = 0;
	usz limit = (usz)g_search_settings.max_matches_per_file;
	if (limit > (usz)MAX_MATCHES_PER_FILE) limit = (usz)MAX_MATCHES_PER_FILE;
	while (start <= content.len && found < limit)
	{
		usz end = start;
		while (end < content.len && content[end] != '\n') end++;
		String text = content[start:end - start];
		if (text.len > 0 && text[text.len - 1] == '\r') text = text[0:text.len - 1];

		usz cap = limit - found;
		usz n   = find_in_line(text, query, case_sensitive, whole_word, columns[0:MAX_MATCHES_PER_FILE], cap);
		for (usz i = 0; i < n; i++)
		{
			out.push({ .line = line, .column = columns[i], .preview = preview_of(allocator, text) });
			found++;
		}

		if (end >= content.len) break;
		line++;
		start = end + 1;
	}
}

fn bool looks_binary(String content)
{
	usz n = content.len < (usz)BINARY_SCAN_BYTES ? content.len : (usz)BINARY_SCAN_BYTES;
	for (usz i = 0; i < n; i++)
	{
		if (content[i] == 0) return true;
	}
	return false;
}

fn void scan_file_path(
	Allocator allocator,
	String path,
	String query,
	bool case_sensitive,
	bool whole_word,
	List{SearchMatch}* out
)
{
	@pool()
	{
		long? size = path::file_size((Path)path);
		if (catch excuse = size) return;
		if (size > (long)g_search_settings.max_file_mb * 1024L * 1024L) return;

		char[]? data = file::load(tmem, path);
		if (catch excuse = data) return;
		String content = (String)data;
		if (looks_binary(content)) return;
		scan_content(allocator, content, query, case_sensitive, whole_word, out);
	};
}

fn void free_batch(Allocator allocator, SearchBatch* batch)
{
	for (sz i = 0; i < batch.matches.len(); i++) batch.matches[i].preview.free(allocator);
	batch.matches.free();
	batch.path.free(allocator);
}

fn void search_worker(void* arg)
{
	SearchWork* work    = (SearchWork*)arg;
	Search* search      = work.search;
	String path         = work.path;
	String query        = work.query;
	bool case_sensitive = work.case_sensitive;
	bool whole_word     = work.whole_word;
	uint generation     = work.generation;

	List{SearchMatch} matches;
	matches.init(search.allocator);

	if (!search.cancel.load())
	{
		scan_file_path(search.allocator, path, query, case_sensitive, whole_word, &matches);
	}

	SearchBatch batch = { .path = path, .matches = matches, .generation = generation };
	if (search.results) (void)search.results.push(batch);
	query.free(search.allocator);
	alloc::free(search.allocator, work);
}

fn void Search.init_pool(&self)
{
	int workers = g_search_settings.workers;
	if (workers < 1) workers = 1;
	if (workers > MAX_SEARCH_WORKERS) workers = MAX_SEARCH_WORKERS;
	if (catch excuse = self.pool.init(self.allocator, workers))
	{
		self.pool_ready = false;
		return;
	}
	UnboundedChannel{SearchBatch}*? created = channel::create_unbounded{SearchBatch}(self.allocator);
	if (catch excuse = created)
	{
		self.pool.destroy();
		self.pool_ready = false;
		return;
	}
	self.results = created;
	self.pool_ready = true;
	(void)self.pool.prewarm(workers);
}

fn void Search.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.open = false;
	self.query_len = 0;
	self.query[0] = 0;
	self.replace_len = 0;
	self.replacement[0] = 0;
	self.replace_open = false;
	self.field = 0;
	self.pending_replace = false;
	self.pending_replace_all = false;
	self.case_sensitive = false;
	self.whole_word = false;
	self.groups.init(allocator);
	self.group_index.init(allocator);
	self.scanning = false;
	self.submitted = 0;
	self.received = 0;
	self.generation = 0;
	self.selected = 0;
	self.scroll = 0;
	self.hold_dir = 0;
	self.hold_next = 0.0;
	self.total_matches = 0;
	self.restart_pending = false;
	self.restart_at = 0.0;
	self.root = "";
	self.consumed = false;
	self.cancel.store(false);
	self.results = null;
	self.pool_ready = false;
	self.init_pool();
}

fn void Search.clear_results(&self)
{
	for (sz i = 0; i < self.groups.len(); i++)
	{
		for (sz m = 0; m < self.groups[i].matches.len(); m++)
		{
			if (self.groups[i].matches[m].preview.len) self.groups[i].matches[m].preview.free(self.allocator);
		}
		self.groups[i].matches.free();
		self.groups[i].path.free(self.allocator);
	}
	self.groups.clear();
	self.group_index.clear();
	self.total_matches = 0;
	self.selected = 0;
	self.scroll = 0;
}

fn void Search.destroy(&self)
{
	if (self.pool_ready)
	{
		self.pool.destroy();
		self.pool_ready = false;
	}
	if (self.results)
	{
		while (true)
		{
			SearchBatch? maybe = self.results.try_pop();
			if (catch excuse = maybe) break;
			SearchBatch batch = maybe;
			free_batch(self.allocator, &batch);
		}
		self.results.destroy();
		self.results = null;
	}
	self.clear_results();
	self.groups.free();
	self.group_index.free();
	if (self.root.len) self.root.free(self.allocator);
}

fn String Search.query_view(&self)
{
	return (String)self.query[0:self.query_len];
}

fn void Search.set_root(&self, String root)
{
	if (self.root.len) self.root.free(self.allocator);
	self.root = root.copy(self.allocator);
}

fn String Search.relative(&self, String path)
{
	if (self.root.len > 0 && path.len > self.root.len && path[0:self.root.len].compare_to(
		self.root
	) == 0 && path[self.root.len] == '/')
	{
		return path[self.root.len + 1:path.len - self.root.len - 1];
	}
	return path;
}

fn void Search.show(&self)
{
	self.open = true;
	self.query_len = 0;
	self.query[0] = 0;
	self.replace_len = 0;
	self.replacement[0] = 0;
	self.replace_open = false;
	self.field = 0;
	self.pending_replace = false;
	self.pending_replace_all = false;
	self.case_sensitive = false;
	self.whole_word = false;
	self.restart_pending = false;
	self.hold_dir = 0;
	self.cancel_run();
	self.clear_results();
}

fn void Search.show_replace(&self)
{
	self.show();
	self.replace_open = true;
	self.field = 0;
}

fn String Search.replacement_view(&self)
{
	return (String)self.replacement[0:self.replace_len];
}

fn void Search.close(&self)
{
	self.cancel_run();
	self.hold_dir = 0;
	self.open = false;
}

fn void Search.cancel_run(&self)
{
	self.cancel.store(true);
	self.generation++;
	self.scanning = false;
	self.submitted = 0;
	self.received = 0;
	self.restart_pending = false;
}

fn void Search.schedule_restart(&self, double now)
{
	self.restart_pending = true;
	self.restart_at = now + (double)g_search_settings.debounce_ms / 1000.0;
}

fn void Search.start(&self, project::Project* project)
{
	self.clear_results();
	self.set_root((String)project.root);
	self.generation++;
	self.cancel.store(false);
	self.scanning = true;
	self.submitted = 0;
	self.received = 0;

	String query = self.query_view();
	if (query.len == 0 || !self.pool_ready)
	{
		self.scanning = false;
		return;
	}

	@pool()
	{
		HashMap{String, int} seen;
		seen.init(tmem);
		for (sz i = 0; i < project.cards.len(); i++)
		{
			String path = (String)project.cards[i].path;
			if (seen.has_key(path)) continue;
			seen.set(path, 0);

			SearchWork* work = alloc::new(self.allocator, SearchWork);
			work.search = self;
			work.path = path.copy(self.allocator);
			work.query = query.copy(self.allocator);
			work.case_sensitive = self.case_sensitive;
			work.whole_word = self.whole_word;
			work.generation = self.generation;
			if (catch excuse = self.pool.add_task(&search_worker, work))
			{
				work.path.free(self.allocator);
				work.query.free(self.allocator);
				alloc::free(self.allocator, work);
				continue;
			}
			self.submitted++;
		}
	};
	if (self.submitted == 0) self.scanning = false;
}

fn void Search.merge_batch(&self, SearchBatch* batch)
{
	if (batch.matches.len() > 0 && self.total_matches < (usz)g_search_settings.max_results)
	{
		int group      = -1;
		int*? existing =  self.group_index.get_ref(batch.path);
		if (catch excuse = existing)
		{
			SearchGroup created;
			created.path = batch.path.copy(self.allocator);
			created.matches.init(self.allocator);
			self.groups.push(created);
			group = (int)(self.groups.len() - 1);
			self.group_index.set(self.groups[group].path, group);
		}
		else
		{
			group = *existing;
		}
		for (sz i = 0; i < batch.matches.len(); i++)
		{
			self.groups[group].matches.push(batch.matches[i]);
			self.total_matches++;
		}
		batch.matches.free();
		batch.path.free(self.allocator);
		return;
	}
	free_batch(self.allocator, batch);
}

fn bool search_apply_file(
	Search* self,
	project::Project* project,
	String path,
	List{SearchMatch}* matches,
	String replacement,
	double now,
	String* error,
	int* replaced
)
{
	int index = project.find_card(path);
	if (index < 0)
	{
		*error = "File is no longer in the project";
		return false;
	}
	FileCard* card = &project.cards[index];
	bool was_open  = card.buffer != null;
	editor::ensure_buffer(card, project.allocator);
	if (!card.buffer || !card.history)
	{
		*error = "Could not load a matched file";
		return false;
	}
	String query = self.query_view();
	int changed  = 0;
	for (sz i = matches.len(); i > 0; i--)
	{
		SearchMatch match = matches.get(i - 1);
		usz line_start    = card.buffer.line_start(match.line);
		usz start         = line_start + match.column;
		if (start > card.buffer.length()) continue;
		if (!find::match_at(card.buffer, start, query, self.case_sensitive, self.whole_word)) continue;
		card.cursor = card.history.replace(card.buffer, start, query.len, replacement, now);
		changed++;
	}
	if (changed == 0) return true;
	if (card.cursor > card.buffer.length()) card.cursor = card.buffer.length();
	card.selection_anchor = card.cursor;
	card.dirty = true;
	if (card.highlight) card.highlight.mark_dirty();
	if (card.view) markdown::view_mark_dirty(card.view);
	lsp::lsp_did_change((String)card.path, card.buffer);
	if (!was_open)
	{
		if (!editor::save_buffer(card, project.allocator))
		{
			*error = "Could not write a closed matched file";
			return false;
		}
		(void)editor::unload_buffer(card, project.allocator);
	}
	*replaced += changed;
	return true;
}

fn bool Search.replace_current(&self, project::Project* project, double now, String* error)
{
	if (self.query_len == 0)
	{
		*error = "Type a search query first";
		return false;
	}
	if (self.scanning)
	{
		*error = "Wait for the search to finish";
		return false;
	}
	String path;
	usz line;
	usz column;
	if (!self.match_at_index(self.selected, &path, &line, &column))
	{
		*error = "No search match selected";
		return false;
	}
	int*? group_index = self.group_index.get_ref(path);
	if (catch excuse = group_index) return false;
	SearchGroup* group = &self.groups[*group_index];
	for (sz m = 0; m < group.matches.len(); m++)
	{
		SearchMatch match = group.matches[m];
		if (match.line != line || match.column != column) continue;
		List{SearchMatch} one;
		one.init(self.allocator);
		one.push(match);
		int replaced = 0;
		bool ok      = search_apply_file(self, project, path, &one, self.replacement_view(), now, error, &replaced);
		one.free();
		if (ok) self.schedule_restart(now);
		return ok;
	}
	return false;
}

fn int Search.replace_all_matches(&self, project::Project* project, double now, String* error, int* files)
{
	int replaced = 0;
	*files = 0;
	for (sz g = 0; g < self.groups.len(); g++)
	{
		SearchGroup* group = &self.groups[g];
		if (group.matches.len() == 0) continue;
		int before = replaced;
		if (!search_apply_file(
			self,
			project,
			group.path,
			&group.matches,
			self.replacement_view(),
			now,
			error,
			&replaced
		))
		{
			return replaced;
		}
		if (replaced > before) (*files)++;
	}
	if (replaced > 0) self.schedule_restart(now);
	return replaced;
}

fn void Search.pump(&self, project::Project* project, double now)
{
	if (self.restart_pending && now >= self.restart_at)
	{
		self.restart_pending = false;
		if (self.open && self.query_len > 0) self.start(project);
	}
	if (self.results)
	{
		int budget = PUMP_BATCH_BUDGET;
		while (budget-- > 0)
		{
			SearchBatch? maybe = self.results.try_pop();
			if (catch excuse = maybe) break;
			SearchBatch batch = maybe;
			if (batch.generation == self.generation)
			{
				self.received++;
				self.merge_batch(&batch);
			}
			else
			{
				free_batch(self.allocator, &batch);
			}
		}
	}
	if (self.scanning && self.received >= self.submitted) self.scanning = false;
}

fn int Search.match_count(&self)
{
	return (int)self.total_matches;
}

fn bool Search.match_at_index(&self, int index, String* path, usz* line, usz* column)
{
	if (index < 0) return false;
	int k = 0;
	for (sz g = 0; g < self.groups.len(); g++)
	{
		for (sz m = 0; m < self.groups[g].matches.len(); m++)
		{
			if (k == index)
			{
				*path = self.groups[g].path;
				*line = self.groups[g].matches[m].line;
				*column = self.groups[g].matches[m].column;
				return true;
			}
			k++;
		}
	}
	return false;
}

fn void Search.move_selection(&self, int delta)
{
	int count = self.match_count();
	if (count == 0) return;
	int next = self.selected + delta;
	if (next < 0) next = 0;
	if (next >= count) next = count - 1;
	self.selected = next;
}

fn void Search.begin_hold(&self, int dir, double now)
{
	self.hold_dir = dir;
	self.hold_next = now + NAV_HOLD_DELAY;
}

fn void Search.hold_tick(&self, bool down, bool up, double now)
{
	if (self.hold_dir > 0 && !down)
	{
		self.hold_dir = 0;
	}
	else if (self.hold_dir < 0 && !up)
	{
		self.hold_dir = 0;
	}
	if (self.hold_dir == 0) return;
	if (now < self.hold_next) return;
	self.move_selection(self.hold_dir);
	self.hold_next = now + NAV_HOLD_INTERVAL;
}

fn int Search.selected_ordinal(&self)
{
	int ordinal = 0;
	int k       = 0;
	for (sz g = 0; g < self.groups.len(); g++)
	{
		ordinal++;
		for (sz m = 0; m < self.groups[g].matches.len(); m++)
		{
			if (k == self.selected) return ordinal;
			ordinal++;
			k++;
		}
	}
	return 0;
}

fn float Search.list_y(&self)
{
	float s    = ui::scale();
	Rect panel = self.panel_rect();
	float pad  = 10.0f * s;
	Rect case_rect;
	Rect word_rect;
	self.chip_rects(&case_rect, &word_rect);
	float status_y = case_rect.y + case_rect.height + 6.0f * s;
	return status_y + 20.0f * s;
}

fn int Search.visible_rows(&self)
{
	float s      = ui::scale();
	Rect panel   = self.panel_rect();
	float pad    = 10.0f * s;
	float list_y = self.list_y();
	float list_h = panel.y + panel.height - list_y - pad;
	float row_h  = 20.0f * s;
	int visible  = (int)(list_h / row_h);
	if (visible < 1) visible = 1;
	return visible;
}

fn void Search.ensure_visible(&self)
{
	int ordinal = self.selected_ordinal();
	int visible = self.visible_rows();
	if (ordinal < self.scroll) self.scroll = ordinal;
	if (ordinal >= self.scroll + visible) self.scroll = ordinal - visible + 1;
	if (self.scroll < 0) self.scroll = 0;
}

fn int Search.row_at_mouse(&self, RLVector2 mouse)
{
	float s      = ui::scale();
	Rect panel   = self.panel_rect();
	float list_y = self.list_y();
	if (mouse[1] < list_y) return -1;
	float row_h    = 20.0f * s;
	float header_h = 22.0f * s;
	float y        = list_y;
	int flat       = 0;
	for (sz g = 0; g < self.groups.len(); g++)
	{
		y += header_h;
		for (sz m = 0; m < self.groups[g].matches.len(); m++)
		{
			if (mouse[1] >= y && mouse[1] < y + row_h) return flat;
			y += row_h;
			flat++;
		}
	}
	return -1;
}

fn SearchTarget Search.activate(&self)
{
	SearchTarget target = { .valid = false, .path = "", .line = 0, .column = 0 };
	String path;
	usz line;
	usz column;
	if (self.match_at_index(self.selected, &path, &line, &column))
	{
		target.valid = true;
		target.path = path;
		target.line = line;
		target.column = column;
	}
	return target;
}

fn Rect Search.panel_rect(&self)
{
	float s      = ui::scale();
	Rect content = topbar::content_rect();
	float width  = 780.0f * s;
	if (width > content.width - 24.0f) width = content.width - 24.0f;
	float height = 460.0f * s;
	if (height > content.height - TOP_MARGIN - 24.0f) height = content.height - TOP_MARGIN - 24.0f;
	if (height < 120.0f) height = 120.0f;
	return {
		.x = content.x + (content.width - width) / 2.0f,
		.y = content.y + TOP_MARGIN,
		.width = width,
		.height = height
	};
}

fn void Search.chip_rects(&self, Rect* case_rect, Rect* word_rect)
{
	float s    = ui::scale();
	Rect panel = self.panel_rect();
	float pad  = 10.0f * s;
	float y    = panel.y + pad + 30.0f * s + 8.0f * s;
	if (self.replace_open) y += 30.0f * s + 6.0f * s;
	float h = 22.0f * s;
	float w = 58.0f * s;
	*case_rect = { .x = panel.x + pad, .y = y, .width = w, .height = h };
	*word_rect = { .x = panel.x + pad + w + 6.0f * s, .y = y, .width = w, .height = h };
}

fn Rect Search.replace_rect(&self)
{
	float s    = ui::scale();
	Rect panel = self.panel_rect();
	float pad  = 10.0f * s;
	return {
		.x = panel.x + pad,
		.y = panel.y + pad + 30.0f * s + 6.0f * s,
		.width = panel.width - pad * 2.0f,
		.height = 30.0f * s,
	};
}

fn SearchTarget Search.update(&self, keymap::Keymap* keymap, project::Project* project, double now)
{
	SearchTarget target = { .valid = false, .path = "", .line = 0, .column = 0 };
	if (!self.open) return target;
	self.consumed = false;

	if (keymap.pressed((int)commands::CommandId.OVERLAY_CLOSE, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.close();
		return target;
	}
	if (keymap.pressed((int)commands::CommandId.SEARCH_REPLACE, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.pending_replace = true;
		return target;
	}
	if (keymap.pressed((int)commands::CommandId.SEARCH_REPLACE_ALL, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.pending_replace_all = true;
		return target;
	}
	if (rl::is_key_pressed(rl::RLKeyboardKey.TAB))
	{
		self.consumed = true;
		if (!self.replace_open)
		{
			self.replace_open = true;
			self.field = 1;
		}
		else
		{
			self.field = self.field == 0 ? 1 : 0;
		}
		return target;
	}
	if (keymap.pressed_repeat((int)commands::CommandId.LIST_ACCEPT, commands::CTX_SEARCH))
	{
		self.consumed = true;
		if (self.field == 0) return self.activate();
		self.pending_replace = true;
		return target;
	}

	int visible    = self.visible_rows();
	bool down_held = keymap.held((int)commands::CommandId.LIST_DOWN, commands::CTX_SEARCH);
	bool up_held   = keymap.held((int)commands::CommandId.LIST_UP, commands::CTX_SEARCH);
	if (keymap.pressed((int)commands::CommandId.LIST_DOWN, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.move_selection(1);
		self.begin_hold(1, now);
	}
	else if (keymap.pressed((int)commands::CommandId.LIST_UP, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.move_selection(-1);
		self.begin_hold(-1, now);
	}
	else
	{
		self.hold_tick(down_held, up_held, now);
		if (self.hold_dir != 0) self.consumed = true;
	}
	if (keymap.pressed((int)commands::CommandId.LIST_PAGE_DOWN, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.move_selection(visible);
	}
	if (keymap.pressed((int)commands::CommandId.LIST_PAGE_UP, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.move_selection(-visible);
	}
	self.ensure_visible();

	if (keymap.pressed((int)commands::CommandId.SEARCH_TOGGLE_CASE, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.case_sensitive = !self.case_sensitive;
		self.schedule_restart(now);
	}
	if (keymap.pressed((int)commands::CommandId.SEARCH_TOGGLE_WORD, commands::CTX_SEARCH))
	{
		self.consumed = true;
		self.whole_word = !self.whole_word;
		self.schedule_restart(now);
	}

	if (rl::is_key_pressed(rl::RLKeyboardKey.BACKSPACE) || rl::is_key_pressed_repeat(rl::RLKeyboardKey.BACKSPACE))
	{
		if (self.field == 0)
		{
			if (self.query_len > 0)
			{
				self.query_len--;
				self.query[self.query_len] = 0;
				self.schedule_restart(now);
			}
		}
		else if (self.replace_len > 0)
		{
			self.replace_len--;
			self.replacement[self.replace_len] = 0;
		}
	}

	int codepoint = rl::get_char_pressed();
	while (codepoint != 0)
	{
		if (codepoint >= 32 && codepoint <= 126)
		{
			if (self.field == 0 && self.query_len < QUERY_MAX)
			{
				self.query[self.query_len] = (char)codepoint;
				self.query_len++;
				self.query[self.query_len] = 0;
				self.schedule_restart(now);
			}
			else if (self.field == 1 && self.replace_len < QUERY_MAX)
			{
				self.replacement[self.replace_len] = (char)codepoint;
				self.replace_len++;
				self.replacement[self.replace_len] = 0;
			}
		}
		codepoint = rl::get_char_pressed();
	}

	// Mouse: fields and chips.
	RLVector2 mouse = rl::get_mouse_position();
	float s_mouse   = ui::scale();
	Rect query_rect = {
		.x = self.panel_rect()
		.x + 10.0f * s_mouse, .y = self.panel_rect()
			.y + 10.0f * s_mouse, .width = self.panel_rect().width - 20.0f * s_mouse, .height = 30.0f * s_mouse, };
	Rect replace_rect = self.replace_rect();
	Rect case_rect;
	Rect word_rect;
	self.chip_rects(&case_rect, &word_rect);
	bool case_over = rect_contains(case_rect, mouse);
	bool word_over = rect_contains(word_rect, mouse);
	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
	{
		if (rect_contains(query_rect, mouse))
		{
			self.field = 0;
			return target;
		}
		if (self.replace_open && rect_contains(replace_rect, mouse))
		{
			self.field = 1;
			return target;
		}
		if (case_over)
		{
			self.case_sensitive = !self.case_sensitive;
			self.schedule_restart(now);
		}
		else if (word_over)
		{
			self.whole_word = !self.whole_word;
			self.schedule_restart(now);
		}
		else
		{
			int row = self.row_at_mouse(mouse);
			if (row >= 0)
			{
				self.selected = row;
				return self.activate();
			}
		}
	}
	return target;
}

fn bool rect_contains(Rect r, RLVector2 point)
{
	return point[0] >= r.x && point[0] <= r.x + r.width && point[1] >= r.y && point[1] <= r.y + r.height;
}

fn float text_width(RLFont font, String text, float size)
{
	if (text.len == 0) return 0.0f;
	float width = 0.0f;
	@pool()
	{
		width = rl::measure_text_ex(font, text.zstr_tcopy(), size, 0.0f)[0];
	};
	return width;
}

fn void draw_text(RLFont font, String text, float x, float y, float size, RLColor color)
{
	if (text.len == 0) return;
	@pool()
	{
		rl::draw_text_ex(font, text.zstr_tcopy(), { x, y }, size, 0.0f, color);
	};
}

fn void Search.draw(&self, RLFont font)
{
	if (!self.open) return;

	float s    = ui::scale();
	float ts   = ui::text_scale();
	Rect panel = self.panel_rect();
	ui::floating_panel(panel, theme::current().panel_bg, theme::current().panel_border);

	float pad     = 10.0f * s;
	float field_h = 30.0f * s;
	Rect field    = { .x = panel.x + pad, .y = panel.y + pad, .width = panel.width - pad * 2.0f, .height = field_h };
	ui::rounded_rect(field, ui::row_radius(), theme::current().panel_field);
	ui::rounded_rect_lines(field, ui::row_radius(), self.field == 0 ? 2.0f : 1.0f, self.field == 0 ? theme::current()
		.topbar_hover : theme::current().panel_border);

	String query  = self.query_view();
	float query_w = text_width(font, query, 15.0f * ts);
	draw_text(font, query, field.x + 6.0f * s, field.y + 7.0f * s, 15.0f * ts, theme::current().panel_text);
	if (query.len == 0)
	{
		draw_text(font, "Search in project...", field.x + 6.0f * s, field.y + 7.0f * s, 15.0f * ts, theme::current()
			.panel_dim);
	}
	else if (self.field == 0)
	{
		rl::draw_rectangle(
			(int)(field.x + 6.0f * s + query_w + 1.0f),
			(int)(field.y + 6.0f * s),
			2,
			(int)(16.0f * s),
			theme::current()
			.panel_caret);
	}

	if (self.replace_open)
	{
		Rect replace = self.replace_rect();
		ui::rounded_rect(replace, ui::row_radius(), theme::current().panel_field);
		ui::rounded_rect_lines(
			replace,
			ui::row_radius(),
			self.field == 1 ? 2.0f : 1.0f,
			self.field == 1 ? theme::current()
			.topbar_hover : theme::current().panel_border);
		String replacement    = self.replacement_view();
		RLColor replace_color = self.field == 1 ? theme::current().panel_text : theme::current().panel_dim;
		draw_text(font, replacement, replace.x + 6.0f * s, replace.y + 7.0f * s, 15.0f * ts, replace_color);
		if (replacement.len == 0)
		{
			draw_text(font, "Replace with...", replace.x + 6.0f * s, replace.y + 7.0f * s, 15.0f * ts, theme::current()
				.panel_dim);
		}
		if (self.field == 1)
		{
			float rw = text_width(font, replacement, 15.0f * ts);
			rl::draw_rectangle(
				(int)(replace.x + 6.0f * s + rw + 1.0f),
				(int)(replace.y + 6.0f * s),
				2,
				(int)(16.0f * s),
				theme::current()
				.panel_caret);
		}
	}

	Rect case_rect;
	Rect word_rect;
	self.chip_rects(&case_rect, &word_rect);
	draw_chip(font, case_rect, "Case", self.case_sensitive, s);
	draw_chip(font, word_rect, "Word", self.whole_word, s);

	float status_y = case_rect.y + case_rect.height + 6.0f * s;
	@pool()
	{
		String status;
		if (query.len == 0)
		{
			status = "Type to search";
		}
		else if (self.scanning)
		{
			status = string::format(
				tmem,
				"Searching... %d files, %d matches",
				(long)self.groups.len(),
				(long)self.total_matches
			);
		}
		else
		{
			status = string::format(tmem, "%d matches in %d files", (long)self.total_matches, (long)self.groups.len());
		}
		draw_text(font, status, panel.x + pad, status_y, 14.0f * ts, theme::current().panel_dim);
	};

	float list_y = self.list_y();
	ui::separator_h({ .x = panel.x + 2.0f, .y = list_y - 1.0f, .width = panel.width - 4.0f, .height = 1.0f });
	float list_h = panel.y + panel.height - list_y - pad;
	if (list_h < 0.0f) list_h = 0.0f;
	float row_h     = 20.0f * s;
	float header_h  = 22.0f * s;
	RLVector2 mouse = rl::get_mouse_position();
	int hover_row   = self.row_at_mouse(mouse);
	bool pressed    = rl::is_mouse_button_down(rl::RLMouseButton.LEFT);

	int ordinal = 0;
	int flat    = 0;
	float y     = list_y;
	bool done   = false;
	rl::begin_scissor_mode((int)panel.x + 2, (int)list_y, (int)panel.width - 4, (int)list_h);
	for (sz g = 0; g < self.groups.len() && !done; g++)
	{
		if (ordinal >= self.scroll)
		{
			draw_text(
				font,
				self.relative(self.groups[g].path),
				panel.x + pad,
				y + 3.0f * s,
				14.0f * ts,
				theme::current()
				.panel_header);
			y += header_h;
			if (y > panel.y + panel.height) break;
		}
		ordinal++;
		for (sz m = 0; m < self.groups[g].matches.len(); m++)
		{
			SearchMatch* match = &self.groups[g].matches[m];
			if (ordinal >= self.scroll)
			{
				if (flat == self.selected)
				{
					ui::row(
						{
							.x = panel.x + 2.0f,
							.y = y,
							.width = panel.width - 4.0f,
							.height = row_h,
						},
						theme::current()
						.panel_selected);
				}
				else if (flat == hover_row)
				{
					ui::row(
						{
							.x = panel.x + 2.0f,
							.y = y,
							.width = panel.width - 4.0f,
							.height = row_h,
						},
						pressed ? theme::current()
						.panel_selected : theme::current().panel_bg_alt);
				}
				@pool()
				{
					String label = string::format(
						tmem,
						"%d:%d  %s",
						(long)(match.line + 1),
						(long)(match.column + 1),
						match.preview
					);
					draw_text(font, label, panel.x + pad + 12.0f * s, y + 2.0f * s, 14.0f * ts, theme::current()
						.panel_text);
				};
				y += row_h;
				if (y > panel.y + panel.height)
				{
					done = true;
					break;
				}
			}
			ordinal++;
			flat++;
		}
	}
	rl::end_scissor_mode();
	if (query.len > 0 && self.total_matches == 0 && !self.scanning)
	{
		ui::empty_state(
			font,
			{ .x = panel.x + 2.0f, .y = list_y, .width = panel.width - 4.0f, .height = list_h },
			"No matches",
			"Try a different query or toggle Case/Word"
		);
	}
	int visible_rows = self.visible_rows();
	if ((int)self.total_matches > visible_rows)
	{
		Rect track = {
			.x = panel.x + panel.width - (float)ui::px(5),
			.y = list_y,
			.width = (float)ui::px(3),
			.height = list_h,
		};
		ui::draw_scrollbar(
			track,
			(float)self.total_matches,
			(float)visible_rows,
			(float)self.scroll,
			false,
			theme::current()
			.editor_scrollbar, theme::current().panel_dim, theme::current().panel_text);
	}
}

fn void draw_chip(RLFont font, Rect r, String label, bool on, float s)
{
	float ts = ui::text_scale();
	ui::rounded_rect(r, ui::row_radius(), on ? theme::current().panel_selected : theme::current().findbar_chip);
	ui::rounded_rect_lines(r, ui::row_radius(), 1.0f, theme::current().panel_border);
	@pool()
	{
		float w = text_width(font, label, 14.0f * ts);
		draw_text(font, label, r.x + (r.width - w) / 2.0f, r.y + 4.0f * s, 14.0f * ts, theme::current().panel_text);
	};
}