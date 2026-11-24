module yun::git;

import std::collections::list;
import std::core::dstring;
import std::core::mem::alloc;
import std::os::env;
import std::os::process;
import std::thread;
import std::thread::channel;
import std::time;
import std::time::clock;

const usz DEFAULT_OUTPUT_CAP = 8 * 1024 * 1024;
const usz DEFAULT_ERROR_CAP  = 1024 * 1024;
const int POLL_MS            = 2;
const int OUTPUT_CHUNK       = 8192;

struct GitRequest
{
	ulong id;
	GitRequestKind kind;
	String[] argv;
	int timeout_ms;
	usz output_cap;
	bool staged;
	bool untracked;
	String path;
	String orig_path;
}

struct GitResult
{
	ulong id;
	GitRequestKind kind;
	int exit_code;
	bool spawn_failed;
	bool cancelled;
	bool timed_out;
	bool truncated;
	bool staged;
	String path;
	String orig_path;
	DString output;
	DString error;
}

struct GitExecutor
{
	Allocator allocator;
	UnboundedChannel{GitRequest}* requests;
	UnboundedChannel{GitResult}* results;
	Thread worker;
	bool started;
	Mutex mutex;
	ulong cancel_id;
	bool stopping;
}

fn void git_free_argv(Allocator allocator, String[] argv)
{
	for (usz i = 0; i < argv.len; i++)
	{
		if (argv[i].len > 0) argv[i].free(allocator);
	}
	alloc::free(allocator, argv);
}

fn void GitResult.destroy(&self, Allocator allocator)
{
	if (self.path.len > 0) self.path.free(allocator);
	if (self.orig_path.len > 0) self.orig_path.free(allocator);
	self.output.free();
	self.error.free();
}

fn void append_capped(DString* out, String text, usz cap, bool* truncated)
{
	if (text.len == 0) return;
	usz current = (usz)out.len();
	if (current >= cap)
	{
		*truncated = true;
		return;
	}
	usz remaining = cap - current;
	if (text.len > remaining)
	{
		out.append_string(text[0:remaining]);
		*truncated = true;
		return;
	}
	out.append_string(text);
}

fn void drain_process(Process* process, DString* out, DString* err, usz out_cap, usz err_cap, bool* truncated)
{
	char[OUTPUT_CHUNK] chunk;
	while (true)
	{
		sz? read = process.read_stdout(&chunk[0], (sz)chunk.len);
		sz got   = 0;
		if (try value = read) got = value;
		if (got <= 0) break;
		append_capped(out, (String)chunk[0:got], out_cap, truncated);
	}
	while (true)
	{
		sz? read = process.read_stderr(&chunk[0], (sz)chunk.len);
		sz got   = 0;
		if (try value = read) got = value;
		if (got <= 0) break;
		append_capped(err, (String)chunk[0:got], err_cap, truncated);
	}
}

fn bool GitExecutor.cancelled(&self, ulong id)
{
	self.mutex.lock();
	bool cancelled = self.cancel_id == id;
	bool stopping  = self.stopping;
	self.mutex.unlock();
	return cancelled || stopping;
}

fn GitResult git_run_request(GitExecutor* executor, GitRequest* request)
{
	GitResult result;
	result.id = request.id;
	result.kind = request.kind;
	result.exit_code = -1;
	result.spawn_failed = false;
	result.cancelled = false;
	result.timed_out = false;
	result.truncated = false;
	result.staged = request.staged;
	result.path = request.path.len > 0 ? request.path.copy(executor.allocator) : "";
	result.orig_path = request.orig_path.len > 0 ? request.orig_path.copy(executor.allocator) : "";
	result.output.init(executor.allocator);
	result.error.init(executor.allocator);

	process::SpawnOptions options = process::SpawnOptions.INHERIT_ENV | process::SpawnOptions.ASYNC_OUTPUT;
	$if env::WIN32:
		options = options | process::SpawnOptions.NO_WINDOW;
	$endif
	Process? spawned = process::spawn(request.argv, options, { }, process::CAPTURE, process::CAPTURE, process::CAPTURE);
	if (catch excuse = spawned)
	{
		result.spawn_failed = true;
		result.error.append_string("Could not start Git");
		return result;
	}

	Process process = spawned;
	defer (void)process.destroy();
	Clock start = clock::now();
	bool alive  = true;
	while (true)
	{
		drain_process(
			&process,
			&result.output,
			&result.error,
			request.output_cap,
			DEFAULT_ERROR_CAP,
			&result.truncated
		);

		bool? running = process.is_running();
		if (try value = running)
		{
			alive = value;
		}
		else
		{
			alive = false;
		}
		if (!alive) break;

		if (GitExecutor.cancelled(executor, request.id))
		{
			result.cancelled = true;
			(void)process.terminate();
			break;
		}
		if (request.timeout_ms > 0 && start.to_now().to_ms() > request.timeout_ms)
		{
			result.timed_out = true;
			(void)process.terminate();
			break;
		}
		thread::sleep_ms(POLL_MS);
	}

	drain_process(&process, &result.output, &result.error, request.output_cap, DEFAULT_ERROR_CAP, &result.truncated);
	if (alive || result.cancelled || result.timed_out)
	{
		(void)process.terminate();
	}
	int? code = process.join();
	if (try value = code) result.exit_code = (int)value;
	return result;
}

fn int git_worker_main(void* arg)
{
	GitExecutor* executor = (GitExecutor*)arg;
	while (true)
	{
		executor.mutex.lock();
		bool stopping = executor.stopping;
		executor.mutex.unlock();
		if (stopping) break;

		GitRequest? maybe = executor.requests.pop();
		if (catch excuse = maybe) break;
		GitRequest request = maybe;
		GitResult result   = git_run_request(executor, &request);
		git_free_argv(executor.allocator, request.argv);
		if (request.path.len > 0) request.path.free(executor.allocator);
		if (request.orig_path.len > 0) request.orig_path.free(executor.allocator);
		if (catch excuse = executor.results.push(result))
		{
			result.destroy(executor.allocator);
			break;
		}
	}
	return 0;
}

fn void GitExecutor.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.requests = null;
	self.results = null;
	self.started = false;
	self.cancel_id = 0;
	self.stopping = false;
	self.mutex.init()!!;
}

fn bool GitExecutor.ensure_started(&self)
{
	if (self.started) return true;
	UnboundedChannel{GitRequest}*? requests = channel::create_unbounded{GitRequest}(self.allocator);
	if (catch excuse = requests) return false;
	UnboundedChannel{GitResult}*? results = channel::create_unbounded{GitResult}(self.allocator);
	if (catch excuse = results)
	{
		requests.destroy();
		return false;
	}
	self.requests = requests;
	self.results = results;
	if (catch excuse = self.worker.create(&git_worker_main, self))
	{
		self.requests.destroy();
		self.results.destroy();
		self.requests = null;
		self.results = null;
		return false;
	}
	self.started = true;
	return true;
}

fn bool GitExecutor.submit(&self, GitRequest* request)
{
	if (request.output_cap == 0) request.output_cap = DEFAULT_OUTPUT_CAP;
	if (!self.ensure_started())
	{
		git_free_argv(self.allocator, request.argv);
		if (request.path.len > 0) request.path.free(self.allocator);
		if (request.orig_path.len > 0) request.orig_path.free(self.allocator);
		return false;
	}
	if (catch excuse = self.requests.push(*request))
	{
		git_free_argv(self.allocator, request.argv);
		if (request.path.len > 0) request.path.free(self.allocator);
		if (request.orig_path.len > 0) request.orig_path.free(self.allocator);
		return false;
	}
	return true;
}

fn void GitExecutor.cancel(&self, ulong id)
{
	self.mutex.lock();
	self.cancel_id = id;
	self.mutex.unlock();
}

fn bool GitExecutor.try_pop(&self, GitResult* out)
{
	if (self.results == null) return false;
	GitResult? maybe = self.results.try_pop();
	if (catch excuse = maybe) return false;
	*out = maybe;
	return true;
}

fn void GitExecutor.stop(&self)
{
	if (!self.started)
	{
		self.mutex.destroy();
		return;
	}
	self.mutex.lock();
	self.stopping = true;
	self.mutex.unlock();
	self.requests.close();
	(void)self.worker.join();
	self.requests.destroy();
	self.requests = null;
	if (self.results)
	{
		while (true)
		{
			GitResult result;
			if (!self.try_pop(&result)) break;
			result.destroy(self.allocator);
		}
		self.results.destroy();
		self.results = null;
	}
	self.started = false;
	self.mutex.destroy();
}