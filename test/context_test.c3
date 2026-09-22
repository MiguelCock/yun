module yun::context @test;

import yun::commands;

fn void test_card_items()
{
	ContextItem[CONTEXT_MAX_ITEMS] items;

	usz count = build(ContextTarget.CARD, true, false, true, items[0:CONTEXT_MAX_ITEMS]);
	assert(count == 5);
	assert(items[0].action == ContextAction.TOGGLE_CARD);
	assert(items[0].label.compare_to("Close") == 0);
	assert(items[1].action == ContextAction.RENAME_CARD);
	assert(items[1].enabled);
	assert(items[4].action == ContextAction.DELETE_CARD);
	assert(items[4].enabled);

	usz closed = build(ContextTarget.CARD, false, true, true, items[0:CONTEXT_MAX_ITEMS]);
	assert(closed == 5);
	assert(items[0].label.compare_to("Open") == 0);
	assert(!items[1].enabled);
	assert(!items[4].enabled);
	assert(items[3].action == ContextAction.COPY_PATH);
	assert(items[3].enabled);
}

fn void test_cluster_and_canvas_items()
{
	ContextItem[CONTEXT_MAX_ITEMS] items;

	usz cluster = build(ContextTarget.CLUSTER, false, false, true, items[0:CONTEXT_MAX_ITEMS]);
	assert(cluster == 2);
	assert(items[0].action == ContextAction.NEW_FILE);
	assert(items[0].enabled);
	assert(items[1].action == ContextAction.NEW_FOLDER);

	usz canvas = build(ContextTarget.CANVAS, false, false, false, items[0:CONTEXT_MAX_ITEMS]);
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
	assert(command_for(ContextAction.DELETE_CARD) == -1);
	assert(command_for(ContextAction.COPY_PATH) == -1);
}