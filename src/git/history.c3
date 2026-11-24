module yun::git;

import std::collections::list;
import std::core::mem::alloc;

fn bool parse_log(Allocator allocator, String data, List{GitCommit}* out)
{
	usz pos = 0;
	while (pos < data.len)
	{
		usz line_end = pos;
		while (line_end < data.len && data[line_end] != '\n') line_end++;
		String line = data[pos:line_end - pos];
		pos = line_end < data.len ? line_end + 1 : data.len;
		if (line.len == 0) continue;
		String[5] fields;
		usz start = 0;
		int count = 0;
		for (usz i = 0; i <= line.len && count < 5; i++)
		{
			if (i < line.len && line[i] != 0) continue;
			fields[count] = line[start:i - start];
			count++;
			start = i + 1;
		}
		if (count < 5) continue;
		out.push(
			{
				.hash = fields[0].copy(allocator),
				.short_hash = fields[1].copy(allocator),
				.author = fields[2].copy(allocator),
				.date = fields[3].copy(allocator),
				.subject = fields[4].copy(allocator),
			}
		);
	}
	return true;
}

fn GitFileState commit_file_state(String status)
{
	if (status.len == 0) return GitFileState.MODIFIED;
	switch (status[0])
	{
		case 'A':
			return GitFileState.ADDED;
		case 'D':
			return GitFileState.DELETED;
		case 'R':
			return GitFileState.RENAMED;
		case 'C':
			return GitFileState.COPIED;
		case 'T':
		case 'M':
			return GitFileState.MODIFIED;
	}
	return GitFileState.MODIFIED;
}

fn bool parse_commit_files(Allocator allocator, String data, List{GitCommitFile}* out)
{
	usz pos = 0;
	while (pos < data.len)
	{
		usz status_end = pos;
		while (status_end < data.len && data[status_end] != 0) status_end++;
		if (status_end >= data.len) break;
		String status = data[pos:status_end - pos];
		pos = status_end + 1;
		usz path_end = pos;
		while (path_end < data.len && data[path_end] != 0) path_end++;
		String first = data[pos:path_end - pos];
		pos = path_end < data.len ? path_end + 1 : data.len;
		String path        = first;
		String orig        = "";
		GitFileState state = commit_file_state(status);
		if (state == GitFileState.RENAMED || state == GitFileState.COPIED)
		{
			usz orig_end = pos;
			while (orig_end < data.len && data[orig_end] != 0) orig_end++;
			orig = first;
			path = data[pos:orig_end - pos];
			pos = orig_end < data.len ? orig_end + 1 : data.len;
		}
		if (path.len == 0) continue;
		if (out.len() >= 1000) break;
		out.push(
			{
				.state = state,
				.path = path.copy(allocator),
				.orig_path = orig.len > 0 ? orig.copy(allocator) : "",
			}
		);
	}
	return true;
}

fn String[] git_log_argv(Allocator allocator, String binary, String root, String path)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("--no-pager");
		list.push("-C");
		list.push(root);
		list.push("log");
		list.push("--max-count=200");
		list.push("--date=short");
		list.push("--format=%H%x00%h%x00%an%x00%ad%x00%s%x00");
		if (path.len > 0)
		{
			list.push("--follow");
			list.push("--");
			list.push(path);
		}
		return finish_argv(allocator, &list);
	};
}

fn String[] git_commit_files_argv(Allocator allocator, String binary, String root, String hash)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-C");
		list.push(root);
		list.push("diff-tree");
		list.push("--no-commit-id");
		list.push("--name-status");
		list.push("-r");
		list.push("-z");
		list.push(hash);
		return finish_argv(allocator, &list);
	};
}