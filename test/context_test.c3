module yun::context @test;

import yun::commands;

fn void test_card_items()
{
	ContextItem[CONTEXT_MAX_ITEMS] items;

	usz count = build(ContextTarget.CARD, true, false, true, true, items[0:CONTEXT_MAX_ITEMS]);
	assert(count == 6);
	assert(items[0].action == ContextAction.TOGGLE_CARD);
	assert(items[0].label.compare_to("Close") == 0);
	assert(items[1].action == ContextAction.RENAME_CARD);
	assert(items[1].enabled);
	assert(items[4].action == ContextAction.DELETE_CARD);
	assert(items[4].enabled);
	assert(items[5].action == ContextAction.GO_TO_DEFINITION);
	assert(items[5].enabled);

	usz closed = build(ContextTarget.CARD, false, true, true, false, items[0:CONTEXT_MAX_ITEMS]);
	assert(closed == 6);
	assert(items[0].label.compare_to("Open") == 0);
	assert(!items[1].enabled);
	assert(!items[4].enabled);
	assert(items[3].action == ContextAction.COPY_PATH);
	assert(items[3].enabled);
	assert(!items[5].enabled);
}

fn void test_cluster_and_canvas_items()
{
	ContextItem[CONTEXT_MAX_ITEMS] items;

	usz cluster = build(ContextTarget.CLUSTER, false, false, true, false, items[0:CONTEXT_MAX_ITEMS]);
	assert(cluster == 2);
	assert(items[0].action == ContextAction.NEW_FILE);
	assert(items[0].enabled);
	assert(items[1].action == ContextAction.NEW_FOLDER);

	usz canvas = build(ContextTarget.CANVAS, false, false, false, false, items[0:CONTEXT_MAX_ITEMS]);
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
	assert(command_for(ContextAction.COPY_PATH) == (int)commands::CommandId.COPY_PATH);
	assert(command_for(ContextAction.TOGGLE_CARD) == (int)commands::CommandId.TOGGLE_CARD);
	assert(command_for(ContextAction.RENAME_CARD) == (int)commands::CommandId.RENAME_CARD);
	assert(command_for(ContextAction.DUPLICATE_CARD) == (int)commands::CommandId.DUPLICATE_CARD);
}