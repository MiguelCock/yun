module yun::index_cache;

import libc;
import std::core::dstring;
import std::core::mem::alloc;
import std::hash::crc64;
import std::io::file;
import std::io::path;
import yun::version;

const uint CACHE_FORMAT_VERSION = 1;
const uint CACHE_QUERY_VERSION  = 1;

fn ulong query_stamp()
{
	Crc64 crc;
	crc.init(0);
	crc.update(version::APP_VERSION);
	char[4] version = {
		(char)CACHE_FORMAT_VERSION,
		(char)(CACHE_FORMAT_VERSION >> 8),
		(char)CACHE_QUERY_VERSION,
		(char)(CACHE_QUERY_VERSION >> 8),
	};
	crc.update(version[0:4]);
	return crc.final();
}

struct ByteReader
{
	char[] data;
	usz pos;
}

fn void ByteReader.init(&self, char[] data)
{
	self.data = data;
	self.pos = 0;
}

fn usz ByteReader.remaining(&self)
{
	return self.data.len > self.pos ? self.data.len - self.pos : 0;
}

fn bool ByteReader.bytes(&self, usz count, char[]* out)
{
	if (count > self.remaining()) return false;
	*out = self.data[self.pos:count];
	self.pos += count;
	return true;
}

fn bool ByteReader.u8(&self, char* out)
{
	if (self.pos >= self.data.len) return false;
	*out = self.data[self.pos];
	self.pos++;
	return true;
}

fn bool ByteReader.read_u16(&self, ushort* out)
{
	if (self.remaining() < 2) return false;
	*out = (ushort)(((ushort)(self.data[self.pos] & 0xFF)) | ((ushort)(self.data[self.pos + 1] & 0xFF) << 8));
	self.pos += 2;
	return true;
}

fn bool ByteReader.read_u32(&self, uint* out)
{
	if (self.remaining() < 4) return false;
	*out = ((uint)(self.data[self.pos] & 0xFF)) | ((uint)(self.data[self.pos + 1] & 0xFF) << 8)
		| ((uint)(self.data[self.pos + 2] & 0xFF) << 16)
		| ((uint)(self.data[self.pos + 3] & 0xFF) << 24);
	self.pos += 4;
	return true;
}

fn bool ByteReader.read_u64(&self, ulong* out)
{
	if (self.remaining() < 8) return false;
	ulong value = 0;
	for (int i = 0; i < 8; i++)
	{
		value |= (ulong)(self.data[self.pos + (usz)i] & 0xFF) << (i * 8);
	}
	self.pos += 8;
	*out = value;
	return true;
}

fn bool ByteReader.varint(&self, ulong* out)
{
	ulong value = 0;
	uint shift  = 0;
	for (int i = 0; i < 10; i++)
	{
		char byte;
		if (!self.u8(&byte)) return false;
		value |= ((ulong)(uint)(byte & 0x7F)) << shift;
		if ((byte & 0x80) == 0)
		{
			*out = value;
			return true;
		}
		shift += 7;
	}
	return false;
}

fn bool ByteReader.string(&self, Allocator allocator, String* out)
{
	ulong length;
	if (!self.varint(&length)) return false;
	if (length > (ulong)self.remaining()) return false;
	char[] bytes;
	if (!self.bytes((usz)length, &bytes)) return false;
	*out = bytes.len == 0 ? "" : ((String)bytes).copy(allocator);
	return true;
}

fn void write_u8(DString* out, char value)
{
	out.append_char(value);
}

fn void write_u16(DString* out, ushort value)
{
	out.append_char((char)(value & 0xFF));
	out.append_char((char)((value >> 8) & 0xFF));
}

fn void write_u32(DString* out, uint value)
{
	for (int i = 0; i < 4; i++) out.append_char((char)((value >> (i * 8)) & 0xFF));
}

fn void write_u64(DString* out, ulong value)
{
	for (int i = 0; i < 8; i++) out.append_char((char)((value >> (i * 8)) & 0xFF));
}

fn void write_varint(DString* out, ulong value)
{
	while (value >= 0x80)
	{
		out.append_char((char)((value & 0x7F) | 0x80));
		value >>= 7;
	}
	out.append_char((char)value);
}

fn void write_string(DString* out, String value)
{
	write_varint(out, (ulong)value.len);
	out.append_bytes(value.ptr[0:value.len]);
}

struct CacheFile
{
	char[] data;
	ByteReader reader;
	uint records;
}

fn void CacheFile.destroy(&self, Allocator allocator)
{
	if (self.data.len > 0) alloc::free(allocator, self.data);
	self.data = { };
	self.reader.data = { };
	self.records = 0;
}

fn bool load_file(Allocator allocator, String path, String magic, ulong expected_stamp, CacheFile* out)
{
	char[]? loaded = file::load(allocator, path);
	if (catch err = loaded) return false;
	char[] data = loaded;
	ByteReader header;
	header.init(data);
	char[] read_magic;
	ushort format;
	ushort flags;
	ulong stamp;
	uint records;
	ulong payload_crc;
	if (!header.bytes(
		8,
		&read_magic
	) || ((String)read_magic).compare_to(
		magic
	) != 0 || !header.read_u16(
		&format
	) || format != CACHE_FORMAT_VERSION || !header.read_u16(
		&flags
	) || flags != 0 || !header.read_u64(
		&stamp
	) || stamp != expected_stamp || !header.read_u32(&records) || !header.read_u64(&payload_crc))
	{
		alloc::free(allocator, data);
		return false;
	}
	char[] payload = data[header.pos:data.len - header.pos];
	if (crc64::hash(payload) != payload_crc)
	{
		alloc::free(allocator, data);
		return false;
	}
	out.data = data;
	out.reader.init(payload);
	out.records = records;
	return true;
}

fn bool save_file(Allocator allocator, String path, String magic, ulong stamp, uint records, char[] payload)
{
	DString out;
	out.init(allocator, 64 + (sz)payload.len);
	out.append_bytes(magic.ptr[0:magic.len]);
	write_u16(&out, (ushort)CACHE_FORMAT_VERSION);
	write_u16(&out, 0);
	write_u64(&out, stamp);
	write_u32(&out, records);
	write_u64(&out, crc64::hash(payload));
	out.append_bytes(payload);
	defer out.free();
	@pool()
	{
		String temp     = string::format(tmem, "%s.tmp", path);
		String out_view = out.str_view();
		if (catch err = file::save((Path)temp, out_view.ptr[0:out_view.len])) return false;
		ZString temp_z = temp.zstr_tcopy();
		ZString path_z = path.zstr_tcopy();
		if (libc::rename(temp_z, path_z) != 0) return false;
	};
	return true;
}