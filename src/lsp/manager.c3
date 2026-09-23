module yun::lsp;

import std::collections::list;
import std::collections::object;
import std::core::mem::alloc;
import std::math;
import yun::config;
import yun::text;

struct LspDoc
{
	String path;
	String uri;
	String language;
	String text;
	long version;
	bool opened;
}

struct Lsp
{
	Allocator allocator;
	config::Config* config;
	String root_uri;
	bool has_root;
	List{LspClient*} clients;
	List{LspDoc} docs;
}

Lsp* active_lsp;

fn void Lsp.init(&self, Allocator allocator, config::Config* config)
{
	self.allocator = allocator;
	self.config = config;
	self.root_uri = "";
	self.has_root = false;
	self.clients.init(allocator);
	self.docs.init(allocator);
}

fn void Lsp.shutdown_all(&self)
{
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

fn void Lsp.set_root(&self, String root)
{
	self.shutdown_all();
	self.root_uri = path_to_uri(self.allocator, root);
	self.has_root = true;
}

fn String lsp_extension(String path)
{
	sz dot = -1;
	for (sz i = (sz)path.len; i > 0; i--)
	{
		char c = path[(usz)(i - 1)];
		if (c == '.')
		{
			dot = i - 1;
			break;
		}
		if (c == '/' || c == '\\') break;
	}
	if (dot < 0) return "";
	return path[(usz)dot:path.len - (usz)dot];
}

fn String lsp_language_for_path(String path)
{
	String ext = lsp_extension(path);
	if (ext.compare_to(".c3") == 0 || ext.compare_to(".c3i") == 0) return "c3";
	if (ext.compare_to(".c") == 0 || ext.compare_to(".h") == 0) return "c";
	if (ext.compare_to(
		".cpp"
	) == 0 || ext.compare_to(
		".cc"
	) == 0 || ext.compare_to(".cxx") == 0 || ext.compare_to(".hpp") == 0 || ext.compare_to(".hh") == 0) return "cpp";
	if (ext.compare_to(".py") == 0) return "python";
	if (ext.compare_to(
		".js"
	) == 0 || ext.compare_to(
		".mjs"
	) == 0 || ext.compare_to(".cjs") == 0 || ext.compare_to(".jsx") == 0) return "javascript";
	if (ext.compare_to(".ts") == 0 || ext.compare_to(".tsx") == 0) return "typescript";
	return "";
}

fn String lsp_default_command(String language)
{
	if (language.compare_to("c3") == 0) return "c3lsp";
	if (language.compare_to("c") == 0 || language.compare_to("cpp") == 0) return "clangd";
	if (language.compare_to("python") == 0) return "pyright-langserver --stdio";
	if (language.compare_to("javascript") == 0 || language.compare_to("typescript") == 0)
	{
		return "typescript-language-server --stdio";
	}
	return "";
}

fn void lsp_split_command(Allocator allocator, String command, List{String}* out)
{
	usz i = 0;
	while (i < command.len)
	{
		while (i < command.len && (command[i] == ' ' || command[i] == '\t')) i++;
		usz start = i;
		while (i < command.len && command[i] != ' ' && command[i] != '\t') i++;
		if (i > start) out.push(command[start:i - start].copy(allocator));
	}
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
		}
	}
}

fn void Lsp.update(&self, double now)
{
	for (sz i = 0; i < self.clients.len(); i++)
	{
		LspClient* client = self.clients[i];
		client.pump();

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