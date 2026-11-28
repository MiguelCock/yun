module yun::console @test;

import raylib6::rl;
import std::io::file;
import std::io::path;
import std::math::geometry;
import std::os::env;
import std::thread;
import yun::ui;
import yun::console_test_helpers;

fn void test_buffer_partial_lines()
{
	ConsoleBuffer buffer;
	buffer.init(mem);
	defer buffer.destroy();

	buffer.append_stdout("hel");
	assert(buffer.line_count() == 0);
	buffer.append_stdout("lo\nwor");
	assert(buffer.line_count() == 1);
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.STDOUT, "hello");
	buffer.append_stdout("ld\n");
	assert(buffer.line_count() == 2);
	console_test_helpers::expect_line(&buffer, 1, ConsoleStream.STDOUT, "world");
}

fn void test_buffer_crlf_and_cr()
{
	ConsoleBuffer buffer;
	buffer.init(mem);
	defer buffer.destroy();

	buffer.append_stdout("a\r\nb\rc\n");
	assert(buffer.line_count() == 3);
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.STDOUT, "a");
	console_test_helpers::expect_line(&buffer, 1, ConsoleStream.STDOUT, "b");
	console_test_helpers::expect_line(&buffer, 2, ConsoleStream.STDOUT, "c");
}

fn void test_buffer_flushes_partial_line()
{
	ConsoleBuffer buffer;
	buffer.init(mem);
	defer buffer.destroy();

	buffer.append_stderr("warning");
	assert(buffer.line_count() == 0);
	buffer.flush();
	assert(buffer.line_count() == 1);
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.STDERR, "warning");
}

fn void test_buffer_ansi_csi_and_osc()
{
	ConsoleBuffer buffer;
	buffer.init(mem);
	defer buffer.destroy();

	buffer.append_stdout("\x1b[31mred\x1b[0m\n");
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.STDOUT, "red");
	buffer.append_stdout("a\x1b]0;title\x07b\n");
	console_test_helpers::expect_line(&buffer, 1, ConsoleStream.STDOUT, "ab");
	buffer.append_stdout("x\x1b[3");
	buffer.append_stdout("2mz\n");
	console_test_helpers::expect_line(&buffer, 2, ConsoleStream.STDOUT, "xz");
}

fn void test_buffer_utf8()
{
	ConsoleBuffer buffer;
	buffer.init(mem);
	defer buffer.destroy();

	buffer.append_stdout("héllo\n");
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.STDOUT, "héllo");

	char[3] bad = { (char)0xFF, 'x', '\n' };
	buffer.append_stdout((String)bad[0:3]);
	char[5] expected = { (char)0xEF, (char)0xBF, (char)0xBD, 'x', 0 };
	console_test_helpers::expect_line(&buffer, 1, ConsoleStream.STDOUT, (String)expected[0:4]);
}

fn void test_buffer_tabs()
{
	ConsoleBuffer buffer;
	buffer.init(mem);
	defer buffer.destroy();

	buffer.append_stdout("a\tb\n");
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.STDOUT, "a    b");
}

fn void test_buffer_line_cap()
{
	ConsoleBuffer buffer;
	buffer.init(mem, 3, 1024 * 1024);
	defer buffer.destroy();

	buffer.append_stdout("1\n2\n3\n4\n5\n");
	assert(buffer.line_count() == 3);
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.STDOUT, "3");
	console_test_helpers::expect_line(&buffer, 1, ConsoleStream.STDOUT, "4");
	console_test_helpers::expect_line(&buffer, 2, ConsoleStream.STDOUT, "5");
	assert(buffer.truncated);
}

fn void test_buffer_byte_cap()
{
	ConsoleBuffer buffer;
	buffer.init(mem, 100, 8);
	defer buffer.destroy();

	buffer.append_stdout("aaaa\nbbbb\ncccc\n");
	assert(buffer.line_count() == 2);
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.STDOUT, "bbbb");
	console_test_helpers::expect_line(&buffer, 1, ConsoleStream.STDOUT, "cccc");
	assert(buffer.truncated);
}

fn void test_buffer_command_flushes_output()
{
	ConsoleBuffer buffer;
	buffer.init(mem);
	defer buffer.destroy();

	buffer.append_stdout("partial");
	buffer.append_command("make");
	assert(buffer.line_count() == 2);
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.STDOUT, "partial");
	console_test_helpers::expect_line(&buffer, 1, ConsoleStream.COMMAND, "$ make");
}

fn void test_buffer_clear()
{
	ConsoleBuffer buffer;
	buffer.init(mem, 2, 1024);
	defer buffer.destroy();

	buffer.append_stdout("a\nb\nc\n");
	assert(buffer.line_count() == 2);
	assert(buffer.truncated);
	buffer.clear();
	assert(buffer.line_count() == 0);
	assert(buffer.total_bytes == 0);
	assert(!buffer.truncated);
	buffer.append_stdout("d\n");
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.STDOUT, "d");
}

fn void test_shell_quoting()
{
	assert(shell_quote_posix(tmem, "/tmp/proj").compare_to("'/tmp/proj'") == 0);
	assert(shell_quote_posix(tmem, "a b").compare_to("'a b'") == 0);
	assert(shell_quote_posix(tmem, "it's").compare_to("'it'\\''s'") == 0);
	assert(console_posix_command(tmem, "/tmp/proj", "echo hi").compare_to("cd '/tmp/proj' && echo hi") == 0);
	assert(console_windows_command(tmem, "C:\\proj", "echo hi")
		.compare_to("chcp 65001 >nul & cd /D \"C:\\proj\" && echo hi") == 0);
}

fn void test_runner_stdout_stderr_exit()
{
	ConsoleBuffer buffer;
	buffer.init(mem);
	defer buffer.destroy();

	ConsoleRunner runner;
	runner.init(mem);
	defer runner.destroy(&buffer);

	String command = console_test_helpers::test_command(false);
	assert(runner.start(&buffer, ".", command));
	assert(console_test_helpers::wait_runner(&runner, &buffer, 500));
	assert(runner.status == ConsoleStatus.EXITED);
	assert(runner.exit_code == 3);
	assert(console_test_helpers::has_line(&buffer, "out"));
	assert(console_test_helpers::has_line(&buffer, "err"));
}

fn void test_runner_rejects_concurrent()
{
	ConsoleBuffer buffer;
	buffer.init(mem);
	defer buffer.destroy();

	ConsoleRunner runner;
	runner.init(mem);
	defer runner.destroy(&buffer);

	assert(runner.start(&buffer, ".", console_test_helpers::test_command(true)));
	(void)thread::sleep_ms(50);
	assert(runner.running());
	assert(!runner.start(&buffer, ".", "echo second"));
	assert(runner.kill());
	assert(console_test_helpers::wait_runner(&runner, &buffer, 500));
	assert(runner.status == ConsoleStatus.KILLED);
	assert(runner.exit_code != 0);
}

fn void test_runner_empty_output()
{
	ConsoleBuffer buffer;
	buffer.init(mem);
	defer buffer.destroy();

	ConsoleRunner runner;
	runner.init(mem);
	defer runner.destroy(&buffer);

	$if env::WIN32:
		String command = "ver >nul";
	$else
		String command = "true";
	$endif
	assert(runner.start(&buffer, ".", command));
	assert(console_test_helpers::wait_runner(&runner, &buffer, 500));
	assert(runner.status == ConsoleStatus.EXITED);
	assert(runner.exit_code == 0);
	assert(buffer.line_count() == 1);
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.COMMAND, string::format(tmem, "$ %s", command));
}

fn void test_console_requires_root()
{
	Console console;
	console.init(mem);
	defer console.destroy();

	assert(!console.run("echo hi"));
	assert(console.buffer.line_count() == 2);
	console_test_helpers::expect_line(&console.buffer, 0, ConsoleStream.COMMAND, "$ echo hi");
	console_test_helpers::expect_line(&console.buffer, 1, ConsoleStream.STDERR, "No project open");
}
fn void test_input_editing()
{
	ConsoleInput input;
	input.init(mem);
	defer input.destroy();

	input.set("abc");
	assert(input.len() == 3);
	input.move_left();
	input.insert_codepoint('X');
	assert(input.text_view().compare_to("abXc") == 0);
	input.backspace();
	assert(input.text_view().compare_to("abc") == 0);
	input.delete_forward();
	assert(input.text_view().compare_to("ab") == 0);

	input.home();
	input.insert_codepoint('Z');
	assert(input.text_view().compare_to("Zab") == 0);
	input.end();
	input.move_left();
	input.backspace();
	assert(input.text_view().compare_to("Zb") == 0);

	input.set("ad");
	input.home();
	input.move_right();
	input.insert_string("bc");
	assert(input.text_view().compare_to("abcd") == 0);
}

fn void test_input_utf8_boundaries()
{
	ConsoleInput input;
	input.init(mem);
	defer input.destroy();

	input.set("é");
	assert(input.len() == 2);
	input.move_left();
	assert(input.cursor == 0);
	input.insert_codepoint('a');
	assert(input.text_view().compare_to("aé") == 0);
	input.backspace();
	assert(input.text_view().compare_to("é") == 0);
	input.end();
	input.backspace();
	assert(input.len() == 0);
	assert(input.cursor == 0);
}

fn void test_history_navigation()
{
	ConsoleInput input;
	input.init(mem);
	defer input.destroy();

	ConsoleHistory history;
	history.init(mem, 3);
	defer history.destroy();

	history.add("one");
	history.add("two");
	history.add("two");
	assert(history.entries.len() == 2);

	input.set("draft");
	assert(history.previous(&input));
	assert(input.text_view().compare_to("two") == 0);
	assert(history.previous(&input));
	assert(input.text_view().compare_to("one") == 0);
	assert(history.previous(&input));
	assert(input.text_view().compare_to("one") == 0);
	assert(history.next(&input));
	assert(input.text_view().compare_to("two") == 0);
	assert(history.next(&input));
	assert(input.text_view().compare_to("draft") == 0);
	assert(!history.next(&input));
}

fn void test_history_capacity_and_empty()
{
	ConsoleInput input;
	input.init(mem);
	defer input.destroy();

	ConsoleHistory history;
	history.init(mem, 2);
	defer history.destroy();

	assert(!history.previous(&input));
	history.add("a");
	history.add("b");
	history.add("c");
	assert(history.entries.len() == 2);
	assert(history.entries[0].compare_to("b") == 0);
	assert(history.entries[1].compare_to("c") == 0);
}

fn void test_console_submit_records_history()
{
	Console console;
	console.init(mem);
	defer console.destroy();

	console.input.set("  echo hi  ");
	assert(!console.submit());
	assert(console.input.len() == 0);
	assert(console.history.entries.len() == 1);
	assert(console.history.entries[0].compare_to("echo hi") == 0);
	assert(console.buffer.line_count() == 2);
	console_test_helpers::expect_line(&console.buffer, 0, ConsoleStream.COMMAND, "$ echo hi");
	console_test_helpers::expect_line(&console.buffer, 1, ConsoleStream.STDERR, "No project open");
}
fn void test_panel_geometry()
{
	ui::set_ui_scale(1.0f);
	ui::set_dpi(1.0f, 1.0f);

	Rect panel = console_panel_rect(220.0f, 1000, 800);
	assert(panel.x == 0.0f && panel.y == 580.0f);
	assert(panel.width == 1000.0f && panel.height == 220.0f);

	Rect full = console_panel_rect(1000.0f, 1000, 800);
	assert(full.y == 120.0f);
	assert(full.height == 680.0f);
}

fn void test_panel_scroll_math()
{
	assert(console_max_scroll(10, 4) == 6);
	assert(console_max_scroll(3, 4) == 0);
	assert(console_clamp_scroll(-2, 10, 4) == 0);
	assert(console_clamp_scroll(8, 10, 4) == 6);
	assert(console_clamp_scroll(2, 10, 4) == 2);
}

fn void test_panel_status_labels()
{
	assert(console_status_label(ConsoleStatus.IDLE).compare_to("Ready") == 0);
	assert(console_status_label(ConsoleStatus.RUNNING).compare_to("Running") == 0);
	assert(console_status_label(ConsoleStatus.EXITED).compare_to("Exit") == 0);
	assert(console_status_label(ConsoleStatus.KILLED).compare_to("Killed") == 0);
}

fn void test_panel_open_close()
{
	ConsolePanel panel;
	panel.init();
	assert(!panel.visible);
	panel.open();
	assert(panel.visible && panel.focused && panel.pinned);
	panel.close();
	assert(!panel.visible && !panel.focused);
}
fn void test_input_zstr_view_clears()
{
	ConsoleInput input;
	input.init(mem);
	defer input.destroy();

	input.set("hello");
	assert(input.zstr_view().str_view().compare_to("hello") == 0);
	input.clear();
	assert(input.zstr_view().str_view().len == 0);

	input.set("abcdef");
	input.set("xy");
	String value = input.zstr_view().str_view();
	assert(value.compare_to("xy") == 0);
	assert(value.len == 2);

	input.set("abcd");
	input.backspace();
	input.backspace();
	assert(input.zstr_view().str_view().compare_to("ab") == 0);
}
fn void test_console_settings_limits()
{
	ConsoleBuffer buffer;
	buffer.init(mem, 10, 1024 * 1024);
	defer buffer.destroy();
	buffer.append_stdout("1\n2\n3\n4\n5\n");
	buffer.set_limits(2, 1024 * 1024);
	assert(buffer.line_count() == 2);
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.STDOUT, "4");
	console_test_helpers::expect_line(&buffer, 1, ConsoleStream.STDOUT, "5");
	assert(buffer.truncated);

	ConsoleHistory history;
	history.init(mem, 5);
	defer history.destroy();
	history.add("a");
	history.add("b");
	history.add("c");
	history.set_max(2);
	assert(history.entries.len() == 2);
	assert(history.entries[0].compare_to("b") == 0);
	assert(history.entries[1].compare_to("c") == 0);
}

fn void test_panel_apply_settings()
{
	ConsolePanel panel;
	panel.init();

	ConsoleSettings settings = {
		.max_lines = 2000,
		.max_output_kb = 1024,
		.history_size = 100,
		.panel_height = 320.0f,
		.auto_scroll = false,
	};
	panel.apply_settings(settings);
	assert(panel.height == 320.0f);
	assert(!panel.auto_scroll);
	panel.open();
	assert(!panel.pinned);

	settings.auto_scroll = true;
	panel.apply_settings(settings);
	assert(panel.pinned);
}
fn void test_runner_kills_process_tree()
{
	$if env::WIN32:
		return;
	$endif
	$if env::DARWIN:
		return;
	$endif
	@pool()
	{
		Path? tmp = path::temp_directory(tmem);
		if (catch err = tmp) return;
		Path? dir = tmp.append(tmem, "yun_console_tree");
		if (catch err = dir) return;
		Path root = dir;
		(void)path::rmtree(root);
		if (catch err = path::mkdir(root, recursive: true)) return;
		Path? leaked = root.append(tmem, "leaked.txt");
		if (catch err = leaked) return;

		ConsoleBuffer buffer;
		buffer.init(mem);
		defer buffer.destroy();

		ConsoleRunner runner;
		runner.init(mem);
		defer runner.destroy(&buffer);

		String command = string::format(tmem, "sh -c 'sleep 1; echo leaked > %s' & wait", (String)leaked);
		assert(runner.start(&buffer, (String)root, command));
		(void)thread::sleep_ms(100);
		assert(runner.kill());
		assert(console_test_helpers::wait_runner(&runner, &buffer, 500));
		assert(runner.status == ConsoleStatus.KILLED);
		(void)thread::sleep_ms(1500);
		assert(!file::exists(leaked));

		(void)path::rmtree(root);
	};
}
fn void test_panel_horizontal_clamp()
{
	assert(console_clamp_hscroll(-10.0f, 500.0f, 200.0f) == 0.0f);
	assert(console_clamp_hscroll(100.0f, 500.0f, 200.0f) == 100.0f);
	assert(console_clamp_hscroll(400.0f, 500.0f, 200.0f) == 300.0f);
	assert(console_clamp_hscroll(50.0f, 100.0f, 200.0f) == 0.0f);
}
fn void test_console_offset_at_x()
{
	assert(console_offset_at_x("abcdef", -5.0f, 10.0f) == 0);
	assert(console_offset_at_x("abcdef", 0.0f, 10.0f) == 0);
	assert(console_offset_at_x("abcdef", 4.0f, 10.0f) == 0);
	assert(console_offset_at_x("abcdef", 6.0f, 10.0f) == 1);
	assert(console_offset_at_x("abcdef", 25.0f, 10.0f) == 2);
	assert(console_offset_at_x("abcdef", 500.0f, 10.0f) == 6);
}

fn void test_console_word_range()
{
	usz start = 0;
	usz end   = 0;
	console_word_range("foo bar_baz!", 5, &start, &end);
	assert(start == 4 && end == 11);
	console_word_range("foo bar_baz!", 0, &start, &end);
	assert(start == 0 && end == 3);
	console_word_range("foo bar_baz!", 3, &start, &end);
	assert(start == 0 && end == 0);
	console_word_range("", 0, &start, &end);
	assert(start == 0 && end == 0);
}

fn void test_console_selection_text()
{
	Console console;
	console.init(mem);
	defer console.destroy();
	console.buffer.append_stdout("hello\nworld\n");

	ConsolePanel panel;
	panel.init();
	panel.has_selection = true;
	panel.sel_first_line = console.buffer.first;
	panel.sel_anchor_line = 0;
	panel.sel_anchor_offset = 1;
	panel.sel_cursor_line = 1;
	panel.sel_cursor_offset = 3;

	String text = panel.selection_text(&console, tmem);
	assert(text.compare_to("ello\nwor") == 0);

	panel.sel_anchor_line = 1;
	panel.sel_anchor_offset = 3;
	panel.sel_cursor_line = 0;
	panel.sel_cursor_offset = 1;
	text = panel.selection_text(&console, tmem);
	assert(text.compare_to("ello\nwor") == 0);

	panel.clear_selection();
	assert(panel.selection_text(&console, tmem).len == 0);
}
fn void test_console_find_matches()
{
	Console console;
	console.init(mem);
	defer console.destroy();
	console.buffer.append_stdout("foo\nbar foo\nFOO\n");

	ConsolePanel panel;
	panel.init();
	panel.find_open = true;
	panel.find_set("foo");
	panel.find_refresh(&console);
	assert(panel.find_count == 3);
	assert(panel.find_matches[0].line == 0 && panel.find_matches[0].start == 0);
	assert(panel.find_matches[1].line == 1 && panel.find_matches[1].start == 4);
	assert(panel.find_matches[2].line == 2 && panel.find_matches[2].start == 0);

	panel.find_backspace();
	panel.find_refresh(&console);
	assert(panel.find_count == 3);
	assert(panel.find_query_view().compare_to("fo") == 0);

	panel.find_close();
	assert(!panel.find_open);
	assert(panel.find_count == 0);
}
fn void test_buffer_ansi_spans()
{
	ConsoleBuffer buffer;
	buffer.init(mem);
	defer buffer.destroy();

	buffer.append_stdout("\x1b[31mred\x1b[0m plain\n");
	console_test_helpers::expect_line(&buffer, 0, ConsoleStream.STDOUT, "red plain");
	ConsoleLine* line = buffer.line_at(0);
	assert(line.span_count == 1);
	assert(line.spans[0].start == 0 && line.spans[0].len == 3);
	assert(((int)line.spans[0].fg[0] & 0xFF) == 205);

	buffer.append_stdout("\x1b[1;4mbold\nstill\x1b[0m\n");
	ConsoleLine* first = buffer.line_at(1);
	assert(first.text.compare_to("bold") == 0);
	assert(first.span_count == 1);
	assert((first.spans[0].attrs & SPAN_BOLD) != 0);
	assert((first.spans[0].attrs & SPAN_UNDERLINE) != 0);
	ConsoleLine* second = buffer.line_at(2);
	assert(second.text.compare_to("still") == 0);
	assert(second.span_count == 1);
	assert((second.spans[0].attrs & SPAN_BOLD) != 0);

	buffer.append_stdout("\x1b[38;5;196mindexed\x1b[0m\n");
	ConsoleLine* indexed = buffer.line_at(3);
	assert(indexed.span_count == 1);
	RLColor expect = ansi_256(196);
	assert(indexed.spans[0].fg[0] == expect[0] && indexed.spans[0].fg[1] == expect[1]);

	buffer.append_stdout("\x1b[38;2;1;2;3mtrue\x1b[0m\n");
	ConsoleLine* truecolor = buffer.line_at(4);
	assert(truecolor.span_count == 1);
	assert(((int)truecolor.spans[0].fg[0] & 0xFF) == 1);
	assert(((int)truecolor.spans[0].fg[1] & 0xFF) == 2);
	assert(((int)truecolor.spans[0].fg[2] & 0xFF) == 3);
}
fn void test_console_autocomplete()
{
	Console console;
	console.init(mem);
	defer console.destroy();

	ConsolePanel panel;
	panel.init();

	assert(!panel.completion_active);
	console.history.add("git status");
	console.history.add("git stash");
	console.input.set("git st");
	panel.refresh_completion(&console);
	assert(panel.completion_active);
	assert(panel.completion_candidate(&console).compare_to("git stash") == 0);
	assert(panel.completion_suffix(&console).compare_to("ash") == 0);

	console.input.set("git s");
	panel.refresh_completion(&console);
	assert(panel.completion_suffix(&console).compare_to("tash") == 0);

	panel.accept_completion(&console);
	assert(console.input.text_view().compare_to("git stash") == 0);
	assert(console.input.cursor == console.input.len());

	console.history.clear();
	console.history.add("Git Status");
	console.input.set("git s");
	panel.refresh_completion(&console);
	assert(panel.completion_active);
	assert(panel.completion_candidate(&console).compare_to("Git Status") == 0);

	console.input.set("git status");
	panel.refresh_completion(&console);
	assert(!panel.completion_active);

	console.input.set("git");
	console.input.move_left();
	panel.refresh_completion(&console);
	assert(!panel.completion_active);
	console.input.end();

	panel.refresh_completion(&console);
	assert(panel.completion_active);
	panel.dismiss_completion();
	assert(!panel.completion_active);
	panel.refresh_completion(&console);
	assert(!panel.completion_active);
	panel.completion_dismissed = false;
	panel.refresh_completion(&console);
	assert(panel.completion_active);

	console.history.browsing = true;
	panel.refresh_completion(&console);
	assert(!panel.completion_active);

	console.history.browsing = false;
	ConsoleSettings settings = console::settings();
	settings.autocomplete = false;
	panel.apply_settings(settings);
	panel.refresh_completion(&console);
	assert(!panel.completion_active);
}
fn void test_console_manager_sessions()
{
	ConsoleManager manager;
	manager.init(mem);
	defer manager.destroy();

	assert(manager.sessions.len() == 1);
	assert(manager.active == 0);
	Console* first = manager.active_console();
	assert(first != null);
	first.buffer.append_stdout("one\n");

	int second = manager.add_session();
	assert(second == 1);
	Console* second_console = manager.active_console();
	assert(second_console != null);
	second_console.buffer.append_stdout("two\n");
	assert(first.buffer.line_count() == 1);
	assert(second_console.buffer.line_count() == 1);

	manager.select(0);
	assert(manager.active == 0);
	assert(manager.active_console() == first);
	assert(manager.active_console().buffer.line_count() == 1);

	manager.open();
	assert(manager.visible);
	assert(manager.active_panel().visible);
	manager.active_panel().height = 300.0f;
	manager.sync_height();
	assert(manager.height == 300.0f);

	assert(manager.close_session(0));
	assert(manager.sessions.len() == 1);
	assert(manager.active == 0);
	assert(manager.active_panel().height == 300.0f);
	manager.flush_pending();

	assert(manager.close_session(0));
	assert(manager.sessions.len() == 1);
	assert(!manager.visible);
	manager.flush_pending();
}

fn void test_console_manager_root()
{
	ConsoleManager manager;
	manager.init(mem);
	defer manager.destroy();

	manager.set_root("/tmp/project");
	assert(manager.root.compare_to("/tmp/project") == 0);
	assert(manager.active_console().root.compare_to("/tmp/project") == 0);
	(void)manager.add_session();
	assert(manager.active_console().root.compare_to("/tmp/project") == 0);

	manager.reset("/tmp/other");
	assert(manager.sessions.len() == 1);
	assert(manager.root.compare_to("/tmp/other") == 0);
	assert(manager.active_console().root.compare_to("/tmp/other") == 0);
}
fn void test_console_profile_command()
{
	ConsoleEnvVar[1] env = { { .key = "MODE", .value = "debug" } };
	String posix         = console_profile_command(tmem, "src", env[0:1], "c3c build");
	assert(posix.compare_to("cd 'src' && export MODE='debug' && c3c build") == 0);
	String windows = console_profile_command(tmem, "src", env[0:1], "c3c build");
	// Same function on this platform; Windows formatting is compile-time.
	$if env::WIN32:
		assert(windows.compare_to("cd /D \"src\" && set \"MODE=debug\" && c3c build") == 0);
	$else
		assert(windows.compare_to(posix) == 0);
	$endif
}
fn void test_console_profile_run()
{
	Console console;
	console.init(mem);
	defer console.destroy();
	console.set_root(".");

	ConsoleEnvVar[] env = { };
	String wrapped      = console_profile_command(tmem, ".", env[0:0], "printf 'profile\\n'");
	assert(console.run_display("build", wrapped));
	for (int i = 0; i < 500 && console.running(); i++)
	{
		console.pump();
		(void)thread::sleep_ms(10);
	}
	console.pump();
	assert(!console.running());
	assert(console.buffer.line_count() >= 2);
	ConsoleLine* header = console.buffer.line_at(0);
	assert(header.text.compare_to("$ build") == 0);
	bool found = false;
	for (sz i = 0; i < console.buffer.line_count(); i++)
	{
		if (console.buffer.line_at(i).text.compare_to("profile") == 0) found = true;
	}
	assert(found);
}
fn void test_console_input_word_nav()
{
	ConsoleInput input;
	input.init(mem);
	defer input.destroy();

	input.set("foo bar_baz!");
	input.end();
	input.move_word_left();
	assert(input.cursor == 11);
	input.move_word_left();
	assert(input.cursor == 4);
	input.move_word_left();
	assert(input.cursor == 0);
	input.move_word_right();
	assert(input.cursor == 3);
	input.move_word_right();
	assert(input.cursor == 4);
	input.move_word_right();
	assert(input.cursor == 11);

	input.set("foo bar");
	input.home();
	input.delete_word_forward();
	assert(input.text_view().compare_to(" bar") == 0);
	input.home();
	input.delete_word_forward();
	assert(input.text_view().compare_to("bar") == 0);
	input.end();
	input.delete_word_back();
	assert(input.len() == 0);

	input.set("café x");
	input.end();
	input.move_word_left();
	assert(input.cursor == 6);
	input.move_word_left();
	assert(input.cursor == 0);
}
fn void test_console_buffer_flags()
{
	ConsoleBuffer buffer;
	buffer.init(mem);
	defer buffer.destroy();

	buffer.set_render_ansi(false);
	buffer.append_stdout("\x1b[31mred\x1b[0m\n");
	ConsoleLine* line = buffer.line_at(0);
	assert(line.text.compare_to("red") == 0);
	assert(line.span_count == 0);

	buffer.set_show_headers(false);
	buffer.append_command("echo hello");
	assert(buffer.line_count() == 1);

	buffer.set_show_headers(true);
	buffer.append_command("echo hello");
	assert(buffer.line_count() == 2);
	assert(buffer.line_at(1).text.compare_to("$ echo hello") == 0);
}

fn void test_console_notify_policy()
{
	assert(!console_should_notify(ConsoleNotify.NEVER, ConsoleStatus.EXITED, 1));
	assert(!console_should_notify(ConsoleNotify.FAILURE, ConsoleStatus.EXITED, 0));
	assert(console_should_notify(ConsoleNotify.FAILURE, ConsoleStatus.EXITED, 1));
	assert(console_should_notify(ConsoleNotify.FAILURE, ConsoleStatus.FAILED, -1));
	assert(console_should_notify(ConsoleNotify.ALWAYS, ConsoleStatus.EXITED, 0));
	assert(console_should_notify(ConsoleNotify.ALWAYS, ConsoleStatus.KILLED, 1));
}

fn void test_panel_console_settings()
{
	ConsolePanel panel;
	panel.init();
	ConsoleSettings settings = console::settings();
	settings.wheel_lines = 7;
	settings.autocomplete = false;
	panel.apply_settings(settings);
	assert(panel.wheel_lines == 7);
	assert(!panel.completion_enabled);
}

fn void test_console_kill_on_close()
{
	ConsoleManager manager;
	manager.init(mem);
	defer manager.destroy();

	ConsoleSettings saved    = console::settings();
	ConsoleSettings settings = saved;
	settings.kill_on_close = true;
	console::set_settings(settings);
	defer console::set_settings(saved);

	manager.set_root(".");
	manager.open();
	Console* console = manager.active_console();
	$if env::WIN32:
		assert(console.run("ping -n 20 127.0.0.1 >nul"));
	$else
		assert(console.run("sleep 10"));
	$endif
	manager.close();
	assert(console.runner.status == ConsoleStatus.KILLING);
}
fn void test_terminal_text_and_utf8()
{
	ConsoleTerminal term;
	term.init(mem);
	term.resize(10, 3);
	term.feed("abc\r\ndef");
	TermCell* a = term.cell_at(0, 0);
	TermCell* b = term.cell_at(1, 0);
	TermCell* c = term.cell_at(2, 0);
	TermCell* d = term.cell_at(0, 1);
	assert(a && a.text[0] == 'a');
	assert(b && b.text[0] == 'b');
	assert(c && c.text[0] == 'c');
	assert(d && d.text[0] == 'd');
	assert(term.cursor_y == 1);
	assert(term.cursor_x == 3);

	term.feed("é");
	TermCell* utf = term.cell_at(3, 1);
	assert(utf && utf.len == 2);
	term.destroy();
}

fn void test_terminal_cursor_and_erase()
{
	ConsoleTerminal term;
	term.init(mem);
	term.resize(10, 4);
	term.feed("hello");
	term.feed("\x1b[2D");
	assert(term.cursor_x == 3);
	term.feed("\x1b[1;1H");
	assert(term.cursor_x == 0 && term.cursor_y == 0);
	term.feed("\x1b[3;5H");
	assert(term.cursor_x == 4 && term.cursor_y == 2);
	term.feed("\x1b[2J");
	TermCell* cleared = term.cell_at(0, 0);
	assert(cleared && cleared.len == 0);
	term.feed("one\ntwo");
	term.feed("\x1b[1;1H\x1b[K");
	TermCell* first = term.cell_at(0, 0);
	assert(first && first.len == 0);
	term.destroy();
}

fn void test_terminal_sgr()
{
	ConsoleTerminal term;
	term.init(mem);
	term.resize(10, 2);
	term.feed("\x1b[31mR\x1b[0mN");
	TermCell* red    = term.cell_at(0, 0);
	TermCell* normal = term.cell_at(1, 0);
	assert(red && red.text[0] == 'R');
	assert(normal && normal.text[0] == 'N');
	assert(red.fg.r != normal.fg.r || red.fg.g != normal.fg.g || red.fg.b != normal.fg.b);
	term.destroy();
}

fn void test_terminal_alt_screen()
{
	ConsoleTerminal term;
	term.init(mem);
	term.resize(10, 2);
	term.feed("main");
	assert(term.cell_at(0, 0).text[0] == 'm');
	term.feed("\x1b[?1049h");
	term.feed("alt");
	assert(term.alt_screen);
	assert(term.cell_at(0, 0).text[0] == 'a');
	term.feed("\x1b[?1049l");
	assert(!term.alt_screen);
	assert(term.cell_at(0, 0).text[0] == 'm');
	term.destroy();
}

fn void test_terminal_scroll_region()
{
	ConsoleTerminal term;
	term.init(mem);
	term.resize(8, 3);
	term.feed("\x1b[1;1Ha\x1b[2;1Hb\x1b[3;1Hc");
	term.feed("\x1b[1;2r");
	term.feed("\x1b[2;1H\nX");
	assert(term.scroll_top == 0);
	assert(term.scroll_bottom == 1);
	TermCell* bottom = term.cell_at(0, 2);
	assert(bottom && bottom.text[0] == 'c');
	term.destroy();
}

fn void test_pty_lifecycle()
{
	$if env::WIN32:
		return;
	$else
		@pool()
		{
			ConsolePty pty;
			pty.init(mem);
			assert(pty.start("", 80, 24));
			assert(pty.running);
			pty.write("printf 'pty-ok\\n'\n");
			char[4096] buffer;
			bool found = false;
			for (int attempt = 0; attempt < 40 && !found; attempt++)
			{
				thread::sleep_ms(25);
				usz count = pty.read(buffer[0:buffer.len]);
				if (count == 0) continue;
				String output = (String)buffer[0:count];
				if (output.contains("pty-ok")) found = true;
			}
			assert(found);
			pty.resize(100, 30);
			pty.stop();
			assert(!pty.running);
			pty.destroy();
		};
	$endif
}
fn void test_terminal_copy_and_resize()
{
	ConsoleTerminal term;
	term.init(mem);
	term.resize(6, 3);
	term.feed("\x1b[1;1Hab\x1b[2;1Hcd");
	@pool()
	{
		String text = term.copy_text(tmem);
		assert(text.starts_with("ab"));
		assert(text.contains("cd"));
	};
	term.resize(8, 4);
	TermCell* a = term.cell_at(0, 0);
	TermCell* c = term.cell_at(0, 1);
	assert(a && a.text[0] == 'a');
	assert(c && c.text[0] == 'c');
	term.destroy();
}