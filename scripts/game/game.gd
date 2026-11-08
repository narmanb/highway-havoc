class_name Game
extends Node2D
## Gameplay controller: owns the segment chain (LaneManager role), steps traffic,
## routes input to the robot, scores, and talks to the HUD.
##
## Frame order: signals -> traffic lanes -> robot -> collision -> near-miss -> camera.

signal game_over(summary: Dictionary)
signal pause_requested
signal delivered(info: Dictionary)

const RUSH_DELIVERIES := 5
const RUSH_TIME := 100.0
const RUSH_OBJECTIVES := [
	{"id": "no_dash", "text": "Deliver without using dash"},
	{"id": "ride_2", "text": "Ride 2 truck roofs"},
	{"id": "near_3", "text": "Score 3 close calls"},
	{"id": "signal", "text": "Use a crosswalk signal"},
]

var mode := "arcade"            # arcade | rush | attract
var run_seed := 0
var score := ScoreAndStreak.new()
var lives := 3
var max_lives := 3
var dash_charges := 2
var bolts := 0
var segments: Array = []
var cur := 0
var rows := {}
var anim_time := 0.0
var crossing_time := 0.0
var par_time := 10.0
var rush_time := RUSH_TIME
var objective: Dictionary = {}
var last_safe_row := 0
var last_safe_col := C.CENTER_COL
var respawn_timer := -1.0
var over := false
var has_moved := false
var hit_stop := 0.0
var _nm := {"row": -999, "x": 0.0, "t": -10.0}
var _task_id := -1
var _task_result: Dictionary = {}
var _task_args: Array = []
var _attract_timer := 4.0

var ground_root: Node2D
var entities: Node2D
var fx: FXPool
var telegraph: HazardTelegraph
var camera: CameraRig
var player: PlayerHopController
var input: InputRouter


func setup(p_mode: String) -> void:
	mode = p_mode
	process_mode = Node.PROCESS_MODE_PAUSABLE
	ground_root = Node2D.new()
	ground_root.name = "Ground"
	ground_root.z_index = -10
	add_child(ground_root)
	fx = FXPool.new()
	fx.decals = FXPool.Decals.new()
	fx.decals.z_index = -5
	add_child(fx.decals)
	entities = Node2D.new()
	entities.name = "Entities"
	entities.y_sort_enabled = true
	add_child(entities)
	fx.z_index = 5
	add_child(fx)
	telegraph = HazardTelegraph.new()
	telegraph.game = self
	telegraph.z_index = 6
	add_child(telegraph)
	camera = CameraRig.new()
	add_child(camera)
	camera.make_current()
	input = InputRouter.new()
	add_child(input)
	input.move.connect(_on_move)
	input.dash.connect(_on_dash)
	input.brake.connect(_on_brake)
	input.player_screen_pos = _player_screen_pos
	input.pause_pressed.connect(func(): if not over and mode != "attract": pause_requested.emit())
	Art.outline_mode = GameState.settings["outlines"]

	if mode == "rush":
		var d := Time.get_date_dict_from_system()
		run_seed = hash([d["year"], d["month"], d["day"], "rush"])
		var orng := RandomNumberGenerator.new()
		orng.seed = run_seed
		objective = RUSH_OBJECTIVES[orng.randi() % RUSH_OBJECTIVES.size()].duplicate()
	else:
		run_seed = randi()
	max_lives = 1 if (GameState.settings["hardcore"] and mode == "arcade") else 3
	lives = max_lives
	dash_charges = 2

	var srng := RandomNumberGenerator.new()
	srng.seed = run_seed
	var start := RoadGenerator.make_start_row(srng)
	_create_segment(_generate(0, start))
	_create_segment(_generate(1, segments[0]["spec"]["rows"].back()))
	par_time = segments[0]["spec"]["par_time"]
	_create_backdrop_rows(srng)

	if mode != "attract":
		player = PlayerHopController.new()
		player.game = self
		player.palette = GameState.palette()
		entities.add_child(player)
		player.hop_started.connect(_on_hop_started)
		player.landed.connect(_on_landed)
		player.died.connect(_on_died)
		player.mounted.connect(_on_mounted)
		player.roof_moved.connect(func(dx): score.add_roof_distance(dx))
		player.bonked.connect(func(): Audio.play("bonk", 0.1))
		player.respawn(0, C.col_to_x(C.CENTER_COL))
		camera.snap_to(C.row_to_y(0))
	else:
		input.enabled = false
		camera.snap_to(C.row_to_y(2))


# ------------------------------------------------------------ segments

func _level_for(index: int) -> int:
	return index + 2 if mode == "rush" else index + 1


func _template_for(index: int) -> String:
	if index == 0 and mode != "rush":
		return RoadGenerator.INTRO_TEMPLATE
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, index, "tmpl"])
	var prev := ""
	if index > 0 and segments.size() >= index:
		prev = segments[index - 1]["spec"]["template"]
	var rot: Array = RoadGenerator.DISTRICTS[RoadGenerator.district_for(index, mode)]["rotation"]
	var pick: String = rot[rng.randi() % rot.size()]
	if pick == prev:
		pick = rot[(rot.find(pick) + 1) % rot.size()]
	return pick


func _generate(index: int, start_row: Dictionary) -> Dictionary:
	return RoadGenerator.generate(run_seed, index, _level_for(index), _template_for(index), start_row)


## Kick off background generation of the next segment (validation can take a moment).
func _request_next_segment() -> void:
	if _task_id != -1:
		return
	var index := segments.size()
	var start_copy: Dictionary = (segments.back()["spec"]["rows"].back() as Dictionary).duplicate(true)
	_task_args = [index, _level_for(index), _template_for(index), start_copy]
	_task_id = WorkerThreadPool.add_task(_task_body)


func _task_body() -> void:
	_task_result = RoadGenerator.generate(run_seed, _task_args[0], _task_args[1], _task_args[2], _task_args[3])


func _finish_task(block: bool) -> void:
	if _task_id == -1:
		return
	if not block and not WorkerThreadPool.is_task_completed(_task_id):
		return
	WorkerThreadPool.wait_for_task_completion(_task_id)
	_task_id = -1
	var spec := _task_result
	# Merge the generator's edits to the shared start row back into the live dictionary.
	var live: Dictionary = segments.back()["spec"]["rows"].back()
	var gen: Dictionary = spec["rows"][0]
	live["button"] = gen.get("button", -1)
	live["blocked"] = gen.get("blocked", [])
	live["planters"] = gen.get("planters", [])
	spec["rows"][0] = live
	_create_segment(spec)


func _create_segment(spec: Dictionary) -> void:
	var k := segments.size()
	var base := 0 if k == 0 else int(segments[k - 1]["goal"])
	var srows: Array = spec["rows"]
	var seg := {"spec": spec, "base": base, "goal": base + srows.size() - 1, "light": null}
	for i in srows.size():
		var wr := base + i
		var rs: RowState
		if i == 0 and rows.has(wr):
			rs = rows[wr]
		else:
			rs = RowState.new()
			rs.index = wr
			rs.spec = srows[i]
			rs.type = int(srows[i]["type"])
			rs.seg = k
			if rs.type == C.Row.ROAD:
				var l := LaneSim.new()
				var r: Dictionary = srows[i]
				l.setup(r["dir"], r["speed"], r["mix"], r["gap_min"], r["gap_max"], r["seed"])
				l.prewarm()
				rs.lane = l
			rows[wr] = rs
		if i == srows.size() - 1:
			rs.is_goal = true
	for i in srows.size():
		var wr := base + i
		rows[wr].above = rows.get(wr + 1)
		rows[wr].below = rows.get(wr - 1)
	var ld: Dictionary = spec["light"]
	if not ld.is_empty():
		var lanes: Array = []
		for li in ld["lanes"]:
			lanes.append(rows[base + int(li)].lane)
			rows[base + int(li)].light = null
		var tl := TrafficLight.new()
		tl.setup(int(ld["column"]), lanes)
		for li in ld["lanes"]:
			rows[base + int(li)].light = tl
		var brow: RowState = rows[base + int(ld["button_row"])]
		brow.button_light = tl
		brow.signal_light = tl
		var top: int = base + int(ld["lanes"].back()) + 1
		if rows.has(top) and rows[top].safe():
			rows[top].signal_light = tl
		tl.state_changed.connect(_on_light_state.bind(tl))
		seg["light"] = tl
	for p in spec["pickups"]:
		rows[base + p.x].pickups.append(p.y)
	segments.append(seg)
	# Create / refresh row nodes.
	for i in srows.size():
		var rs: RowState = rows[base + i]
		if rs.ground == null:
			var g := preload("res://scripts/game/row_ground.gd").new()
			g.row = rs
			g.position = Vector2(0, C.row_to_y(rs.index))
			ground_root.add_child(g)
			rs.ground = g
			var v := preload("res://scripts/game/row_view.gd").new()
			v.row = rs
			v.game = self
			v.position = Vector2(0, C.row_to_y(rs.index) + C.LANE_HALF_H)
			entities.add_child(v)
			rs.view = v
		else:
			rs.ground.queue_redraw()
	if rows.has(base - 1):
		rows[base - 1].ground.queue_redraw()


## Decorative city blocks below the first crossing so the screen is never empty.
## They sit below min_row(), so the robot can never walk into them.
func _create_backdrop_rows(rng: RandomNumberGenerator) -> void:
	var pattern := [C.Row.ROAD, C.Row.ROAD, C.Row.SIDEWALK, C.Row.ROAD, C.Row.ROAD, C.Row.SIDEWALK, C.Row.ROAD, C.Row.ROAD, C.Row.SIDEWALK]
	var dir := 1
	for i in pattern.size():
		var wr := -1 - i
		var rs := RowState.new()
		rs.index = wr
		rs.type = pattern[i]
		rs.seg = -1
		if rs.type == C.Row.ROAD:
			rs.spec = {"type": rs.type, "dir": dir, "deco_seed": rng.randi()}
			var l := LaneSim.new()
			l.setup(dir, rng.randf_range(110, 200), RoadGenerator.MIXES["mixed"], 1.6, 3.4, rng.randi())
			l.prewarm()
			rs.lane = l
			dir = -dir
		else:
			rs.spec = {"type": rs.type, "blocked": [], "deco_seed": rng.randi(), "button": -1}
		rows[wr] = rs
	for i in pattern.size():
		var wr := -1 - i
		rows[wr].above = rows.get(wr + 1)
		rows[wr].below = rows.get(wr - 1)
	rows[0].below = rows[-1]
	for i in pattern.size():
		var rs: RowState = rows[-1 - i]
		var g := preload("res://scripts/game/row_ground.gd").new()
		g.row = rs
		g.position = Vector2(0, C.row_to_y(rs.index))
		ground_root.add_child(g)
		rs.ground = g
		var v := preload("res://scripts/game/row_view.gd").new()
		v.row = rs
		v.game = self
		v.position = Vector2(0, C.row_to_y(rs.index) + C.LANE_HALF_H)
		entities.add_child(v)
		rs.view = v
	rows[0].ground.queue_redraw()


func _prune() -> void:
	if cur < 2:
		return
	var keep_from: int = segments[cur - 1]["base"]
	for idx in rows.keys():
		if idx < keep_from:
			var rs: RowState = rows[idx]
			if rs.ground:
				rs.ground.queue_free()
			if rs.view:
				rs.view.queue_free()
			rows.erase(idx)
	if rows.has(keep_from):
		rows[keep_from].below = null


# ------------------------------------------------------------ queries (used by player/views)

## Robot body centre in viewport (screen) coordinates, for "tap toward robot" controls.
func _player_screen_pos() -> Vector2:
	if player == null:
		return camera.view_size() * 0.5
	var world := Vector2(player.px, player.position.y - float(player.get_meta("bias", C.PLAYER_HALF_H)) - 26.0 - player.roof_z)
	return get_viewport().get_canvas_transform() * world


func row_state(r: int) -> RowState:
	return rows.get(r)


func min_row() -> int:
	return int(segments[cur]["base"])


func max_row() -> int:
	return int(segments[cur]["goal"])


func can_dash() -> bool:
	return dash_charges > 0


func is_riding(vid: int) -> bool:
	return player != null and player.is_riding() and player.ride_vid == vid


func ride_edge_warning() -> bool:
	return player != null and player.edge_warning


func view_half_width() -> float:
	return camera.view_size().x * 0.5


func level() -> int:
	return _level_for(cur)


func district() -> String:
	return String(segments[cur]["spec"].get("district", "downtown"))


func district_name() -> String:
	return RoadGenerator.DISTRICTS[district()]["name"]


## Visual standing height of a safe cell (planter boxes lift the robot a little).
func stand_height(r: int, x: float) -> float:
	var rs := row_state(r)
	if rs == null or not rs.safe():
		return 0.0
	return 14.0 if rs.planter(C.x_to_col(x)) else 0.0


func crossing_number() -> int:
	return cur + 1


func time_left() -> float:
	return maxf(0.0, par_time - crossing_time)


# ------------------------------------------------------------ main loop

func _process(dt: float) -> void:
	if hit_stop > 0.0:
		hit_stop -= dt
		return
	anim_time += dt
	_finish_task(false)
	for i in range(maxi(0, cur - 1), segments.size()):
		var tl: TrafficLight = segments[i]["light"]
		if tl != null:
			tl.step(dt)
	for rs in rows.values():
		if rs.lane != null:
			_step_lane(rs, dt)
	if mode == "attract":
		_attract(dt)
		return
	player.update(dt)
	player.check_collision()
	_check_near_miss()
	if not over:
		if has_moved:
			crossing_time += dt
		if mode == "rush" and has_moved:
			rush_time -= dt
			if rush_time <= 0.0:
				rush_time = 0.0
				_end_run(0.4)
	if respawn_timer >= 0.0:
		respawn_timer -= dt
		if respawn_timer < 0.0:
			_respawn()
	var py := C.row_to_y(player.row)
	if player.state == PlayerHopController.S.HOP and not player.hop_on_roof:
		py = lerpf(C.row_to_y(player.hop_from_row), C.row_to_y(player.hop_to_row), minf(player.hop_t, 1.0))
	camera.follow(py, dt)


func _step_lane(rs: RowState, dt: float) -> void:
	var lane := rs.lane
	lane.step(dt)
	# Skid marks for vehicles braking hard (a cheap, readable "they reacted" cue).
	if GameState.quality() >= 1:
		for v in lane.vehicles:
			if v.braking and v.speed > 40.0 and absf(v.x) < view_half_width() + 100.0 and randf() < 0.25:
				fx.skid(Vector2(v.x - v.length * 0.3 * lane.dir, C.row_to_y(rs.index)), 10.0, lane.dir)


func _attract(dt: float) -> void:
	_attract_timer -= dt
	if _attract_timer <= 0.0:
		_attract_timer = 9.0
		var tl: TrafficLight = segments[0]["light"]
		if tl != null:
			tl.press()
	camera.position.y = lerpf(camera.position.y, C.row_to_y(3), 1.0 - exp(-dt * 2.0))


# ------------------------------------------------------------ input

func _on_move(d: Vector2i) -> void:
	if over or player == null:
		return
	if player.try_move(d, false):
		has_moved = true


func _on_dash() -> void:
	if over or player == null or dash_charges <= 0:
		if dash_charges <= 0:
			Audio.play("bonk", 0.05)
		return
	var d := player.facing
	if d == Vector2i(0, -1) and not player.is_riding():
		d = Vector2i(0, 1)
	if player.try_move(d, true):
		has_moved = true


func _on_brake() -> void:
	if player != null and player.is_riding():
		player.try_move(Vector2i(0, -1), false)


# ------------------------------------------------------------ player events

func _on_hop_started(from_row: int, to_row: int, dash: bool) -> void:
	Audio.play("dash" if dash else "hop", 0.12)
	if dash:
		dash_charges -= 1
		score.dashes_used += 1
	var rs := row_state(from_row)
	if rs != null and rs.type == C.Row.ROAD and not player.is_riding():
		_nm = {"row": from_row, "x": player.px, "t": anim_time}


func _on_landed(r: int, x: float) -> void:
	var rs := row_state(r)
	var col := C.x_to_col(x)
	fx.dust(Vector2(x, C.row_to_y(r) + 14), 4)
	if rs.safe():
		last_safe_row = r
		last_safe_col = col
	if rs.type == C.Row.ROAD and player.state == PlayerHopController.S.IDLE:
		# Pickups
		if absf(x - C.col_to_x(col)) < 30.0 and rs.pickups.has(col):
			rs.pickups.erase(col)
			var pts := score.add_pickup()
			bolts += 1
			Audio.play("pickup", 0.05)
			fx.sparkle(Vector2(x, C.row_to_y(r) - 20))
			var msg := "BOLT +%d" % pts
			if bolts >= 3:
				bolts = 0
				if dash_charges < C.MAX_DASH_CHARGES:
					dash_charges += 1
					msg += "  DASH +1"
			fx.popup(Vector2(x, C.row_to_y(r) - 60), msg, Color("ffd23f"), 26)
		_check_tailgate(rs, x)
	if rs.button_light != null and col == rs.button_col():
		if rs.button_light.press():
			score.signals_used += 1
			Audio.play("button")
			fx.popup(Vector2(x, C.row_to_y(r) - 70), "SIGNAL CALLED", Color("9dff9d"), 26)
	if r == max_row():
		_deliver(x)


func _deliver(x: float) -> void:
	var r := max_row()
	var col := C.x_to_col(x)
	var goal_rs := row_state(r)
	var info := score.deliver(time_left(), level(), col == goal_rs.locker_col())
	info["crossing_number"] = cur + 1
	var old_district := district()
	Audio.play("deliver")
	fx.confetti(Vector2(x, C.row_to_y(r) - 30))
	fx.popup(Vector2(x, C.row_to_y(r) - 90), "DELIVERED +%d" % info["total"], Color("ffd23f"), 38)
	if info["doorstep"] > 0:
		fx.popup(Vector2(x, C.row_to_y(r) - 50), "DOORSTEP!", Color("9de8ff"), 26)
	player.set_mood("happy", 1.4)
	dash_charges = mini(C.MAX_DASH_CHARGES, dash_charges + 1)
	GameState.add_delivery()
	_finish_task(true)
	cur += 1
	crossing_time = 0.0
	par_time = segments[cur]["spec"]["par_time"]
	last_safe_row = r
	last_safe_col = col
	_request_next_segment()
	_prune()
	if district() != old_district:
		info["new_district"] = district_name()
		GameState.unlock_district(district())
	delivered.emit(info)
	if mode == "rush" and score.deliveries >= RUSH_DELIVERIES:
		_end_run(1.0)


func _on_mounted(v) -> void:
	var pts := score.add_roof_mount()
	Audio.play("ride")
	fx.popup(Vector2(player.px, C.row_to_y(player.row) - 90), "ROOF RIDE +%d" % pts, Color("9de8ff"), 26)


func _on_died(cause: String, v) -> void:
	lives -= 1
	score.lose_life()
	var pos := Vector2(player.px, C.row_to_y(player.row) - 20)
	Audio.play("crash")
	if v != null:
		Audio.play_at("honk", Vector2(v.x, pos.y), 0.15)
		v.slow_timer = 0.7
	fx.sparks(pos, signf(player.death_vel.x))
	camera.add_shake(12.0)
	hit_stop = 0.07
	var msg: String = "CARRIED AWAY!" if cause == "carried" else ["BONK!", "OOF!", "SPLAT!", "WHOOPS!"][randi() % 4]
	fx.popup(pos - Vector2(0, 50), msg, Color("ff6b6b"), 34)
	if lives <= 0:
		_end_run(1.1)
	else:
		respawn_timer = 0.75


func _respawn() -> void:
	var rs := row_state(last_safe_row)
	var col := last_safe_col
	if rs == null or rs.blocked(col):
		col = C.CENTER_COL
	if rs == null:
		last_safe_row = min_row()
	player.respawn(last_safe_row, C.col_to_x(col))
	Audio.play("respawn")


func _end_run(delay: float) -> void:
	if over:
		return
	over = true
	input.enabled = false
	var summary := {
		"mode": mode, "score": score.score, "breakdown": score.breakdown.duplicate(),
		"best_streak": score.best_streak, "deliveries": score.deliveries,
		"near_misses": score.near_misses, "roof_rides": score.roof_rides, "pickups": score.pickups,
		"crossings": cur,
	}
	if mode == "rush":
		var ok := _objective_met()
		summary["objective"] = objective.get("text", "")
		summary["objective_met"] = ok
		summary["rush_complete"] = score.deliveries >= RUSH_DELIVERIES
		if ok and summary["rush_complete"]:
			summary["score"] += 500
			summary["breakdown"]["objective"] = 500
	summary["new_high"] = GameState.record_run(summary)
	await get_tree().create_timer(delay, false).timeout
	game_over.emit(summary)


func _objective_met() -> bool:
	match objective.get("id", ""):
		"no_dash": return score.dashes_used == 0 and score.deliveries > 0
		"ride_2": return score.roof_rides >= 2
		"near_3": return score.near_misses >= 3
		"signal": return score.signals_used >= 1
	return false


func objective_progress() -> String:
	match objective.get("id", ""):
		"no_dash": return "dashes used: %d" % score.dashes_used
		"ride_2": return "%d / 2" % mini(score.roof_rides, 2)
		"near_3": return "%d / 3" % mini(score.near_misses, 3)
		"signal": return "done" if score.signals_used > 0 else "not yet"
	return ""


# ------------------------------------------------------------ near misses

## A close call is a vehicle physically sweeping through the spot the robot stood on
## less than 0.45 s earlier, or the robot landing right behind a vehicle's bumper.
## Each vehicle pays out once.
func _check_near_miss() -> void:
	if player.state == PlayerHopController.S.DEAD:
		return
	if anim_time - float(_nm["t"]) > 0.45:
		return
	var rs := row_state(int(_nm["row"]))
	if rs == null or rs.lane == null:
		return
	var x: float = _nm["x"]
	for v in rs.lane.vehicles:
		if v.near_miss_awarded:
			continue
		if v.hit_max() > x - C.PLAYER_HALF_W - 4.0 and v.hit_min() < x + C.PLAYER_HALF_W + 4.0:
			_award_near_miss(v, Vector2(x, C.row_to_y(rs.index)))


func _check_tailgate(rs: RowState, x: float) -> void:
	for v in rs.lane.vehicles:
		if v.near_miss_awarded:
			continue
		var gap: float
		if rs.lane.dir > 0:
			gap = (x - C.PLAYER_HALF_W) - v.hit_max()
		else:
			gap = v.hit_min() - (x + C.PLAYER_HALF_W)
		if gap > 0.0 and gap < 26.0:
			_award_near_miss(v, Vector2(x, C.row_to_y(rs.index)))


func _award_near_miss(v, pos: Vector2) -> void:
	v.near_miss_awarded = true
	var pts := score.add_near_miss(v.id)
	if pts <= 0:
		return
	Audio.play("nearmiss", 0.1)
	if v.honk_cooldown <= 0.0 and randf() < 0.6:
		v.honk_cooldown = 3.0
		Audio.play_at("honk", Vector2(v.x, pos.y), 0.2)
	fx.popup(pos - Vector2(0, 80), "CLOSE CALL +%d" % pts, Color("ff9df0"), 28)
	player.set_mood("worried", 0.6)
	camera.add_shake(3.0)


func _on_light_state(s: int, tl: TrafficLight) -> void:
	if mode == "attract":
		return
	match s:
		TrafficLight.AMBER: Audio.play("signal_wait")
		TrafficLight.WALK: Audio.play("signal_walk")
		TrafficLight.WALK_ENDING: Audio.play("signal_end")
