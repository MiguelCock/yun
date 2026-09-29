module yun::minimap;

import raylib6::rl;
import std::math;
import yun::canvas;
import yun::card;
import yun::editor;
import yun::project;
import yun::text;
import yun::theme;

const int MINIMAP_WIDTH            = 220;
const int MINIMAP_HEIGHT           = 160;
const int MINIMAP_MARGIN           = 16;
const int MINIMAP_MAX_CARDS        = 600;
const float MINIMAP_ZOOM_THRESHOLD = 0.4f;

struct MinimapSettings
{
	bool enabled;
	float size;
	float zoom_threshold;
}

MinimapSettings g_minimap_settings = {
	.enabled = true,
	.size = 1.0f,
	.zoom_threshold = MINIMAP_ZOOM_THRESHOLD,
};

fn MinimapSettings settings()
{
	return g_minimap_settings;
}

fn void set_settings(MinimapSettings value)
{
	if (value.size < 0.25f) value.size = 0.25f;
	if (value.size > 4.0f) value.size = 4.0f;
	if (value.zoom_threshold < 0.0f) value.zoom_threshold = 0.0f;
	g_minimap_settings = value;
}

fn Rect minimap_panel(int screen_w, int screen_h)
{
	int width  = (int)math::round((float)MINIMAP_WIDTH * g_minimap_settings.size);
	int height = (int)math::round((float)MINIMAP_HEIGHT * g_minimap_settings.size);
	return {
		.x = (float)(screen_w - width - MINIMAP_MARGIN),
		.y = (float)(screen_h - height - MINIMAP_MARGIN),
		.width = (float)width,
		.height = (float)height,
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
	if (!g_minimap_settings.enabled) return false;
	if (canvas.camera.zoom >= g_minimap_settings.zoom_threshold) return false;
	if (project.cards.len() > (sz)MINIMAP_MAX_CARDS) return false;
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
	rl::draw_rectangle_rec(panel, theme::current().minimap_bg);
	rl::draw_rectangle_lines_ex(panel, 1.0f, theme::current().minimap_border);

	for (sz i = 0; i < project.folders.len(); i++)
	{
		if (!project.cluster_visible((int)i)) continue;
		rl::draw_rectangle_rec(to_minimap_rect(project.cluster_visual_bounds((int)i), content, panel), theme::current()
			.minimap_cluster);
	}

	for (sz i = 0; i < project.cards.len(); i++)
	{
		if (!project.card_visible((int)i)) continue;
		Rect block = to_minimap_rect(project.cards[i].rect, content, panel);
		block.width = math::max(block.width, 1.0f);
		block.height = math::max(block.height, 1.0f);
		rl::draw_rectangle_rec(block, theme::current().minimap_card);
	}

	rl::draw_rectangle_lines_ex(to_minimap_rect(canvas.visible_world_rect(), content, panel), 1.0f, theme::current()
		.minimap_viewport);
}

const int FILE_MINIMAP_REF_COLS = 120;
const int FILE_MINIMAP_SAMPLES  = 4;

fn bool file_visible(project::Project* project)
{
	if (!g_minimap_settings.enabled) return false;
	int index = project.focus_card;
	if (index < 0 || index >= (int)project.cards.len()) return false;
	return project.cards[index].buffer != null;
}

fn int file_minimap_line_at(Rect panel, float y, usz line_count)
{
	if (line_count == 0 || panel.height <= 0.0f) return 0;
	float t = (y - panel.y) / panel.height;
	if (t < 0.0f) t = 0.0f;
	if (t > 1.0f) t = 1.0f;
	int line = (int)(t * (float)line_count);
	int last = (int)line_count - 1;
	if (line > last) line = last;
	return line;
}

fn Rect file_minimap_band(Rect panel, usz line, usz line_count)
{
	if (line_count == 0) return { .x = panel.x, .y = panel.y, .width = panel.width, .height = 1.0f };
	float top    = panel.y + (float)line / (float)line_count * panel.height;
	float bottom = panel.y + (float)(line + 1) / (float)line_count * panel.height;
	float height = bottom - top;
	if (height < 1.0f) height = 1.0f;
	return { .x = panel.x, .y = top, .width = panel.width, .height = height };
}

fn Rect file_minimap_viewport(Rect panel, usz first_line, usz visible_lines, usz line_count)
{
	if (line_count == 0) return { .x = panel.x, .y = panel.y, .width = panel.width, .height = 1.0f };
	float top    = panel.y + (float)first_line / (float)line_count * panel.height;
	float bottom = panel.y + (float)(first_line + visible_lines) / (float)line_count * panel.height;
	float height = bottom - top;
	if (height < 2.0f) height = 2.0f;
	if (height > panel.height) height = panel.height;
	return { .x = panel.x, .y = top, .width = panel.width, .height = height };
}

fn bool file_contains_screen(project::Project* project, RLVector2 screen)
{
	if (!file_visible(project)) return false;
	Rect panel = minimap_panel(rl::get_screen_width(), rl::get_screen_height());
	return screen[0] >= panel.x && screen[0] <= panel.x + panel.width && screen[1] >= panel.y
		&& screen[1] <= panel.y + panel.height;
}

fn usz file_line_length(PieceTable* table, usz line, usz line_count)
{
	usz start = table.line_start(line);
	usz end   = line + 1 < line_count ? table.line_start(line + 1) : table.length();
	return end > start ? end - start : 0;
}

fn void draw_file(project::Project* project, editor::EditorMetrics metrics)
{
	if (!file_visible(project)) return;
	card::FileCard* card = &project.cards[project.focus_card];
	usz line_count       = card.buffer.line_count();

	Rect panel = minimap_panel(rl::get_screen_width(), rl::get_screen_height());
	rl::draw_rectangle_rec(panel, theme::current().minimap_bg);
	rl::draw_rectangle_lines_ex(panel, 1.0f, theme::current().minimap_border);
	if (line_count == 0 || metrics.line_height <= 0.0f) return;

	int rows = (int)panel.height;
	if (rows < 1) rows = 1;
	float bar_x = panel.x + 3.0f;
	float bar_w = panel.width - 6.0f;
	for (int row = 0; row < rows; row++)
	{
		usz first = (usz)((long)row * (long)line_count / rows);
		usz last  = (usz)((long)(row + 1) * (long)line_count / rows);
		if (last <= first) last = first + 1;
		if (last > line_count) last = line_count;

		usz max_len = 0;
		for (int s = 0; s < FILE_MINIMAP_SAMPLES; s++)
		{
			usz line = first + (usz)((long)(last - first) * s / FILE_MINIMAP_SAMPLES);
			if (line >= line_count) break;
			usz len = file_line_length(card.buffer, line, line_count);
			if (len > max_len) max_len = len;
		}
		if (max_len == 0) continue;
		float frac = (float)max_len / (float)FILE_MINIMAP_REF_COLS;
		if (frac > 1.0f) frac = 1.0f;
		Rect bar = { .x = bar_x, .y = panel.y + (float)row, .width = bar_w * frac, .height = 1.0f };
		rl::draw_rectangle_rec(bar, theme::current().minimap_card);
	}

	Rect text         = editor::text_rect(card.rect, metrics, line_count);
	usz first_visible = (usz)(card.scroll / metrics.line_height);
	usz visible_lines = (usz)(text.height / metrics.line_height) + 1;
	Rect viewport     = file_minimap_viewport(panel, first_visible, visible_lines, line_count);
	rl::draw_rectangle_lines_ex(viewport, 1.0f, theme::current().minimap_viewport);
}

fn void update_file(project::Project* project, editor::EditorMetrics metrics)
{
	if (!file_visible(project)) return;
	Rect panel      = minimap_panel(rl::get_screen_width(), rl::get_screen_height());
	RLVector2 mouse = rl::get_mouse_position();
	if (!(mouse[0] >= panel.x && mouse[0] <= panel.x + panel.width && mouse[1] >= panel.y
		&& mouse[1] <= panel.y + panel.height)) return;
	if (!rl::is_mouse_button_down(rl::RLMouseButton.LEFT)) return;

	card::FileCard* card = &project.cards[project.focus_card];
	usz line_count       = card.buffer.line_count();
	if (line_count == 0 || metrics.line_height <= 0.0f) return;

	int line    = file_minimap_line_at(panel, mouse[1], line_count);
	Rect text   = editor::text_rect(card.rect, metrics, line_count);
	float value = (float)line * metrics.line_height;
	float max   = editor::max_scroll(line_count, metrics, text.height);
	if (value < 0.0f) value = 0.0f;
	if (value > max) value = max;
	card.scroll = value;
}