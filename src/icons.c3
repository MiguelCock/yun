module yun::icons;

import raylib6::rl;
import std::math;
import std::math::geometry;
import yun::ui;

enum IconKind : int
{
	NEW_FILE,
	OPEN,
	SAVE,
	SETTINGS,
	CONNECTIONS,
	QUIT,
	PREVIEW,
	MAXIMIZE,
	MINIMIZE,
	CLOSE,
	SEARCH,
	PROBLEMS,
	SYMBOLS,
	CONSOLE,
	KEYBOARD,
	THEME,
	PLAY,
	STOP,
	TRASH,
	CHEVRON_DOWN,
	CHEVRON_RIGHT,
}

fn float icon_size(int logical)
{
	return ui::pxf((float)logical);
}

fn Rect icon_box(Rect button, int logical)
{
	float size = icon_size(logical);
	return {
		.x = button.x + (button.width - size) * 0.5f,
		.y = button.y + (button.height - size) * 0.5f,
		.width = size,
		.height = size,
	};
}

fn void seg(Rect b, float x1, float y1, float x2, float y2, float stroke, RLColor color)
{
	rl::draw_line_ex(
		{ b.x + b.width * x1, b.y + b.height * y1 },
		{ b.x + b.width * x2, b.y + b.height * y2 },
		stroke,
		color
	);
}

fn void draw(IconKind icon, Rect b, RLColor color)
{
	float stroke = math::max(1.0f, b.width * 0.09f);
	switch (icon)
	{
		case IconKind.NEW_FILE:
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.25f, b.y + b.height * 0.12f, b.width * 0.5f, b.height * 0.76f },
				stroke,
				color
			);
			seg(b, 0.5f, 0.35f, 0.5f, 0.65f, stroke, color);
			seg(b, 0.35f, 0.5f, 0.65f, 0.5f, stroke, color);
		case IconKind.OPEN:
			seg(b, 0.15f, 0.3f, 0.45f, 0.3f, stroke, color);
			seg(b, 0.45f, 0.3f, 0.55f, 0.4f, stroke, color);
			seg(b, 0.55f, 0.4f, 0.85f, 0.4f, stroke, color);
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.15f, b.y + b.height * 0.4f, b.width * 0.7f, b.height * 0.4f },
				stroke,
				color
			);
		case IconKind.SAVE:
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.18f, b.y + b.height * 0.15f, b.width * 0.64f, b.height * 0.7f },
				stroke,
				color
			);
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.33f, b.y + b.height * 0.5f, b.width * 0.34f, b.height * 0.35f },
				stroke,
				color
			);
			rl::draw_rectangle_rec(
				{ b.x + b.width * 0.35f, b.y + b.height * 0.18f, b.width * 0.3f, b.height * 0.22f },
				color
			);
		case IconKind.SETTINGS:
			rl::draw_ring_lines(
				{ b.x + b.width * 0.5f, b.y + b.height * 0.5f },
				b.width * 0.18f,
				b.width * 0.28f,
				0.0f,
				360.0f,
				24,
				color
			);
			for (int i = 0; i < 4; i++)
			{
				float a = (float)i * math::PI * 0.5f;
				seg(
					b,
					0.5f + math::cos(a) * 0.28f,
					0.5f + math::sin(a) * 0.28f,
					0.5f + math::cos(a) * 0.42f,
					0.5f + math::sin(a) * 0.42f,
					stroke,
					color
				);
			}
		case IconKind.CONNECTIONS:
			rl::draw_circle_lines_v({ b.x + b.width * 0.25f, b.y + b.height * 0.35f }, b.width * 0.12f, color);
			rl::draw_circle_lines_v({ b.x + b.width * 0.75f, b.y + b.height * 0.65f }, b.width * 0.12f, color);
			seg(b, 0.34f, 0.42f, 0.66f, 0.58f, stroke, color);
		case IconKind.QUIT:
			rl::draw_ring_lines(
				{ b.x + b.width * 0.5f, b.y + b.height * 0.52f },
				b.width * 0.28f,
				b.width * 0.38f,
				40.0f,
				320.0f,
				24,
				color
			);
			seg(b, 0.5f, 0.12f, 0.5f, 0.5f, stroke, color);
		case IconKind.PREVIEW:
			rl::draw_ring_lines(
				{ b.x + b.width * 0.5f, b.y + b.height * 0.5f },
				b.width * 0.1f,
				b.width * 0.34f,
				0.0f,
				360.0f,
				24,
				color
			);
			rl::draw_circle_v({ b.x + b.width * 0.5f, b.y + b.height * 0.5f }, b.width * 0.08f, color);
		case IconKind.MAXIMIZE:
			seg(b, 0.2f, 0.4f, 0.2f, 0.2f, stroke, color);
			seg(b, 0.2f, 0.2f, 0.4f, 0.2f, stroke, color);
			seg(b, 0.8f, 0.4f, 0.8f, 0.2f, stroke, color);
			seg(b, 0.8f, 0.2f, 0.6f, 0.2f, stroke, color);
			seg(b, 0.2f, 0.6f, 0.2f, 0.8f, stroke, color);
			seg(b, 0.2f, 0.8f, 0.4f, 0.8f, stroke, color);
			seg(b, 0.8f, 0.6f, 0.8f, 0.8f, stroke, color);
			seg(b, 0.8f, 0.8f, 0.6f, 0.8f, stroke, color);
		case IconKind.MINIMIZE:
			seg(b, 0.3f, 0.5f, 0.5f, 0.7f, stroke, color);
			seg(b, 0.5f, 0.7f, 0.7f, 0.5f, stroke, color);
		case IconKind.CLOSE:
			seg(b, 0.25f, 0.25f, 0.75f, 0.75f, stroke, color);
			seg(b, 0.75f, 0.25f, 0.25f, 0.75f, stroke, color);
		case IconKind.SEARCH:
			rl::draw_ring_lines(
				{ b.x + b.width * 0.42f, b.y + b.height * 0.42f },
				b.width * 0.18f,
				b.width * 0.28f,
				0.0f,
				360.0f,
				24,
				color
			);
			seg(b, 0.62f, 0.62f, 0.82f, 0.82f, stroke, color);
		case IconKind.PROBLEMS:
			seg(b, 0.5f, 0.15f, 0.15f, 0.82f, stroke, color);
			seg(b, 0.15f, 0.82f, 0.85f, 0.82f, stroke, color);
			seg(b, 0.85f, 0.82f, 0.5f, 0.15f, stroke, color);
			seg(b, 0.5f, 0.38f, 0.5f, 0.62f, stroke, color);
			rl::draw_circle_v({ b.x + b.width * 0.5f, b.y + b.height * 0.72f }, stroke * 0.55f, color);
		case IconKind.SYMBOLS:
			seg(b, 0.38f, 0.15f, 0.28f, 0.22f, stroke, color);
			seg(b, 0.28f, 0.22f, 0.28f, 0.78f, stroke, color);
			seg(b, 0.28f, 0.78f, 0.38f, 0.85f, stroke, color);
			seg(b, 0.62f, 0.15f, 0.72f, 0.22f, stroke, color);
			seg(b, 0.72f, 0.22f, 0.72f, 0.78f, stroke, color);
			seg(b, 0.72f, 0.78f, 0.62f, 0.85f, stroke, color);
		case IconKind.CONSOLE:
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.1f, b.y + b.height * 0.18f, b.width * 0.8f, b.height * 0.64f },
				stroke,
				color
			);
			seg(b, 0.28f, 0.42f, 0.4f, 0.5f, stroke, color);
			seg(b, 0.4f, 0.5f, 0.28f, 0.58f, stroke, color);
			seg(b, 0.52f, 0.62f, 0.7f, 0.62f, stroke, color);
		case IconKind.KEYBOARD:
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.08f, b.y + b.height * 0.25f, b.width * 0.84f, b.height * 0.5f },
				stroke,
				color
			);
			for (int i = 0; i < 3; i++)
			{
				rl::draw_circle_v(
					{ b.x + b.width * (0.25f + (float)i * 0.25f), b.y + b.height * 0.48f },
					stroke * 0.45f,
					color
				);
			}
			seg(b, 0.3f, 0.62f, 0.7f, 0.62f, stroke, color);
		case IconKind.THEME:
			rl::draw_ring_lines(
				{ b.x + b.width * 0.5f, b.y + b.height * 0.5f },
				b.width * 0.34f,
				b.width * 0.42f,
				0.0f,
				360.0f,
				24,
				color
			);
			rl::draw_circle_sector(
				{ b.x + b.width * 0.5f, b.y + b.height * 0.5f },
				b.width * 0.33f,
				270.0f,
				90.0f,
				16,
				color
			);
		case IconKind.PLAY:
			rl::draw_triangle(
				{ b.x + b.width * 0.35f, b.y + b.height * 0.2f },
				{ b.x + b.width * 0.35f, b.y + b.height * 0.8f },
				{ b.x + b.width * 0.8f, b.y + b.height * 0.5f },
				color
			);
		case IconKind.STOP:
			rl::draw_rectangle_rec(
				{ b.x + b.width * 0.28f, b.y + b.height * 0.28f, b.width * 0.44f, b.height * 0.44f },
				color
			);
		case IconKind.TRASH:
			seg(b, 0.25f, 0.28f, 0.75f, 0.28f, stroke, color);
			seg(b, 0.4f, 0.18f, 0.6f, 0.18f, stroke, color);
			rl::draw_rectangle_lines_ex(
				{ b.x + b.width * 0.3f, b.y + b.height * 0.3f, b.width * 0.4f, b.height * 0.55f },
				stroke,
				color
			);
		case IconKind.CHEVRON_DOWN:
			seg(b, 0.25f, 0.4f, 0.5f, 0.65f, stroke, color);
			seg(b, 0.5f, 0.65f, 0.75f, 0.4f, stroke, color);
		case IconKind.CHEVRON_RIGHT:
			seg(b, 0.4f, 0.25f, 0.65f, 0.5f, stroke, color);
			seg(b, 0.65f, 0.5f, 0.4f, 0.75f, stroke, color);
	}
}