module yun::context;

import yun::commands;

enum ContextTarget
{
	CARD,
	CLUSTER,
	CANVAS,
}

enum ContextAction
{
	TOGGLE_CARD,
	RENAME_CARD,
	DUPLICATE_CARD,
	COPY_PATH,
	DELETE_CARD,
	MINIMIZE_CARD,
	UNDO,
	REDO,
	CUT,
	COPY,
	PASTE,
	SELECT_ALL,
	FIND,
	REPLACE,
	SAVE,
	EXIT_FOCUS,
	NEW_FILE,
	NEW_FOLDER,
	OPEN_PROJECT,
	GO_TO_DEFINITION,
	REFERENCES,
	CODE_ACTIONS,
	MOD_ITEM,
}

struct ContextItem
{
	String label;
	ContextAction action;
	bool enabled;
	int index;
}

const int CONTEXT_MAX_ITEMS = 32;

fn usz build(
	ContextTarget target,
	bool card_open,
	bool card_missing,
	bool has_project,
	bool can_define,
	bool editing,
	bool has_selection,
	bool focus_mode,
	ContextItem[] out
)
{
	usz count = 0;
	switch (target)
	{
		case ContextTarget.CARD:
			out[count] = {
				.label = card_open ? "Close" : "Open",
				.action = ContextAction.TOGGLE_CARD,
				.enabled = true,
			};
			count++;
			out[count] = { .label = "Rename", .action = ContextAction.RENAME_CARD, .enabled = !card_missing };
			count++;
			out[count] = { .label = "Duplicate", .action = ContextAction.DUPLICATE_CARD, .enabled = !card_missing };
			count++;
			out[count] = { .label = "Copy Path", .action = ContextAction.COPY_PATH, .enabled = true };
			count++;
			out[count] = { .label = "Minimize", .action = ContextAction.MINIMIZE_CARD, .enabled = !card_missing };
			count++;
			out[count] = { .label = "Delete", .action = ContextAction.DELETE_CARD, .enabled = !card_missing };
			count++;
			out[count] = {
				.label = "Go to Definition",
				.action = ContextAction.GO_TO_DEFINITION,
				.enabled = can_define,
			};
			count++;
			out[count] = {
				.label = "Find References",
				.action = ContextAction.REFERENCES,
				.enabled = can_define,
			};
			count++;
			out[count] = {
				.label = "Code Actions",
				.action = ContextAction.CODE_ACTIONS,
				.enabled = can_define,
			};
			count++;
			if (editing)
			{
				out[count] = { .label = "Undo", .action = ContextAction.UNDO, .enabled = true };
				count++;
				out[count] = { .label = "Redo", .action = ContextAction.REDO, .enabled = true };
				count++;
				out[count] = { .label = "Cut", .action = ContextAction.CUT, .enabled = has_selection };
				count++;
				out[count] = { .label = "Copy", .action = ContextAction.COPY, .enabled = has_selection };
				count++;
				out[count] = { .label = "Paste", .action = ContextAction.PASTE, .enabled = true };
				count++;
				out[count] = { .label = "Select All", .action = ContextAction.SELECT_ALL, .enabled = true };
				count++;
				out[count] = { .label = "Find", .action = ContextAction.FIND, .enabled = true };
				count++;
				out[count] = { .label = "Replace", .action = ContextAction.REPLACE, .enabled = true };
				count++;
				out[count] = { .label = "Save", .action = ContextAction.SAVE, .enabled = true };
				count++;
				if (focus_mode)
				{
					out[count] = { .label = "Exit Focus", .action = ContextAction.EXIT_FOCUS, .enabled = true };
					count++;
				}
			}
			break;
		case ContextTarget.CLUSTER:
			out[count] = { .label = "New File", .action = ContextAction.NEW_FILE, .enabled = has_project };
			count++;
			out[count] = { .label = "New Folder", .action = ContextAction.NEW_FOLDER, .enabled = has_project };
			count++;
			break;
		case ContextTarget.CANVAS:
			out[count] = { .label = "New File", .action = ContextAction.NEW_FILE, .enabled = has_project };
			count++;
			out[count] = { .label = "New Folder", .action = ContextAction.NEW_FOLDER, .enabled = has_project };
			count++;
			out[count] = { .label = "Open Project", .action = ContextAction.OPEN_PROJECT, .enabled = true };
			count++;
			break;
	}
	return count;
}

fn int command_for(ContextAction action)
{
	switch (action)
	{
		case ContextAction.NEW_FILE:
			return (int)commands::CommandId.NEW_FILE;
		case ContextAction.NEW_FOLDER:
			return (int)commands::CommandId.NEW_FOLDER;
		case ContextAction.OPEN_PROJECT:
			return (int)commands::CommandId.OPEN;
		case ContextAction.GO_TO_DEFINITION:
			return (int)commands::CommandId.GO_TO_DEFINITION;
		case ContextAction.REFERENCES:
			return (int)commands::CommandId.REFERENCES;
		case ContextAction.CODE_ACTIONS:
			return (int)commands::CommandId.CODE_ACTIONS;
		case ContextAction.TOGGLE_CARD:
			return (int)commands::CommandId.TOGGLE_CARD;
		case ContextAction.RENAME_CARD:
			return (int)commands::CommandId.RENAME_CARD;
		case ContextAction.DUPLICATE_CARD:
			return (int)commands::CommandId.DUPLICATE_CARD;
		case ContextAction.COPY_PATH:
			return (int)commands::CommandId.COPY_PATH;
		case ContextAction.DELETE_CARD:
			return (int)commands::CommandId.DELETE_CARD;
		case ContextAction.MINIMIZE_CARD:
			return (int)commands::CommandId.MINIMIZE_CARD;
		case ContextAction.UNDO:
			return (int)commands::CommandId.UNDO;
		case ContextAction.REDO:
			return (int)commands::CommandId.REDO;
		case ContextAction.CUT:
			return (int)commands::CommandId.CUT;
		case ContextAction.COPY:
			return (int)commands::CommandId.COPY;
		case ContextAction.PASTE:
			return (int)commands::CommandId.PASTE;
		case ContextAction.SELECT_ALL:
			return (int)commands::CommandId.SELECT_ALL;
		case ContextAction.FIND:
			return (int)commands::CommandId.FIND;
		case ContextAction.REPLACE:
			return (int)commands::CommandId.REPLACE;
		case ContextAction.SAVE:
			return (int)commands::CommandId.SAVE;
		case ContextAction.EXIT_FOCUS:
			return (int)commands::CommandId.TOGGLE_FOCUS_MODE;
		case ContextAction.MOD_ITEM:
			return -1;
		default:
			return -1;
	}
}