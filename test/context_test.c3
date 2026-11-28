module yun::context @test;

import yun::commands;

fn void test_card_items()
{
	ContextItem[CONTEXT_MAX_ITEMS] items;

	usz count = build(ContextTarget.CARD, true, false, true, true, false, false, false, items[0:CONTEXT_MAX_ITEMS]);
	assert(count == 9);
	assert(items[0].action == ContextAction.TOGGLE_CARD);
	assert(items[0].label.compare_to("Close") == 0);
	assert(items[1].action == ContextAction.RENAME_CARD);
	assert(items[1].enabled);
	assert(items[4].action == ContextAction.MINIMIZE_CARD);
	assert(items[4].enabled);
	assert(items[5].action == ContextAction.DELETE_CARD);
	assert(items[5].enabled);
	assert(items[6].action == ContextAction.GO_TO_DEFINITION);
	assert(items[6].enabled);
	assert(items[7].action == ContextAction.REFERENCES);
	assert(items[8].action == ContextAction.CODE_ACTIONS);

	usz closed = build(ContextTarget.CARD, false, true, true, false, false, false, false, items[0:CONTEXT_MAX_ITEMS]);
	assert(closed == 9);
	assert(items[0].label.compare_to("Open") == 0);
	assert(!items[1].enabled);
	assert(!items[4].enabled);
	assert(items[3].action == ContextAction.COPY_PATH);
	assert(items[3].enabled);
	assert(!items[5].enabled);
	assert(!items[6].enabled);
}

fn void test_cluster_and_canvas_items()
{
	ContextItem[CONTEXT_MAX_ITEMS] items;

	usz cluster = build(
		ContextTarget.CLUSTER,
		false,
		false,
		true,
		false,
		false,
		false,
		false,
		items[0:CONTEXT_MAX_ITEMS]
	);
	assert(cluster == 2);
	assert(items[0].action == ContextAction.NEW_FILE);
	assert(items[0].enabled);
	assert(items[1].action == ContextAction.NEW_FOLDER);

	usz canvas = build(
		ContextTarget.CANVAS,
		false,
		false,
		false,
		false,
		false,
		false,
		false,
		items[0:CONTEXT_MAX_ITEMS]
	);
	assert(canvas == 3);
	assert(items[0].action == ContextAction.NEW_FILE);
	assert(!items[0].enabled);
	assert(items[2].action == ContextAction.OPEN_PROJECT);
	assert(items[2].enabled);
}

fn void test_command_mapping()
{
	assert(command_for(ContextAction.NEW_FILE) == (int)commands::CommandId.NEW_FILE);
	assert(command_for(ContextAction.NEW_FOLDER) == (int)commands::CommandId.NEW_FOLDER);
	assert(command_for(ContextAction.OPEN_PROJECT) == (int)commands::CommandId.OPEN);
	assert(command_for(ContextAction.GO_TO_DEFINITION) == (int)commands::CommandId.GO_TO_DEFINITION);
	assert(command_for(ContextAction.DELETE_CARD) == (int)commands::CommandId.DELETE_CARD);
	assert(command_for(ContextAction.MINIMIZE_CARD) == (int)commands::CommandId.MINIMIZE_CARD);
	assert(command_for(ContextAction.COPY_PATH) == (int)commands::CommandId.COPY_PATH);
	assert(command_for(ContextAction.TOGGLE_CARD) == (int)commands::CommandId.TOGGLE_CARD);
	assert(command_for(ContextAction.RENAME_CARD) == (int)commands::CommandId.RENAME_CARD);
	assert(command_for(ContextAction.DUPLICATE_CARD) == (int)commands::CommandId.DUPLICATE_CARD);
}
fn void test_editor_items_and_focus_exit()
{
	ContextItem[CONTEXT_MAX_ITEMS] items;
	usz count = build(ContextTarget.CARD, true, false, true, true, true, true, false, items[0:CONTEXT_MAX_ITEMS]);
	assert(count == 18);
	assert(items[9].action == ContextAction.UNDO);
	assert(items[11].action == ContextAction.CUT);
	assert(items[11].enabled);
	assert(items[12].action == ContextAction.COPY);
	assert(items[12].enabled);
	assert(items[13].action == ContextAction.PASTE);
	assert(items[17].action == ContextAction.SAVE);
	assert(command_for(ContextAction.CUT) == (int)commands::CommandId.CUT);
	assert(command_for(ContextAction.PASTE) == (int)commands::CommandId.PASTE);
	assert(command_for(ContextAction.FIND) == (int)commands::CommandId.FIND);
	assert(command_for(ContextAction.SAVE) == (int)commands::CommandId.SAVE);

	usz focus = build(ContextTarget.CARD, true, false, true, true, true, false, true, items[0:CONTEXT_MAX_ITEMS]);
	assert(focus == 19);
	assert(items[18].action == ContextAction.EXIT_FOCUS);
	assert(command_for(ContextAction.EXIT_FOCUS) == (int)commands::CommandId.TOGGLE_FOCUS_MODE);
}