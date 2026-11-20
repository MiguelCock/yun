module yun::card;

import raylib6::rl;
import std::io::path;
import std::math;
import yun::highlight;
import yun::icons;
import yun::markdown;
import yun::text;
import yun::theme;
import yun::ui;

const float CARD_WIDTH            = 240.0f;
const float CARD_HEIGHT           = 160.0f;
const float CARD_TITLE_HEIGHT     = 28.0f;
const float CARD_TITLE_BUTTON     = 24.0f;
const float CARD_TITLE_BUTTON_GAP = 2.0f;
const float HANDLE_PX             = 10.0f;

struct FileCard
{
	Path path;
	String name;
	Rect rect;
	bool open;
	bool dirty;
	int folder;
	PieceTable* buffer;
	History* history;
	highlight::Highlighter* highlight;
	float scroll;
	float scroll_x;
	usz cursor;
	usz selection_anchor;
	usz preferred_column;
	long mtime;
	long size;
	bool missing;
	bool ephemeral;
	bool sleeping;
	bool restored;
	bool preview;
	float preview_scroll;
	markdown::View* view;
}

fn Rect FileCard.effective_rect(&self)
{
	Rect r = self.rect;
	if (!self.open) r.height = ui::pxf(CARD_TITLE_HEIGHT);
	return r;
}

fn Rect FileCard.title_button_rect(&self, int slot)
{
	Rect r    = self.effective_rect();
	float w   = ui::pxf(CARD_TITLE_BUTTON);
	float gap = ui::pxf(CARD_TITLE_BUTTON_GAP);
	return {
		.x = r.x + r.width - (float)(3 - slot) * w - (float)(2 - slot) * gap,
		.y = r.y + (ui::pxf(CARD_TITLE_HEIGHT) - w) * 0.5f,
		.width = w,
		.height = w,
	};
}

fn bool rect_has_point(Rect r, RLVector2 p)
{
	return p[0] >= r.x && p[0] <= r.x + r.width && p[1] >= r.y && p[1] <= r.y + r.height;
}

fn bool FileCard.preview_marker_hit(&self, RLVector2 world)
{
	return rect_has_point(self.title_button_rect(0), world);
}

fn bool FileCard.maximize_marker_hit(&self, RLVector2 world)
{
	return rect_has_point(self.title_button_rect(1), world);
}

fn bool FileCard.minimize_marker_hit(&self, RLVector2 world)
{
	return rect_has_point(self.title_button_rect(2), world);
}

fn RLVector2 FileCard.center(&self)
{
	return { self.rect.x + self.rect.width / 2.0f, self.rect.y + self.rect.height / 2.0f };
}

fn bool FileCard.contains(&self, RLVector2 world)
{
	Rect r = self.effective_rect();
	return world[0] >= r.x && world[0] <= r.x + r.width && world[1] >= r.y && world[1] <= r.y + r.height;
}

fn void FileCard.move_by(&self, RLVector2 world_delta)
{
	self.rect.x += world_delta[0];
	self.rect.y += world_delta[1];
}

fn float screen_thickness(float px, float zoom)
{
	if (zoom <= 0.0f) return px;
	float t = px / zoom;
	if (t < 0.01f) t = 0.01f;
	return t;
}

fn void draw_title_button(Rect button, icons::IconKind icon, bool active, bool hovered, bool pressed, float zoom)
{
	if (pressed)
	{
		ui::rounded_rect(button, zoom > 0.0f ? ui::row_radius() / zoom : ui::row_radius(), theme::current()
			.panel_selected);
	}
	else if (hovered || active)
	{
		ui::rounded_rect(button, zoom > 0.0f ? ui::row_radius() / zoom : ui::row_radius(), theme::current()
			.panel_bg_alt);
	}
	float size = ui::pxf(16.0f);
	icons::draw(
		icon,
		{
			.x = button.x + (button.width - size) * 0.5f,
			.y = button.y + (button.height - size) * 0.5f,
			.width = size,
			.height = size,
		},
		active ? theme::current()
		.card_focus : theme::current().card_text);
}

fn void FileCard.draw(&self, bool focused, RLCamera2D camera, RLVector2 mouse_world, bool focus_mode)
{
	float zoom   = camera.zoom;
	Rect r       = self.effective_rect();
	float radius = zoom > 0.0f ? ui::corner_radius() / zoom : ui::corner_radius();
	ui::rounded_rect(r, radius, theme::current().card_body);
	Rect title = {
		.x = r.x,
		.y = r.y,
		.width = r.width,
		.height = ui::pxf(CARD_TITLE_HEIGHT),
	};
	ui::rounded_top(title, radius, theme::current().card_title);
	if (focused)
	{
		ui::rounded_rect_lines(r, radius, screen_thickness(1.0f, zoom), theme::current().card_focus);
	}
	else
	{
		ui::rounded_rect_lines(r, radius, screen_thickness(1.0f, zoom), theme::current().card_border);
	}
	@pool()
	{
		rl::draw_text_ex(
			ui::font(),
			self.name.zstr_tcopy(),
			{ r.x + (float)ui::px(10), r.y + (float)ui::px(7) },
			(float)ui::tpx(16),
			0.0f,
			theme::current()
			.card_text);
	};
	bool buttons_enabled = !focus_mode;
	bool pressed         = rl::is_mouse_button_down(rl::RLMouseButton.LEFT);
	Rect preview_button  = self.title_button_rect(0);
	Rect maximize_button = self.title_button_rect(1);
	Rect minimize_button = self.title_button_rect(2);

	if (markdown::is_markdown_path((String)self.path))
	{
		bool hovered = buttons_enabled && rect_has_point(preview_button, mouse_world);
		draw_title_button(preview_button, icons::IconKind.PREVIEW, self.preview, hovered, hovered && pressed, zoom);
	}
	if (self.dirty) rl::draw_circle(
		(int)(preview_button.x - (float)ui::px(8)),
		(int)(r.y + ui::pxf(CARD_TITLE_HEIGHT) * 0.5f),
		(float)ui::px(3),
		theme::current()
		.card_dirty);

	bool maximize_hovered = buttons_enabled && rect_has_point(maximize_button, mouse_world);
	draw_title_button(
		maximize_button,
		focus_mode ? icons::IconKind.RESTORE : icons::IconKind.MAXIMIZE,
		focus_mode,
		maximize_hovered,
		maximize_hovered && pressed,
		zoom
	);

	bool minimize_hovered = buttons_enabled && rect_has_point(minimize_button, mouse_world);
	draw_title_button(
		minimize_button,
		self.open ? icons::IconKind.CHEVRON_DOWN : icons::IconKind.CHEVRON_RIGHT,
		false,
		minimize_hovered,
		minimize_hovered && pressed,
		zoom
	);
}

fn void FileCard.draw_lod(&self, float zoom)
{
	Rect r       = self.effective_rect();
	float radius = zoom > 0.0f ? ui::corner_radius() / zoom : ui::corner_radius();
	ui::rounded_rect(r, radius, theme::current().card_body);
	ui::rounded_rect_lines(r, radius, screen_thickness(1.0f, zoom), theme::current().card_border);
}
fn void FileCard.handle_points(&self, RLVector2[8]* points)
{
	Rect r = self.rect;
	(*points)[0] = { r.x, r.y };
	(*points)[1] = { r.x + r.width / 2.0f, r.y };
	(*points)[2] = { r.x + r.width, r.y };
	(*points)[3] = { r.x + r.width, r.y + r.height / 2.0f };
	(*points)[4] = { r.x + r.width, r.y + r.height };
	(*points)[5] = { r.x + r.width / 2.0f, r.y + r.height };
	(*points)[6] = { r.x, r.y + r.height };
	(*points)[7] = { r.x, r.y + r.height / 2.0f };
}

fn int FileCard.resize_handle_at(&self, RLVector2 world, RLCamera2D camera)
{
	if (!self.open) return -1;
	RLVector2[8] points;
	self.handle_points(&points);
	float half = (HANDLE_PX / camera.zoom) / 2.0f;
	for (int i = 0; i < 8; i++)
	{
		if (world[0] >= points[i][0] - half && world[0] <= points[i][0] + half && world[1] >= points[i][1] - half
			&& world[1] <= points[i][1] + half)
		{
			return i;
		}
	}
	return -1;
}

fn void FileCard.resize_from(&self, int handle, RLVector2 delta, float min_w, float min_h)
{
	Rect r = self.rect;

	if (handle == 0 || handle == 6 || handle == 7)
	{
		float new_width = r.width - delta[0];
		float new_x     = r.x + delta[0];
		if (new_width < min_w)
		{
			new_x = r.x + r.width - min_w;
			new_width = min_w;
		}
		r.x = new_x;
		r.width = new_width;
	}
	if (handle == 2 || handle == 3 || handle == 4)
	{
		float new_width = r.width + delta[0];
		if (new_width < min_w) new_width = min_w;
		r.width = new_width;
	}
	if (handle == 0 || handle == 1 || handle == 2)
	{
		float new_height = r.height - delta[1];
		float new_y      = r.y + delta[1];
		if (new_height < min_h)
		{
			new_y = r.y + r.height - min_h;
			new_height = min_h;
		}
		r.y = new_y;
		r.height = new_height;
	}
	if (handle == 4 || handle == 5 || handle == 6)
	{
		float new_height = r.height + delta[1];
		if (new_height < min_h) new_height = min_h;
		r.height = new_height;
	}

	self.rect = r;
}

fn void FileCard.draw_handles(&self, RLCamera2D camera, RLColor color)
{
	if (!self.open) return;
	RLVector2[8] points;
	self.handle_points(&points);
	float half = (HANDLE_PX / camera.zoom) / 2.0f;
	for (int i = 0; i < 8; i++)
	{
		Rect square = {
			.x = points[i][0] - half,
			.y = points[i][1] - half,
			.width = half * 2.0f,
			.height = half * 2.0f
		};
		rl::draw_rectangle_rec(square, color);
	}
}