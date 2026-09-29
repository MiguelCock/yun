module yun::spatial;

import raylib6::rl;
import std::collections::list;
import std::collections::map;
import std::math;

const float CELL_SIZE = 512.0f;

struct Bucket
{
	List{int} items;
}

struct Grid
{
	Allocator allocator;
	float cell;
	HashMap{long, int} lookup;
	List{Bucket} buckets;
	sz active;
	List{uint} stamp;
	uint generation;
}

fn long cell_key(int cx, int cy)
{
	return ((long)cx << 32) | (long)(uint)cy;
}

fn void Grid.init(&self, Allocator allocator, float cell)
{
	self.allocator = allocator;
	self.cell = cell > 1.0f ? cell : 1.0f;
	self.lookup.init(allocator);
	self.buckets.init(allocator);
	self.active = 0;
	self.stamp.init(allocator);
	self.generation = 0;
}

fn void Grid.destroy(&self)
{
	for (sz i = 0; i < self.buckets.len(); i++) self.buckets[i].items.free();
	self.buckets.free();
	self.lookup.free();
	self.stamp.free();
}

fn void Grid.clear(&self)
{
	for (sz i = 0; i < self.active; i++) self.buckets[i].items.clear();
	self.lookup.clear();
	self.active = 0;
}

fn int Grid.bucket_for(&self, int cx, int cy)
{
	long key    = cell_key(cx, cy);
	int*? found = self.lookup.get_ref(key);
	if (catch excuse = found)
	{
		// Not present yet: fall through and create a bucket.
	}
	else
	{
		return *found;
	}
	int index;
	if (self.active < self.buckets.len())
	{
		index = (int)self.active;
		self.buckets[index].items.clear();
	}
	else
	{
		Bucket bucket = { .items = { } };
		bucket.items.init(self.allocator);
		self.buckets.push(bucket);
		index = (int)(self.buckets.len() - 1);
	}
	self.active++;
	self.lookup.set(key, index);
	return index;
}

fn void Grid.insert(&self, Rect rect, int value)
{
	if (rect.width <= 0.0f || rect.height <= 0.0f) return;
	int cx0 = (int)math::floor(rect.x / self.cell);
	int cy0 = (int)math::floor(rect.y / self.cell);
	int cx1 = (int)math::floor((rect.x + rect.width - 0.001f) / self.cell);
	int cy1 = (int)math::floor((rect.y + rect.height - 0.001f) / self.cell);
	for (int cy = cy0; cy <= cy1; cy++)
	{
		for (int cx = cx0; cx <= cx1; cx++)
		{
			self.buckets[self.bucket_for(cx, cy)].items.push(value);
		}
	}
}

fn void Grid.query_point(&self, RLVector2 world, List{int}* out)
{
	int cx      = (int)math::floor(world[0] / self.cell);
	int cy      = (int)math::floor(world[1] / self.cell);
	int*? found = self.lookup.get_ref(cell_key(cx, cy));
	if (catch excuse = found) return;
	List{int} items = self.buckets[*found].items;
	for (sz i = 0; i < items.len(); i++) out.push(items[i]);
}

fn bool Grid.mark(&self, int value)
{
	if (value < 0) return false;
	usz need = (usz)value + 1;
	while ((usz)self.stamp.len() < need) self.stamp.push(0);
	if (self.stamp[(sz)value] == self.generation) return false;
	self.stamp[(sz)value] = self.generation;
	return true;
}

fn void Grid.query_rect(&self, Rect rect, List{int}* out)
{
	if (rect.width <= 0.0f || rect.height <= 0.0f) return;
	self.generation++;
	if (self.generation == 0)
	{
		for (sz i = 0; i < self.stamp.len(); i++) self.stamp[i] = 0;
		self.generation = 1;
	}
	int cx0 = (int)math::floor(rect.x / self.cell);
	int cy0 = (int)math::floor(rect.y / self.cell);
	int cx1 = (int)math::floor((rect.x + rect.width) / self.cell);
	int cy1 = (int)math::floor((rect.y + rect.height) / self.cell);
	for (int cy = cy0; cy <= cy1; cy++)
	{
		for (int cx = cx0; cx <= cx1; cx++)
		{
			int*? found = self.lookup.get_ref(cell_key(cx, cy));
			if (catch excuse = found) continue;
			List{int} items = self.buckets[*found].items;
			for (sz i = 0; i < items.len(); i++)
			{
				int value = items[i];
				if (!self.mark(value)) continue;
				out.push(value);
			}
		}
	}
}