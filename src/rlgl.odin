package main

import rl "vendor:raylib"

// The handful of rlgl calls this program needs, bound directly against the
// system libraylib. nixpkgs' Odin patches vendor:raylib to link system raylib
// but strips the bundled static library that vendor:raylib/rlgl still names,
// so importing that package fails to link.
@(default_calling_convention = "c", link_prefix = "rl")
foreign rlgl_lib {
	Begin :: proc(mode: i32) ---
	End :: proc() ---
	Vertex3f :: proc(x, y, z: f32) ---
	Color4ub :: proc(r, g, b, a: u8) ---
	EnableDepthTest :: proc() ---
	DisableDepthTest :: proc() ---
	EnableBackfaceCulling :: proc() ---
	DisableBackfaceCulling :: proc() ---
	DrawRenderBatchActive :: proc() ---
	SetMatrixProjection :: proc(proj: rl.Matrix) ---
	SetMatrixModelview :: proc(view: rl.Matrix) ---
}

foreign import rlgl_lib "system:raylib"

QUADS :: 0x0007 // GL_QUADS, as rlgl defines it
