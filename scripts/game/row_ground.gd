extends Node2D
## Static ground art for one row (asphalt, sidewalk, median). Drawn once and cached
## by the renderer, so even a tall phone full of rows costs almost nothing per frame.

const HALF := C.TILE * 0.5
const W := 1500.0

const ASPHALT := Color("3a3e49")
const CONCRETE := Color("cdc6b6")
const CURB := Color("9c968a")
const GRASS := Color("5e9a4c")

var row: RowState


func _draw() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(row.spec.get("deco_seed", row.index * 7919))
	match row.type:
		C.Row.ROAD: _road(rng)
		C.Row.SIDEWALK: _sidewalk(rng)
		C.Row.MEDIAN: _median(rng)
	# Dim everything outside the playable columns so the bounds read instantly.
	var shade := Color(0.05, 0.06, 0.12, 0.22)
	draw_rect(Rect2(-W, -HALF, W - C.PLAY_HALF_W, C.TILE), shade)
	draw_rect(Rect2(C.PLAY_HALF_W, -HALF, W - C.PLAY_HALF_W, C.TILE), shade)


func _road(rng: RandomNumberGenerator) -> void:
	var base := ASPHALT.lerp(Color("444855"), rng.randf() * 0.5)
	draw_rect(Rect2(-W, -HALF, W * 2.0, C.TILE), base)
	# Aggregate speckle texture.
	for i in 260:
		var p := Vector2(rng.randf_range(-W, W), rng.randf_range(-HALF + 2, HALF - 2))
		var c := base.lightened(0.12) if rng.randf() < 0.5 else base.darkened(0.15)
		draw_rect(Rect2(p, Vector2(2, 2)), c)
	# Tyre polish bands where wheels run.
	draw_rect(Rect2(-W, -HALF + 18, W * 2.0, 6), Color(0, 0, 0, 0.07))
	draw_rect(Rect2(-W, HALF - 22, W * 2.0, 6), Color(0, 0, 0, 0.07))
	# Cracks, patches, manholes, oil stains.
	for i in 6:
		var p2 := Vector2(rng.randf_range(-W, W), rng.randf_range(-20, 20))
		var pts := PackedVector2Array([p2])
		for k in 4:
			p2 += Vector2(rng.randf_range(6, 16), rng.randf_range(-6, 6))
			pts.append(p2)
		draw_polyline(pts, base.darkened(0.35), 1.5)
	for i in 3:
		var p3 := Vector2(rng.randf_range(-W, W), rng.randf_range(-14, 14))
		draw_rect(Rect2(p3, Vector2(rng.randf_range(30, 70), rng.randf_range(14, 24))), base.darkened(0.08))
	if rng.randf() < 0.6:
		var m := Vector2(rng.randf_range(-C.PLAY_HALF_W, C.PLAY_HALF_W), rng.randf_range(-10, 10))
		draw_circle(m, 13.0, Color("2b2e36"))
		draw_arc(m, 11.0, 0, TAU, 16, Color("555a66"), 2.0)
		draw_line(m + Vector2(-8, 0), m + Vector2(8, 0), Color("555a66"), 1.5)
	for i in 2:
		var o := Vector2(rng.randf_range(-W, W), rng.randf_range(-12, 12))
		draw_circle(o, rng.randf_range(8, 14), Color(0.05, 0.05, 0.08, 0.35))
	# Painted direction chevrons (faint): readable hint of which way traffic flows.
	var dir: int = row.spec["dir"]
	var off := rng.randf_range(0, 300)
	var x := -W + off
	while x < W:
		var c2 := Color(1, 1, 1, 0.13)
		for k in 2:
			var cx := x + k * 16.0 * dir
			draw_polyline(PackedVector2Array([Vector2(cx - 8 * dir, -12), Vector2(cx + 4 * dir, 0), Vector2(cx - 8 * dir, 12)]), c2, 4.0)
		x += 420.0
	# Lane boundary with the row above.
	var ab := row.above
	if ab != null and ab.type == C.Row.ROAD:
		if int(ab.spec["dir"]) == dir:
			var dx := -W + fmod(float(row.index) * 37.0, 48.0)
			while dx < W:
				var worn := rng.randf()
				var a := 0.8 if worn > 0.15 else 0.35
				draw_rect(Rect2(dx, -HALF - 2, 28, 4), Color(0.95, 0.95, 0.9, a))
				dx += 48.0
		else:
			draw_rect(Rect2(-W, -HALF - 4, W * 2.0, 3), Color("f2c230"))
			draw_rect(Rect2(-W, -HALF + 1, W * 2.0, 3), Color("f2c230"))
	elif ab != null:
		draw_rect(Rect2(-W, -HALF + 3, W * 2.0, 3), Color(1, 1, 1, 0.75))
	if row.below != null and row.below.type != C.Row.ROAD:
		draw_rect(Rect2(-W, HALF - 6, W * 2.0, 3), Color(1, 1, 1, 0.75))
	# Crosswalk and stop line for signal-controlled lanes.
	if row.light != null:
		var cxw: float = row.light.x
		for k in 4:
			draw_rect(Rect2(cxw - 30, -HALF + 4 + k * 17.0, 60, 10), Color(0.96, 0.96, 0.92, 0.85))
		var sx := row.lane.stop_line_f() * dir
		draw_rect(Rect2(sx - 3 if dir > 0 else sx - 3, -HALF + 2, 6, C.TILE - 4), Color(0.96, 0.96, 0.92, 0.9))


func _sidewalk(rng: RandomNumberGenerator) -> void:
	draw_rect(Rect2(-W, -HALF, W * 2.0, C.TILE), CONCRETE)
	# Paving slabs.
	var slab := 36.0
	var x := -W
	while x < W:
		var shade := rng.randf_range(-0.04, 0.04)
		draw_rect(Rect2(x + 1, -HALF + 7, slab - 2, slab - 6), CONCRETE.lightened(shade) if shade > 0 else CONCRETE.darkened(-shade))
		draw_rect(Rect2(x + 1, -HALF + 7 + slab - 4, slab - 2, slab - 10), CONCRETE.darkened(0.03 + shade * 0.5))
		x += slab
	for i in 10:
		draw_rect(Rect2(rng.randf_range(-W, W), rng.randf_range(-20, 20), 3, 2), CONCRETE.darkened(0.25))
	# Curbs: top lip and front face toward the road below.
	draw_rect(Rect2(-W, -HALF, W * 2.0, 6), CURB.lightened(0.15))
	draw_rect(Rect2(-W, HALF - 7, W * 2.0, 7), CURB.darkened(0.15))
	draw_rect(Rect2(-W, HALF - 9, W * 2.0, 2), CURB.lightened(0.25))
	# Delivery goal styling: yellow-black hazard edge and a glowing doorstep pad.
	if row.is_goal:
		var hx := -C.PLAY_HALF_W
		var k := 0
		while hx < C.PLAY_HALF_W:
			draw_rect(Rect2(hx, HALF - 13, 18, 4), Color("f5c400") if k % 2 == 0 else Color("2b2b2b"))
			hx += 18.0
			k += 1
		var lc := row.locker_col()
		if lc >= 0:
			var lx := C.col_to_x(lc)
			draw_rect(Rect2(lx - 32, -HALF + 8, 64, C.TILE - 18), Color("ffd84a"))
			draw_rect(Rect2(lx - 28, -HALF + 12, 56, C.TILE - 26), Color("ffe98c"))
	# Push-button pad at the foot of a crosswalk.
	var bc := row.button_col()
	if bc >= 0:
		var bx := C.col_to_x(bc)
		draw_rect(Rect2(bx - 30, -HALF + 8, 60, C.TILE - 16), Color("f2d36b"))
		for yy in range(-24, 25, 8):
			for xx in range(-24, 25, 8):
				draw_circle(Vector2(bx + xx, yy), 1.6, Color("c9a33a"))


func _median(rng: RandomNumberGenerator) -> void:
	draw_rect(Rect2(-W, -HALF, W * 2.0, C.TILE), Color("bdb6a6"))
	draw_rect(Rect2(-W, -HALF + 10, W * 2.0, C.TILE - 22), GRASS)
	for i in 160:
		var p := Vector2(rng.randf_range(-W, W), rng.randf_range(-HALF + 12, HALF - 14))
		draw_rect(Rect2(p, Vector2(2, 3)), GRASS.lightened(0.15) if rng.randf() < 0.6 else GRASS.darkened(0.2))
	for i in 14:
		var f := Vector2(rng.randf_range(-W, W), rng.randf_range(-HALF + 14, HALF - 16))
		draw_circle(f, 2.0, [Color("ffe066"), Color("ff8fb1"), Color.WHITE][i % 3])
	draw_rect(Rect2(-W, -HALF, W * 2.0, 5), CURB.lightened(0.2))
	draw_rect(Rect2(-W, HALF - 12, W * 2.0, 5), CURB.lightened(0.2))
	draw_rect(Rect2(-W, HALF - 7, W * 2.0, 7), CURB.darkened(0.15))
	var bc := row.button_col()
	if bc >= 0:
		var bx := C.col_to_x(bc)
		draw_rect(Rect2(bx - 30, -HALF + 8, 60, C.TILE - 16), Color("f2d36b"))
		for yy in range(-24, 25, 8):
			for xx in range(-24, 25, 8):
				draw_circle(Vector2(bx + xx, yy), 1.6, Color("c9a33a"))
