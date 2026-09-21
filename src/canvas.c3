module yun::canvas;

import raylib6::rl;
import std::math;

const RLColor BACKGROUND               = { 24, 24, 28, 255 };
const RLColor GRID_MINOR               = { 40, 40, 47, 255 };
const RLColor GRID_MAJOR               = { 64, 64, 74, 255 };
const float BASE_CELL                  = 64.0f;
const float MIN_GRID_PX                = 16.0f;
const float MAX_GRID_PX                = 64.0f;
const int MAJOR_EVERY                  = 8;
const int MAX_GRID_LINES               = 4096;
const float DRAG_THRESHOLD_PX          = 4.0f;
const float MAX_PAN_DELTA_PX           = 200.0f;
const float MIN_ZOOM                   = 0.1f;
const float MAX_ZOOM                   = 8.0f;
const float ZOOM_STEP                  = 1.1f;
const float PAN_RESPONSIVENESS         = 20.0f;
const float ZOOM_RESPONSIVENESS        = 16.0f;
const float INERTIA_FRICTION_PER_FRAME = 0.9f;
const float INERTIA_MIN_SPEED          = 5.0f;
const float MAX_FRAME_DT               = 0.05f;
const float CAMERA_SNAP_EPSILON        = 0.001f;
const bool SMOOTHING_ENABLED           = true;

struct Canvas
{
	RLCamera2D camera;
	RLCamera2D target;
	RLVector2 velocity;
	bool pointer_over_ui;
	bool drag_pending;
	bool dragging;
	RLMouseButton drag_button;
	RLVector2 drag_start;
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
}

fn void Canvas.update(&self)
{
	self.camera.offset = { (float)rl::get_screen_width() / 2.0f, (float)rl::get_screen_height() / 2.0f };
	self.target.offset = self.camera.offset;

	float dt        = math::min(rl::get_frame_time(), MAX_FRAME_DT);
	RLVector2 mouse = rl::get_mouse_position();

	float wheel = rl::get_mouse_wheel_move();
	if (wheel != 0.0f)
	{
		self.velocity = { 0.0f, 0.0f };
		self.zoom_at(wheel, mouse);
	}

	if (!self.drag_pending && !self.dragging)
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
			if (self.drag_pending && dx * dx + dy * dy > DRAG_THRESHOLD_PX * DRAG_THRESHOLD_PX)
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

fn void Canvas.begin_drag(&self, RLMouseButton button, RLVector2 mouse)
{
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
	if (speed_sq <= INERTIA_MIN_SPEED * INERTIA_MIN_SPEED)
	{
		self.velocity = { 0.0f, 0.0f };
		return;
	}
	self.target.target[0] -= self.velocity[0] * dt;
	self.target.target[1] -= self.velocity[1] * dt;
	float decay = math::pow(INERTIA_FRICTION_PER_FRAME, dt * 60.0f);
	self.velocity[0] *= decay;
	self.velocity[1] *= decay;
}

fn void Canvas.ease_camera(&self, float dt)
{
	if (!SMOOTHING_ENABLED)
	{
		self.camera = self.target;
		return;
	}

	float pan_t  = ease_factor(PAN_RESPONSIVENESS, dt);
	float zoom_t = ease_factor(ZOOM_RESPONSIVENESS, dt);

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
}

fn void Canvas.zoom_at(&self, float wheel, RLVector2 screen_anchor)
{
	if (wheel == 0.0f || self.target.zoom <= 0.0f) return;
	RLVector2 world_under_cursor = screen_to_world_camera(self.camera, screen_anchor);
	float new_zoom               = math::clamp(self.target.zoom * math::pow(ZOOM_STEP, wheel), MIN_ZOOM, MAX_ZOOM);
	self.target.zoom = new_zoom;
	self.target.target[0] = world_under_cursor[0] - (screen_anchor[0] - self.target.offset[0]) / new_zoom;
	self.target.target[1] = world_under_cursor[1] - (screen_anchor[1] - self.target.offset[1]) / new_zoom;
}

fn void Canvas.pan_by(&self, RLVector2 screen_delta)
{
	if (self.target.zoom <= 0.0f) return;
	self.target.target[0] -= screen_delta[0] / self.target.zoom;
	self.target.target[1] -= screen_delta[1] / self.target.zoom;
}

fn RLVector2 Canvas.clamp_delta(&self, RLVector2 delta)
{
	float len_sq = delta[0] * delta[0] + delta[1] * delta[1];
	if (len_sq <= MAX_PAN_DELTA_PX * MAX_PAN_DELTA_PX) return delta;
	float scale = MAX_PAN_DELTA_PX / math::sqrt(len_sq);
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

fn float grid_step(float zoom)
{
	if (zoom <= 0.0f) return BASE_CELL;
	float step = BASE_CELL;
	while (step * zoom < MIN_GRID_PX) step *= 2.0f;
	while (step * zoom > MAX_GRID_PX) step *= 0.5f;
	return step;
}

fn void Canvas.draw_grid(&self)
{
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
		rl::draw_line_ex({ x, world.y }, { x, world.y + world.height }, thick, GRID_MINOR);
	}
	float y0 = math::floor(world.y / step) * step;
	for (float y = y0; y <= world.y + world.height; y += step)
	{
		rl::draw_line_ex({ world.x, y }, { world.x + world.width, y }, thick, GRID_MINOR);
	}

	float major_x0 = math::floor(world.x / major) * major;
	for (float x = major_x0; x <= world.x + world.width; x += major)
	{
		rl::draw_line_ex({ x, world.y }, { x, world.y + world.height }, thick, GRID_MAJOR);
	}
	float major_y0 = math::floor(world.y / major) * major;
	for (float y = major_y0; y <= world.y + world.height; y += major)
	{
		rl::draw_line_ex({ world.x, y }, { world.x + world.width, y }, thick, GRID_MAJOR);
	}
}

fn void Canvas.draw(&self)
{
	rl::clear_background(BACKGROUND);
	rl::@mode2d(self.camera)
	{
		self.draw_grid();
	};
}