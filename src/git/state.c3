module yun::git;

import std::collections::list;
import std::core::dstring;
import std::core::mem::alloc;
import std::io::file;
import std::io::path;

const int STATUS_TIMEOUT_MS   = 30000;
const int DETECT_TIMEOUT_MS   = 10000;
const int DIFF_TIMEOUT_MS     = 60000;
const int ACTION_TIMEOUT_MS   = 120000;
const int BRANCH_TIMEOUT_MS   = 15000;
const int REMOTE_TIMEOUT_MS   = 300000;
const int HISTORY_TIMEOUT_MS  = 30000;
const usz STATUS_OUTPUT_CAP   = 4 * 1024 * 1024;
const usz DETECT_OUTPUT_CAP   = 64 * 1024;
const usz DIFF_OUTPUT_CAP     = 16 * 1024 * 1024;
const usz ACTION_OUTPUT_CAP   = 4 * 1024 * 1024;
const usz BRANCH_OUTPUT_CAP   = 512 * 1024;
const usz REMOTE_OUTPUT_CAP   = 2 * 1024 * 1024;
const usz HISTORY_OUTPUT_CAP  = 4 * 1024 * 1024;
const double PERIODIC_REFRESH = 5.0;

struct GitSettings
{
	String binary;
	bool auto_refresh;
	int debounce_ms;
	bool confirm_discard;
	String default_remote;
}

GitSettings g_git_settings = {
	.binary = "git",
	.auto_refresh = true,
	.debounce_ms = 250,
	.confirm_discard = true,
	.default_remote = "origin",
};

fn GitSettings settings()
{
	return g_git_settings;
}

fn void set_settings(GitSettings value)
{
	if (value.binary.len == 0) value.binary = "git";
	if (value.debounce_ms < 0) value.debounce_ms = 0;
	if (value.debounce_ms > 5000) value.debounce_ms = 5000;
	if (value.default_remote.len == 0) value.default_remote = "origin";
	g_git_settings = value;
}

struct State
{
	Allocator allocator;
	GitExecutor executor;
	String project_root;
	String repo_root;
	String binary;
	GitStatus status;
	bool has_status;
	ulong status_revision;
	List{GitBranch} branches;
	ulong branches_revision;
	bool branches_loaded;
	bool is_repo;
	bool checked;
	bool dirty;
	double dirty_at;
	bool refresh_requested;
	bool refreshing;
	ulong next_id;
	ulong in_flight_id;
	GitRequestKind in_flight_kind;
	GitError error;
	ulong error_revision;
	bool error_quiet;
	GitAction action;
	ulong action_revision;
	bool busy;
	bool sync_pending;
	GitDiffResult diff;
	ulong diff_revision;
	int last_cards_revision;
	double last_periodic;
	bool last_focus;
	double current_now;
	String patch_file;
	List{GitCommit} commits;
	ulong commits_revision;
	bool history_requested;
	String pending_history_path;
	List{GitCommitFile} commit_files;
	ulong commit_files_revision;
	bool commit_files_requested;
	String pending_commit_hash;
}

fn void State.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.executor.init(allocator);
	self.project_root = "";
	self.repo_root = "";
	self.binary = "";
	self.status.init(allocator);
	self.has_status = false;
	self.status_revision = 0;
	self.branches.init(allocator);
	self.branches_revision = 0;
	self.branches_loaded = false;
	self.is_repo = false;
	self.checked = false;
	self.dirty = false;
	self.dirty_at = 0.0;
	self.refresh_requested = false;
	self.refreshing = false;
	self.next_id = 1;
	self.in_flight_id = 0;
	self.in_flight_kind = GitRequestKind.STATUS;
	self.error.init(allocator);
	self.error_revision = 0;
	self.error_quiet = false;
	self.action.init(allocator);
	self.action_revision = 0;
	self.busy = false;
	self.sync_pending = false;
	self.diff.init(allocator);
	self.diff_revision = 0;
	self.last_cards_revision = -1;
	self.last_periodic = 0.0;
	self.last_focus = false;
	self.current_now = 0.0;
	self.patch_file = "";
	self.commits.init(allocator);
	self.commits_revision = 0;
	self.history_requested = false;
	self.pending_history_path = "";
	self.commit_files.init(allocator);
	self.commit_files_revision = 0;
	self.commit_files_requested = false;
	self.pending_commit_hash = "";
}

fn void State.destroy(&self)
{
	if (self.in_flight_id != 0) self.executor.cancel(self.in_flight_id);
	self.executor.stop();
	if (self.project_root.len > 0) self.project_root.free(self.allocator);
	if (self.repo_root.len > 0) self.repo_root.free(self.allocator);
	if (self.binary.len > 0) self.binary.free(self.allocator);
	self.clear_patch_file();
	self.clear_history();
	self.commits.free();
	self.commit_files.free();
	self.status.destroy();
	self.clear_branches();
	self.branches.free();
	self.error.clear();
	self.action.destroy();
	self.diff.destroy();
}

fn void State.clear_patch_file(&self)
{
	if (self.patch_file.len == 0) return;
	(void)file::delete(self.patch_file);
	self.patch_file.free(self.allocator);
	self.patch_file = "";
}

fn void State.clear_history(&self)
{
	for (sz i = 0; i < self.commits.len(); i++) self.commits[i].destroy(self.allocator);
	self.commits.clear();
	for (sz i = 0; i < self.commit_files.len(); i++) self.commit_files[i].destroy(self.allocator);
	self.commit_files.clear();
	if (self.pending_history_path.len > 0) self.pending_history_path.free(self.allocator);
	if (self.pending_commit_hash.len > 0) self.pending_commit_hash.free(self.allocator);
	self.pending_history_path = "";
	self.pending_commit_hash = "";
	self.history_requested = false;
	self.commit_files_requested = false;
}

fn void State.clear_branches(&self)
{
	for (sz i = 0; i < self.branches.len(); i++)
	{
		self.branches[i].destroy(self.allocator);
	}
	self.branches.clear();
	self.branches_revision++;
}

fn void State.clear_status(&self)
{
	GitStatus fresh;
	fresh.init(self.allocator);
	self.status.destroy();
	self.status = fresh;
	self.has_status = false;
	self.status_revision++;
}

fn void State.cancel_in_flight(&self)
{
	if (self.in_flight_id != 0) self.executor.cancel(self.in_flight_id);
	self.in_flight_id = 0;
	self.refreshing = false;
	self.busy = false;
	self.clear_patch_file();
}

fn void State.set_project(&self, String root)
{
	self.cancel_in_flight();
	if (self.project_root.len > 0) self.project_root.free(self.allocator);
	self.project_root = root.len > 0 ? root.copy(self.allocator) : "";
	if (self.repo_root.len > 0) self.repo_root.free(self.allocator);
	self.repo_root = "";
	self.clear_status();
	self.clear_branches();
	self.clear_history();
	self.branches_loaded = false;
	self.checked = false;
	self.is_repo = false;
	self.dirty = root.len > 0;
	self.dirty_at = 0.0;
	self.refresh_requested = false;
	self.last_cards_revision = -1;
	self.last_periodic = 0.0;
	self.error.clear();
	self.error_quiet = false;
}

fn void State.mark_dirty(&self, double now)
{
	if (self.project_root.len == 0) return;
	self.dirty = true;
	self.dirty_at = now;
}

fn void State.refresh_now(&self, double now)
{
	if (self.project_root.len == 0) return;
	self.refresh_requested = true;
	self.dirty = true;
	self.dirty_at = now - 10.0;
}

fn bool State.busy_or_refreshing(&self)
{
	return self.busy || self.refreshing || self.in_flight_id != 0;
}

fn bool State.send(
	&self,
	GitRequestKind kind,
	String[] argv,
	int timeout_ms,
	usz output_cap,
	String path,
	String orig_path,
	bool staged,
	bool untracked,
	String rev = ""
)
{
	GitRequest request = {
		.id = self.next_id++,
		.kind = kind,
		.argv = argv,
		.timeout_ms = timeout_ms,
		.output_cap = output_cap,
		.staged = staged,
		.untracked = untracked,
		.rev = rev.len > 0 ? rev.copy(self.allocator) : "",
		.path = path.len > 0 ? path.copy(self.allocator) : "",
		.orig_path = orig_path.len > 0 ? orig_path.copy(self.allocator) : "",
	};
	if (!self.executor.submit(&request))
	{
		self.set_error(GitErrorKind.NOT_FOUND, "Could not start Git. Check the git.binary setting.", "");
		return false;
	}
	self.in_flight_id = request.id;
	self.in_flight_kind = kind;
	return true;
}

fn String first_line(String value)
{
	usz end = 0;
	while (end < value.len && value[end] != '\n' && value[end] != '\r') end++;
	return value[0:end];
}

fn bool contains_ci(String haystack, String needle)
{
	if (needle.len == 0 || haystack.len < needle.len) return false;
	for (usz i = 0; i + needle.len <= haystack.len; i++)
	{
		bool match = true;
		for (usz j = 0; j < needle.len; j++)
		{
			char a = haystack[i + j];
			char b = needle[j];
			if (a >= 'A' && a <= 'Z') a = (char)(a + ('a' - 'A'));
			if (b >= 'A' && b <= 'Z') b = (char)(b + ('a' - 'A'));
			if (a != b)
			{
				match = false;
				break;
			}
		}
		if (match) return true;
	}
	return false;
}

fn GitErrorKind classify_error(String detail)
{
	if (contains_ci(detail, "index.lock") || contains_ci(detail, "unable to create") && contains_ci(detail, ".lock"))
	{
		return GitErrorKind.LOCKED;
	}
	if (contains_ci(
		detail,
		"authentication failed"
	) || contains_ci(
		detail,
		"could not read username"
	) || contains_ci(detail, "permission denied (publickey)") || contains_ci(detail, "terminal prompts disabled"))
	{
		return GitErrorKind.AUTH;
	}
	if (contains_ci(
		detail,
		"could not resolve host"
	) || contains_ci(
		detail,
		"unable to access"
	) || contains_ci(detail, "connection refused") || contains_ci(detail, "network is unreachable"))
	{
		return GitErrorKind.NETWORK;
	}
	if (contains_ci(detail, "conflict") || contains_ci(detail, "unmerged")) return GitErrorKind.CONFLICT;
	return GitErrorKind.COMMAND_FAILED;
}

fn String error_message(GitErrorKind kind, String detail)
{
	switch (kind)
	{
		case GitErrorKind.NOT_FOUND:
			return "Git is not installed or not on PATH.";
		case GitErrorKind.NOT_REPO:
			return "Not a Git repository.";
		case GitErrorKind.TIMEOUT:
			return "Git did not finish in time.";
		case GitErrorKind.LOCKED:
			return "The Git index is locked by another process.";
		case GitErrorKind.AUTH:
			return "Git authentication failed.";
		case GitErrorKind.NETWORK:
			return "Could not reach the Git remote.";
		case GitErrorKind.CONFLICT:
			return "Git reported unresolved conflicts.";
		case GitErrorKind.COMMAND_FAILED:
			break;
		case GitErrorKind.NONE:
			return "";
	}
	String line = first_line(detail);
	if (line.len == 0) return "Git command failed.";
	return line;
}

fn void State.set_error(&self, GitErrorKind kind, String message, String detail)
{
	if (self.error.kind == kind && self.error.message.compare_to(message) == 0) return;
	self.error.set(kind, message, detail);
	self.error_revision++;
}

fn void State.clear_error(&self)
{
	if (self.error.kind == GitErrorKind.NONE) return;
	self.error.clear();
	self.error_quiet = false;
	self.error_revision++;
}

fn void State.start_detect(&self)
{
	if (self.busy_or_refreshing()) return;
	String[] argv = git_detect_argv(self.allocator, self.binary, self.project_root);
	if (!self.send(GitRequestKind.DETECT, argv, DETECT_TIMEOUT_MS, DETECT_OUTPUT_CAP, "", "", false, false))
	{
		self.checked = true;
		self.is_repo = false;
		self.dirty = false;
		return;
	}
	self.refreshing = true;
}

fn void State.start_status(&self)
{
	if (self.busy_or_refreshing()) return;
	String[] argv = git_status_argv(self.allocator, self.binary, self.repo_root);
	if (!self.send(GitRequestKind.STATUS, argv, STATUS_TIMEOUT_MS, STATUS_OUTPUT_CAP, "", "", false, false))
	{
		self.dirty = false;
		return;
	}
	self.refreshing = true;
}

fn void State.start_branch_list(&self)
{
	if (self.busy_or_refreshing()) return;
	String[] argv = git_branch_list_argv(self.allocator, self.binary, self.repo_root);
	if (!self.send(GitRequestKind.BRANCH_LIST, argv, BRANCH_TIMEOUT_MS, BRANCH_OUTPUT_CAP, "", "", false, false))
	{
		self.branches_loaded = true;
		self.dirty = false;
		return;
	}
	self.refreshing = true;
}

fn void State.start_log(&self)
{
	if (self.busy_or_refreshing()) return;
	String[] argv = git_log_argv(self.allocator, self.binary, self.repo_root, self.pending_history_path);
	self.history_requested = false;
	self.refreshing = true;
	if (!self.send(GitRequestKind.LOG, argv, HISTORY_TIMEOUT_MS, HISTORY_OUTPUT_CAP, "", "", false, false))
	{
		self.refreshing = false;
		return;
	}
}

fn void State.start_commit_files(&self)
{
	if (self.busy_or_refreshing()) return;
	String[] argv = git_commit_files_argv(self.allocator, self.binary, self.repo_root, self.pending_commit_hash);
	self.commit_files_requested = false;
	self.refreshing = true;
	if (!self.send(GitRequestKind.COMMIT_FILES, argv, HISTORY_TIMEOUT_MS, HISTORY_OUTPUT_CAP, "", "", false, false))
	{
		self.refreshing = false;
		return;
	}
}

fn void State.handle_log(&self, GitResult* result)
{
	if (result.exit_code != 0)
	{
		self.set_error(GitErrorKind.COMMAND_FAILED, "Could not load Git history.", result.error.str_view());
		return;
	}
	List{GitCommit} next;
	next.init(self.allocator);
	parse_log(self.allocator, result.output.str_view(), &next);
	for (sz i = 0; i < self.commits.len(); i++) self.commits[i].destroy(self.allocator);
	self.commits.free();
	self.commits = next;
	self.commits_revision++;
}

fn void State.handle_commit_files(&self, GitResult* result)
{
	if (result.exit_code != 0)
	{
		self.set_error(GitErrorKind.COMMAND_FAILED, "Could not load commit details.", result.error.str_view());
		return;
	}
	List{GitCommitFile} next;
	next.init(self.allocator);
	parse_commit_files(self.allocator, result.output.str_view(), &next);
	for (sz i = 0; i < self.commit_files.len(); i++) self.commit_files[i].destroy(self.allocator);
	self.commit_files.free();
	self.commit_files = next;
	self.commit_files_revision++;
}

fn void State.handle_detect(&self, GitResult* result)
{
	if (result.spawn_failed)
	{
		self.checked = true;
		self.is_repo = false;
		self.dirty = false;
		self.set_error(GitErrorKind.NOT_FOUND, "Git is not installed or not on PATH.", "");
		self.error_quiet = false;
		return;
	}
	if (result.timed_out)
	{
		self.checked = true;
		self.is_repo = false;
		self.dirty = false;
		self.set_error(GitErrorKind.TIMEOUT, "Git did not respond while detecting the repository.", "");
		return;
	}
	if (result.exit_code != 0)
	{
		self.checked = true;
		self.is_repo = false;
		self.dirty = false;
		self.set_error(GitErrorKind.NOT_REPO, "Not a Git repository.", result.error.str_view());
		self.error_quiet = true;
		return;
	}
	String raw = result.output.str_view();
	usz end    = 0;
	while (end < raw.len && raw[end] != '\n' && raw[end] != '\r') end++;
	String root = trim_eol(raw[0:end]);
	if (root.len == 0)
	{
		self.checked = true;
		self.is_repo = false;
		self.dirty = false;
		self.set_error(GitErrorKind.NOT_REPO, "Not a Git repository.", "");
		self.error_quiet = true;
		return;
	}
	if (self.repo_root.len > 0) self.repo_root.free(self.allocator);
	self.repo_root = root.copy(self.allocator);
	self.checked = true;
	self.is_repo = true;
	self.branches_loaded = false;
	self.clear_branches();
	self.clear_error();
	self.dirty = true;
	self.dirty_at = 0.0;
}

fn void State.handle_status(&self, GitResult* result)
{
	if (result.spawn_failed)
	{
		self.dirty = false;
		self.set_error(GitErrorKind.NOT_FOUND, "Git is not installed or not on PATH.", "");
		return;
	}
	if (result.timed_out)
	{
		self.dirty = false;
		self.set_error(GitErrorKind.TIMEOUT, "Git status did not finish in time.", "");
		return;
	}
	if (result.exit_code != 0)
	{
		self.dirty = false;
		GitErrorKind kind = classify_error(result.error.str_view());
		self.set_error(kind, error_message(kind, result.error.str_view()), result.error.str_view());
		return;
	}

	GitStatus next;
	next.init(self.allocator);
	String data = result.output.str_view();
	if (!next.parse(self.repo_root, data))
	{
		next.destroy();
		self.dirty = false;
		self.set_error(GitErrorKind.COMMAND_FAILED, "Could not parse Git status.", "");
		return;
	}
	self.status.destroy();
	self.status = next;
	self.has_status = true;
	self.status_revision++;
	self.is_repo = true;
	self.checked = true;
	self.clear_error();
	if (self.dirty) self.dirty_at = 0.0;
}

fn void State.handle_diff(&self, GitResult* result)
{
	self.diff.destroy();
	self.diff.init(self.allocator);
	self.diff.valid = true;
	self.diff.staged = result.staged;
	self.diff.untracked = result.untracked;
	self.diff.rev = result.rev.len > 0 ? result.rev.copy(self.allocator) : "";
	self.diff.path = result.path.len > 0 ? result.path.copy(self.allocator) : "";
	self.diff.orig_path = result.orig_path.len > 0 ? result.orig_path.copy(self.allocator) : "";
	self.diff.exit_code = result.exit_code;
	self.diff.output = result.output.len() > 0 ? result.output.copy_str(self.allocator) : "";
	self.diff.error = result.error.len() > 0 ? result.error.copy_str(self.allocator) : "";
	self.diff.truncated = result.truncated;
	if (result.spawn_failed)
	{
		if (self.diff.error.len > 0) self.diff.error.free(self.allocator);
		self.diff.error = "Could not start Git".copy(self.allocator);
	}
	self.diff_revision++;
}

fn void State.handle_action(&self, GitResult* result)
{
	self.action.destroy();
	self.action.init(self.allocator);
	self.action.kind = result.kind;
	self.action.success = result.exit_code == 0 && !result.spawn_failed && !result.timed_out && !result.cancelled;
	self.action.output = result.output.len() > 0 ? result.output.copy_str(self.allocator) : "";
	self.action.error = result.error.len() > 0 ? result.error.copy_str(self.allocator) : "";
	if (result.spawn_failed || result.timed_out || result.cancelled)
	{
		if (self.action.error.len > 0) self.action.error.free(self.allocator);
		if (result.spawn_failed)
		{
			self.action.error = "Could not start Git".copy(self.allocator);
		}
		else if (result.timed_out)
		{
			self.action.error = "Git did not finish in time.".copy(self.allocator);
		}
		else
		{
			self.action.error = "Git command was cancelled.".copy(self.allocator);
		}
	}
	self.action_revision++;
	self.busy = false;
	if (self.action.success)
	{
		self.clear_error();
		if (self.action.kind == GitRequestKind.BRANCH_SWITCH || self.action.kind == GitRequestKind.BRANCH_CREATE)
		{
			self.branches_loaded = false;
			self.clear_status();
		}
	}
	else
	{
		GitErrorKind kind = classify_error(self.action.error);
		self.set_error(kind, error_message(kind, self.action.error), self.action.error);
	}
	if (self.sync_pending)
	{
		if (result.kind == GitRequestKind.PULL && self.action.success)
		{
			self.sync_pending = false;
			(void)self.push(false);
		}
		else if (!self.action.success)
		{
			self.sync_pending = false;
		}
	}
	self.mark_dirty(self.current_now);
}

fn void State.handle_branch_list(&self, GitResult* result)
{
	self.branches_loaded = true;
	if (result.spawn_failed)
	{
		self.dirty = false;
		self.set_error(GitErrorKind.NOT_FOUND, "Git is not installed or not on PATH.", "");
		return;
	}
	if (result.timed_out)
	{
		self.dirty = false;
		self.set_error(GitErrorKind.TIMEOUT, "Git did not finish listing branches.", "");
		return;
	}
	if (result.exit_code != 0)
	{
		self.dirty = false;
		GitErrorKind kind = classify_error(result.error.str_view());
		self.set_error(kind, error_message(kind, result.error.str_view()), result.error.str_view());
		return;
	}
	List{GitBranch} next;
	next.init(self.allocator);
	if (!parse_branches(self.allocator, result.output.str_view(), &next))
	{
		for (sz i = 0; i < next.len(); i++) next[i].destroy(self.allocator);
		next.free();
		self.dirty = false;
		self.set_error(GitErrorKind.COMMAND_FAILED, "Could not parse Git branches.", "");
		return;
	}
	self.clear_branches();
	self.branches.free();
	self.branches = next;
	self.branches_revision++;
	self.clear_error();
	self.dirty = true;
	self.dirty_at = 0.0;
}

fn void State.handle_result(&self, GitResult* result)
{
	if (result.id != self.in_flight_id)
	{
		result.destroy(self.allocator);
		return;
	}
	self.in_flight_id = 0;
	self.refreshing = false;
	GitRequestKind kind = result.kind;
	switch (kind)
	{
		case GitRequestKind.DETECT:
			self.handle_detect(result);
		case GitRequestKind.STATUS:
			self.handle_status(result);
		case GitRequestKind.DIFF:
			self.handle_diff(result);
		case GitRequestKind.BRANCH_LIST:
			self.handle_branch_list(result);
		case GitRequestKind.STAGE:
		case GitRequestKind.UNSTAGE:
		case GitRequestKind.DISCARD:
		case GitRequestKind.COMMIT:
		case GitRequestKind.BRANCH_SWITCH:
		case GitRequestKind.BRANCH_CREATE:
		case GitRequestKind.FETCH:
		case GitRequestKind.PULL:
		case GitRequestKind.PUSH:
		case GitRequestKind.PUBLISH:
		case GitRequestKind.MERGE_ABORT:
		case GitRequestKind.APPLY_PATCH:
			self.handle_action(result);
		case GitRequestKind.LOG:
			self.handle_log(result);
		case GitRequestKind.COMMIT_FILES:
			self.handle_commit_files(result);
	}
	if (kind == GitRequestKind.APPLY_PATCH) self.clear_patch_file();
	result.destroy(self.allocator);
	self.in_flight_id = 0;
	self.refreshing = false;
	if (self.is_repo && (self.dirty || self.refresh_requested) && !self.busy) self.dirty_at = self.current_now;
}

fn void State.pump(&self)
{
	if (self.executor.results == null) return;
	for (int i = 0; i < 8; i++)
	{
		GitResult result;
		if (!self.executor.try_pop(&result)) break;
		self.handle_result(&result);
	}
}

fn void State.update(&self, String project_root, int cards_revision, double now, bool window_focused)
{
	if (self.project_root.len == 0 || self.project_root.compare_to(project_root) != 0) return;
	self.current_now = now;
	self.pump();

	String wanted_binary = g_git_settings.binary.len > 0 ? g_git_settings.binary : "git";
	if (self.binary.len == 0 || self.binary.compare_to(wanted_binary) != 0)
	{
		self.cancel_in_flight();
		if (self.binary.len > 0) self.binary.free(self.allocator);
		self.binary = wanted_binary.copy(self.allocator);
		self.checked = false;
		self.is_repo = false;
		self.clear_status();
		self.clear_branches();
		self.branches_loaded = false;
		if (self.repo_root.len > 0) self.repo_root.free(self.allocator);
		self.repo_root = "";
		self.error.clear();
		self.error_quiet = false;
		self.dirty = true;
		self.dirty_at = now;
	}

	if (self.last_focus != window_focused)
	{
		self.last_focus = window_focused;
		if (window_focused) self.mark_dirty(now);
	}
	if (cards_revision != self.last_cards_revision)
	{
		self.last_cards_revision = cards_revision;
		self.mark_dirty(now);
	}
	if (g_git_settings.auto_refresh && self.is_repo && !self.busy_or_refreshing()
		&& now - self.last_periodic >= PERIODIC_REFRESH)
	{
		self.last_periodic = now;
		self.mark_dirty(now);
	}

	if (self.busy_or_refreshing()) return;

	bool allowed = self.refresh_requested || (g_git_settings.auto_refresh && self.dirty);
	if (!allowed) return;
	double debounce = (double)g_git_settings.debounce_ms / 1000.0;
	if (!self.refresh_requested && now - self.dirty_at < debounce) return;

	if (!self.checked)
	{
		if (!git_find_marker(self.project_root))
		{
			self.checked = true;
			self.is_repo = false;
			self.dirty = false;
			self.refresh_requested = false;
			self.clear_status();
			self.clear_error();
			self.error_quiet = false;
			return;
		}
		self.dirty = false;
		self.refresh_requested = false;
		self.start_detect();
		return;
	}
	if (!self.is_repo)
	{
		self.dirty = false;
		self.refresh_requested = false;
		if (self.error.kind == GitErrorKind.NONE) self.error_quiet = false;
		return;
	}

	if (self.history_requested)
	{
		self.start_log();
		return;
	}
	if (self.commit_files_requested)
	{
		self.start_commit_files();
		return;
	}

	if (!self.branches_loaded)
	{
		self.dirty = false;
		self.refresh_requested = false;
		self.start_branch_list();
		return;
	}

	self.dirty = false;
	self.refresh_requested = false;
	self.start_status();
}

fn void State.request_branches(&self)
{
	self.branches_loaded = false;
	self.dirty = true;
	self.refresh_requested = true;
	self.dirty_at = 0.0;
}

fn bool State.switch_branch(&self, String name)
{
	if (self.busy_or_refreshing() || !self.is_repo || name.len == 0) return false;
	String[] argv = git_branch_switch_argv(self.allocator, self.binary, self.repo_root, name);
	self.busy = true;
	if (!self.send(GitRequestKind.BRANCH_SWITCH, argv, ACTION_TIMEOUT_MS, ACTION_OUTPUT_CAP, "", "", false, false))
	{
		self.busy = false;
		return false;
	}
	return true;
}

fn bool State.create_branch(&self, String name)
{
	if (self.busy_or_refreshing() || !self.is_repo || name.len == 0) return false;
	String[] argv = git_branch_create_argv(self.allocator, self.binary, self.repo_root, name);
	self.busy = true;
	if (!self.send(GitRequestKind.BRANCH_CREATE, argv, ACTION_TIMEOUT_MS, ACTION_OUTPUT_CAP, "", "", false, false))
	{
		self.busy = false;
		return false;
	}
	return true;
}

fn String State.default_remote(&self)
{
	return g_git_settings.default_remote.len > 0 ? g_git_settings.default_remote : "origin";
}

fn bool State.sync(&self)
{
	if (!self.has_status || self.status.upstream.len == 0 || !self.pull()) return false;
	self.sync_pending = true;
	return true;
}

fn bool State.fetch(&self)
{
	if (self.busy_or_refreshing() || !self.is_repo) return false;
	String[] argv = git_fetch_argv(self.allocator, self.binary, self.repo_root, self.default_remote());
	self.busy = true;
	if (!self.send(GitRequestKind.FETCH, argv, REMOTE_TIMEOUT_MS, REMOTE_OUTPUT_CAP, "", "", false, false))
	{
		self.busy = false;
		return false;
	}
	return true;
}

fn bool State.pull(&self)
{
	if (self.busy_or_refreshing() || !self.is_repo || !self.has_status || self.status.branch.len == 0)
	{
		return false;
	}
	String[] argv = git_pull_argv(self.allocator, self.binary, self.repo_root);
	self.busy = true;
	if (!self.send(GitRequestKind.PULL, argv, REMOTE_TIMEOUT_MS, REMOTE_OUTPUT_CAP, "", "", false, false))
	{
		self.busy = false;
		return false;
	}
	return true;
}

fn bool State.push(&self, bool publish)
{
	if (self.busy_or_refreshing() || !self.is_repo || !self.has_status || self.status.branch.len == 0)
	{
		return false;
	}
	String[] argv = git_push_argv(
		self.allocator,
		self.binary,
		self.repo_root,
		self.default_remote(),
		self.status.branch,
		publish
	);
	self.busy = true;
	if (!self.send(
		publish ? GitRequestKind.PUBLISH : GitRequestKind.PUSH,
		argv,
		REMOTE_TIMEOUT_MS,
		REMOTE_OUTPUT_CAP,
		"",
		"",
		false,
		false
	))
	{
		self.busy = false;
		return false;
	}
	return true;
}

fn bool State.abort_merge(&self)
{
	if (self.busy_or_refreshing() || !self.is_repo) return false;
	String[] argv = git_merge_abort_argv(self.allocator, self.binary, self.repo_root);
	self.busy = true;
	if (!self.send(GitRequestKind.MERGE_ABORT, argv, ACTION_TIMEOUT_MS, ACTION_OUTPUT_CAP, "", "", false, false))
	{
		self.busy = false;
		return false;
	}
	return true;
}

fn void State.request_history(&self, String path)
{
	if (self.pending_history_path.len > 0) self.pending_history_path.free(self.allocator);
	self.pending_history_path = path.len > 0 ? path.copy(self.allocator) : "";
	self.history_requested = true;
	self.refresh_requested = true;
}

fn void State.request_commit_files(&self, String hash)
{
	if (self.pending_commit_hash.len > 0) self.pending_commit_hash.free(self.allocator);
	self.pending_commit_hash = hash.len > 0 ? hash.copy(self.allocator) : "";
	self.commit_files_requested = true;
	self.refresh_requested = true;
}

fn bool State.apply_patch(&self, String patch, bool reverse)
{
	if (self.busy_or_refreshing() || !self.is_repo || patch.len == 0) return false;
	Path? temp = path::temp_directory(tmem);
	if (catch err = temp) return false;
	String patch_file = string::format(self.allocator, "%s/yun_git_patch_%d.patch", (String)temp, (long)self.next_id);
	if (catch err = file::save(patch_file, patch))
	{
		patch_file.free(self.allocator);
		return false;
	}
	self.clear_patch_file();
	self.patch_file = patch_file;
	String[] argv = git_apply_patch_argv(self.allocator, self.binary, self.repo_root, self.patch_file, reverse);
	self.busy = true;
	if (!self.send(GitRequestKind.APPLY_PATCH, argv, ACTION_TIMEOUT_MS, ACTION_OUTPUT_CAP, "", "", false, false))
	{
		self.clear_patch_file();
		self.busy = false;
		return false;
	}
	return true;
}

fn bool State.request_commit_diff(&self, String rev, String path, String orig_path)
{
	if (self.busy_or_refreshing() || !self.is_repo || rev.len == 0) return false;
	String[] argv = git_show_diff_argv(self.allocator, self.binary, self.repo_root, rev, path, orig_path);
	if (!self.send(GitRequestKind.DIFF, argv, DIFF_TIMEOUT_MS, DIFF_OUTPUT_CAP, path, orig_path, false, false, rev))
	{
		return false;
	}
	self.refreshing = true;
	return true;
}

fn bool State.request_diff(&self, String path, String orig_path, bool staged, bool untracked)
{
	if (self.busy_or_refreshing() || !self.is_repo) return false;
	String[] argv = git_diff_argv(self.allocator, self.binary, self.repo_root, path, orig_path, staged, untracked);
	if (!self.send(GitRequestKind.DIFF, argv, DIFF_TIMEOUT_MS, DIFF_OUTPUT_CAP, path, orig_path, staged, untracked))
	{
		return false;
	}
	self.refreshing = true;
	return true;
}

fn bool State.stage(&self, String[] paths)
{
	if (self.busy_or_refreshing() || !self.is_repo || paths.len == 0) return false;
	String[] argv = git_stage_argv(self.allocator, self.binary, self.repo_root, paths);
	self.busy = true;
	if (!self.send(GitRequestKind.STAGE, argv, ACTION_TIMEOUT_MS, ACTION_OUTPUT_CAP, "", "", false, false))
	{
		self.busy = false;
		return false;
	}
	return true;
}

fn bool State.unstage(&self, String[] paths)
{
	if (self.busy_or_refreshing() || !self.is_repo || paths.len == 0) return false;
	bool initial  = self.has_status && self.status.initial;
	String[] argv = git_unstage_argv(self.allocator, self.binary, self.repo_root, paths, initial);
	self.busy = true;
	if (!self.send(GitRequestKind.UNSTAGE, argv, ACTION_TIMEOUT_MS, ACTION_OUTPUT_CAP, "", "", false, false))
	{
		self.busy = false;
		return false;
	}
	return true;
}

fn bool State.discard(&self, String[] paths)
{
	if (self.busy_or_refreshing() || !self.is_repo || paths.len == 0) return false;
	String[] argv = git_discard_argv(self.allocator, self.binary, self.repo_root, paths);
	self.busy = true;
	if (!self.send(GitRequestKind.DISCARD, argv, ACTION_TIMEOUT_MS, ACTION_OUTPUT_CAP, "", "", false, false))
	{
		self.busy = false;
		return false;
	}
	return true;
}

fn bool State.discard_untracked(&self, String abs_path, double now)
{
	if (catch err = file::delete(abs_path)) return false;
	self.mark_dirty(now);
	self.refresh_requested = true;
	return true;
}

fn bool State.commit(&self, String message, bool amend)
{
	if (self.busy_or_refreshing() || !self.is_repo || message.len == 0) return false;
	String[] argv = git_commit_argv(self.allocator, self.binary, self.repo_root, message, amend);
	self.busy = true;
	if (!self.send(GitRequestKind.COMMIT, argv, ACTION_TIMEOUT_MS, ACTION_OUTPUT_CAP, "", "", false, false))
	{
		self.busy = false;
		return false;
	}
	return true;
}