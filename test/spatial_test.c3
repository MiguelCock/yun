module yun::spatial @test;

import raylib6::rl;
import std::collections::list;
import std::math::geometry;

fn void test_point_query()
{
	Grid g;
	g.init(tmem, 100.0f);
	Rect a = { .x = 0.0f, .y = 0.0f, .width = 50.0f, .height = 50.0f };
	Rect b = { .x = 500.0f, .y = 500.0f, .width = 50.0f, .height = 50.0f };
	g.insert(a, 7);
	g.insert(b, 9);

	List{int} out;
	out.init(tmem);
	g.query_point({ 10.0f, 10.0f }, &out);
	assert(out.len() == 1 && out[0] == 7);
	out.clear();
	g.query_point({ 510.0f, 510.0f }, &out);
	assert(out.len() == 1 && out[0] == 9);
	out.clear();
	g.query_point({ 250.0f, 250.0f }, &out);
	assert(out.len() == 0);
	g.destroy();
}

fn void test_rect_query_dedupes()
{
	Grid g;
	g.init(tmem, 64.0f);
	Rect wide  = { .x = 0.0f, .y = 0.0f, .width = 300.0f, .height = 20.0f };
	Rect small = { .x = 10.0f, .y = 0.0f, .width = 20.0f, .height = 20.0f };
	g.insert(wide, 3);
	g.insert(small, 4);

	List{int} out;
	out.init(tmem);
	Rect query = { .x = -50.0f, .y = -50.0f, .width = 500.0f, .height = 200.0f };
	g.query_rect(query, &out);
	for (sz i = 0; i < out.len(); i++)
	{
		for (sz j = i + 1; j < out.len(); j++) assert(out[i] != out[j]);
	}
	assert(out.len() == 2);
	g.destroy();
}

fn void test_clear_reuses_buckets()
{
	Grid g;
	g.init(tmem, 64.0f);
	Rect r = { .x = 0.0f, .y = 0.0f, .width = 10.0f, .height = 10.0f };
	g.insert(r, 1);
	g.clear();

	List{int} out;
	out.init(tmem);
	Rect query = { .x = -10.0f, .y = -10.0f, .width = 100.0f, .height = 100.0f };
	g.query_rect(query, &out);
	assert(out.len() == 0);

	out.clear();
	g.insert(r, 2);
	g.query_point({ 5.0f, 5.0f }, &out);
	assert(out.len() == 1 && out[0] == 2);
	g.destroy();
}