module yun::commands;

enum CommandId
{
	NEW_FILE,
	NEW_FOLDER,
	OPEN,
	SAVE,
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
};

fn usz command_count()
{
	return COMMAND_DEFS.len;
}

fn CommandDef command_def(CommandId id)
{
	return COMMAND_DEFS[(int)id];
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