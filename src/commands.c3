module yun::commands;

enum CommandId
{
	NEW_FILE,
	NEW_FOLDER,
	OPEN,
	SAVE,
	SHOW_PALETTE,
	FIND,
	REPLACE,
	COPY,
	CUT,
	PASTE,
	SELECT_ALL,
	PROBLEMS,
}

struct CommandDef
{
	CommandId id;
	String label;
	String shortcut;
	bool in_top_bar;
}

const CommandDef[] COMMAND_DEFS = {
	{ .id = CommandId.NEW_FILE, .label = "New", .shortcut = "Ctrl+N", .in_top_bar = true },
	{ .id = CommandId.NEW_FOLDER, .label = "New Folder", .shortcut = "", .in_top_bar = false },
	{ .id = CommandId.OPEN, .label = "Open", .shortcut = "Ctrl+O", .in_top_bar = true },
	{ .id = CommandId.SAVE, .label = "Save", .shortcut = "Ctrl+S", .in_top_bar = true },
	{ .id = CommandId.SHOW_PALETTE, .label = "Command Palette", .shortcut = "Ctrl+Shift+P", .in_top_bar = false },
	{ .id = CommandId.FIND, .label = "Find", .shortcut = "Ctrl+F", .in_top_bar = false },
	{ .id = CommandId.REPLACE, .label = "Replace", .shortcut = "Ctrl+H", .in_top_bar = false },
	{ .id = CommandId.COPY, .label = "Copy", .shortcut = "Ctrl+C", .in_top_bar = false },
	{ .id = CommandId.CUT, .label = "Cut", .shortcut = "Ctrl+X", .in_top_bar = false },
	{ .id = CommandId.PASTE, .label = "Paste", .shortcut = "Ctrl+V", .in_top_bar = false },
	{ .id = CommandId.SELECT_ALL, .label = "Select All", .shortcut = "Ctrl+A", .in_top_bar = false },
	{ .id = CommandId.PROBLEMS, .label = "Problems", .shortcut = "Ctrl+Shift+M", .in_top_bar = false },
};

fn usz command_count()
{
	return COMMAND_DEFS.len;
}

fn CommandDef command_def(CommandId id)
{
	return COMMAND_DEFS[(int)id];
}

fn String command_name(CommandId id)
{
	switch (id)
	{
		case CommandId.NEW_FILE:
			return "new_file";
		case CommandId.NEW_FOLDER:
			return "new_folder";
		case CommandId.OPEN:
			return "open";
		case CommandId.SAVE:
			return "save";
		case CommandId.SHOW_PALETTE:
			return "show_palette";
		case CommandId.FIND:
			return "find";
		case CommandId.REPLACE:
			return "replace";
		case CommandId.COPY:
			return "copy";
		case CommandId.CUT:
			return "cut";
		case CommandId.PASTE:
			return "paste";
		case CommandId.SELECT_ALL:
			return "select_all";
		case CommandId.PROBLEMS:
			return "problems";
	}
}

fn int command_from_name(String name)
{
	for (usz i = 0; i < command_count(); i++)
	{
		if (command_name((CommandId)i).compare_to(name) == 0) return (int)i;
	}
	return -1;
}

fn usz bar_command_count()
{
	usz count = 0;
	foreach (CommandDef def : COMMAND_DEFS)
	{
		if (def.in_top_bar) count++;
	}
	return count;
}

fn CommandDef bar_command(usz slot)
{
	usz seen = 0;
	foreach (CommandDef def : COMMAND_DEFS)
	{
		if (!def.in_top_bar) continue;
		if (seen == slot) return def;
		seen++;
	}
	return COMMAND_DEFS[0];
}

fn bool command_enabled(CommandId id, bool has_project, bool has_buffer)
{
	switch (id)
	{
		case CommandId.NEW_FILE:
			return has_project;
		case CommandId.NEW_FOLDER:
			return has_project;
		case CommandId.OPEN:
			return true;
		case CommandId.SAVE:
			return has_buffer;
		case CommandId.SHOW_PALETTE:
			return true;
		case CommandId.FIND:
			return has_buffer;
		case CommandId.REPLACE:
			return has_buffer;
		case CommandId.COPY:
			return has_buffer;
		case CommandId.CUT:
			return has_buffer;
		case CommandId.PASTE:
			return has_buffer;
		case CommandId.SELECT_ALL:
			return has_buffer;
		case CommandId.PROBLEMS:
			return true;
	}
}

fn char lower_ascii(char c)
{
	if (c >= 'A' && c <= 'Z') return (char)(c + 32);
	return c;
}

fn int fuzzy_match(String haystack, String needle, usz[] positions)
{
	if (needle.len == 0) return 0;
	if (needle.len > positions.len) return -1;

	usz at    =  0;
	int score =  0;
	sz prev   = -1;
	for (usz n = 0; n < needle.len; n++)
	{
		char want  = lower_ascii(needle[n]);
		bool found = false;
		while (at < haystack.len)
		{
			char c = lower_ascii(haystack[at]);
			if (c == want)
			{
				positions[n] = at;
				score += 1;
				if (prev >= 0 && (usz)(prev + 1) == at)
				{
					score += 8;
				}
				else if (at == 0 || haystack[at - 1] == ' ' || haystack[at - 1] == '_' || haystack[at - 1] == '-'
					|| haystack[at - 1] == '/')
				{
					score += 12;
				}
				prev = (sz)at;
				at++;
				found = true;
				break;
			}
			at++;
		}
		if (!found) return -1;
	}
	return score;
}