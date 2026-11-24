module yun::git;

import std::collections::list;
import std::collections::map;
import std::io::path;

fn String after_spaces(String token, int count)
{
	usz pos  = 0;
	int seen = 0;
	while (pos < token.len && seen < count)
	{
		if (token[pos] == ' ') seen++;
		pos++;
	}
	if (pos >= token.len) return "";
	return token[pos:token.len - pos];
}

fn String header_value(String token, String key)
{
	if (token.len <= 2) return "";
	String rest = token[2:token.len - 2];
	if (!rest.starts_with(key)) return "";
	if (rest.len <= key.len || rest[key.len] != ' ') return "";
	usz start = key.len + 1;
	if (start >= rest.len) return "";
	return rest[start:rest.len - start];
}

fn int parse_int_prefix(String value, usz* pos)
{
	while (*pos < value.len && value[*pos] == ' ') (*pos)++;
	bool negative = false;
	if (*pos < value.len && (value[*pos] == '+' || value[*pos] == '-'))
	{
		negative = value[*pos] == '-';
		(*pos)++;
	}
	long number = 0;
	while (*pos < value.len && value[*pos] >= '0' && value[*pos] <= '9')
	{
		number = number * 10 + (long)(value[*pos] - '0');
		(*pos)++;
	}
	return negative ? -(int)number : (int)number;
}

fn void parse_branch_ab(GitStatus* status, String value)
{
	usz pos = 0;
	status.ahead = parse_int_prefix(value, &pos);
	int behind = parse_int_prefix(value, &pos);
	status.behind = behind < 0 ? -behind : behind;
}

fn void GitStatus.add_entry(
	&self,
	String path,
	String orig_path,
	GitFileState index,
	GitFileState worktree,
	bool conflicted,
	bool untracked
)
{
	if (path.len == 0) return;
	String abs_path = path_join_alloc(self.allocator, self.root, path);
	if (self.by_abs_path.has_key(abs_path))
	{
		abs_path.free(self.allocator);
		return;
	}
	GitEntry entry = {
		.path = path.copy(self.allocator),
		.orig_path = orig_path.len > 0 ? orig_path.copy(self.allocator) : "",
		.abs_path = abs_path,
		.index = index,
		.worktree = worktree,
		.conflicted = conflicted,
		.untracked = untracked,
	};
	int index_at = (int)self.entries.len();
	self.entries.push(entry);
	self.by_abs_path.set(entry.abs_path, index_at);
}

fn bool GitStatus.parse(&self, String root, String data)
{
	self.root = root.copy(self.allocator);
	self.valid = true;
	usz pos = 0;
	while (pos < data.len)
	{
		usz end = pos;
		while (end < data.len && data[end] != 0) end++;
		String token = data[pos:end - pos];
		pos = end < data.len ? end + 1 : data.len;
		if (token.len == 0) continue;

		if (token[0] == '#')
		{
			String oid = header_value(token, "branch.oid");
			if (oid.len > 0 && oid.compare_to("(initial)") == 0) self.initial = true;
			String head = header_value(token, "branch.head");
			if (head.len > 0)
			{
				if (head.compare_to("(detached)") == 0)
				{
					self.detached = true;
				}
				else
				{
					if (self.branch.len > 0) self.branch.free(self.allocator);
					self.branch = head.copy(self.allocator);
				}
			}
			String upstream = header_value(token, "branch.upstream");
			if (upstream.len > 0)
			{
				if (self.upstream.len > 0) self.upstream.free(self.allocator);
				self.upstream = upstream.copy(self.allocator);
			}
			String ab = header_value(token, "branch.ab");
			if (ab.len > 0) parse_branch_ab(self, ab);
			continue;
		}

		char kind = token[0];
		if (kind == '1' && token.len >= 4)
		{
			char x      = token[2];
			char y      = token[3];
			String path = after_spaces(token, 8);
			self.add_entry(path, "", state_from_char(x), state_from_char(y), false, false);
			continue;
		}
		if (kind == '2' && token.len >= 4)
		{
			char x      = token[2];
			char y      = token[3];
			String path = after_spaces(token, 9);
			String orig = "";
			if (pos < data.len)
			{
				usz oend = pos;
				while (oend < data.len && data[oend] != 0) oend++;
				orig = data[pos:oend - pos];
				pos = oend < data.len ? oend + 1 : data.len;
			}
			self.add_entry(path, orig, state_from_char(x), state_from_char(y), false, false);
			continue;
		}
		if (kind == 'u' && token.len >= 4)
		{
			String path = after_spaces(token, 10);
			self.add_entry(path, "", GitFileState.CONFLICTED, GitFileState.CONFLICTED, true, false);
			continue;
		}
		if (kind == '?' && token.len > 2)
		{
			String path = token[2:token.len - 2];
			self.add_entry(path, "", GitFileState.UNTRACKED, GitFileState.UNTRACKED, false, true);
			continue;
		}
	}
	return true;
}