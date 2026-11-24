module yun::notify;

import raylib6::rl;
import std::collections::list;
import yun::theme;
import yun::ui;

const float NOTICE_TTL  = 4.0f;
const int MAX_NOTICES   = 5;
const int NOTICE_HEIGHT = 24;

struct Notice
{
	String text;
	float ttl;
}

struct Notifier
{
	List{Notice} items;
	Allocator allocator;
	float ttl;
	int max_items;
	int position;
}

fn void Notifier.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.items.init(allocator);
	self.ttl = self.ttl;
	self.max_items = MAX_NOTICES;
	self.position = 2;
}

fn void Notifier.configure(&self, float ttl, int max_items, int position)
{
	self.ttl = ttl > 0.1f ? ttl : 0.1f;
	self.max_items = max_items > 0 ? max_items : 1;
	self.position = position >= 0 && position < 4 ? position : 2;
}

fn void Notifier.destroy(&self)
{
	for (sz i = 0; i < self.items.len(); i++)
	{
		if (self.items[i].text.len) self.items[i].text.free(self.allocator);
	}
	self.items.free();
}

fn void Notifier.push(&self, String message)
{
	if (self.items.len() >= self.max_items)
	{
		if (self.items[0].text.len) self.items[0].text.free(self.allocator);
		self.items.remove_at(0);
	}
	self.items.push({ .text = message.copy(self.allocator), .ttl = self.ttl });
}

fn void Notifier.update(&self, float dt)
{
	for (sz i = self.items.len(); i > 0; i--)
	{
		self.items[i - 1].ttl -= dt;
		if (self.items[i - 1].ttl <= 0.0f)
		{
			if (self.items[i - 1].text.len) self.items[i - 1].text.free(self.allocator);
			self.items.remove_at(i - 1);
		}
	}
}

fn void Notifier.draw(&self)
{
	int height  = ui::px(NOTICE_HEIGHT);
	int margin  = ui::px(10);
	bool right  = self.position == 1 || self.position == 3;
	bool bottom = self.position >= 2;
	float y     = bottom ? (float)(rl::get_screen_height() - height - margin) : (float)margin;
	foreach (Notice notice : self.items)
	{
		@pool()
		{
			float size  = (float)ui::tpx(NOTICE_HEIGHT - 8);
			float width = rl::measure_text_ex(ui::font(), notice.text.zstr_tcopy(), size, 0.0f)[0] + (float)ui::px(16);
			float x     = right ? (float)rl::get_screen_width() - width - (float)margin : (float)margin;
			ui::rounded_rect(
				{ .x = x, .y = y, .width = width, .height = (float)height },
				ui::corner_radius(),
				theme::current()
				.notice_bg);
			rl::draw_text_ex(
				ui::font(),
				notice.text.zstr_tcopy(),
				{ x + (float)ui::px(8), (float)(y + ui::px(4)) },
				size,
				0.0f,
				theme::current()
				.notice_text);
		};
		y += bottom ? -(float)(height + ui::px(4)) : (float)(height + ui::px(4));
	}
}