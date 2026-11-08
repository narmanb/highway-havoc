extends Node
## Screenshot helper (development only).
## xvfb-run godot --path . res://tools/capture.tscn -- <screen> <seconds> <out.png>
## screen: title | game | settings | garage | results

var main: Node
var shot := "game"
var wait := 3.0
var out := "user://shot.png"
var t := 0.0
var done := false

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0: shot = a[0]
	if a.size() > 1: wait = float(a[1])
	if a.size() > 2: out = a[2]
	main = load("res://scripts/ui/main.gd").new()
	add_child(main)
	await get_tree().process_frame
	match shot:
		"game", "ride": main.start_game("arcade")
		"dpad", "relative":
			GameState.settings["touch_mode"] = shot
			main.start_game("arcade")
		"rush": main.start_game("rush")
		"settings", "settings_dpad", "settings_relative":
			GameState.settings["touch_mode"] = {"settings": "swipe", "settings_dpad": "dpad", "settings_relative": "relative"}[shot]
			main.show_settings(main.show_title)
			if shot == "settings_dpad":
				for c in main.screen.get_children():
					if c.has_method("flash"): c.flash()
		"freeway", "river":
			main.start_game("arcade")
			await get_tree().process_frame
			for i in (5 if shot == "freeway" else 11):
				main.game._deliver(0.0)
				main.game.player.respawn(main.game.min_row(), 0.0)
			main.game.camera.snap_to(C.row_to_y(main.game.min_row()))
		"garage": main.show_garage()
		"results":
			main.start_game("arcade")
			main.show_results({"mode": "arcade", "score": 4210, "new_high": true, "breakdown": {"crossing": 900, "time": 1400, "near_miss": 650, "roof": 310, "pickups": 150, "doorstep": 100, "streak": 700}, "near_misses": 13, "roof_rides": 6, "pickups": 6, "deliveries": 7, "best_streak": 5})

func _process(dt: float) -> void:
	t += dt
	if shot == "game" and main.game and main.game.player and t > 0.8 and int(t * 10) % 7 == 0:
		var p = main.game.player
		if p.state == 0 and p.row < 3: main.game._on_move(Vector2i(0, 1))
	if shot == "relative" and main.game and absf(t - (wait - 0.12)) < dt * 0.6:
		var e := InputEventScreenTouch.new()
		e.pressed = true
		e.position = get_viewport().get_final_transform() * (main.game._player_screen_pos() + Vector2(-230, 60))
		Input.parse_input_event(e)
	if shot == "dpad" and main.game and absf(t - (wait - 0.05)) < dt * 0.6:
		var e2 := InputEventScreenTouch.new()
		e2.pressed = true
		e2.position = get_viewport().get_final_transform() * (main.game.input.dpad_center + Vector2(-80, 0))
		Input.parse_input_event(e2)
	if t >= wait and not done:
		done = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(out)
		print("saved ", out, " ", img.get_size())
		get_tree().quit()
