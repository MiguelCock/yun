module yun::index_cache @test;

import std::core::dstring;
import std::io::file;
import std::io::path;

fn void test_varint_roundtrip()
{
	DString out;
	out.init(mem, 64);
	ulong[] values = { 0, 1, 127, 128, 300, 16384, 0xFFFF_FFFF };
	for (usz i = 0; i < values.len; i++) write_varint(&out, values[i]);
	String view = out.str_view();
	ByteReader reader;
	reader.init(view.ptr[0:view.len]);
	for (usz i = 0; i < values.len; i++)
	{
		ulong value;
		assert(reader.varint(&value));
		assert(value == values[i]);
	}
	assert(reader.remaining() == 0);
	out.free();
}

fn void test_string_and_scalars_roundtrip()
{
	DString out;
	out.init(mem, 128);
	write_u8(&out, (char)0xAB);
	write_u16(&out, 0xBEEF);
	write_u32(&out, 0xDEADBEEF);
	write_u64(&out, 0x0123456789ABCDEF);
	write_string(&out, "hello");
	write_string(&out, "caminho/ção.c3");
	String view = out.str_view();
	ByteReader reader;
	reader.init(view.ptr[0:view.len]);
	char a;
	ushort b;
	uint c;
	ulong d;
	String first;
	String second;
	assert(reader.u8(&a) && a == (char)0xAB);
	assert(reader.read_u16(&b) && b == 0xBEEF);
	assert(reader.read_u32(&c) && c == 0xDEADBEEF);
	assert(reader.read_u64(&d) && d == 0x0123456789ABCDEF);
	assert(reader.string(mem, &first) && first.compare_to("hello") == 0);
	assert(reader.string(mem, &second) && second.compare_to("caminho/ção.c3") == 0);
	first.free(mem);
	second.free(mem);
	out.free();
}

fn void test_cache_file_roundtrip()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? dir = tmp.append(tmem, "yun_index_cache");
		if (catch excuse = dir) return;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? file_path = dir.append(tmem, "index.bin");
		if (catch excuse = file_path) return;

		DString body;
		body.init(mem, 64);
		write_string(&body, "src/main.c3");
		write_u64(&body, 123456789);
		write_varint(&body, 42);
		String view = body.str_view();
		assert(save_file(mem, (String)file_path, "YUNIMPT1", query_stamp(), 1, view.ptr[0:view.len]));

		CacheFile cache;
		assert(load_file(mem, (String)file_path, "YUNIMPT1", query_stamp(), &cache));
		assert(cache.records == 1);
		String path_value;
		ulong stamp;
		ulong number;
		assert(cache.reader.string(mem, &path_value));
		assert(path_value.compare_to("src/main.c3") == 0);
		assert(cache.reader.read_u64(&stamp) && stamp == 123456789);
		assert(cache.reader.varint(&number) && number == 42);
		assert(cache.reader.remaining() == 0);
		path_value.free(mem);
		cache.destroy(mem);
		body.free();
		(void)path::rmtree(dir);
	};
}

fn void test_cache_rejects_wrong_header()
{
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch excuse = tmp) return;
		Path? dir = tmp.append(tmem, "yun_index_cache_bad");
		if (catch excuse = dir) return;
		(void)path::rmtree(dir);
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? file_path = dir.append(tmem, "index.bin");
		if (catch excuse = file_path) return;

		DString body;
		body.init(mem, 16);
		write_varint(&body, 7);
		String view = body.str_view();
		assert(save_file(mem, (String)file_path, "YUNIMPT1", query_stamp(), 1, view.ptr[0:view.len]));

		CacheFile wrong_magic;
		assert(!load_file(mem, (String)file_path, "YUNSYMT1", query_stamp(), &wrong_magic));
		CacheFile wrong_stamp;
		assert(!load_file(mem, (String)file_path, "YUNIMPT1", query_stamp() + 1, &wrong_stamp));

		CacheFile cache;
		assert(load_file(mem, (String)file_path, "YUNIMPT1", query_stamp(), &cache));
		cache.data[32] ^= 1;
		(void)file::save(file_path, cache.data[0:cache.data.len]);
		cache.destroy(mem);
		CacheFile corrupt;
		assert(!load_file(mem, (String)file_path, "YUNIMPT1", query_stamp(), &corrupt));
		body.free();
		(void)path::rmtree(dir);
	};
}