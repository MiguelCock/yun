module yun::markdown;

import raylib6::rl;
import std::collections::list;
import std::core::dstring;
import std::core::mem::alloc;
import std::math;
import yun::highlight;
import yun::language;
import yun::text;
import yun::theme;
import yun::ui;

const float[] HEADING_SCALE = { 1.7f, 1.45f, 1.25f, 1.12f, 1.05f, 1.0f };
const float BLOCK_GAP       = 0.5f;
const float CODE_PAD        = 8.0f;
const float QUOTE_INDENT    = 14.0f;
const float LIST_INDENT     = 16.0f;

enum MdBlockKind : int
{
	HEADING,
	PARAGRAPH,
	LIST_ITEM,
	CODE,
	QUOTE,
	RULE,
}

enum MdStyle : int
{
	TEXT,
	HEADING,
	STRONG,
	EM,
	CODE,
	LINK,
	QUOTE,
}

enum MdRectKind : int
{
	CODE_BG,
	QUOTE_BAR,
	BULLET,
	RULE,
}

struct MdBlock
{
	MdBlockKind kind;
	int level;
	bool ordered;
	int index;
	String text;
	String language;
	uint start;
	uint end;
}

struct MdDocument
{
	Allocator allocator;
	List{MdBlock} blocks;
}

struct MdInline
{
	String text;
	MdStyle style;
}

struct MdRun
{
	String text;
	float x;
	float y;
	float size;
	MdStyle style;
	bool bold;
	uint src_start;
	uint src_end;
}

struct MdRect
{
	Rect rect;
	MdRectKind kind;
}

struct MdAnchor
{
	float y;
	uint offset;
}

struct MdLayout
{
	Allocator allocator;
	List{MdRun} runs;
	List{MdRect} rects;
	List{MdAnchor} anchors;
	float height;
}

struct View
{
	Allocator allocator;
	MdDocument* doc;
	MdLayout* layout;
	float layout_width;
	float layout_char_width;
	float layout_font_size;
	bool dirty;
}

fn bool is_markdown_path(String path)
{
	return language::language_for_path(path) == language::Language.MARKDOWN;
}

fn usz line_end_at(String text, usz start)
{
	usz i = start;
	while (i < text.len && text[i] != '\n') i++;
	return i;
}

fn String trim_view(String s)
{
	usz start = 0;
	usz end   = s.len;
	while (start < end && (s[start] == ' ' || s[start] == '\t' || s[start] == '\r')) start++;
	while (end > start && (s[end - 1] == ' ' || s[end - 1] == '\t' || s[end - 1] == '\r')) end--;
	return s[start:end - start];
}

fn bool is_blank(String s)
{
	for (usz i = 0; i < s.len; i++)
	{
		char c = s[i];
		if (c != ' ' && c != '\t' && c != '\r') return false;
	}
	return true;
}

fn int heading_level(String line, usz* content_start)
{
	usz i = 0;
	while (i < line.len && line[i] == '#') i++;
	if (i == 0 || i > 6) return 0;
	if (i < line.len && line[i] != ' ' && line[i] != '\t') return 0;
	usz c = i;
	while (c < line.len && (line[c] == ' ' || line[c] == '\t')) c++;
	*content_start = c;
	return (int)i;
}

fn bool is_thematic_break(String s)
{
	char marker = 0;
	int count   = 0;
	for (usz i = 0; i < s.len; i++)
	{
		char c = s[i];
		if (c == ' ' || c == '\t' || c == '\r') continue;
		if (marker == 0)
		{
			if (c != '-' && c != '*' && c != '_') return false;
			marker = c;
		}
		else if (c != marker)
		{
			return false;
		}
		count++;
	}
	return count >= 3;
}

fn bool fence_start(String s, char* fence_char, int* fence_len, String* info)
{
	String t = trim_view(s);
	if (t.len < 3) return false;
	char c = t[0];
	if (c != '`' && c != '~') return false;
	usz i = 0;
	while (i < t.len && t[i] == c) i++;
	if (i < 3) return false;
	*fence_char = c;
	*fence_len = (int)i;
	*info = trim_view(t[i:t.len - i]);
	return true;
}

fn bool fence_end(String s, char fence_char, int fence_len)
{
	String t = trim_view(s);
	usz i    = 0;
	while (i < t.len && t[i] == fence_char) i++;
	if ((int)i < fence_len) return false;
	while (i < t.len)
	{
		if (t[i] != ' ' && t[i] != '\t') return false;
		i++;
	}
	return true;
}

fn bool list_marker(String s, bool* ordered, int* index, usz* content_start, int* indent)
{
	usz i   = 0;
	int ind = 0;
	while (i < s.len && (s[i] == ' ' || s[i] == '\t'))
	{
		ind += (s[i] == '\t') ? 4 : 1;
		i++;
	}
	if (i >= s.len) return false;
	char c = s[i];
	if ((c == '-' || c == '*' || c == '+') && i + 1 < s.len && (s[i + 1] == ' ' || s[i + 1] == '\t'))
	{
		usz j = i + 1;
		while (j < s.len && (s[j] == ' ' || s[j] == '\t')) j++;
		*ordered = false;
		*index = 0;
		*indent = ind;
		*content_start = j;
		return true;
	}
	usz j = i;
	while (j < s.len && s[j] >= '0' && s[j] <= '9') j++;
	if (j > i && j < s.len && (s[j] == '.' || s[j] == ')') && j + 1 < s.len && (s[j + 1] == ' ' || s[j + 1] == '\t'))
	{
		int n = 0;
		for (usz k = i; k < j; k++) n = n * 10 + (int)(s[k] - '0');
		usz k2 = j + 1;
		while (k2 < s.len && (s[k2] == ' ' || s[k2] == '\t')) k2++;
		*ordered = true;
		*index = n;
		*indent = ind;
		*content_start = k2;
		return true;
	}
	return false;
}

fn void push_block(
	MdDocument* doc,
	MdBlockKind kind,
	int level,
	bool ordered,
	int index,
	String text,
	String language,
	uint start,
	uint end
)
{
	MdBlock b;
	b.kind = kind;
	b.level = level;
	b.ordered = ordered;
	b.index = index;
	b.text = text.copy(doc.allocator);
	b.language = language.copy(doc.allocator);
	b.start = start;
	b.end = end;
	doc.blocks.push(b);
}

fn void flush_paragraph(MdDocument* doc, DString* para, uint* start, bool* have)
{
	if (!*have) return;
	push_block(doc, MdBlockKind.PARAGRAPH, 0, false, 0, para.str_view(), "", *start, *start + (uint)para.len());
	para.clear();
	*have = false;
}

fn MdDocument* parse(Allocator allocator, String text)
{
	MdDocument* doc = alloc::new(allocator, MdDocument);
	doc.allocator = allocator;
	doc.blocks.init(allocator);

	DString para;
	para.init(allocator, 128);
	uint para_start = 0;
	bool have_para  = false;

	usz i = 0;
	while (i < text.len)
	{
		usz e       = line_end_at(text, i);
		String line = text[i:e - i];
		uint off    = (uint)i;
		usz next    = e < text.len ? e + 1 : e;

		char fc;
		int fl;
		String info;
		if (fence_start(line, &fc, &fl, &info))
		{
			flush_paragraph(doc, &para, &para_start, &have_para);
			DString code;
			code.init(allocator, 128);
			uint content_start = (uint)next;
			uint content_end   = content_start;
			usz j              = next;
			while (j < text.len)
			{
				usz je    = line_end_at(text, j);
				String l2 = text[j:je - j];
				usz after = je < text.len ? je + 1 : je;
				if (fence_end(l2, fc, fl))
				{
					content_end = (uint)j;
					j = after;
					break;
				}
				code.append_string(l2);
				code.append_char('\n');
				content_end = (uint)after;
				j = after;
			}
			push_block(doc, MdBlockKind.CODE, 0, false, 0, code.str_view(), info, content_start, content_end);
			code.free();
			i = j;
			continue;
		}

		if (is_blank(line))
		{
			flush_paragraph(doc, &para, &para_start, &have_para);
			i = next;
			continue;
		}

		usz hs;
		int hl = heading_level(line, &hs);
		if (hl > 0)
		{
			flush_paragraph(doc, &para, &para_start, &have_para);
			push_block(doc, MdBlockKind.HEADING, hl, false, 0, trim_view(line[hs:line.len - hs]), "", off, (uint)e);
			i = next;
			continue;
		}

		if (is_thematic_break(line))
		{
			flush_paragraph(doc, &para, &para_start, &have_para);
			push_block(doc, MdBlockKind.RULE, 0, false, 0, "", "", off, (uint)e);
			i = next;
			continue;
		}

		String t = trim_view(line);
		if (t.len > 0 && t[0] == '>')
		{
			flush_paragraph(doc, &para, &para_start, &have_para);
			DString q;
			q.init(allocator, 64);
			usz k = i;
			while (k < text.len)
			{
				usz ke    = line_end_at(text, k);
				String l2 = text[k:ke - k];
				String t2 = trim_view(l2);
				if (t2.len == 0 || t2[0] != '>') break;
				usz c = 1;
				if (c < t2.len && t2[c] == ' ') c++;
				if (q.len() > 0) q.append_char(' ');
				q.append_string(trim_view(t2[c:t2.len - c]));
				k = ke < text.len ? ke + 1 : ke;
			}
			push_block(doc, MdBlockKind.QUOTE, 1, false, 0, q.str_view(), "", off, (uint)e);
			q.free();
			i = k;
			continue;
		}

		bool ordered;
		int idx;
		usz cs;
		int indent;
		if (list_marker(line, &ordered, &idx, &cs, &indent))
		{
			flush_paragraph(doc, &para, &para_start, &have_para);
			push_block(
				doc,
				MdBlockKind.LIST_ITEM,
				indent / 2 + 1,
				ordered,
				idx,
				trim_view(line[cs:line.len - cs]),
				"",
				off,
				(uint)e
			);
			i = next;
			continue;
		}

		if (!have_para)
		{
			para_start = off;
			have_para = true;
		}
		else
		{
			para.append_char(' ');
		}
		para.append_string(trim_view(line));
		i = next;
	}

	flush_paragraph(doc, &para, &para_start, &have_para);
	para.free();
	return doc;
}

fn void free_document(MdDocument* doc, Allocator allocator)
{
	if (!doc) return;
	for (sz i = 0; i < doc.blocks.len(); i++)
	{
		doc.blocks[i].text.free(allocator);
		doc.blocks[i].language.free(allocator);
	}
	doc.blocks.free();
	alloc::free(allocator, doc);
}

fn usz find_char(String s, usz from, char ch)
{
	usz i = from;
	while (i < s.len)
	{
		if (s[i] == ch) return i;
		i++;
	}
	return s.len;
}

fn usz find_pair(String s, usz from, char a, char b)
{
	usz i = from;
	while (i + 1 < s.len)
	{
		if (s[i] == a && s[i + 1] == b) return i;
		i++;
	}
	return s.len;
}

fn void flush_plain(List{MdInline}* out, String text, usz* plain, usz end)
{
	if (end > *plain) out.push({ .text = text[*plain:end - *plain], .style = MdStyle.TEXT });
	*plain = end;
}

fn void parse_inlines(Allocator allocator, String text, List{MdInline}* out)
{
	out.init(allocator);
	usz i     = 0;
	usz plain = 0;
	while (i < text.len)
	{
		char c = text[i];

		if (c == '`')
		{
			usz close = find_char(text, i + 1, '`');
			if (close < text.len)
			{
				flush_plain(out, text, &plain, i);
				out.push({ .text = text[i + 1:close - i - 1], .style = MdStyle.CODE });
				i = close + 1;
				plain = i;
				continue;
			}
		}

		if ((c == '*' || c == '_') && i + 1 < text.len && text[i + 1] == c)
		{
			usz close = find_pair(text, i + 2, c, c);
			if (close < text.len)
			{
				flush_plain(out, text, &plain, i);
				out.push({ .text = text[i + 2:close - i - 2], .style = MdStyle.STRONG });
				i = close + 2;
				plain = i;
				continue;
			}
		}

		if (c == '*' || c == '_')
		{
			usz close = find_char(text, i + 1, c);
			if (close < text.len)
			{
				flush_plain(out, text, &plain, i);
				out.push({ .text = text[i + 1:close - i - 1], .style = MdStyle.EM });
				i = close + 1;
				plain = i;
				continue;
			}
		}

		if (c == '[')
		{
			usz close = find_char(text, i + 1, ']');
			if (close < text.len && close + 1 < text.len && text[close + 1] == '(')
			{
				usz paren = find_char(text, close + 2, ')');
				if (paren < text.len)
				{
					flush_plain(out, text, &plain, i);
					out.push({ .text = text[i + 1:close - i - 1], .style = MdStyle.LINK });
					i = paren + 1;
					plain = i;
					continue;
				}
			}
		}

		i++;
	}
	flush_plain(out, text, &plain, text.len);
}

fn void add_run(MdLayout* out, String text, float x, float y, float size, MdStyle style, bool bold)
{
	if (text.len == 0) return;
	out.runs.push({ .text = text, .x = x, .y = y, .size = size, .style = style, .bold = bold });
}

fn void layout_inline(
	MdLayout* out,
	List{MdInline}* inlines,
	float x0,
	float* y,
	float cw,
	float lh,
	float size,
	float max_x,
	MdStyle base,
	bool bold
)
{
	float max_cols = (max_x - x0) / cw;
	if (max_cols < 1.0f) max_cols = 1.0f;
	float col      = 0.0f;
	bool line_used = false;

	foreach (MdInline in : inlines)
	{
		MdStyle st = in.style;
		if (base == MdStyle.HEADING && st == MdStyle.TEXT) st = MdStyle.HEADING;
		String s = in.text;
		usz p    = 0;
		while (p < s.len)
		{
			usz ws = p;
			while (p < s.len && s[p] == ' ') p++;
			if (p > ws)
			{
				col += (float)(p - ws);
				if (col > max_cols)
				{
					*y += lh;
					col = 0.0f;
					line_used = false;
				}
			}
			usz w0 = p;
			while (p < s.len && s[p] != ' ') p++;
			if (p == w0) continue;
			String word = s[w0:p - w0];
			float wlen  = (float)word.len;
			if (line_used && col + wlen > max_cols)
			{
				*y += lh;
				col = 0.0f;
				line_used = false;
			}
			if (wlen > max_cols)
			{
				usz off = 0;
				while (off < word.len)
				{
					float room = max_cols - col;
					usz take   = room > 1.0f ? (usz)room : 1;
					if (off + take > word.len) take = word.len - off;
					add_run(out, word[off:take], x0 + col * cw, *y, size, st, bold);
					off += take;
					col += (float)take;
					line_used = true;
					if (off < word.len)
					{
						*y += lh;
						col = 0.0f;
						line_used = false;
					}
				}
			}
			else
			{
				add_run(out, word, x0 + col * cw, *y, size, st, bold);
				col += wlen;
				line_used = true;
			}
		}
	}
	*y += lh;
}

fn void layout_code_block(
	MdLayout* out,
	MdBlock* block,
	float x0,
	float* y,
	float cw,
	float lh,
	float size,
	float max_x
)
{
	float top    = *y;
	float code_x = x0 + CODE_PAD;
	String text  = block.text;
	usz i        = 0;
	uint src     = block.start;
	bool first   = true;
	while (i < text.len)
	{
		usz e = line_end_at(text, i);
		if (!first) *y += lh;
		add_run(out, text[i:e - i], code_x, *y, size, MdStyle.CODE, false);
		out.runs[out.runs.len() - 1].src_start = src;
		out.runs[out.runs.len() - 1].src_end = src + (uint)(e - i);
		src += (uint)(e - i) + 1;
		first = false;
		i = e < text.len ? e + 1 : e;
	}
	*y += lh;
	float bottom = *y;
	out.rects.push(
		{
			.rect = { .x = x0, .y = top, .width = max_x - x0, .height = bottom - top + CODE_PAD },
			.kind = MdRectKind.CODE_BG,
		}
	);
}

fn MdLayout* layout(
	Allocator allocator,
	MdDocument* doc,
	float width,
	float char_width,
	float font_size,
	float line_height
)
{
	MdLayout* out = alloc::new(allocator, MdLayout);
	out.allocator = allocator;
	out.runs.init(allocator);
	out.rects.init(allocator);
	out.anchors.init(allocator);

	float y = 0.0f;
	foreach (MdBlock block : doc.blocks)
	{
		float block_y = y;
		switch (block.kind)
		{
			case MdBlockKind.HEADING:

				{
					float size = font_size * HEADING_SCALE[(block.level - 1) % 6];
					float cw   = char_width * size / font_size;
					float lh   = line_height * size / font_size;
					y += line_height * 0.5f;
					List{MdInline} inlines;
					parse_inlines(allocator, block.text, &inlines);
					layout_inline(out, &inlines, 0.0f, &y, cw, lh, size, width, MdStyle.HEADING, true);
					inlines.free();
					y += line_height * 0.25f;
				}
			case MdBlockKind.PARAGRAPH:

				{
					List{MdInline} inlines;
					parse_inlines(allocator, block.text, &inlines);
					layout_inline(
						out,
						&inlines,
						0.0f,
						&y,
						char_width,
						line_height,
						font_size,
						width,
						MdStyle.TEXT,
						false
					);
					inlines.free();
					y += line_height * BLOCK_GAP;
				}
			case MdBlockKind.LIST_ITEM:

				{
					float indent = LIST_INDENT * (float)block.level;
					if (block.ordered)
					{
						@pool()
						{
							String marker = string::format(tmem, "%d.", block.index);
							add_run(
								out,
								marker.copy(allocator),
								indent - LIST_INDENT + 2.0f,
								y,
								font_size,
								MdStyle.TEXT,
								false
							);
						};
					}
					else
					{
						out.rects.push(
							{
								.rect = {
									.x = indent - LIST_INDENT + 4.0f,
									.y = y + line_height * 0.35f,
									.width = char_width * 0.6f,
									.height = char_width * 0.6f
								},
								.kind = MdRectKind.BULLET,
							}
						);
					}
					List{MdInline} inlines;
					parse_inlines(allocator, block.text, &inlines);
					layout_inline(
						out,
						&inlines,
						indent,
						&y,
						char_width,
						line_height,
						font_size,
						width,
						MdStyle.TEXT,
						false
					);
					inlines.free();
					y += line_height * 0.2f;
				}
			case MdBlockKind.CODE:

				{
					y += line_height * 0.3f;
					layout_code_block(out, &block, 0.0f, &y, char_width, line_height, font_size, width);
					y += line_height * BLOCK_GAP;
				}
			case MdBlockKind.QUOTE:

				{
					float top = y;
					out.rects.push(
						{
							.rect = { .x = 2.0f, .y = top, .width = 3.0f, .height = line_height },
							.kind = MdRectKind.QUOTE_BAR,
						}
					);
					List{MdInline} inlines;
					parse_inlines(allocator, block.text, &inlines);
					layout_inline(
						out,
						&inlines,
						QUOTE_INDENT,
						&y,
						char_width,
						line_height,
						font_size,
						width,
						MdStyle.QUOTE,
						false
					);
					inlines.free();
					out.rects[out.rects.len() - 1].rect.height = y - top;
					y += line_height * BLOCK_GAP;
				}
			case MdBlockKind.RULE:

				{
					y += line_height * 0.5f;
					out.rects.push(
						{
							.rect = { .x = 0.0f, .y = y, .width = width, .height = 1.0f },
							.kind = MdRectKind.RULE,
						}
					);
					y += line_height * 0.5f;
				}
		}
		out.anchors.push({ .y = block_y, .offset = block.start });
	}

	out.height = y;
	return out;
}

fn void free_layout(MdLayout* out, Allocator allocator)
{
	if (!out) return;
	out.runs.free();
	out.rects.free();
	out.anchors.free();
	alloc::free(allocator, out);
}

fn View* view_create(Allocator allocator)
{
	View* view = alloc::new(allocator, View);
	view.allocator = allocator;
	view.doc = null;
	view.layout = null;
	view.layout_width = -1.0f;
	view.layout_char_width = 0.0f;
	view.layout_font_size = 0.0f;
	view.dirty = true;
	return view;
}

fn void view_mark_dirty(View* view)
{
	if (view) view.dirty = true;
}

fn void view_destroy(View* view, Allocator allocator)
{
	if (!view) return;
	if (view.doc) free_document(view.doc, allocator);
	if (view.layout) free_layout(view.layout, allocator);
	alloc::free(allocator, view);
}

fn void view_ensure(View* view, PieceTable* table, float width, float char_width, float font_size, float line_height)
{
	if (!view) return;
	if (!view.dirty && view.layout && view.layout_width == width && view.layout_char_width == char_width
		&& view.layout_font_size == font_size) return;

	if (view.doc) free_document(view.doc, view.allocator);
	if (view.layout) free_layout(view.layout, view.allocator);
	view.doc = null;
	view.layout = null;
	if (!table)
	{
		view.dirty = false;
		return;
	}

	String src = table.slice(0, table.length(), view.allocator);
	view.doc = parse(view.allocator, src);
	src.free(view.allocator);
	view.layout = layout(view.allocator, view.doc, width, char_width, font_size, line_height);
	view.layout_width = width;
	view.layout_char_width = char_width;
	view.layout_font_size = font_size;
	view.dirty = false;
}

fn float view_content_height(
	View* view,
	PieceTable* table,
	float width,
	float char_width,
	float font_size,
	float line_height
)
{
	view_ensure(view, table, width, char_width, font_size, line_height);
	if (!view.layout) return 0.0f;
	return view.layout.height;
}

fn usz view_block_offset_at(View* view, float y)
{
	if (!view.layout) return 0;
	usz result = 0;
	foreach (MdAnchor a : view.layout.anchors)
	{
		if (a.y <= y)
		{
			result = a.offset;
		}
		else
		{
			break;
		}
	}
	return result;
}

fn RLColor style_color(MdStyle style)
{
	Theme* t = theme::current();
	switch (style)
	{
		case MdStyle.TEXT:
			return t.editor_text;
		case MdStyle.HEADING:
			return t.syn_keyword;
		case MdStyle.STRONG:
			return t.syn_type;
		case MdStyle.EM:
			return t.syn_attribute;
		case MdStyle.CODE:
			return t.editor_text;
		case MdStyle.LINK:
			return t.syn_module;
		case MdStyle.QUOTE:
			return t.panel_dim;
	}
}

fn RLColor rect_color(MdRectKind kind)
{
	Theme* t = theme::current();
	switch (kind)
	{
		case MdRectKind.CODE_BG:
			return t.panel_bg_alt;
		case MdRectKind.QUOTE_BAR:
			return t.panel_border;
		case MdRectKind.BULLET:
			return t.panel_dim;
		case MdRectKind.RULE:
			return t.panel_border;
	}
}

fn void apply_scissor(Rect area, RLCamera2D camera)
{
	RLVector2 tl = rl::get_world_to_screen2d({ area.x, area.y }, camera);
	RLVector2 br = rl::get_world_to_screen2d({ area.x + area.width, area.y + area.height }, camera);
	rl::begin_scissor_mode((int)tl[0], (int)tl[1], (int)(br[0] - tl[0]), (int)(br[1] - tl[1]));
}

fn void draw_run(RLFont font, MdRun run, float x, float y, RLColor color)
{
	@pool()
	{
		ZString z = run.text.zstr_tcopy();
		rl::draw_text_ex(font, z, { x, y }, run.size, 0.0f, color);
		if (run.bold) rl::draw_text_ex(font, z, { x + 1.0f, y }, run.size, 0.0f, color);
	};
}

fn void draw_code_run(highlight::Highlighter* hl, MdRun run, float x, float y, float char_width, RLFont font)
{
	draw_run(font, run, x, y, style_color(MdStyle.CODE));
	if (!hl || run.src_end <= run.src_start) return;
	@pool()
	{
		List{highlight::Span} spans;
		spans.init(tmem);
		hl.runs_for_line(run.src_start, run.src_end, &spans);
		foreach (highlight::Span span : spans)
		{
			usz s = span.start > run.src_start ? (usz)(span.start - run.src_start) : 0;
			usz e = span.end < run.src_end ? (usz)(span.end - run.src_start) : run.text.len;
			if (e > run.text.len) e = run.text.len;
			if (s >= e) continue;
			draw_run(
				font,
				{ .text = run.text[s:e - s], .size = run.size, .bold = false },
				x + (float)s * char_width,
				y,
				highlight::role_color(span.role)
			);
		}
		spans.free();
	};
}

fn float view_draw(
	View* view,
	PieceTable* table,
	Rect area,
	float scroll,
	RLCamera2D camera,
	RLFont font,
	float font_size,
	float char_width,
	float line_height,
	highlight::Highlighter* hl
)
{
	if (!view) return 0.0f;
	view_ensure(view, table, area.width, char_width, font_size, line_height);
	MdLayout* l = view.layout;
	if (!l) return 0.0f;

	apply_scissor(area, camera);

	foreach (MdRect r : l.rects)
	{
		float ry = area.y + r.rect.y - scroll;
		if (ry + r.rect.height < area.y || ry > area.y + area.height) continue;
		rl::draw_rectangle_rec(
			{ .x = area.x + r.rect.x, .y = ry, .width = r.rect.width, .height = r.rect.height },
			rect_color(r.kind)
		);
	}

	foreach (MdRun run : l.runs)
	{
		float ry = area.y + run.y - scroll;
		if (ry + run.size < area.y) continue;
		if (ry > area.y + area.height) break;
		float rx = area.x + run.x;
		if (run.style == MdStyle.CODE && hl && run.src_end > run.src_start)
		{
			draw_code_run(hl, run, rx, ry, char_width, font);
			continue;
		}
		RLColor color = style_color(run.style);
		draw_run(font, run, rx, ry, color);
		if (run.style == MdStyle.LINK)
		{
			rl::draw_rectangle(
				(int)rx,
				(int)(ry + run.size * 0.95f),
				(int)((float)run.text.len * char_width),
				1,
				color
			);
		}
	}

	rl::end_scissor_mode();

	float max = l.height - area.height;
	return max > 0.0f ? max : 0.0f;
}