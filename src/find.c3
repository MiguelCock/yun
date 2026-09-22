module yun::find;

import std::collections::list;
import yun::text;

enum FindField
{
	QUERY,
	REPLACE,
}

const usz MATCH_COUNT_CAP = 2000;

fn char fold_ascii(char c)
{
	if (c >= 'A' && c <= 'Z') return (char)(c + 32);
	return c;
}

fn bool is_word_char(char c)
{
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_';
}

fn bool match_equals(PieceTable* table, usz offset, String query, bool case_sensitive)
{
	if (offset + query.len > table.length()) return false;
	for (usz i = 0; i < query.len; i++)
	{
		char a = table.char_at(offset + i);
		char b = query[i];
		if (!case_sensitive)
		{
			a = fold_ascii(a);
			b = fold_ascii(b);
		}
		if (a != b) return false;
	}
	return true;
}

fn bool boundaries_ok(PieceTable* table, usz offset, usz len, bool whole_word)
{
	if (!whole_word) return true;
	if (offset > 0 && is_word_char(table.char_at(offset - 1))) return false;
	usz end = offset + len;
	if (end < table.length() && is_word_char(table.char_at(end))) return false;
	return true;
}

fn bool match_at(PieceTable* table, usz offset, String query, bool case_sensitive, bool whole_word)
{
	if (query.len == 0) return false;
	if (!match_equals(table, offset, query, case_sensitive)) return false;
	return boundaries_ok(table, offset, query.len, whole_word);
}

fn bool next_match(PieceTable* table, usz from, String query, bool case_sensitive, bool whole_word, usz* out_start)
{
	usz length = table.length();
	if (query.len == 0 || length == 0) return false;
	usz pos = from;
	while (pos + query.len <= length)
	{
		if (match_at(table, pos, query, case_sensitive, whole_word))
		{
			*out_start = pos;
			return true;
		}
		pos++;
	}
	pos = 0;
	while (pos < from && pos + query.len <= length)
	{
		if (match_at(table, pos, query, case_sensitive, whole_word))
		{
			*out_start = pos;
			return true;
		}
		pos++;
	}
	return false;
}

fn bool prev_match(PieceTable* table, usz from, String query, bool case_sensitive, bool whole_word, usz* out_start)
{
	usz length = table.length();
	if (query.len == 0 || length == 0) return false;
	sz pos = (sz)from - 1;
	while (pos >= 0)
	{
		if (match_at(table, (usz)pos, query, case_sensitive, whole_word))
		{
			*out_start = (usz)pos;
			return true;
		}
		pos--;
	}
	if (length < query.len) return false;
	pos = (sz)(length - query.len);
	while (pos >= 0)
	{
		if (match_at(table, (usz)pos, query, case_sensitive, whole_word))
		{
			*out_start = (usz)pos;
			return true;
		}
		pos--;
	}
	return false;
}

fn usz collect_matches(PieceTable* table, String query, bool case_sensitive, bool whole_word, usz cap, List{usz}* out)
{
	out.clear();
	if (query.len == 0) return 0;
	usz length = table.length();
	usz pos    = 0;
	while (pos + query.len <= length && out.len() < (sz)cap)
	{
		if (match_at(table, pos, query, case_sensitive, whole_word))
		{
			out.push(pos);
			pos += query.len;
		}
		else
		{
			pos++;
		}
	}
	return (usz)out.len();
}

fn usz count_matches(PieceTable* table, String query, bool case_sensitive, bool whole_word, usz cap)
{
	if (query.len == 0) return 0;
	usz length = table.length();
	usz pos    = 0;
	usz total  = 0;
	while (pos + query.len <= length && total < cap)
	{
		if (match_at(table, pos, query, case_sensitive, whole_word))
		{
			total++;
			pos += query.len;
		}
		else
		{
			pos++;
		}
	}
	return total;
}

fn usz replace_at(PieceTable* table, History* history, usz start, usz len, String replacement, double now)
{
	history.break_coalescing();
	return history.replace(table, start, len, replacement, now);
}

fn usz replace_all(
	PieceTable* table,
	History* history,
	String query,
	String replacement,
	bool case_sensitive,
	bool whole_word,
	usz cap,
	double now
)
{
	if (query.len == 0) return 0;

	usz length = table.length();
	List{usz} all;
	all.init(history.allocator);
	defer all.free();
	collect_matches(table, query, case_sensitive, whole_word, cap, &all);

	history.break_coalescing();
	for (sz i = all.len(); i > 0; i--)
	{
		usz start = all[i - 1];
		(void)history.replace(table, start, query.len, replacement, now);
	}
	return (usz)all.len();
}