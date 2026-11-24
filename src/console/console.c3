module yun::console;

const int PUMP_BUDGET = 64 * 1024;

struct ConsoleSettings
{
	int max_lines;
	int max_output_kb;
	int history_size;
	float panel_height;
	bool auto_scroll;
	bool autocomplete;
}

ConsoleSettings g_console_settings = {
	.max_lines = DEFAULT_MAX_LINES,
	.max_output_kb = (int)(DEFAULT_MAX_BYTES / 1024),
	.history_size = DEFAULT_HISTORY,
	.panel_height = DEFAULT_HEIGHT,
	.auto_scroll = true,
	.autocomplete = true,
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
	String root;
}

fn void Console.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.buffer.init(allocator);
	self.runner.init(allocator);
	self.input.init(allocator);
	self.history.init(allocator);
	self.root = "";
}

fn void Console.set_root(&self, String root)
{
	if (self.root.len > 0 && root.len > 0 && self.root.compare_to(root) == 0) return;
	self.runner.stop(&self.buffer);
	self.buffer.clear();
	self.history.clear();
	if (self.root.len > 0) self.root.free(self.allocator);
	self.root = root.len > 0 ? root.copy(self.allocator) : "";
}

fn bool Console.run(&self, String command)
{
	if (self.root.len == 0)
	{
		self.buffer.append_command(command);
		self.buffer.append_stderr("No project open\n");
		self.buffer.flush();
		return false;
	}
	return self.runner.start(&self.buffer, self.root, command);
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
	self.buffer.set_limits(settings.max_lines, (usz)settings.max_output_kb * 1024);
	self.history.set_max(settings.history_size);
}

fn void Console.pump(&self)
{
	self.runner.pump(&self.buffer, PUMP_BUDGET);
}

fn bool Console.running(&self)
{
	return self.runner.running();
}

fn void Console.kill(&self)
{
	(void)self.runner.kill();
}

fn void Console.clear(&self)
{
	self.buffer.clear();
}

fn void Console.destroy(&self)
{
	self.runner.destroy(&self.buffer);
	self.buffer.destroy();
	self.input.destroy();
	self.history.destroy();
	if (self.root.len > 0) self.root.free(self.allocator);
	self.root = "";
}