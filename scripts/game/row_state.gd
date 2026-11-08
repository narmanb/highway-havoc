class_name RowState
extends RefCounted
## Runtime data for one world row.

var index := 0
var spec: Dictionary
var type := C.Row.SIDEWALK
var lane: LaneSim = null
var light: TrafficLight = null      # light controlling this lane (road rows)
var button_light: TrafficLight = null  # light whose push button sits on this safe row
var signal_light: TrafficLight = null  # light whose poles stand on this safe row
var seg := 0
var is_goal := false
var pickups: Array = []             # columns holding a bolt pickup
var above: RowState = null
var below: RowState = null
var ground: Node2D
var view: Node2D


func blocked(col: int) -> bool:
	if not safe():
		return false
	return (spec.get("blocked", []) as Array).has(col)


## Low flower box: walkable, the robot just stands a little higher on it.
func planter(col: int) -> bool:
	if not safe():
		return false
	return (spec.get("planters", []) as Array).has(col)


func style() -> String:
	return String(spec.get("style", "city"))


func safe() -> bool:
	return type != C.Row.ROAD and type != C.Row.WATER


func is_water() -> bool:
	return type == C.Row.WATER


func button_col() -> int:
	return int(spec.get("button", -1))


func locker_col() -> int:
	return int(spec.get("locker", -1)) if is_goal else -1
