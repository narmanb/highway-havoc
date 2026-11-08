class_name InputRouter
extends Node
## Turns touch gestures, keyboard, D-pad and analog sticks into clean grid moves.
##  * Swipe: one crisp hop per swipe; a long swipe that keeps travelling can chain hops.
##  * Tap: hop forward (or, with "double-tap to dash" on, double-tap dashes forward).
##  * Optional hold-to-hop edge regions.
##  * D-pad / keys / stick: one hop per press, repeat while held at a configurable pace.
##  * Sticks use hysteresis and dominant-axis locking, so no diagonals or double moves.

signal move(dir: Vector2i)
signal dash
signal brake
signal pause_pressed

const SWIPE_DIST := 34.0
const TAP_MAX_TIME := 0.28
const DOUBLE_TAP := 0.32
const HOLD_DELAY := 0.24
const STICK_ON := 0.6
const STICK_OFF := 0.3

var enabled := true
var exclusion: Array = []           # Controls whose rects never start gestures

var _touches := {}
var _last_tap := -10.0
var _held_action := ""
var _held_dir := Vector2i.ZERO
var _hold_timer := 0.0
var _stick_dir := Vector2i.ZERO
var _stick_timer := 0.0

const DIRS := {
	"move_up": Vector2i(0, 1), "move_down": Vector2i(0, -1),
	"move_left": Vector2i(-1, 0), "move_right": Vector2i(1, 0),
}


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _repeat_rate() -> float:
	return float(GameState.settings["repeat_rate"])


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		pause_pressed.emit()
		get_viewport().set_input_as_handled()
		return
	if not enabled:
		return
	if event is InputEventScreenTouch:
		_touch(event)
		return
	if event is InputEventScreenDrag:
		_drag(event)
		return
	if event.is_echo():
		return
	for a in DIRS:
		if event.is_action_pressed(a):
			move.emit(DIRS[a])
			_held_action = a
			_held_dir = DIRS[a]
			_hold_timer = HOLD_DELAY
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released(a) and a == _held_action:
			_held_action = ""
	if event.is_action_pressed("dash"):
		dash.emit()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("brake"):
		brake.emit()
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	if not enabled:
		_touches.clear()
		_held_action = ""
		return
	# Held D-pad / keys.
	if _held_action != "":
		if Input.is_action_pressed(_held_action):
			_hold_timer -= dt
			if _hold_timer <= 0.0:
				move.emit(_held_dir)
				_hold_timer = _repeat_rate()
		else:
			_held_action = ""
	_poll_stick(dt)
	_poll_touch_hold(dt)


func _poll_stick(dt: float) -> void:
	var v := Vector2.ZERO
	for id in Input.get_connected_joypads():
		var s := Vector2(Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
		if s.length() > v.length():
			v = s
	var d := Vector2i.ZERO
	var ax := absf(v.x)
	var ay := absf(v.y)
	if _stick_dir != Vector2i.ZERO:
		# Stay locked on the current axis until the stick relaxes.
		var along := v.dot(Vector2(_stick_dir.x, -_stick_dir.y))
		if along > STICK_OFF:
			d = _stick_dir
	if d == Vector2i.ZERO:
		if ax > STICK_ON and ax > ay * 1.3:
			d = Vector2i(1 if v.x > 0 else -1, 0)
		elif ay > STICK_ON and ay > ax * 1.3:
			d = Vector2i(0, -1 if v.y > 0 else 1)
	if d != _stick_dir:
		_stick_dir = d
		if d != Vector2i.ZERO:
			move.emit(d)
			_stick_timer = HOLD_DELAY
	elif d != Vector2i.ZERO:
		_stick_timer -= dt
		if _stick_timer <= 0.0:
			move.emit(d)
			_stick_timer = _repeat_rate()


func _excluded(pos: Vector2) -> bool:
	for c in exclusion:
		if is_instance_valid(c) and c.is_visible_in_tree() and c.get_global_rect().grow(8.0).has_point(pos):
			return true
	return false


func _edge_dir(pos: Vector2) -> Vector2i:
	var size := get_viewport().get_visible_rect().size
	if pos.y < size.y * 0.22:
		return Vector2i(0, 1)
	if pos.y > size.y * 0.82:
		return Vector2i(0, -1)
	if pos.x < size.x * 0.18:
		return Vector2i(-1, 0)
	if pos.x > size.x * 0.82:
		return Vector2i(1, 0)
	return Vector2i.ZERO


func _touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if _excluded(e.position):
			return
		_touches[e.index] = {"start": e.position, "anchor": e.position, "t0": _now(),
			"swiped": false, "hold_dir": _edge_dir(e.position), "holding": false, "hold_t": 0.0}
		get_viewport().set_input_as_handled()
		return
	if not _touches.has(e.index):
		return
	var t: Dictionary = _touches[e.index]
	_touches.erase(e.index)
	get_viewport().set_input_as_handled()
	if t["swiped"] or t["holding"]:
		return
	var dur := _now() - float(t["t0"])
	if dur > TAP_MAX_TIME or (e.position - t["start"]).length() > SWIPE_DIST:
		return
	if GameState.settings["double_tap_dash"]:
		if _now() - _last_tap < DOUBLE_TAP:
			_last_tap = -10.0
			dash.emit()
		else:
			_last_tap = _now()
	else:
		move.emit(Vector2i(0, 1))


func _drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	var t: Dictionary = _touches[e.index]
	var delta: Vector2 = e.position - t["anchor"]
	if delta.length() < SWIPE_DIST:
		return
	var d: Vector2i
	if absf(delta.x) > absf(delta.y):
		d = Vector2i(1 if delta.x > 0 else -1, 0)
	else:
		d = Vector2i(0, -1 if delta.y > 0 else 1)
	move.emit(d)
	t["anchor"] = e.position
	t["swiped"] = true
	get_viewport().set_input_as_handled()


func _poll_touch_hold(dt: float) -> void:
	if not GameState.settings["hold_edges"]:
		return
	for idx in _touches:
		var t: Dictionary = _touches[idx]
		if t["swiped"] or t["hold_dir"] == Vector2i.ZERO:
			continue
		t["hold_t"] += dt
		if not t["holding"] and t["hold_t"] >= HOLD_DELAY:
			t["holding"] = true
			t["hold_t"] = 0.0
			move.emit(t["hold_dir"])
		elif t["holding"] and t["hold_t"] >= _repeat_rate():
			t["hold_t"] = 0.0
			move.emit(t["hold_dir"])
