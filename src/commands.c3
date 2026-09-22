module yun::commands;

enum CommandId
{
	NEW_FILE,
	OPEN,
	SAVE,
}

struct CommandDef
{
	CommandId id;
	String label;
	String shortcut;
}

const CommandDef[] COMMAND_DEFS = {
	{ .id = CommandId.NEW_FILE, .label = "New", .shortcut = "Ctrl+N" },
	{ .id = CommandId.OPEN, .label = "Open", .shortcut = "Ctrl+O" },
	{ .id = CommandId.SAVE, .label = "Save", .shortcut = "Ctrl+S" },
};

fn usz command_count()
{
	return COMMAND_DEFS.len;
}

fn CommandDef command_def(CommandId id)
{
	return COMMAND_DEFS[(int)id];
}

fn bool command_enabled(CommandId id, bool has_project, bool has_buffer)
{
	switch (id)
	{
		case CommandId.NEW_FILE:
			return has_project;
		case CommandId.OPEN:
			return true;
		case CommandId.SAVE:
			return has_buffer;
	}
}