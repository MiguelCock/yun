module yun::canvas;

import raylib6::rl;
import std::math;
import yun::theme;

const float BASE_CELL                  = 64.0f;
const float MIN_GRID_PX                = 16.0f;
const float MAX_GRID_PX                = 64.0f;
const int MAJOR_EVERY                  = 8;
const int MAX_GRID_LINES               = 4096;
const float DRAG_THRESHOLD_PX          = 4.0f;
const float MAX_PAN_DELTA_PX           = 200.0f;
const float MIN_ZOOM                   = 0.1f;
const float MAX_ZOOM                   = 8.0f;
const float FIT_MAX_ZOOM               = 1.0f;
const float ZOOM_STEP                  = 1.1f;
const float PAN_RESPONSIVENESS         = 20.0f;
const float ZOOM_RESPONSIVENESS        = 16.0f;
const float INERTIA_FRICTION_PER_FRAME = 0.9f;
const float EDGE_PAN_MARGIN            = 48.0f;
const float EDGE_PAN_SPEED             = 900.0f;
const float GRAB_FOLLOW_MARGIN_X       = 0.15f;
const float GRAB_FOLLOW_MARGIN_Y       = 0.15f;
const float GRAB_FOLLOW_MIN_X          = 80.0f;
const float GRAB_FOLLOW_MIN_Y          = 60.0f;
const float INERTIA_MIN_SPEED          = 5.0f;
const float MAX_FRAME_DT               = 0.05f;
const float CAMERA_SNAP_EPSILON        = 0.001f;
const bool SMOOTHING_ENABLED           = true;

struct CanvasSettings
{
	float min_zoom;
	float max_zoom;
	float zoom_step;
	float key_pan_step;
	float pan_responsiveness;
	float zoom_responsiveness;
	bool smoothing;
	float inertia_friction;
	float inertia_min_speed;
	float drag_threshold;
	float max_pan_delta;
	bool grid;
	float grid_cell;
	float grid_min_px;
	float grid_max_px;
	bool snap_to_grid;
	float snap_step;
	float jump_zoom_min;
	float jump_zoom_target;
	bool follow_selection;
}

CanvasSettings g_canvas_settings = {
	.min_zoom = MIN_ZOOM,
	.max_zoom = MAX_ZOOM,
	.zoom_step = ZOOM_STEP,
	.key_pan_step = 48.0f,
	.pan_responsiveness = PAN_RESPONSIVENESS,
	.zoom_responsiveness = ZOOM_RESPONSIVENESS,
	.smoothing = SMOOTHING_ENABLED,
	.inertia_friction = INERTIA_FRICTION_PER_FRAME,
	.inertia_min_speed = INERTIA_MIN_SPEED,
	.drag_threshold = DRAG_THRESHOLD_PX,
	.max_pan_delta = MAX_PAN_DELTA_PX,
	.grid = true,
	.grid_cell = BASE_CELL,
	.grid_min_px = MIN_GRID_PX,
	.grid_max_px = MAX_GRID_PX,
	.snap_to_grid = true,
	.snap_step = 0.0f,
	.jump_zoom_min = 0.6f,
	.jump_zoom_target = 1.0f,
	.follow_selection = true,
};

fn CanvasSettings settings()
{
	return g_canvas_settings;
}

fn void set_settings(CanvasSettings value)
{
	if (value.zoom_step < 1.001f) value.zoom_step = 1.001f;
	if (value.pan_responsiveness < 0.1f) value.pan_responsiveness = 0.1f;
	if (value.zoom_responsiveness < 0.1f) value.zoom_responsiveness = 0.1f;
	if (value.inertia_friction < 0.0f) value.inertia_friction = 0.0f;
	if (value.inertia_friction > 0.99f) value.inertia_friction = 0.99f;
	if (value.inertia_min_speed < 0.0f) value.inertia_min_speed = 0.0f;
	if (value.drag_threshold < 0.0f) value.drag_threshold = 0.0f;
	if (value.max_pan_delta < 1.0f) value.max_pan_delta = 1.0f;
	if (value.grid_cell < 1.0f) value.grid_cell = 1.0f;
	if (value.snap_step < 0.0f) value.snap_step = 0.0f;
	if (value.snap_step > 1024.0f) value.snap_step = 1024.0f;

	if (value.max_zoom < 0.02f) value.max_zoom = 0.02f;
	if (value.max_zoom > 100.0f) value.max_zoom = 100.0f;
	if (value.min_zoom < 0.001f) value.min_zoom = 0.001f;
	if (value.min_zoom > value.max_zoom - 0.001f) value.min_zoom = value.max_zoom - 0.001f;

	if (value.grid_max_px < 1.0f) value.grid_max_px = 1.0f;
	if (value.grid_min_px < 0.5f) value.grid_min_px = 0.5f;
	if (value.grid_min_px > value.grid_max_px - 0.5f) value.grid_min_px = value.grid_max_px - 0.5f;

	if (value.jump_zoom_target < 0.01f) value.jump_zoom_target = 0.01f;
	if (value.jump_zoom_min < 0.001f) value.jump_zoom_min = 0.001f;
	if (value.jump_zoom_min > value.jump_zoom_target) value.jump_zoom_min = value.jump_zoom_target;

	g_canvas_settings = value;
}

struct Canvas
{
	RLCamera2D camera;
	RLCamera2D target;
	RLVector2 velocity;
	float top_inset;
	float bottom_inset;
	float left_inset;
	float right_inset;
	bool pointer_over_ui;
	bool block_zoom;
	bool block_pan;
	bool drag_pending;
	bool dragging;
	RLMouseButton drag_button;
	RLVector2 drag_start;
	bool following;
	RLVector2 follow_center;
}

fn void Canvas.init(&self)
{
	RLCamera2D initial = {
		.offset = { (float)rl::get_screen_width() / 2.0f, (float)rl::get_screen_height() / 2.0f },
		.target = { 0.0f, 0.0f },
		.rotation = 0.0f,
		.zoom = 1.0f,
	};
	self.camera = initial;
	self.target = initial;
	self.top_inset = 0.0f;
	self.bottom_inset = 0.0f;
	self.left_inset = 0.0f;
	self.right_inset = 0.0f;
	self.following = false;
	self.follow_center = { 0.0f, 0.0f };
}

fn void Canvas.follow(&self, RLVector2 center)
{
	self.following = true;
	self.follow_center = center;
	self.target.target = center;
}

fn void Canvas.unfollow(&self)
{
	self.following = false;
}

fn void Canvas.update(&self)
{
	self.camera.offset = { self.usable_offset_x(), self.usable_offset_y() };
	self.target.offset = self.camera.offset;

	float dt        = math::min(rl::get_frame_time(), MAX_FRAME_DT);
	RLVector2 mouse = rl::get_mouse_position();

	float wheel = rl::get_mouse_wheel_move();
	if (wheel != 0.0f && !self.block_zoom)
	{
		self.velocity = { 0.0f, 0.0f };
		self.zoom_at(wheel, mouse);
	}

	if (!self.block_pan && !self.drag_pending && !self.dragging)
	{
		if (rl::is_mouse_button_pressed(rl::RLMouseButton.MIDDLE))
		{
			self.begin_drag(rl::RLMouseButton.MIDDLE, mouse);
		}
		else if (rl::is_mouse_button_pressed(rl::RLMouseButton.LEFT) && !self.is_over_ui(mouse))
		{
			self.begin_drag(rl::RLMouseButton.LEFT, mouse);
		}
	}

	if (self.drag_pending || self.dragging)
	{
		if (!rl::is_mouse_button_down(self.drag_button))
		{
			self.drag_pending = false;
			self.dragging = false;
		}
		else
		{
			float dx = mouse[0] - self.drag_start[0];
			float dy = mouse[1] - self.drag_start[1];
			if (self.drag_pending
				&& dx * dx + dy * dy > g_canvas_settings.drag_threshold * g_canvas_settings.drag_threshold)
			{
				self.dragging = true;
			}
			if (self.dragging)
			{
				RLVector2 screen_delta = self.clamp_delta(rl::get_mouse_delta());
				self.pan_by(screen_delta);
				if (dt > 0.0f)
				{
					RLVector2 world_delta = {
						screen_delta[0] / self.target.zoom,
						screen_delta[1] / self.target.zoom,
					};
					self.velocity[0] += (world_delta[0] / dt - self.velocity[0]) * 0.5f;
					self.velocity[1] += (world_delta[1] / dt - self.velocity[1]) * 0.5f;
				}
			}
		}
	}

	if (!self.dragging)
	{
		self.apply_inertia(dt);
	}

	self.ease_camera(dt);
}

fn Rect usable_rect_for(
	float screen_w,
	float screen_h,
	float top_inset,
	float bottom_inset,
	float left_inset,
	float right_inset
)
{
	float width  = screen_w - left_inset - right_inset;
	float height = screen_h - top_inset - bottom_inset;
	if (width < 0.0f) width = 0.0f;
	if (height < 0.0f) height = 0.0f;
	return { .x = left_inset, .y = top_inset, .width = width, .height = height };
}

fn float Canvas.usable_offset_y(&self)
{
	Rect usable = self.usable_rect();
	return usable.y + usable.height / 2.0f;
}

fn float Canvas.usable_width(&self)
{
	return self.usable_rect().width;
}

fn float Canvas.usable_height(&self)
{
	return self.usable_rect().height;
}

fn float Canvas.usable_offset_x(&self)
{
	Rect usable = self.usable_rect();
	return usable.x + usable.width / 2.0f;
}

fn Rect Canvas.usable_rect(&self)
{
	return usable_rect_for(
		(float)rl::get_screen_width(),
		(float)rl::get_screen_height(),
		self.top_inset,
		self.bottom_inset,
		self.left_inset,
		self.right_inset
	);
}

fn Rect Canvas.usable_world_rect(&self)
{
	Rect usable  = self.usable_rect();
	RLVector2 tl = screen_to_world_camera(self.camera, { usable.x, usable.y });
	RLVector2 br = screen_to_world_camera(self.camera, { usable.x + usable.width, usable.y + usable.height });
	return { .x = tl[0], .y = tl[1], .width = br[0] - tl[0], .height = br[1] - tl[1] };
}

fn void Canvas.begin_drag(&self, RLMouseButton button, RLVector2 mouse)
{
	self.following = false;
	self.drag_pending = true;
	self.drag_button = button;
	self.drag_start = mouse;
	self.velocity = { 0.0f, 0.0f };
}

fn float ease_factor(float responsiveness, float dt)
{
	return math::clamp(1.0f - math::exp(-responsiveness * dt), 0.0f, 1.0f);
}

fn RLVector2 screen_to_world_camera(RLCamera2D camera, RLVector2 screen)
{
	return rl::get_screen_to_world2d(screen, camera);
}

fn void Canvas.apply_inertia(&self, float dt)
{
	float speed_sq = self.velocity[0] * self.velocity[0] + self.velocity[1] * self.velocity[1];
	if (speed_sq <= g_canvas_settings.inertia_min_speed * g_canvas_settings.inertia_min_speed)
	{
		self.velocity = { 0.0f, 0.0f };
		return;
	}
	self.target.target[0] -= self.velocity[0] * dt;
	self.target.target[1] -= self.velocity[1] * dt;
	float decay = math::pow(g_canvas_settings.inertia_friction, dt * 60.0f);
	self.velocity[0] *= decay;
	self.velocity[1] *= decay;
}

fn RLVector2 edge_pan_delta(
	RLVector2 mouse,
	float width,
	float height,
	float top_inset,
	float margin,
	float speed,
	float zoom,
	float dt,
	float bottom_inset = 0.0f,
	float left_inset = 0.0f,
	float right_inset = 0.0f
)
{
	RLVector2 delta = { 0.0f, 0.0f };
	if (zoom <= 0.0f) zoom = 1.0f;
	if (margin <= 0.0f) return delta;

	float usable_width  = width - left_inset - right_inset;
	float usable_height = height - top_inset - bottom_inset;
	if (usable_width < margin * 2.0f) margin = usable_width * 0.5f;
	if (usable_height < margin * 2.0f) margin = usable_height * 0.5f;
	if (margin <= 0.0f) return delta;

	float left   = left_inset + margin;
	float right  = width - right_inset - margin;
	float top    = top_inset + margin;
	float bottom = height - bottom_inset - margin;

	if (mouse[0] < left)
	{
		delta[0] = -math::min(left - mouse[0], margin) / margin;
	}
	else if (mouse[0] > right)
	{
		delta[0] = math::min(mouse[0] - right, margin) / margin;
	}
	if (mouse[1] < top)
	{
		delta[1] = -math::min(top - mouse[1], margin) / margin;
	}
	else if (mouse[1] > bottom)
	{
		delta[1] = math::min(mouse[1] - bottom, margin) / margin;
	}

	float step = speed * dt / zoom;
	delta[0] *= step;
	delta[1] *= step;
	return delta;
}

fn RLVector2 keep_item_in_view_delta(Rect item, Rect safe, float zoom)
{
	RLVector2 delta = { 0.0f, 0.0f };
	if (zoom <= 0.0f) zoom = 1.0f;
	if (safe.width < 1.0f) safe.width = 1.0f;
	if (safe.height < 1.0f) safe.height = 1.0f;

	float center_x    = item.x + item.width / 2.0f;
	float center_y    = item.y + item.height / 2.0f;
	float item_right  = item.x + item.width;
	float item_bottom = item.y + item.height;
	float safe_right  = safe.x + safe.width;
	float safe_bottom = safe.y + safe.height;

	if (item.width > safe.width)
	{
		delta[0] = (center_x - (safe.x + safe.width / 2.0f)) / zoom;
	}
	else if (item.x < safe.x)
	{
		delta[0] = (item.x - safe.x) / zoom;
	}
	else if (item_right > safe_right)
	{
		delta[0] = (item_right - safe_right) / zoom;
	}

	if (item.height > safe.height)
	{
		delta[1] = (center_y - (safe.y + safe.height / 2.0f)) / zoom;
	}
	else if (item.y < safe.y)
	{
		delta[1] = (item.y - safe.y) / zoom;
	}
	else if (item_bottom > safe_bottom)
	{
		delta[1] = (item_bottom - safe_bottom) / zoom;
	}

	float max_x = safe.width / zoom;
	float max_y = safe.height / zoom;
	delta[0] = math::clamp(delta[0], -max_x, max_x);
	delta[1] = math::clamp(delta[1], -max_y, max_y);
	if (math::is_nan(delta[0]) || math::is_inf(delta[0])) delta[0] = 0.0f;
	if (math::is_nan(delta[1]) || math::is_inf(delta[1])) delta[1] = 0.0f;
	return delta;
}

fn void Canvas.ensure_item_visible(&self, Rect item, float margin_ratio)
{
	if (item.width <= 0.0f || item.height <= 0.0f) return;
	float zoom  = self.target.zoom > 0.0f ? self.target.zoom : 1.0f;
	RLVector2 a = rl::get_world_to_screen2d({ item.x, item.y }, self.target);
	RLVector2 b = rl::get_world_to_screen2d({ item.x + item.width, item.y + item.height }, self.target);
	Rect screen_item = {
		.x = math::min(a[0], b[0]),
		.y = math::min(a[1], b[1]),
		.width = math::abs(b[0] - a[0]),
		.height = math::abs(b[1] - a[1]),
	};
	Rect usable    = self.usable_rect();
	float margin_x = math::max(GRAB_FOLLOW_MIN_X, usable.width * margin_ratio);
	float margin_y = math::max(GRAB_FOLLOW_MIN_Y, usable.height * margin_ratio);
	Rect safe = {
		.x = usable.x + margin_x,
		.y = usable.y + margin_y,
		.width = usable.width - margin_x * 2.0f,
		.height = usable.height - margin_y * 2.0f,
	};
	RLVector2 delta = keep_item_in_view_delta(screen_item, safe, zoom);
	self.following = false;
	self.target.target[0] += delta[0];
	self.target.target[1] += delta[1];
}

fn void Canvas.ease_camera(&self, float dt)
{
	if (!g_canvas_settings.smoothing)
	{
		self.camera = self.target;
		self.following = false;
		return;
	}

	float pan_t  = ease_factor(g_canvas_settings.pan_responsiveness, dt);
	float zoom_t = ease_factor(g_canvas_settings.zoom_responsiveness, dt);
	if (self.following && !self.dragging) self.target.target = self.follow_center;

	if (self.dragging)
	{
		self.camera.target = self.target.target;
	}
	else
	{
		self.camera.target[0] += (self.target.target[0] - self.camera.target[0]) * pan_t;
		self.camera.target[1] += (self.target.target[1] - self.camera.target[1]) * pan_t;
		if (math::abs(
			self.target.target[0] - self.camera.target[0]
		) < CAMERA_SNAP_EPSILON && math::abs(self.target.target[1] - self.camera.target[1]) < CAMERA_SNAP_EPSILON)
		{
			self.camera.target = self.target.target;
		}
	}

	self.camera.zoom += (self.target.zoom - self.camera.zoom) * zoom_t;
	if (math::abs(self.target.zoom - self.camera.zoom) < CAMERA_SNAP_EPSILON)
	{
		self.camera.zoom = self.target.zoom;
	}
	if (self.following && !self.dragging && math::abs(
		self.target.target[0] - self.camera.target[0]
	) < CAMERA_SNAP_EPSILON && math::abs(self.target.target[1] - self.camera.target[1]) < CAMERA_SNAP_EPSILON)
	{
		self.following = false;
	}
}

fn void Canvas.zoom_at(&self, float wheel, RLVector2 screen_anchor)
{
	if (wheel == 0.0f || self.target.zoom <= 0.0f) return;
	self.following = false;
	RLVector2 world_under_cursor = screen_to_world_camera(self.target, screen_anchor);
	float new_zoom = math::clamp(
		self.target.zoom * math::pow(g_canvas_settings.zoom_step, wheel),
		g_canvas_settings.min_zoom,
		g_canvas_settings.max_zoom
	);
	self.target.zoom = new_zoom;
	self.target.target[0] = world_under_cursor[0] - (screen_anchor[0] - self.target.offset[0]) / new_zoom;
	self.target.target[1] = world_under_cursor[1] - (screen_anchor[1] - self.target.offset[1]) / new_zoom;
}

fn void Canvas.pan_by(&self, RLVector2 screen_delta)
{
	if (self.target.zoom <= 0.0f) return;
	self.following = false;
	self.target.target[0] -= screen_delta[0] / self.target.zoom;
	self.target.target[1] -= screen_delta[1] / self.target.zoom;
}

fn void Canvas.key_pan(&self, RLVector2 screen_delta)
{
	self.following = false;
	float zoom = self.target.zoom > 0.0f ? self.target.zoom : 1.0f;
	self.target.target[0] += screen_delta[0] / zoom;
	self.target.target[1] += screen_delta[1] / zoom;
	self.velocity = { 0.0f, 0.0f };
}

fn void Canvas.key_zoom(&self, float direction)
{
	self.following = false;
	float zoom = self.target.zoom > 0.0f ? self.target.zoom : 1.0f;
	self.target.zoom = math::clamp(
		zoom * math::pow(g_canvas_settings.zoom_step, direction),
		g_canvas_settings.min_zoom,
		g_canvas_settings.max_zoom
	);
}

fn void Canvas.reset_zoom(&self)
{
	self.following = false;
	self.target.zoom = 1.0f;
}

fn void Canvas.fit_zoom(&self, Rect content, int screen_w, int screen_h)
{
	if (content.width <= 0.0f || content.height <= 0.0f) return;
	float margin = 40.0f;
	float width  = (float)screen_w - self.left_inset - self.right_inset;
	float height = (float)screen_h - self.top_inset - self.bottom_inset;
	if (width < 1.0f) width = 1.0f;
	if (height < 1.0f) height = 1.0f;
	float fit_x = (width - margin * 2.0f) / content.width;
	float fit_y = (height - margin * 2.0f) / content.height;
	float top   = math::min(g_canvas_settings.max_zoom, FIT_MAX_ZOOM);
	self.target.zoom = math::clamp(math::min(fit_x, fit_y), g_canvas_settings.min_zoom, top);
	self.target.target = {
		content.x + content.width / 2.0f,
		content.y + content.height / 2.0f,
	};
}

fn void Canvas.fit_zoom_floor(&self, Rect content, int screen_w, int screen_h, float floor)
{
	self.fit_zoom(content, screen_w, screen_h);
	if (floor <= 0.0f || self.target.zoom >= floor) return;
	self.target.zoom = floor;
	float width  = (float)screen_w - self.left_inset - self.right_inset;
	float height = (float)screen_h - self.top_inset - self.bottom_inset;
	if (width < 1.0f) width = 1.0f;
	if (height < 1.0f) height = 1.0f;
	self.target.target = {
		content.x + width / (2.0f * floor),
		content.y + height / (2.0f * floor),
	};
}

fn RLVector2 Canvas.clamp_delta(&self, RLVector2 delta)
{
	float len_sq = delta[0] * delta[0] + delta[1] * delta[1];
	if (len_sq <= g_canvas_settings.max_pan_delta * g_canvas_settings.max_pan_delta) return delta;
	float scale = g_canvas_settings.max_pan_delta / math::sqrt(len_sq);
	return { delta[0] * scale, delta[1] * scale };
}

fn bool Canvas.is_over_ui(&self, RLVector2 screen)
{
	return self.pointer_over_ui;
}

fn RLVector2 Canvas.screen_to_world(&self, RLVector2 screen)
{
	return screen_to_world_camera(self.camera, screen);
}

fn Rect Canvas.visible_world_rect(&self)
{
	RLVector2 min = self.screen_to_world({ 0.0f, 0.0f });
	RLVector2 max = self.screen_to_world({ (float)rl::get_screen_width(), (float)rl::get_screen_height() });
	return { .x = min[0], .y = min[1], .width = max[0] - min[0], .height = max[1] - min[1] };
}

fn float snap_step(float zoom)
{
	if (g_canvas_settings.snap_step > 0.0f) return g_canvas_settings.snap_step;
	return grid_step(zoom);
}

fn float snap_value(float value, float step)
{
	if (step <= 0.0f) return value;
	return math::round(value / step) * step;
}

fn float grid_step(float zoom)
{
	if (zoom <= 0.0f) return g_canvas_settings.grid_cell;
	float step = g_canvas_settings.grid_cell;
	while (step * zoom < g_canvas_settings.grid_min_px) step *= 2.0f;
	while (step * zoom > g_canvas_settings.grid_max_px) step *= 0.5f;
	return step;
}

fn void Canvas.draw_grid(&self)
{
	if (!g_canvas_settings.grid) return;
	Rect world = self.visible_world_rect();
	if (world.width <= 0.0f || world.height <= 0.0f) return;

	float step       = grid_step(self.camera.zoom);
	float major      = step * MAJOR_EVERY;
	float thick      = 1.0f / self.camera.zoom;
	float line_count = world.width / step + world.height / step;
	if (line_count > MAX_GRID_LINES) return;

	float x0 = math::floor(world.x / step) * step;
	for (float x = x0; x <= world.x + world.width; x += step)
	{
		rl::draw_line_ex({ x, world.y }, { x, world.y + world.height }, thick, theme::current().grid_minor);
	}
	float y0 = math::floor(world.y / step) * step;
	for (float y = y0; y <= world.y + world.height; y += step)
	{
		rl::draw_line_ex({ world.x, y }, { world.x + world.width, y }, thick, theme::current().grid_minor);
	}

	float major_x0 = math::floor(world.x / major) * major;
	for (float x = major_x0; x <= world.x + world.width; x += major)
	{
		rl::draw_line_ex({ x, world.y }, { x, world.y + world.height }, thick, theme::current().grid_major);
	}
	float major_y0 = math::floor(world.y / major) * major;
	for (float y = major_y0; y <= world.y + world.height; y += major)
	{
		rl::draw_line_ex({ world.x, y }, { world.x + world.width, y }, thick, theme::current().grid_major);
	}
}

fn void Canvas.draw(&self)
{
	rl::clear_background(theme::current().window_bg);
	rl::@mode2d(self.camera)
	{
		self.draw_grid();
	};
}