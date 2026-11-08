extends Node
## Injects real touch events (Input.parse_input_event) into a running Game and checks
## which hops the InputRouter produces in each touch mode.
## Run: godot --headless --path . --fixed-fps 60 res://tests/touch_test.tscn

var main: Node
var failures := 0
var checks := 0
var got: Array = []


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)
	else:
		print("ok   ", msg)


func _ready() -> void:
	GameState.settings["hold_edges"] = false
	GameState.settings["double_tap_dash"] = false
	main = load("res://scripts/ui/main.gd").new()
	add_child(main)
	await _frames(2)
	await _test_relative()
	await _test_dpad()
	await _test_swipe()
	await _test_planter()
	GameState.settings["touch_mode"] = "swipe"
	print("\n%d checks, %d failures" % [checks, failures])
	get_tree().quit(1 if failures > 0 else 0)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _start(mode: String) -> void:
	GameState.settings["touch_mode"] = mode
	main.start_game("arcade")
	await _frames(10)
	got.clear()
	main.game.input.move.connect(func(d): got.append(d))


## Positions are given in viewport coordinates and converted to window pixels,
## exactly like a real finger on the device.
func _win(p: Vector2) -> Vector2:
	return get_viewport().get_final_transform() * p


func _touch(pos: Vector2, hold_frames := 2, drag_to = null) -> void:
	pos = _win(pos)
	if drag_to != null:
		drag_to = _win(drag_to)
	var e := InputEventScreenTouch.new()
	e.index = 0
	e.position = pos
	e.pressed = true
	Input.parse_input_event(e)
	await _frames(1)
	if drag_to != null:
		var dr := InputEventScreenDrag.new()
		dr.index = 0
		dr.position = drag_to
		dr.relative = drag_to - pos
		Input.parse_input_event(dr)
		await _frames(1)
	await _frames(hold_frames)
	var u := InputEventScreenTouch.new()
	u.index = 0
	u.position = drag_to if drag_to != null else pos
	u.pressed = false
	Input.parse_input_event(u)
	await _frames(14)


func _test_relative() -> void:
	await _start("relative")
	var g: Game = main.game
	var rp: Vector2 = g._player_screen_pos()
	var size := get_viewport().get_visible_rect().size
	check(absf(rp.x - size.x * 0.5) < 40.0 and rp.y > size.y * 0.5 and rp.y < size.y * 0.8, "robot screen position is sane (%s in %s)" % [rp, size])
	await _touch(Vector2(20, rp.y))                       # far left edge, same height
	check(got == [Vector2i(-1, 0)], "relative: far left -> LEFT (%s)" % [got])
	check(C.x_to_col(g.player.px) == 3, "robot actually hopped left (col %d)" % C.x_to_col(g.player.px))
	got.clear()
	rp = g._player_screen_pos()
	await _touch(rp + Vector2(-60, 200))                  # lower-left, more below than left
	check(got == [Vector2i(0, -1)], "relative: lower-left (mostly below) -> DOWN (%s)" % [got])
	got.clear()
	await _touch(rp + Vector2(-220, 90))                  # lower-left, more left than below
	check(got == [Vector2i(-1, 0)], "relative: lower-left (mostly left) -> LEFT (%s)" % [got])
	got.clear()
	rp = g._player_screen_pos()
	await _touch(Vector2(size.x - 10, rp.y + 30))         # far right
	check(got == [Vector2i(1, 0)], "relative: far right -> RIGHT (%s)" % [got])
	got.clear()
	await _touch(g._player_screen_pos() + Vector2(5, 5))  # on the robot: dead zone
	check(got.is_empty(), "relative: touching the robot itself does nothing (%s)" % [got])
	got.clear()
	# Hold far to the right: keeps hopping right, then stops at the play edge / finger.
	await _touch(Vector2(size.x - 10, g._player_screen_pos().y), 70)
	var rights := got.filter(func(d): return d == Vector2i(1, 0)).size()
	check(rights >= 3 and got.size() == rights, "relative: holding repeats in one direction only (%s)" % [got])


func _test_dpad() -> void:
	await _start("dpad")
	var g: Game = main.game
	var c: Vector2 = g.input.dpad_center
	var r: float = g.input.dpad_radius
	var size := get_viewport().get_visible_rect().size
	check(r > 0.0 and c.x > size.x * 0.5 and c.y > size.y * 0.7, "dpad placed bottom-right (%s r=%.0f)" % [c, r])
	await _touch(c + Vector2(-r * 0.7, 0))
	check(got == [Vector2i(-1, 0)], "dpad: left arm -> LEFT (%s)" % [got])
	got.clear()
	await _touch(c + Vector2(0, r * 0.7))
	check(got == [Vector2i(0, -1)], "dpad: bottom arm -> DOWN (%s)" % [got])
	got.clear()
	await _touch(c + Vector2(-r * 0.7, 0), 2, c + Vector2(r * 0.7, 0))
	check(got == [Vector2i(-1, 0), Vector2i(1, 0)], "dpad: slide left->right hops both ways (%s)" % [got])
	got.clear()
	await _touch(Vector2(size.x * 0.5, size.y * 0.3))
	check(got.is_empty(), "dpad: tap outside the pad does nothing (%s)" % [got])
	check(not main.hud_layer.get_child(0).dash_btn.get_global_rect().has_point(c), "dash button does not overlap the D-pad")


func _test_swipe() -> void:
	await _start("swipe")
	var p := get_viewport().get_visible_rect().size * Vector2(0.5, 0.55)
	await _touch(p, 1, p + Vector2(-22, 3))   # short sideways flick, below drag threshold
	check(got == [Vector2i(-1, 0)], "swipe: short sideways flick hops sideways, not forward (%s)" % [got])
	got.clear()
	await _touch(p, 1, p + Vector2(60, 0))
	check(got == [Vector2i(1, 0)], "swipe: full swipe right -> RIGHT (%s)" % [got])
	got.clear()
	await _touch(p)
	check(got == [Vector2i(0, 1)], "swipe: tap -> forward (%s)" % [got])


func _test_planter() -> void:
	await _start("swipe")
	var g: Game = main.game
	var rs: RowState = g.row_state(0)
	rs.spec["planters"] = [3]
	rs.spec["blocked"] = [1]
	g._on_move(Vector2i(-1, 0))
	await _frames(20)
	check(C.x_to_col(g.player.px) == 3 and g.player.stand_z > 10.0, "robot hops up onto a flower planter (col %d, lift %.0f)" % [C.x_to_col(g.player.px), g.player.stand_z])
	g._on_move(Vector2i(-1, 0))
	await _frames(20)
	check(C.x_to_col(g.player.px) == 2 and g.player.stand_z < 1.0, "and back down (col %d)" % C.x_to_col(g.player.px))
	g._on_move(Vector2i(-1, 0))
	await _frames(20)
	check(C.x_to_col(g.player.px) == 2, "a tree still blocks (col %d)" % C.x_to_col(g.player.px))
