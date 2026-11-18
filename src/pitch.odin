package main

import "core:math"
import rl "vendor:raylib"

// World space
// -----------
// One world unit is one pixel of the original Amiga game (SWOS 96/97), so the
// reverse-engineered speeds and distances can be used unchanged later.
// Origin is the centre spot. X runs across the pitch (left to right), Z runs
// along it (negative Z is the top goal, as on the original's vertical pitch),
// Y is height.
//
// Scale: 7 units per metre. The original's pitch was 510 × 641 units, which
// squashes a real pitch: 7.5 units/m across but only 6.1 units/m along. Its
// penalty area (285 units for 40.32 m) is 7.07 units/m. Using 7 units/m on a
// real 105 × 68 m pitch gives 735 × 476 units: same area as the original to
// within 7%, with real proportions (length +15%, width −7%).
M :: 7.0

PITCH_LENGTH : f32 : 105.0 * M // 735
PITCH_WIDTH  : f32 : 68.0 * M  // 476
HALF_L       : f32 : PITCH_LENGTH / 2
HALF_W       : f32 : PITCH_WIDTH / 2

// Real lines are at most 0.12 m (0.84 units); rounded up to one original pixel.
LINE_W : f32 : 1.0

CENTRE_CIRCLE_R     : f32 : 9.15 * M
SPOT_R              : f32 : 1.2
PENALTY_AREA_DEPTH  : f32 : 16.5 * M
PENALTY_AREA_HALF_W : f32 : (7.32 / 2 + 16.5) * M
GOAL_AREA_DEPTH     : f32 : 5.5 * M
GOAL_AREA_HALF_W    : f32 : (7.32 / 2 + 5.5) * M
PENALTY_SPOT_DIST   : f32 : 11.0 * M
PENALTY_ARC_R       : f32 : 9.15 * M
CORNER_ARC_R        : f32 : 1.0 * M

// Real goal: 7.32 × 2.44 m (51 × 17 units). The original exaggerated the
// mouth to 64 units wide; its crossbar sat at 15.
GOAL_HALF_W      : f32 : 7.32 / 2 * M // inside edge of the posts
GOAL_HEIGHT      : f32 : 2.44 * M     // underside of the crossbar
POST_W           : f32 : LINE_W       // posts are as wide as the goal line
NET_DEPTH_BOTTOM : f32 : 2.0 * M
NET_DEPTH_TOP    : f32 : 1.0 * M
CORNER_FLAG_H    : f32 : 1.5 * M

// Grass beyond the lines, ending at the advertising boards.
RUNOFF_SIDE  : f32 : 7.0 * M
RUNOFF_END   : f32 : 9.0 * M
WORLD_HALF_W : f32 : HALF_W + RUNOFF_SIDE
WORLD_HALF_L : f32 : HALF_L + RUNOFF_END
BOARD_H      : f32 : 0.9 * M
BOARD_T      : f32 : 0.5
BOARD_PANEL  : f32 : 6.0 * M

MOW_BANDS :: 18 // mowing stripes across the playing length

GRASS_LIGHT :: rl.Color{80, 162, 68, 255}
GRASS_DARK  :: rl.Color{68, 146, 58, 255}
LINE_COLOUR :: rl.Color{238, 241, 232, 255}
SURROUND    :: rl.Color{36, 44, 40, 255}
POST_COLOUR :: rl.Color{250, 250, 250, 255}
NET_COLOUR  :: rl.Color{228, 232, 226, 140}
NET_FRAME   :: rl.Color{190, 194, 190, 255}
FLAG_POLE   :: rl.Color{245, 214, 60, 255}
FLAG_CLOTH  :: rl.Color{226, 52, 44, 255}

BOARD_COLOURS := [4]rl.Color {
	{200, 44, 44, 255},
	{240, 240, 236, 255},
	{36, 78, 170, 255},
	{236, 196, 44, 255},
}

SIDES :: [2]f32{-1, 1}

// Ground geometry: flat quads at Y = 0, drawn without depth testing in
// painter's order (grass, then lines).

quad3 :: proc(a, b, c, d: rl.Vector3, col: rl.Color) {
	Begin(QUADS)
	Color4ub(col.r, col.g, col.b, col.a)
	Vertex3f(a.x, a.y, a.z)
	Vertex3f(b.x, b.y, b.z)
	Vertex3f(c.x, c.y, c.z)
	Vertex3f(d.x, d.y, d.z)
	End()
}

ground_rect :: proc(x0, z0, x1, z1: f32, col: rl.Color) {
	quad3({x0, 0, z0}, {x1, 0, z0}, {x1, 0, z1}, {x0, 0, z1}, col)
}

// Lines belong to the area they bound, so outlines are drawn inside the box.
ground_outline :: proc(x0, z0, x1, z1: f32, col: rl.Color) {
	ground_rect(x0, z0, x1, z0 + LINE_W, col)
	ground_rect(x0, z1 - LINE_W, x1, z1, col)
	ground_rect(x0, z0, x0 + LINE_W, z1, col)
	ground_rect(x1 - LINE_W, z0, x1, z1, col)
}

// Ring segment of the given width inside r_outer. Angles are in the XZ plane:
// 0 points to +X, π/2 points to +Z (down the screen).
ground_arc :: proc(cx, cz, r_outer, width, a0, a1: f32, col: rl.Color) {
	r_inner := max(r_outer - width, 0)
	segs := max(8, int(abs(a1 - a0) * r_outer / 2)) // about 2 units per segment
	for i in 0 ..< segs {
		t0 := a0 + (a1 - a0) * f32(i) / f32(segs)
		t1 := a0 + (a1 - a0) * f32(i + 1) / f32(segs)
		c0, s0 := math.cos(t0), math.sin(t0)
		c1, s1 := math.cos(t1), math.sin(t1)
		quad3(
			{cx + c0 * r_inner, 0, cz + s0 * r_inner},
			{cx + c0 * r_outer, 0, cz + s0 * r_outer},
			{cx + c1 * r_outer, 0, cz + s1 * r_outer},
			{cx + c1 * r_inner, 0, cz + s1 * r_inner},
			col,
		)
	}
}

ground_disc :: proc(cx, cz, r: f32, col: rl.Color) {
	ground_arc(cx, cz, r, r, 0, math.TAU, col)
}

draw_grass :: proc() {
	band := PITCH_LENGTH / MOW_BANDS
	// Bands are aligned to the goal line and continue into the run-off.
	first := int(math.floor((-WORLD_HALF_L + HALF_L) / band))
	for i := first;; i += 1 {
		z0 := -HALF_L + f32(i) * band
		if z0 >= WORLD_HALF_L do break
		z1 := z0 + band
		col := GRASS_LIGHT if (i & 1) == 0 else GRASS_DARK
		ground_rect(-WORLD_HALF_W, max(z0, -WORLD_HALF_L), WORLD_HALF_W, min(z1, WORLD_HALF_L), col)
	}
}

draw_markings :: proc() {
	c := LINE_COLOUR

	// Touchlines and goal lines.
	ground_outline(-HALF_W, -HALF_L, HALF_W, HALF_L, c)

	// Halfway line, centre circle, centre mark.
	ground_rect(-HALF_W, -LINE_W / 2, HALF_W, LINE_W / 2, c)
	ground_arc(0, 0, CENTRE_CIRCLE_R, LINE_W, 0, math.TAU, c)
	ground_disc(0, 0, SPOT_R, c)

	// Penalty arc: the part of a 9.15 m circle round the penalty mark that
	// lies outside the penalty area.
	arc_half := math.asin((PENALTY_AREA_DEPTH - PENALTY_SPOT_DIST) / PENALTY_ARC_R)

	for side in SIDES {
		goal_z := side * HALF_L      // outer edge of this goal line
		inward := -side              // direction towards the halfway line
		pz := goal_z + inward * PENALTY_AREA_DEPTH
		gz := goal_z + inward * GOAL_AREA_DEPTH

		ground_outline(-PENALTY_AREA_HALF_W, min(goal_z, pz), PENALTY_AREA_HALF_W, max(goal_z, pz), c)
		ground_outline(-GOAL_AREA_HALF_W, min(goal_z, gz), GOAL_AREA_HALF_W, max(goal_z, gz), c)

		spot_z := goal_z + inward * PENALTY_SPOT_DIST
		ground_disc(0, spot_z, SPOT_R, c)

		facing: f32 = math.PI / 2 if inward > 0 else -math.PI / 2
		ground_arc(0, spot_z, PENALTY_ARC_R, LINE_W, facing - (math.PI / 2 - arc_half), facing + (math.PI / 2 - arc_half), c)
	}

	// Corner arcs, quarter circles of 1 m inside each corner.
	ground_arc(-HALF_W, -HALF_L, CORNER_ARC_R, LINE_W, 0, math.PI / 2, c)
	ground_arc(HALF_W, -HALF_L, CORNER_ARC_R, LINE_W, math.PI / 2, math.PI, c)
	ground_arc(HALF_W, HALF_L, CORNER_ARC_R, LINE_W, math.PI, 3 * math.PI / 2, c)
	ground_arc(-HALF_W, HALF_L, CORNER_ARC_R, LINE_W, 3 * math.PI / 2, math.TAU, c)
}

// Raised geometry, drawn with depth testing.

draw_goal :: proc(side: f32) {
	line_z := side * HALF_L // outer edge of the goal line; posts sit on the line
	post_z := line_z - side * POST_W / 2

	for sx in SIDES {
		x := sx * (GOAL_HALF_W + POST_W / 2)
		rl.DrawCubeV({x, (GOAL_HEIGHT + POST_W) / 2, post_z}, {POST_W, GOAL_HEIGHT + POST_W, POST_W}, POST_COLOUR)
	}
	rl.DrawCubeV({0, GOAL_HEIGHT + POST_W / 2, post_z}, {2 * (GOAL_HALF_W + POST_W), POST_W, POST_W}, POST_COLOUR)

	draw_net(line_z, side)
}

draw_net :: proc(line_z, side: f32) {
	MESH :: 2.0 // net spacing in units
	gw := GOAL_HALF_W
	h := GOAL_HEIGHT
	bz := line_z + side * NET_DEPTH_BOTTOM // back of the net at ground level
	tz := line_z + side * NET_DEPTH_TOP    // back of the net at crossbar height

	// Back panel, sloping from the ground to the roof.
	for x := -gw; x <= gw + 0.01; x += MESH {
		rl.DrawLine3D({x, 0, bz}, {x, h, tz}, NET_COLOUR)
	}
	for y: f32 = MESH; y <= h + 0.01; y += MESH {
		z := bz + (tz - bz) * (y / h)
		rl.DrawLine3D({-gw, y, z}, {gw, y, z}, NET_COLOUR)
	}

	// Roof.
	for x := -gw; x <= gw + 0.01; x += MESH {
		rl.DrawLine3D({x, h, line_z}, {x, h, tz}, NET_COLOUR)
	}
	roof_lines := NET_DEPTH_TOP / MESH
	for i in 1 ..= int(roof_lines) {
		z := line_z + side * f32(i) * MESH
		rl.DrawLine3D({-gw, h, z}, {gw, h, z}, NET_COLOUR)
	}

	// Side panels.
	for sx in SIDES {
		x := sx * gw
		side_lines := NET_DEPTH_BOTTOM / MESH
		for i in 1 ..= int(side_lines) {
			t := f32(i) * MESH / NET_DEPTH_BOTTOM
			rl.DrawLine3D({x, 0, line_z + (bz - line_z) * t}, {x, h, line_z + (tz - line_z) * t}, NET_COLOUR)
		}
		for y: f32 = MESH; y <= h + 0.01; y += MESH {
			rl.DrawLine3D({x, y, line_z}, {x, y, bz + (tz - bz) * (y / h)}, NET_COLOUR)
		}

		// Frame.
		rl.DrawLine3D({x, h, line_z}, {x, h, tz}, NET_FRAME)
		rl.DrawLine3D({x, h, tz}, {x, 0, bz}, NET_FRAME)
		rl.DrawLine3D({x, 0, bz}, {x, 0, line_z}, NET_FRAME)
	}
	rl.DrawLine3D({-gw, 0, bz}, {gw, 0, bz}, NET_FRAME)
	rl.DrawLine3D({-gw, h, tz}, {gw, h, tz}, NET_FRAME)
}

draw_corner_flag :: proc(x, z: f32) {
	POLE :: 0.4
	rl.DrawCubeV({x, CORNER_FLAG_H / 2, z}, {POLE, CORNER_FLAG_H, POLE}, FLAG_POLE)
	// Cloth hangs towards the pitch, in the vertical plane through the pole.
	dir: f32 = -1 if x > 0 else 1
	top := CORNER_FLAG_H
	quad3({x, top, z}, {x + dir * 3.5, top, z}, {x + dir * 3.5, top - 2.5, z}, {x, top - 2.5, z}, FLAG_CLOTH)
}

draw_boards :: proc() {
	// Behind each goal line.
	for side in SIDES {
		z := side * (WORLD_HALF_L - BOARD_T / 2)
		n := int(math.ceil(2 * WORLD_HALF_W / BOARD_PANEL))
		for i in 0 ..< n {
			x0 := -WORLD_HALF_W + f32(i) * BOARD_PANEL
			x1 := min(x0 + BOARD_PANEL, WORLD_HALF_W)
			rl.DrawCubeV({(x0 + x1) / 2, BOARD_H / 2, z}, {x1 - x0 - 0.6, BOARD_H, BOARD_T}, BOARD_COLOURS[i % 4])
		}
	}
	// Along each touchline.
	for side in SIDES {
		x := side * (WORLD_HALF_W - BOARD_T / 2)
		n := int(math.ceil(2 * WORLD_HALF_L / BOARD_PANEL))
		for i in 0 ..< n {
			z0 := -WORLD_HALF_L + f32(i) * BOARD_PANEL
			z1 := min(z0 + BOARD_PANEL, WORLD_HALF_L)
			rl.DrawCubeV({x, BOARD_H / 2, (z0 + z1) / 2}, {BOARD_T, BOARD_H, z1 - z0 - 0.6}, BOARD_COLOURS[(i + 2) % 4])
		}
	}
}

draw_pitch :: proc() {
	DisableBackfaceCulling()

	DisableDepthTest()
	draw_grass()
	draw_markings()
	DrawRenderBatchActive()

	EnableDepthTest()
	draw_boards()
	for side in SIDES do draw_goal(side)
	for sx in SIDES {
		for sz in SIDES do draw_corner_flag(sx * HALF_W, sz * HALF_L)
	}
	DrawRenderBatchActive()

	EnableBackfaceCulling()
}
