class_name TrafficLight
extends RefCounted
## Pedestrian-button traffic signal controlling a contiguous group of lanes.
##
## GREEN ──press──▶ AMBER (visible warning) ─▶ CLEARING (until the crosswalk is
## physically empty) ─▶ WALK ─▶ WALK_ENDING (flashing hand, cars still stopped) ─▶ GREEN.
## The WALK phase is only entered once no vehicle overlaps the crosswalk, so the
## walking-figure signal never lies.

signal state_changed(new_state: int)

enum { GREEN, AMBER, CLEARING, WALK, WALK_ENDING }

const AMBER_TIME := 1.4
const WALK_TIME := 4.5
const WALK_ENDING_TIME := 1.6
const COOLDOWN := 2.5

var state := GREEN
var timer := 0.0
var cooldown := 0.0
var lanes: Array = []          # LaneSim
var column := 4
var x := 0.0                   # crosswalk world x
var button_rows: Array = []    # rows holding a push button (safe rows adjacent to the group)
var presses := 0


func setup(p_column: int, p_lanes: Array) -> void:
	column = p_column
	x = C.col_to_x(column)
	lanes = p_lanes
	for l in lanes:
		l.light = self
		l.crosswalk_x = x


func stop_active() -> bool:
	return state != GREEN


func can_press() -> bool:
	return state == GREEN and cooldown <= 0.0


func press() -> bool:
	if not can_press():
		return false
	presses += 1
	_set_state(AMBER)
	timer = AMBER_TIME
	for l in lanes:
		l.evaluate_stops()
	return true


func walk_progress() -> float:
	match state:
		WALK: return timer / (WALK_TIME + WALK_ENDING_TIME) + WALK_ENDING_TIME / (WALK_TIME + WALK_ENDING_TIME)
		WALK_ENDING: return timer / (WALK_TIME + WALK_ENDING_TIME)
	return 0.0


func crosswalk_clear() -> bool:
	var a := x - C.TILE * 0.5 - 4.0
	var b := x + C.TILE * 0.5 + 4.0
	for l in lanes:
		if l.vehicle_overlapping(a, b) != null:
			return false
	return true


func step(dt: float) -> void:
	if cooldown > 0.0:
		cooldown -= dt
	match state:
		AMBER:
			timer -= dt
			if timer <= 0.0:
				_set_state(CLEARING)
		CLEARING:
			if crosswalk_clear():
				_set_state(WALK)
				timer = WALK_TIME
		WALK:
			timer -= dt
			if timer <= 0.0:
				_set_state(WALK_ENDING)
				timer = WALK_ENDING_TIME
		WALK_ENDING:
			timer -= dt
			if timer <= 0.0:
				_set_state(GREEN)
				cooldown = COOLDOWN
				for l in lanes:
					l.clear_stops()


## True while a pedestrian on the crosswalk is guaranteed safe from controlled lanes.
func walk_safe() -> bool:
	return state == WALK or state == WALK_ENDING


func _set_state(s: int) -> void:
	state = s
	state_changed.emit(s)
