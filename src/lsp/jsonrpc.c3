module yun::lsp;

import std::core::dstring;

faultdef LSP_INCOMPLETE;
faultdef LSP_MALFORMED;

const usz LSP_MAX_MESSAGE = 128 * 1024 * 1024;

fn String jsonrpc_encode(Allocator allocator, String json)
{
	return string::format(allocator, "Content-Length: %d\r\n\r\n%s", (long)json.len, json);
}

fn bool jsonrpc_find_header_end(char[] buffer, usz* header_end)
{
	if (buffer.len < 4) return false;
	for (usz i = 0; i + 3 < buffer.len; i++)
	{
		if (buffer[i] == '\r' && buffer[i + 1] == '\n' && buffer[i + 2] == '\r' && buffer[i + 3] == '\n')
		{
			*header_end = i + 4;
			return true;
		}
	}
	return false;
}

fn bool jsonrpc_parse_length(char[] buffer, usz header_end, usz* length)
{
	usz i = 0;
	while (i < header_end)
	{
		usz j = i;
		while (j < header_end && buffer[j] != '\n') j++;
		String line = (String)buffer[i:j - i];
		while (line.len > 0 && (line[line.len - 1] == '\r' || line[line.len - 1] == ' ')) line = line[0:line.len - 1];
		if (line.starts_with("Content-Length:"))
		{
			String value = line[15:line.len - 15];
			while (value.len > 0 && value[0] == ' ') value = value[1:value.len - 1];
			usz parsed      = 0;
			bool has_digits = false;
			for (usz k = 0; k < value.len; k++)
			{
				char c = value[k];
				if (c < '0' || c > '9') return false;
				parsed = parsed * 10 + (usz)(c - '0');
				has_digits = true;
			}
			if (!has_digits || parsed > LSP_MAX_MESSAGE) return false;
			*length = parsed;
			return true;
		}
		i = j + 1;
	}
	return false;
}

fn String? jsonrpc_try_parse(char[] buffer, usz* consumed)
{
	*consumed = 0;
	usz header_end = 0;
	if (!jsonrpc_find_header_end(buffer, &header_end)) return LSP_INCOMPLETE~;

	usz length = 0;
	if (!jsonrpc_parse_length(buffer, header_end, &length))
	{
		*consumed = header_end;
		return LSP_MALFORMED~;
	}
	if (header_end + length > buffer.len) return LSP_INCOMPLETE~;

	*consumed = header_end + length;
	return (String)buffer[header_end:length];
}