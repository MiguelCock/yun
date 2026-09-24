module yun::lsp;

import std::collections::list;
import std::collections::object;
import std::core::dstring;
import std::core::mem::alloc;
import std::encoding::json;
import std::os::process;
import std::thread;
import std::thread::channel;

alias LspWriteFn = fn bool(void* ctx, char[] bytes);
alias LspReadFn = fn sz?(void* ctx, char* buffer, sz size);
alias LspAliveFn = fn bool(void* ctx);
alias LspCloseFn = fn void(void* ctx);

struct LspTransport
{
	void* ctx;
	LspWriteFn write;
	LspReadFn read;
	LspAliveFn is_alive;
	LspCloseFn close;
}

enum LspStatus : int
{
	STOPPED,
	STARTING,
	READY,
	ERROR,
}

struct LspPending
{
	int id;
	String method;
}

struct LspNotification
{
	String method;
	Object* message;
}

struct LspResponse
{
	int id;
	String method;
	Object* message;
}

struct LspClient
{
	Allocator allocator;
	LspTransport transport;
	LspStatus status;
	String language;
	String root_uri;
	Process* process;
	Thread reader;
	bool reader_started;
	Thread stderr_reader;
	bool stderr_started;
	UnboundedChannel{String}* incoming;
	UnboundedChannel{String}* errors;
	int next_id;
	bool handshake_done;
	bool initialized_sent;
	List{LspPending} pending;
	List{String} argv;
	List{LspNotification} notifications;
	List{LspResponse} responses;
	LspCapabilities caps;
	String last_error;
	double backoff;
	double restart_at;
}

fn void LspClient.init(&self, Allocator allocator, String language, String root_uri)
{
	self.allocator = allocator;
	self.transport = { };
	self.status = LspStatus.STOPPED;
	self.language = language.copy(allocator);
	self.root_uri = root_uri.copy(allocator);
	self.process = null;
	self.reader_started = false;
	self.stderr_started = false;
	self.incoming = null;
	self.errors = null;
	self.next_id = 1;
	self.handshake_done = false;
	self.initialized_sent = false;
	self.pending.init(allocator);
	self.argv.init(allocator);
	self.notifications.init(allocator);
	self.responses.init(allocator);
	lsp_capabilities_init(&self.caps, allocator);
	self.last_error = "";
	self.backoff = 0.0;
	self.restart_at = 0.0;
}

fn void LspClient.clear_notifications(&self)
{
	for (sz i = 0; i < self.notifications.len(); i++)
	{
		self.notifications[i].method.free(self.allocator);
		self.notifications[i].message.free();
	}
	self.notifications.clear();
}

fn void LspClient.clear_responses(&self)
{
	for (sz i = 0; i < self.responses.len(); i++)
	{
		self.responses[i].method.free(self.allocator);
		self.responses[i].message.free();
	}
	self.responses.clear();
}

fn void LspClient.destroy(&self)
{
	self.stop();
	self.clear_notifications();
	self.clear_responses();
	for (sz i = 0; i < self.pending.len(); i++)
	{
		self.pending[i].method.free(self.allocator);
	}
	self.pending.free();
	self.notifications.free();
	self.responses.free();
	lsp_capabilities_free(&self.caps, self.allocator);
	self.language.free(self.allocator);
	self.root_uri.free(self.allocator);
	for (sz i = 0; i < self.argv.len(); i++)
	{
		self.argv[i].free(self.allocator);
	}
	self.argv.free();
	if (self.last_error.len) self.last_error.free(self.allocator);
}

fn bool lsp_process_write(void* ctx, char[] bytes)
{
	Process* proc = (Process*)ctx;
	sz? written   = proc.write_stdin(bytes);
	if (catch excuse = written) return false;
	return written == bytes.len;
}

fn sz? lsp_process_read(void* ctx, char* buffer, sz size)
{
	Process* proc = (Process*)ctx;
	return proc.read_stdout(buffer, size);
}

fn bool lsp_process_alive(void* ctx)
{
	Process* proc = (Process*)ctx;
	bool? running = proc.is_running();
	if (catch excuse = running) return false;
	return running;
}

fn void lsp_process_close(void* ctx)
{
	Process* proc = (Process*)ctx;
	(void)proc.terminate();
	(void)proc.destroy();
	alloc::free(mem, proc);
}

fn bool LspClient.spawn(&self, String[] argv)
{
	for (sz i = 0; i < self.argv.len(); i++)
	{
		self.argv[i].free(self.allocator);
	}
	self.argv.clear();
	foreach (String arg : argv) self.argv.push(arg.copy(self.allocator));

	Process? spawned = process::spawn(
		argv,
		process::SpawnOptions.INHERIT_ENV,
		{ },
		process::CAPTURE,
		process::CAPTURE,
		process::CAPTURE
	);
	if (catch excuse = spawned)
	{
		self.status = LspStatus.ERROR;
		return false;
	}
	Process* proc = alloc::new(mem, Process);
	*proc = spawned;
	self.process = proc;
	self.transport = {
		.ctx = proc,
		.write = &lsp_process_write,
		.read = &lsp_process_read,
		.is_alive = &lsp_process_alive,
		.close = &lsp_process_close,
	};
	return true;
}

fn int lsp_reader_main(void* arg)
{
	LspClient* client = (LspClient*)arg;
	DString acc;
	acc.init(mem);
	char[8192] chunk;
	while (true)
	{
		if (!client.transport.is_alive(client.transport.ctx)) break;
		sz? read = client.transport.read(client.transport.ctx, &chunk[0], chunk.len);
		if (catch excuse = read) break;
		if (read <= 0) break;

		acc.append_bytes(chunk[0:read]);
		while (true)
		{
			usz consumed = 0;
			String? body = jsonrpc_try_parse(acc.str_view(), &consumed);
			if (catch excuse = body)
			{
				if (consumed > 0)
				{
					if (consumed >= (usz)acc.len())
					{
						acc.clear();
					}
					else
					{
						acc.delete_range(0, (sz)consumed);
					}
					continue;
				}
				break;
			}
			String copy = body.copy(mem);
			(void)client.incoming.push(copy);
			if (consumed >= (usz)acc.len())
			{
				acc.clear();
			}
			else
			{
				acc.delete_range(0, (sz)consumed);
			}
		}
	}
	acc.free();
	client.incoming.close();
	return 0;
}

fn int lsp_stderr_main(void* arg)
{
	LspClient* client = (LspClient*)arg;
	DString line;
	line.init(mem);
	char[1024] chunk;
	while (true)
	{
		if (!client.transport.is_alive(client.transport.ctx)) break;
		Process* proc = client.process;
		if (!proc) break;
		sz? read = proc.read_stderr(&chunk[0], chunk.len);
		if (catch excuse = read) break;
		if (read <= 0) break;
		for (sz i = 0; i < read; i++)
		{
			if (chunk[i] == '\n')
			{
				(void)client.errors.push(line.str_view().copy(mem));
				line.clear();
			}
			else if (chunk[i] != '\r')
			{
				line.append_char(chunk[i]);
			}
		}
	}
	line.free();
	client.errors.close();
	return 0;
}

fn bool LspClient.start_threads(&self)
{
	UnboundedChannel{String}*? incoming = channel::create_unbounded{String}(mem);
	if (catch excuse = incoming) return false;
	UnboundedChannel{String}*? errors = channel::create_unbounded{String}(mem);
	if (catch excuse = errors)
	{
		incoming.destroy();
		return false;
	}
	self.incoming = incoming;
	self.errors = errors;

	if (catch excuse = self.reader.create(&lsp_reader_main, self))
	{
		self.status = LspStatus.ERROR;
		return false;
	}
	self.reader_started = true;

	if (catch excuse = self.stderr_reader.create(&lsp_stderr_main, self))
	{
		self.stderr_started = false;
	}
	else
	{
		self.stderr_started = true;
	}
	return true;
}

fn void LspClient.stop(&self)
{
	if (self.process) (void)self.process.terminate();
	if (self.reader_started)
	{
		(void)self.reader.join();
		self.reader_started = false;
	}
	if (self.stderr_started)
	{
		(void)self.stderr_reader.join();
		self.stderr_started = false;
	}
	if (self.process)
	{
		self.transport.close(self.transport.ctx);
		self.process = null;
	}
	if (self.incoming)
	{
		self.incoming.destroy();
		self.incoming = null;
	}
	if (self.errors)
	{
		self.errors.destroy();
		self.errors = null;
	}
	self.status = LspStatus.STOPPED;
}

fn bool LspClient.restart(&self)
{
	self.stop();
	self.clear_notifications();
	self.clear_responses();
	self.handshake_done = false;
	self.initialized_sent = false;
	for (sz i = 0; i < self.pending.len(); i++)
	{
		self.pending[i].method.free(self.allocator);
	}
	self.pending.clear();
	lsp_capabilities_free(&self.caps, self.allocator);
	lsp_capabilities_init(&self.caps, self.allocator);

	if (!self.spawn(self.argv.entries[0:self.argv.len()])) return false;
	if (!self.start_threads()) return false;
	@pool()
	{
		Object* params = lsp_initialize_params(tmem, self.root_uri);
		self.send_request("initialize", params);
	};
	self.status = LspStatus.STARTING;
	return true;
}

fn bool LspClient.send_raw(&self, Allocator allocator, String json)
{
	String frame = jsonrpc_encode(allocator, json);
	return self.transport.write(self.transport.ctx, frame.ptr[0:frame.len]);
}

fn int LspClient.send_request(&self, String method, Object* params)
{
	int id = self.next_id;
	self.next_id++;
	@pool()
	{
		String json = lsp_message(tmem, true, id, method, params);
		if (!self.send_raw(tmem, json)) self.status = LspStatus.ERROR;
	};
	self.pending.push({ .id = id, .method = method.copy(self.allocator) });
	return id;
}

fn void LspClient.send_notification(&self, String method, Object* params)
{
	@pool()
	{
		String json = lsp_message(tmem, false, 0, method, params);
		if (!self.send_raw(tmem, json)) self.status = LspStatus.ERROR;
	};
}

fn void LspClient.pump(&self)
{
	if (self.incoming)
	{
		while (true)
		{
			String? raw = self.incoming.try_pop();
			if (catch excuse = raw) break;
			self.handle_message(raw);
			raw.free(mem);
		}
	}
	if (self.errors)
	{
		while (true)
		{
			String? line = self.errors.try_pop();
			if (catch excuse = line) break;
			if (self.last_error.len) self.last_error.free(self.allocator);
			self.last_error = line.copy(self.allocator);
			line.free(mem);
		}
	}
}

fn void LspClient.resolve_pending(&self, int id, Object* message)
{
	for (sz i = 0; i < self.pending.len(); i++)
	{
		if (self.pending[i].id != id) continue;
		String method = self.pending[i].method;

		if (message.has_key("error"))
		{
			if (method.compare_to("initialize") == 0) self.status = LspStatus.ERROR;
			message.free();
		}
		else if (method.compare_to("initialize") == 0)
		{
			Object*? result_opt = message.get("result");
			if (try result = result_opt)
			{
				lsp_parse_capabilities(self.allocator, result, &self.caps);
			}
			self.handshake_done = true;
			message.free();
		}
		else
		{
			self.responses.push({ .id = id, .method = method.copy(self.allocator), .message = message });
		}

		self.pending[i].method.free(self.allocator);
		self.pending.remove_at(i);
		return;
	}
	message.free();
}

fn void LspClient.handle_message(&self, String json)
{
	Object*? parsed = json::parse(self.allocator, json);
	if (catch excuse = parsed) return;
	Object* message = parsed;

	Object*? id_opt = message.get("id");
	if (try id_obj = id_opt)
	{
		int? id = id_obj.to_value(int);
		if (try value = id)
		{
			self.resolve_pending(value, message);
			return;
		}
	}

	Object*? method_opt = message.get("method");
	if (try method = method_opt)
	{
		self.notifications.push({ .method = method.s.copy(self.allocator), .message = message });
		return;
	}
	message.free();
}