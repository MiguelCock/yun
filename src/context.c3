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
	NEW_FILE,
	NEW_FOLDER,
	OPEN_PROJECT,
	GO_TO_DEFINITION,
}

struct ContextItem
{
	String label;
	ContextAction action;
	bool enabled;
}

const int CONTEXT_MAX_ITEMS = 8;

fn usz build(
	ContextTarget target,
	bool card_open,
	bool card_missing,
	bool has_project,
	bool can_define,
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
			out[count] = { .label = "Delete", .action = ContextAction.DELETE_CARD, .enabled = !card_missing };
			count++;
			out[count] = {
				.label = "Go to Definition",
				.action = ContextAction.GO_TO_DEFINITION,
				.enabled = can_define,
			};
			count++;
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
		default:
			return -1;
	}
}