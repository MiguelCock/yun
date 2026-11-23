module yun::console @test;

import std::os::env;
import std::thread;
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