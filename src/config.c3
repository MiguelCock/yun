module yun::config;

import std::collections::list;
import std::collections::object;
import std::core::dstring;
import std::core::mem::alloc;
import std::encoding::json;
import std::io::file;
import std::io::path;
import std::os::env;
import yun::commands;
import yun::settings;

const String CONFIG_DIR     = "yun";
const String CONFIG_FILE    = "config.json";
const String PROJECT_DIR    = ".yun";
const String DEFAULT_CONFIG = "{\n  \"app\": {\n    \"theme\": \"dark\"\n  },\n  \"editor\": {\n    \"font_size\": 16\n  },\n  \"keymap\": {},\n  \"lsp\": {}\n}\n";

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

struct RunEnv
{
	String key;
	String value;
}

struct RunProfile
{
	String name;
	String command;
	String cwd;
	List{RunEnv} env;
}

struct Config
{
	Allocator allocator;
	settings::Settings settings;
	List{KeyBinding} keymap_global;
	List{KeyBinding} keymap_project;
	List{LspCommand} lsp;
	List{RunProfile} run_profiles;
	List{String} warnings;
	bool lsp_enabled;
}

fn void Config.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.settings.init(allocator);
	self.keymap_global.init(allocator);
	self.keymap_project.init(allocator);
	self.lsp.init(allocator);
	self.run_profiles.init(allocator);
	self.warnings.init(allocator);
	self.lsp_enabled = true;
}

fn void Config.destroy(&self)
{
	self.settings.destroy();
	self.free_keymap();
	self.free_lsp();
	self.free_run_profiles();
	self.free_warnings();
	self.keymap_global.free();
	self.keymap_project.free();
	self.lsp.free();
	self.run_profiles.free();
	self.warnings.free();
}

fn void Config.free_keymap(&self)
{
	self.free_keymap_layer(&self.keymap_global);
	self.free_keymap_layer(&self.keymap_project);
}

fn void Config.free_keymap_layer(&self, List{KeyBinding}* list)
{
	for (sz i = 0; i < list.len(); i++)
	{
		list.get_ref(i).command.free(self.allocator);
		list.get_ref(i).chord.free(self.allocator);
	}
	list.clear();
}

fn List{KeyBinding}* Config.keymap_layer(&self, settings::SettingLayer layer)
{
	switch (layer)
	{
		case settings::SettingLayer.GLOBAL:
			return &self.keymap_global;
		case settings::SettingLayer.PROJECT:
			return &self.keymap_project;
		case settings::SettingLayer.DEFAULT:
			return null;
	}
}

fn sz Config.keymap_index(&self, List{KeyBinding}* list, String command)
{
	for (sz i = 0; i < list.len(); i++)
	{
		if (list.get(i).command.compare_to(command) == 0) return i;
	}
	return -1;
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
	self.settings.reset();
	self.free_keymap();
	self.free_lsp();
	self.free_run_profiles();
	self.free_warnings();
}

fn void Config.add_warning(&self, String message)
{
	self.warnings.push(message.copy(self.allocator));
}

fn void Config.set_key_binding(&self, String command, String chord, settings::SettingLayer layer)
{
	List{KeyBinding}* list = self.keymap_layer(layer);
	if (list == null) return;
	sz index = self.keymap_index(list, command);
	if (index >= 0)
	{
		list.get_ref(index).chord.free(self.allocator);
		list.get_ref(index).chord = chord.copy(self.allocator);
		return;
	}
	list.push({ .command = command.copy(self.allocator), .chord = chord.copy(self.allocator) });
}

fn void Config.remove_key_binding(&self, String command, settings::SettingLayer layer)
{
	List{KeyBinding}* list = self.keymap_layer(layer);
	if (list == null) return;
	sz index = self.keymap_index(list, command);
	if (index < 0) return;
	list.get_ref(index).command.free(self.allocator);
	list.get_ref(index).chord.free(self.allocator);
	list.remove_at(index);
}

fn void Config.clear_keymap(&self, settings::SettingLayer layer)
{
	List{KeyBinding}* list = self.keymap_layer(layer);
	if (list == null) return;
	for (sz i = 0; i < list.len(); i++)
	{
		list.get_ref(i).command.free(self.allocator);
		list.get_ref(i).chord.free(self.allocator);
	}
	list.clear();
}

fn bool Config.keymap_override(&self, String command, String* out_chord, settings::SettingLayer* out_layer)
{
	sz project = self.keymap_index(&self.keymap_project, command);
	if (project >= 0)
	{
		*out_chord = self.keymap_project.get(project).chord;
		*out_layer = settings::SettingLayer.PROJECT;
		return true;
	}
	sz global = self.keymap_index(&self.keymap_global, command);
	if (global >= 0)
	{
		*out_chord = self.keymap_global.get(global).chord;
		*out_layer = settings::SettingLayer.GLOBAL;
		return true;
	}
	return false;
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

fn void Config.apply_keymap(&self, Object* map, settings::SettingLayer layer)
{
	map.@each_entry(; String key, Object* value)
	{
		if (!value.is_string())
		{
			self.add_warning(string::format(self.allocator, "Config keymap entry \"%s\" must be a string", key));
		}
		else
		{
			self.set_key_binding(key, value.s, layer);
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

fn void RunProfile.free(&self, Allocator allocator)
{
	if (self.name.len > 0) self.name.free(allocator);
	if (self.command.len > 0) self.command.free(allocator);
	if (self.cwd.len > 0) self.cwd.free(allocator);
	for (sz i = 0; i < self.env.len(); i++)
	{
		if (self.env[i].key.len > 0) self.env[i].key.free(allocator);
		if (self.env[i].value.len > 0) self.env[i].value.free(allocator);
	}
	self.env.free();
}

fn void Config.free_run_profiles(&self)
{
	for (sz i = 0; i < self.run_profiles.len(); i++) self.run_profiles[i].free(self.allocator);
	self.run_profiles.clear();
}

fn void Config.set_run_profile(&self, RunProfile profile)
{
	for (sz i = 0; i < self.run_profiles.len(); i++)
	{
		if (self.run_profiles[i].name.compare_to(profile.name) == 0)
		{
			self.run_profiles[i].free(self.allocator);
			self.run_profiles[i] = profile;
			return;
		}
	}
	self.run_profiles.push(profile);
}

fn bool run_env_name_valid(String key)
{
	if (key.len == 0) return false;
	char c = key[0];
	if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '_')) return false;
	for (usz i = 1; i < key.len; i++)
	{
		c = key[i];
		if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_'))
		{
			return false;
		}
	}
	return true;
}

fn void Config.apply_run_profile(&self, String name, Object* value)
{
	if (name.len == 0 || !value.is_map())
	{
		self.add_warning(string::format(self.allocator, "Config run profile \"%s\" must be an object", name));
		return;
	}
	Object*? command_obj = value.get("command");
	if (catch excuse = command_obj)
	{
		self.add_warning(string::format(self.allocator, "Run profile \"%s\" is missing a command", name));
		return;
	}
	if (!command_obj.is_string() || command_obj.s.len == 0)
	{
		self.add_warning(string::format(self.allocator, "Run profile \"%s\" command must be a non-empty string", name));
		return;
	}
	String cwd       = ".";
	Object*? cwd_obj = value.get("cwd");
	if (try cwd_value = cwd_obj)
	{
		if (!cwd_value.is_string() || cwd_value.s.len == 0)
		{
			self.add_warning(string::format(self.allocator, "Run profile \"%s\" cwd must be a non-empty string", name));
			return;
		}
		cwd = cwd_value.s;
	}
	List{RunEnv} env;
	env.init(self.allocator);
	Object*? env_obj = value.get("env");
	if (try env_value_obj = env_obj)
	{
		if (!env_value_obj.is_map())
		{
			self.add_warning(string::format(self.allocator, "Run profile \"%s\" env must be an object", name));
			env.free();
			return;
		}
		env_value_obj.@each_entry(; String key, Object* env_value)
		{
			if (!run_env_name_valid(key) || !env_value.is_string())
			{
				self.add_warning(
					string::format(
						self.allocator,
						"Run profile \"%s\" env entries must use valid names and string values",
						name
					)
				);
			}
			else
			{
				env.push({ .key = key.copy(self.allocator), .value = env_value.s.copy(self.allocator) });
			}
		};
	}
	RunProfile profile = {
		.name = name.copy(self.allocator),
		.command = command_obj.s.copy(self.allocator),
		.cwd = cwd.copy(self.allocator),
		.env = env,
	};
	self.set_run_profile(profile);
}

fn void Config.apply_run(&self, Object* map)
{
	map.@each_entry(; String name, Object* value)
	{
		self.apply_run_profile(name, value);
	};
}

fn void Config.apply_object(&self, Object* obj, settings::SettingLayer layer)
{
	if (!obj.is_map())
	{
		self.add_warning("Config root must be an object");
		return;
	}

	obj.@each_entry(; String key, Object* value)
	{
		bool handled = key.compare_to("keymap") == 0 || key.compare_to("lsp") == 0 || key.compare_to("run") == 0;
		if (!handled && settings::is_section(key))
		{
			self.settings.apply_section(key, value, layer, &self.warnings);
			handled = true;
		}
		if (!handled)
		{
			self.add_warning(string::format(self.allocator, "Unknown config key: %s", key));
		}
	};

	if (obj.has_key("keymap"))
	{
		Object*? keymap = obj.get("keymap");
		if (catch excuse = keymap)
		{
			self.add_warning("Config \"keymap\" is invalid");
		}
		else if (keymap.is_map())
		{
			self.apply_keymap(keymap, layer);
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
	if (obj.has_key("run"))
	{
		Object*? run = obj.get("run");
		if (catch excuse = run)
		{
			self.add_warning("Config \"run\" is invalid");
		}
		else if (run.is_map())
		{
			self.apply_run(run);
		}
		else
		{
			self.add_warning("Config \"run\" must be an object");
		}
	}
}

fn bool Config.apply_json(&self, String json_text, settings::SettingLayer layer)
{
	Object*? parsed = json::parse(self.allocator, json_text);
	if (catch excuse = parsed) return false;
	Object* obj = parsed;
	self.apply_object(obj, layer);
	obj.free();
	return true;
}

fn bool Config.load_path(&self, Path path, settings::SettingLayer layer)
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
			ok = self.apply_json((String)data, layer);
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
	@pool()
	{
		Path? config_dir = env::get_config_dir(tmem);
		if (catch excuse = config_dir)
		{
			self.add_warning("Could not resolve config directory");
			return;
		}
		Path? dir = config_dir.append(tmem, CONFIG_DIR);
		if (catch excuse = dir)
		{
			self.add_warning("Could not resolve config directory");
			return;
		}
		Path? file = dir.append(tmem, CONFIG_FILE);
		if (catch excuse = file)
		{
			self.add_warning("Could not resolve config path");
			return;
		}
		self.ensure_defaults(dir, file);
		self.load_path(file, settings::SettingLayer.GLOBAL);
	};
}

fn void Config.load_project(&self, String project_root)
{
	if (project_root.len == 0) return;
	@pool()
	{
		Path? dir = ((Path)project_root).append(tmem, PROJECT_DIR);
		if (catch excuse = dir) return;
		Path? file = dir.append(tmem, CONFIG_FILE);
		if (catch excuse = file) return;
		self.load_path(file, settings::SettingLayer.PROJECT);
	};
}

fn void Config.load(&self, String project_root)
{
	self.reset();
	self.load_global();
	self.load_project(project_root);
	self.lsp_enabled = self.settings.get_bool(settings::SettingId.LSP_ENABLED);
	self.settings.mark_all_changed();
}

fn String Config.key_binding(&self, commands::CommandId id)
{
	String name = commands::command_name(id);
	String chord;
	settings::SettingLayer layer;
	if (self.keymap_override(name, &chord, &layer)) return chord;
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

fn void append_json_string(DString* out, String s)
{
	out.append_char('"');
	for (usz i = 0; i < s.len; i++)
	{
		char c = s[i];
		if (c == '"' || c == '\\') out.append_char('\\');
		out.append_char(c);
	}
	out.append_char('"');
}

fn void Config.save_path(&self, Path path, settings::SettingLayer scope)
{
	@pool()
	{
		DString out;
		out.init(tmem, 256);
		out.append_string("{\n");
		self.settings.write_sections(&out, scope);
		List{KeyBinding}* keymap = self.keymap_layer(scope);
		out.append_string("  \"keymap\": {");
		if (keymap != null)
		{
			for (sz i = 0; i < keymap.len(); i++)
			{
				if (i > 0) out.append_string(", ");
				append_json_string(&out, keymap.get(i).command);
				out.append_string(": ");
				append_json_string(&out, keymap.get(i).chord);
			}
		}
		out.append_string("},\n");
		out.append_string("  \"lsp\": {");
		for (sz i = 0; i < self.lsp.len(); i++)
		{
			if (i > 0) out.append_string(", ");
			append_json_string(&out, self.lsp[i].language);
			out.append_string(": ");
			append_json_string(&out, self.lsp[i].command);
		}
		out.append_string("}\n}\n");
		(void)file::save(path, out.str_view());
		out.free();
	};
}

fn void Config.save_global(&self)
{
	@pool()
	{
		Path? config_dir = env::get_config_dir(tmem);
		if (catch excuse = config_dir) return;
		Path? dir = config_dir.append(tmem, CONFIG_DIR);
		if (catch excuse = dir) return;
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		Path? file = dir.append(tmem, CONFIG_FILE);
		if (catch excuse = file) return;
		self.save_path(file, settings::SettingLayer.GLOBAL);
	};
}

fn void Config.save_project(&self, String project_root)
{
	if (project_root.len == 0) return;
	@pool()
	{
		Path? dir = ((Path)project_root).append(tmem, PROJECT_DIR);
		if (catch excuse = dir) return;
		Path? file = dir.append(tmem, CONFIG_FILE);
		if (catch excuse = file) return;
		if (catch excuse = path::mkdir(dir, recursive: true)) return;
		self.save_path(file, settings::SettingLayer.PROJECT);
	};
}