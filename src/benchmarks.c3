module yun::benchmarks @feat(BENCHMARKING);

import raylib6::rl;
import std::collections::list;
import std::core::dstring;
import std::math::geometry;
import yun::card;
import yun::highlight;
import yun::project;
import yun::text;
import yun::ui;

const int BENCH_CARDS = 200;

project::Project g_bench_project;
bool g_bench_project_ready = false;
int g_bench_counter        = 0;

text::PieceTable g_bench_table;
highlight::Highlighter* g_bench_highlighter;
List{highlight::Span} g_bench_runs;
bool g_bench_highlight_ready = false;

macro void ensure_bench_project()
{
	if (!g_bench_project_ready)
	{
		g_bench_project.init(mem);
		int cols = 15;
		float cw = ui::pxf(card::CARD_WIDTH) + ui::pxf(32.0f);
		float ch = ui::pxf(card::CARD_HEIGHT) + ui::pxf(32.0f);
		for (int k = 0; k < BENCH_CARDS; k++)
		{
			String path = string::format(mem, "/bench/bench_%d.c3", k);
			int index   = g_bench_project.append_card(path, { 0.0f, 0.0f });
			g_bench_project.cards[index].rect = {
				.x = (float)(k % cols) * cw,
				.y = (float)(k / cols) * ch,
				.width = ui::pxf(card::CARD_WIDTH),
				.height = ui::pxf(card::CARD_HEIGHT),
			};
		}
		g_bench_project.invalidate_bounds();
		g_bench_project_ready = true;
	}
}

macro void ensure_bench_highlight()
{
	if (!g_bench_highlight_ready)
	{
		g_bench_runs.init(mem);
		DString src;
		src.init(mem, 8192);
		for (int i = 0; i < 60; i++)
		{
			(void)src.appendf("fn int f%d(int a, int b) { return a + b; } // note\n", i);
		}
		String text = src.str_view().copy(mem);
		src.free();
		g_bench_table.init_from_buffer(mem, text);
		g_bench_highlighter = highlight::create(mem, &g_bench_table, "bench.c3");
		g_bench_highlighter.ensure_parsed();
		g_bench_highlight_ready = true;
	}
}

fn void bench_hit_test() @benchmark
{
	ensure_bench_project();
	g_bench_counter++;
	RLVector2 point = {
		.x = (float)(g_bench_counter * 37 % 4000),
		.y = (float)(g_bench_counter * 91 % 4000),
	};
	(void)g_bench_project.hit_test(point);
}

fn void bench_content_bounds_cached() @benchmark
{
	ensure_bench_project();
	Rect out;
	(void)g_bench_project.content_bounds(&out);
}

fn void bench_content_bounds_uncached() @benchmark
{
	ensure_bench_project();
	g_bench_project.invalidate_bounds();
	Rect out;
	(void)g_bench_project.content_bounds(&out);
}

fn void bench_runs_for_line() @benchmark
{
	ensure_bench_highlight();
	usz lines = g_bench_table.line_count();
	g_bench_highlighter.begin_runs();
	for (usz line = 0; line + 1 < lines; line++)
	{
		usz start = g_bench_table.line_start(line);
		usz end   = g_bench_table.line_start(line + 1);
		g_bench_highlighter.runs_for_line(start, end, &g_bench_runs);
	}
}