module yun::console;

import std::collections::list;
import std::core::mem::alloc;

struct ConsoleSession
{
	Console console;
	ConsolePanel panel;
	String title;
}

struct ConsoleManager
{
	Allocator allocator;
	List{ConsoleSession*} sessions;
	List{ConsoleSession*} pending_free;
	int active;
	int next_title;
	bool visible;
	float height;
	String root;
}

fn void ConsoleManager.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.sessions.init(allocator);
	self.pending_free.init(allocator);
	self.active = 0;
	self.next_title = 1;
	self.visible = false;
	self.height = DEFAULT_HEIGHT;
	self.root = "";
	(void)self.add_session();
}

fn ConsoleSession* ConsoleManager.active_session(&self)
{
	if (self.active < 0 || self.active >= (int)self.sessions.len()) return null;
	return self.sessions[self.active];
}

fn Console* ConsoleManager.active_console(&self)
{
	ConsoleSession* session = self.active_session();
	return session ? &session.console : null;
}

fn ConsolePanel* ConsoleManager.active_panel(&self)
{
	ConsoleSession* session = self.active_session();
	return session ? &session.panel : null;
}

fn int ConsoleManager.add_session_named(&self, String title)
{
	ConsoleSession* session = alloc::new(self.allocator, ConsoleSession);
	session.console.init(self.allocator);
	session.panel.init();
	session.panel.height = self.height;
	session.title = title.len > 0 ? title.copy(self.allocator)
		: string::format(self.allocator, "Console %d", (long)self.next_title);
	self.next_title++;
	if (self.root.len > 0) session.console.set_root(self.root);
	self.sessions.push(session);
	self.active = (int)self.sessions.len() - 1;
	self.sync_active_panel();
	return self.active;
}

fn int ConsoleManager.add_session(&self)
{
	return self.add_session_named("");
}

fn void ConsoleManager.clear_sessions(&self)
{
	for (sz i = 0; i < self.sessions.len(); i++) destroy_session(self, self.sessions[i]);
	for (sz i = 0; i < self.pending_free.len(); i++) destroy_session(self, self.pending_free[i]);
	self.sessions.clear();
	self.pending_free.clear();
	self.active = 0;
	self.next_title = 1;
}

fn void ConsoleManager.sync_active_panel(&self)
{
	for (sz i = 0; i < self.sessions.len(); i++)
	{
		ConsoleSession* session = self.sessions[i];
		session.panel.visible = false;
		session.panel.focused = false;
	}
	ConsolePanel* panel = self.active_panel();
	if (!panel) return;
	panel.height = self.height;
	panel.visible = self.visible;
}

fn void ConsoleManager.select(&self, int index)
{
	if (index < 0 || index >= (int)self.sessions.len()) return;
	self.active = index;
	self.sync_active_panel();
}

fn void ConsoleManager.open(&self)
{
	self.visible = true;
	ConsolePanel* panel = self.active_panel();
	if (panel) panel.open();
	self.sync_active_panel();
}

fn void ConsoleManager.close(&self)
{
	self.visible = false;
	if (g_console_settings.kill_on_close)
	{
		Console* console = self.active_console();
		if (console) console.kill();
	}
	ConsolePanel* panel = self.active_panel();
	if (panel) panel.close();
}

fn void ConsoleManager.sync_height(&self)
{
	ConsolePanel* panel = self.active_panel();
	if (panel && !panel.resizing) self.height = panel.height;
}

fn void ConsoleManager.apply_settings(&self, ConsoleSettings settings)
{
	for (sz i = 0; i < self.sessions.len(); i++)
	{
		ConsoleSession* session = self.sessions[i];
		session.console.apply_settings(settings);
		session.panel.apply_settings(settings);
	}
}

fn void ConsoleManager.pump(&self)
{
	for (sz i = 0; i < self.sessions.len(); i++) self.sessions[i].console.pump();
}

fn void ConsoleManager.set_root(&self, String root)
{
	if (self.root.len > 0) self.root.free(self.allocator);
	self.root = root.len > 0 ? root.copy(self.allocator) : "";
	for (sz i = 0; i < self.sessions.len(); i++) self.sessions[i].console.set_root(self.root);
}

fn void destroy_session(ConsoleManager* self, ConsoleSession* session)
{
	session.console.destroy();
	session.title.free(self.allocator);
	alloc::free(self.allocator, session);
}

fn void ConsoleManager.reset(&self, String root)
{
	self.clear_sessions();
	if (self.root.len > 0) self.root.free(self.allocator);
	self.root = root.len > 0 ? root.copy(self.allocator) : "";
	(void)self.add_session();
}

fn bool ConsoleManager.close_session(&self, int index)
{
	if (index < 0 || index >= (int)self.sessions.len()) return false;
	if (self.sessions.len() == 1)
	{
		ConsoleSession* only = self.sessions[0];
		only.console.kill();
		only.console.clear();
		only.console.input.clear();
		only.panel.close();
		self.visible = false;
		return true;
	}
	ConsoleSession* session = self.sessions[index];
	session.panel.visible = false;
	session.panel.focused = false;
	self.sessions.remove_at(index);
	self.pending_free.push(session);
	if (self.active > index) self.active--;
	if (self.active >= (int)self.sessions.len()) self.active = (int)self.sessions.len() - 1;
	if (self.active < 0) self.active = 0;
	self.sync_active_panel();
	return true;
}

fn void ConsoleManager.flush_pending(&self)
{
	for (sz i = 0; i < self.pending_free.len(); i++) destroy_session(self, self.pending_free[i]);
	self.pending_free.clear();
}

fn void ConsoleManager.destroy(&self)
{
	for (sz i = 0; i < self.sessions.len(); i++) destroy_session(self, self.sessions[i]);
	for (sz i = 0; i < self.pending_free.len(); i++) destroy_session(self, self.pending_free[i]);
	self.sessions.free();
	self.pending_free.free();
	if (self.root.len > 0) self.root.free(self.allocator);
	self.root = "";
}