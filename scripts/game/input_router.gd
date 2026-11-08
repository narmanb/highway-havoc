class_name InputRouter
extends Node
## Turns touch gestures, keyboard, D-pad and analog sticks into clean grid moves.
##  * Swipe: one crisp hop per swipe; a long swipe that keeps travelling can chain hops.
##  * Tap: hop forward (or, with "double-tap to dash" on, double-tap dashes forward).
##  * Optional hold-to-hop edge regions.
##  * Alternative touch modes (Settings > Touch controls):
##      "relative": tap anywhere; the robot hops in the closest of the four directions
##                  from itself toward your finger. Hold to keep hopping.
##      "dpad":     a large translucent on-screen D-pad; press, hold, or slide between arms.
##  * D-pad / keys / stick: one hop per press, repeat while held at a configurable pace.
##  * Sticks use hysteresis and dominant-axis locking, so no diagonals or double moves.

signal move(dir: Vector2i)
signal dash
signal brake
signal pause_pressed
signal touch_feedback(pos: Vector2, dir: Vector2i)

const SWIPE_DIST := 34.0
const FLICK_MIN := 14.0            # shorter than this on release = a tap
const RELATIVE_DEAD_ZONE := 30.0   # touches right on the robot are ignored
const TAP_MAX_TIME := 0.28
const DOUBLE_TAP := 0.32
const STICK_ON := 0.6
const STICK_OFF := 0.3

var enabled := true
var exclusion: Array = []           # Controls whose rects never start gestures
var player_screen_pos: Callable     # () -> Vector2: robot centre in viewport coordinates
var dpad_center := Vector2.ZERO     # on-screen D-pad (set by the HUD in D-pad mode)
var dpad_radius := 0.0              # outer radius of the arms
var dpad_dead := 0.0                # centre dead zone (grows with arrow spread)

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


## Pause between the first hop and the start of repeating (Settings > "Repeat starts after").
func _hold_delay() -> float:
	return float(GameState.settings.get("repeat_delay", 0.24))


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
			_hold_timer = _hold_delay()
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
			_stick_timer = _hold_delay()
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


## Direction of the larger axis of `delta` (screen space, y down), or ZERO inside the dead zone.
## Used by "tap toward robot" (delta = touch - robot) and the on-screen D-pad (touch - pad centre).
static func dir_from(delta: Vector2, dead: float) -> Vector2i:
	if delta.length() < dead:
		return Vector2i.ZERO
	if absf(delta.x) > absf(delta.y):
		return Vector2i(1 if delta.x > 0 else -1, 0)
	return Vector2i(0, -1 if delta.y > 0 else 1)


func touch_mode() -> String:
	return String(GameState.settings.get("touch_mode", "swipe"))


func _robot_pos() -> Vector2:
	return player_screen_pos.call() if player_screen_pos.is_valid() else get_viewport().get_visible_rect().size * 0.5


func _emit_touch(d: Vector2i, pos: Vector2) -> void:
	if d == Vector2i.ZERO:
		return
	move.emit(d)
	touch_feedback.emit(pos, d)


func _in_dpad(pos: Vector2) -> bool:
	return dpad_radius > 0.0 and pos.distance_to(dpad_center) <= dpad_radius * 1.3


func _touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if _excluded(e.position):
			return
		var mode := touch_mode()
		var t := {"start": e.position, "anchor": e.position, "pos": e.position, "t0": _now(),
			"swiped": false, "hold_dir": Vector2i.ZERO, "holding": false, "hold_t": 0.0, "kind": "swipe"}
		if mode == "relative":
			var d := dir_from(e.position - _robot_pos(), RELATIVE_DEAD_ZONE)
			t["kind"] = "relative"
			t["hold_dir"] = d
			_emit_touch(d, e.position)
		elif mode == "dpad" and _in_dpad(e.position):
			var d2 := dir_from(e.position - dpad_center, dpad_dead)
			t["kind"] = "dpad"
			t["hold_dir"] = d2
			_emit_touch(d2, e.position)
		elif mode == "swipe" and GameState.settings["hold_edges"]:
			t["hold_dir"] = _edge_dir(e.position)
		_touches[e.index] = t
		get_viewport().set_input_as_handled()
		return
	if not _touches.has(e.index):
		return
	var t: Dictionary = _touches[e.index]
	_touches.erase(e.index)
	get_viewport().set_input_as_handled()
	if t["kind"] != "swipe" or t["swiped"] or t["holding"]:
		return
	var moved: Vector2 = e.position - t["start"]
	# A quick flick that ended before crossing the drag threshold is still a swipe,
	# never a tap (a short sideways flick used to hop the robot forward).
	if moved.length() >= FLICK_MIN:
		_emit_touch(dir_from(moved, 0.0), e.position)
		return
	if touch_mode() != "swipe":
		return  # in D-pad mode, stray taps outside the pad do nothing
	var dur := _now() - float(t["t0"])
	if dur > TAP_MAX_TIME:
		return
	if GameState.settings["double_tap_dash"]:
		if _now() - _last_tap < DOUBLE_TAP:
			_last_tap = -10.0
			dash.emit()
		else:
			_last_tap = _now()
	else:
		_emit_touch(Vector2i(0, 1), e.position)


func _drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	var t: Dictionary = _touches[e.index]
	t["pos"] = e.position
	get_viewport().set_input_as_handled()
	match t["kind"]:
		"relative":
			return  # the hold logic re-reads the finger position
		"dpad":
			# Sliding the thumb onto another arm hops that way immediately.
			var d := dir_from(e.position - dpad_center, dpad_dead)
			if d != t["hold_dir"]:
				t["hold_dir"] = d
				t["holding"] = false
				t["hold_t"] = 0.0
				_emit_touch(d, e.position)
			return
	var delta: Vector2 = e.position - t["anchor"]
	if delta.length() < SWIPE_DIST:
		return
	_emit_touch(dir_from(delta, 0.0), e.position)
	t["anchor"] = e.position
	t["swiped"] = true


func _poll_touch_hold(dt: float) -> void:
	for idx in _touches:
		var t: Dictionary = _touches[idx]
		if t["swiped"] or t["hold_dir"] == Vector2i.ZERO:
			continue
		if t["kind"] == "swipe" and not GameState.settings["hold_edges"]:
			continue
		t["hold_t"] += dt
		var due: bool = (not t["holding"] and t["hold_t"] >= _hold_delay()) or (t["holding"] and t["hold_t"] >= _repeat_rate())
		if not due:
			continue
		t["holding"] = true
		t["hold_t"] = 0.0
		if t["kind"] == "relative":
			# Keep hopping toward the finger only while that is still the closest direction,
			# so the robot stops once it reaches the finger instead of turning a corner.
			var d := dir_from(t["pos"] - _robot_pos(), RELATIVE_DEAD_ZONE)
			if d != t["hold_dir"]:
				t["hold_dir"] = Vector2i.ZERO
				continue
		_emit_touch(t["hold_dir"], t["pos"])
