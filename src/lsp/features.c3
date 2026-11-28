module yun::lsp;

import std::collections::list;
import std::collections::object;

struct WorkspaceTextEdit
{
	String new_text;
	uint start_line;
	uint start_character;
	uint end_line;
	uint end_character;
}

struct WorkspaceFileEdit
{
	String path;
	List{WorkspaceTextEdit} edits;
}

struct WorkspaceEdit
{
	List{WorkspaceFileEdit} files;
}

struct CodeActionItem
{
	String title;
	WorkspaceEdit edit;
}

struct LspSymbol
{
	String name;
	String detail;
	String path;
	int kind;
	uint line;
	uint character;
}

struct SemanticToken
{
	uint line;
	uint character;
	uint length;
	int token_type;
}

fn Object* lsp_reference_params(Allocator allocator, String uri, uint line, uint character, bool include_declaration)
{
	Object* root    = lsp_document_position_params(allocator, uri, line, character);
	Object* context = root.get_or_create_obj("context");
	context.set("includeDeclaration", include_declaration);
	return root;
}

fn Object* lsp_rename_params(Allocator allocator, String uri, uint line, uint character, String new_name)
{
	Object* root = lsp_document_position_params(allocator, uri, line, character);
	root.set("newName", new_name);
	return root;
}

fn Object* lsp_code_action_params(
	Allocator allocator,
	String uri,
	uint start_line,
	uint start_character,
	uint end_line,
	uint end_character,
	LspDiagnostic[] diagnostics
)
{
	Object* root = object::new_obj(allocator);
	Object* doc  = root.get_or_create_obj("textDocument");
	doc.set("uri", uri);
	Object* range = root.get_or_create_obj("range");
	Object* start = range.get_or_create_obj("start");
	start.set("line", (long)start_line);
	start.set("character", (long)start_character);
	Object* end = range.get_or_create_obj("end");
	end.set("line", (long)end_line);
	end.set("character", (long)end_character);
	Object* context = root.get_or_create_obj("context");
	Object* list    = object::new_array(allocator);
	for (sz i = 0; i < diagnostics.len; i++)
	{
		LspDiagnostic diag = diagnostics[i];
		Object* item       = object::new_obj(allocator);
		Object* item_range = item.get_or_create_obj("range");
		Object* item_start = item_range.get_or_create_obj("start");
		item_start.set("line", (long)diag.start_line);
		item_start.set("character", (long)diag.start_character);
		Object* item_end = item_range.get_or_create_obj("end");
		item_end.set("line", (long)diag.end_line);
		item_end.set("character", (long)diag.end_character);
		item.set("severity", (long)diag.severity);
		item.set("message", diag.message);
		list.push(item);
	}
	context.set("diagnostics", list);
	return root;
}

fn Object* lsp_document_symbol_params(Allocator allocator, String uri)
{
	Object* root = object::new_obj(allocator);
	Object* doc  = root.get_or_create_obj("textDocument");
	doc.set("uri", uri);
	return root;
}

fn Object* lsp_workspace_symbol_params(Allocator allocator, String query)
{
	Object* root = object::new_obj(allocator);
	root.set("query", query);
	return root;
}

fn uint lsp_token_uint(Object* value)
{
	uint? number = value.to_value(uint);
	if (catch err = number) return 0;
	return number;
}

fn uint lsp_feature_uint(Object* obj, String key)
{
	uint? value = obj.get_uint(key);
	if (catch err = value) return 0;
	return value;
}

fn bool lsp_feature_range(Object* value, uint* start_line, uint* start_character, uint* end_line, uint* end_character)
{
	if (!value.is_map()) return false;
	Object*? start_opt = value.get("start");
	if (catch err = start_opt) return false;
	Object*? end_opt = value.get("end");
	if (catch end_excuse = end_opt) return false;
	*start_line = lsp_feature_uint(start_opt, "line");
	*start_character = lsp_feature_uint(start_opt, "character");
	*end_line = lsp_feature_uint(end_opt, "line");
	*end_character = lsp_feature_uint(end_opt, "character");
	return true;
}

fn bool lsp_parse_text_edit(Allocator allocator, Object* value, WorkspaceTextEdit* out)
{
	Object*? range_opt = value.get("range");
	if (catch err = range_opt) return false;
	if (!lsp_feature_range(range_opt, &out.start_line, &out.start_character, &out.end_line, &out.end_character))
	{
		return false;
	}
	Object*? text_opt = value.get("newText");
	if (catch text_excuse = text_opt) return false;
	if (!text_opt.is_string()) return false;
	out.new_text = text_opt.s.copy(allocator);
	return true;
}

fn void lsp_workspace_edit_init(WorkspaceEdit* edit, Allocator allocator)
{
	edit.files.init(allocator);
}

fn void lsp_workspace_edit_free(WorkspaceEdit* edit, Allocator allocator)
{
	for (sz f = 0; f < edit.files.len(); f++)
	{
		WorkspaceFileEdit* file = &edit.files[f];
		for (sz e = 0; e < file.edits.len(); e++)
		{
			if (file.edits[e].new_text.len) file.edits[e].new_text.free(allocator);
		}
		file.edits.free();
		file.path.free(allocator);
	}
	edit.files.free();
}

fn void lsp_workspace_edit_add_file(Allocator allocator, WorkspaceEdit* edit, String uri, Object* edits)
{
	if (!edits.is_array() || edits.get_len() == 0) return;
	WorkspaceFileEdit file;
	file.path = uri_to_path(allocator, uri);
	file.edits.init(allocator);
	for (sz i = 0; i < edits.get_len(); i++)
	{
		Object* value = edits.get_at(i);
		if (!value.is_map()) continue;
		WorkspaceTextEdit text_edit;
		if (lsp_parse_text_edit(allocator, value, &text_edit))
		{
			file.edits.push(text_edit);
		}
	}
	if (file.edits.len() == 0)
	{
		file.path.free(allocator);
		file.edits.free();
		return;
	}
	edit.files.push(file);
}

fn bool lsp_parse_workspace_edit(Allocator allocator, Object* result, WorkspaceEdit* out)
{
	lsp_workspace_edit_init(out, allocator);
	if (!result.is_map()) return false;

	Object*? changes_opt = result.get("changes");
	if (try changes = changes_opt)
	{
		changes.@each_entry(; String uri, Object* edits)
		{
			lsp_workspace_edit_add_file(allocator, out, uri, edits);
		};
	}

	Object*? document_opt = result.get("documentChanges");
	if (try document_changes = document_opt)
	{
		if (document_changes.is_array())
		{
			for (sz i = 0; i < document_changes.get_len(); i++)
			{
				Object* change = document_changes.get_at(i);
				if (!change.is_map()) continue;
				Object*? doc_opt = change.get("textDocument");
				if (catch err = doc_opt) continue;
				if (!doc_opt.is_map()) continue;
				Object*? uri_opt = doc_opt.get("uri");
				if (catch uri_excuse = uri_opt) continue;
				if (!uri_opt.is_string()) continue;
				Object*? edits_opt = change.get("edits");
				if (catch edits_excuse = edits_opt) continue;
				lsp_workspace_edit_add_file(allocator, out, uri_opt.s, edits_opt);
			}
		}
	}
	return out.files.len() > 0;
}

fn void lsp_code_action_free(CodeActionItem* item, Allocator allocator)
{
	if (item.title.len) item.title.free(allocator);
	lsp_workspace_edit_free(&item.edit, allocator);
}

fn void lsp_parse_code_actions(Allocator allocator, Object* result, List{CodeActionItem}* out)
{
	if (!result.is_array()) return;
	for (sz i = 0; i < result.get_len(); i++)
	{
		Object* value = result.get_at(i);
		if (!value.is_map()) continue;
		Object*? title_opt = value.get("title");
		if (catch err = title_opt) continue;
		if (!title_opt.is_string()) continue;
		Object*? edit_opt = value.get("edit");
		if (catch edit_excuse = edit_opt) continue;
		CodeActionItem item;
		item.title = title_opt.s.copy(allocator);
		if (!lsp_parse_workspace_edit(allocator, edit_opt, &item.edit))
		{
			item.title.free(allocator);
			lsp_workspace_edit_free(&item.edit, allocator);
			continue;
		}
		out.push(item);
	}
}

fn void lsp_parse_document_symbols(Allocator allocator, Object* result, String path, List{LspSymbol}* out)
{
	if (!result.is_array()) return;
	for (sz i = 0; i < result.get_len(); i++)
	{
		Object* value = result.get_at(i);
		if (!value.is_map()) continue;
		Object*? name_opt = value.get("name");
		if (catch err = name_opt) continue;
		if (!name_opt.is_string()) continue;
		uint start_line        = 0;
		uint start_character   = 0;
		uint end_line          = 0;
		uint end_character     = 0;
		Object*? selection_opt = value.get("selectionRange");
		if (catch selection_excuse = selection_opt) continue;
		if (!lsp_feature_range(selection_opt, &start_line, &start_character, &end_line, &end_character))
		{
			continue;
		}
		LspSymbol symbol;
		symbol.name = name_opt.s.copy(allocator);
		symbol.path = path.copy(allocator);
		symbol.detail = "";
		Object*? detail_opt = value.get("detail");
		if (try detail = detail_opt)
		{
			if (detail.is_string()) symbol.detail = detail.s.copy(allocator);
		}
		symbol.kind = (int)lsp_feature_uint(value, "kind");
		symbol.line = start_line;
		symbol.character = start_character;
		out.push(symbol);
	}
}

fn void lsp_parse_workspace_symbols(Allocator allocator, Object* result, List{LspSymbol}* out)
{
	if (!result.is_array()) return;
	for (sz i = 0; i < result.get_len(); i++)
	{
		Object* value = result.get_at(i);
		if (!value.is_map()) continue;
		Object*? name_opt = value.get("name");
		if (catch err = name_opt) continue;
		if (!name_opt.is_string()) continue;
		Object*? location_opt = value.get("location");
		if (catch location_excuse = location_opt) continue;
		if (!location_opt.is_map()) continue;
		Object*? uri_opt = location_opt.get("uri");
		if (catch uri_excuse = uri_opt) continue;
		if (!uri_opt.is_string()) continue;
		Object*? range_opt = location_opt.get("range");
		if (catch range_excuse = range_opt) continue;
		uint start_line      = 0;
		uint start_character = 0;
		uint end_line        = 0;
		uint end_character   = 0;
		if (!lsp_feature_range(range_opt, &start_line, &start_character, &end_line, &end_character))
		{
			continue;
		}
		LspSymbol symbol;
		symbol.name = name_opt.s.copy(allocator);
		symbol.path = uri_to_path(allocator, uri_opt.s);
		symbol.detail = "";
		symbol.kind = (int)lsp_feature_uint(value, "kind");
		symbol.line = start_line;
		symbol.character = start_character;
		out.push(symbol);
	}
}

fn void lsp_symbols_free(List{LspSymbol}* symbols, Allocator allocator)
{
	for (sz i = 0; i < symbols.len(); i++)
	{
		LspSymbol symbol = symbols.get(i);
		if (symbol.name.len) symbol.name.free(allocator);
		if (symbol.detail.len) symbol.detail.free(allocator);
		if (symbol.path.len) symbol.path.free(allocator);
	}
	symbols.free();
}

fn bool lsp_parse_prepare_rename(Allocator allocator, Object* result, String* placeholder)
{
	*placeholder = "";
	if (!result.is_map()) return false;
	Object*? text_opt = result.get("placeholder");
	if (try text = text_opt)
	{
		if (text.is_string()) *placeholder = text.s.copy(allocator);
	}
	return true;
}

fn void lsp_parse_signature_help(Allocator allocator, Object* result, String* out)
{
	*out = "";
	if (!result.is_map()) return;
	Object*? signatures_opt = result.get("signatures");
	if (catch err = signatures_opt) return;
	if (!signatures_opt.is_array() || signatures_opt.get_len() == 0) return;
	uint active = lsp_feature_uint(result, "activeSignature");
	if (active >= (uint)signatures_opt.get_len()) active = 0;
	Object* signature = signatures_opt.get_at((sz)active);
	if (!signature.is_map()) return;
	Object*? label_opt = signature.get("label");
	if (catch label_excuse = label_opt) return;
	if (!label_opt.is_string()) return;
	*out = label_opt.s.copy(allocator);
}

fn void lsp_parse_semantic_tokens(Allocator allocator, Object* result, List{SemanticToken}* out)
{
	(void)allocator;
	if (!result.is_map()) return;
	Object*? data_opt = result.get("data");
	if (catch err = data_opt) return;
	if (!data_opt.is_array()) return;
	sz count       = data_opt.get_len();
	uint line      = 0;
	uint character = 0;
	for (sz i = 0; i + 4 < count; i += 5)
	{
		uint delta_line  = lsp_token_uint(data_opt.get_at(i));
		uint delta_start = lsp_token_uint(data_opt.get_at(i + 1));
		uint length      = lsp_token_uint(data_opt.get_at(i + 2));
		uint token_type  = lsp_token_uint(data_opt.get_at(i + 3));
		line += delta_line;
		if (delta_line == 0)
		{
			character += delta_start;
		}
		else
		{
			character = delta_start;
		}
		out.push(
			{
				.line = line,
				.character = character,
				.length = length,
				.token_type = (int)token_type,
			}
		);
	}
}