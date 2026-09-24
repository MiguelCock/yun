module yun::lsp @test;

import std::collections::list;
import std::collections::object;
import std::encoding::json;
import yun::lsp::fake;
import yun::text;

fn void test_jsonrpc_roundtrip()
{
	@pool()
	{
		String frame = jsonrpc_encode(tmem, "{\"a\":1}");
		assert(frame.compare_to("Content-Length: 7\r\n\r\n{\"a\":1}") == 0);

		usz consumed = 0;
		String? body = jsonrpc_try_parse(frame.ptr[0:frame.len], &consumed);
		if (catch excuse = body)
		{
			assert(false);
		}
		else
		{
			assert(body.compare_to("{\"a\":1}") == 0);
		}
		assert(consumed == frame.len);
	};
}

fn void test_jsonrpc_partial_and_stream()
{
	@pool()
	{
		String frame = jsonrpc_encode(tmem, "{\"a\":1}");

		usz consumed    = 0;
		String? partial = jsonrpc_try_parse(frame.ptr[0:frame.len - 2], &consumed);
		bool incomplete = false;
		if (catch excuse = partial) incomplete = true;
		assert(incomplete);
		assert(consumed == 0);

		String stream = string::format(tmem, "%s%s", frame, frame);
		usz first     = 0;
		String? one   = jsonrpc_try_parse(stream.ptr[0:stream.len], &first);
		if (catch excuse = one)
		{
			assert(false);
		}
		else
		{
			assert(one.compare_to("{\"a\":1}") == 0);
		}
		assert(first == frame.len);

		usz second  = 0;
		String? two = jsonrpc_try_parse(stream.ptr[first:stream.len - first], &second);
		if (catch excuse = two)
		{
			assert(false);
		}
		else
		{
			assert(two.compare_to("{\"a\":1}") == 0);
		}
		assert(second == frame.len);
	};
}

fn void test_jsonrpc_malformed()
{
	String bad     = "Content-Length: abc\r\n\r\n{}";
	usz consumed   = 0;
	String? result = jsonrpc_try_parse(bad.ptr[0:bad.len], &consumed);
	bool faulted   = false;
	if (catch excuse = result) faulted = true;
	assert(faulted);
	assert(consumed > 0);
}

fn void test_utf16_positions()
{
	@pool()
	{
		PieceTable t;
		t.init_from_buffer(tmem, "héllo\n😀x");

		uint line      = 99;
		uint character = 99;

		position_from_offset(&t, 0, &line, &character);
		assert(line == 0 && character == 0);

		position_from_offset(&t, 3, &line, &character);
		assert(line == 0 && character == 2);

		usz second_line = t.line_start(1);
		position_from_offset(&t, second_line + 4, &line, &character);
		assert(line == 1 && character == 2);

		assert(offset_from_position(&t, 0, 2) == 3);
		assert(offset_from_position(&t, 1, 2) == second_line + 4);
		assert(offset_from_position(&t, 0, 100) == t.line_start(0) + 6);

		t.destroy();
	};
}

fn void test_uris()
{
	@pool()
	{
		String uri = path_to_uri(tmem, "/home/a b/c#d.c3");
		assert(uri.compare_to("file:///home/a%20b/c%23d.c3") == 0);
		String path = uri_to_path(tmem, uri);
		assert(path.compare_to("/home/a b/c#d.c3") == 0);
	};
}

fn void test_message_builders()
{
	@pool()
	{
		Object* params = lsp_initialize_params(tmem, "file:///root");
		String json    = lsp_message(tmem, true, 7, "initialize", params);

		Object*? parsed = json::parse(tmem, json);
		if (catch excuse = parsed)
		{
			assert(false);
		}
		else
		{
			assert(parsed.has_key("jsonrpc"));
			assert(parsed.has_key("id"));
			assert(parsed.has_key("params"));
			Object*? method = parsed.get("method");
			if (try value = method) assert(value.s.compare_to("initialize") == 0);
			Object*? sent = parsed.get("params");
			if (try value = sent) assert(value.has_key("rootUri"));
		}
	};
}

fn void test_capabilities_parse()
{
	@pool()
	{
		String json     = "{\"capabilities\":{\"hoverProvider\":true,\"definitionProvider\":true,\"completionProvider\":{\"triggerCharacters\":[\".\",\":\"]}}}";
		Object*? parsed = json::parse(tmem, json);
		if (catch excuse = parsed)
		{
			assert(false);
		}
		else
		{
			LspCapabilities caps;
			lsp_capabilities_init(&caps, tmem);
			lsp_parse_capabilities(tmem, parsed, &caps);
			assert(caps.hover);
			assert(caps.definition);
			assert(caps.completion);
			assert(caps.trigger_characters.len() == 2);
			assert(caps.trigger_characters[0].compare_to(".") == 0);
			lsp_capabilities_free(&caps, tmem);
		}
	};
}

fn void test_diagnostics_parse()
{
	@pool()
	{
		String json     = "{\"diagnostics\":[{\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":5}},\"severity\":1,\"message\":\"boom\"}]}";
		Object*? parsed = json::parse(tmem, json);
		if (catch excuse = parsed)
		{
			assert(false);
		}
		else
		{
			List{LspDiagnostic} diags;
			diags.init(tmem);
			lsp_parse_diagnostics(tmem, parsed, &diags);
			assert(diags.len() == 1);
			assert(diags[0].start_line == 1 && diags[0].start_character == 2);
			assert(diags[0].end_line == 1 && diags[0].end_character == 5);
			assert(diags[0].severity == 1);
			assert(diags[0].message.compare_to("boom") == 0);
			diags.free();
		}
	};
}

fn void test_client_correlation()
{
	@pool()
	{
		FakeTransport fake_transport_ctx;
		fake::fake_init(&fake_transport_ctx, tmem);

		LspClient client;
		client.init(tmem, "c", "file:///root");
		client.transport = fake::fake_transport(&fake_transport_ctx);

		Object* params = lsp_initialize_params(tmem, "file:///root");
		int id         = client.send_request("initialize", params);
		assert(id == 1);
		assert(fake_transport_ctx.written.len() == 1);
		assert(fake_transport_ctx.written[0].contains("initialize"));
		assert(client.pending.len() == 1);

		String response = "{\"id\":1,\"result\":{\"capabilities\":{\"hoverProvider\":true}}}";
		client.handle_message(response);
		assert(client.handshake_done);
		assert(client.caps.hover);
		assert(client.pending.len() == 0);

		client.destroy();
		fake::fake_free(&fake_transport_ctx);
	};
}
fn void test_client_captures_notifications()
{
	@pool()
	{
		LspClient client;
		client.init(tmem, "c", "file:///root");
		client.handle_message("{\"method\":\"textDocument/publishDiagnostics\",\"params\":{\"uri\":\"file:///a.c\"}}");
		assert(client.notifications.len() == 1);
		assert(client.notifications[0].method.compare_to("textDocument/publishDiagnostics") == 0);
		assert(client.notifications[0].message.has_key("params"));
		client.clear_notifications();
		assert(client.notifications.len() == 0);
		client.destroy();
	};
}

fn void test_diagnostics_store()
{
	@pool()
	{
		Lsp lsp;
		lsp.init(tmem, null);

		Object*? params = json::parse(
			tmem,
			"{\"uri\":\"file:///proj/a.c\",\"diagnostics\":[{\"range\":{\"start\":{\"line\":0,\"character\":1},\"end\":{\"line\":0,\"character\":3}},\"severity\":1,\"message\":\"boom\"}]}"
		);
		if (catch excuse = params)
		{
			assert(false);
		}
		else
		{
			lsp.handle_notification("textDocument/publishDiagnostics", params);
		}

		assert(lsp.diagnostics_for("/proj/a.c").len == 1);
		assert(lsp.diagnostics_for("/proj/a.c")[0].message.compare_to("boom") == 0);

		int errors   = 0;
		int warnings = 0;
		int infos    = 0;
		int hints    = 0;
		lsp.counts(&errors, &warnings, &infos, &hints);
		assert(errors == 1 && warnings == 0);

		lsp.clear_diagnostics("/proj/a.c");
		assert(lsp.diagnostics_for("/proj/a.c").len == 0);
		lsp.counts(&errors, &warnings, &infos, &hints);
		assert(errors == 0);

		lsp.shutdown_all();
	};
}
fn void test_normalize_hover()
{
	@pool()
	{
		Object*? markup = json::parse(tmem, "{\"contents\":{\"kind\":\"markdown\",\"value\":\"**hi**\"}}");
		if (try obj = markup)
		{
			String? text = lsp_normalize_hover(tmem, obj);
			if (catch excuse = text)
			{
				assert(false);
			}
			else
			{
				assert(text.compare_to("**hi**") == 0);
			}
		}

		Object*? marked = json::parse(tmem, "{\"contents\":{\"language\":\"c\",\"value\":\"int x;\"}}");
		if (try obj = marked)
		{
			String? text = lsp_normalize_hover(tmem, obj);
			if (catch excuse = text)
			{
				assert(false);
			}
			else
			{
				assert(text.compare_to("```c\nint x;\n```") == 0);
			}
		}

		Object*? array = json::parse(tmem, "{\"contents\":[\"plain\",\"two\"]}");
		if (try obj = array)
		{
			String? text = lsp_normalize_hover(tmem, obj);
			if (catch excuse = text)
			{
				assert(false);
			}
			else
			{
				assert(text.compare_to("plain\n\ntwo") == 0);
			}
		}

		Object*? empty = json::parse(tmem, "{\"contents\":null}");
		if (try obj = empty)
		{
			String? text = lsp_normalize_hover(tmem, obj);
			bool faulted = false;
			if (catch excuse = text) faulted = true;
			assert(faulted);
		}

		// A null hover result (e.g. clangd hovering whitespace) must not crash.
		Object*? null_result = json::parse(tmem, "{\"result\":null}");
		if (try message = null_result)
		{
			Object*? null_result_opt = message.get("result");
			if (catch null_excuse = null_result_opt)
			{
				assert(false);
			}
			else
			{
				String? text = lsp_normalize_hover(tmem, null_result_opt);
				bool faulted = false;
				if (catch null_text_excuse = text) faulted = true;
				assert(faulted);
			}
		}

		// A non-map result (array) must also be treated as no hover.
		Object*? array_result = json::parse(tmem, "{\"result\":[\"x\"]}");
		if (try message = array_result)
		{
			Object*? array_result_opt = message.get("result");
			if (catch array_excuse = array_result_opt)
			{
				assert(false);
			}
			else
			{
				String? text = lsp_normalize_hover(tmem, array_result_opt);
				bool faulted = false;
				if (catch array_text_excuse = text) faulted = true;
				assert(faulted);
			}
		}
	};
}