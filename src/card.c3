module yun::card;

import raylib6::rl;
import std::io::path;
import std::math;

const float CARD_WIDTH        = 240.0f;
const float CARD_HEIGHT       = 160.0f;
const float CARD_TITLE_HEIGHT = 28.0f;
const RLColor CARD_BODY       = { 32, 32, 38, 255 };
const RLColor CARD_TITLE      = { 44, 44, 54, 255 };
const RLColor CARD_BORDER     = { 70, 70, 84, 255 };
const RLColor CARD_FOCUS      = { 120, 160, 240, 255 };
const RLColor CARD_TEXT       = { 220, 220, 228, 255 };

struct FileCard
{
	Path path;
	String name;
	Rect rect;
	bool open;
	bool dirty;
	int folder;
}

fn bool FileCard.contains(&self, RLVector2 world)
{
	return world[0] >= self.rect.x && world[0] <= self.rect.x + self.rect.width && world[1] >= self.rect.y
		&& world[1] <= self.rect.y + self.rect.height;
}

fn void FileCard.move_by(&self, RLVector2 world_delta)
{
	self.rect.x += world_delta[0];
	self.rect.y += world_delta[1];
}

fn void FileCard.draw(&self, bool focused)
{
	rl::draw_rectangle_rec(self.rect, CARD_BODY);
	Rect title = {
		.x = self.rect.x,
		.y = self.rect.y,
		.width = self.rect.width,
		.height = CARD_TITLE_HEIGHT,
	};
	rl::draw_rectangle_rec(title, CARD_TITLE);
	if (focused)
	{
		rl::draw_rectangle_lines_ex(self.rect, 1.0f, CARD_FOCUS);
	}
	else
	{
		rl::draw_rectangle_lines_ex(self.rect, 1.0f, CARD_BORDER);
	}
	rl::draw_text((ZString)self.name.ptr, (int)(self.rect.x + 10.0f), (int)(self.rect.y + 7.0f), 16, CARD_TEXT);
}