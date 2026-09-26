module yun::ui;

import raylib6::rl;
import std::math;

const int BASE_SIZE = 16;

RLFont g_font;
int g_size = BASE_SIZE;

fn void set_font(RLFont font, int size)
{
	g_font = font;
	g_size = size > 0 ? size : BASE_SIZE;
}

fn RLFont font()
{
	return g_font;
}

fn int size()
{
	return g_size;
}

fn float scale()
{
	return (float)g_size / (float)BASE_SIZE;
}

fn int px(int base)
{
	return (int)math::round((float)base * scale());
}

fn float pxf(float base)
{
	return base * scale();
}