module yun::notify;

import raylib6::rl;
import std::collections::list;

const float NOTICE_TTL    = 4.0f;
const int MAX_NOTICES     = 5;
const int NOTICE_HEIGHT   = 24;
const RLColor NOTICE_BG   = { 0, 0, 0, 180 };
const RLColor NOTICE_TEXT = { 240, 240, 240, 255 };

struct Notice
{
	String text;
	float ttl;
}

struct Notifier
{
	List{Notice} items;
	Allocator allocator;
}

fn void Notifier.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.items.init(allocator);
}

fn void Notifier.push(&self, String message)
{
	if (self.items.len() >= MAX_NOTICES)
	{
		self.items.remove_at(0);
	}
	self.items.push({ .text = message.copy(self.allocator), .ttl = NOTICE_TTL });
}

fn void Notifier.update(&self, float dt)
{
	for (sz i = self.items.len(); i > 0; i--)
	{
		self.items[i - 1].ttl -= dt;
		if (self.items[i - 1].ttl <= 0.0f) self.items.remove_at(i - 1);
	}
}

fn void Notifier.draw(&self)
{
	int y = rl::get_screen_height() - NOTICE_HEIGHT - 10;
	foreach (Notice notice : self.items)
	{
		int width = rl::measure_text((ZString)notice.text.ptr, NOTICE_HEIGHT - 8) + 16;
		rl::draw_rectangle(10, y, width, NOTICE_HEIGHT, NOTICE_BG);
		rl::draw_text((ZString)notice.text.ptr, 18, y + 4, NOTICE_HEIGHT - 8, NOTICE_TEXT);
		y -= NOTICE_HEIGHT + 4;
	}
}