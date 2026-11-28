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
	void* win_hpc;
	void* win_input;
	void* win_output;
	void* win_process;
	void* win_thread;
}

struct ConsoleWinsize
{
	ushort rows;
	ushort cols;
	ushort xpixel;
	ushort ypixel;
}

struct ConsoleWinCoord
{
	short x;
	short y;
}

struct ConsoleWinSecurity
{
	uint length;
	void* descriptor;
	int inherit;
}

struct ConsoleWinStartup
{
	uint cb;
	void* reserved;
	void* desktop;
	void* title;
	uint x;
	uint y;
	uint x_size;
	uint y_size;
	uint x_chars;
	uint y_chars;
	uint fill;
	uint flags;
	ushort show;
	ushort reserved2_len;
	void* reserved2;
	void* std_input;
	void* std_output;
	void* std_error;
}

struct ConsoleWinStartupEx
{
	inline ConsoleWinStartup startup;
	void* attribute_list;
}

struct ConsoleWinProcess
{
	void* process;
	void* thread;
	uint process_id;
	uint thread_id;
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

extern fn int createPseudoConsole(
	ConsoleWinCoord size,
	void* input,
	void* output,
	uint flags,
	void** console
) @cname("CreatePseudoConsole") @feat(WIN32);
extern fn int resizePseudoConsole(void* console, ConsoleWinCoord size) @cname("ResizePseudoConsole") @feat(WIN32);
extern fn void closePseudoConsole(void* console) @cname("ClosePseudoConsole") @feat(WIN32);
extern fn int createPipe(
	void** read,
	void** write,
	ConsoleWinSecurity* attributes,
	uint size
) @cname("CreatePipe") @feat(WIN32);
extern fn int setHandleInformation(void* handle, uint mask, uint flags) @cname("SetHandleInformation") @feat(WIN32);
extern fn int closeHandle(void* handle) @cname("CloseHandle") @feat(WIN32);
extern fn int initializeProcThreadAttributeList(
	void* list,
	uint count,
	uint flags,
	usz* size
) @cname("InitializeProcThreadAttributeList") @feat(WIN32);
extern fn int updateProcThreadAttribute(
	void* list,
	uint flags,
	usz attribute,
	void* value,
	usz size,
	void* previous,
	usz* returned
) @cname("UpdateProcThreadAttribute") @feat(WIN32);
extern fn void deleteProcThreadAttributeList(void* list) @cname("DeleteProcThreadAttributeList") @feat(WIN32);
extern fn int createProcessW(
	Char16* application,
	Char16* command,
	void* process_attributes,
	void* thread_attributes,
	int inherit,
	uint flags,
	void* environment,
	Char16* directory,
	void* startup,
	ConsoleWinProcess* process
) @cname("CreateProcessW") @feat(WIN32);
extern fn int readFile(
	void* file,
	void* buffer,
	uint size,
	uint* read,
	void* overlapped
) @cname("ReadFile") @feat(WIN32);
extern fn int writeFile(
	void* file,
	void* buffer,
	uint size,
	uint* written,
	void* overlapped
) @cname("WriteFile") @feat(WIN32);
extern fn int peekNamedPipe(
	void* pipe,
	void* buffer,
	uint size,
	uint* read,
	uint* available,
	uint* left
) @cname("PeekNamedPipe") @feat(WIN32);
extern fn int getExitCodeProcess(void* process, uint* code) @cname("GetExitCodeProcess") @feat(WIN32);
extern fn uint waitForSingleObject(void* handle, uint ms) @cname("WaitForSingleObject") @feat(WIN32);
extern fn int terminateProcess(void* process, uint code) @cname("TerminateProcess") @feat(WIN32);

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
	self.win_hpc = null;
	self.win_input = null;
	self.win_output = null;
	self.win_process = null;
	self.win_thread = null;
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
		@pool()
		{
			ConsoleWinSecurity security = { .length = 24, .descriptor = null, .inherit = 1 };
			void* input_read            = null;
			void* input_write           = null;
			void* output_read           = null;
			void* output_write          = null;
			if (!createPipe(
				&input_read,
				&input_write,
				&security,
				0
			) || !createPipe(&output_read, &output_write, &security, 0))
			{
				self.set_error("Could not create terminal pipes");
				return false;
			}
			ConsoleWinCoord size = { .x = (short)self.cols, .y = (short)self.rows };
			void* console        = null;
			if (createPseudoConsole(size, input_read, output_write, 0, &console) < 0)
			{
				(void)closeHandle(input_read);
				(void)closeHandle(input_write);
				(void)closeHandle(output_read);
				(void)closeHandle(output_write);
				self.set_error("Could not create a pseudoconsole");
				return false;
			}
			usz attr_size = 0;
			(void)initializeProcThreadAttributeList(null, 1, 0, &attr_size);
			char[] attr_buffer = alloc::new_array(tmem, char, (sz)attr_size);
			void* attrs        = &attr_buffer[0];
			if (!initializeProcThreadAttributeList(
				attrs,
				1,
				0,
				&attr_size
			) || !updateProcThreadAttribute(attrs, 0, 0x00020016, &console, (usz)@sizeof(console), null, null))
			{
				(void)closePseudoConsole(console);
				(void)closeHandle(input_read);
				(void)closeHandle(input_write);
				(void)closeHandle(output_read);
				(void)closeHandle(output_write);
				self.set_error("Could not bind the pseudoconsole");
				return false;
			}
			ConsoleWinStartupEx startup = { };
			startup.startup.cb = (uint)@sizeof(startup);
			startup.attribute_list = attrs;
			ConsoleWinProcess process;
			Char16[]? command = "cmd.exe /Q".to_temp_utf16();
			if (catch err = command)
			{
				(void)deleteProcThreadAttributeList(attrs);
				(void)closePseudoConsole(console);
				return false;
			}
			Char16[] cwd_value = { };
			if (root.len > 0)
			{
				Char16[]? converted = root.to_temp_utf16();
				if (catch err = converted)
				{
				}
				else
				{
					cwd_value = converted;
				}
			}
			Char16* cwd_ptr = cwd_value.len > 0 ? &cwd_value[0] : null;
			int created = createProcessW(
				null,
				&command[0],
				null,
				null,
				1,
				0x00080000 | 0x00000400,
				null,
				cwd_ptr,
				&startup,
				&process
			);
			(void)deleteProcThreadAttributeList(attrs);
			if (!created)
			{
				(void)closePseudoConsole(console);
				(void)closeHandle(input_read);
				(void)closeHandle(input_write);
				(void)closeHandle(output_read);
				(void)closeHandle(output_write);
				self.set_error("Could not start cmd.exe");
				return false;
			}
			self.win_hpc = console;
			self.win_input = input_write;
			self.win_output = output_read;
			self.win_process = process.process;
			self.win_thread = process.thread;
			(void)closeHandle(input_read);
			(void)closeHandle(output_write);
		};
		self.running = true;
		return true;
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
		if (!self.win_output) return 0;
		uint available = 0;
		if (!peekNamedPipe(self.win_output, null, 0, null, &available, null) || available == 0) return 0;
		uint want       = available < buffer.len ? available : (uint)buffer.len;
		uint read_count = 0;
		if (!readFile(self.win_output, &buffer[0], want, &read_count, null)) return 0;
		return read_count;
	$else
		CInt count = read(self.master, &buffer[0], buffer.len);
		return count > 0 ? (usz)count : 0;
	$endif
}

fn void ConsolePty.write(&self, String text)
{
	if (!self.running || self.master < 0 || text.len == 0) return;
	$if env::WIN32:
		if (!self.win_input) return;
		uint written = 0;
		(void)writeFile(self.win_input, (void*)&text[0], (uint)text.len, &written, null);
	$else
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
	$if env::WIN32:
		if (self.win_hpc)
		{
			ConsoleWinCoord size = { .x = (short)cols, .y = (short)rows };
			(void)resizePseudoConsole(self.win_hpc, size);
		}
	$else
		self.update_winsize();
	$endif
}

fn bool ConsolePty.poll_exit(&self, int* exit_code)
{
	if (!self.running) return true;
	$if env::WIN32:
		if (!self.win_process) return false;
		if (waitForSingleObject(self.win_process, 0) != 0) return false;
		uint code = 0;
		(void)getExitCodeProcess(self.win_process, &code);
		*exit_code = (int)code;
		self.running = false;
		(void)closeHandle(self.win_process);
		(void)closeHandle(self.win_thread);
		self.win_process = null;
		self.win_thread = null;
		return true;
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
		if (self.win_process)
		{
			(void)terminateProcess(self.win_process, 0);
			(void)waitForSingleObject(self.win_process, 0xFFFFFFFF);
			(void)closeHandle(self.win_process);
			(void)closeHandle(self.win_thread);
			self.win_process = null;
			self.win_thread = null;
		}
		if (self.win_hpc)
		{
			closePseudoConsole(self.win_hpc);
			self.win_hpc = null;
		}
		if (self.win_input)
		{
			(void)closeHandle(self.win_input);
			self.win_input = null;
		}
		if (self.win_output)
		{
			(void)closeHandle(self.win_output);
			self.win_output = null;
		}
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