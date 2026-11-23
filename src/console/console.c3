module yun::console;

const int PUMP_BUDGET = 64 * 1024;

struct Console
{
	Allocator allocator;
	ConsoleBuffer buffer;
	ConsoleRunner runner;
	String root;
}

fn void Console.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.buffer.init(allocator);
	self.runner.init(allocator);
	self.root = "";
}

fn void Console.set_root(&self, String root)
{
	if (self.root.len > 0 && root.len > 0 && self.root.compare_to(root) == 0) return;
	self.runner.stop(&self.buffer);
	self.buffer.clear();
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
	if (self.root.len > 0) self.root.free(self.allocator);
	self.root = "";
}