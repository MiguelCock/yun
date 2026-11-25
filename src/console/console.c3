module yun::console;

const int PUMP_BUDGET = 64 * 1024;

struct ConsoleEnvVar
{
	String key;
	String value;
}

enum ConsoleNotify : int
{
	NEVER,
	FAILURE,
	ALWAYS,
}

struct ConsoleSettings
{
	int max_lines;
	int max_output_kb;
	int history_size;
	float panel_height;
	bool auto_scroll;
	bool autocomplete;
	int wheel_lines;
	bool ansi_colors;
	bool show_headers;
	bool clear_on_run;
	bool kill_on_close;
	ConsoleNotify notify;
	bool persist_history;
	bool restore_sessions;
	bool pty;
}

ConsoleSettings g_console_settings = {
	.max_lines = DEFAULT_MAX_LINES,
	.max_output_kb = (int)(DEFAULT_MAX_BYTES / 1024),
	.history_size = DEFAULT_HISTORY,
	.panel_height = DEFAULT_HEIGHT,
	.auto_scroll = true,
	.autocomplete = true,
	.wheel_lines = 3,
	.ansi_colors = true,
	.show_headers = true,
	.clear_on_run = false,
	.kill_on_close = false,
	.notify = ConsoleNotify.FAILURE,
	.persist_history = true,
	.restore_sessions = true,
	.pty = false,
};

fn void set_settings(ConsoleSettings settings)
{
	if (settings.max_lines < 100) settings.max_lines = 100;
	if (settings.max_lines > 100000) settings.max_lines = 100000;
	if (settings.max_output_kb < 16) settings.max_output_kb = 16;
	if (settings.max_output_kb > 1024 * 1024) settings.max_output_kb = 1024 * 1024;
	if (settings.history_size < 1) settings.history_size = 1;
	if (settings.history_size > 10000) settings.history_size = 10000;
	if (settings.panel_height < MIN_HEIGHT) settings.panel_height = MIN_HEIGHT;
	if (settings.panel_height > 2000.0f) settings.panel_height = 2000.0f;
	if (settings.wheel_lines < 1) settings.wheel_lines = 1;
	if (settings.wheel_lines > 20) settings.wheel_lines = 20;
	g_console_settings = settings;
}

fn ConsoleSettings settings()
{
	return g_console_settings;
}

struct Console
{
	Allocator allocator;
	ConsoleBuffer buffer;
	ConsoleRunner runner;
	ConsoleInput input;
	ConsoleHistory history;
	ConsoleTerminal terminal;
	ConsolePty pty;
	bool pty_enabled;
	bool terminal_active;
	String root;
}

fn void Console.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.buffer.init(allocator);
	self.runner.init(allocator);
	self.input.init(allocator);
	self.history.init(allocator);
	self.terminal.init(allocator);
	self.pty.init(allocator);
	self.pty_enabled = false;
	self.terminal_active = false;
	self.root = "";
}

fn void Console.set_root(&self, String root)
{
	if (self.root.len > 0 && root.len > 0 && self.root.compare_to(root) == 0) return;
	self.runner.stop(&self.buffer);
	self.pty.stop();
	self.terminal_active = false;
	self.buffer.clear();
	self.history.clear();
	if (self.root.len > 0) self.root.free(self.allocator);
	self.root = root.len > 0 ? root.copy(self.allocator) : "";
}

fn String console_profile_command(Allocator allocator, String cwd, ConsoleEnvVar[] env, String command)
{
	DString out;
	out.init(allocator, command.len + 32);
	$if env::WIN32:
		out.appendf("cd /D \"%s\" && ", cwd);
		for (usz i = 0; i < env.len; i++)
		{
			out.appendf("set \"%s=%s\" && ", env[i].key, env[i].value);
		}
	$else
		String quoted_cwd = shell_quote_posix(allocator, cwd);
		out.appendf("cd %s && ", quoted_cwd);
		quoted_cwd.free(allocator);
		for (usz i = 0; i < env.len; i++)
		{
			String quoted_value = shell_quote_posix(allocator, env[i].value);
			out.appendf("export %s=%s && ", env[i].key, quoted_value);
			quoted_value.free(allocator);
		}
	$endif
	out.append_string(command);
	String result = out.str_view().copy(allocator);
	out.free();
	return result;
}

fn bool Console.run_display(&self, String display, String command)
{
	if (g_console_settings.clear_on_run) self.buffer.clear();
	if (self.root.len == 0)
	{
		self.buffer.append_command(display);
		self.buffer.append_stderr("No project open\n");
		self.buffer.flush();
		return false;
	}
	return self.runner.start_display(&self.buffer, self.root, command, display);
}

fn bool Console.run(&self, String command)
{
	return self.run_display(command, command);
}

fn bool Console.start_terminal(&self, int cols, int rows)
{
	if (!self.pty_enabled) return false;
	if (self.pty.running)
	{
		self.terminal_active = true;
		return true;
	}
	if (!self.pty.start(self.root, cols, rows)) return false;
	self.terminal_active = true;
	self.terminal.resize(cols, rows);
	self.runner.status = ConsoleStatus.RUNNING;
	self.runner.exit_code = 0;
	return true;
}

fn bool Console.submit(&self)
{
	String command = self.input.text_view().trim();
	if (command.len == 0) return false;
	if (self.runner.running()) return false;
	bool ok = self.run(command);
	self.history.add(command);
	self.input.clear();
	return ok;
}

fn void Console.apply_settings(&self, ConsoleSettings settings)
{
	self.pty_enabled = settings.pty;
	if (!self.pty_enabled)
	{
		self.terminal_active = false;
		self.pty.stop();
	}
	self.buffer.set_limits(settings.max_lines, (usz)settings.max_output_kb * 1024);
	self.buffer.set_render_ansi(settings.ansi_colors);
	self.buffer.set_show_headers(settings.show_headers);
	self.history.set_max(settings.history_size);
}

fn bool console_should_notify(ConsoleNotify mode, ConsoleStatus status, int exit_code)
{
	if (mode == ConsoleNotify.NEVER) return false;
	bool failed = status == ConsoleStatus.FAILED || (status == ConsoleStatus.EXITED && exit_code != 0);
	if (mode == ConsoleNotify.FAILURE) return failed;
	return status == ConsoleStatus.EXITED || status == ConsoleStatus.FAILED || status == ConsoleStatus.KILLED;
}

fn bool Console.take_notify(&self, int* exit_code, ConsoleStatus* status)
{
	if (!self.runner.notify_pending) return false;
	self.runner.notify_pending = false;
	*exit_code = self.runner.notify_code;
	*status = self.runner.notify_status;
	return true;
}

fn void Console.pump(&self)
{
	if (self.pty_enabled && self.pty.running)
	{
		char[4096] buffer;
		while (true)
		{
			usz count = self.pty.read(buffer[0:buffer.len]);
			if (count == 0) break;
			self.terminal.feed((String)buffer[0:count]);
		}
		int exit_code = 0;
		if (self.pty.poll_exit(&exit_code))
		{
			self.runner.status = self.runner.kill_requested ? ConsoleStatus.KILLED : ConsoleStatus.EXITED;
			self.runner.exit_code = exit_code;
			self.runner.notify_pending = true;
			self.runner.notify_code = exit_code;
			self.runner.notify_status = self.runner.status;
			self.terminal_active = false;
			self.buffer.flush();
		}
		return;
	}
	self.runner.pump(&self.buffer, PUMP_BUDGET);
}

fn void Console.resize_terminal(&self, int cols, int rows)
{
	if (!self.pty_enabled) return;
	self.terminal.resize(cols, rows);
	self.pty.resize(cols, rows);
}

fn bool Console.running(&self)
{
	return self.runner.running() || self.pty.running;
}

fn void Console.kill(&self)
{
	if (self.pty.running)
	{
		self.pty.stop();
		self.runner.status = ConsoleStatus.KILLED;
		self.runner.exit_code = -1;
		self.runner.notify_pending = true;
		self.runner.notify_code = -1;
		self.runner.notify_status = ConsoleStatus.KILLED;
		self.terminal_active = false;
		return;
	}
	(void)self.runner.kill();
}

fn void Console.clear(&self)
{
	self.buffer.clear();
}

fn void Console.destroy(&self)
{
	self.pty.stop();
	self.pty.destroy();
	self.terminal.destroy();
	self.runner.destroy(&self.buffer);
	self.buffer.destroy();
	self.input.destroy();
	self.history.destroy();
	if (self.root.len > 0) self.root.free(self.allocator);
	self.root = "";
}