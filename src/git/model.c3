module yun::git;

import std::collections::list;
import std::collections::map;
import std::io::path;

enum GitFileState : int
{
	UNMODIFIED,
	MODIFIED,
	ADDED,
	DELETED,
	RENAMED,
	COPIED,
	CONFLICTED,
	UNTRACKED,
}

enum GitErrorKind : int
{
	NONE,
	NOT_FOUND,
	NOT_REPO,
	TIMEOUT,
	LOCKED,
	AUTH,
	NETWORK,
	CONFLICT,
	COMMAND_FAILED,
}

enum GitRequestKind : int
{
	DETECT,
	STATUS,
	DIFF,
	STAGE,
	UNSTAGE,
	DISCARD,
	COMMIT,
}

struct GitEntry
{
	String path;
	String orig_path;
	String abs_path;
	GitFileState index;
	GitFileState worktree;
	bool conflicted;
	bool untracked;
}

struct GitStatus
{
	Allocator allocator;
	String root;
	bool valid;
	bool initial;
	bool detached;
	String branch;
	String upstream;
	int ahead;
	int behind;
	List{GitEntry} entries;
	HashMap{String, int} by_abs_path;
}

struct GitError
{
	Allocator allocator;
	GitErrorKind kind;
	String message;
	String detail;
}

struct GitAction
{
	Allocator allocator;
	GitRequestKind kind;
	bool success;
	String output;
	String error;
}

struct GitDiffResult
{
	Allocator allocator;
	bool valid;
	bool staged;
	String path;
	String orig_path;
	int exit_code;
	String output;
	String error;
	bool truncated;
}

fn GitFileState state_from_char(char c)
{
	switch (c)
	{
		case '.':
			return GitFileState.UNMODIFIED;
		case 'M':
		case 'T':
			return GitFileState.MODIFIED;
		case 'A':
			return GitFileState.ADDED;
		case 'D':
			return GitFileState.DELETED;
		case 'R':
			return GitFileState.RENAMED;
		case 'C':
			return GitFileState.COPIED;
		case 'U':
			return GitFileState.CONFLICTED;
	}
	return GitFileState.UNMODIFIED;
}

fn char state_char(GitFileState state)
{
	switch (state)
	{
		case GitFileState.UNMODIFIED:
			return '.';
		case GitFileState.MODIFIED:
			return 'M';
		case GitFileState.ADDED:
			return 'A';
		case GitFileState.DELETED:
			return 'D';
		case GitFileState.RENAMED:
			return 'R';
		case GitFileState.COPIED:
			return 'C';
		case GitFileState.CONFLICTED:
			return 'U';
		case GitFileState.UNTRACKED:
			return '?';
	}
}

fn char entry_badge(GitEntry* entry)
{
	if (entry.conflicted || entry.index == GitFileState.CONFLICTED || entry.worktree == GitFileState.CONFLICTED)
	{
		return 'U';
	}
	if (entry.untracked) return '?';
	if (entry.worktree != GitFileState.UNMODIFIED) return state_char(entry.worktree);
	if (entry.index != GitFileState.UNMODIFIED) return state_char(entry.index);
	return ' ';
}

fn String entry_display_path(GitEntry* entry)
{
	return entry.path;
}

fn bool entry_has_staged(GitEntry* entry)
{
	return !entry.untracked && !entry.conflicted && entry.index != GitFileState.UNMODIFIED;
}

fn bool entry_has_unstaged(GitEntry* entry)
{
	return !entry.untracked && !entry.conflicted && entry.worktree != GitFileState.UNMODIFIED;
}

fn void GitEntry.destroy(&self, Allocator allocator)
{
	if (self.path.len > 0) self.path.free(allocator);
	if (self.orig_path.len > 0) self.orig_path.free(allocator);
	if (self.abs_path.len > 0) self.abs_path.free(allocator);
}

fn void GitStatus.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.root = "";
	self.valid = false;
	self.initial = false;
	self.detached = false;
	self.branch = "";
	self.upstream = "";
	self.ahead = 0;
	self.behind = 0;
	self.entries.init(allocator);
	self.by_abs_path.init(allocator);
}

fn void GitStatus.destroy(&self)
{
	for (sz i = 0; i < self.entries.len(); i++)
	{
		self.entries[i].destroy(self.allocator);
	}
	self.entries.free();
	self.by_abs_path.free();
	if (self.root.len > 0) self.root.free(self.allocator);
	if (self.branch.len > 0) self.branch.free(self.allocator);
	if (self.upstream.len > 0) self.upstream.free(self.allocator);
	self.root = "";
	self.branch = "";
	self.upstream = "";
	self.valid = false;
}

fn GitEntry* GitStatus.find_abs(&self, String abs_path)
{
	int*? index = self.by_abs_path.get_ref(abs_path);
	if (catch excuse = index) return null;
	if (*index < 0 || *index >= (int)self.entries.len()) return null;
	return &self.entries[*index];
}

fn void GitError.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.kind = GitErrorKind.NONE;
	self.message = "";
	self.detail = "";
}

fn void GitError.clear(&self)
{
	if (self.message.len > 0) self.message.free(self.allocator);
	if (self.detail.len > 0) self.detail.free(self.allocator);
	self.kind = GitErrorKind.NONE;
	self.message = "";
	self.detail = "";
}

fn void GitError.set(&self, GitErrorKind kind, String message, String detail)
{
	self.clear();
	self.kind = kind;
	self.message = message.len > 0 ? message.copy(self.allocator) : "";
	self.detail = detail.len > 0 ? detail.copy(self.allocator) : "";
}

fn void GitAction.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.kind = GitRequestKind.STATUS;
	self.success = false;
	self.output = "";
	self.error = "";
}

fn void GitAction.destroy(&self)
{
	if (self.output.len > 0) self.output.free(self.allocator);
	if (self.error.len > 0) self.error.free(self.allocator);
	self.output = "";
	self.error = "";
}

fn void GitDiffResult.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.valid = false;
	self.staged = false;
	self.path = "";
	self.orig_path = "";
	self.exit_code = 0;
	self.output = "";
	self.error = "";
	self.truncated = false;
}

fn void GitDiffResult.destroy(&self)
{
	if (self.path.len > 0) self.path.free(self.allocator);
	if (self.orig_path.len > 0) self.orig_path.free(self.allocator);
	if (self.output.len > 0) self.output.free(self.allocator);
	if (self.error.len > 0) self.error.free(self.allocator);
	self.path = "";
	self.orig_path = "";
	self.output = "";
	self.error = "";
}

fn String trim_eol(String value)
{
	usz len = value.len;
	while (len > 0)
	{
		char c = value[len - 1];
		if (c != '\n' && c != '\r') break;
		len--;
	}
	return value[0:len];
}

fn String path_join_alloc(Allocator allocator, String root, String rel)
{
	if (rel.len == 0) return root.copy(allocator);
	if (rel[0] == '/' || (rel.len > 1 && rel[1] == ':')) return rel.copy(allocator);
	Path? joined = ((Path)root).append(allocator, rel);
	if (catch excuse = joined) return root.copy(allocator);
	return (String)joined;
}