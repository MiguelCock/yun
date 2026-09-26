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
	int height = ui::px(NOTICE_HEIGHT);
	int y      = rl::get_screen_height() - height - ui::px(10);
	foreach (Notice notice : self.items)
	{
		@pool()
		{
			float size  = (float)(height - ui::px(8));
			float width = rl::measure_text_ex(ui::font(), notice.text.zstr_tcopy(), size, 0.0f)[0] + (float)ui::px(16);
			rl::draw_rectangle(ui::px(10), y, (int)width, height, theme::current().notice_bg);
			rl::draw_text_ex(
				ui::font(),
				notice.text.zstr_tcopy(),
				{ (float)ui::px(18), (float)(y + ui::px(4)) },
				size,
				0.0f,
				theme::current()
				.notice_text);
		};
		y -= height + ui::px(4);
	}
}