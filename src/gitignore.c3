module yun::gitignore;

import std::collections::list;
import std::core::mem::alloc;
import std::io::file;
import std::io::path;

struct IgnoreRule
{
	String base;
	String pattern;
	bool negate;
	bool dir_only;
	bool anchored;
}

struct Gitignore
{
	List{IgnoreRule} rules;
	Allocator allocator;
}

fn void Gitignore.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.rules.init(allocator);
}

fn void Gitignore.free(&self)
{
	for (sz i = 0; i < self.rules.len(); i++)
	{
		self.rules[i].base.free(self.allocator);
		self.rules[i].pattern.free(self.allocator);
	}
	self.rules.free();
}

fn String path_basename(String path)
{
	for (sz i = (sz)path.len; i > 0; i--)
	{
		if (path[(usz)(i - 1)] == '/') return path[(usz)i:path.len - (usz)i];
	}
	return path;
}

fn bool relative_under(String base, String abs, String* out)
{
	if (base.len == 0)
	{
		*out = abs;
		return true;
	}
	if (abs.len <= base.len) return false;
	if (abs[0:base.len].compare_to(base) != 0) return false;
	if (abs[base.len] != '/') return false;
	*out = abs[base.len + 1:abs.len - base.len - 1];
	return true;
}

fn bool glob_match_from(String pattern, usz pattern_at, String text, usz text_at)
{
	while (pattern_at < pattern.len)
	{
		char c = pattern[pattern_at];
		if (c == '*')
		{
			bool double_star = pattern_at + 1 < pattern.len && pattern[pattern_at + 1] == '*';
			if (double_star)
			{
				usz next = pattern_at + 2;
				if (next < pattern.len && pattern[next] == '/')
				{
					if (glob_match_from(pattern, next + 1, text, text_at)) return true;
				}
				for (usz k = text_at; k <= text.len; k++)
				{
					if (glob_match_from(pattern, next, text, k)) return true;
				}
				return false;
			}
			usz k = text_at;
			while (true)
			{
				if (glob_match_from(pattern, pattern_at + 1, text, k)) return true;
				if (k >= text.len || text[k] == '/') break;
				k++;
			}
			return false;
		}
		if (c == '?')
		{
			if (text_at >= text.len || text[text_at] == '/') return false;
			pattern_at++;
			text_at++;
			continue;
		}
		if (text_at >= text.len || text[text_at] != c) return false;
		pattern_at++;
		text_at++;
	}
	return text_at == text.len;
}

fn bool glob_match(String pattern, String text)
{
	return glob_match_from(pattern, 0, text, 0);
}

fn bool rule_matches(IgnoreRule rule, String relative)
{
	if (rule.anchored)
	{
		if (glob_match(rule.pattern, relative)) return true;
		if (rule.pattern.starts_with("**/") && glob_match(rule.pattern[3..], relative)) return true;
		return false;
	}
	return glob_match(rule.pattern, path_basename(relative));
}

fn void Gitignore.add_line(&self, String base, String raw)
{
	usz len = raw.len;
	if (len > 0 && raw[len - 1] == '\r') len--;
	String line = raw[0:len];
	if (line.len == 0) return;
	if (line[0] == '#') return;

	bool negate = false;
	usz start   = 0;
	if (line[0] == '!')
	{
		negate = true;
		start = 1;
	}
	if (start >= line.len) return;

	bool anchored = false;
	if (line[start] == '\\' && start + 1 < line.len && (line[start + 1] == '#' || line[start + 1] == '!'))
	{
		start++;
	}
	else if (line[start] == '/')
	{
		anchored = true;
		start++;
	}

	usz end       = line.len;
	bool dir_only = false;
	if (end > start && line[end - 1] == '/')
	{
		dir_only = true;
		end--;
	}
	if (end <= start) return;

	String pattern = line[start:end - start];
	if (pattern.contains("/")) anchored = true;

	self.rules.push(
		{
			.base = base.copy(self.allocator),
			.pattern = pattern.copy(self.allocator),
			.negate = negate,
			.dir_only = dir_only,
			.anchored = anchored,
		}
	);
}

fn void Gitignore.load_file(&self, Path gitignore_file, String base)
{
	@pool()
	{
		char[]? data = file::load(tmem, (String)gitignore_file);
		if (catch excuse = data) return;
		String text = (String)data;
		usz start   = 0;
		for (usz i = 0; i <= text.len; i++)
		{
			if (i != text.len && text[i] != '\n') continue;
			self.add_line(base, text[start:i - start]);
			start = i + 1;
		}
	};
}

fn bool Gitignore.is_ignored(&self, String abs_path, bool is_dir)
{
	bool ignored  =  false;
	usz best_base =  0;
	sz best_index = -1;
	for (sz i = 0; i < self.rules.len(); i++)
	{
		IgnoreRule rule = self.rules[i];
		String relative;
		if (!relative_under(rule.base, abs_path, &relative)) continue;
		if (rule.dir_only && !is_dir) continue;
		if (!rule_matches(rule, relative)) continue;
		if (rule.base.len > best_base || (rule.base.len == best_base && i > best_index))
		{
			best_base = rule.base.len;
			best_index = i;
			ignored = !rule.negate;
		}
	}
	return ignored;
}