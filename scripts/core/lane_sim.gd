class_name LaneSim
extends RefCounted
## Pure-logic traffic lane. No nodes, no rendering: the exact same code drives the
## live game, the SafePathValidator and the headless tests, so what the validator
## predicts is what the player will face (until the player presses a crosswalk button,
## which only ever *removes* danger).
##
## Coordinates: vehicles live on a 1-D axis (world x). `dir` is +1 (moving right) or
## -1 (moving left). "Forward" coordinate f = x * dir grows in the direction of travel.

class Vehicle:
	var id: int
	var kind: String
	var x: float
	var prev_x: float
	var length: float
	var speed: float
	var color: Color
	var phase: float
	var braking := false
	var will_stop := -1          # -1: no light decision, 0: proceed through amber, 1: stop at line
	var near_miss_awarded := false
	var slow_timer := 0.0        # brief jolt after an impact
	var honk_cooldown := 0.0

	func hit_min() -> float:
		return x - length * 0.5 + C.HITBOX_INSET

	func hit_max() -> float:
		return x + length * 0.5 - C.HITBOX_INSET

	func rideable() -> bool:
		return VehicleTypes.is_rideable(kind)

	## Rear cargo region (world x interval) of a rideable truck.
	func cargo_range(dir: int) -> Vector2:
		var cab: float = VehicleTypes.DEFS[kind]["cab"]
		var cargo_len := length - cab
		if dir > 0:
			var r := x - length * 0.5
			return Vector2(r, r + cargo_len)
		var r2 := x + length * 0.5
		return Vector2(r2 - cargo_len, r2)

	## Solid (lethal) interval: the full hitbox for normal vehicles, only the cab for trucks.
	func solid_range(dir: int) -> Vector2:
		if not rideable():
			return Vector2(hit_min(), hit_max())
		var cab: float = VehicleTypes.DEFS[kind]["cab"]
		if dir > 0:
			return Vector2(x + length * 0.5 - cab, hit_max())
		return Vector2(hit_min(), x - length * 0.5 + cab)


const MIN_GAP_PX := 150.0

static var _next_id := 1

var dir := 1
var speed := 150.0
var mix: Array = []            # [[kind, weight], ...]
var gap_min_s := 1.4
var gap_max_s := 3.0
var rng := RandomNumberGenerator.new()
var vehicles: Array = []       # leader (furthest forward) first
var next_gap_px := 0.0
var time := 0.0
var light: RefCounted = null   # TrafficLight controlling this lane, or null
var crosswalk_x := 0.0         # world x of the crosswalk column (when light != null)

var on_spawn: Callable         # optional hook (vehicle) -> void, used by the renderer


func setup(p_dir: int, p_speed: float, p_mix: Array, p_gap_min: float, p_gap_max: float, p_seed: int) -> void:
	dir = p_dir
	speed = p_speed
	mix = p_mix
	gap_min_s = maxf(p_gap_min, C.MIN_GAP_SECONDS)
	gap_max_s = maxf(p_gap_max, gap_min_s)
	rng.seed = p_seed
	vehicles.clear()
	time = 0.0
	_roll_gap()


## Fill the lane so it looks like it has been running for a while. Deterministic.
func prewarm() -> void:
	var travel := C.SPAWN_X + C.DESPAWN_X
	var steps := int(ceil(travel / speed / 0.1)) + 2
	for i in steps:
		step(0.1)
	time = 0.0


func spawn_f() -> float:
	return -C.SPAWN_X


func _roll_gap() -> void:
	# Gap is a time window, but never shorter than MIN_GAP_PX so slow lanes stay open too.
	next_gap_px = maxf(speed * rng.randf_range(gap_min_s, gap_max_s), MIN_GAP_PX)


func _pick_kind() -> String:
	var total := 0.0
	for m in mix:
		total += float(m[1])
	var r := rng.randf() * total
	for m in mix:
		r -= float(m[1])
		if r <= 0.0:
			return m[0]
	return mix[0][0]


func _make_vehicle(kind: String, front_f: float) -> Vehicle:
	var v := Vehicle.new()
	v.id = _next_id
	_next_id += 1
	v.kind = kind
	v.length = VehicleTypes.length_of(kind)
	v.x = (front_f - v.length * 0.5) * dir
	v.prev_x = v.x
	v.speed = speed
	v.color = VehicleTypes.pick_color(kind, rng)
	v.phase = rng.randf() * TAU
	if light != null and light.call("stop_active"):
		v.will_stop = 1
	return v


func _try_spawn() -> void:
	# Spawning is anchored to the previous vehicle so spacing is exact and frame-rate independent.
	while true:
		var front_f: float
		if vehicles.is_empty():
			front_f = spawn_f()
		else:
			var last: Vehicle = vehicles[vehicles.size() - 1]
			var last_rear_f := last.x * dir - last.length * 0.5
			front_f = last_rear_f - next_gap_px
			if front_f < spawn_f():
				return
		var kind := _pick_kind()
		var v := _make_vehicle(kind, front_f)
		vehicles.append(v)
		_roll_gap()
		if on_spawn.is_valid():
			on_spawn.call(v)
		if vehicles.size() == 1:
			return


func stop_line_f() -> float:
	return crosswalk_x * dir - C.TILE * 0.5 - 12.0


func light_stopping() -> bool:
	return light != null and light.call("stop_active")


## Called by the TrafficLight when it turns amber: each vehicle decides once, using
## honest braking physics, whether it can stop comfortably or must proceed.
func evaluate_stops() -> void:
	var line := stop_line_f()
	for v in vehicles:
		var front_f: float = v.x * dir + v.length * 0.5
		var dist := line - front_f
		var brake_dist: float = v.speed * v.speed / (2.0 * C.VEHICLE_DECEL)
		v.will_stop = 1 if dist >= brake_dist + 4.0 else 0


func clear_stops() -> void:
	for v in vehicles:
		v.will_stop = -1


func step(dt: float) -> void:
	time += dt
	var stopping := light_stopping()
	var line := stop_line_f()
	var prev_rear_f := INF
	for i in vehicles.size():
		var v: Vehicle = vehicles[i]
		v.prev_x = v.x
		if v.slow_timer > 0.0:
			v.slow_timer -= dt
		if v.honk_cooldown > 0.0:
			v.honk_cooldown -= dt
		var target := speed * (0.35 if v.slow_timer > 0.0 else 1.0)
		var front_f: float = v.x * dir + v.length * 0.5
		var limit := prev_rear_f - C.QUEUE_GAP
		if stopping and v.will_stop == 1:
			limit = minf(limit, line)
		var desired := target
		if limit < INF:
			var dist := limit - front_f
			desired = minf(target, sqrt(2.0 * C.VEHICLE_DECEL * maxf(0.0, dist - 1.0)))
		if v.speed < desired:
			v.speed = minf(desired, v.speed + C.VEHICLE_ACCEL * dt)
		else:
			v.speed = maxf(desired, v.speed - C.VEHICLE_DECEL * 2.0 * dt)
		v.braking = v.speed < target - 8.0 and desired <= v.speed + 0.01
		var new_front := front_f + v.speed * dt
		if new_front > limit:
			new_front = maxf(front_f, limit)
			v.speed = 0.0 if new_front <= front_f else v.speed
		v.x = (new_front - v.length * 0.5) * dir
		prev_rear_f = new_front - v.length
	# Despawn vehicles that left the far side.
	while not vehicles.is_empty():
		var lead: Vehicle = vehicles[0]
		if lead.x * dir - lead.length * 0.5 > C.DESPAWN_X:
			vehicles.pop_front()
		else:
			break
	_try_spawn()


# ---------------------------------------------------------------- queries

func vehicle_overlapping(min_x: float, max_x: float) -> Vehicle:
	for v in vehicles:
		if v.hit_max() > min_x and v.hit_min() < max_x:
			return v
	return null


## Vehicle whose *lethal* part overlaps [min_x, max_x] (truck cargo roofs are not lethal
## to land on; they are mounted instead).
func solid_overlapping(min_x: float, max_x: float) -> Vehicle:
	for v in vehicles:
		var r: Vector2 = v.solid_range(dir)
		if r.y > min_x and r.x < max_x:
			return v
	return null


## Rideable truck whose cargo roof can take a robot centred at px.
func cargo_at(px: float) -> Vehicle:
	for v in vehicles:
		if not v.rideable():
			continue
		var r: Vector2 = v.cargo_range(dir)
		if px >= r.x + 8.0 and px <= r.y - 8.0:
			return v
	return null


func find_vehicle(id: int) -> Vehicle:
	for v in vehicles:
		if v.id == id:
			return v
	return null
