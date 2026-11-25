module yun::connections;

import raylib6::rl;
import std::collections::list;
import std::core::mem::alloc;
import std::math;
import yun::card;
import yun::connection_details;
import yun::editor;
import yun::imports;
import yun::project;
import yun::symbols;
import yun::icons;
import yun::theme;
import yun::topbar;
import yun::ui;

const float PANEL_WIDTH   = 680.0f;
const float LIST_WIDTH    = 300.0f;
const float PANEL_MARGIN  = 12.0f;
const float HEADER_HEIGHT = 34.0f;
const float ROW_HEIGHT    = 44.0f;
const float DETAIL_ROW    = 22.0f;
const float USAGE_ROW     = 18.0f;

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

struct ConnectionHit
{
	Rect rect;
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
	ui::Motion motion;
	int last_hover_source;
	usz last_hover_ref;
	usz last_files;
	usz last_received;
	connection_details::Details details;
	int detail_row;
	int detail_scroll;
	List{ConnectionHit} hits;
	bool detail_dirty;
	usz detail_received;
	usz detail_length;
	bool select_resolved;
}

fn void Connections.init(&self, Allocator allocator)
{
	self.allocator = allocator;
	self.open = false;
	self.scroll = 0;
	self.selected = 0;
	self.hover = -1;
	self.rows.init(allocator);
	self.details.init(allocator);
	self.hits.init(allocator);
	self.detail_row = -1;
	self.detail_scroll = 0;
	self.detail_dirty = true;
	self.detail_received = 0;
	self.detail_length = 0;
	self.select_resolved = false;
	self.last_focus = -2;
	self.last_hover = false;
	self.last_hover_source = -1;
	self.last_hover_ref = 0;
	self.last_files = 0;
	self.last_received = 0;
}

fn void Connections.destroy(&self)
{
	self.details.destroy(self.allocator);
	self.hits.free();
	self.rows.free();
}

fn void Connections.show(&self)
{
	self.open = true;
	self.select_resolved = true;
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
	Rect content = topbar::content_rect();
	float margin = ui::pxf(PANEL_MARGIN);
	float width  = ui::pxf(PANEL_WIDTH);
	return {
		.x = content.x + content.width - width - margin,
		.y = content.y + margin,
		.width = width,
		.height = content.height - margin * 2.0f,
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

fn void Connections.ensure_details(&self, project::Project* project, symbols::Symbols* symbols)
{
	if (!self.open || self.selected < 0 || self.selected >= (int)self.rows.len())
	{
		if (self.detail_row != -1)
		{
			self.details.clear(self.allocator);
			self.hits.clear();
			self.detail_row = -1;
		}
		return;
	}
	if (!self.detail_dirty && self.detail_row == self.selected)
	{
		ConnectionRow current = self.rows[self.selected];
		usz length            = 0;
		int card              = project.find_card(current.path);
		if (card >= 0 && project.cards[card].buffer) length = project.cards[card].buffer.length();
		bool indexed_now     = current.resolved && self.details.indexed;
		bool symbols_arrived = !indexed_now && symbols.received != self.detail_received;
		if (length == self.detail_length && !symbols_arrived) return;
	}
	symbols.ensure_index(project);
	ConnectionRow row       = self.rows[self.selected];
	symbols::Symbols* index = symbols;
	usz card_length         = 0;
	int card_index          = project.find_card(row.path);
	if (card_index >= 0 && project.cards[card_index].buffer)
	{
		card_length = project.cards[card_index].buffer.length();
	}
	self.details.clear(self.allocator);
	self.hits.clear();
	self.detail_row = self.selected;
	self.detail_scroll = 0;
	self.detail_dirty = false;
	self.detail_received = index.received;
	self.detail_length = card_length;
	String target = row.resolved ? row.other : "";
	self.details.build(self.allocator, project, index, row.path, target, row.line);
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
	self.details.clear(self.allocator);
	self.hits.clear();
	self.detail_row = -1;
	self.detail_scroll = 0;
	self.detail_dirty = true;
	self.detail_received = 0;
	self.detail_length = 0;

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

	if (self.select_resolved)
	{
		for (sz i = 0; i < self.rows.len(); i++)
		{
			if (self.rows.get(i).resolved)
			{
				self.selected = (int)i;
				break;
			}
		}
		self.select_resolved = false;
	}
	self.clamp();
}

fn int Connections.visible_rows(&self)
{
	float scale = ui::scale();
	float list  = self.panel_rect().height - HEADER_HEIGHT * scale;
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
	if (mouse[0] > panel.x + LIST_WIDTH * scale) return -1;
	if (mouse[1] < list_y) return -1;
	int slot = (int)((mouse[1] - list_y) / row_h);
	int row  = self.scroll + slot;
	return row >= 0 && row < (int)self.rows.len() ? row : -1;
}

fn ConnectionTarget Connections.update_input(
	&self,
	project::Project* project,
	imports::ImportIndex* index,
	symbols::Symbols* symbols
)
{
	ConnectionTarget target = { .valid = false };
	if (!self.open) return target;

	self.refresh(project, index);
	self.ensure_details(project, symbols);
	RLVector2 mouse = rl::get_mouse_position();
	if (!self.contains_screen(mouse))
	{
		self.hover = -1;
		return target;
	}

	float wheel = rl::get_mouse_wheel_move();
	if (wheel != 0.0f)
	{
		if (mouse[0] > self.panel_rect().x + LIST_WIDTH * ui::scale())
		{
			self.detail_scroll -= (int)wheel;
		}
		else
		{
			self.scroll -= (int)wheel;
		}
	}
	for (sz i = 0; i < self.hits.len(); i++)
	{
		ConnectionHit hit = self.hits[i];
		if (!rect_contains(hit.rect, mouse)) continue;
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT))
		{
			target.valid = true;
			target.path = hit.path;
			target.line = hit.line;
			target.column = hit.column;
			return target;
		}
		ui::request_cursor(rl::RLMouseCursor.POINTING_HAND, 5);
		break;
	}

	int row = self.row_at(mouse);
	self.hover = row;
	if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT) && row >= 0)
	{
		if (self.selected != row) self.detail_dirty = true;
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

fn void Connections.draw(
	&self,
	RLFont font,
	project::Project* project,
	imports::ImportIndex* index,
	symbols::Symbols* symbols
)
{
	if (!self.open)
	{
		self.motion.update(false);
		return;
	}
	self.motion.update(true);
	self.refresh(project, index);
	self.ensure_details(project, symbols);

	float scale = ui::scale();
	float text  = ui::text_scale();
	Rect panel  = self.panel_rect();
	panel.x += self.motion.offset(ui::pxf(12.0f));
	ui::floating_panel(panel, theme::current().panel_bg, theme::current().panel_border);
	self.hits.clear();

	float list_w  = LIST_WIDTH * scale;
	float icon_px = icons::icon_size(18);
	icons::draw(
		icons::IconKind.CONNECTIONS,
		{ .x = panel.x + (float)ui::px(12), .y = panel.y + (float)ui::px(9), .width = icon_px, .height = icon_px },
		theme::current()
		.panel_header);
	@pool()
	{
		String title = string::format(tmem, "Connections (%d)", (long)self.rows.len());
		draw_text(
			font,
			title,
			panel.x + (float)ui::px(12) + icon_px + (float)ui::px(6),
			panel.y + (float)ui::px(9),
			18.0f * text,
			theme::current()
			.panel_text);
	};

	float list_y = panel.y + HEADER_HEIGHT * scale;
	ui::separator_h({ .x = panel.x + 2.0f, .y = list_y - 1.0f, .width = panel.width - 4.0f, .height = 1.0f });
	ui::separator_v({ .x = panel.x + list_w, .y = list_y, .width = 1.0f, .height = panel.y + panel.height - list_y });
	if (self.rows.len() == 0)
	{
		ui::empty_state(
			font,
			{
				.x = panel.x + 2.0f,
				.y = list_y,
				.width = list_w - 4.0f,
				.height = panel.height - HEADER_HEIGHT * scale
			},
			"No connections",
			"Open imports from a card or hover an arrow"
		);
		return;
	}

	float row_h = ROW_HEIGHT * scale;
	int visible = self.visible_rows();
	int shown   = (int)self.rows.len() - self.scroll;
	if (shown > visible) shown = visible;
	rl::begin_scissor_mode((int)panel.x + 2, (int)list_y, (int)list_w - 4, (int)((float)shown * row_h));
	for (int slot = 0; slot < visible; slot++)
	{
		int row_index = self.scroll + slot;
		if (row_index >= (int)self.rows.len()) break;
		ConnectionRow row = self.rows[row_index];
		float y           = list_y + (float)slot * row_h;
		if (row_index == self.selected)
		{
			ui::row({ .x = panel.x + 2.0f, .y = y, .width = list_w - 4.0f, .height = row_h }, theme::current()
				.panel_selected);
		}
		else if (row_index == self.hover)
		{
			ui::row(
				{ .x = panel.x + 2.0f, .y = y, .width = list_w - 4.0f, .height = row_h },
				rl::is_mouse_button_down(rl::RLMouseButton.LEFT) ? theme::current()
				.panel_selected : theme::current().panel_bg_alt);
		}

		float x     = panel.x + (float)ui::px(12);
		float max_x = panel.x + list_w - (float)ui::px(10);
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
	if ((int)self.rows.len() > visible)
	{
		Rect track = {
			.x = panel.x + list_w - (float)ui::px(5),
			.y = list_y + 2.0f,
			.width = (float)ui::px(3),
			.height = panel.y + panel.height - list_y - 4.0f,
		};
		ui::draw_scrollbar(track, (float)self.rows.len(), (float)visible, (float)self.scroll, false, theme::current()
			.editor_scrollbar, theme::current().panel_dim, theme::current().panel_text);
	}

	float detail_x    = panel.x + list_w + (float)ui::px(8);
	float detail_w    = panel.width - list_w - (float)ui::px(16);
	float detail_y    = list_y + (float)ui::px(8);
	ConnectionRow row = self.rows[self.selected];
	@pool()
	{
		String specifier = row.specifier.len > 0 ? row.specifier : "(module)";
		String header    = string::format(tmem, "%s  %s:%d", specifier, file_name_view(row.path), (long)(row.line + 1));
		draw_text(font, elide(font, header, 15.0f * text, detail_w), detail_x, detail_y, 15.0f * text, theme::current()
			.panel_text);
		String path_line = row.resolved ? string::format(tmem, "-> %s", file_name_view(row.other))
			: "external / unresolved";
		draw_text(
			font,
			elide(font, path_line, 13.0f * text, detail_w),
			detail_x,
			detail_y + (float)ui::px(20),
			13.0f * text,
			theme::current()
			.panel_dim);
	};

	@pool()
	{
		String scope        = self.details.named ? "named imports" : "module import";
		String symbols_word = self.details.symbols.len() == 1 ? "symbol" : "symbols";
		String usages_word  = self.details.total_usages == 1 ? "usage" : "usages";
		String summary = string::format(
			tmem,
			"%s  -  %d %s, %d %s",
			scope,
			(long)self.details.symbols.len(),
			symbols_word,
			(long)self.details.total_usages,
			usages_word
		);
		draw_text(
			font,
			elide(font, summary, 12.0f * text, detail_w),
			detail_x,
			detail_y + (float)ui::px(38),
			12.0f * text,
			theme::current()
			.panel_dim);
	};

	float symbols_y   = detail_y + (float)ui::px(58);
	float available_h = panel.y + panel.height - symbols_y - (float)ui::px(8);
	if (self.details.symbols.len() == 0)
	{
		if (row.resolved && symbols.scanning)
		{
			ui::empty_state(
				font,
				{ .x = detail_x, .y = symbols_y, .width = detail_w, .height = available_h },
				"Scanning symbols",
				"The target file is being indexed"
			);
		}
		else if (!row.resolved)
		{
			ui::empty_state(
				font,
				{ .x = detail_x, .y = symbols_y, .width = detail_w, .height = available_h },
				"External import",
				"No named symbols and no target file in the project"
			);
		}
		else if (self.details.indexed)
		{
			ui::empty_state(
				font,
				{ .x = detail_x, .y = symbols_y, .width = detail_w, .height = available_h },
				"No used symbols",
				"None of the target symbols are referenced here"
			);
		}
		else
		{
			ui::empty_state(
				font,
				{ .x = detail_x, .y = symbols_y, .width = detail_w, .height = available_h },
				"No symbols indexed",
				"The target file has no indexed symbols"
			);
		}
		return;
	}

	float content_h = 0.0f;
	for (sz i = 0; i < self.details.symbols.len(); i++)
	{
		content_h += DETAIL_ROW * scale;
		content_h += (float)self.details.symbols[i].usages.len() * USAGE_ROW * scale;
	}
	int max_detail_scroll = (int)((content_h - available_h) / (USAGE_ROW * scale));
	if (max_detail_scroll < 0) max_detail_scroll = 0;
	if (self.detail_scroll < 0) self.detail_scroll = 0;
	if (self.detail_scroll > max_detail_scroll) self.detail_scroll = max_detail_scroll;

	rl::begin_scissor_mode((int)detail_x, (int)symbols_y, (int)detail_w, (int)available_h);
	float y = symbols_y - (float)self.detail_scroll * USAGE_ROW * scale;
	for (sz i = 0; i < self.details.symbols.len(); i++)
	{
		connection_details::DetailSymbol symbol = self.details.symbols[i];
		Rect def_rect;
		def_rect.x = detail_x;
		def_rect.y = y;
		def_rect.width = detail_w - (float)ui::px(4);
		def_rect.height = DETAIL_ROW * scale;
		if (y + DETAIL_ROW * scale >= symbols_y && y <= symbols_y + available_h)
		{
			@pool()
			{
				String name  = symbol.alias_name.len > 0 ? string::format(
					tmem,
					"%s as %s",
					symbol.name,
					symbol.alias_name
				)
					: symbol.name;
				String uses  = symbol.usages.len() == 1 ? "use" : "uses";
				String label = symbol.has_target ? string::format(
					tmem,
					"%s  %s  %d:%d  (%d %s)",
					symbol.kind,
					name,
					(long)(symbol.line + 1),
					(long)(symbol.column + 1),
					(long)symbol.usages.len(),
					uses
				)
					: string::format(tmem, "%s  %s  (%d %s)", symbol.kind, name, (long)symbol.usages.len(), uses);
				draw_text(
					font,
					elide(font, label, 13.0f * text, detail_w - (float)ui::px(8)),
					detail_x,
					y + 3.0f,
					13.0f * text,
					theme::current()
					.panel_text);
			};
			if (symbol.has_target && row.other.len > 0)
			{
				self.hits.push({ .rect = def_rect, .path = row.other, .line = symbol.line, .column = symbol.column });
			}
			y += DETAIL_ROW * scale;
			for (sz u = 0; u < symbol.usages.len(); u++)
			{
				connection_details::DetailUsage usage = symbol.usages[u];
				Rect usage_rect;
				usage_rect.x = detail_x + (float)ui::px(14);
				usage_rect.y = y;
				usage_rect.width = detail_w - (float)ui::px(18);
				usage_rect.height = USAGE_ROW * scale;
				if (y + USAGE_ROW * scale >= symbols_y && y <= symbols_y + available_h)
				{
					@pool()
					{
						String label = string::format(
							tmem,
							"%d:%d  %s",
							(long)(usage.line + 1),
							(long)(usage.column + 1),
							usage.preview
						);
						draw_text(
							font,
							elide(font, label, 12.0f * text, detail_w - (float)ui::px(20)),
							detail_x + (float)ui::px(14),
							y + 2.0f,
							12.0f * text,
							theme::current()
							.panel_dim);
					};
					self.hits.push(
						{ .rect = usage_rect, .path = row.path, .line = usage.line, .column = usage.column }
					);
				}
				y += USAGE_ROW * scale;
			}
		}
		else
		{
			y += DETAIL_ROW * scale;
			y += (float)symbol.usages.len() * USAGE_ROW * scale;
		}
	}
	rl::end_scissor_mode();
	if (content_h > available_h)
	{
		Rect track = {
			.x = panel.x + panel.width - (float)ui::px(5),
			.y = symbols_y,
			.width = (float)ui::px(3),
			.height = available_h,
		};
		ui::draw_scrollbar(
			track,
			content_h / (USAGE_ROW * scale),
			available_h / (USAGE_ROW * scale),
			(float)self.detail_scroll,
			false,
			theme::current()
			.editor_scrollbar, theme::current().panel_dim, theme::current().panel_text);
	}
}