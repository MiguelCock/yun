module yun::git;

import raylib6::rl;
import yun::theme;

fn RLColor entry_color(GitEntry* entry)
{
	if (entry.conflicted || entry.index == GitFileState.CONFLICTED || entry.worktree == GitFileState.CONFLICTED)
	{
		return theme::current().git_conflict;
	}
	if (entry.untracked) return theme::current().git_untracked;
	char badge = entry_badge(entry);
	switch (badge)
	{
		case 'A':
			return theme::current().git_added;
		case 'D':
			return theme::current().git_deleted;
		case 'R':
		case 'C':
			return theme::current().git_renamed;
		case 'U':
			return theme::current().git_conflict;
		case '?':
			return theme::current().git_untracked;
	}
	return theme::current().git_modified;
}

fn GitEntry* status_entry(GitStatus* status, String abs_path)
{
	if (!status || !status.valid) return null;
	return status.find_abs(abs_path);
}