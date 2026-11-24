module yun::console_test_helpers;

import std::os::env;
import std::thread;
import yun::console;

fn void expect_line(ConsoleBuffer* buffer, sz index, ConsoleStream stream, String text)
{
	ConsoleLine* line = buffer.line_at(index);
	assert(line != null);
	assert(line.stream == stream);
	assert(line.text.compare_to(text) == 0);
}

fn bool has_line(ConsoleBuffer* buffer, String text)
{
	for (sz i = 0; i < buffer.line_count(); i++)
	{
		ConsoleLine* line = buffer.line_at(i);
		if (line.text.compare_to(text) == 0) return true;
	}
	return false;
}

fn bool wait_runner(ConsoleRunner* runner, ConsoleBuffer* buffer, int attempts)
{
	for (int i = 0; i < attempts; i++)
	{
		runner.pump(buffer, 64 * 1024);
		if (!runner.running()) return true;
		(void)thread::sleep_ms(10);
	}
	return false;
}

fn String test_command(bool long_running)
{
	if (long_running)
	{
		$if env::WIN32:
			return "ping -n 20 127.0.0.1 >nul";
		$else
			return "sleep 10";
		$endif
	}
	$if env::WIN32:
		return "echo out & echo err 1>&2 & exit /b 3";
	$else
		return "printf 'out\\n'; printf 'err\\n' >&2; exit 3";
	$endif
}