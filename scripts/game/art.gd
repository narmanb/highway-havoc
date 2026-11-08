class_name Art
## Procedural, hand-authored 2.5D art. Every sprite in the game is drawn here with
## CanvasItem primitives, so the "source" for all art is this file.
##
## Projection: a slightly angled orthographic view. A point at ground position
## (x, y) and height z is drawn at (x, y - z). Boxes therefore show a top face and
## a front face, which gives the chunky, readable silhouettes the design calls for.

const OUTLINE := Color(0.07, 0.07, 0.10, 1.0)
const GLASS := Color("23324a")
const GLASS_HI := Color("4f6d93")
const SHADOW := Color(0, 0, 0, 0.26)
const SHADOW_SOFT := Color(0, 0, 0, 0.12)
const HEADLIGHT := Color("fff3c4")
const TAIL := Color("c3262e")
const TAIL_ON := Color("ff3b3b")
const TIRE := Color("17181d")
const HICON := Color("ffe640")

static var outline_mode := false   # high-contrast outlines setting


## Draws a box with ground footprint [x0,x1] x [y0,y1] from height z0 to z1.
static func box(ci: CanvasItem, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float,
		top: Color, front: Color, outline := true) -> void:
	var top_r := Rect2(x0, y0 - z1, x1 - x0, y1 - y0)
	var front_r := Rect2(x0, y1 - z1, x1 - x0, z1 - z0)
	if outline:
		ci.draw_rect(Rect2(x0 - 1.5, y0 - z1 - 1.5, x1 - x0 + 3.0, (y1 - y0) + (z1 - z0) + 3.0), OUTLINE)
	ci.draw_rect(top_r, top)
	ci.draw_rect(front_r, front)
	# Bevel highlight along the top edge of the front face.
	ci.draw_rect(Rect2(x0, y1 - z1, x1 - x0, 2.0), top.lightened(0.12))


static func shadow(ci: CanvasItem, x0: float, x1: float, cy: float, half_h: float, offset := Vector2(6, 8)) -> void:
	ci.draw_rect(Rect2(x0 + offset.x - 4.0, cy - half_h + offset.y - 2.0, x1 - x0 + 8.0, half_h * 2.0 + 6.0), SHADOW_SOFT)
	ci.draw_rect(Rect2(x0 + offset.x * 0.5, cy - half_h + offset.y * 0.6, x1 - x0, half_h * 2.0), SHADOW)


static func wheel(ci: CanvasItem, x: float, y: float, w := 16.0) -> void:
	ci.draw_rect(Rect2(x - w * 0.5, y - 9.0, w, 10.0), TIRE)
	ci.draw_rect(Rect2(x - w * 0.25, y - 7.0, w * 0.5, 4.0), Color("4a4d57"))


static func glow(ci: CanvasItem, pos: Vector2, radius: float, col: Color) -> void:
	for i in 3:
		var f := 1.0 - float(i) / 3.0
		ci.draw_circle(pos, radius * f, Color(col.r, col.g, col.b, col.a * (0.25 + 0.3 * float(i))))


# ------------------------------------------------------------------ vehicles

## cy: lane centre (ground). dir: +1 = travelling right.
static func vehicle(ci: CanvasItem, v, dir: int, cy: float, t: float, quality: int, flash_marker := false) -> void:
	var L: float = v.length
	var x0: float = v.x - L * 0.5
	var x1: float = v.x + L * 0.5
	var bob := sin(t * 9.0 + v.phase) * (0.8 if v.speed > 5.0 else 0.0)
	match v.kind:
		"car": _car(ci, v, dir, x0, x1, cy, bob, quality)
		"moto": _moto(ci, v, dir, x0, x1, cy, bob, t)
		"bus": _bus(ci, v, dir, x0, x1, cy, bob, quality)
		"truck": _truck(ci, v, dir, x0, x1, cy, bob, t, flash_marker)
	if outline_mode:
		var h: float = VehicleTypes.DEFS[v.kind]["height"] + 14.0
		ci.draw_rect(Rect2(x0 - 3, cy - 22 - h - 3, L + 6, 44 + h + 6), HICON, false, 3.0)


static func _lights(ci: CanvasItem, v, dir: int, x0: float, x1: float, y: float, h: float, quality: int) -> void:
	var front := x1 if dir > 0 else x0
	var rear := x0 if dir > 0 else x1
	var fs := -1.0 if dir > 0 else 1.0
	# Headlights and their beams on the asphalt.
	ci.draw_rect(Rect2(front + fs * 5.0 - 2.5, y - h, 5.0, 5.0), HEADLIGHT)
	if quality >= 1:
		var tip := front - fs * 70.0
		var beam := PackedVector2Array([Vector2(front, y - 16), Vector2(tip, y - 30), Vector2(tip, y + 10), Vector2(front, y + 4)])
		ci.draw_colored_polygon(beam, Color(1.0, 0.95, 0.7, 0.07))
	var tail := TAIL_ON if v.braking else TAIL
	ci.draw_rect(Rect2(rear - fs * 5.0 - 2.5, y - h, 5.0, 5.0), tail)
	if v.braking:
		glow(ci, Vector2(rear - fs * 3.0, y - h + 2.0), 13.0, Color(1, 0.15, 0.1, 0.35))


static func _car(ci: CanvasItem, v, dir: int, x0: float, x1: float, cy: float, bob: float, quality: int) -> void:
	var L := x1 - x0
	shadow(ci, x0, x1, cy, 20.0)
	wheel(ci, x0 + L * 0.2, cy + 21)
	wheel(ci, x1 - L * 0.2, cy + 21)
	var col: Color = v.color
	box(ci, x0, x1, cy - 20, cy + 20, 5 + bob, 15 + bob, col, col.darkened(0.3))
	# Cabin (greenhouse) sits toward the rear.
	var c0: float
	var c1: float
	if dir > 0:
		c0 = x0 + L * 0.16
		c1 = x1 - L * 0.34
	else:
		c0 = x0 + L * 0.34
		c1 = x1 - L * 0.16
	box(ci, c0, c1, cy - 16, cy + 16, 15 + bob, 27 + bob, col.lightened(0.12), GLASS)
	# Windshield on the roof's leading edge, rear window on trailing edge.
	var ws := c1 - 9.0 if dir > 0 else c0
	var rw := c0 if dir > 0 else c1 - 6.0
	ci.draw_rect(Rect2(ws, cy - 16 - 27 - bob, 9.0, 32.0), GLASS)
	ci.draw_rect(Rect2(ws + 2.0, cy - 14 - 27 - bob, 2.0, 12.0), GLASS_HI)
	ci.draw_rect(Rect2(rw, cy - 16 - 27 - bob, 6.0, 32.0), GLASS.lightened(0.05))
	# Side window highlight on the front face.
	ci.draw_rect(Rect2(c0 + 4.0, cy + 16 - 25 - bob, (c1 - c0) * 0.35, 3.0), GLASS_HI)
	# Door seam & handle.
	ci.draw_line(Vector2(v.x, cy + 20 - 14 - bob), Vector2(v.x, cy + 20 - 6 - bob), col.darkened(0.45), 1.5)
	_lights(ci, v, dir, x0, x1, cy + 20, 13 + bob, quality)


static func _bus(ci: CanvasItem, v, dir: int, x0: float, x1: float, cy: float, bob: float, quality: int) -> void:
	var L := x1 - x0
	shadow(ci, x0, x1, cy, 22.0, Vector2(8, 10))
	for wx in [x0 + 30.0, x0 + 52.0, x1 - 40.0]:
		wheel(ci, wx if dir > 0 else (x0 + x1 - wx), cy + 22, 18.0)
	var col: Color = v.color
	box(ci, x0, x1, cy - 21, cy + 21, 5 + bob, 36 + bob, Color("e9e6dc"), col)
	var top_y := cy - 21 - 36 - bob
	# Roof stripe and AC units.
	ci.draw_rect(Rect2(x0, top_y + 16, L, 10), col.lightened(0.1))
	for i in 2:
		var ax := x0 + L * (0.3 + 0.32 * i)
		ci.draw_rect(Rect2(ax - 14, top_y + 8, 28, 20), Color("b9b6ad"))
		ci.draw_rect(Rect2(ax - 10, top_y + 11, 20, 14), Color("8e8b83"))
	# Window band on the front face.
	var wy := cy + 21 - 33 - bob
	var n := int(L / 30.0)
	for i in n:
		var wx2 := x0 + 8.0 + i * (L - 16.0) / n
		ci.draw_rect(Rect2(wx2, wy, (L - 16.0) / n - 5.0, 12.0), GLASS)
		ci.draw_rect(Rect2(wx2 + 2, wy + 2, 3.0, 6.0), GLASS_HI)
	# Door
	var dx := x1 - 34.0 if dir > 0 else x0 + 20.0
	ci.draw_rect(Rect2(dx, wy, 14, 26), GLASS.darkened(0.2))
	# Route sign at the front of the roof.
	var sx := x1 - 22.0 if dir > 0 else x0 + 6.0
	ci.draw_rect(Rect2(sx, top_y + 2, 16, 8), Color("1b1b1b"))
	ci.draw_rect(Rect2(sx + 2, top_y + 4, 12, 4), Color("ffb000"))
	_lights(ci, v, dir, x0, x1, cy + 21, 12 + bob, quality)


static func _truck(ci: CanvasItem, v, dir: int, x0: float, x1: float, cy: float, bob: float, t: float, flash: bool) -> void:
	var L := x1 - x0
	var cab: float = VehicleTypes.DEFS["truck"]["cab"]
	shadow(ci, x0, x1, cy, 21.0, Vector2(8, 10))
	for wx in [x0 + 26.0, x0 + 50.0, x1 - 26.0]:
		wheel(ci, wx if dir > 0 else (x0 + x1 - wx), cy + 22, 18.0)
	var col: Color = v.color
	var cab_col := Color("e8463c")
	var cr := v.cargo_range(dir) as Vector2
	var k0: float
	var k1: float
	if dir > 0:
		k0 = cr.y + 3.0
		k1 = x1
	else:
		k0 = x0
		k1 = cr.x - 3.0
	# Cab
	box(ci, k0, k1, cy - 18, cy + 18, 5 + bob, 28 + bob, cab_col, cab_col.darkened(0.3))
	var ws := k1 - 12.0 if dir > 0 else k0 + 2.0
	ci.draw_rect(Rect2(ws, cy - 18 - 28 - bob, 10.0, 36.0), GLASS)
	ci.draw_rect(Rect2(k0 + 6.0, cy + 18 - 25 - bob, (k1 - k0) - 14.0, 9.0), GLASS)
	# Cargo box (rideable roof)
	box(ci, cr.x, cr.y, cy - 21, cy + 21, 5 + bob, 34 + bob, col, col.darkened(0.18))
	var roof_y := cy - 21 - 34 - bob
	# Brand stripe + parcel logo on the side.
	var fy := cy + 21 - 34 - bob
	ci.draw_rect(Rect2(cr.x, fy + 8, cr.y - cr.x, 6), Color("f2a33a"))
	var lx := (cr.x + cr.y) * 0.5
	ci.draw_rect(Rect2(lx - 9, fy + 16, 18, 12), Color("b97a43"))
	ci.draw_rect(Rect2(lx - 1.5, fy + 16, 3, 12), Color("f2d29b"))
	# Landing marker on the roof: a bright pad with chevrons in the travel direction.
	var pad_col := Color("ffd640")
	if flash and int(t * 8.0) % 2 == 0:
		pad_col = Color("ff4a3a")
	var pc := Vector2(lx, roof_y + 21)
	ci.draw_rect(Rect2(cr.x + 6, roof_y + 4, cr.y - cr.x - 12, 34), Color(0, 0, 0, 0.12))
	ci.draw_arc(pc, 15.0, 0, TAU, 24, pad_col, 3.0)
	for i in 2:
		var ox := (float(i) * 8.0 - 4.0) * dir
		var pts := PackedVector2Array([pc + Vector2(ox - 4 * dir, -7), pc + Vector2(ox + 4 * dir, 0), pc + Vector2(ox - 4 * dir, 7)])
		ci.draw_polyline(pts, pad_col, 3.0)
	_lights(ci, v, dir, x0, x1, cy + 21, 12 + bob, 1)


static func _moto(ci: CanvasItem, v, dir: int, x0: float, x1: float, cy: float, bob: float, t: float) -> void:
	var L := x1 - x0
	shadow(ci, x0 + 4, x1 - 4, cy, 9.0, Vector2(5, 6))
	wheel(ci, x0 + 10, cy + 10, 14.0)
	wheel(ci, x1 - 10, cy + 10, 14.0)
	var col: Color = v.color
	box(ci, x0 + 6, x1 - 6, cy - 6, cy + 6, 6 + bob, 14 + bob, col, col.darkened(0.3))
	# Rider: torso and helmet, leaning into the wind.
	var rx: float = v.x - 6.0 * dir
	box(ci, rx - 8, rx + 8, cy - 7, cy + 7, 14 + bob, 30 + bob, Color("34384a"), Color("23262f"))
	var hc := Vector2(rx + 5.0 * dir, cy - 34 - bob)
	ci.draw_circle(hc, 9.5, OUTLINE)
	ci.draw_circle(hc, 8.0, col.lightened(0.25))
	ci.draw_rect(Rect2(hc.x + (1.0 if dir > 0 else -7.0), hc.y - 3.0, 6.0, 5.0), GLASS)
	var front := x1 if dir > 0 else x0
	ci.draw_rect(Rect2(front - 4.0 * dir - 2.0, cy + 6 - 12 - bob, 4.0, 4.0), HEADLIGHT)


# ------------------------------------------------------------------ robot

## Draws the delivery robot with its feet at `origin`.
## facing: Vector2i(0,1)=away from camera (up), (0,-1)=toward camera, (+-1,0)=sideways.
static func robot(ci: CanvasItem, origin: Vector2, pal: Dictionary, facing: Vector2i, lift: float,
		squash: float, t: float, mood: String, shadow_on := true, roof := 0.0, sc := 1.0, ring := false) -> void:
	var body: Color = pal["body"]
	var accent: Color = pal["accent"]
	var eye: Color = pal["eye"]
	if shadow_on:
		var s := clampf(1.0 - lift / 70.0, 0.4, 1.0) * sc
		ci.draw_set_transform(origin + Vector2(3, 3 - roof), 0.0, Vector2(s, s * 0.45))
		if ring:
			# Bright findability ring under the robot.
			ci.draw_arc(Vector2(-3, -6), 30.0, 0, TAU, 32, Color(1, 1, 1, 0.55), 5.0)
		ci.draw_circle(Vector2.ZERO, 19.0, SHADOW)
		ci.draw_set_transform(Vector2.ZERO)
	var sx := 1.0 + squash * 0.25
	var sy := 1.0 - squash * 0.25
	ci.draw_set_transform(origin + Vector2(0, -lift - roof), 0.0, Vector2(sx, sy) * sc)
	var side := facing.x
	# Wheels / feet
	ci.draw_rect(Rect2(-15, -7, 11, 8), TIRE)
	ci.draw_rect(Rect2(4, -7, 11, 8), TIRE)
	# Backpack parcel behind (drawn first when facing the camera or sideways).
	var pack_col := Color("c8874a")
	var tape := Color("f3d7a0")
	if facing.y <= 0:
		var px := -side * 10.0
		_parcel(ci, Vector2(px, -40), Vector2(30, 22), pack_col, tape)
	# Body shell: front face + top face.
	ci.draw_rect(Rect2(-18.5, -42.5, 37, 39), OUTLINE)
	ci.draw_rect(Rect2(-17, -41, 34, 12), body.lightened(0.18))
	ci.draw_rect(Rect2(-17, -29, 34, 24), body)
	ci.draw_rect(Rect2(-17, -9, 34, 4), body.darkened(0.25))
	# Accent belt
	ci.draw_rect(Rect2(-17, -15, 34, 4), accent)
	if facing.y > 0:
		# Seen from behind: the big parcel covers the back.
		_parcel(ci, Vector2(0, -30), Vector2(30, 24), pack_col, tape)
	else:
		# Face screen
		var fx := side * 4.0
		ci.draw_rect(Rect2(-12 + fx, -28, 24, 13), Color("101622"))
		_eyes(ci, Vector2(fx, -21.5), eye, mood, t)
	# Antenna with blinking tip.
	var ax := -6.0 if side >= 0 else 6.0
	ci.draw_line(Vector2(ax, -42), Vector2(ax - side * 3.0, -54), OUTLINE, 3.0)
	var blink := 0.5 + 0.5 * sin(t * 6.0)
	ci.draw_circle(Vector2(ax - side * 3.0, -56), 4.0, OUTLINE)
	ci.draw_circle(Vector2(ax - side * 3.0, -56), 3.0, accent.lerp(Color.WHITE, blink * 0.5))
	ci.draw_set_transform(Vector2.ZERO)


static func _parcel(ci: CanvasItem, c: Vector2, size: Vector2, col: Color, tape: Color) -> void:
	var r := Rect2(c - size * 0.5, size)
	ci.draw_rect(r.grow(1.5), OUTLINE)
	ci.draw_rect(r, col)
	ci.draw_rect(Rect2(r.position, Vector2(size.x, 5)), col.lightened(0.15))
	ci.draw_rect(Rect2(c.x - 2, r.position.y, 4, size.y), tape)


static func _eyes(ci: CanvasItem, c: Vector2, col: Color, mood: String, t: float) -> void:
	var blink := fmod(t, 3.7) < 0.12
	match mood:
		"happy":
			for s in [-1.0, 1.0]:
				ci.draw_arc(c + Vector2(5.5 * s, 2), 3.5, PI, TAU, 8, col, 2.0)
		"dead":
			for s in [-1.0, 1.0]:
				var e := c + Vector2(5.5 * s, 0)
				ci.draw_line(e + Vector2(-3, -3), e + Vector2(3, 3), Color("ff5050"), 2.0)
				ci.draw_line(e + Vector2(-3, 3), e + Vector2(3, -3), Color("ff5050"), 2.0)
		"worried":
			for s in [-1.0, 1.0]:
				ci.draw_circle(c + Vector2(5.5 * s, 0.5), 3.2, col)
				ci.draw_line(c + Vector2(5.5 * s - 3, -5 + s), c + Vector2(5.5 * s + 3, -5 - s), col, 1.5)
		_:
			for s in [-1.0, 1.0]:
				if blink:
					ci.draw_line(c + Vector2(5.5 * s - 3, 0), c + Vector2(5.5 * s + 3, 0), col, 2.0)
				else:
					ci.draw_rect(Rect2(c.x + 5.5 * s - 2.5, c.y - 3, 5, 6), col)


# ------------------------------------------------------------------ props

static func tree(ci: CanvasItem, p: Vector2, seed_v: int) -> void:
	var g := Color("3f8f4a").lerp(Color("5aa846"), float(seed_v % 7) / 7.0)
	ci.draw_rect(Rect2(p.x - 20, p.y - 12, 40, 18), Color("8a7f6c"))
	ci.draw_rect(Rect2(p.x - 20, p.y - 16, 40, 6), Color("a39883"))
	ci.draw_rect(Rect2(p.x - 3, p.y - 30, 6, 18), Color("6b4a2f"))
	ci.draw_circle(Vector2(p.x + 4, p.y - 30), 22.0, Color(0, 0, 0, 0.18))
	ci.draw_circle(Vector2(p.x, p.y - 40), 22.0, OUTLINE)
	ci.draw_circle(Vector2(p.x, p.y - 40), 20.5, g.darkened(0.2))
	ci.draw_circle(Vector2(p.x - 5, p.y - 45), 14.0, g)
	ci.draw_circle(Vector2(p.x - 8, p.y - 49), 6.0, g.lightened(0.2))


static func lamp(ci: CanvasItem, p: Vector2, t: float, quality: int) -> void:
	ci.draw_rect(Rect2(p.x - 3, p.y - 70, 6, 72), Color("3a3f4b"))
	ci.draw_rect(Rect2(p.x - 6, p.y - 4, 12, 6), Color("2a2e38"))
	ci.draw_rect(Rect2(p.x - 3, p.y - 72, 22, 5), Color("3a3f4b"))
	ci.draw_rect(Rect2(p.x + 12, p.y - 70, 12, 5), Color("fff0b0"))
	if quality >= 1:
		glow(ci, Vector2(p.x + 18, p.y - 66), 18.0, Color(1, 0.95, 0.6, 0.18))


static func hydrant(ci: CanvasItem, p: Vector2) -> void:
	ci.draw_rect(Rect2(p.x - 9, p.y - 26, 18, 26), OUTLINE)
	ci.draw_rect(Rect2(p.x - 7.5, p.y - 24, 15, 23), Color("d8332f"))
	ci.draw_rect(Rect2(p.x - 12, p.y - 18, 24, 5), Color("b02824"))
	ci.draw_rect(Rect2(p.x - 6, p.y - 29, 12, 6), Color("e85a50"))


static func bench(ci: CanvasItem, p: Vector2) -> void:
	box(ci, p.x - 26, p.x + 26, p.y - 8, p.y + 4, 8, 12, Color("a8693a"), Color("7a4a28"))
	ci.draw_rect(Rect2(p.x - 26, p.y - 32, 52, 8), Color("a8693a"))
	ci.draw_rect(Rect2(p.x - 22, p.y - 24, 4, 20), Color("3a3f4b"))
	ci.draw_rect(Rect2(p.x + 18, p.y - 24, 4, 20), Color("3a3f4b"))


static func planter(ci: CanvasItem, p: Vector2, seed_v: int) -> void:
	box(ci, p.x - 28, p.x + 28, p.y - 22, p.y + 18, 0, 14, Color("b8b0a0"), Color("8e8676"))
	var g := Color("4c9a45")
	for i in 5:
		var ox := -18.0 + i * 9.0
		ci.draw_circle(Vector2(p.x + ox, p.y - 20 - (seed_v + i) % 3 * 2), 9.0, g.darkened(0.15 * (i % 2)))
	ci.draw_circle(Vector2(p.x - 6, p.y - 26), 3.0, Color("ff7aa8"))
	ci.draw_circle(Vector2(p.x + 10, p.y - 24), 3.0, Color("ffe066"))


static func kiosk(ci: CanvasItem, p: Vector2, col: Color) -> void:
	box(ci, p.x - 30, p.x + 30, p.y - 20, p.y + 14, 0, 40, Color("e8e2d2"), Color("cfc7b4"))
	# Striped awning
	for i in 6:
		ci.draw_rect(Rect2(p.x - 34 + i * 11.3, p.y + 14 - 46, 11.3, 10), col if i % 2 == 0 else Color.WHITE)
	ci.draw_rect(Rect2(p.x - 22, p.y + 14 - 30, 44, 18), Color("2b3446"))
	ci.draw_rect(Rect2(p.x - 18, p.y + 14 - 26, 12, 10), Color("ffd27a"))
