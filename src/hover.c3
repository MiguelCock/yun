module yun::hover;

import raylib6::rl;
import std::collections::list;
import std::core::dstring;
import std::core::mem::alloc;
import std::math;

const float HOVER_MAX_WIDTH = 560.0f;
const int HOVER_MAX_LINES   = 24;
const float HOVER_LINE_H    = 18.0f;
const RLColor HOVER_BG      = { 20, 22, 30, 250 };
const RLColor HOVER_BORDER  = { 90, 110, 150, 255 };
const RLColor HOVER_TEXT    = { 210, 214, 222, 255 };
const RLColor HOVER_CODE    = { 152, 195, 121, 255 };
const RLColor HOVER_CODE_BG = { 30, 33, 42, 255 };
const RLColor HOVER_HEADING = { 229, 192, 123, 255 };
const RLColor HOVER_DIM     = { 140, 150, 170, 255 };

struct HoverRun
{
	String text;
	bool code;
}

struct HoverLine
{
	List{HoverRun} runs;
	bool code;
	bool heading;
}

fn void push_run(Allocator allocator, DString* current, List{HoverRun}* runs, bool code)
{
	if (current.len() == 0) return;
	runs.push({ .text = current.str_view().copy(allocator), .code = code });
	current.clear();
}

fn void build_runs(Allocator allocator, String body, List{HoverRun}* runs)
{
	DString current;
	current.init(allocator, 32);
	bool in_code = false;
	usz i        = 0;
	while (i < body.len)
	{
		char c = body[i];
		if (c == '`')
		{
			push_run(allocator, &current, runs, in_code);
			in_code = !in_code;
			i++;
			continue;
		}
		if (!in_code && (c == '*' || c == '_'))
		{
			i++;
			continue;
		}
		current.append_char(c);
		i++;
	}
	push_run(allocator, &current, runs, in_code);
	current.free();
}

fn void parse_markdown(Allocator allocator, String text, List{HoverLine}* out)
{
	bool in_code = false;
	usz i        = 0;
	while (i < text.len)
	{
		usz start = i;
		while (i < text.len && text[i] != '\n') i++;
		String line = text[start:i - start];
		if (i < text.len) i++;

		if (line.len >= 3 && line[0] == '`' && line[1] == '`' && line[2] == '`')
		{
			in_code = !in_code;
			continue;
		}

		HoverLine hover_line;
		hover_line.code = in_code;
		hover_line.heading = false;
		hover_line.runs.init(allocator);

		if (in_code)
		{
			hover_line.runs.push({ .text = line.copy(allocator), .code = true });
		}
		else
		{
			String body = line;
			usz hashes  = 0;
			while (hashes < body.len && body[hashes] == '#') hashes++;
			if (hashes > 0 && hashes < body.len && body[hashes] == ' ')
			{
				hover_line.heading = true;
				body = body[hashes + 1..];
			}
			build_runs(allocator, body, &hover_line.runs);
		}
		out.push(hover_line);
	}
}

fn float text_width(RLFont font, String text, float size)
{
	if (text.len == 0) return 0.0f;
	float width = 0.0f;
	@pool()
	{
		width = rl::measure_text_ex(font, text.zstr_tcopy(), size, 0.0f)[0];
	};
	return width;
}

fn void draw_run(RLFont font, String text, float x, float y, float size, RLColor color)
{
	if (text.len == 0) return;
	@pool()
	{
		rl::draw_text_ex(font, text.zstr_tcopy(), { x, y }, size, 0.0f, color);
	};
}

fn float line_width(RLFont font, HoverLine* line)
{
	float size  = line.heading ? 16.0f : 14.0f;
	float width = 0.0f;
	for (sz i = 0; i < line.runs.len(); i++)
	{
		width += text_width(font, line.runs[i].text, size);
	}
	return width;
}

fn void draw_hover(String markdown, RLVector2 anchor, RLFont font)
{
	if (markdown.len == 0) return;
	@pool()
	{
		List{HoverLine} lines;
		lines.init(tmem);
		parse_markdown(tmem, markdown, &lines);
		if (lines.len() == 0) return;

		int count = (int)lines.len();
		if (count > HOVER_MAX_LINES) count = HOVER_MAX_LINES;

		float width = 0.0f;
		for (int i = 0; i < count; i++)
		{
			float w = line_width(font, &lines[(sz)i]);
			if (w > width) width = w;
		}
		if (width > HOVER_MAX_WIDTH) width = HOVER_MAX_WIDTH;

		Rect panel = {
			.x = anchor[0] + 14.0f,
			.y = anchor[1] + 14.0f,
			.width = width + 16.0f,
			.height = (float)count * HOVER_LINE_H + 12.0f,
		};
		if (panel.x + panel.width > (float)rl::get_screen_width()) panel.x = anchor[0] - panel.width - 8.0f;
		if (panel.y + panel.height > (float)rl::get_screen_height()) panel.y = anchor[1] - panel.height - 8.0f;
		if (panel.x < 4.0f) panel.x = 4.0f;
		if (panel.y < 4.0f) panel.y = 4.0f;

		rl::draw_rectangle_rec(panel, HOVER_BG);
		rl::draw_rectangle_lines_ex(panel, 1.0f, HOVER_BORDER);

		rl::begin_scissor_mode((int)panel.x + 2, (int)panel.y + 2, (int)panel.width - 4, (int)panel.height - 4);
		for (int i = 0; i < count; i++)
		{
			HoverLine* line = &lines[(sz)i];
			float row_y     = panel.y + 6.0f + (float)i * HOVER_LINE_H;
			if (line.code)
			{
				rl::draw_rectangle_rec(
					{ .x = panel.x + 4.0f, .y = row_y - 1.0f, .width = panel.width - 8.0f, .height = HOVER_LINE_H },
					HOVER_CODE_BG
				);
			}
			float size = line.heading ? 16.0f : 14.0f;
			float x    = panel.x + 8.0f;
			for (sz r = 0; r < line.runs.len(); r++)
			{
				RLColor color = line.runs[r].code ? HOVER_CODE : (line.heading ? HOVER_HEADING : HOVER_TEXT);
				draw_run(font, line.runs[r].text, x, row_y, size, color);
				x += text_width(font, line.runs[r].text, size);
			}
		}
		if ((int)lines.len() > count)
		{
			draw_run(font, "...", panel.x + 8.0f, panel.y + 6.0f + (float)count * HOVER_LINE_H, 14.0f, HOVER_DIM);
		}
		rl::end_scissor_mode();
	};
}