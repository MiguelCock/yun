module yun::theme;

import raylib6::rl;

struct Theme
{
	// canvas
	RLColor window_bg;
	RLColor grid_minor;
	RLColor grid_major;
	// cards
	RLColor card_body;
	RLColor card_title;
	RLColor card_border;
	RLColor card_focus;
	RLColor card_text;
	RLColor card_dirty;
	// folder clusters
	RLColor cluster_body;
	RLColor cluster_border;
	RLColor cluster_title;
	RLColor cluster_text;
	// editor
	RLColor editor_text;
	RLColor editor_placeholder;
	RLColor editor_caret;
	RLColor editor_gutter_bg;
	RLColor editor_gutter_text;
	RLColor editor_current_line;
	RLColor editor_scrollbar;
	RLColor editor_handle;
	RLColor editor_match;
	RLColor editor_match_current;
	RLColor editor_selection;
	// diagnostics
	RLColor diag_error;
	RLColor diag_warning;
	RLColor diag_info;
	RLColor diag_hint;
	// import arrows
	RLColor import_solid;
	RLColor import_external;
	RLColor import_label;
	RLColor import_solid_dim;
	RLColor import_external_dim;
	RLColor import_label_dim;
	RLColor import_solid_hover;
	RLColor import_external_hover;
	// top bar
	RLColor topbar_bg;
	RLColor topbar_border;
	RLColor topbar_button;
	RLColor topbar_hover;
	RLColor topbar_text;
	RLColor topbar_disabled;
	RLColor topbar_name;
	RLColor topbar_error;
	RLColor topbar_warning;
	// minimap
	RLColor minimap_bg;
	RLColor minimap_border;
	RLColor minimap_cluster;
	RLColor minimap_card;
	RLColor minimap_viewport;
	// notifications
	RLColor notice_bg;
	RLColor notice_text;
	// loading overlay
	RLColor loading_scrim;
	RLColor loading_panel;
	RLColor loading_border;
	RLColor loading_title;
	RLColor loading_status;
	RLColor loading_hint;
	// generic panels (browser, palette, problems, menu, hover, completion, prompt, findbar)
	RLColor panel_bg;
	RLColor panel_bg_alt;
	RLColor panel_border;
	RLColor panel_text;
	RLColor panel_dim;
	RLColor panel_disabled;
	RLColor panel_selected;
	RLColor panel_field;
	RLColor panel_caret;
	RLColor panel_match;
	RLColor panel_header;
	RLColor findbar_chip;
	RLColor hover_code;
	RLColor hover_code_bg;
	RLColor hover_heading;
	// syntax highlighting
	RLColor syn_keyword;
	RLColor syn_string;
	RLColor syn_comment;
	RLColor syn_number;
	RLColor syn_type;
	RLColor syn_function;
	RLColor syn_constant;
	RLColor syn_operator;
	RLColor syn_punctuation;
	RLColor syn_attribute;
	RLColor syn_module;
	RLColor syn_label;
	RLColor syn_boolean;
	RLColor syn_character;
	RLColor syn_escape;
	RLColor syn_parameter;
	RLColor syn_property;
	RLColor syn_builtin;
}

struct ThemeSpec
{
	String name;
	String label;
	bool light;
	RLColor bg;
	RLColor fg;
	RLColor surface;
	RLColor surface_alt;
	RLColor border;
	RLColor accent;
	RLColor muted;
	RLColor error;
	RLColor warning;
	RLColor info;
	RLColor hint;
	RLColor syn_keyword;
	RLColor syn_string;
	RLColor syn_comment;
	RLColor syn_number;
	RLColor syn_type;
	RLColor syn_function;
	RLColor syn_constant;
	RLColor syn_operator;
	RLColor syn_punctuation;
	RLColor syn_attribute;
	RLColor syn_module;
	RLColor syn_label;
	RLColor syn_boolean;
	RLColor syn_character;
	RLColor syn_escape;
	RLColor syn_parameter;
	RLColor syn_property;
	RLColor syn_builtin;
}

const ThemeSpec YUN_DARK = {
	.name = "yun_dark",
	.label = "Yun Dark",
	.light = false,
	.bg = { 24, 24, 28, 255 },
	.fg = { 210, 214, 222, 255 },
	.surface = { 32, 32, 38, 255 },
	.surface_alt = { 44, 44, 54, 255 },
	.border = { 70, 70, 84, 255 },
	.accent = { 110, 170, 240, 255 },
	.muted = { 140, 150, 170, 255 },
	.error = { 240, 90, 90, 255 },
	.warning = { 230, 190, 80, 255 },
	.info = { 90, 160, 230, 255 },
	.hint = { 140, 150, 170, 255 },
	.syn_keyword = { 197, 134, 192, 255 },
	.syn_string = { 152, 195, 121, 255 },
	.syn_comment = { 108, 112, 134, 255 },
	.syn_number = { 209, 154, 102, 255 },
	.syn_type = { 229, 192, 123, 255 },
	.syn_function = { 97, 175, 239, 255 },
	.syn_constant = { 209, 154, 102, 255 },
	.syn_operator = { 86, 182, 194, 255 },
	.syn_punctuation = { 150, 155, 170, 255 },
	.syn_attribute = { 229, 192, 123, 255 },
	.syn_module = { 229, 192, 123, 255 },
	.syn_label = { 97, 175, 239, 255 },
	.syn_boolean = { 209, 154, 102, 255 },
	.syn_character = { 152, 195, 121, 255 },
	.syn_escape = { 86, 182, 194, 255 },
	.syn_parameter = { 220, 190, 160, 255 },
	.syn_property = { 224, 108, 117, 255 },
	.syn_builtin = { 86, 182, 194, 255 },
};

const ThemeSpec YUN_LIGHT = {
	.name = "yun_light",
	.label = "Yun Light",
	.light = true,
	.bg = { 246, 246, 249, 255 },
	.fg = { 40, 42, 52, 255 },
	.surface = { 255, 255, 255, 255 },
	.surface_alt = { 236, 237, 242, 255 },
	.border = { 205, 207, 215, 255 },
	.accent = { 60, 120, 220, 255 },
	.muted = { 120, 125, 140, 255 },
	.error = { 200, 50, 50, 255 },
	.warning = { 170, 120, 20, 255 },
	.info = { 30, 110, 190, 255 },
	.hint = { 120, 125, 140, 255 },
	.syn_keyword = { 170, 40, 140, 255 },
	.syn_string = { 30, 120, 60, 255 },
	.syn_comment = { 140, 145, 155, 255 },
	.syn_number = { 160, 90, 20, 255 },
	.syn_type = { 140, 100, 20, 255 },
	.syn_function = { 30, 90, 190, 255 },
	.syn_constant = { 160, 90, 20, 255 },
	.syn_operator = { 20, 120, 140, 255 },
	.syn_punctuation = { 110, 115, 130, 255 },
	.syn_attribute = { 140, 100, 20, 255 },
	.syn_module = { 140, 100, 20, 255 },
	.syn_label = { 30, 90, 190, 255 },
	.syn_boolean = { 160, 90, 20, 255 },
	.syn_character = { 30, 120, 60, 255 },
	.syn_escape = { 20, 120, 140, 255 },
	.syn_parameter = { 140, 90, 60, 255 },
	.syn_property = { 190, 60, 70, 255 },
	.syn_builtin = { 20, 120, 140, 255 },
};

const ThemeSpec DRACULA = {
	.name = "dracula",
	.label = "Dracula",
	.light = false,
	.bg = { 40, 42, 54, 255 },
	.fg = { 248, 248, 242, 255 },
	.surface = { 52, 55, 70, 255 },
	.surface_alt = { 68, 71, 90, 255 },
	.border = { 98, 114, 164, 255 },
	.accent = { 189, 147, 249, 255 },
	.muted = { 98, 114, 164, 255 },
	.error = { 255, 85, 85, 255 },
	.warning = { 241, 250, 140, 255 },
	.info = { 139, 233, 253, 255 },
	.hint = { 98, 114, 164, 255 },
	.syn_keyword = { 255, 121, 198, 255 },
	.syn_string = { 241, 250, 140, 255 },
	.syn_comment = { 98, 114, 164, 255 },
	.syn_number = { 189, 147, 249, 255 },
	.syn_type = { 139, 233, 253, 255 },
	.syn_function = { 80, 250, 123, 255 },
	.syn_constant = { 189, 147, 249, 255 },
	.syn_operator = { 255, 121, 198, 255 },
	.syn_punctuation = { 248, 248, 242, 255 },
	.syn_attribute = { 80, 250, 123, 255 },
	.syn_module = { 139, 233, 253, 255 },
	.syn_label = { 80, 250, 123, 255 },
	.syn_boolean = { 189, 147, 249, 255 },
	.syn_character = { 241, 250, 140, 255 },
	.syn_escape = { 255, 121, 198, 255 },
	.syn_parameter = { 255, 184, 108, 255 },
	.syn_property = { 139, 233, 253, 255 },
	.syn_builtin = { 139, 233, 253, 255 },
};

const ThemeSpec ONE_DARK = {
	.name = "one_dark",
	.label = "One Dark",
	.light = false,
	.bg = { 40, 44, 52, 255 },
	.fg = { 171, 178, 191, 255 },
	.surface = { 50, 54, 62, 255 },
	.surface_alt = { 60, 65, 74, 255 },
	.border = { 62, 68, 81, 255 },
	.accent = { 97, 175, 239, 255 },
	.muted = { 92, 99, 112, 255 },
	.error = { 224, 108, 117, 255 },
	.warning = { 229, 192, 123, 255 },
	.info = { 86, 182, 194, 255 },
	.hint = { 92, 99, 112, 255 },
	.syn_keyword = { 198, 120, 221, 255 },
	.syn_string = { 152, 195, 121, 255 },
	.syn_comment = { 92, 99, 112, 255 },
	.syn_number = { 209, 154, 102, 255 },
	.syn_type = { 229, 192, 123, 255 },
	.syn_function = { 97, 175, 239, 255 },
	.syn_constant = { 209, 154, 102, 255 },
	.syn_operator = { 86, 182, 194, 255 },
	.syn_punctuation = { 171, 178, 191, 255 },
	.syn_attribute = { 229, 192, 123, 255 },
	.syn_module = { 229, 192, 123, 255 },
	.syn_label = { 97, 175, 239, 255 },
	.syn_boolean = { 209, 154, 102, 255 },
	.syn_character = { 152, 195, 121, 255 },
	.syn_escape = { 86, 182, 194, 255 },
	.syn_parameter = { 220, 190, 160, 255 },
	.syn_property = { 224, 108, 117, 255 },
	.syn_builtin = { 86, 182, 194, 255 },
};

const ThemeSpec GRUVBOX_DARK = {
	.name = "gruvbox_dark",
	.label = "Gruvbox Dark",
	.light = false,
	.bg = { 40, 40, 40, 255 },
	.fg = { 235, 219, 178, 255 },
	.surface = { 60, 56, 54, 255 },
	.surface_alt = { 80, 73, 69, 255 },
	.border = { 102, 92, 84, 255 },
	.accent = { 131, 165, 152, 255 },
	.muted = { 146, 131, 116, 255 },
	.error = { 251, 73, 52, 255 },
	.warning = { 250, 189, 47, 255 },
	.info = { 131, 165, 152, 255 },
	.hint = { 146, 131, 116, 255 },
	.syn_keyword = { 251, 73, 52, 255 },
	.syn_string = { 184, 187, 38, 255 },
	.syn_comment = { 146, 131, 116, 255 },
	.syn_number = { 211, 134, 155, 255 },
	.syn_type = { 250, 189, 47, 255 },
	.syn_function = { 184, 187, 38, 255 },
	.syn_constant = { 211, 134, 155, 255 },
	.syn_operator = { 142, 192, 124, 255 },
	.syn_punctuation = { 235, 219, 178, 255 },
	.syn_attribute = { 142, 192, 124, 255 },
	.syn_module = { 250, 189, 47, 255 },
	.syn_label = { 184, 187, 38, 255 },
	.syn_boolean = { 211, 134, 155, 255 },
	.syn_character = { 184, 187, 38, 255 },
	.syn_escape = { 254, 128, 25, 255 },
	.syn_parameter = { 235, 219, 178, 255 },
	.syn_property = { 131, 165, 152, 255 },
	.syn_builtin = { 142, 192, 124, 255 },
};

const ThemeSpec GRUVBOX_LIGHT = {
	.name = "gruvbox_light",
	.label = "Gruvbox Light",
	.light = true,
	.bg = { 251, 241, 199, 255 },
	.fg = { 60, 56, 54, 255 },
	.surface = { 242, 229, 188, 255 },
	.surface_alt = { 235, 219, 178, 255 },
	.border = { 213, 196, 161, 255 },
	.accent = { 7, 102, 120, 255 },
	.muted = { 146, 131, 116, 255 },
	.error = { 157, 0, 6, 255 },
	.warning = { 181, 118, 20, 255 },
	.info = { 7, 102, 120, 255 },
	.hint = { 146, 131, 116, 255 },
	.syn_keyword = { 157, 0, 6, 255 },
	.syn_string = { 121, 116, 14, 255 },
	.syn_comment = { 146, 131, 116, 255 },
	.syn_number = { 143, 63, 113, 255 },
	.syn_type = { 181, 118, 20, 255 },
	.syn_function = { 121, 116, 14, 255 },
	.syn_constant = { 143, 63, 113, 255 },
	.syn_operator = { 66, 123, 88, 255 },
	.syn_punctuation = { 60, 56, 54, 255 },
	.syn_attribute = { 66, 123, 88, 255 },
	.syn_module = { 181, 118, 20, 255 },
	.syn_label = { 121, 116, 14, 255 },
	.syn_boolean = { 143, 63, 113, 255 },
	.syn_character = { 121, 116, 14, 255 },
	.syn_escape = { 175, 58, 3, 255 },
	.syn_parameter = { 60, 56, 54, 255 },
	.syn_property = { 7, 102, 120, 255 },
	.syn_builtin = { 66, 123, 88, 255 },
};

const ThemeSpec NORD = {
	.name = "nord",
	.label = "Nord",
	.light = false,
	.bg = { 46, 52, 64, 255 },
	.fg = { 216, 222, 233, 255 },
	.surface = { 59, 66, 82, 255 },
	.surface_alt = { 67, 76, 94, 255 },
	.border = { 76, 86, 106, 255 },
	.accent = { 136, 192, 208, 255 },
	.muted = { 129, 161, 193, 255 },
	.error = { 191, 97, 106, 255 },
	.warning = { 235, 203, 139, 255 },
	.info = { 136, 192, 208, 255 },
	.hint = { 129, 161, 193, 255 },
	.syn_keyword = { 180, 142, 173, 255 },
	.syn_string = { 163, 190, 140, 255 },
	.syn_comment = { 97, 110, 136, 255 },
	.syn_number = { 208, 135, 112, 255 },
	.syn_type = { 143, 188, 187, 255 },
	.syn_function = { 136, 192, 208, 255 },
	.syn_constant = { 208, 135, 112, 255 },
	.syn_operator = { 129, 161, 193, 255 },
	.syn_punctuation = { 216, 222, 233, 255 },
	.syn_attribute = { 143, 188, 187, 255 },
	.syn_module = { 143, 188, 187, 255 },
	.syn_label = { 136, 192, 208, 255 },
	.syn_boolean = { 208, 135, 112, 255 },
	.syn_character = { 163, 190, 140, 255 },
	.syn_escape = { 136, 192, 208, 255 },
	.syn_parameter = { 216, 222, 233, 255 },
	.syn_property = { 191, 97, 106, 255 },
	.syn_builtin = { 136, 192, 208, 255 },
};

const ThemeSpec CATPPUCCIN_MOCHA = {
	.name = "catppuccin_mocha",
	.label = "Catppuccin Mocha",
	.light = false,
	.bg = { 30, 30, 46, 255 },
	.fg = { 205, 214, 244, 255 },
	.surface = { 49, 50, 68, 255 },
	.surface_alt = { 69, 71, 90, 255 },
	.border = { 88, 91, 112, 255 },
	.accent = { 203, 166, 247, 255 },
	.muted = { 108, 112, 134, 255 },
	.error = { 243, 139, 168, 255 },
	.warning = { 249, 226, 175, 255 },
	.info = { 137, 180, 250, 255 },
	.hint = { 108, 112, 134, 255 },
	.syn_keyword = { 203, 166, 247, 255 },
	.syn_string = { 166, 227, 161, 255 },
	.syn_comment = { 108, 112, 134, 255 },
	.syn_number = { 250, 179, 135, 255 },
	.syn_type = { 249, 226, 175, 255 },
	.syn_function = { 137, 180, 250, 255 },
	.syn_constant = { 250, 179, 135, 255 },
	.syn_operator = { 148, 226, 213, 255 },
	.syn_punctuation = { 205, 214, 244, 255 },
	.syn_attribute = { 249, 226, 175, 255 },
	.syn_module = { 249, 226, 175, 255 },
	.syn_label = { 137, 180, 250, 255 },
	.syn_boolean = { 250, 179, 135, 255 },
	.syn_character = { 166, 227, 161, 255 },
	.syn_escape = { 148, 226, 213, 255 },
	.syn_parameter = { 242, 205, 205, 255 },
	.syn_property = { 245, 194, 231, 255 },
	.syn_builtin = { 148, 226, 213, 255 },
};

const ThemeSpec CATPPUCCIN_LATTE = {
	.name = "catppuccin_latte",
	.label = "Catppuccin Latte",
	.light = true,
	.bg = { 239, 241, 245, 255 },
	.fg = { 76, 79, 105, 255 },
	.surface = { 255, 255, 255, 255 },
	.surface_alt = { 230, 233, 239, 255 },
	.border = { 188, 192, 204, 255 },
	.accent = { 136, 57, 239, 255 },
	.muted = { 140, 143, 161, 255 },
	.error = { 210, 15, 57, 255 },
	.warning = { 223, 142, 29, 255 },
	.info = { 30, 102, 245, 255 },
	.hint = { 140, 143, 161, 255 },
	.syn_keyword = { 136, 57, 239, 255 },
	.syn_string = { 64, 160, 43, 255 },
	.syn_comment = { 140, 143, 161, 255 },
	.syn_number = { 254, 100, 11, 255 },
	.syn_type = { 223, 142, 29, 255 },
	.syn_function = { 30, 102, 245, 255 },
	.syn_constant = { 254, 100, 11, 255 },
	.syn_operator = { 4, 165, 229, 255 },
	.syn_punctuation = { 76, 79, 105, 255 },
	.syn_attribute = { 223, 142, 29, 255 },
	.syn_module = { 223, 142, 29, 255 },
	.syn_label = { 30, 102, 245, 255 },
	.syn_boolean = { 254, 100, 11, 255 },
	.syn_character = { 64, 160, 43, 255 },
	.syn_escape = { 4, 165, 229, 255 },
	.syn_parameter = { 92, 64, 55, 255 },
	.syn_property = { 234, 118, 203, 255 },
	.syn_builtin = { 4, 165, 229, 255 },
};

const ThemeSpec[] THEME_SPECS = {
	YUN_DARK,
	YUN_LIGHT,
	DRACULA,
	ONE_DARK,
	GRUVBOX_DARK,
	GRUVBOX_LIGHT,
	NORD,
	CATPPUCCIN_MOCHA,
	CATPPUCCIN_LATTE,
};

Theme active;
int active_index  = 0;
bool active_ready = false;

fn char lerp8(char a, char b, float t)
{
	float v = (float)a + ((float)b - (float)a) * t;
	if (v < 0.0f) v = 0.0f;
	if (v > 255.0f) v = 255.0f;
	return (char)v;
}

fn RLColor mix(RLColor a, RLColor b, float t)
{
	return { lerp8(a[0], b[0], t), lerp8(a[1], b[1], t), lerp8(a[2], b[2], t), a[3] };
}

fn RLColor with_alpha(RLColor c, char alpha)
{
	return { c[0], c[1], c[2], alpha };
}

fn Theme theme_build(ThemeSpec spec)
{
	Theme t;
	t.window_bg = spec.bg;
	t.grid_minor = mix(spec.bg, spec.fg, 0.08f);
	t.grid_major = mix(spec.bg, spec.fg, 0.16f);

	t.card_body = spec.surface;
	t.card_title = spec.surface_alt;
	t.card_border = spec.border;
	t.card_focus = spec.accent;
	t.card_text = spec.fg;
	t.card_dirty = spec.warning;

	t.cluster_body = with_alpha(spec.surface, 200);
	t.cluster_border = spec.border;
	t.cluster_title = spec.surface_alt;
	t.cluster_text = mix(spec.fg, spec.accent, 0.45f);

	t.editor_text = spec.fg;
	t.editor_placeholder = mix(spec.bg, spec.fg, 0.30f);
	t.editor_caret = spec.fg;
	t.editor_gutter_bg = mix(spec.bg, spec.surface, 0.5f);
	t.editor_gutter_text = mix(spec.bg, spec.fg, 0.45f);
	t.editor_current_line = with_alpha(spec.fg, 18);
	t.editor_scrollbar = with_alpha(mix(spec.surface, spec.fg, 0.35f), 200);
	t.editor_handle = with_alpha(spec.accent, 220);
	t.editor_match = with_alpha(mix(spec.surface, spec.accent, 0.5f), 200);
	t.editor_match_current = with_alpha(spec.warning, 220);
	t.editor_selection = with_alpha(spec.accent, 90);

	t.diag_error = spec.error;
	t.diag_warning = spec.warning;
	t.diag_info = spec.info;
	t.diag_hint = spec.hint;

	t.import_solid = with_alpha(spec.accent, 220);
	t.import_external = with_alpha(spec.muted, 200);
	t.import_label = spec.muted;
	t.import_solid_dim = with_alpha(spec.accent, 45);
	t.import_external_dim = with_alpha(spec.muted, 40);
	t.import_label_dim = with_alpha(spec.muted, 80);
	t.import_solid_hover = mix(spec.accent, spec.fg, 0.4f);
	t.import_external_hover = mix(spec.muted, spec.fg, 0.4f);

	t.topbar_bg = spec.surface_alt;
	t.topbar_border = spec.border;
	t.topbar_button = spec.surface;
	t.topbar_hover = mix(spec.surface, spec.fg, 0.12f);
	t.topbar_text = spec.fg;
	t.topbar_disabled = spec.muted;
	t.topbar_name = mix(spec.fg, spec.accent, 0.45f);
	t.topbar_error = spec.error;
	t.topbar_warning = spec.warning;

	t.minimap_bg = with_alpha(spec.bg, 230);
	t.minimap_border = spec.border;
	t.minimap_cluster = with_alpha(spec.accent, 160);
	t.minimap_card = mix(spec.fg, spec.accent, 0.45f);
	t.minimap_viewport = spec.fg;

	t.notice_bg = with_alpha(spec.bg, 200);
	t.notice_text = spec.fg;

	t.loading_scrim = { 0, 0, 0, 120 };
	t.loading_panel = spec.surface;
	t.loading_border = spec.border;
	t.loading_title = mix(spec.fg, spec.accent, 0.2f);
	t.loading_status = spec.muted;
	t.loading_hint = mix(spec.bg, spec.fg, 0.35f);

	t.panel_bg = spec.surface;
	t.panel_bg_alt = mix(spec.surface, spec.bg, 0.4f);
	t.panel_border = spec.border;
	t.panel_text = spec.fg;
	t.panel_dim = spec.muted;
	t.panel_disabled = mix(spec.bg, spec.fg, 0.5f);
	t.panel_selected = with_alpha(spec.accent, 200);
	t.panel_field = mix(spec.bg, spec.surface, 0.3f);
	t.panel_caret = spec.fg;
	t.panel_match = spec.warning;
	t.panel_header = mix(spec.fg, spec.accent, 0.45f);
	t.findbar_chip = mix(spec.surface, spec.fg, 0.1f);
	t.hover_code = spec.syn_string;
	t.hover_code_bg = mix(spec.surface, spec.bg, 0.5f);
	t.hover_heading = spec.syn_type;

	t.syn_keyword = spec.syn_keyword;
	t.syn_string = spec.syn_string;
	t.syn_comment = spec.syn_comment;
	t.syn_number = spec.syn_number;
	t.syn_type = spec.syn_type;
	t.syn_function = spec.syn_function;
	t.syn_constant = spec.syn_constant;
	t.syn_operator = spec.syn_operator;
	t.syn_punctuation = spec.syn_punctuation;
	t.syn_attribute = spec.syn_attribute;
	t.syn_module = spec.syn_module;
	t.syn_label = spec.syn_label;
	t.syn_boolean = spec.syn_boolean;
	t.syn_character = spec.syn_character;
	t.syn_escape = spec.syn_escape;
	t.syn_parameter = spec.syn_parameter;
	t.syn_property = spec.syn_property;
	t.syn_builtin = spec.syn_builtin;
	return t;
}

fn void init()
{
	if (active_ready) return;
	set_index(0);
}

fn Theme* current()
{
	if (!active_ready) init();
	return &active;
}

fn int count()
{
	return (int)THEME_SPECS.len;
}

fn int index_of(String name)
{
	for (int i = 0; i < count(); i++)
	{
		if (THEME_SPECS[(sz)i].name.compare_to(name) == 0) return i;
	}
	return -1;
}

fn int index_by_name(String name)
{
	int found = index_of(name);
	if (found >= 0) return found;
	if (name.compare_to("dark") == 0) return index_of("yun_dark");
	if (name.compare_to("light") == 0) return index_of("yun_light");
	return -1;
}

fn String name(int index)
{
	if (index < 0 || index >= count()) index = 0;
	return THEME_SPECS[(sz)index].name;
}

fn String label(int index)
{
	if (index < 0 || index >= count()) index = 0;
	return THEME_SPECS[(sz)index].label;
}

fn void set_index(int index)
{
	if (index < 0 || index >= count()) index = 0;
	active = theme_build(THEME_SPECS[(sz)index]);
	active_index = index;
	active_ready = true;
}

fn bool set_by_name(String name)
{
	int found = index_by_name(name);
	if (found < 0) return false;
	set_index(found);
	return true;
}

fn void next()
{
	set_index((active_index + 1) % count());
}

fn void prev()
{
	set_index((active_index + count() - 1) % count());
}

fn int index()
{
	return active_index;
}

fn String current_name()
{
	return name(active_index);
}

fn String current_label()
{
	return label(active_index);
}