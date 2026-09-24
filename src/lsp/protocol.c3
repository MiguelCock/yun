module yun::lsp;

import std::collections::list;
import std::collections::object;
import std::core::dstring;
import std::core::mem::alloc;
import std::encoding::json;

faultdef LSP_NO_HOVER;

struct LspCapabilities
{
	bool hover;
	bool definition;
	bool completion;
	List{String} trigger_characters;
}

struct LspDiagnostic
{
	uint start_line;
	uint start_character;
	uint end_line;
	uint end_character;
	int severity;
	String message;
}

const int DIAGNOSTIC_ERROR   = 1;
const int DIAGNOSTIC_WARNING = 2;
const int DIAGNOSTIC_INFO    = 3;
const int DIAGNOSTIC_HINT    = 4;

fn void lsp_capabilities_init(LspCapabilities* caps, Allocator allocator)
{
	caps.hover = false;
	caps.definition = false;
	caps.completion = false;
	caps.trigger_characters.init(allocator);
}

fn void lsp_capabilities_free(LspCapabilities* caps, Allocator allocator)
{
	for (sz i = 0; i < caps.trigger_characters.len(); i++)
	{
		caps.trigger_characters[i].free(allocator);
	}
	caps.trigger_characters.free();
}

fn String lsp_message(Allocator allocator, bool has_id, long id, String method, Object* params)
{
	Object* root = object::new_obj(allocator);
	root.set("jsonrpc", "2.0");
	if (has_id) root.set("id", id);
	root.set("method", method);
	if (params) root.set("params", params);
	String json = json::marshal(allocator, root, JsonIndent.NONE);
	if (allocator != tmem) root.free();
	return json;
}

fn Object* lsp_initialize_params(Allocator allocator, String root_uri)
{
	Object* root = object::new_obj(allocator);
	root.set("rootUri", root_uri);

	Object* client = root.get_or_create_obj("clientInfo");
	client.set("name", "Yun");
	client.set("version", "0.1.0");

	Object* caps = root.get_or_create_obj("capabilities");
	Object* td   = caps.get_or_create_obj("textDocument");

	Object* sync = td.get_or_create_obj("synchronization");
	sync.set("dynamicRegistration", false);

	Object* hover   = td.get_or_create_obj("hover");
	Object* formats = object::new_array(allocator);
	formats.push("markdown");
	formats.push("plaintext");
	hover.set("contentFormat", formats);

	Object* completion = td.get_or_create_obj("completion");
	Object* item       = completion.get_or_create_obj("completionItem");
	item.set("snippetSupport", false);

	Object* diagnostics = td.get_or_create_obj("publishDiagnostics");
	diagnostics.set("relatedInformation", true);

	return root;
}

fn Object* lsp_did_open_params(Allocator allocator, String uri, String language_id, long version, String text)
{
	Object* root = object::new_obj(allocator);
	Object* doc  = root.get_or_create_obj("textDocument");
	doc.set("uri", uri);
	doc.set("languageId", language_id);
	doc.set("version", version);
	doc.set("text", text);
	return root;
}

fn Object* lsp_did_change_params(Allocator allocator, String uri, long version, String text)
{
	Object* root = object::new_obj(allocator);
	Object* doc  = root.get_or_create_obj("textDocument");
	doc.set("uri", uri);
	doc.set("version", version);

	Object* changes = object::new_array(allocator);
	Object* change  = object::new_obj(allocator);
	change.set("text", text);
	changes.push(change);
	root.set("contentChanges", changes);
	return root;
}

fn Object* lsp_did_close_params(Allocator allocator, String uri)
{
	Object* root = object::new_obj(allocator);
	Object* doc  = root.get_or_create_obj("textDocument");
	doc.set("uri", uri);
	return root;
}

fn Object* lsp_document_position_params(Allocator allocator, String uri, uint line, uint character)
{
	Object* root = object::new_obj(allocator);
	Object* doc  = root.get_or_create_obj("textDocument");
	doc.set("uri", uri);
	Object* position = root.get_or_create_obj("position");
	position.set("line", (long)line);
	position.set("character", (long)character);
	return root;
}

fn void lsp_append_marked_string(Allocator allocator, Object* item, DString* out)
{
	if (item.is_string())
	{
		out.append_string(item.s);
		return;
	}
	if (!item.is_map()) return;
	Object*? language_opt = item.get("language");
	Object*? value_opt    = item.get("value");
	if (catch excuse = value_opt) return;
	if (try language = language_opt)
	{
		@pool()
		{
			String block = string::format(tmem, "```%s\n%s\n```", language.s, value_opt.s);
			out.append_string(block);
		};
	}
	else
	{
		out.append_string(value_opt.s);
	}
}

fn String? lsp_normalize_hover(Allocator allocator, Object* result)
{
	if (!result.is_map()) return LSP_NO_HOVER~;

	Object*? contents_opt = result.get("contents");
	if (catch excuse = contents_opt) return LSP_NO_HOVER~;
	Object* contents = contents_opt;

	if (contents.is_string()) return contents.s.copy(allocator);

	if (contents.is_map())
	{
		if (contents.has_key("kind") && contents.has_key("value"))
		{
			Object*? value_opt = contents.get("value");
			if (try value = value_opt)
			{
				if (value.is_string()) return value.s.copy(allocator);
			}
		}
		DString out;
		out.init(allocator, 64);
		lsp_append_marked_string(allocator, contents, &out);
		if (out.len() == 0)
		{
			out.free();
			return LSP_NO_HOVER~;
		}
		String text = out.str_view().copy(allocator);
		out.free();
		return text;
	}

	if (contents.is_array())
	{
		DString out;
		out.init(allocator, 64);
		for (sz i = 0; i < contents.get_len(); i++)
		{
			if (out.len() > 0) out.append_string("\n\n");
			lsp_append_marked_string(allocator, contents.get_at(i), &out);
		}
		if (out.len() == 0)
		{
			out.free();
			return LSP_NO_HOVER~;
		}
		String text = out.str_view().copy(allocator);
		out.free();
		return text;
	}

	return LSP_NO_HOVER~;
}

fn void lsp_parse_capabilities(Allocator allocator, Object* result, LspCapabilities* out)
{
	Object*? caps_opt = result.get("capabilities");
	if (catch excuse = caps_opt) return;
	Object* caps = caps_opt;

	out.hover = caps.has_key("hoverProvider");
	out.definition = caps.has_key("definitionProvider");
	out.completion = caps.has_key("completionProvider");

	Object*? provider_opt = caps.get("completionProvider");
	if (catch excuse = provider_opt) return;

	Object*? triggers_opt = provider_opt.get("triggerCharacters");
	if (catch excuse = triggers_opt) return;
	if (!triggers_opt.is_array()) return;

	for (sz i = 0; i < triggers_opt.get_len(); i++)
	{
		Object* entry = triggers_opt.get_at(i);
		if (entry.is_string()) out.trigger_characters.push(entry.s.copy(allocator));
	}
}

fn uint lsp_object_uint(Object* obj, String key)
{
	Object*? value_opt = obj.get(key);
	if (catch excuse = value_opt) return 0;
	uint? number = value_opt.to_value(uint);
	if (catch excuse = number) return 0;
	return number;
}

fn void lsp_parse_diagnostics(Allocator allocator, Object* params, List{LspDiagnostic}* out)
{
	Object*? list_opt = params.get("diagnostics");
	if (catch excuse = list_opt) return;
	if (!list_opt.is_array()) return;

	for (sz i = 0; i < list_opt.get_len(); i++)
	{
		Object* entry = list_opt.get_at(i);
		if (!entry.is_map()) continue;

		LspDiagnostic diag = { };

		Object*? range_opt = entry.get("range");
		if (try range = range_opt)
		{
			Object*? start_opt = range.get("start");
			if (try start = start_opt)
			{
				diag.start_line = lsp_object_uint(start, "line");
				diag.start_character = lsp_object_uint(start, "character");
			}
			Object*? end_opt = range.get("end");
			if (try end = end_opt)
			{
				diag.end_line = lsp_object_uint(end, "line");
				diag.end_character = lsp_object_uint(end, "character");
			}
		}

		diag.severity = (int)lsp_object_uint(entry, "severity");
		Object*? message_opt = entry.get("message");
		if (try message = message_opt)
		{
			diag.message = message.is_string() ? message.s.copy(allocator) : "";
		}
		else
		{
			diag.message = "";
		}
		out.push(diag);
	}
}