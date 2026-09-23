module yun::lsp::fake;

import std::collections::list;
import yun::lsp;

struct FakeTransport
{
	Allocator allocator;
	List{String} written;
	bool alive;
}

fn void fake_init(FakeTransport* fake, Allocator allocator)
{
	fake.allocator = allocator;
	fake.written.init(allocator);
	fake.alive = true;
}

fn void fake_free(FakeTransport* fake)
{
	for (sz i = 0; i < fake.written.len(); i++)
	{
		fake.written[i].free(fake.allocator);
	}
	fake.written.free();
}

fn bool fake_write(void* ctx, char[] bytes)
{
	FakeTransport* fake = (FakeTransport*)ctx;
	fake.written.push(((String)bytes).copy(fake.allocator));
	return true;
}

fn sz? fake_read(void* ctx, char* buffer, sz size)
{
	(void)ctx;
	(void)buffer;
	(void)size;
	return 0;
}

fn bool fake_alive(void* ctx)
{
	FakeTransport* fake = (FakeTransport*)ctx;
	return fake.alive;
}

fn void fake_close(void* ctx)
{
	(void)ctx;
}

fn LspTransport fake_transport(FakeTransport* fake)
{
	return {
		.ctx = fake,
		.write = &fake_write,
		.read = &fake_read,
		.is_alive = &fake_alive,
		.close = &fake_close,
	};
}