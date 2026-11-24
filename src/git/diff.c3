module yun::git;

import std::collections::list;
import std::core::mem::alloc;

enum DiffLineKind : int
{
	CONTEXT,
	ADD,
	DELETE,
	META,
}

struct DiffLine
{
	DiffLineKind kind;
	String text;
	int old_line;
	int new_line;
}

struct DiffHunk
{
	String header;
	int old_start;
	int old_count;
	int new_start;
	int new_count;
	List{DiffLine} lines;
}

struct DiffFile
{
	Allocator allocator;
	bool valid;
	bool binary;
	bool truncated;
	String old_path;
	String new_path;
	List{DiffHunk} hunks;
	int additions;
	int deletions;
}

fn void DiffHunk.init(&self, Allocator allocator)
{
	self.header = "";
	self.old_start = 0;
	self.old_count = 0;
	self.new_start = 0;
	self.new_count = 0;
	self.lines.init(allocator);
}

fn void DiffHunk.destroy(&self, Allocator allocator)
{
	if (self.header.len > 0) self.header.free(allocator);
	for (sz i = 0; i < self.lines.len(); i++)
	{
		if (self.lines[i].text.len > 0) self.lines[i].text.free(allocator);
	}
	self.lines.free();
}

fn void DiffFile.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.valid = false;
	self.binary = false;
	self.truncated = false;
	self.old_path = "";
	self.new_path = "";
	self.hunks.init(allocator);
	self.additions = 0;
	self.deletions = 0;
}

fn void DiffFile.destroy(&self)
{
	for (sz i = 0; i < self.hunks.len(); i++)
	{
		self.hunks[i].destroy(self.allocator);
	}
	self.hunks.free();
	if (self.old_path.len > 0) self.old_path.free(self.allocator);
	if (self.new_path.len > 0) self.new_path.free(self.allocator);
}

fn bool diff_parse_int(String text, usz* pos, int* out)
{
	while (*pos < text.len && text[*pos] == ' ') (*pos)++;
	bool negative = false;
	if (*pos < text.len && text[*pos] == '-')
	{
		negative = true;
		(*pos)++;
	}
	if (*pos >= text.len || text[*pos] < '0' || text[*pos] > '9') return false;
	long value = 0;
	while (*pos < text.len && text[*pos] >= '0' && text[*pos] <= '9')
	{
		value = value * 10 + (long)(text[*pos] - '0');
		(*pos)++;
	}
	*out = negative ? -(int)value : (int)value;
	return true;
}

fn bool diff_parse_range(String text, usz* pos, int* start, int* count)
{
	if (!diff_parse_int(text, pos, start)) return false;
	*count = 1;
	if (*pos < text.len && text[*pos] == ',')
	{
		(*pos)++;
		if (!diff_parse_int(text, pos, count)) return false;
	}
	return true;
}

fn bool diff_parse_hunk_header(String line, DiffHunk* hunk)
{
	if (!line.starts_with("@@ -")) return false;
	usz pos = 4;
	if (!diff_parse_range(line, &pos, &hunk.old_start, &hunk.old_count)) return false;
	while (pos < line.len && line[pos] == ' ') pos++;
	if (pos >= line.len || line[pos] != '+') return false;
	pos++;
	if (!diff_parse_range(line, &pos, &hunk.new_start, &hunk.new_count)) return false;
	return true;
}

fn String strip_line_eol(String line)
{
	usz len = line.len;
	if (len > 0 && line[len - 1] == '\r') len--;
	return line[0:len];
}

fn bool DiffFile.parse(&self, String output)
{
	self.valid = true;
	if (output.len == 0) return true;
	if (contains_ci(output, "binary files") || output.starts_with("GIT binary patch")) self.binary = true;

	usz pos        = 0;
	DiffHunk* hunk = null;
	int old_line   = 0;
	int new_line   = 0;
	while (pos < output.len)
	{
		usz end = pos;
		while (end < output.len && output[end] != '\n') end++;
		String raw = output[pos:end - pos];
		pos = end < output.len ? end + 1 : output.len;
		String line = strip_line_eol(raw);

		if (line.starts_with("diff --git "))
		{
			hunk = null;
			continue;
		}
		if (line.starts_with("--- "))
		{
			if (self.old_path.len > 0) self.old_path.free(self.allocator);
			self.old_path = line.len > 4 ? line[4:line.len - 4].copy(self.allocator) : "";
			continue;
		}
		if (line.starts_with("+++ "))
		{
			if (self.new_path.len > 0) self.new_path.free(self.allocator);
			self.new_path = line.len > 4 ? line[4:line.len - 4].copy(self.allocator) : "";
			continue;
		}
		if (line.starts_with("@@ "))
		{
			DiffHunk created;
			created.init(self.allocator);
			if (!diff_parse_hunk_header(line, &created))
			{
				created.destroy(self.allocator);
				continue;
			}
			created.header = line.copy(self.allocator);
			self.hunks.push(created);
			hunk = &self.hunks[self.hunks.len() - 1];
			old_line = created.old_start;
			new_line = created.new_start;
			continue;
		}
		if (!hunk) continue;
		if (line.starts_with("\\ No newline"))
		{
			DiffLine meta = { .kind = DiffLineKind.META, .text = line.copy(self.allocator) };
			hunk.lines.push(meta);
			continue;
		}
		if (line.len == 0) continue;
		char prefix = line[0];
		String text = line.len > 1 ? line[1:line.len - 1].copy(self.allocator) : "";
		DiffLine diff_line;
		diff_line.text = text;
		diff_line.old_line = 0;
		diff_line.new_line = 0;
		switch (prefix)
		{
			case ' ':
				diff_line.kind = DiffLineKind.CONTEXT;
				diff_line.old_line = old_line++;
				diff_line.new_line = new_line++;
			case '+':
				diff_line.kind = DiffLineKind.ADD;
				diff_line.new_line = new_line++;
				self.additions++;
			case '-':
				diff_line.kind = DiffLineKind.DELETE;
				diff_line.old_line = old_line++;
				self.deletions++;
			case '\\':
				diff_line.kind = DiffLineKind.META;
				if (diff_line.text.len > 0) diff_line.text.free(self.allocator);
				diff_line.text = line.copy(self.allocator);
			default:
				diff_line.kind = DiffLineKind.META;
				if (diff_line.text.len > 0) diff_line.text.free(self.allocator);
				diff_line.text = line.copy(self.allocator);
		}
		hunk.lines.push(diff_line);
	}
	return true;
}