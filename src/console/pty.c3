module yun::console;

import libc;
import std::core::mem::alloc;
import std::os::env;

struct ConsolePty
{
	Allocator allocator;
	bool running;
	int master;
	int child;
	int cols;
	int rows;
	String error;
}

struct ConsoleWinsize
{
	ushort rows;
	ushort cols;
	ushort xpixel;
	ushort ypixel;
}

extern fn CInt posix_openpt(CInt flags) @cname("posix_openpt") @feat(LINUX, MACOS);
extern fn CInt grantpt(CInt fd) @cname("grantpt") @feat(LINUX, MACOS);
extern fn CInt unlockpt(CInt fd) @cname("unlockpt") @feat(LINUX, MACOS);
extern fn CInt ptsname_r(CInt fd, char* buffer, usz length) @cname("ptsname_r") @feat(LINUX, MACOS);
extern fn CInt open(char* path, CInt flags, ...) @cname("open") @feat(LINUX, MACOS);
extern fn CInt close(CInt fd) @cname("close") @feat(LINUX, MACOS);
extern fn CInt read(CInt fd, void* buffer, usz count) @cname("read") @feat(LINUX, MACOS);
extern fn CInt write(CInt fd, void* buffer, usz count) @cname("write") @feat(LINUX, MACOS);
extern fn CInt fork() @cname("fork") @feat(LINUX, MACOS);
extern fn CInt setsid() @cname("setsid") @feat(LINUX, MACOS);
extern fn CInt chdir(char* path) @cname("chdir") @feat(LINUX, MACOS);
extern fn CInt dup2(CInt oldfd, CInt newfd) @cname("dup2") @feat(LINUX, MACOS);
extern fn CInt execvp(char* file, char** argv) @cname("execvp") @feat(LINUX, MACOS);
extern fn CInt fcntl(CInt fd, CInt cmd, ...) @cname("fcntl") @feat(LINUX, MACOS);
extern fn CInt ioctl(CInt fd, ulong request, ...) @cname("ioctl") @feat(LINUX, MACOS);
extern fn CInt kill(CInt pid, CInt sig) @cname("kill") @feat(LINUX, MACOS);
extern fn CInt waitpid(CInt pid, CInt* status, CInt options) @cname("waitpid") @feat(LINUX, MACOS);
extern fn void _exit(CInt code) @cname("_exit") @noreturn @feat(LINUX, MACOS);

const CInt PTY_O_NOCTTY    = env::LINUX ? 0x100 : 0x20000;
const CInt PTY_O_NONBLOCK  = env::LINUX ? 0x800 : 0x4;
const ulong PTY_TIOCSCTTY  = env::LINUX ? 0x540E : 0x20007461;
const ulong PTY_TIOCSWINSZ = env::LINUX ? 0x5414 : 0x80087467;

fn void ConsolePty.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.running = false;
	self.master = -1;
	self.child = -1;
	self.cols = 80;
	self.rows = 24;
	self.error = "";
}

fn void ConsolePty.destroy(&self)
{
	self.stop();
	if (self.error.len) self.error.free(self.allocator);
	self.error = "";
}

fn void ConsolePty.set_error(&self, String message)
{
	if (self.error.len) self.error.free(self.allocator);
	self.error = message.copy(self.allocator);
}

fn void ConsolePty.update_winsize(&self) @feat(LINUX, MACOS)
{
	if (self.master < 0) return;
	ConsoleWinsize size = {
		.rows = (ushort)(self.rows > 0 ? self.rows : 1),
		.cols = (ushort)(self.cols > 0 ? self.cols : 1),
		.xpixel = 0,
		.ypixel = 0,
	};
	(void)ioctl(self.master, PTY_TIOCSWINSZ, &size);
}

fn bool ConsolePty.start(&self, String root, int cols, int rows)
{
	if (self.running) return true;
	self.cols = cols > 0 ? cols : 80;
	self.rows = rows > 0 ? rows : 24;
	$if env::WIN32:
		self.set_error("ConPTY is not available in this build");
		return false;
	$else
		self.master = posix_openpt(0x0002 | PTY_O_NOCTTY);
		if (self.master < 0)
		{
			self.set_error("Could not allocate a pseudo-terminal");
			return false;
		}
		if (grantpt(self.master) != 0 || unlockpt(self.master) != 0)
		{
			(void)close(self.master);
			self.master = -1;
			self.set_error("Could not unlock the pseudo-terminal");
			return false;
		}
		char[256] slave_name;
		if (ptsname_r(self.master, &slave_name[0], slave_name.len) != 0)
		{
			(void)close(self.master);
			self.master = -1;
			self.set_error("Could not resolve the pseudo-terminal");
			return false;
		}
		int slave = open(&slave_name[0], 0x0002 | PTY_O_NOCTTY);
		if (slave < 0)
		{
			(void)close(self.master);
			self.master = -1;
			self.set_error("Could not open the pseudo-terminal");
			return false;
		}
		self.update_winsize();

		@pool()
		{
			ZString root_z  = root.zstr_tcopy();
			ZString shell_z = "/bin/sh";
			ZString[] argv  = alloc::new_array(tmem, ZString, 3);
			argv[0] = shell_z;
			argv[1] = "-i";
			argv[2] = (ZString)null;
			int pid = fork();
			if (pid == 0)
			{
				(void)setsid();
				(void)ioctl(slave, PTY_TIOCSCTTY, (void*)null);
				(void)dup2(slave, 0);
				(void)dup2(slave, 1);
				(void)dup2(slave, 2);
				if (slave > 2) (void)close(slave);
				(void)close(self.master);
				if (root.len > 0) (void)chdir(root_z);
				(void)execvp(shell_z, (char**)argv.ptr);
				_exit(127);
			}
			if (pid < 0)
			{
				(void)close(slave);
				(void)close(self.master);
				self.master = -1;
				self.set_error("Could not start the terminal shell");
				return false;
			}
			self.child = pid;
		};
		(void)close(slave);
		int flags = fcntl(self.master, 3, 0);
		if (flags >= 0) (void)fcntl(self.master, 4, flags | PTY_O_NONBLOCK);
		self.running = true;
		if (self.error.len)
		{
			self.error.free(self.allocator);
			self.error = "";
		}
		return true;
	$endif
}

fn usz ConsolePty.read(&self, char[] buffer)
{
	if (!self.running || self.master < 0 || buffer.len == 0) return 0;
	$if env::WIN32:
		return 0;
	$else
		CInt count = read(self.master, &buffer[0], buffer.len);
		return count > 0 ? (usz)count : 0;
	$endif
}

fn void ConsolePty.write(&self, String text)
{
	if (!self.running || self.master < 0 || text.len == 0) return;
	$if !env::WIN32:
		usz offset = 0;
		while (offset < text.len)
		{
			CInt count = write(self.master, (void*)&text[offset], text.len - offset);
			if (count <= 0) break;
			offset += (usz)count;
		}
	$endif
}

fn void ConsolePty.resize(&self, int cols, int rows)
{
	if (cols < 1) cols = 1;
	if (rows < 1) rows = 1;
	if (self.cols == cols && self.rows == rows) return;
	self.cols = cols;
	self.rows = rows;
	$if !env::WIN32:
		self.update_winsize();
	$endif
}

fn bool ConsolePty.poll_exit(&self, int* exit_code)
{
	if (!self.running) return true;
	$if env::WIN32:
		return false;
	$else
		CInt status = 0;
		CInt result = waitpid(self.child, &status, 1);
		if (result != self.child) return false;
		*exit_code = ((status & 0x7F) == 0) ? ((status >> 8) & 0xFF) : -1;
		self.running = false;
		self.child = -1;
		if (self.master >= 0)
		{
			(void)close(self.master);
			self.master = -1;
		}
		return true;
	$endif
}

fn void ConsolePty.stop(&self)
{
	if (!self.running) return;
	$if env::WIN32:
		self.running = false;
	$else
		if (self.child > 0)
		{
			(void)kill(-self.child, 1);
			(void)kill(-self.child, 9);
			CInt status;
			(void)waitpid(self.child, &status, 0);
			self.child = -1;
		}
		if (self.master >= 0)
		{
			(void)close(self.master);
			self.master = -1;
		}
		self.running = false;
	$endif
}