module yun::git;

import std::core::dstring;

fn String build_hunk_patch(Allocator allocator, DiffFile* diff, int hunk_index, String path)
{
	if (hunk_index < 0 || hunk_index >= (int)diff.hunks.len()) return "";
	DiffHunk* hunk = &diff.hunks[hunk_index];
	if (hunk.lines.len() == 0) return "";
	DString out;
	out.init(allocator);
	@pool()
	{
		String old_path = diff.old_path.len > 0 ? diff.old_path : string::format(tmem, "a/%s", path);
		String new_path = diff.new_path.len > 0 ? diff.new_path : string::format(tmem, "b/%s", path);
		if (old_path.compare_to("/dev/null") == 0 || new_path.compare_to("/dev/null") == 0)
		{
			out.free();
			return "";
		}
		String header = string::format(tmem, "diff --git a/%s b/%s\n--- %s\n+++ %s\n", path, path, old_path, new_path);
		out.append_string(header);
	};
	out.append_string(hunk.header);
	out.append_char('\n');
	for (sz i = 0; i < hunk.lines.len(); i++)
	{
		DiffLine* line = &hunk.lines[i];
		switch (line.kind)
		{
			case DiffLineKind.CONTEXT:
				out.append_char(' ');
			case DiffLineKind.ADD:
				out.append_char('+');
			case DiffLineKind.DELETE:
				out.append_char('-');
			case DiffLineKind.META:
				break;
		}
		out.append_string(line.text);
		out.append_char('\n');
	}
	String result = out.copy_str(allocator);
	out.free();
	return result;
}