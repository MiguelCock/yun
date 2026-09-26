module yun::card;

import raylib6::rl;
import std::io::path;
import std::math;
import yun::highlight;
import yun::text;
import yun::theme;
import yun::ui;

const float CARD_WIDTH        = 240.0f;
const float CARD_HEIGHT       = 160.0f;
const float CARD_TITLE_HEIGHT = 28.0f;
const float HANDLE_PX         = 10.0f;

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
}

fn Rect FileCard.effective_rect(&self)
{
	Rect r = self.rect;
	if (!self.open) r.height = CARD_TITLE_HEIGHT;
	return r;
}

fn bool FileCard.marker_hit(&self, RLVector2 world)
{
	Rect r  = self.effective_rect();
	float x = r.x + r.width - 24.0f;
	return world[0] >= x && world[0] <= r.x + r.width && world[1] >= r.y && world[1] <= r.y + CARD_TITLE_HEIGHT;
}

fn bool FileCard.close_marker_hit(&self, RLVector2 world)
{
	Rect r  = self.effective_rect();
	float x = r.x + r.width - 44.0f;
	return world[0] >= x && world[0] <= r.x + r.width - 24.0f && world[1] >= r.y && world[1] <= r.y + CARD_TITLE_HEIGHT;
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

fn void FileCard.draw(&self, bool focused)
{
	Rect r = self.effective_rect();
	rl::draw_rectangle_rec(r, theme::current().card_body);
	Rect title = {
		.x = r.x,
		.y = r.y,
		.width = r.width,
		.height = ui::pxf(CARD_TITLE_HEIGHT),
	};
	rl::draw_rectangle_rec(title, theme::current().card_title);
	if (focused)
	{
		rl::draw_rectangle_lines_ex(r, 1.0f, theme::current().card_focus);
	}
	else
	{
		rl::draw_rectangle_lines_ex(r, 1.0f, theme::current().card_border);
	}
	@pool()
	{
		rl::draw_text_ex(
			ui::font(),
			self.name.zstr_tcopy(),
			{ r.x + (float)ui::px(10), r.y + (float)ui::px(7) },
			(float)ui::px(16),
			0.0f,
			theme::current()
			.card_text);
	};
	if (self.dirty) rl::draw_circle(
		(int)(r.x + r.width - (float)ui::px(52)),
		(int)(r.y + (float)ui::px(14)),
		(float)ui::px(3),
		theme::current()
		.card_dirty);
	if (self.buffer) rl::draw_text_ex(
		ui::font(),
		"x",
		{ r.x + r.width - (float)ui::px(40), r.y + (float)ui::px(7) },
		(float)ui::px(16),
		0.0f,
		theme::current()
		.card_text);
	rl::draw_text_ex(
		ui::font(),
		self.open ? "-" : "+",
		{ r.x + r.width - (float)ui::px(18), r.y + (float)ui::px(7) },
		(float)ui::px(16),
		0.0f,
		theme::current()
		.card_text);
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