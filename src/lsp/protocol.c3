module yun::lsp;

import std::collections::list;
import std::collections::object;
import std::core::dstring;
import std::core::mem::alloc;
import std::encoding::json;
import yun::version;

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

struct DefinitionTarget
{
	String path;
	uint line;
	uint character;
}

struct CompletionItem
{
	String label;
	String filter_text;
	String sort_text;
	String insert_text;
	String detail;
	int kind;
	bool has_text_edit;
	uint edit_start_line;
	uint edit_start_character;
	uint edit_end_line;
	uint edit_end_character;
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
	client.set("version", version::APP_VERSION);

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

fn Object* lsp_completion_params(
	Allocator allocator,
	String uri,
	uint line,
	uint character,
	int trigger_kind,
	String trigger_char
)
{
	Object* root    = lsp_document_position_params(allocator, uri, line, character);
	Object* context = root.get_or_create_obj("context");
	context.set("triggerKind", (long)trigger_kind);
	if (trigger_char.len > 0) context.set("triggerCharacter", trigger_char);
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

fn void lsp_add_definition(Allocator allocator, Object* item, List{DefinitionTarget}* out)
{
	if (!item.is_map()) return;

	Object* uri_obj         = null;
	Object*? uri_opt        = item.get("uri");
	Object*? target_uri_opt = item.get("targetUri");
	if (try uri = uri_opt)
	{
		uri_obj = uri;
	}
	else if (try target_uri = target_uri_opt)
	{
		uri_obj = target_uri;
	}
	if (!uri_obj || !uri_obj.is_string()) return;

	Object* range_obj         = null;
	Object*? range_opt        = item.get("range");
	Object*? selection_opt    = item.get("targetSelectionRange");
	Object*? target_range_opt = item.get("targetRange");
	if (try range = range_opt)
	{
		range_obj = range;
	}
	else if (try selection = selection_opt)
	{
		range_obj = selection;
	}
	else if (try target_range = target_range_opt)
	{
		range_obj = target_range;
	}
	if (!range_obj || !range_obj.is_map()) return;

	Object*? start_opt = range_obj.get("start");
	if (catch excuse = start_opt) return;

	out.push(
		{
			.path = uri_to_path(allocator, uri_obj.s),
			.line = lsp_object_uint(start_opt, "line"),
			.character = lsp_object_uint(start_opt, "character"),
		}
	);
}

fn void lsp_normalize_definition(Allocator allocator, Object* result, List{DefinitionTarget}* out)
{
	if (result.is_array())
	{
		for (sz i = 0; i < result.get_len(); i++)
		{
			lsp_add_definition(allocator, result.get_at(i), out);
		}
		return;
	}
	if (result.is_map()) lsp_add_definition(allocator, result, out);
}

fn void lsp_add_completion_item(Allocator allocator, Object* item, List{CompletionItem}* out)
{
	if (!item.is_map()) return;
	Object*? label_opt = item.get("label");
	if (catch excuse = label_opt) return;
	if (!label_opt.is_string()) return;

	String label = label_opt.s.copy(allocator);

	CompletionItem entry = {
		.label = label,
		.filter_text = label.copy(allocator),
		.sort_text = label.copy(allocator),
		.insert_text = label.copy(allocator),
		.detail = "",
		.kind = (int)lsp_object_uint(item, "kind"),
		.has_text_edit = false,
	};

	Object*? filter_opt = item.get("filterText");
	if (try filter = filter_opt)
	{
		if (filter.is_string())
		{
			entry.filter_text.free(allocator);
			entry.filter_text = filter.s.copy(allocator);
		}
	}
	Object*? sort_opt = item.get("sortText");
	if (try sort = sort_opt)
	{
		if (sort.is_string())
		{
			entry.sort_text.free(allocator);
			entry.sort_text = sort.s.copy(allocator);
		}
	}
	Object*? insert_opt = item.get("insertText");
	if (try insert = insert_opt)
	{
		if (insert.is_string())
		{
			entry.insert_text.free(allocator);
			entry.insert_text = insert.s.copy(allocator);
		}
	}
	Object*? detail_opt = item.get("detail");
	if (try detail = detail_opt)
	{
		if (detail.is_string()) entry.detail = detail.s.copy(allocator);
	}

	Object*? text_edit_opt = item.get("textEdit");
	if (try text_edit = text_edit_opt)
	{
		if (text_edit.is_map())
		{
			Object* range_obj         = null;
			Object*? range_opt        = text_edit.get("range");
			Object*? insert_range_opt = text_edit.get("insert");
			if (try range = range_opt)
			{
				range_obj = range;
			}
			else if (try insert_range = insert_range_opt)
			{
				range_obj = insert_range;
			}
			if (range_obj && range_obj.is_map())
			{
				Object*? start_opt = range_obj.get("start");
				Object*? end_opt   = range_obj.get("end");
				if (try start = start_opt)
				{
					if (try end = end_opt)
					{
						entry.has_text_edit = true;
						entry.edit_start_line = lsp_object_uint(start, "line");
						entry.edit_start_character = lsp_object_uint(start, "character");
						entry.edit_end_line = lsp_object_uint(end, "line");
						entry.edit_end_character = lsp_object_uint(end, "character");
					}
				}
			}
			Object*? new_text_opt = text_edit.get("newText");
			if (try new_text = new_text_opt)
			{
				if (new_text.is_string())
				{
					entry.insert_text.free(allocator);
					entry.insert_text = new_text.s.copy(allocator);
				}
			}
		}
	}

	out.push(entry);
}

fn void lsp_normalize_completion(Allocator allocator, Object* result, List{CompletionItem}* out, bool* incomplete)
{
	*incomplete = false;
	if (result.is_array())
	{
		for (sz i = 0; i < result.get_len(); i++)
		{
			lsp_add_completion_item(allocator, result.get_at(i), out);
		}
		return;
	}
	if (!result.is_map()) return;

	Object*? items_opt = result.get("items");
	if (catch excuse = items_opt)
	{
		lsp_add_completion_item(allocator, result, out);
		return;
	}
	if (items_opt.is_array())
	{
		for (sz i = 0; i < items_opt.get_len(); i++)
		{
			lsp_add_completion_item(allocator, items_opt.get_at(i), out);
		}
	}
	Object*? incomplete_opt = result.get("isIncomplete");
	if (try flag = incomplete_opt)
	{
		if (flag.is_bool()) *incomplete = flag.b;
	}
}

fn void lsp_parse_capabilities(Allocator allocator, Object* result, LspCapabilities* out)
{
	if (!result.is_map()) return;
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