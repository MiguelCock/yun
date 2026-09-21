module yun::minimap;

import raylib6::rl;
import std::math;
import yun::canvas;
import yun::project;

const int MINIMAP_WIDTH            = 220;
const int MINIMAP_HEIGHT           = 160;
const int MINIMAP_MARGIN           = 16;
const float MINIMAP_ZOOM_THRESHOLD = 0.4f;
const RLColor MINIMAP_BG           = { 18, 20, 26, 230 };
const RLColor MINIMAP_BORDER       = { 80, 96, 130, 255 };
const RLColor MINIMAP_CLUSTER      = { 60, 80, 120, 200 };
const RLColor MINIMAP_CARD         = { 150, 170, 210, 255 };
const RLColor MINIMAP_VIEWPORT     = { 240, 240, 240, 255 };

fn Rect minimap_panel(int screen_w, int screen_h)
{
	return {
		.x = (float)(screen_w - MINIMAP_WIDTH - MINIMAP_MARGIN),
		.y = (float)(screen_h - MINIMAP_HEIGHT - MINIMAP_MARGIN),
		.width = (float)MINIMAP_WIDTH,
		.height = (float)MINIMAP_HEIGHT,
	};
}

fn float minimap_scale(Rect content, Rect panel)
{
	if (content.width <= 0.0f || content.height <= 0.0f) return 1.0f;
	return math::min(panel.width / content.width, panel.height / content.height);
}

fn float minimap_offset_x(Rect content, Rect panel, float scale)
{
	return panel.x + (panel.width - content.width * scale) / 2.0f - content.x * scale;
}

fn float minimap_offset_y(Rect content, Rect panel, float scale)
{
	return panel.y + (panel.height - content.height * scale) / 2.0f - content.y * scale;
}

fn RLVector2 world_to_minimap(RLVector2 world, Rect content, Rect panel)
{
	float scale = minimap_scale(content, panel);
	float off_x = minimap_offset_x(content, panel, scale);
	float off_y = minimap_offset_y(content, panel, scale);
	return { off_x + world[0] * scale, off_y + world[1] * scale };
}

fn RLVector2 minimap_to_world(RLVector2 point, Rect content, Rect panel)
{
	float scale = minimap_scale(content, panel);
	if (scale <= 0.0f) return { content.x, content.y };
	float off_x = minimap_offset_x(content, panel, scale);
	float off_y = minimap_offset_y(content, panel, scale);
	return { (point[0] - off_x) / scale, (point[1] - off_y) / scale };
}

fn bool visible(project::Project* project, canvas::Canvas* canvas)
{
	if (canvas.camera.zoom >= MINIMAP_ZOOM_THRESHOLD) return false;
	Rect bounds;
	return project.content_bounds(&bounds);
}

fn bool contains_screen(project::Project* project, canvas::Canvas* canvas, RLVector2 screen)
{
	if (!visible(project, canvas)) return false;
	Rect panel = minimap_panel(rl::get_screen_width(), rl::get_screen_height());
	return screen[0] >= panel.x && screen[0] <= panel.x + panel.width && screen[1] >= panel.y
		&& screen[1] <= panel.y + panel.height;
}

fn void update(project::Project* project, canvas::Canvas* canvas)
{
	if (!visible(project, canvas)) return;
	RLVector2 mouse = rl::get_mouse_position();
	if (!contains_screen(project, canvas, mouse)) return;
	if (!rl::is_mouse_button_down(rl::RLMouseButton.LEFT)) return;

	Rect content;
	if (!project.content_bounds(&content)) return;
	Rect panel = minimap_panel(rl::get_screen_width(), rl::get_screen_height());
	canvas.target.target = minimap_to_world(mouse, content, panel);
}

fn Rect to_minimap_rect(Rect world, Rect content, Rect panel)
{
	RLVector2 tl = world_to_minimap({ world.x, world.y }, content, panel);
	RLVector2 br = world_to_minimap({ world.x + world.width, world.y + world.height }, content, panel);
	return { .x = tl[0], .y = tl[1], .width = br[0] - tl[0], .height = br[1] - tl[1] };
}

fn void draw(project::Project* project, canvas::Canvas* canvas)
{
	if (!visible(project, canvas)) return;
	Rect content;
	if (!project.content_bounds(&content)) return;

	Rect panel = minimap_panel(rl::get_screen_width(), rl::get_screen_height());
	rl::draw_rectangle_rec(panel, MINIMAP_BG);
	rl::draw_rectangle_lines_ex(panel, 1.0f, MINIMAP_BORDER);

	for (sz i = 0; i < project.folders.len(); i++)
	{
		if (!project.cluster_visible((int)i)) continue;
		rl::draw_rectangle_rec(to_minimap_rect(project.cluster_visual_bounds((int)i), content, panel), MINIMAP_CLUSTER);
	}

	for (sz i = 0; i < project.cards.len(); i++)
	{
		if (!project.card_visible((int)i)) continue;
		Rect block = to_minimap_rect(project.cards[i].rect, content, panel);
		block.width = math::max(block.width, 1.0f);
		block.height = math::max(block.height, 1.0f);
		rl::draw_rectangle_rec(block, MINIMAP_CARD);
	}

	rl::draw_rectangle_lines_ex(to_minimap_rect(canvas.visible_world_rect(), content, panel), 1.0f, MINIMAP_VIEWPORT);
}