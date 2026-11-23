module yun::console;

import libc;
import std::collections::list;
import std::core::dstring;
import std::os::env;
import std::os::posix;
import std::os::process;

enum ConsoleStatus : int
{
	IDLE,
	RUNNING,
	KILLING,
	EXITED,
	KILLED,
	FAILED,
}

struct ConsoleRunner
{
	Allocator allocator;
	Process process;
	bool has_process;
	ConsoleStatus status;
	int exit_code;
	bool kill_requested;
	String command;
	String error;
}

fn void ConsoleRunner.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.has_process = false;
	self.status = ConsoleStatus.IDLE;
	self.exit_code = 0;
	self.kill_requested = false;
	self.command = "";
	self.error = "";
}

fn bool ConsoleRunner.running(&self)
{
	if (!self.has_process) return false;
	return self.status == ConsoleStatus.RUNNING || self.status == ConsoleStatus.KILLING;
}

fn String shell_quote_posix(Allocator allocator, String text)
{
	DString out;
	out.init(allocator, text.len + 2);
	out.append_char('\'');
	for (usz i = 0; i < text.len; i++)
	{
		char c = text[i];
		if (c == '\'')
		{
			out.append_string("'\\''");
		}
		else
		{
			out.append_char(c);
		}
	}
	out.append_char('\'');
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn String console_posix_command(Allocator allocator, String root, String command)
{
	String quoted = shell_quote_posix(allocator, root);
	defer quoted.free(allocator);
	return string::format(allocator, "cd %s && %s", quoted, command);
}

fn String console_windows_command(Allocator allocator, String root, String command)
{
	return string::format(allocator, "chcp 65001 >nul & cd /D \"%s\" && %s", root, command);
}

fn bool ConsoleRunner.start(&self, ConsoleBuffer* output, String root, String command)
{
	if (self.running()) return false;
	if (self.has_process) self.stop(output);
	if (self.command.len > 0) self.command.free(self.allocator);
	if (self.error.len > 0) self.error.free(self.allocator);
	self.command = command.copy(self.allocator);
	self.error = "";
	self.exit_code = 0;
	self.kill_requested = false;
	if (output) output.append_command(command);

	Process? spawned = { };
	@pool()
	{
		List{String} argv;
		argv.init(tmem);
		String wrapped = "";
		$if env::WIN32:
			wrapped = console_windows_command(tmem, root, command);
			argv.push("cmd");
			argv.push("/C");
		$else
			wrapped = console_posix_command(tmem, root, command);
			argv.push("/bin/sh");
			argv.push("-c");
		$endif
		argv.push(wrapped);

		process::SpawnOptions options = process::SpawnOptions.INHERIT_ENV | process::SpawnOptions.ASYNC_OUTPUT;
		$if env::WIN32:
			options = options | process::SpawnOptions.NO_WINDOW;
		$endif
		spawned = process::spawn(
			argv.entries[0:argv.len()],
			options,
			{ },
			process::CAPTURE,
			process::CAPTURE,
			process::CAPTURE
		);
	};
	if (catch excuse = spawned)
	{
		self.status = ConsoleStatus.FAILED;
		self.error = "Could not start the shell".copy(self.allocator);
		if (output)
		{
			output.append_stderr("Could not start the shell\n");
			output.flush();
		}
		return false;
	}
	self.process = spawned;
	self.has_process = true;
	self.status = ConsoleStatus.RUNNING;
	return true;
}

fn int ConsoleRunner.drain(&self, ConsoleBuffer* output, int remaining)
{
	if (!self.has_process || remaining <= 0) return remaining;
	char[4096] chunk;
	while (remaining > 0)
	{
		bool progress = false;
		int want      = remaining < (int)chunk.len ? remaining : (int)chunk.len;
		sz? out       = self.process.read_stdout(&chunk[0], want);
		sz out_len    = 0;
		if (try value = out) out_len = value;
		if (out_len > 0)
		{
			if (output) output.append_stdout((String)chunk[0:out_len]);
			remaining -= (int)out_len;
			progress = true;
		}

		want = remaining < (int)chunk.len ? remaining : (int)chunk.len;
		if (want > 0)
		{
			sz? err    = self.process.read_stderr(&chunk[0], want);
			sz err_len = 0;
			if (try value = err) err_len = value;
			if (err_len > 0)
			{
				if (output) output.append_stderr((String)chunk[0:err_len]);
				remaining -= (int)err_len;
				progress = true;
			}
		}
		if (!progress) break;
	}
	return remaining;
}

fn void ConsoleRunner.pump(&self, ConsoleBuffer* output, int budget)
{
	if (!self.has_process) return;
	if (self.status != ConsoleStatus.RUNNING && self.status != ConsoleStatus.KILLING) return;

	(void)self.drain(output, budget > 0 ? budget : 1);
	bool alive = false;
	$if env::WIN32:
		bool? running = self.process.is_running();
		if (try value = running)
		{
			alive = value;
		}
	$else
		int status;
		int child  = (int)self.process.child;
		int result = (int)posix::waitpid(child, &status, posix::WNOHANG);
		if (result == 0)
		{
			alive = true;
		}
		else
		{
			if (result == child)
			{
				self.exit_code = posix::wIFEXITED(status) ? (int)posix::wEXITSTATUS(status) : libc::EXIT_FAILURE;
				self.process.return_status = self.exit_code;
			}
			else
			{
				self.exit_code = -1;
			}
			self.process.child = 0;
			self.process.is_alive = false;
		}
	$endif
	if (alive) return;

	(void)self.drain(output, 64 * 1024);
	if (output) output.flush();
	$if env::WIN32:
		CInt? code    =  self.process.join();
		int exit_code = -1;
		if (try value = code) exit_code = (int)value;
		self.exit_code = exit_code;
	$endif
	self.status = self.kill_requested ? ConsoleStatus.KILLED : ConsoleStatus.EXITED;
	(void)self.process.destroy();
	self.has_process = false;
}

fn bool ConsoleRunner.kill(&self)
{
	if (!self.has_process || self.status != ConsoleStatus.RUNNING) return false;
	self.kill_requested = true;
	self.status = ConsoleStatus.KILLING;
	(void)self.process.terminate();
	return true;
}

fn void ConsoleRunner.stop(&self, ConsoleBuffer* output)
{
	if (!self.has_process) return;
	(void)self.process.terminate();
	CInt? code    =  self.process.join();
	int exit_code = -1;
	if (try value = code) exit_code = (int)value;
	self.exit_code = exit_code;
	if (output) output.flush();
	(void)self.process.destroy();
	self.has_process = false;
	self.status = ConsoleStatus.IDLE;
	self.kill_requested = false;
}

fn void ConsoleRunner.destroy(&self, ConsoleBuffer* output)
{
	self.stop(output);
	if (self.command.len > 0) self.command.free(self.allocator);
	if (self.error.len > 0) self.error.free(self.allocator);
	self.command = "";
	self.error = "";
}