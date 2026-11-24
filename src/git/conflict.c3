module yun::git;

import std::collections::list;
import std::core::dstring;
import std::core::mem::alloc;

enum ConflictChoice : int
{
	UNSET,
	CURRENT,
	INCOMING,
	BOTH,
}

struct ConflictBlock
{
	usz start;
	usz end;
	int ours_line;
	int theirs_line;
	String ours;
	String base;
	String theirs;
	String ours_label;
	String theirs_label;
}

fn int line_number_at(String content, usz pos)
{
	int line = 1;
	for (usz i = 0; i < pos && i < content.len; i++)
	{
		if (content[i] == '\n') line++;
	}
	return line;
}

fn String trim_marker_label(String line)
{
	usz start = 7;
	while (start < line.len && (line[start] == ' ' || line[start] == '\t')) start++;
	usz end = line.len;
	while (end > start && (line[end - 1] == '\r' || line[end - 1] == '\n')) end--;
	return line[start:end - start];
}

fn bool line_starts(String content, usz pos, String prefix)
{
	if (pos + prefix.len > content.len) return false;
	for (usz i = 0; i < prefix.len; i++)
	{
		if (content[pos + i] != prefix[i]) return false;
	}
	return true;
}

fn usz line_after(String content, usz pos)
{
	while (pos < content.len && content[pos] != '\n') pos++;
	return pos < content.len ? pos + 1 : content.len;
}

fn void ConflictBlock.destroy(&self, Allocator allocator)
{
	if (self.ours.len > 0) self.ours.free(allocator);
	if (self.base.len > 0) self.base.free(allocator);
	if (self.theirs.len > 0) self.theirs.free(allocator);
	if (self.ours_label.len > 0) self.ours_label.free(allocator);
	if (self.theirs_label.len > 0) self.theirs_label.free(allocator);
}

fn bool parse_conflicts(Allocator allocator, String content, List{ConflictBlock}* out)
{
	usz pos = 0;
	while (pos < content.len)
	{
		if (!line_starts(content, pos, "<<<<<<<"))
		{
			pos = line_after(content, pos);
			continue;
		}
		usz block_start   = pos;
		usz marker_end    = line_after(content, pos);
		String ours_label = trim_marker_label(content[pos:marker_end - pos]);
		usz ours_start    = marker_end;
		usz ours_end      = ours_start;
		usz base_start    = 0;
		usz base_end      = 0;
		bool has_base     = false;
		usz theirs_start  = 0;
		bool closed       = false;
		usz scan          = marker_end;
		while (scan < content.len)
		{
			if (line_starts(content, scan, "|||||||") && !has_base)
			{
				ours_end = scan;
				has_base = true;
				base_start = line_after(content, scan);
				base_end = base_start;
				scan = base_start;
				continue;
			}
			if (line_starts(content, scan, "======="))
			{
				if (!has_base)
				{
					ours_end = scan;
				}
				else
				{
					base_end = scan;
				}
				theirs_start = line_after(content, scan);
				scan = theirs_start;
				continue;
			}
			if (line_starts(content, scan, ">>>>>>>"))
			{
				usz block_end = line_after(content, scan);
				ConflictBlock block;
				block.start = block_start;
				block.end = block_end;
				block.ours_line = line_number_at(content, ours_start);
				block.theirs_line = line_number_at(content, theirs_start);
				block.ours = content[ours_start:ours_end - ours_start].copy(allocator);
				block.base = has_base ? content[base_start:base_end - base_start].copy(allocator) : "";
				block.theirs = content[theirs_start:scan - theirs_start].copy(allocator);
				block.ours_label = ours_label.len > 0 ? ours_label.copy(allocator) : "Current".copy(allocator);
				String theirs_line = content[scan:block_end - scan];
				block.theirs_label = trim_marker_label(theirs_line);
				if (block.theirs_label.len == 0)
				{
					block.theirs_label = "Incoming".copy(allocator);
				}
				else
				{
					block.theirs_label = block.theirs_label.copy(allocator);
				}
				out.push(block);
				pos = block_end;
				closed = true;
				break;
			}
			scan = line_after(content, scan);
		}
		if (!closed) break;
	}
	return out.len() > 0;
}

fn bool resolve_conflicts(
	Allocator allocator,
	String content,
	List{ConflictBlock}* blocks,
	List{ConflictChoice}* choices,
	String* out
)
{
	if (blocks.len() != choices.len()) return false;
	for (sz i = 0; i < choices.len(); i++)
	{
		if (choices.get(i) == ConflictChoice.UNSET) return false;
	}
	DString result;
	result.init(allocator);
	usz pos = 0;
	for (sz i = 0; i < blocks.len(); i++)
	{
		ConflictBlock* block = blocks.get_ref(i);
		if (block.start < pos || block.end > content.len) return false;
		result.append_string(content[pos:block.start - pos]);
		switch (choices.get(i))
		{
			case ConflictChoice.CURRENT:
				result.append_string(block.ours);
			case ConflictChoice.INCOMING:
				result.append_string(block.theirs);
			case ConflictChoice.BOTH:
				result.append_string(block.ours);
				result.append_string(block.theirs);
			case ConflictChoice.UNSET:
				break;
		}
		pos = block.end;
	}
	result.append_string(content[pos:content.len - pos]);
	*out = result.copy_str(allocator);
	result.free();
	return true;
}