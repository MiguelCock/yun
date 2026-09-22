module yun::config;

import std::collections::list;
import std::collections::object;
import std::core::mem::alloc;
import std::encoding::json;
import std::io::file;
import std::io::path;
import std::os::env;
import yun::commands;

const String CONFIG_DIR     = "yun";
const String CONFIG_FILE    = "config.json";
const String PROJECT_DIR    = ".yun";
const String DEFAULT_THEME  = "dark";
const int DEFAULT_FONT_SIZE = 16;
const String DEFAULT_CONFIG = "{\n  \"theme\": \"dark\",\n  \"font_size\": 16,\n  \"keymap\": {},\n  \"lsp\": {}\n}\n";
const String[] KNOWN_KEYS   = { "theme", "font_size", "keymap", "lsp" };

struct KeyBinding
{
	String command;
	String chord;
}

struct LspCommand
{
	String language;
	String command;
}

struct Config
{
	Allocator allocator;
	String theme;
	int font_size;
	bool owns_theme;
	List{KeyBinding} keymap;
	List{LspCommand} lsp;
	List{String} warnings;
}

fn void Config.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.theme = DEFAULT_THEME;
	self.font_size = DEFAULT_FONT_SIZE;
	self.owns_theme = false;
	self.keymap.init(allocator);
	self.lsp.init(allocator);
	self.warnings.init(allocator);
}

fn void Config.destroy(&self)
{
	self.free_theme();
	self.free_keymap();
	self.free_lsp();
	self.free_warnings();
	self.keymap.free();
	self.lsp.free();
	self.warnings.free();
}

fn void Config.free_theme(&self)
{
	if (self.owns_theme) self.theme.free(self.allocator);
	self.owns_theme = false;
}

fn void Config.free_keymap(&self)
{
	for (sz i = 0; i < self.keymap.len(); i++)
	{
		self.keymap[i].command.free(self.allocator);
		self.keymap[i].chord.free(self.allocator);
	}
	self.keymap.clear();
}

fn void Config.free_lsp(&self)
{
	for (sz i = 0; i < self.lsp.len(); i++)
	{
		self.lsp[i].language.free(self.allocator);
		self.lsp[i].command.free(self.allocator);
	}
	self.lsp.clear();
}

fn void Config.free_warnings(&self)
{
	for (sz i = 0; i < self.warnings.len(); i++)
	{
		self.warnings[i].free(self.allocator);
	}
	self.warnings.clear();
}

fn void Config.reset(&self)
{
	self.free_theme();
	self.theme = DEFAULT_THEME;
	self.font_size = DEFAULT_FONT_SIZE;
	self.free_keymap();
	self.free_lsp();
	self.free_warnings();
}

fn void Config.set_theme(&self, String value)
{
	self.free_theme();
	self.theme = value.copy(self.allocator);
	self.owns_theme = true;
}

fn void Config.add_warning(&self, String message)
{
	self.warnings.push(message.copy(self.allocator));
}

fn bool is_known_key(String key)
{
	foreach (String known : KNOWN_KEYS)
	{
		if (key.compare_to(known) == 0) return true;
	}
	return false;
}

fn void Config.set_key_binding(&self, String command, String chord)
{
	for (sz i = 0; i < self.keymap.len(); i++)
	{
		if (self.keymap[i].command.compare_to(command) == 0)
		{
			self.keymap[i].chord.free(self.allocator);
			self.keymap[i].chord = chord.copy(self.allocator);
			return;
		}
	}
	self.keymap.push({ .command = command.copy(self.allocator), .chord = chord.copy(self.allocator) });
}

fn void Config.set_lsp_command(&self, String language, String command)
{
	for (sz i = 0; i < self.lsp.len(); i++)
	{
		if (self.lsp[i].language.compare_to(language) == 0)
		{
			self.lsp[i].command.free(self.allocator);
			self.lsp[i].command = command.copy(self.allocator);
			return;
		}
	}
	self.lsp.push({ .language = language.copy(self.allocator), .command = command.copy(self.allocator) });
}

fn void Config.apply_keymap(&self, Object* map)
{
	map.@each_entry(; String key, Object* value)
	{
		if (!value.is_string())
		{
			self.add_warning(string::format(self.allocator, "Config keymap entry \"%s\" must be a string", key));
		}
		else
		{
			self.set_key_binding(key, value.s);
		}
	};
}

fn void Config.apply_lsp(&self, Object* map)
{
	map.@each_entry(; String key, Object* value)
	{
		if (!value.is_string())
		{
			self.add_warning(string::format(self.allocator, "Config lsp entry \"%s\" must be a string", key));
		}
		else
		{
			self.set_lsp_command(key, value.s);
		}
	};
}

fn void Config.apply_object(&self, Object* obj)
{
	if (!obj.is_map())
	{
		self.add_warning("Config root must be an object");
		return;
	}

	obj.@each_entry(; String key, Object* value)
	{
		if (!is_known_key(key))
		{
			self.add_warning(string::format(self.allocator, "Unknown config key: %s", key));
		}
	};

	if (obj.has_key("theme"))
	{
		String? theme = obj.get_string("theme");
		if (catch excuse = theme)
		{
			self.add_warning("Config \"theme\" must be a string");
		}
		else
		{
			self.set_theme(theme);
		}
	}
	if (obj.has_key("font_size"))
	{
		int? size = obj.get_int("font_size");
		if (catch excuse = size)
		{
			self.add_warning("Config \"font_size\" must be an integer");
		}
		else
		{
			self.font_size = size;
		}
	}
	if (obj.has_key("keymap"))
	{
		Object*? keymap = obj.get("keymap");
		if (catch excuse = keymap)
		{
			self.add_warning("Config \"keymap\" is invalid");
		}
		else if (keymap.is_map())
		{
			self.apply_keymap(keymap);
		}
		else
		{
			self.add_warning("Config \"keymap\" must be an object");
		}
	}
	if (obj.has_key("lsp"))
	{
		Object*? lsp = obj.get("lsp");
		if (catch excuse = lsp)
		{
			self.add_warning("Config \"lsp\" is invalid");
		}
		else if (lsp.is_map())
		{
			self.apply_lsp(lsp);
		}
		else
		{
			self.add_warning("Config \"lsp\" must be an object");
		}
	}
}

fn bool Config.apply_json(&self, String json)
{
	Object*? parsed = json::parse(self.allocator, json);
	if (catch excuse = parsed) return false;
	Object* obj = parsed;
	self.apply_object(obj);
	obj.free();
	return true;
}

fn bool Config.load_path(&self, Path path)
{
	if (!path::exists(path)) return false;
	bool ok = false;
	@pool()
	{
		char[]? data = file::load(tmem, path);
		if (catch excuse = data)
		{
			ok = false;
		}
		else
		{
			ok = self.apply_json((String)data);
		}
	};
	if (!ok) self.add_warning(string::format(self.allocator, "Malformed config: %s", (String)path));
	return ok;
}

fn void Config.ensure_defaults(&self, Path dir, Path file)
{
	if (path::exists(file)) return;
	if (catch excuse = path::mkdir(dir, recursive: true)) return;
	(void)file::save(file, DEFAULT_CONFIG);
}

fn void Config.load_global(&self)
{
	Path? config_dir = env::get_config_dir(self.allocator);
	if (catch excuse = config_dir)
	{
		self.add_warning("Could not resolve config directory");
		return;
	}
	Path? dir = config_dir.append(self.allocator, CONFIG_DIR);
	if (catch excuse = dir)
	{
		self.add_warning("Could not resolve config directory");
		return;
	}
	Path? file = dir.append(self.allocator, CONFIG_FILE);
	if (catch excuse = file)
	{
		self.add_warning("Could not resolve config path");
		return;
	}
	self.ensure_defaults(dir, file);
	self.load_path(file);
}

fn void Config.load_project(&self, String project_root)
{
	if (project_root.len == 0) return;
	Path? dir = ((Path)project_root).append(self.allocator, PROJECT_DIR);
	if (catch excuse = dir) return;
	Path? file = dir.append(self.allocator, CONFIG_FILE);
	if (catch excuse = file) return;
	self.load_path(file);
}

fn void Config.load(&self, String project_root)
{
	self.reset();
	self.load_global();
	self.load_project(project_root);
}

fn String Config.key_binding(&self, commands::CommandId id)
{
	String name = commands::command_name(id);
	for (sz i = 0; i < self.keymap.len(); i++)
	{
		if (self.keymap[i].command.compare_to(name) == 0) return self.keymap[i].chord;
	}
	return "";
}

fn String Config.lsp_command(&self, String language)
{
	for (sz i = 0; i < self.lsp.len(); i++)
	{
		if (self.lsp[i].language.compare_to(language) == 0) return self.lsp[i].command;
	}
	return "";
}