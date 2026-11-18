module yun::lsp;

import std::collections::list;
import std::collections::map;
import std::collections::object;
import std::core::dstring;
import std::core::mem::alloc;
import std::io;
import std::math;
import yun::config;
import yun::language;
import yun::text;

struct LspDoc
{
	String path;
	String uri;
	String language;
	String text;
	long version;
	bool opened;
	bool symbols_requested;
}

struct FileDiagnostics
{
	String path;
	List{LspDiagnostic} diags;
}

struct LspDiagnosticRef
{
	String path;
	LspDiagnostic diag;
}

struct Lsp
{
	Allocator allocator;
	config::Config* config;
	String root_uri;
	bool has_root;
	List{LspClient*} clients;
	List{LspDoc} docs;
	List{FileDiagnostics} diag_files;
	HashMap{String, int} diag_index;
	bool hover_over;
	String hover_path;
	usz hover_offset;
	double hover_send_at;
	int hover_request_id;
	String hover_text;
	bool hover_valid;
	int definition_request_id;
	List{DefinitionTarget} definition_results;
	bool definition_ready;
	int completion_request_id;
	List{CompletionItem} completion_items;
	bool completion_ready;
	bool completion_incomplete;
	int formatting_request_id;
	String formatting_path;
	List{FormattingEdit} formatting_edits;
	bool formatting_ready;
	int references_request_id;
	List{DefinitionTarget} reference_results;
	bool references_ready;
	int prepare_rename_request_id;
	bool prepare_rename_ready;
	String rename_placeholder;
	int rename_request_id;
	WorkspaceEdit rename_edit;
	bool rename_ready;
	int code_action_request_id;
	List{CodeActionItem} code_actions;
	bool code_actions_ready;
	int signature_request_id;
	String signature_text;
	String signature_path;
	usz signature_offset;
	double signature_send_at;
	bool signature_ready;
	int document_symbol_request_id;
	String document_symbol_path;
	List{LspSymbol} document_symbol_list;
	bool document_symbols_ready;
	int workspace_symbol_request_id;
	List{LspSymbol} workspace_symbol_list;
	bool workspace_symbols_ready;
	int semantic_request_id;
	String semantic_path;
	long semantic_request_version;
	long semantic_requested_version;
	long semantic_change_version;
	double semantic_send_at;
	List{SemanticToken} semantic_tokens;
	bool semantic_ready;
}

Lsp* active_lsp;

const LspDiagnostic[] NO_DIAGNOSTICS = { };
const String[] NO_TRIGGERS           = { };

fn void Lsp.init(&self, Allocator allocator, config::Config* config)
{
	self.allocator = allocator;
	self.config = config;
	self.root_uri = "";
	self.has_root = false;
	self.clients.init(allocator);
	self.docs.init(allocator);
	self.diag_files.init(allocator);
	self.diag_index.init(allocator);
	self.hover_over = false;
	self.hover_path = "";
	self.hover_offset = 0;
	self.hover_send_at = 0.0;
	self.hover_request_id = -1;
	self.hover_text = "";
	self.hover_valid = false;
	self.definition_request_id = -1;
	self.definition_results.init(allocator);
	self.definition_ready = false;
	self.completion_request_id = -1;
	self.completion_items.init(allocator);
	self.completion_ready = false;
	self.completion_incomplete = false;
	self.formatting_request_id = -1;
	self.formatting_path = "";
	self.formatting_edits.init(allocator);
	self.formatting_ready = false;
	self.references_request_id = -1;
	self.reference_results.init(allocator);
	self.references_ready = false;
	self.prepare_rename_request_id = -1;
	self.prepare_rename_ready = false;
	self.rename_placeholder = "";
	self.rename_request_id = -1;
	lsp_workspace_edit_init(&self.rename_edit, allocator);
	self.rename_ready = false;
	self.code_action_request_id = -1;
	self.code_actions.init(allocator);
	self.code_actions_ready = false;
	self.signature_request_id = -1;
	self.signature_text = "";
	self.signature_path = "";
	self.signature_offset = 0;
	self.signature_send_at = 0.0;
	self.signature_ready = false;
	self.document_symbol_request_id = -1;
	self.document_symbol_path = "";
	self.document_symbol_list.init(allocator);
	self.document_symbols_ready = false;
	self.workspace_symbol_request_id = -1;
	self.workspace_symbol_list.init(allocator);
	self.workspace_symbols_ready = false;
	self.semantic_request_id = -1;
	self.semantic_path = "";
	self.semantic_request_version = -1;
	self.semantic_requested_version = -1;
	self.semantic_change_version = -1;
	self.semantic_send_at = 0.0;
	self.semantic_tokens.init(allocator);
	self.semantic_ready = false;
}

fn void Lsp.free_diagnostics(&self)
{
	for (sz i = 0; i < self.diag_files.len(); i++)
	{
		for (sz d = 0; d < self.diag_files[i].diags.len(); d++)
		{
			if (self.diag_files[i].diags[d].message.len)
			{
				self.diag_files[i].diags[d].message.free(self.allocator);
			}
		}
		self.diag_files[i].diags.free();
		self.diag_files[i].path.free(self.allocator);
	}
	self.diag_files.clear();
	self.diag_index.clear();
}

fn void Lsp.shutdown_all(&self)
{
	self.free_diagnostics();
	self.clear_hover();
	self.clear_definition_results();
	self.clear_completion();
	self.clear_formatting();
	self.clear_references();
	self.clear_prepare_rename();
	self.clear_rename();
	self.clear_code_actions();
	self.clear_signature();
	self.clear_document_symbols();
	self.clear_workspace_symbols();
	self.clear_semantic_tokens();
	for (sz i = 0; i < self.clients.len(); i++)
	{
		LspClient* client = self.clients[i];
		if (client.status == LspStatus.READY) client.send_notification("exit", null);
		client.destroy();
		alloc::free(self.allocator, client);
	}
	self.clients.clear();
	for (sz i = 0; i < self.docs.len(); i++)
	{
		self.docs[i].path.free(self.allocator);
		self.docs[i].uri.free(self.allocator);
		self.docs[i].language.free(self.allocator);
		if (self.docs[i].text.len) self.docs[i].text.free(self.allocator);
	}
	self.docs.clear();
	if (self.root_uri.len) self.root_uri.free(self.allocator);
	self.root_uri = "";
	self.has_root = false;
}

fn void Lsp.destroy(&self)
{
	self.shutdown_all();
	self.clients.free();
	self.docs.free();
	self.diag_files.free();
	self.diag_index.free();
	self.definition_results.free();
	self.completion_items.free();
	self.formatting_edits.free();
	self.reference_results.free();
	lsp_workspace_edit_free(&self.rename_edit, self.allocator);
	self.code_actions.free();
	self.document_symbol_list.free();
	self.workspace_symbol_list.free();
	self.semantic_tokens.free();
}

fn void Lsp.set_root(&self, String root)
{
	self.shutdown_all();
	self.root_uri = path_to_uri(self.allocator, root);
	self.has_root = true;
}

fn void Lsp.clear_diagnostics(&self, String path)
{
	int*? entry = self.diag_index.get_ref(path);
	if (catch excuse = entry) return;
	sz index = *entry;
	for (sz d = 0; d < self.diag_files[index].diags.len(); d++)
	{
		if (self.diag_files[index].diags[d].message.len)
		{
			self.diag_files[index].diags[d].message.free(self.allocator);
		}
	}
	self.diag_files[index].diags.free();
	self.diag_files[index].path.free(self.allocator);
	self.diag_files.remove_at(index);
	self.diag_index.clear();
	for (sz i = 0; i < self.diag_files.len(); i++)
	{
		self.diag_index.set(self.diag_files[i].path, (int)i);
	}
}

fn void Lsp.replace_diagnostics(&self, String path, List{LspDiagnostic}* parsed)
{
	int*? entry = self.diag_index.get_ref(path);
	if (catch excuse = entry)
	{
		FileDiagnostics file;
		file.path = path.copy(self.allocator);
		file.diags = *parsed;
		self.diag_files.push(file);
		self.diag_index.set(file.path, (int)(self.diag_files.len() - 1));
		return;
	}
	sz index = *entry;
	for (sz d = 0; d < self.diag_files[index].diags.len(); d++)
	{
		if (self.diag_files[index].diags[d].message.len)
		{
			self.diag_files[index].diags[d].message.free(self.allocator);
		}
	}
	self.diag_files[index].diags.free();
	self.diag_files[index].diags = *parsed;
}

fn LspDiagnostic[] Lsp.diagnostics_for(&self, String path)
{
	int*? entry = self.diag_index.get_ref(path);
	if (catch excuse = entry) return NO_DIAGNOSTICS;
	FileDiagnostics* file = &self.diag_files[*entry];
	return file.diags.entries[0:file.diags.len()];
}

fn void Lsp.collect_all(&self, List{LspDiagnosticRef}* out)
{
	for (sz f = 0; f < self.diag_files.len(); f++)
	{
		for (sz d = 0; d < self.diag_files[f].diags.len(); d++)
		{
			out.push({ .path = self.diag_files[f].path, .diag = self.diag_files[f].diags[d] });
		}
	}
}

fn void Lsp.counts(&self, int* errors, int* warnings, int* infos, int* hints)
{
	*errors = 0;
	*warnings = 0;
	*infos = 0;
	*hints = 0;
	for (sz f = 0; f < self.diag_files.len(); f++)
	{
		for (sz d = 0; d < self.diag_files[f].diags.len(); d++)
		{
			switch (self.diag_files[f].diags[d].severity)
			{
				case DIAGNOSTIC_ERROR:
					(*errors)++;
				case DIAGNOSTIC_WARNING:
					(*warnings)++;
				case DIAGNOSTIC_INFO:
					(*infos)++;
				default:
					(*hints)++;
			}
		}
	}
}

fn void Lsp.clear_hover(&self)
{
	if (self.hover_path.len) self.hover_path.free(self.allocator);
	if (self.hover_text.len) self.hover_text.free(self.allocator);
	self.hover_path = "";
	self.hover_text = "";
	self.hover_over = false;
	self.hover_offset = 0;
	self.hover_request_id = -1;
	self.hover_valid = false;
}

fn void Lsp.clear_definition_results(&self)
{
	for (sz i = 0; i < self.definition_results.len(); i++)
	{
		if (self.definition_results[i].path.len) self.definition_results[i].path.free(self.allocator);
	}
	self.definition_results.clear();
	self.definition_ready = false;
}

fn bool Lsp.request_definition(&self, String path, PieceTable* table, usz offset)
{
	self.clear_definition_results();
	self.definition_request_id = -1;

	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || client.status != LspStatus.READY || !client.caps.definition) return false;

	uint line      = 0;
	uint character = 0;
	position_from_offset(table, offset, &line, &character);
	@pool()
	{
		String uri     = path_to_uri(tmem, path);
		Object* params = lsp_document_position_params(tmem, uri, line, character);
		self.definition_request_id = client.send_request("textDocument/definition", params);
	};
	return true;
}

fn bool Lsp.take_definition(&self, List{DefinitionTarget}* out)
{
	if (!self.definition_ready) return false;
	self.definition_ready = false;
	self.definition_request_id = -1;
	*out = self.definition_results;
	self.definition_results.init(self.allocator);
	return true;
}

fn void Lsp.clear_completion(&self)
{
	for (sz i = 0; i < self.completion_items.len(); i++)
	{
		CompletionItem item = self.completion_items[i];
		if (item.label.len) item.label.free(self.allocator);
		if (item.filter_text.len) item.filter_text.free(self.allocator);
		if (item.sort_text.len) item.sort_text.free(self.allocator);
		if (item.insert_text.len) item.insert_text.free(self.allocator);
		if (item.detail.len) item.detail.free(self.allocator);
	}
	self.completion_items.clear();
	self.completion_ready = false;
	self.completion_incomplete = false;
}

fn bool Lsp.request_completion(&self, String path, PieceTable* table, usz offset, int trigger_kind, String trigger_char)
{
	self.clear_completion();
	self.completion_request_id = -1;

	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || client.status != LspStatus.READY || !client.caps.completion) return false;

	uint line      = 0;
	uint character = 0;
	position_from_offset(table, offset, &line, &character);
	@pool()
	{
		String uri     = path_to_uri(tmem, path);
		Object* params = lsp_completion_params(tmem, uri, line, character, trigger_kind, trigger_char);
		self.completion_request_id = client.send_request("textDocument/completion", params);
	};
	return true;
}

fn bool Lsp.take_completion(&self, List{CompletionItem}* out, bool* incomplete)
{
	if (!self.completion_ready) return false;
	self.completion_ready = false;
	self.completion_request_id = -1;
	*out = self.completion_items;
	self.completion_items.init(self.allocator);
	*incomplete = self.completion_incomplete;
	self.completion_incomplete = false;
	return true;
}

fn void Lsp.clear_formatting_edits(&self)
{
	for (sz i = 0; i < self.formatting_edits.len(); i++)
	{
		if (self.formatting_edits[i].new_text.len) self.formatting_edits[i].new_text.free(self.allocator);
	}
	self.formatting_edits.clear();
}

fn void Lsp.clear_formatting(&self)
{
	self.clear_formatting_edits();
	if (self.formatting_path.len) self.formatting_path.free(self.allocator);
	self.formatting_path = "";
	self.formatting_ready = false;
	self.formatting_request_id = -1;
}

fn bool Lsp.request_formatting(&self, String path)
{
	self.clear_formatting();

	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || client.status != LspStatus.READY || !client.caps.formatting) return false;

	@pool()
	{
		String uri     = path_to_uri(tmem, path);
		Object* params = lsp_formatting_params(tmem, uri);
		self.formatting_request_id = client.send_request("textDocument/formatting", params);
	};
	self.formatting_path = path.copy(self.allocator);
	return true;
}

fn bool Lsp.take_formatting(&self, List{FormattingEdit}* out, String* path)
{
	if (!self.formatting_ready) return false;
	self.formatting_ready = false;
	self.formatting_request_id = -1;
	*out = self.formatting_edits;
	self.formatting_edits.init(self.allocator);
	*path = self.formatting_path;
	self.formatting_path = "";
	return true;
}

fn void Lsp.clear_references(&self)
{
	for (sz i = 0; i < self.reference_results.len(); i++)
	{
		if (self.reference_results[i].path.len)
		{
			self.reference_results[i].path.free(self.allocator);
		}
	}
	self.reference_results.clear();
	self.references_ready = false;
	self.references_request_id = -1;
}

fn bool Lsp.request_references(&self, String path, PieceTable* table, usz offset)
{
	self.clear_references();

	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || client.status != LspStatus.READY || !client.caps.references) return false;

	uint line      = 0;
	uint character = 0;
	position_from_offset(table, offset, &line, &character);
	@pool()
	{
		String uri     = path_to_uri(tmem, path);
		Object* params = lsp_reference_params(tmem, uri, line, character, true);
		self.references_request_id = client.send_request("textDocument/references", params);
	};
	return true;
}

fn bool Lsp.take_references(&self, List{DefinitionTarget}* out)
{
	if (!self.references_ready) return false;
	self.references_ready = false;
	self.references_request_id = -1;
	*out = self.reference_results;
	self.reference_results.init(self.allocator);
	return true;
}

fn void Lsp.clear_prepare_rename(&self)
{
	if (self.rename_placeholder.len) self.rename_placeholder.free(self.allocator);
	self.rename_placeholder = "";
	self.prepare_rename_ready = false;
	self.prepare_rename_request_id = -1;
}

fn bool Lsp.request_prepare_rename(&self, String path, PieceTable* table, usz offset)
{
	self.clear_prepare_rename();

	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || client.status != LspStatus.READY || !client.caps.rename) return false;
	if (!client.caps.prepare_rename)
	{
		self.prepare_rename_ready = true;
		return true;
	}

	uint line      = 0;
	uint character = 0;
	position_from_offset(table, offset, &line, &character);
	@pool()
	{
		String uri     = path_to_uri(tmem, path);
		Object* params = lsp_document_position_params(tmem, uri, line, character);
		self.prepare_rename_request_id = client.send_request("textDocument/prepareRename", params);
	};
	return true;
}

fn bool Lsp.take_prepare_rename(&self, String* placeholder)
{
	if (!self.prepare_rename_ready) return false;
	self.prepare_rename_ready = false;
	self.prepare_rename_request_id = -1;
	*placeholder = self.rename_placeholder;
	self.rename_placeholder = "";
	return true;
}

fn void Lsp.clear_rename(&self)
{
	lsp_workspace_edit_free(&self.rename_edit, self.allocator);
	lsp_workspace_edit_init(&self.rename_edit, self.allocator);
	self.rename_ready = false;
	self.rename_request_id = -1;
}

fn bool Lsp.request_rename(&self, String path, PieceTable* table, usz offset, String new_name)
{
	self.clear_rename();

	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || client.status != LspStatus.READY || !client.caps.rename) return false;

	uint line      = 0;
	uint character = 0;
	position_from_offset(table, offset, &line, &character);
	@pool()
	{
		String uri     = path_to_uri(tmem, path);
		Object* params = lsp_rename_params(tmem, uri, line, character, new_name);
		self.rename_request_id = client.send_request("textDocument/rename", params);
	};
	return true;
}

fn bool Lsp.take_rename(&self, WorkspaceEdit* edit)
{
	if (!self.rename_ready) return false;
	self.rename_ready = false;
	self.rename_request_id = -1;
	*edit = self.rename_edit;
	lsp_workspace_edit_init(&self.rename_edit, self.allocator);
	return true;
}

fn void Lsp.clear_code_actions(&self)
{
	for (sz i = 0; i < self.code_actions.len(); i++)
	{
		lsp_code_action_free(&self.code_actions[i], self.allocator);
	}
	self.code_actions.clear();
	self.code_actions_ready = false;
	self.code_action_request_id = -1;
}

fn bool Lsp.request_code_actions(&self, String path, PieceTable* table, usz offset)
{
	self.clear_code_actions();

	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || client.status != LspStatus.READY || !client.caps.code_action) return false;

	uint line      = 0;
	uint character = 0;
	position_from_offset(table, offset, &line, &character);
	@pool()
	{
		String uri = path_to_uri(tmem, path);
		LspDiagnostic[] file_diagnostics = self.diagnostics_for(path);
		Object* params = lsp_code_action_params(tmem, uri, line, character, line, character, file_diagnostics);
		self.code_action_request_id = client.send_request("textDocument/codeAction", params);
	};
	return true;
}

fn bool Lsp.take_code_actions(&self, List{CodeActionItem}* out)
{
	if (!self.code_actions_ready) return false;
	self.code_actions_ready = false;
	self.code_action_request_id = -1;
	*out = self.code_actions;
	self.code_actions.init(self.allocator);
	return true;
}

fn void Lsp.clear_signature(&self)
{
	if (self.signature_text.len) self.signature_text.free(self.allocator);
	if (self.signature_path.len) self.signature_path.free(self.allocator);
	self.signature_text = "";
	self.signature_path = "";
	self.signature_offset = 0;
	self.signature_send_at = 0.0;
	self.signature_ready = false;
	self.signature_request_id = -1;
}

fn bool lsp_inside_call(PieceTable* table, usz offset, usz* open_offset)
{
	int depth = 0;
	usz i     = offset;
	while (i > 0)
	{
		i--;
		char c = table.byte_at(i);
		if (c == ')')
		{
			depth++;
			continue;
		}
		if (c == '(')
		{
			if (depth == 0)
			{
				*open_offset = i;
				return true;
			}
			depth--;
			continue;
		}
		if (depth == 0 && (c == ';' || c == '{' || c == '}'))
		{
			return false;
		}
	}
	return false;
}

fn void Lsp.update_signature(&self, double now, String path, PieceTable* table, usz offset)
{
	usz open_offset = 0;
	if (!lsp_inside_call(table, offset, &open_offset))
	{
		self.clear_signature();
		return;
	}
	if (self.signature_path.compare_to(path) == 0 && self.signature_offset == offset)
	{
		if (self.signature_ready || self.signature_request_id >= 0) return;
		if (now < self.signature_send_at) return;
	}
	else
	{
		if (self.signature_text.len) self.signature_text.free(self.allocator);
		if (self.signature_path.len) self.signature_path.free(self.allocator);
		self.signature_text = "";
		self.signature_path = path.copy(self.allocator);
		self.signature_offset = offset;
		self.signature_send_at = now + 0.12;
		self.signature_ready = false;
		self.signature_request_id = -1;
		return;
	}

	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || client.status != LspStatus.READY || !client.caps.signature_help)
	{
		return;
	}

	uint line      = 0;
	uint character = 0;
	position_from_offset(table, offset, &line, &character);
	@pool()
	{
		String uri     = path_to_uri(tmem, path);
		Object* params = lsp_document_position_params(tmem, uri, line, character);
		self.signature_request_id = client.send_request("textDocument/signatureHelp", params);
	};
}

fn void Lsp.clear_document_symbols(&self)
{
	if (self.document_symbol_path.len) self.document_symbol_path.free(self.allocator);
	self.document_symbol_path = "";
	lsp_symbols_free(&self.document_symbol_list, self.allocator);
	self.document_symbol_list.init(self.allocator);
	self.document_symbols_ready = false;
	self.document_symbol_request_id = -1;
}

fn void Lsp.update_document_symbols(&self, String path)
{
	sz index = self.doc_index(path);
	if (index < 0) return;
	LspDoc* doc = &self.docs[index];
	if (doc.symbols_requested || !doc.opened) return;

	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || client.status != LspStatus.READY || !client.caps.document_symbol) return;

	doc.symbols_requested = true;
	if (self.document_symbol_path.len) self.document_symbol_path.free(self.allocator);
	self.document_symbol_path = path.copy(self.allocator);
	@pool()
	{
		String uri     = path_to_uri(tmem, path);
		Object* params = lsp_document_symbol_params(tmem, uri);
		self.document_symbol_request_id = client.send_request("textDocument/documentSymbol", params);
	};
}

fn bool Lsp.take_document_symbols(&self, String* path, List{LspSymbol}* out)
{
	if (!self.document_symbols_ready) return false;
	self.document_symbols_ready = false;
	self.document_symbol_request_id = -1;
	*out = self.document_symbol_list;
	self.document_symbol_list.init(self.allocator);
	*path = self.document_symbol_path;
	self.document_symbol_path = "";
	return true;
}

fn void Lsp.clear_workspace_symbols(&self)
{
	lsp_symbols_free(&self.workspace_symbol_list, self.allocator);
	self.workspace_symbol_list.init(self.allocator);
	self.workspace_symbols_ready = false;
	self.workspace_symbol_request_id = -1;
}

fn bool Lsp.request_workspace_symbols(&self, String query)
{
	self.clear_workspace_symbols();

	LspClient* client = null;
	for (sz i = 0; i < self.clients.len(); i++)
	{
		if (self.clients[i].status == LspStatus.READY && self.clients[i].caps.workspace_symbol)
		{
			client = self.clients[i];
			break;
		}
	}
	if (!client) return false;

	@pool()
	{
		Object* params = lsp_workspace_symbol_params(tmem, query);
		self.workspace_symbol_request_id = client.send_request("workspace/symbol", params);
	};
	return true;
}

fn bool Lsp.take_workspace_symbols(&self, List{LspSymbol}* out)
{
	if (!self.workspace_symbols_ready) return false;
	self.workspace_symbols_ready = false;
	self.workspace_symbol_request_id = -1;
	*out = self.workspace_symbol_list;
	self.workspace_symbol_list.init(self.allocator);
	return true;
}

fn void Lsp.clear_semantic_tokens(&self)
{
	if (self.semantic_path.len) self.semantic_path.free(self.allocator);
	self.semantic_path = "";
	self.semantic_tokens.clear();
	self.semantic_ready = false;
	self.semantic_request_id = -1;
	self.semantic_request_version = -1;
	self.semantic_requested_version = -1;
	self.semantic_change_version = -1;
	self.semantic_send_at = 0.0;
}

fn void Lsp.update_semantic_tokens(&self, double now, String path)
{
	sz index = self.doc_index(path);
	if (index < 0) return;
	LspDoc* doc = &self.docs[index];

	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || client.status != LspStatus.READY || !client.caps.semantic_tokens) return;

	if (self.semantic_path.compare_to(path) != 0)
	{
		if (self.semantic_path.len) self.semantic_path.free(self.allocator);
		self.semantic_path = path.copy(self.allocator);
		self.semantic_change_version = -1;
		self.semantic_requested_version = -1;
		self.semantic_ready = false;
	}

	if (doc.version != self.semantic_change_version)
	{
		self.semantic_change_version = doc.version;
		self.semantic_send_at = now + 0.25;
		return;
	}
	if (doc.version == self.semantic_requested_version) return;
	if (now < self.semantic_send_at) return;

	if (self.semantic_path.len) self.semantic_path.free(self.allocator);
	self.semantic_path = path.copy(self.allocator);
	self.semantic_request_version = doc.version;
	self.semantic_requested_version = doc.version;
	self.semantic_ready = false;
	@pool()
	{
		String uri     = path_to_uri(tmem, path);
		Object* params = lsp_document_symbol_params(tmem, uri);
		self.semantic_request_id = client.send_request("textDocument/semanticTokens/full", params);
	};
}

fn bool Lsp.take_semantic_tokens(&self, String* path, List{SemanticToken}* out)
{
	if (!self.semantic_ready) return false;
	self.semantic_ready = false;
	*path = self.semantic_path;
	self.semantic_path = "";
	*out = self.semantic_tokens;
	self.semantic_tokens.init(self.allocator);
	self.semantic_request_id = -1;
	return true;
}

fn String Lsp.semantic_token_type(&self, String path, int token_type)
{
	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || token_type < 0 || token_type >= (int)client.caps.semantic_token_types.len()) return "";
	return client.caps.semantic_token_types[(sz)token_type];
}

fn bool Lsp.signature_valid(&self, String path, usz offset)
{
	return self.signature_ready && self.signature_path.compare_to(path) == 0 && self.signature_offset == offset;
}

fn String Lsp.signature_message(&self)
{
	return self.signature_text;
}

fn String[] Lsp.completion_triggers(&self, String path)
{
	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || client.status != LspStatus.READY) return NO_TRIGGERS;
	List{String}* triggers = &client.caps.trigger_characters;
	return triggers.entries[0:triggers.len()];
}

fn void Lsp.update_hover(&self, double now, bool over, String path, PieceTable* table, usz offset)
{
	if (!over)
	{
		if (self.hover_over) self.clear_hover();
		return;
	}
	bool changed = !self.hover_over || self.hover_offset != offset || self.hover_path.compare_to(path) != 0;
	if (changed)
	{
		if (self.hover_path.len) self.hover_path.free(self.allocator);
		if (self.hover_text.len) self.hover_text.free(self.allocator);
		self.hover_path = path.copy(self.allocator);
		self.hover_text = "";
		self.hover_offset = offset;
		self.hover_over = true;
		self.hover_request_id = -1;
		self.hover_send_at = now + 0.3;
		self.hover_valid = false;
		return;
	}
	if (self.hover_valid || self.hover_request_id >= 0) return;
	if (now < self.hover_send_at) return;

	String language   = lsp_language_for_path(path);
	LspClient* client = self.client_for(language);
	if (!client || client.status != LspStatus.READY || !client.caps.hover) return;

	uint line      = 0;
	uint character = 0;
	position_from_offset(table, offset, &line, &character);
	@pool()
	{
		String uri     = path_to_uri(tmem, path);
		Object* params = lsp_document_position_params(tmem, uri, line, character);
		self.hover_request_id = client.send_request("textDocument/hover", params);
	};
	self.hover_send_at = now + 100000.0;
}

fn bool Lsp.hover_is_valid(&self)
{
	return self.hover_valid;
}

fn String Lsp.hover_message(&self)
{
	return self.hover_text;
}

fn void Lsp.handle_notification(&self, String method, Object* params)
{
	if (method.compare_to("textDocument/publishDiagnostics") != 0) return;

	String? uri = params.get_string("uri");
	if (catch excuse = uri) return;

	@pool()
	{
		String path = uri_to_path(tmem, uri);
		List{LspDiagnostic} diags;
		diags.init(self.allocator);
		lsp_parse_diagnostics(self.allocator, params, &diags);
		self.replace_diagnostics(path, &diags);
	};
}

fn String lsp_language_for_path(String path)
{
	return language::lsp_for_path(path);
}

fn String lsp_default_command(String language)
{
	return language::lsp_command(language);
}

fn void lsp_split_command(Allocator allocator, String command, List{String}* out)
{
	DString current;
	current.init(allocator, command.len);
	bool has_current = false;

	usz i = 0;
	while (i < command.len)
	{
		char c = command[i];
		if (c == ' ' || c == '\t' || c == '\n' || c == '\r')
		{
			if (has_current)
			{
				out.push(current.str_view().copy(allocator));
				current.clear();
				has_current = false;
			}
			i++;
			continue;
		}
		if (c == '"' || c == '\'')
		{
			char quote = c;
			has_current = true;
			i++;
			while (i < command.len && command[i] != quote)
			{
				char ch = command[i];
				if (ch == '\\' && quote == '"' && i + 1 < command.len)
				{
					i++;
					ch = command[i];
				}
				current.append_char(ch);
				i++;
			}
			if (i < command.len) i++;
			continue;
		}
		has_current = true;
		current.append_char(c);
		i++;
	}

	if (has_current)
	{
		out.push(current.str_view().copy(allocator));
	}
	current.free();
}

fn LspClient* Lsp.client_for(&self, String language)
{
	for (sz i = 0; i < self.clients.len(); i++)
	{
		if (self.clients[i].language.compare_to(language) == 0) return self.clients[i];
	}
	return null;
}

fn LspClient* Lsp.ensure_client(&self, String language)
{
	LspClient* existing = self.client_for(language);
	if (existing) return existing;
	if (!self.has_root) return null;

	String command = "";
	if (self.config) command = self.config.lsp_command(language);
	if (command.len == 0) command = lsp_default_command(language);
	if (command.len == 0) return null;

	LspClient* client = alloc::new(self.allocator, LspClient);
	client.init(self.allocator, language, self.root_uri);

	bool spawned = false;
	@pool()
	{
		List{String} argv;
		argv.init(tmem);
		lsp_split_command(tmem, command, &argv);
		if (argv.len() > 0) spawned = client.spawn(argv.entries[0:argv.len()]);
	};
	if (!spawned || !client.start_threads())
	{
		client.destroy();
		alloc::free(self.allocator, client);
		return null;
	}

	@pool()
	{
		Object* params = lsp_initialize_params(tmem, self.root_uri);
		client.send_request("initialize", params);
	};
	client.status = LspStatus.STARTING;
	self.clients.push(client);
	return client;
}

fn sz Lsp.doc_index(&self, String path)
{
	for (sz i = 0; i < self.docs.len(); i++)
	{
		if (self.docs[i].path.compare_to(path) == 0) return i;
	}
	return -1;
}

fn void Lsp.handle_open(&self, String path, PieceTable* table)
{
	String language = lsp_language_for_path(path);
	if (language.len == 0) return;

	if (self.doc_index(path) >= 0)
	{
		self.handle_change(path, table);
		return;
	}

	LspClient* client = self.ensure_client(language);
	if (!client) return;

	LspDoc doc;
	doc.path = path.copy(self.allocator);
	doc.uri = path_to_uri(self.allocator, path);
	doc.language = language.copy(self.allocator);
	doc.text = table.slice(0, table.length(), self.allocator);
	doc.version = 1;
	doc.opened = false;
	doc.symbols_requested = false;
	self.docs.push(doc);
}

fn void Lsp.handle_change(&self, String path, PieceTable* table)
{
	sz index = self.doc_index(path);
	if (index < 0) return;
	LspDoc* doc = &self.docs[index];
	doc.version++;
	if (!doc.opened)
	{
		if (doc.text.len) doc.text.free(self.allocator);
		doc.text = table.slice(0, table.length(), self.allocator);
		return;
	}
	LspClient* client = self.client_for(doc.language);
	if (!client || client.status != LspStatus.READY) return;
	@pool()
	{
		String text    = table.slice(0, table.length(), tmem);
		Object* params = lsp_did_change_params(tmem, doc.uri, doc.version, text);
		client.send_notification("textDocument/didChange", params);
	};
}

fn void Lsp.handle_close(&self, String path)
{
	sz index = self.doc_index(path);
	if (index < 0) return;
	LspDoc doc = self.docs[index];
	if (doc.opened)
	{
		LspClient* client = self.client_for(doc.language);
		if (client && client.status == LspStatus.READY)
		{
			@pool()
			{
				Object* params = lsp_did_close_params(tmem, doc.uri);
				client.send_notification("textDocument/didClose", params);
			};
		}
	}
	self.clear_diagnostics(doc.path);
	if (self.semantic_path.compare_to(doc.path) == 0) self.clear_semantic_tokens();
	doc.path.free(self.allocator);
	doc.uri.free(self.allocator);
	doc.language.free(self.allocator);
	if (doc.text.len) doc.text.free(self.allocator);
	self.docs.remove_at(index);
}

fn void Lsp.mark_language_reopen(&self, String language)
{
	for (sz i = 0; i < self.docs.len(); i++)
	{
		if (self.docs[i].language.compare_to(language) == 0)
		{
			self.docs[i].opened = false;
			self.docs[i].version++;
			self.docs[i].symbols_requested = false;
		}
	}
}

fn void Lsp.update(&self, double now)
{
	for (sz i = 0; i < self.clients.len(); i++)
	{
		LspClient* client = self.clients[i];
		client.pump();
		for (sz n = 0; n < client.notifications.len(); n++)
		{
			LspNotification note = client.notifications[n];
			Object*? params_opt  = note.message.get("params");
			if (try params = params_opt) self.handle_notification(note.method, params);
			note.method.free(client.allocator);
			note.message.free();
		}
		client.notifications.clear();

		for (sz r = 0; r < client.responses.len(); r++)
		{
			LspResponse response = client.responses[r];
			if (self.hover_request_id >= 0 && response.id == self.hover_request_id && response.method.compare_to(
				"textDocument/hover"
			) == 0)
			{
				Object*? result_opt = response.message.get("result");
				if (try result = result_opt)
				{
					String? text = lsp_normalize_hover(self.allocator, result);
					if (catch excuse = text)
					{
						(void)excuse;
					}
					else
					{
						if (self.hover_text.len) self.hover_text.free(self.allocator);
						self.hover_text = text;
						self.hover_valid = true;
					}
				}
				self.hover_request_id = -1;
			}
			else if (self.definition_request_id >= 0 && response.id == self.definition_request_id
				&& response.method.compare_to(
				"textDocument/definition"
			) == 0)
			{
				self.clear_definition_results();
				Object*? result_opt = response.message.get("result");
				if (try result = result_opt)
				{
					lsp_normalize_definition(self.allocator, result, &self.definition_results);
				}
				self.definition_ready = true;
				self.definition_request_id = -1;
			}
			else if (self.completion_request_id >= 0 && response.id == self.completion_request_id
				&& response.method.compare_to(
				"textDocument/completion"
			) == 0)
			{
				self.clear_completion();
				Object*? result_opt = response.message.get("result");
				if (try result = result_opt)
				{
					lsp_normalize_completion(
						self.allocator,
						result,
						&self.completion_items,
						&self.completion_incomplete
					);
				}
				if (self.completion_items.len() == 0)
				{
					io::eprintfn("LSP: %s completion returned no items", client.language);
				}
				self.completion_ready = true;
				self.completion_request_id = -1;
			}
			else if (self.formatting_request_id >= 0 && response.id == self.formatting_request_id
				&& response.method.compare_to(
				"textDocument/formatting"
			) == 0)
			{
				self.clear_formatting_edits();
				Object*? result_opt = response.message.get("result");
				if (try result = result_opt)
				{
					lsp_parse_formatting(self.allocator, result, &self.formatting_edits);
				}
				self.formatting_ready = true;
				self.formatting_request_id = -1;
			}
			else if (self.references_request_id >= 0 && response.id == self.references_request_id
				&& response.method.compare_to(
				"textDocument/references"
			) == 0)
			{
				self.clear_references();
				Object*? result_opt = response.message.get("result");
				if (try result = result_opt)
				{
					lsp_normalize_definition(self.allocator, result, &self.reference_results);
				}
				self.references_ready = true;
				self.references_request_id = -1;
			}
			else if (self.prepare_rename_request_id >= 0 && response.id == self.prepare_rename_request_id
				&& response.method.compare_to(
				"textDocument/prepareRename"
			) == 0)
			{
				self.clear_prepare_rename();
				Object*? result_opt = response.message.get("result");
				if (try result = result_opt)
				{
					(void)lsp_parse_prepare_rename(self.allocator, result, &self.rename_placeholder);
				}
				self.prepare_rename_ready = true;
				self.prepare_rename_request_id = -1;
			}
			else if (self.rename_request_id >= 0 && response.id == self.rename_request_id && response.method.compare_to(
				"textDocument/rename"
			) == 0)
			{
				self.clear_rename();
				Object*? result_opt = response.message.get("result");
				if (try result = result_opt)
				{
					(void)lsp_parse_workspace_edit(self.allocator, result, &self.rename_edit);
				}
				self.rename_ready = true;
				self.rename_request_id = -1;
			}
			else if (self.code_action_request_id >= 0 && response.id == self.code_action_request_id
				&& response.method.compare_to(
				"textDocument/codeAction"
			) == 0)
			{
				self.clear_code_actions();
				Object*? result_opt = response.message.get("result");
				if (try result = result_opt)
				{
					lsp_parse_code_actions(self.allocator, result, &self.code_actions);
				}
				self.code_actions_ready = true;
				self.code_action_request_id = -1;
			}
			else if (self.signature_request_id >= 0 && response.id == self.signature_request_id
				&& response.method.compare_to(
				"textDocument/signatureHelp"
			) == 0)
			{
				if (self.signature_text.len) self.signature_text.free(self.allocator);
				self.signature_text = "";
				Object*? result_opt = response.message.get("result");
				if (try result = result_opt)
				{
					lsp_parse_signature_help(self.allocator, result, &self.signature_text);
				}
				self.signature_ready = self.signature_text.len > 0;
				self.signature_request_id = -1;
			}
			else if (self.document_symbol_request_id >= 0 && response.id == self.document_symbol_request_id
				&& response.method.compare_to(
				"textDocument/documentSymbol"
			) == 0)
			{
				String path = self.document_symbol_path;
				self.document_symbol_path = "";
				lsp_symbols_free(&self.document_symbol_list, self.allocator);
				self.document_symbol_list.init(self.allocator);
				Object*? result_opt = response.message.get("result");
				if (try result = result_opt)
				{
					lsp_parse_document_symbols(self.allocator, result, path, &self.document_symbol_list);
				}
				self.document_symbol_path = path;
				self.document_symbols_ready = true;
				self.document_symbol_request_id = -1;
			}
			else if (self.workspace_symbol_request_id >= 0 && response.id == self.workspace_symbol_request_id
				&& response.method.compare_to(
				"workspace/symbol"
			) == 0)
			{
				self.clear_workspace_symbols();
				Object*? result_opt = response.message.get("result");
				if (try result = result_opt)
				{
					lsp_parse_workspace_symbols(self.allocator, result, &self.workspace_symbol_list);
				}
				self.workspace_symbols_ready = true;
				self.workspace_symbol_request_id = -1;
			}
			else if (self.semantic_request_id >= 0 && response.id == self.semantic_request_id
				&& response.method.compare_to(
				"textDocument/semanticTokens/full"
			) == 0)
			{
				bool current = false;
				sz doc_index = self.doc_index(self.semantic_path);
				if (doc_index >= 0 && self.docs[doc_index].version == self.semantic_request_version)
				{
					current = true;
				}
				self.semantic_tokens.clear();
				if (current)
				{
					Object*? result_opt = response.message.get("result");
					if (try result = result_opt)
					{
						lsp_parse_semantic_tokens(self.allocator, result, &self.semantic_tokens);
					}
					self.semantic_ready = true;
				}
				self.semantic_request_id = -1;
			}
			response.method.free(client.allocator);
			response.message.free();
		}
		client.responses.clear();

		if (client.status == LspStatus.STARTING && client.handshake_done && !client.initialized_sent)
		{
			client.send_notification("initialized", null);
			client.initialized_sent = true;
			client.status = LspStatus.READY;
			client.backoff = 0.0;
		}

		if (client.process && client.status != LspStatus.STOPPED && !client.transport.is_alive(client.transport.ctx))
		{
			if (client.status != LspStatus.ERROR)
			{
				if (client.last_error.len > 0)
				{
					io::eprintfn("LSP: %s server exited (%s)", client.language, client.last_error);
				}
				else
				{
					io::eprintfn("LSP: %s server exited; restarting", client.language);
				}
				client.backoff = client.backoff == 0.0 ? 1.0 : math::min(client.backoff * 2.0, 8.0);
				client.restart_at = now + client.backoff;
				client.status = LspStatus.ERROR;
			}
		}
		if (client.status == LspStatus.ERROR && now >= client.restart_at)
		{
			if (client.restart())
			{
				self.mark_language_reopen(client.language);
			}
			else
			{
				client.backoff = math::min(client.backoff * 2.0, 8.0);
				client.restart_at = now + client.backoff;
			}
		}
	}

	for (sz i = 0; i < self.docs.len(); i++)
	{
		LspDoc* doc = &self.docs[i];
		if (doc.opened) continue;
		LspClient* client = self.client_for(doc.language);
		if (!client || client.status != LspStatus.READY) continue;
		@pool()
		{
			Object* params = lsp_did_open_params(tmem, doc.uri, doc.language, doc.version, doc.text);
			client.send_notification("textDocument/didOpen", params);
		};
		doc.opened = true;
		if (doc.text.len)
		{
			doc.text.free(self.allocator);
			doc.text = "";
		}
	}
}

fn String Lsp.status_text(&self)
{
	int total = 0;
	int ready = 0;
	for (sz i = 0; i < self.clients.len(); i++)
	{
		total++;
		if (self.clients[i].status == LspStatus.READY) ready++;
	}
	if (total == 0) return "LSP: off";
	return string::format(tmem, "LSP: %d/%d", ready, total);
}

fn void lsp_set_active(Lsp* lsp)
{
	active_lsp = lsp;
}

fn void lsp_did_open(String path, PieceTable* table)
{
	if (active_lsp) active_lsp.handle_open(path, table);
}

fn void lsp_did_change(String path, PieceTable* table)
{
	if (active_lsp) active_lsp.handle_change(path, table);
}

fn void lsp_did_close(String path)
{
	if (active_lsp) active_lsp.handle_close(path);
}

fn LspDiagnostic[] lsp_diagnostics_for(String path)
{
	if (!active_lsp) return NO_DIAGNOSTICS;
	return active_lsp.diagnostics_for(path);
}

fn void lsp_diagnostic_counts(int* errors, int* warnings, int* infos, int* hints)
{
	if (!active_lsp)
	{
		*errors = 0;
		*warnings = 0;
		*infos = 0;
		*hints = 0;
		return;
	}
	active_lsp.counts(errors, warnings, infos, hints);
}

fn void lsp_collect_all(List{LspDiagnosticRef}* out)
{
	if (active_lsp) active_lsp.collect_all(out);
}
fn bool lsp_request_definition(String path, PieceTable* table, usz offset)
{
	if (!active_lsp) return false;
	return active_lsp.request_definition(path, table, offset);
}

fn bool lsp_take_definition(List{DefinitionTarget}* out)
{
	if (!active_lsp) return false;
	return active_lsp.take_definition(out);
}
fn bool lsp_request_completion(String path, PieceTable* table, usz offset, int trigger_kind, String trigger_char)
{
	if (!active_lsp) return false;
	return active_lsp.request_completion(path, table, offset, trigger_kind, trigger_char);
}

fn bool lsp_take_completion(List{CompletionItem}* out, bool* incomplete)
{
	if (!active_lsp) return false;
	return active_lsp.take_completion(out, incomplete);
}

fn String[] lsp_completion_triggers(String path)
{
	if (!active_lsp) return NO_TRIGGERS;
	return active_lsp.completion_triggers(path);
}

fn bool lsp_request_references(String path, PieceTable* table, usz offset)
{
	if (!active_lsp) return false;
	return active_lsp.request_references(path, table, offset);
}

fn bool lsp_take_references(List{DefinitionTarget}* out)
{
	if (!active_lsp) return false;
	return active_lsp.take_references(out);
}

fn bool lsp_request_prepare_rename(String path, PieceTable* table, usz offset)
{
	if (!active_lsp) return false;
	return active_lsp.request_prepare_rename(path, table, offset);
}

fn bool lsp_take_prepare_rename(String* placeholder)
{
	if (!active_lsp) return false;
	return active_lsp.take_prepare_rename(placeholder);
}

fn bool lsp_request_rename(String path, PieceTable* table, usz offset, String new_name)
{
	if (!active_lsp) return false;
	return active_lsp.request_rename(path, table, offset, new_name);
}

fn bool lsp_take_rename(WorkspaceEdit* edit)
{
	if (!active_lsp) return false;
	return active_lsp.take_rename(edit);
}

fn bool lsp_request_code_actions(String path, PieceTable* table, usz offset)
{
	if (!active_lsp) return false;
	return active_lsp.request_code_actions(path, table, offset);
}

fn bool lsp_take_code_actions(List{CodeActionItem}* out)
{
	if (!active_lsp) return false;
	return active_lsp.take_code_actions(out);
}

fn void lsp_update_signature(double now, String path, PieceTable* table, usz offset)
{
	if (active_lsp) active_lsp.update_signature(now, path, table, offset);
}

fn bool lsp_signature_valid(String path, usz offset)
{
	if (!active_lsp) return false;
	return active_lsp.signature_valid(path, offset);
}

fn String lsp_signature_message()
{
	if (!active_lsp) return "";
	return active_lsp.signature_message();
}

fn void lsp_update_document_symbols(String path)
{
	if (active_lsp) active_lsp.update_document_symbols(path);
}

fn bool lsp_take_document_symbols(String* path, List{LspSymbol}* out)
{
	if (!active_lsp) return false;
	return active_lsp.take_document_symbols(path, out);
}

fn bool lsp_request_workspace_symbols(String query)
{
	if (!active_lsp) return false;
	return active_lsp.request_workspace_symbols(query);
}

fn bool lsp_take_workspace_symbols(List{LspSymbol}* out)
{
	if (!active_lsp) return false;
	return active_lsp.take_workspace_symbols(out);
}

fn void lsp_update_semantic_tokens(double now, String path)
{
	if (active_lsp) active_lsp.update_semantic_tokens(now, path);
}

fn bool lsp_take_semantic_tokens(String* path, List{SemanticToken}* out)
{
	if (!active_lsp) return false;
	return active_lsp.take_semantic_tokens(path, out);
}

fn String lsp_semantic_token_type(String path, int token_type)
{
	if (!active_lsp) return "";
	return active_lsp.semantic_token_type(path, token_type);
}

fn bool lsp_request_formatting(String path)
{
	if (!active_lsp) return false;
	return active_lsp.request_formatting(path);
}

fn bool lsp_take_formatting(List{FormattingEdit}* out, String* path)
{
	if (!active_lsp) return false;
	return active_lsp.take_formatting(out, path);
}