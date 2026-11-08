extends Node2D
## Dynamic, depth-sorted contents of one row: vehicles, props, pickups, signals.
## The node sits at the bottom edge of the vehicle footprint so Godot's y-sort puts
## lower rows (closer to the camera) in front of higher ones.

const SORT_OFFSET := C.LANE_HALF_H

var row: RowState
var game: Node


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	var cy := -SORT_OFFSET
	var t: float = game.anim_time
	var q: int = GameState.quality()
	var view_half: float = game.view_half_width() + 140.0
	if row.type == C.Row.ROAD:
		for col in row.pickups:
			_bolt(Vector2(C.col_to_x(col), cy), t)
		var lane := row.lane
		for v in lane.vehicles:
			if absf(v.x) - v.length * 0.5 > view_half:
				continue
			var flash := false
			if v.rideable() and game.is_riding(v.id):
				flash = game.ride_edge_warning()
			Art.vehicle(self, v, lane.dir, cy, t, q, flash)
		return
	# Safe rows: decorative props in the margins + blocking props in play cells.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(row.spec.get("deco_seed", 1))
	for col in row.spec.get("blocked", []):
		var p := Vector2(C.col_to_x(col), cy + 10)
		if row.type == C.Row.MEDIAN:
			Art.planter(self, p, col)
		elif (col + row.index) % 2 == 0:
			Art.tree(self, p, col + row.index)
		else:
			Art.planter(self, p, col)
	_margin_props(rng, cy, t, q, view_half)
	if row.signal_light != null:
		_signal_poles(row.signal_light, cy, t)
	if row.button_light != null:
		_button(row.button_light, cy, t)
	if row.is_goal and row.locker_col() >= 0:
		_locker(Vector2(C.col_to_x(row.locker_col()), cy - 6), t)


func _margin_props(rng: RandomNumberGenerator, cy: float, t: float, q: int, view_half: float) -> void:
	# Bollards mark the play boundary on safe rows.
	for s in [-1.0, 1.0]:
		var bx: float = s * (C.PLAY_HALF_W + 8.0)
		draw_rect(Rect2(bx - 5, cy - 6, 10, 18), Art.OUTLINE)
		draw_rect(Rect2(bx - 4, cy - 5, 8, 16), Color("f5c400"))
		draw_rect(Rect2(bx - 4, cy, 8, 4), Color("2b2b2b"))
	var x := C.PLAY_HALF_W + 60.0 + rng.randf_range(0, 60)
	var kind := rng.randi() % 5
	while x < view_half:
		for s in [-1.0, 1.0]:
			var p := Vector2(s * x, cy + 4)
			match (kind + int(s)) % 5:
				0: Art.tree(self, p, int(x))
				1: Art.lamp(self, p, t, q)
				2: Art.bench(self, p)
				3: Art.kiosk(self, p, [Color("e8504a"), Color("3fa7d6"), Color("6cc551")][int(x) % 3])
				_: Art.hydrant(self, p)
		x += rng.randf_range(110, 190)
		kind = rng.randi() % 5


func _bolt(p: Vector2, t: float) -> void:
	var y := p.y - 14 + sin(t * 4.0 + p.x) * 3.0
	draw_circle(Vector2(p.x + 3, p.y + 6), 8.0, Art.SHADOW)
	var r := 11.0
	var pts := PackedVector2Array()
	for i in 12:
		var a := t * 2.0 + i * TAU / 12.0
		var rr := r if i % 2 == 0 else r * 0.72
		pts.append(Vector2(p.x, y) + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(pts, Color("ffd23f"))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Art.OUTLINE, 1.5)
	draw_circle(Vector2(p.x, y), 4.0, Color("b07a10"))


func _button(light: TrafficLight, cy: float, t: float) -> void:
	var bx := light.x
	var p := Vector2(bx, cy + 8)
	var can_push := light.can_press()
	var col := Color("39d353") if can_push else Color("ffb000")
	if light.walk_safe():
		col = Color("ffffff")
	# Big hand icon on the pad.
	draw_circle(p, 17.0, Art.OUTLINE)
	draw_circle(p, 15.0, col)
	draw_rect(Rect2(p.x - 5, p.y - 9, 10, 14), Color("1d2230"))
	for i in 3:
		draw_rect(Rect2(p.x - 5 + i * 3.5, p.y - 13, 3, 6), Color("1d2230"))
	if can_push and not GameState.settings["reduced_flash"]:
		draw_arc(p, 20.0 + fmod(t * 20.0, 10.0), 0, TAU, 24, Color(col.r, col.g, col.b, 0.5), 2.0)


## Signal poles stand on the safe rows beside the crosswalk.
func _signal_poles(light: TrafficLight, cy: float, t: float) -> void:
	var px := light.x + C.TILE * 0.5 + 6.0
	var base := Vector2(px, cy + 6)
	draw_rect(Rect2(base.x - 3, base.y - 84, 6, 86), Color("2e323d"))
	draw_rect(Rect2(base.x - 6, base.y - 2, 12, 5), Color("20232b"))
	# Vehicle head: red / amber / green.
	var head := Rect2(base.x - 9, base.y - 116, 18, 46)
	draw_rect(head.grow(1.5), Art.OUTLINE)
	draw_rect(head, Color("1c1f27"))
	var st := light.state
	var flash_ok: bool = not GameState.settings["reduced_flash"]
	var cols := [Color("401512"), Color("3d2e0a"), Color("0f3317")]
	if st == TrafficLight.GREEN:
		cols[2] = Color("3dff6e")
	elif st == TrafficLight.AMBER:
		cols[1] = Color("ffbf1f")
	else:
		cols[0] = Color("ff3b30")
	for i in 3:
		var c := Vector2(base.x, base.y - 108 + i * 15)
		draw_circle(c, 6.0, cols[i])
		if cols[i].v > 0.9:
			Art.glow(self, c, 12.0, Color(cols[i].r, cols[i].g, cols[i].b, 0.35))
	# Pedestrian head: walking figure / hand.
	var ph := Rect2(base.x - 24, base.y - 66, 18, 20)
	draw_rect(ph.grow(1.5), Art.OUTLINE)
	draw_rect(ph, Color("1c1f27"))
	var pc := ph.get_center()
	if st == TrafficLight.WALK or (st == TrafficLight.WALK_ENDING and (not flash_ok or int(t * 6.0) % 2 == 0)):
		var wc := Color("f2f2f2") if st == TrafficLight.WALK else Color("ff8a3d")
		if st == TrafficLight.WALK_ENDING:
			_hand(pc, wc)
		else:
			draw_circle(pc + Vector2(0, -6), 2.5, wc)
			draw_line(pc + Vector2(0, -3), pc + Vector2(0, 3), wc, 2.5)
			draw_line(pc + Vector2(0, 3), pc + Vector2(-3, 8), wc, 2.0)
			draw_line(pc + Vector2(0, 3), pc + Vector2(3, 8), wc, 2.0)
			draw_line(pc + Vector2(-4, 0), pc + Vector2(4, -2), wc, 2.0)
	else:
		_hand(pc, Color("ff8a3d"))


func _hand(c: Vector2, col: Color) -> void:
	draw_rect(Rect2(c.x - 4, c.y - 3, 8, 9), col)
	for i in 3:
		draw_rect(Rect2(c.x - 4 + i * 3, c.y - 7, 2, 5), col)


func _locker(p: Vector2, t: float) -> void:
	# Parcel locker: the delivery destination.
	Art.box(self, p.x - 30, p.x + 30, p.y - 16, p.y + 4, 0, 56, Color("2d7dd2"), Color("1f5ea3"))
	var fy := p.y + 4 - 56
	for i in 3:
		for j in 2:
			draw_rect(Rect2(p.x - 26 + i * 18, fy + 6 + j * 22, 15, 19), Color("174a82"))
			draw_rect(Rect2(p.x - 15 + i * 18, fy + 14 + j * 22, 2, 4), Color("cfe3ff"))
	var bob := sin(t * 3.0) * 4.0
	var ap := Vector2(p.x, p.y - 96 + bob)
	draw_colored_polygon(PackedVector2Array([ap + Vector2(-14, -10), ap + Vector2(14, -10), ap + Vector2(0, 8)]), Color("ffd84a"))
	draw_polyline(PackedVector2Array([ap + Vector2(-14, -10), ap + Vector2(14, -10), ap + Vector2(0, 8), ap + Vector2(-14, -10)]), Art.OUTLINE, 2.0)
