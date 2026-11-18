package main

import "core:fmt"
import "core:math"
import "core:os"
import "core:strconv"
import "core:strings"
import rl "vendor:raylib"

// The Amiga original showed a 336 × 272 window onto its pitch. Matching its
// vertical span keeps the same zoom; a widescreen window then shows more width.
ORIGINAL_VIEW_H :: 272.0
MIN_VIEW_H :: 80.0
MAX_VIEW_H :: 1200.0
VIEW_MARGIN : f32 : 4.0 * M // how far past the boards the camera may look

PAN_SPEED :: 300.0 // units per second at the original zoom
FAST_PAN :: 2.5    // Shift multiplier

View :: struct {
	centre:   [2]f32, // camera centre on the ground: x across, z along the pitch
	view_h:   f32,    // world units visible top to bottom
	height_k: f32,    // screen pixels moved up per unit of height: 1 = original oblique, 0 = straight down
}

// Oblique orthographic projection, the original's rule: ground is drawn
// without foreshortening and a point at height Y moves Y units up the screen.
// Depth runs along the projection direction (up and towards the bottom of
// the screen), so raised objects correctly cover what is behind them.
view_projection :: proc(v: View, aspect: f32) -> rl.Matrix {
	DEPTH_RANGE :: 4000.0
	hh := v.view_h / 2
	hw := hh * aspect
	k := v.height_k
	cx, cz := v.centre.x, v.centre.y
	return rl.Matrix {
		1 / hw, 0,                0,                  -cx / hw,
		0,      k / hh,           -1 / hh,            cz / hh,
		0,      -1 / DEPTH_RANGE, -k / DEPTH_RANGE,   k * cz / DEPTH_RANGE,
		0,      0,                0,                  1,
	}
}

view_width :: proc(v: View, aspect: f32) -> f32 {
	return v.view_h * aspect
}

clamp_view :: proc(v: ^View, aspect: f32) {
	v.view_h = clamp(v.view_h, MIN_VIEW_H, MAX_VIEW_H)
	hw := view_width(v^, aspect) / 2
	hh := v.view_h / 2
	bx := WORLD_HALF_W + VIEW_MARGIN
	bz := WORLD_HALF_L + VIEW_MARGIN
	v.centre.x = 0 if hw >= bx else clamp(v.centre.x, -bx + hw, bx - hw)
	v.centre.y = 0 if hh >= bz else clamp(v.centre.y, -bz + hh, bz - hh)
}

update_view :: proc(v: ^View, dt, aspect: f32) {
	dir: [2]f32
	if rl.IsKeyDown(.LEFT) do dir.x -= 1
	if rl.IsKeyDown(.RIGHT) do dir.x += 1
	if rl.IsKeyDown(.UP) do dir.y -= 1
	if rl.IsKeyDown(.DOWN) do dir.y += 1
	if dir.x != 0 || dir.y != 0 {
		dir /= math.sqrt(dir.x * dir.x + dir.y * dir.y)
		speed: f32 = PAN_SPEED * v.view_h / ORIGINAL_VIEW_H // same on-screen speed at any zoom
		if rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT) do speed *= FAST_PAN
		v.centre += dir * speed * dt
	}

	zoom := rl.GetMouseWheelMove()
	if rl.IsKeyPressed(.EQUAL) || rl.IsKeyPressed(.KP_ADD) do zoom += 1
	if rl.IsKeyPressed(.MINUS) || rl.IsKeyPressed(.KP_SUBTRACT) do zoom -= 1
	if zoom != 0 do v.view_h *= math.pow(f32(1.15), -zoom)
	if rl.IsKeyPressed(.ZERO) || rl.IsKeyPressed(.KP_0) do v.view_h = ORIGINAL_VIEW_H
	if rl.IsKeyPressed(.F) {
		// Whole pitch, run-off and boards.
		v.view_h = max(2 * (WORLD_HALF_L + VIEW_MARGIN), 2 * (WORLD_HALF_W + VIEW_MARGIN) / aspect)
	}
	if rl.IsKeyPressed(.T) do v.height_k = 0 if v.height_k > 0 else 1

	clamp_view(v, aspect)
}

draw_world :: proc(v: View, aspect: f32) {
	// BeginMode3D sets up raylib's 3D state; the camera's own matrices are
	// then replaced with the oblique projection.
	cam := rl.Camera3D {
		position   = {0, 100, 0},
		target     = {0, 0, 0},
		up         = {0, 0, -1},
		fovy       = v.view_h,
		projection = .ORTHOGRAPHIC,
	}
	rl.BeginMode3D(cam)
	SetMatrixProjection(view_projection(v, aspect))
	SetMatrixModelview(rl.Matrix(1))
	draw_pitch()
	rl.EndMode3D()
}

draw_hud :: proc(v: View, aspect: f32) {
	sw := rl.GetScreenWidth()
	sh := rl.GetScreenHeight()
	vw := view_width(v, aspect)

	// Short lines so the panel fits a narrow tiled window.
	lines := [?]cstring {
		fmt.ctprintf("Pitch 105 x 68 m = %.0f x %.0f units", PITCH_LENGTH, PITCH_WIDTH),
		fmt.ctprintf("%.0f units/m; original SWOS was 641 x 510", M),
		fmt.ctprintf("View %.0f x %.0f units (original 336 x 272)", vw, v.view_h),
		fmt.ctprintf("Shows %.0f%% of width, %.0f%% of length", 100 * min(vw / PITCH_WIDTH, 1), 100 * min(v.view_h / PITCH_LENGTH, 1)),
		fmt.ctprintf("Camera %+.1f m, %+.1f m  %s", v.centre.x / M, v.centre.y / M, "oblique" if v.height_k > 0 else "top-down"),
		"Arrows move  Shift fast  Wheel or -/= zoom",
		"0 orig zoom  F whole pitch  T view  H hide",
	}
	FONT :: 16
	PAD :: 10
	width: i32 = 0
	for l in lines do width = max(width, rl.MeasureText(l, FONT))
	rl.DrawRectangle(0, 0, width + 2 * PAD, i32(len(lines)) * (FONT + 6) + 2 * PAD - 6, {0, 0, 0, 150})
	for l, i in lines do rl.DrawText(l, PAD, PAD + i32(i) * (FONT + 6), FONT, rl.RAYWHITE)

	// 10 m scale bar.
	px_per_unit := f32(sh) / v.view_h
	bar := i32(10 * M * px_per_unit)
	x0, y0 := i32(20), sh - 30
	rl.DrawRectangle(x0 - 8, y0 - 26, bar + 16, 40, {0, 0, 0, 150})
	rl.DrawRectangle(x0, y0, bar, 4, rl.RAYWHITE)
	rl.DrawRectangle(x0, y0 - 6, 2, 10, rl.RAYWHITE)
	rl.DrawRectangle(x0 + bar - 2, y0 - 6, 2, 10, rl.RAYWHITE)
	rl.DrawText("10 m", x0, y0 - 22, FONT, rl.RAYWHITE)

	rl.DrawFPS(sw - 100, 10)
}

Options :: struct {
	shot:      string, // save a screenshot to this path and exit
	at:        [2]f32, // starting camera position in metres from the centre spot
	view_h:    f32,
	top_down:  bool,
	width:     i32,
	height:    i32,
}

parse_args :: proc() -> (o: Options) {
	o.view_h = ORIGINAL_VIEW_H
	o.width, o.height = 1600, 1000
	for a in os.args[1:] {
		switch {
		case strings.has_prefix(a, "--shot="):
			o.shot = a[len("--shot="):]
		case strings.has_prefix(a, "--at="):
			parts := strings.split(a[len("--at="):], ",", context.temp_allocator)
			if len(parts) == 2 {
				o.at.x, _ = strconv.parse_f32(parts[0])
				o.at.y, _ = strconv.parse_f32(parts[1])
			}
		case strings.has_prefix(a, "--zoom="):
			o.view_h, _ = strconv.parse_f32(a[len("--zoom="):])
		case strings.has_prefix(a, "--size="):
			parts := strings.split(a[len("--size="):], "x", context.temp_allocator)
			if len(parts) == 2 {
				w, _ := strconv.parse_int(parts[0])
				h, _ := strconv.parse_int(parts[1])
				o.width, o.height = i32(w), i32(h)
			}
		case a == "--top-down":
			o.top_down = true
		case:
			fmt.eprintln("unknown argument:", a)
			fmt.eprintln("usage: senselesssoccer [--at=X,Z] [--zoom=UNITS] [--top-down] [--size=WxH] [--shot=FILE.png]")
			os.exit(2)
		}
	}
	return
}

main :: proc() {
	opts := parse_args()

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .MSAA_4X_HINT, .VSYNC_HINT})
	rl.SetTraceLogLevel(.ERROR) // GLFW warns that Wayland cannot position windows; harmless
	rl.InitWindow(opts.width, opts.height, "senselesssoccer: pitch")
	defer rl.CloseWindow()

	view := View {
		centre   = opts.at * M,
		view_h   = opts.view_h,
		height_k = 0 if opts.top_down else 1,
	}

	show_hud := true
	frames := 0
	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		aspect := f32(rl.GetScreenWidth()) / f32(rl.GetScreenHeight())
		update_view(&view, dt, aspect)
		if rl.IsKeyPressed(.H) do show_hud = !show_hud

		rl.BeginDrawing()
		rl.ClearBackground(SURROUND)
		draw_world(view, aspect)
		if show_hud do draw_hud(view, aspect)

		frames += 1
		if opts.shot != "" && frames == 20 {
			DrawRenderBatchActive() // flush the HUD before reading the back buffer
			img := rl.LoadImageFromScreen()
			ok := rl.ExportImage(img, strings.clone_to_cstring(opts.shot, context.temp_allocator))
			rl.UnloadImage(img)
			rl.EndDrawing()
			if !ok do os.exit(1)
			break
		}
		rl.EndDrawing()
		free_all(context.temp_allocator)
	}
}
