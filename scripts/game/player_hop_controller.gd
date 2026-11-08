class_name PlayerHopController
extends Node2D
## Tile-to-tile hopping robot with input buffering, roof riding and honest collision.
##
## Collision rule (the whole game hinges on it): the robot's hitbox is a 40x36 box
## on its row. Animation height never matters. While hopping, the robot occupies its
## source row for the first half of the hop and its destination row for the second.
## Landing on a delivery-truck cargo roof mounts it; touching anything else that
## moves is a hit.

signal hop_started(from_row: int, to_row: int, dash: bool)
signal landed(row: int, x: float)
signal died(cause: String, vehicle)
signal mounted(vehicle)
signal roof_moved(dx: float)
signal bonked

enum S { IDLE, HOP, RIDE, DEAD }

const ROOF_Z := 34.0

var game: Node
var state := S.IDLE
var row := 0
var px := 0.0
var facing := Vector2i(0, 1)
var palette: Dictionary = {}

var ride_lane: LaneSim
var ride_vid := -1
var ride_offset := 0.0
var edge_warning := false

var hop_t := 0.0
var hop_dur := C.HOP_TIME
var hop_from_row := 0
var hop_to_row := 0
var hop_from_x := 0.0
var hop_to_x := 0.0
var hop_dash := false
var hop_on_roof := false
var hop_roof_from := 0.0
var queued: Array = []          # one buffered [dir, dash]

var squash := 0.0
var anim_t := 0.0
var mood := "normal"
var mood_timer := 0.0
var roof_z := 0.0
var stand_z := 0.0      # visual lift from standing on a planter box
var death_t := 0.0
var death_vel := Vector2.ZERO
var death_off := Vector2.ZERO
var death_spin := 0.0
var spawn_pop := 0.0


func respawn(r: int, x: float) -> void:
	state = S.IDLE
	row = r
	px = x
	facing = Vector2i(0, 1)
	queued.clear()
	ride_vid = -1
	ride_lane = null
	roof_z = 0.0
	rotation = 0.0
	death_off = Vector2.ZERO
	spawn_pop = 1.0
	mood = "normal"
	edge_warning = false
	_sync_node()


func is_riding() -> bool:
	return ride_vid >= 0 and (state == S.RIDE or (state == S.HOP and hop_on_roof))


func ride_vehicle() -> LaneSim.Vehicle:
	if ride_lane == null:
		return null
	return ride_lane.find_vehicle(ride_vid)


func set_mood(m: String, dur := 0.8) -> void:
	if state == S.DEAD:
		return
	mood = m
	mood_timer = dur


## Returns true when the move was started or buffered.
func try_move(d: Vector2i, dash := false) -> bool:
	if state == S.DEAD:
		return false
	if state == S.HOP:
		queued = [d, dash]
		return true
	return _start(d, dash)


func _bonk() -> void:
	squash = 0.5
	bonked.emit()


func _start(d: Vector2i, dash: bool) -> bool:
	if dash and not game.can_dash():
		dash = false
	var steps := 2 if dash else 1
	facing = d
	var cur_x := px
	if d.y != 0:
		var to_row := row + d.y * steps
		if to_row < game.min_row() or to_row > game.max_row():
			if dash and row + d.y >= game.min_row() and row + d.y <= game.max_row():
				return _start(d, false)  # not enough runway for a dash: do a normal hop
			_bonk()
			return false
		var rs: RowState = game.row_state(to_row)
		var tx: float
		if rs.safe():
			var c := C.x_to_col(cur_x)
			if rs.blocked(c):
				var alt := c + (1 if cur_x > C.col_to_x(c) else -1)
				if alt >= 0 and alt < C.COLS and not rs.blocked(alt) and absf(C.col_to_x(alt) - cur_x) < C.TILE * 0.8:
					c = alt
				else:
					_bonk()
					return false
			tx = C.col_to_x(c)
		else:
			tx = clampf(cur_x, -C.PLAY_HALF_W + C.TILE * 0.5, C.PLAY_HALF_W - C.TILE * 0.5)
		if is_riding():
			_leave_ride()
		_begin_hop(to_row, cur_x, tx, dash)
		return true

	# Lateral move.
	if state == S.RIDE:
		var v := ride_vehicle()
		if v != null:
			var cr: Vector2 = v.cargo_range(ride_lane.dir)
			var toff := ride_offset + d.x * C.TILE * steps
			var lo := cr.x + 10.0 - v.x
			var hi := cr.y - 10.0 - v.x
			if toff >= lo and toff <= hi:
				_begin_roof_hop(toff, dash)
				return true
			if d.x == ride_lane.dir and float(VehicleTypes.DEFS[v.kind]["cab"]) > 0.0:
				# Toward the cab: slide to the front edge of the cargo roof if there is room.
				var edge := hi if d.x > 0 else lo
				if absf(edge - ride_offset) > 12.0:
					_begin_roof_hop(edge, dash)
					return true
				_bonk()
				return false
			# Off the back of the truck (or either end of a floating platform).
			var tx2 := cur_x + d.x * C.TILE * steps
			if not C.in_play_x(tx2):
				_bonk()
				return false
			_leave_ride()
			_begin_hop(row, cur_x, tx2, dash)
			return true
	var rs2: RowState = game.row_state(row)
	var tx3: float
	if rs2.safe():
		var c2 := C.x_to_col(cur_x) + d.x * steps
		if c2 < 0 or c2 >= C.COLS or rs2.blocked(c2):
			if dash:
				return _start(d, false)
			_bonk()
			return false
		tx3 = C.col_to_x(c2)
	else:
		tx3 = cur_x + d.x * C.TILE * steps
		if not C.in_play_x(tx3):
			var edge2 := signf(d.x) * (C.PLAY_HALF_W - C.TILE * 0.5)
			if absf(edge2 - cur_x) > 8.0 and signf(edge2 - cur_x) == signf(d.x):
				tx3 = edge2
			else:
				_bonk()
				return false
	_begin_hop(row, cur_x, tx3, dash)
	return true


func _begin_hop(to_row: int, fx: float, tx: float, dash: bool) -> void:
	state = S.HOP
	hop_on_roof = false
	hop_t = 0.0
	hop_dash = dash
	hop_dur = C.DASH_TIME if dash else C.HOP_TIME
	hop_from_row = row
	hop_to_row = to_row
	hop_from_x = fx
	hop_to_x = tx
	hop_roof_from = roof_z
	squash = -0.6
	hop_started.emit(row, to_row, dash)


func _begin_roof_hop(toff: float, dash: bool) -> void:
	state = S.HOP
	hop_on_roof = true
	hop_t = 0.0
	hop_dash = dash
	hop_dur = C.DASH_TIME if dash else C.HOP_TIME
	hop_from_row = row
	hop_to_row = row
	hop_from_x = ride_offset
	hop_to_x = toff
	hop_roof_from = ROOF_Z
	squash = -0.6
	hop_started.emit(row, row, dash)


func _leave_ride() -> void:
	ride_vid = -1
	ride_lane = null
	edge_warning = false


## Row whose traffic can currently hit the robot, or -1 while airborne mid-dash.
func collision_row() -> int:
	if state != S.HOP:
		return row
	if hop_dash and hop_from_row != hop_to_row:
		if hop_t < 0.25:
			return hop_from_row
		if hop_t < 0.75:
			return -1
		return hop_to_row
	return hop_from_row if hop_t < 0.5 else hop_to_row


func update(dt: float) -> void:
	anim_t += dt
	squash = move_toward(squash, 0.0, dt * 6.0)
	spawn_pop = maxf(0.0, spawn_pop - dt * 4.0)
	if mood_timer > 0.0:
		mood_timer -= dt
		if mood_timer <= 0.0 and state != S.DEAD:
			mood = "normal"
	if state == S.IDLE:
		stand_z = move_toward(stand_z, game.stand_height(row, px), dt * 200.0)
	elif state == S.HOP and not hop_on_roof:
		var k0 := minf(hop_t, 1.0)
		stand_z = lerpf(game.stand_height(hop_from_row, hop_from_x), game.stand_height(hop_to_row, hop_to_x), k0)
	else:
		stand_z = 0.0
	match state:
		S.RIDE:
			_follow_ride()
			roof_z = move_toward(roof_z, ROOF_Z, dt * 500.0)
		S.HOP:
			hop_t += dt / hop_dur
			var k := minf(hop_t, 1.0)
			if hop_on_roof:
				var v := ride_vehicle()
				if v == null:
					_leave_ride()
					hop_on_roof = false
					hop_from_x = px
					hop_to_x = px
				else:
					px = v.x + lerpf(hop_from_x, hop_to_x, k)
					roof_moved.emit(v.x - v.prev_x)
					_check_edge(v)
			else:
				px = lerpf(hop_from_x, hop_to_x, k)
				roof_z = lerpf(hop_roof_from, 0.0, k)
			if hop_t >= 1.0:
				_land()
		S.DEAD:
			death_t += dt
			death_vel.y += 1400.0 * dt
			death_off += death_vel * dt
			if death_off.y > 0.0 and death_t > 0.2:
				death_off.y = 0.0
				death_vel = Vector2(death_vel.x * 0.5, -death_vel.y * 0.35)
			rotation += death_spin * dt
			death_spin *= 0.98
	_sync_node()


func _follow_ride() -> void:
	var v := ride_vehicle()
	if v == null:
		_leave_ride()
		state = S.IDLE
		return
	px = v.x + ride_offset
	roof_moved.emit(v.x - v.prev_x)
	_check_edge(v)


func _check_edge(v) -> void:
	var lim := C.PLAY_HALF_W - C.TILE * 0.5
	var outward := signf(px) == float(ride_lane.dir)
	edge_warning = outward and absf(px) > lim - C.TILE * 1.3
	if edge_warning:
		set_mood("worried", 0.2)
	if absf(px) > lim + 30.0:
		_die("carried", v)


func _land() -> void:
	row = hop_to_row
	squash = 0.7
	if hop_on_roof:
		ride_offset = hop_to_x
		state = S.RIDE
		hop_on_roof = false
		_after_land()
		return
	px = hop_to_x
	state = S.IDLE
	var rs: RowState = game.row_state(row)
	if rs != null and rs.lane != null:
		var lane := rs.lane
		var a := px - C.PLAYER_HALF_W
		var b := px + C.PLAYER_HALF_W
		var truck = _mountable(lane)
		if truck != null and lane.solid_overlapping(a, b) == null:
			_mount(lane, truck)
		elif rs.is_water():
			_die("splash", null)
			return
		else:
			var v = lane.vehicle_overlapping(a, b)
			if v != null:
				_die("splat", v)
				return
	landed.emit(row, px)
	_after_land()


func _after_land() -> void:
	if state != S.DEAD and not queued.is_empty():
		var q := queued
		queued = []
		try_move(q[0], q[1])


func _mountable(lane: LaneSim):
	for v in lane.vehicles:
		if not v.rideable():
			continue
		var r: Vector2 = v.cargo_range(lane.dir)
		if px >= r.x - 4.0 and px <= r.y + 4.0:
			return v
	return null


func _mount(lane: LaneSim, v) -> void:
	var r: Vector2 = v.cargo_range(lane.dir)
	state = S.RIDE
	ride_lane = lane
	ride_vid = v.id
	ride_offset = clampf(px, r.x + 10.0, r.y - 10.0) - v.x
	px = v.x + ride_offset
	mounted.emit(v)


## Called by the game each frame after traffic and the robot have moved.
func check_collision() -> void:
	if state == S.DEAD or is_riding():
		return
	var r := collision_row()
	if r < 0:
		return
	var rs: RowState = game.row_state(r)
	if rs == null or rs.lane == null:
		return
	if rs.is_water():
		# Standing in water (not on a deck) is only possible if the deck left: splash.
		if state == S.IDLE:
			_die("splash", null)
		return
	var lane := rs.lane
	var a := px - C.PLAYER_HALF_W
	var b := px + C.PLAYER_HALF_W
	var v
	if state == S.HOP and hop_t >= 0.5:
		v = lane.solid_overlapping(a, b)   # arriving: a cargo roof under us will be mounted
	else:
		v = lane.vehicle_overlapping(a, b)
	if v != null:
		_die("hit", v)


func _die(cause: String, v) -> void:
	var push := 1.0
	if v != null and ride_lane != null:
		push = float(ride_lane.dir)
	elif v != null:
		var rs: RowState = game.row_state(collision_row() if collision_row() >= 0 else row)
		if rs != null and rs.lane != null:
			push = float(rs.lane.dir)
	if state == S.HOP and not hop_on_roof:
		row = hop_from_row if hop_t < 0.5 else hop_to_row
	state = S.DEAD
	queued.clear()
	_leave_ride()
	death_t = 0.0
	death_off = Vector2(0, -roof_z)
	roof_z = 0.0
	death_vel = Vector2(push * 340.0, -520.0)
	death_spin = push * 16.0
	if cause == "splash":
		death_vel = Vector2(0.0, -260.0)
		death_spin = 3.0
	mood = "dead"
	died.emit(cause, v)


func _sync_node() -> void:
	var y: float
	if state == S.HOP and not hop_on_roof:
		var k := minf(hop_t, 1.0)
		y = lerpf(C.row_to_y(hop_from_row), C.row_to_y(hop_to_row), k)
	else:
		y = C.row_to_y(row)
	var bias := 30.0 if (is_riding() or roof_z > 1.0 or stand_z > 1.0) else C.PLAYER_HALF_H
	position = Vector2(px, y + bias) + death_off
	set_meta("bias", bias)
	queue_redraw()


func _draw() -> void:
	var bias: float = get_meta("bias", C.PLAYER_HALF_H)
	var lift := 0.0
	if state == S.HOP:
		var k := minf(hop_t, 1.0)
		lift = sin(k * PI) * (C.DASH_HEIGHT if hop_dash else C.HOP_HEIGHT)
	var rz := roof_z + stand_z
	if state == S.HOP and hop_on_roof:
		rz = ROOF_Z
	Art.robot(self, Vector2(0, -bias), palette, facing, lift, squash - spawn_pop * 0.8, anim_t, mood,
		state != S.DEAD, rz, 1.22, true)
