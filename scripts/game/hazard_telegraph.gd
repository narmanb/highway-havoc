class_name HazardTelegraph
extends Node2D
## Makes danger announce itself:
##  * edge chevrons for vehicles about to enter the screen (sized by vehicle),
##  * crosswalk countdown rings (WAIT / WALK / hurry),
##  * safe-exit arrows above and below the robot while it rides a roof.

const LOOKAHEAD_S := 1.3

var game: Node


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var vr: Rect2 = game.camera.visible_rect()
	var t: float = game.anim_time
	var flash_ok: bool = not GameState.settings["reduced_flash"]
	for r in game.rows.values():
		var rs: RowState = r
		var y := C.row_to_y(rs.index)
		if y < vr.position.y - 40 or y > vr.end.y + 40:
			continue
		if rs.type == C.Row.ROAD:
			_edge_arrows(rs, vr, y, t, flash_ok)
		if rs.button_light != null:
			_crosswalk_timer(rs.button_light, y, t, flash_ok)
	_ride_hints()


func _edge_arrows(rs: RowState, vr: Rect2, y: float, t: float, flash_ok: bool) -> void:
	var lane := rs.lane
	var edge_x := vr.position.x if lane.dir > 0 else vr.end.x
	for v in lane.vehicles:
		var front: float = v.x + v.length * 0.5 * lane.dir
		var dist: float = (edge_x - front) * lane.dir
		if dist <= 0.0 or dist > maxf(v.speed, 60.0) * LOOKAHEAD_S:
			continue
		var urgency := 1.0 - dist / (maxf(v.speed, 60.0) * LOOKAHEAD_S)
		var ax := edge_x + 16.0 * lane.dir
		var big: bool = v.kind == "bus" or v.kind == "truck"
		var s := 10.0 if big else 7.0
		var a := 0.45 + 0.55 * urgency
		if flash_ok and urgency > 0.6:
			a *= 0.7 + 0.3 * sin(t * 20.0)
		var col := Color(1.0, 0.85 - 0.5 * urgency, 0.2, a)
		var d := float(lane.dir)
		for k in (2 if big else 1):
			var ox := ax + k * 10.0 * d
			var pts := PackedVector2Array([Vector2(ox - s * d, y - s), Vector2(ox + s * 0.6 * d, y), Vector2(ox - s * d, y + s)])
			draw_polyline(pts, Color(0, 0, 0, a * 0.6), 7.0)
			draw_polyline(pts, col, 4.0)
		break


func _crosswalk_timer(light: TrafficLight, y: float, t: float, flash_ok: bool) -> void:
	if light.state == TrafficLight.GREEN:
		return
	var c := Vector2(light.x, y - 58)
	draw_circle(c, 17.0, Color(0.05, 0.06, 0.1, 0.75))
	match light.state:
		TrafficLight.AMBER, TrafficLight.CLEARING:
			var spin := t * 6.0
			draw_arc(c, 13.0, spin, spin + PI * 1.3, 16, Color("ffbf1f"), 4.0)
		TrafficLight.WALK, TrafficLight.WALK_ENDING:
			var frac := light.walk_progress()
			var col := Color.WHITE if light.state == TrafficLight.WALK else Color("ff8a3d")
			if light.state == TrafficLight.WALK_ENDING and flash_ok and int(t * 8.0) % 2 == 0:
				col = Color("ff3b30")
			draw_arc(c, 13.0, -PI * 0.5, -PI * 0.5 + TAU * frac, 24, col, 4.0)
			draw_circle(c, 5.0, col)


func _ride_hints() -> void:
	var p: PlayerHopController = game.player
	if p == null or not p.is_riding() or p.state == PlayerHopController.S.DEAD:
		return
	for d: int in [1, -1]:
		var r: int = p.row + d
		if r < game.min_row() or r > game.max_row():
			continue
		var rs: RowState = game.row_state(r)
		if rs == null:
			continue
		var ok := true
		if rs.type == C.Row.ROAD:
			var pad: float = 30.0 + rs.lane.speed * C.HOP_TIME
			ok = rs.lane.solid_overlapping(p.px - C.PLAYER_HALF_W - pad, p.px + C.PLAYER_HALF_W + pad) == null
			if not ok and rs.lane.cargo_at(p.px) != null:
				ok = true
		elif rs.blocked(C.x_to_col(p.px)):
			ok = false
		var y: float = C.row_to_y(p.row) - 34.0 - d * 50.0
		var col := Color("3dff6e") if ok else Color("ff3b30")
		var tip: Vector2 = Vector2(p.px, y - d * 9.0)
		var pts := PackedVector2Array([Vector2(p.px - 10, y + d * 5.0), tip, Vector2(p.px + 10, y + d * 5.0)])
		draw_polyline(pts, Color(0, 0, 0, 0.6), 7.0)
		draw_polyline(pts, col, 4.0)
