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
		"rush": main.start_game("rush")
		"settings": main.show_settings(main.show_title)
		"garage": main.show_garage()
		"results":
			main.start_game("arcade")
			main.show_results({"mode": "arcade", "score": 4210, "new_high": true, "breakdown": {"crossing": 900, "time": 1400, "near_miss": 650, "roof": 310, "pickups": 150, "doorstep": 100, "streak": 700}, "near_misses": 13, "roof_rides": 6, "pickups": 6, "deliveries": 7, "best_streak": 5})

func _process(dt: float) -> void:
	t += dt
	if shot == "game" and main.game and main.game.player and t > 0.8 and int(t * 10) % 7 == 0:
		var p = main.game.player
		if p.state == 0 and p.row < 3: main.game._on_move(Vector2i(0, 1))
	if t >= wait and not done:
		done = true
		var img := get_viewport().get_texture().get_image()
		img.save_png(out)
		print("saved ", out, " ", img.get_size())
		get_tree().quit()
