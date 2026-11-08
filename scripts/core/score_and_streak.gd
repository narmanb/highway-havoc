class_name ScoreAndStreak
extends RefCounted
## Score = crossing points + (time remaining x tempo bonus) + near-miss bonuses,
## with deliveries multiplied by the parcel-streak multiplier.

const CROSSING_POINTS := 100
const NEAR_MISS_POINTS := 50
const ROOF_MOUNT_POINTS := 30
const PICKUP_POINTS := 25
const DOORSTEP_POINTS := 50
const MAX_NEAR_MISS_PER_CROSSING := 8

var score := 0
var breakdown := {"crossing": 0, "time": 0, "near_miss": 0, "roof": 0, "pickups": 0, "doorstep": 0, "streak": 0}
var streak := 0
var best_streak := 0
var deliveries := 0
var near_misses := 0
var roof_rides := 0
var pickups := 0
var dashes_used := 0
var signals_used := 0
var _near_miss_ids := {}
var _near_miss_this_crossing := 0
var _roof_carry := 0.0


func multiplier() -> float:
	return 1.0 + 0.5 * float(clampi(streak - 1, 0, 6))


func _add(cat: String, pts: int) -> int:
	breakdown[cat] += pts
	score += pts
	return pts


## Returns points awarded (0 when this vehicle already paid out, or farming is capped).
func add_near_miss(vehicle_id: int) -> int:
	if _near_miss_ids.has(vehicle_id) or _near_miss_this_crossing >= MAX_NEAR_MISS_PER_CROSSING:
		return 0
	_near_miss_ids[vehicle_id] = true
	_near_miss_this_crossing += 1
	near_misses += 1
	return _add("near_miss", NEAR_MISS_POINTS)


var _mounted_ids := {}


## Points for boarding a truck roof or floating platform: once per vehicle, so
## hopping back and forth on the same barge can't be farmed.
func add_roof_mount(vehicle_id := -1) -> int:
	if vehicle_id >= 0:
		if _mounted_ids.has(vehicle_id):
			return 0
		_mounted_ids[vehicle_id] = true
	roof_rides += 1
	return _add("roof", ROOF_MOUNT_POINTS)


## Small trickle of points for distance ridden on a roof (1 pt per 12 px).
func add_roof_distance(px: float) -> int:
	_roof_carry += absf(px) / 12.0
	var whole := int(_roof_carry)
	_roof_carry -= whole
	if whole > 0:
		return _add("roof", whole)
	return 0


func add_pickup() -> int:
	pickups += 1
	return _add("pickups", PICKUP_POINTS)


func deliver(time_remaining: float, level: int, doorstep: bool) -> Dictionary:
	streak += 1
	best_streak = maxi(best_streak, streak)
	deliveries += 1
	_near_miss_this_crossing = 0
	var tempo := 8 + 2 * level
	var crossing := CROSSING_POINTS + 20 * (level - 1)
	var time_pts := int(maxf(0.0, time_remaining) * tempo)
	var door := DOORSTEP_POINTS if doorstep else 0
	var base := crossing + time_pts + door
	var mult := multiplier()
	var bonus := int(round(base * (mult - 1.0)))
	_add("crossing", crossing)
	_add("time", time_pts)
	_add("doorstep", door)
	_add("streak", bonus)
	return {"crossing": crossing, "time": time_pts, "doorstep": door, "streak_bonus": bonus,
		"multiplier": mult, "total": base + bonus}


func lose_life() -> void:
	streak = 0
