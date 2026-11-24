module yun::git;

import std::collections::list;
import std::core::mem::alloc;

fn bool parse_branches(Allocator allocator, String data, List{GitBranch}* out)
{
	usz pos = 0;
	while (pos < data.len)
	{
		usz line_end = pos;
		while (line_end < data.len && data[line_end] != '\n') line_end++;
		String line = data[pos:line_end - pos];
		pos = line_end < data.len ? line_end + 1 : data.len;
		if (line.len == 0) continue;

		usz first_end = 0;
		while (first_end < line.len && line[first_end] != 0) first_end++;
		String name = line[0:first_end];
		if (name.len == 0) continue;

		bool current    = false;
		String upstream = "";
		if (first_end < line.len)
		{
			usz second_start = first_end + 1;
			usz second_end   = second_start;
			while (second_end < line.len && line[second_end] != 0) second_end++;
			String head = line[second_start:second_end - second_start];
			current = head.len > 0 && head[0] == '*';
			if (second_end < line.len)
			{
				usz third_start = second_end + 1;
				usz third_end   = third_start;
				while (third_end < line.len && line[third_end] != 0) third_end++;
				upstream = line[third_start:third_end - third_start];
			}
		}
		out.push(
			{
				.name = name.copy(allocator),
				.upstream = upstream.len > 0 ? upstream.copy(allocator) : "",
				.current = current,
			}
		);
	}
	return true;
}

fn String[] git_branch_list_argv(Allocator allocator, String binary, String root)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("--no-pager");
		list.push("-C");
		list.push(root);
		list.push("for-each-ref");
		list.push("--format=%(refname:short)%00%(HEAD)%00%(upstream:short)");
		list.push("refs/heads");
		return finish_argv(allocator, &list);
	};
}

fn String[] git_branch_switch_argv(Allocator allocator, String binary, String root, String name)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-C");
		list.push(root);
		list.push("switch");
		list.push("--");
		list.push(name);
		return finish_argv(allocator, &list);
	};
}

fn String[] git_branch_create_argv(Allocator allocator, String binary, String root, String name)
{
	@pool()
	{
		List{String} list;
		list.init(tmem);
		list.push(binary);
		list.push("-C");
		list.push(root);
		list.push("switch");
		list.push("-c");
		list.push(name);
		return finish_argv(allocator, &list);
	};
}