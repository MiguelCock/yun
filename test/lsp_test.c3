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

fn void test_notification_empty_params()
{
	@pool()
	{
		String json = lsp_message(tmem, false, 0, "initialized", null);

		Object*? parsed = json::parse(tmem, json);
		if (catch excuse = parsed)
		{
			assert(false);
		}
		else
		{
			assert(!parsed.has_key("id"));
			Object*? params = parsed.get("params");
			if (try value = params)
			{
				assert(value.is_map());
				assert(value.get_len() == 0);
			}
			else
			{
				assert(false);
			}
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

fn void test_client_answers_server_requests()
{
	@pool()
	{
		FakeTransport fake_ctx;
		fake::fake_init(&fake_ctx, tmem);

		LspClient client;
		client.init(tmem, "c", "file:///root");
		client.transport = fake::fake_transport(&fake_ctx);

		client.handle_message("{\"id\":42,\"method\":\"client/registerCapability\",\"params\":{}}");
		assert(fake_ctx.written.len() == 1);
		assert(fake_ctx.written[0].contains("\"id\":42"));
		assert(fake_ctx.written[0].contains("\"result\":null"));

		client.handle_message("{\"id\":43,\"method\":\"workspace/configuration\",\"params\":{\"items\":[{},{}]}}");
		assert(fake_ctx.written.len() == 2);
		assert(fake_ctx.written[1].contains("\"result\":[{},{}]"));

		client.handle_message("{\"id\":44,\"method\":\"workspace/applyEdit\",\"params\":{}}");
		assert(fake_ctx.written.len() == 3);
		assert(fake_ctx.written[2].contains("\"applied\":false"));

		client.destroy();
		fake::fake_free(&fake_ctx);
	};
}

fn void test_client_handles_request_error()
{
	@pool()
	{
		LspClient client;
		client.init(tmem, "zig", "file:///root");
		client.pending.push({ .id = 7, .method = "textDocument/completion".copy(tmem) });

		client.handle_message("{\"id\":7,\"error\":{\"code\":-32601,\"message\":\"nope\"}}");
		assert(client.pending.len() == 0);
		assert(client.responses.len() == 0);

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
fn void test_normalize_definition()
{
	@pool()
	{
		List{DefinitionTarget} out;
		out.init(tmem);

		Object*? loc = json::parse(
			tmem,
			"{\"uri\":\"file:///a.c\",\"range\":{\"start\":{\"line\":1,\"character\":2},\"end\":{\"line\":1,\"character\":5}}}"
		);
		if (try obj = loc) lsp_normalize_definition(tmem, obj, &out);
		assert(out.len() == 1);
		assert(out[0].path.compare_to("/a.c") == 0);
		assert(out[0].line == 1 && out[0].character == 2);
		out.clear();

		Object*? arr = json::parse(
			tmem,
			"[{\"uri\":\"file:///a.c\",\"range\":{\"start\":{\"line\":0,\"character\":0},\"end\":{\"line\":0,\"character\":1}}},{\"targetUri\":\"file:///b.c\",\"targetSelectionRange\":{\"start\":{\"line\":3,\"character\":4},\"end\":{\"line\":3,\"character\":5}}}]"
		);
		if (try obj = arr) lsp_normalize_definition(tmem, obj, &out);
		assert(out.len() == 2);
		assert(out[1].path.compare_to("/b.c") == 0);
		assert(out[1].line == 3 && out[1].character == 4);
		out.clear();

		Object*? msg = json::parse(tmem, "{\"result\":null}");
		if (try obj = msg)
		{
			Object*? result_opt = obj.get("result");
			if (catch def_excuse = result_opt)
			{
				assert(false);
			}
			else
			{
				lsp_normalize_definition(tmem, result_opt, &out);
			}
		}
		assert(out.len() == 0);

		out.free();
	};
}
fn void test_normalize_completion()
{
	@pool()
	{
		List{CompletionItem} out;
		out.init(tmem);
		bool incomplete = false;

		Object*? arr = json::parse(
			tmem,
			"[{\"label\":\"foo\",\"kind\":3,\"filterText\":\"fooF\"},{\"label\":\"bar\",\"insertText\":\"bar()\"}]"
		);
		if (try obj = arr) lsp_normalize_completion(tmem, obj, &out, &incomplete);
		assert(out.len() == 2);
		assert(out[0].label.compare_to("foo") == 0);
		assert(out[0].kind == 3);
		assert(out[0].filter_text.compare_to("fooF") == 0);
		assert(out[1].insert_text.compare_to("bar()") == 0);
		assert(!incomplete);
		out.clear();

		Object*? list = json::parse(
			tmem,
			"{\"isIncomplete\":true,\"items\":[{\"label\":\"baz\",\"textEdit\":{\"newText\":\"baz!\",\"range\":{\"start\":{\"line\":0,\"character\":2},\"end\":{\"line\":0,\"character\":5}}}}]}"
		);
		if (try obj = list) lsp_normalize_completion(tmem, obj, &out, &incomplete);
		assert(out.len() == 1);
		assert(out[0].has_text_edit);
		assert(out[0].insert_text.compare_to("baz!") == 0);
		assert(out[0].edit_start_character == 2);
		assert(out[0].edit_end_character == 5);
		assert(incomplete);
		out.free();
	};
}

fn void test_lsp_language_detection()
{
	assert(lsp_language_for_path("src/main.c3").compare_to("c3") == 0);
	assert(lsp_language_for_path("lib/foo.c3i").compare_to("c3") == 0);
	assert(lsp_language_for_path("src/main.c").compare_to("c") == 0);
	assert(lsp_language_for_path("include/foo.h").compare_to("c") == 0);
	assert(lsp_language_for_path("src/main.cpp").compare_to("cpp") == 0);
	assert(lsp_language_for_path("src/main.cc").compare_to("cpp") == 0);
	assert(lsp_language_for_path("src/main.cxx").compare_to("cpp") == 0);
	assert(lsp_language_for_path("include/foo.hpp").compare_to("cpp") == 0);
	assert(lsp_language_for_path("include/foo.hh").compare_to("cpp") == 0);
	assert(lsp_language_for_path("include/foo.hxx").compare_to("cpp") == 0);
	assert(lsp_language_for_path("script.py").compare_to("python") == 0);
	assert(lsp_language_for_path("app.js").compare_to("javascript") == 0);
	assert(lsp_language_for_path("app.mjs").compare_to("javascript") == 0);
	assert(lsp_language_for_path("app.cjs").compare_to("javascript") == 0);
	assert(lsp_language_for_path("app.jsx").compare_to("javascript") == 0);
	assert(lsp_language_for_path("app.ts").compare_to("typescript") == 0);
	assert(lsp_language_for_path("app.tsx").compare_to("typescript") == 0);
	assert(lsp_language_for_path("main.go").compare_to("go") == 0);
	assert(lsp_language_for_path("lib.rs").compare_to("rust") == 0);
	assert(lsp_language_for_path("build.zig").compare_to("zig") == 0);
	assert(lsp_language_for_path("build.zon").compare_to("zig") == 0);
	assert(lsp_language_for_path("main.odin").compare_to("odin") == 0);
	assert(lsp_language_for_path("main.v").compare_to("v") == 0);
	assert(lsp_language_for_path("main.nim").compare_to("nim") == 0);
	assert(lsp_language_for_path("main.nims").compare_to("nim") == 0);
	assert(lsp_language_for_path("Main.java").compare_to("java") == 0);
	assert(lsp_language_for_path("Main.kt").compare_to("kotlin") == 0);
	assert(lsp_language_for_path("build.gradle.kts").compare_to("kotlin") == 0);
	assert(lsp_language_for_path("Main.scala").compare_to("scala") == 0);
	assert(lsp_language_for_path("build.sc").compare_to("scala") == 0);
	assert(lsp_language_for_path("build.sbt").compare_to("scala") == 0);
	assert(lsp_language_for_path("Program.cs").compare_to("csharp") == 0);
	assert(lsp_language_for_path("app.ts").compare_to("typescript") == 0);
	assert(lsp_language_for_path("app.mts").compare_to("typescript") == 0);
	assert(lsp_language_for_path("app.cts").compare_to("typescript") == 0);
	assert(lsp_language_for_path("style.css").compare_to("css") == 0);
	assert(lsp_language_for_path("index.html").compare_to("html") == 0);
	assert(lsp_language_for_path("index.htm").compare_to("html") == 0);
	assert(lsp_language_for_path("init.lua").compare_to("lua") == 0);
	assert(lsp_language_for_path("index.php").compare_to("php") == 0);
	assert(lsp_language_for_path("app.rb").compare_to("ruby") == 0);
	assert(lsp_language_for_path("analysis.r").compare_to("r") == 0);
	assert(lsp_language_for_path("analysis.R").compare_to("r") == 0);
	assert(lsp_language_for_path("main.jl").compare_to("julia") == 0);
	assert(lsp_language_for_path("Main.hs").compare_to("haskell") == 0);
	assert(lsp_language_for_path("app.gleam").compare_to("gleam") == 0);
	assert(lsp_language_for_path("server.erl").compare_to("erlang") == 0);
	assert(lsp_language_for_path("server.hrl").compare_to("erlang") == 0);
	assert(lsp_language_for_path("lib.ex").compare_to("elixir") == 0);
	assert(lsp_language_for_path("test.exs").compare_to("elixir") == 0);
	assert(lsp_language_for_path("main.dart").compare_to("dart") == 0);
	assert(lsp_language_for_path("README.md").compare_to("markdown") == 0);
	assert(lsp_language_for_path("doc.markdown").compare_to("markdown") == 0);
	assert(lsp_language_for_path("notes.txt").len == 0);
	assert(lsp_language_for_path("Makefile").len == 0);
	assert(lsp_language_for_path("dir.with.dots/file").len == 0);
}

fn void test_lsp_default_commands()
{
	assert(lsp_default_command("c3").compare_to("c3lsp") == 0);
	assert(lsp_default_command("c").compare_to("clangd") == 0);
	assert(lsp_default_command("cpp").compare_to("clangd") == 0);
	assert(lsp_default_command("python").compare_to("pyright-langserver --stdio") == 0);
	assert(lsp_default_command("javascript").compare_to("typescript-language-server --stdio") == 0);
	assert(lsp_default_command("typescript").compare_to("typescript-language-server --stdio") == 0);
	assert(lsp_default_command("go").compare_to("gopls") == 0);
	assert(lsp_default_command("rust").compare_to("rust-analyzer") == 0);
	assert(lsp_default_command("zig").compare_to("zls") == 0);
	assert(lsp_default_command("odin").compare_to("ols") == 0);
	assert(lsp_default_command("v").compare_to("v-analyzer") == 0);
	assert(lsp_default_command("nim").compare_to("nimlangserver") == 0);
	assert(lsp_default_command("java").compare_to("jdtls") == 0);
	assert(lsp_default_command("kotlin").compare_to("kotlin-language-server") == 0);
	assert(lsp_default_command("scala").compare_to("metals") == 0);
	assert(lsp_default_command("csharp").compare_to("csharp-ls") == 0);
	assert(lsp_default_command("css").compare_to("vscode-css-language-server --stdio") == 0);
	assert(lsp_default_command("html").compare_to("vscode-html-language-server --stdio") == 0);
	assert(lsp_default_command("lua").compare_to("lua-language-server") == 0);
	assert(lsp_default_command("php").compare_to("intelephense --stdio") == 0);
	assert(lsp_default_command("ruby").compare_to("ruby-lsp") == 0);
	assert(lsp_default_command("r").compare_to("R --no-echo -e \"languageserver::run()\"") == 0);
	assert(lsp_default_command("julia")
		.compare_to(
			"julia --startup-file=no --history-file=no -e \"using LanguageServer; LanguageServer.runserver()\""
		) == 0);
	assert(lsp_default_command("haskell").compare_to("haskell-language-server-wrapper --lsp") == 0);
	assert(lsp_default_command("gleam").compare_to("gleam lsp") == 0);
	assert(lsp_default_command("erlang").compare_to("elp server") == 0);
	assert(lsp_default_command("elixir").compare_to("elixir-ls") == 0);
	assert(lsp_default_command("dart").compare_to("dart language-server --protocol=lsp") == 0);
	assert(lsp_default_command("markdown").compare_to("marksman server") == 0);
	assert(lsp_default_command("unknown").len == 0);
}

fn void test_did_open_language_id()
{
	@pool()
	{
		Object* params   = lsp_did_open_params(tmem, "file:///proj/a.c3", "c3", 1, "fn int main() {}");
		Object*? doc_opt = params.get("textDocument");
		if (catch excuse = doc_opt)
		{
			assert(false);
		}
		else
		{
			Object* doc  = doc_opt;
			String? lang = doc.get_string("languageId");
			if (catch lang_excuse = lang)
			{
				assert(false);
			}
			else
			{
				assert(lang.compare_to("c3") == 0);
			}
		}
	};
}
fn void test_split_command()
{
	@pool()
	{
		List{String} out;
		out.init(tmem);

		lsp_split_command(tmem, "c3lsp", &out);
		assert(out.len() == 1 && out[0].compare_to("c3lsp") == 0);
		out.clear();

		lsp_split_command(tmem, "intelephense --stdio", &out);
		assert(out.len() == 2);
		assert(out[0].compare_to("intelephense") == 0 && out[1].compare_to("--stdio") == 0);
		out.clear();

		lsp_split_command(tmem, "R --no-echo -e \"languageserver::run()\"", &out);
		assert(out.len() == 4);
		assert(out[0].compare_to("R") == 0);
		assert(out[3].compare_to("languageserver::run()") == 0);
		out.clear();

		lsp_split_command(tmem, "julia -e 'using LanguageServer; run()'", &out);
		assert(out.len() == 3);
		assert(out[2].compare_to("using LanguageServer; run()") == 0);
		out.clear();

		lsp_split_command(tmem, "sh -c \"echo \\\"hi\\\"\"", &out);
		assert(out.len() == 3);
		assert(out[2].compare_to("echo \"hi\"") == 0);
		out.clear();

		lsp_split_command(tmem, "  a\tb  c  ", &out);
		assert(out.len() == 3);
		assert(out[0].compare_to("a") == 0 && out[2].compare_to("c") == 0);
		out.free();
	};
}