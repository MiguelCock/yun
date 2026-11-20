module yun::connections;

import raylib6::rl;
import std::collections::list;
import std::core::mem::alloc;
import std::math;
import yun::card;
import yun::editor;
import yun::imports;
import yun::project;
import yun::theme;
import yun::topbar;
import yun::ui;

const float PANEL_WIDTH   = 360.0f;
const float PANEL_MARGIN  = 12.0f;
const float HEADER_HEIGHT = 34.0f;
const float ROW_HEIGHT    = 44.0f;

struct ConnectionRow
{
	bool incoming;
	String path;
	String other;
	String specifier;
	String kind;
	usz line;
	usz column;
	bool resolved;
}

struct ConnectionTarget
{
	bool valid;
	String path;
	usz line;
	usz column;
}

struct Connections
{
	Allocator allocator;
	bool open;
	int scroll;
	int selected;
	int hover;
	List{ConnectionRow} rows;
	int last_focus;
	bool last_hover;
	int last_hover_source;
	usz last_hover_ref;
	usz last_files;
	usz last_received;
}

fn void Connections.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.open = false;
	self.scroll = 0;
	self.selected = 0;
	self.hover = -1;
	self.rows.init(allocator);
	self.last_focus = -2;
	self.last_hover = false;
	self.last_hover_source = -1;
	self.last_hover_ref = 0;
	self.last_files = 0;
	self.last_received = 0;
}

fn void Connections.destroy(&self)
{
	self.rows.free();
}

fn void Connections.show(&self)
{
	self.open = true;
	self.refresh_pending();
}

fn void Connections.close(&self)
{
	self.open = false;
	self.hover = -1;
}

fn void Connections.refresh_pending(&self)
{
	self.last_focus = -2;
	self.last_files = 0;
	self.last_received = 0;
}

fn String file_name_view(String path)
{
	usz cut = path.len;
	while (cut > 0)
	{
		cut--;
		if (path[cut] == '/' || path[cut] == '\\') return path[cut + 1:path.len - cut - 1];
	}
	return path;
}

fn usz next_utf8(String text, usz i)
{
	i++;
	while (i < text.len && ((int)text[i] & 0xC0) == 0x80) i++;
	return i;
}

fn String elide(RLFont font, String text, float size, float max_width)
{
	if (text.len == 0 || max_width <= 0.0f) return "";
	if (rl::measure_text_ex(font, (ZString)text.ptr, size, 0.0f)[0] <= max_width) return text;

	String ellipsis      = "...";
	float ellipsis_width = rl::measure_text_ex(font, (ZString)ellipsis.ptr, size, 0.0f)[0];
	if (max_width <= ellipsis_width) return "";

	usz end       = 0;
	usz last_good = 0;
	while (end < text.len)
	{
		end = next_utf8(text, end);
		String prefix = text[0:end];
		if (rl::measure_text_ex(font, (ZString)prefix.ptr, size, 0.0f)[0] + ellipsis_width > max_width) break;
		last_good = end;
	}
	if (last_good == 0) return "";
	return string::format(tmem, "%s...", text[0:last_good]);
}

fn Rect Connections.panel_rect(&self)
{
	float margin = ui::pxf(PANEL_MARGIN);
	float width  = ui::pxf(PANEL_WIDTH);
	float x      = (float)rl::get_screen_width() - width - margin;
	float y      = ui::pxf(topbar::TOP_BAR_HEIGHT) + margin;
	return {
		.x = x,
		.y = y,
		.width = width,
		.height = (float)rl::get_screen_height() - y - margin,
	};
}

fn bool rect_contains(Rect r, RLVector2 p)
{
	return p[0] >= r.x && p[0] <= r.x + r.width && p[1] >= r.y && p[1] <= r.y + r.height;
}

fn bool Connections.contains_screen(&self, RLVector2 screen)
{
	return self.open && rect_contains(self.panel_rect(), screen);
}

fn void Connections.add_row(&self, bool incoming, String path, String other, ImportRef ref)
{
	self.rows.push(
		{
			.incoming = incoming,
			.path = path,
			.other = other,
			.specifier = ref.specifier,
			.kind = ref.kind,
			.line = ref.line,
			.column = ref.column,
			.resolved = ref.resolved,
		}
	);
}

fn void Connections.refresh(&self, project::Project* project, imports::ImportIndex* index)
{
	if (!self.open) return;

	bool hover = index.hover.valid;
	int focus  = project.focused >= 0 ? project.focused : project.selected;
	if (self.last_focus == focus && self.last_hover == hover && self.last_hover_source == index.hover.source
		&& self.last_hover_ref == index.hover.ref_index
		&& self.last_files == (usz)index.files.len()
		&& self.last_received == index.received) return;

	self.last_focus = focus;
	self.last_hover = hover;
	self.last_hover_source = index.hover.source;
	self.last_hover_ref = index.hover.ref_index;
	self.last_files = (usz)index.files.len();
	self.last_received = index.received;
	self.rows.clear();

	if (hover && index.hover.source >= 0 && index.hover.source < (int)index.files.len())
	{
		CardImports file = index.files[index.hover.source];
		if (index.hover.ref_index < (usz)file.imports.len())
		{
			ImportRef ref = file.imports[(sz)index.hover.ref_index];
			self.add_row(false, file.path, ref.target_path, ref);
		}
	}
	else if (focus >= 0 && focus < (int)project.cards.len())
	{
		FileCard* card   = &project.cards[focus];
		String path      = (String)card.path;
		ImportRef[] refs = index.imports_for(path);
		for (usz i = 0; i < refs.len; i++)
		{
			ImportRef ref = refs[i];
			self.add_row(false, path, ref.target_path, ref);
		}

		@pool()
		{
			List{ImporterRef} importers;
			importers.init(tmem);
			index.importers_of(path, &importers);
			foreach (ImporterRef importer : importers)
			{
				if (importer.file < 0 || importer.file >= (int)index.files.len()) continue;
				CardImports file = index.files[importer.file];
				if (importer.ref >= (usz)file.imports.len()) continue;
				ImportRef ref = file.imports[(sz)importer.ref];
				self.add_row(true, file.path, path, ref);
			}
		};
	}

	self.clamp();
}

fn int Connections.visible_rows(&self)
{
	float scale = ui::scale();
	float list  = (float)rl::get_screen_height() - ui::pxf(
		topbar::TOP_BAR_HEIGHT
	) - ui::pxf(PANEL_MARGIN) * 2.0f - HEADER_HEIGHT * scale;
	int rows    = (int)(list / (ROW_HEIGHT * scale));
	return rows > 0 ? rows : 1;
}

fn void Connections.clamp(&self)
{
	int count = (int)self.rows.len();
	if (count == 0)
	{
		self.selected = 0;
		self.scroll = 0;
		return;
	}
	if (self.selected < 0) self.selected = 0;
	if (self.selected >= count) self.selected = count - 1;

	int visible    = self.visible_rows();
	int max_scroll = count - visible;
	if (max_scroll < 0) max_scroll = 0;
	if (self.selected < self.scroll) self.scroll = self.selected;
	if (self.selected >= self.scroll + visible) self.scroll = self.selected - visible + 1;
	if (self.scroll > max_scroll) self.scroll = max_scroll;
	if (self.scroll < 0) self.scroll = 0;
}

fn int Connections.row_at(&self, RLVector2 mouse)
{
	Rect panel   = self.panel_rect();
	float scale  = ui::scale();
	float list_y = panel.y + HEADER_HEIGHT * scale;
	float row_h  = ROW_HEIGHT * scale;
	if (mouse[1] < list_y) return -1;
	int slot = (int)((mouse[1] - list_y) / row_h);
	int row  = self.scroll + slot;
	return row >= 0 && row < (int)self.rows.len() ? row : -1;
}

fn ConnectionTarget Connections.update_input(&self, project::Project* project, imports::ImportIndex* index)
{
	ConnectionTarget target = { .valid = false };
	if (!self.open) return target;

	self.refresh(project, index);
	RLVector2 mouse = rl::get_mouse_position();
	if (!self.contains_screen(mouse))
	{
		self.hover = -1;
		return target;
	}

	float wheel = rl::get_mouse_wheel_move();
	if (wheel != 0.0f) self.scroll -= (int)wheel;
	int row = self.row_at(mouse);
	self.hover = row;
	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT) && row >= 0)
	{
		self.selected = row;
		ConnectionRow hit = self.rows[row];
		target.valid = true;
		target.path = hit.path;
		target.line = hit.line;
		target.column = hit.column;
	}
	self.clamp();
	return target;
}

fn void draw_text(RLFont font, String text, float x, float y, float size, RLColor color)
{
	if (text.len == 0) return;
	rl::draw_text_ex(font, text.zstr_tcopy(), { x, y }, size, 0.0f, color);
}

fn void Connections.draw(&self, RLFont font, project::Project* project, imports::ImportIndex* index)
{
	if (!self.open) return;
	self.refresh(project, index);

	float scale = ui::scale();
	float text  = ui::text_scale();
	Rect panel  = self.panel_rect();
	ui::panel(panel, theme::current().panel_bg, theme::current().panel_border);

	@pool()
	{
		String title = string::format(tmem, "Connections (%d)", (long)self.rows.len());
		draw_text(font, title, panel.x + (float)ui::px(12), panel.y + (float)ui::px(9), 18.0f * text, theme::current()
			.panel_text);
	};

	float list_y = panel.y + HEADER_HEIGHT * scale;
	if (self.rows.len() == 0)
	{
		draw_text(
			font,
			"No connections",
			panel.x + (float)ui::px(12),
			list_y + (float)ui::px(6),
			16.0f * text,
			theme::current()
			.panel_dim);
		return;
	}

	float row_h = ROW_HEIGHT * scale;
	int visible = self.visible_rows();
	int shown   = (int)self.rows.len() - self.scroll;
	if (shown > visible) shown = visible;
	rl::begin_scissor_mode((int)panel.x + 2, (int)list_y, (int)panel.width - 4, (int)((float)shown * row_h));
	for (int slot = 0; slot < visible; slot++)
	{
		int row_index = self.scroll + slot;
		if (row_index >= (int)self.rows.len()) break;
		ConnectionRow row = self.rows[row_index];
		float y           = list_y + (float)slot * row_h;
		if (row_index == self.selected)
		{
			ui::row(
				{
					.x = panel.x + 2.0f,
					.y = y,
					.width = panel.width - 4.0f,
					.height = row_h,
				},
				theme::current()
				.panel_selected);
		}
		else if (row_index == self.hover)
		{
			ui::row(
				{
					.x = panel.x + 2.0f,
					.y = y,
					.width = panel.width - 4.0f,
					.height = row_h,
				},
				theme::current()
				.panel_bg_alt);
		}

		float x     = panel.x + (float)ui::px(12);
		float max_x = panel.x + panel.width - (float)ui::px(12);
		@pool()
		{
			String arrow = row.incoming ? "<" : ">";
			String first = row.other.len > 0 ? string::format(
				tmem,
				"%s %s -> %s",
				arrow,
				file_name_view(row.path),
				file_name_view(row.other)
			)
				: string::format(tmem, "%s %s", arrow, file_name_view(row.path));
			draw_text(
				font,
				elide(font, first, 16.0f * text, max_x - x),
				x,
				y + (float)ui::px(5),
				16.0f * text,
				theme::current()
				.panel_text);

			String kind = row.kind.len > 0 ? row.kind : "import";
			String meta = string::format(
				tmem,
				"%s  %d:%d%s",
				kind,
				(long)(row.line + 1),
				(long)(row.column + 1),
				row.resolved ? "" : "  external"
			);
			draw_text(
				font,
				elide(font, meta, 14.0f * text, max_x - x),
				x,
				y + (float)ui::px(23),
				14.0f * text,
				theme::current()
				.panel_dim);
		};
	}
	rl::end_scissor_mode();
}