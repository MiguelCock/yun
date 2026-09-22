module yun::text;

import libc;
import std::collections::list;
import std::core::dstring;
import std::io::file;
import std::io::file::mmap;
import std::math;

enum PieceSource
{
	ORIGINAL,
	ADD,
}

struct Piece
{
	PieceSource source;
	usz start;
	usz length;
}

struct Edit
{
	usz start_byte;
	usz old_end_byte;
	usz new_end_byte;
}

struct PieceTable
{
	FileMmap mmap;
	bool has_mmap;
	bool owns_original;
	String owned_original;
	char[] original;
	DString add;
	List{Piece} pieces;
	List{usz} line_starts;
	Allocator allocator;
	usz total;
}

fn void PieceTable.init_empty(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.has_mmap = false;
	self.owns_original = false;
	self.owned_original = "";
	self.original = { };
	self.add.init(allocator);
	self.pieces.init(allocator);
	self.line_starts.init(allocator);
	self.line_starts.push(0);
	self.total = 0;
}

fn void PieceTable.init_from_buffer(&self, Allocator allocator, String text)
{
	self.init_empty(allocator);
	if (text.len == 0) return;
	self.owned_original = text.copy(allocator);
	self.owns_original = true;
	self.original = self.owned_original.ptr[0:self.owned_original.len];
	self.pieces.push({ .source = PieceSource.ORIGINAL, .start = 0, .length = self.original.len });
	self.total = self.original.len;
	self.rebuild_line_index();
}

fn bool PieceTable.init_from_file(&self, Allocator allocator, String path)
{
	self.init_empty(allocator);
	long? size = file::get_size(path);
	if (catch excuse = size) return false;
	if (size == 0) return true;

	FileMmap? mapped = file::mmap_open(path, "rb");
	if (catch excuse = mapped) return false;
	self.mmap = mapped;
	self.has_mmap = true;
	self.original = self.mmap.bytes();
	self.pieces.push({ .source = PieceSource.ORIGINAL, .start = 0, .length = self.original.len });
	self.total = self.original.len;
	self.rebuild_line_index();
	return true;
}

fn void PieceTable.destroy(&self)
{
	if (self.has_mmap) (void)self.mmap.destroy();
	if (self.owns_original) self.owned_original.free(self.allocator);
	self.add.free();
	self.pieces.free();
	self.line_starts.free();
}

fn usz PieceTable.length(&self)
{
	return self.total;
}

fn char[] PieceTable.piece_bytes(&self, Piece piece)
{
	if (piece.source == PieceSource.ORIGINAL) return self.original[piece.start:piece.length];
	return self.add.str_view().ptr[piece.start:piece.length];
}

fn sz PieceTable.find_piece(&self, usz offset, usz* within)
{
	usz acc = 0;
	for (sz i = 0; i < self.pieces.len(); i++)
	{
		Piece piece = self.pieces[i];
		if (offset < acc + piece.length)
		{
			*within = offset - acc;
			return i;
		}
		acc += piece.length;
	}
	*within = 0;
	return -1;
}

fn char PieceTable.byte_at(&self, usz offset)
{
	if (offset >= self.total) return 0;
	usz within = 0;
	sz index   = self.find_piece(offset, &within);
	if (index < 0) return 0;
	Piece piece = self.pieces[index];
	if (piece.source == PieceSource.ORIGINAL) return self.original[piece.start + within];
	return self.add.str_view().ptr[piece.start + within];
}

fn char PieceTable.char_at(&self, usz offset)
{
	return self.byte_at(offset);
}

fn void PieceTable.split_at(&self, usz pos)
{
	if (pos == 0 || pos >= self.total) return;
	usz within = 0;
	sz index   = self.find_piece(pos, &within);
	if (index < 0) return;
	Piece piece = self.pieces[index];
	if (within == 0 || within == piece.length) return;
	self.pieces.get_ref(index).length = within;
	self.pieces.insert_at(
		index + 1,
		{
			.source = piece.source,
			.start = piece.start + within,
			.length = piece.length - within,
		}
	);
}

fn void PieceTable.merge_pieces(&self)
{
	sz i = 0;
	while (i + 1 < self.pieces.len())
	{
		Piece a = self.pieces[i];
		Piece b = self.pieces[i + 1];
		if (a.source == b.source && a.start + a.length == b.start)
		{
			self.pieces.get_ref(i).length = a.length + b.length;
			self.pieces.remove_at(i + 1);
		}
		else
		{
			i++;
		}
	}
}

fn Edit PieceTable.insert(&self, usz offset, String text)
{
	Edit edit = { .start_byte = offset, .old_end_byte = offset, .new_end_byte = offset + text.len };
	if (text.len == 0) return edit;

	usz add_start = (usz)self.add.len();
	self.add.append_bytes(text.ptr[0:text.len]);

	usz within = 0;
	sz index   = self.find_piece(offset, &within);
	if (index < 0)
	{
		self.pieces.push({ .source = PieceSource.ADD, .start = add_start, .length = text.len });
	}
	else
	{
		Piece piece = self.pieces[index];
		if (within == 0)
		{
			self.pieces.insert_at(index, { .source = PieceSource.ADD, .start = add_start, .length = text.len });
		}
		else if (within == piece.length)
		{
			self.pieces.insert_at(index + 1, { .source = PieceSource.ADD, .start = add_start, .length = text.len });
		}
		else
		{
			self.pieces.get_ref(index).length = within;
			self.pieces.insert_at(index + 1, { .source = PieceSource.ADD, .start = add_start, .length = text.len });
			self.pieces.insert_at(
				index + 2,
				{
					.source = piece.source,
					.start = piece.start + within,
					.length = piece.length - within,
				}
			);
		}
	}

	self.total += text.len;
	self.merge_pieces();
	self.index_insert(offset, text);
	return edit;
}

fn Edit PieceTable.delete(&self, usz offset, usz del_len)
{
	Edit edit = { .start_byte = offset, .old_end_byte = offset + del_len, .new_end_byte = offset };
	if (del_len == 0) return edit;

	usz end = offset + del_len;
	self.split_at(end);
	self.split_at(offset);

	usz acc  =  0;
	sz first = -1;
	sz last  = -1;
	for (sz i = 0; i < self.pieces.len(); i++)
	{
		usz piece_start = acc;
		usz piece_end   = acc + self.pieces[i].length;
		if (piece_end <= offset)
		{
			acc = piece_end;
			continue;
		}
		if (piece_start >= end) break;
		if (first < 0) first = i;
		last = i;
		acc = piece_end;
	}
	if (first >= 0)
	{
		for (sz i = last; i >= first; i--) self.pieces.remove_at(i);
	}

	self.total -= del_len;
	self.merge_pieces();
	self.index_delete(offset, del_len);
	return edit;
}

fn String PieceTable.slice(&self, usz offset, usz len, Allocator allocator)
{
	DString out;
	out.init(allocator, (sz)(len + 1));

	usz remaining = len;
	usz pos       = offset;
	while (remaining > 0)
	{
		usz within = 0;
		sz index   = self.find_piece(pos, &within);
		if (index < 0) break;
		Piece piece = self.pieces[index];
		usz take    = math::min(piece.length - within, remaining);
		if (take == 0) break;
		char[] bytes = self.piece_bytes(piece);
		out.append_bytes(bytes[within:take]);
		pos += take;
		remaining -= take;
	}

	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn bool PieceTable.save_to_file(&self, String path, Allocator allocator)
{
	@pool()
	{
		String data = self.slice(0, self.total, allocator);
		defer data.free(allocator);

		String tmp = string::format(allocator, "%s.yun-tmp", path);
		defer tmp.free(allocator);

		if (catch excuse = file::save(tmp, data)) return false;
		if (libc::rename(tmp.zstr_tcopy(), path.zstr_tcopy()) != 0)
		{
			(void)libc::remove(tmp.zstr_tcopy());
			return false;
		}
		return true;
	};
}

fn usz utf8_char_len(char lead)
{
	int b = (int)lead & 0xFF;
	if (b < 0x80) return 1;
	if ((b & 0xE0) == 0xC0) return 2;
	if ((b & 0xF0) == 0xE0) return 3;
	if ((b & 0xF8) == 0xF0) return 4;
	return 1;
}

fn usz PieceTable.prev_boundary(&self, usz offset)
{
	usz pos = offset;
	while (pos > 0 && (((int)self.byte_at(pos) & 0xC0) == 0x80)) pos--;
	return pos;
}

fn usz PieceTable.next_boundary(&self, usz offset)
{
	if (offset >= self.total) return self.total;
	usz pos = offset + 1;
	while (pos < self.total && (((int)self.byte_at(pos) & 0xC0) == 0x80)) pos++;
	return pos;
}

fn void PieceTable.rebuild_line_index(&self)
{
	self.line_starts.clear();
	self.line_starts.push(0);
	for (usz i = 0; i < self.total; i++)
	{
		if (self.byte_at(i) == '\n') self.line_starts.push(i + 1);
	}
}

fn sz PieceTable.line_start_insert_pos(&self, usz pos)
{
	sz lo = 0;
	sz hi = self.line_starts.len();
	while (lo < hi)
	{
		sz mid = (lo + hi) / 2;
		if (self.line_starts[mid] > pos)
		{
			hi = mid;
		}
		else
		{
			lo = mid + 1;
		}
	}
	return lo;
}

fn void PieceTable.index_insert(&self, usz offset, String text)
{
	for (sz i = 0; i < self.line_starts.len(); i++)
	{
		usz value = self.line_starts[i];
		if (value > offset) *self.line_starts.get_ref(i) = value + text.len;
	}
	for (usz r = 0; r < text.len; r++)
	{
		if (text[r] == '\n')
		{
			usz pos = offset + r + 1;
			self.line_starts.insert_at(self.line_start_insert_pos(pos), pos);
		}
	}
}

fn void PieceTable.index_delete(&self, usz offset, usz del_len)
{
	usz end = offset + del_len;
	for (sz i = self.line_starts.len(); i > 0; i--)
	{
		usz value = self.line_starts[i - 1];
		if (value > offset && value <= end) self.line_starts.remove_at(i - 1);
	}
	for (sz i = 0; i < self.line_starts.len(); i++)
	{
		usz value = self.line_starts[i];
		if (value > end) *self.line_starts.get_ref(i) = value - del_len;
	}
}

fn usz PieceTable.line_count(&self)
{
	return (usz)self.line_starts.len();
}

fn usz PieceTable.line_start(&self, usz line)
{
	if (line >= (usz)self.line_starts.len()) return self.total;
	return self.line_starts[(sz)line];
}

fn usz PieceTable.line_of(&self, usz offset)
{
	usz lo = 0;
	usz hi = (usz)self.line_starts.len() - 1;
	while (lo < hi)
	{
		usz mid = (lo + hi + 1) / 2;
		if (self.line_starts[(sz)mid] <= offset)
		{
			lo = mid;
		}
		else
		{
			hi = mid - 1;
		}
	}
	return lo;
}

fn usz PieceTable.offset_of(&self, usz line, usz column)
{
	usz count = (usz)self.line_starts.len();
	if (line >= count) return self.total;
	usz start = self.line_starts[(sz)line];
	usz end   = line + 1 < count ? self.line_starts[(sz)(line + 1)] : self.total;
	usz pos   = start + column;
	if (pos > end) pos = end;
	return pos;
}