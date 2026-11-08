extends Node
## App shell: title (with live traffic behind it), Settings, Garage, gameplay + HUD,
## pause menu and results. Every screen is controller-navigable.

var game: Game
var ui: CanvasLayer
var hud_layer: CanvasLayer
var screen: Control
var theme_res: Theme
var _last_mode := "arcade"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme_res = UiTheme.build()
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 5
	add_child(hud_layer)
	ui = CanvasLayer.new()
	ui.layer = 10
	add_child(ui)
	_vignette()
	Audio.start_music()
	show_title()


func _vignette() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 4
	add_child(layer)
	var tr := TextureRect.new()
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.05, 1.05)
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0.02, 0.02, 0.08, 0.45))
	g.gradient = grad
	tr.texture = g
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(tr)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		if game != null and game.mode != "attract" and not game.over and not get_tree().paused:
			show_pause()


# ---------------------------------------------------------------- helpers

func _clear_screen() -> void:
	if screen != null:
		screen.queue_free()
		screen = null


func _new_screen(dim := 0.0) -> Control:
	_clear_screen()
	var root := Control.new()
	root.theme = theme_res
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	if dim > 0.0:
		var bg := ColorRect.new()
		bg.color = Color(0.03, 0.04, 0.08, dim)
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		root.add_child(bg)
	ui.add_child(root)
	screen = root
	return root


func _center_column(root: Control, width := 560.0) -> VBoxContainer:
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(cc)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(width, 0)
	v.add_theme_constant_override("separation", 18)
	cc.add_child(v)
	return v


func _set_game(mode: String) -> void:
	if game != null:
		game.queue_free()
	for c in hud_layer.get_children():
		c.queue_free()
	game = Game.new()
	game.name = "Game"
	add_child(game)
	move_child(game, 0)
	game.setup(mode)
	game.pause_requested.connect(show_pause)
	game.game_over.connect(show_results)


func _focus_first(btn: Control) -> void:
	btn.call_deferred("grab_focus")


# ---------------------------------------------------------------- title

func show_title() -> void:
	get_tree().paused = false
	_set_game("attract")
	var root := _new_screen(0.4)
	var v := _center_column(root)
	var logo := TitleLogo.new()
	logo.custom_minimum_size = Vector2(560, 300)
	v.add_child(logo)
	var hs := UiTheme.label("BEST %d    RUSH BEST %d" % [GameState.save["high_score"], GameState.save["rush_best"]], 26, Color("c9d1e8"))
	v.add_child(hs)
	var play := UiTheme.button("PLAY", func(): start_game("arcade"), 110)
	play.add_theme_font_size_override("font_size", 46)
	v.add_child(play)
	v.add_child(UiTheme.button("DELIVERY RUSH", func(): start_game("rush")))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	var garage := UiTheme.button("GARAGE", show_garage)
	var settings := UiTheme.button("SETTINGS", func(): show_settings(show_title))
	garage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(garage)
	row.add_child(settings)
	v.add_child(row)
	v.add_child(UiTheme.label("Deliveries: %d" % GameState.save["total_deliveries"], 22, Color("8f97ad")))
	_focus_first(play)


func start_game(mode: String) -> void:
	_last_mode = mode
	get_tree().paused = false
	_clear_screen()
	_set_game(mode)
	var hud := preload("res://scripts/ui/hud.gd").new()
	hud.theme = theme_res
	hud_layer.add_child(hud)
	hud.setup(game)


# ---------------------------------------------------------------- pause

func show_pause() -> void:
	if game == null or game.over or game.mode == "attract":
		return
	if get_tree().paused:
		_resume()
		return
	get_tree().paused = true
	var root := _new_screen(0.6)
	var v := _center_column(root, 480)
	v.add_child(UiTheme.label("PAUSED", 56, UiTheme.YELLOW))
	var resume := UiTheme.button("RESUME", _resume)
	v.add_child(resume)
	v.add_child(UiTheme.button("RESTART", func(): start_game(_last_mode)))
	v.add_child(UiTheme.button("SETTINGS", func(): show_settings(_reopen_pause)))
	v.add_child(UiTheme.button("QUIT", show_title))
	_focus_first(resume)


func _reopen_pause() -> void:
	get_tree().paused = false
	show_pause()


func _resume() -> void:
	_clear_screen()
	get_tree().paused = false


func _unhandled_input(event: InputEvent) -> void:
	# Controller/back: cancel closes the pause menu.
	if screen != null and get_tree().paused and event.is_action_pressed("pause"):
		_resume()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- results

func show_results(summary: Dictionary) -> void:
	var root := _new_screen(0.7)
	var v := _center_column(root, 600)
	var title := "DELIVERY RUSH" if summary["mode"] == "rush" else "SHIFT OVER"
	v.add_child(UiTheme.label(title, 48, UiTheme.YELLOW))
	if summary["new_high"]:
		v.add_child(UiTheme.label("NEW BEST!", 36, Color("ff9df0")))
	v.add_child(UiTheme.label(str(summary["score"]), 84))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	var bd: Dictionary = summary["breakdown"]
	var lines := [
		["Crossings", bd.get("crossing", 0)], ["Time bonus", bd.get("time", 0)],
		["Close calls (%d)" % summary["near_misses"], bd.get("near_miss", 0)],
		["Roof rides (%d)" % summary["roof_rides"], bd.get("roof", 0)],
		["Bolts (%d)" % summary["pickups"], bd.get("pickups", 0)], ["Doorstep", bd.get("doorstep", 0)],
		["Streak bonus", bd.get("streak", 0)],
	]
	if bd.has("objective"):
		lines.append(["Objective", bd["objective"]])
	for l in lines:
		var a := UiTheme.label(l[0], 26, Color("c9d1e8"))
		a.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		var b := UiTheme.label(str(l[1]), 26)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(a)
		grid.add_child(b)
	v.add_child(grid)
	v.add_child(UiTheme.label("Deliveries %d    Best streak %d" % [summary["deliveries"], summary["best_streak"]], 26, Color("ffd23f")))
	if summary["mode"] == "rush":
		var ok: bool = summary.get("objective_met", false) and summary.get("rush_complete", false)
		v.add_child(UiTheme.label(("OBJECTIVE COMPLETE: " if ok else "Objective missed: ") + summary.get("objective", ""), 24,
			Color("9dff9d") if ok else Color("ff9d9d")))
	var retry := UiTheme.button("RETRY", func(): start_game(_last_mode), 140)
	retry.add_theme_font_size_override("font_size", 60)
	v.add_child(retry)
	v.add_child(UiTheme.button("MENU", show_title))
	_focus_first(retry)


# ---------------------------------------------------------------- settings

func show_settings(back: Callable) -> void:
	var root := _new_screen(0.75)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := UiTheme.safe_margins(get_viewport())
	margin.add_theme_constant_override("margin_top", int(m["top"]) + 30)
	margin.add_theme_constant_override("margin_bottom", int(m["bottom"]) + 30)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_right", 30)
	root.add_child(margin)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 16)
	margin.add_child(outer)
	outer.add_child(UiTheme.label("SETTINGS", 48, UiTheme.YELLOW))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	outer.add_child(scroll)
	var cc := CenterContainer.new()
	cc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(cc)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(600, 0)
	v.add_theme_constant_override("separation", 12)
	cc.add_child(v)
	# Touch control scheme (first, it's the one players most want to change).
	var help := UiTheme.label("", 22, Color("c9d1e8"))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(600, 0)
	var tb := UiTheme.button("", func(): pass, 88)
	var refresh_touch := func():
		var tm: String = GameState.settings["touch_mode"]
		tb.text = "Touch: %s" % GameState.TOUCH_MODE_NAMES[tm]
		help.text = GameState.TOUCH_MODE_HELP[tm]
	refresh_touch.call()
	tb.pressed.connect(func():
		var i := GameState.TOUCH_MODES.find(GameState.settings["touch_mode"])
		GameState.set_setting("touch_mode", GameState.TOUCH_MODES[(i + 1) % GameState.TOUCH_MODES.size()])
		refresh_touch.call())
	v.add_child(tb)
	v.add_child(help)
	var first := tb
	_slider(v, "Music", "music_vol", 0.0, 1.0)
	_slider(v, "Sound effects", "sfx_vol", 0.0, 1.0)
	_slider(v, "Screen shake", "shake", 0.0, 1.5)
	_slider(v, "Hold-repeat delay", "repeat_rate", 0.10, 0.30)
	var q := ["LOW", "MEDIUM", "HIGH"]
	var qb := UiTheme.button("Effects: %s" % q[GameState.quality()], func(): pass, 80)
	qb.pressed.connect(func():
		GameState.set_setting("quality", (GameState.quality() + 1) % 3)
		qb.text = "Effects: %s" % q[GameState.quality()])
	v.add_child(qb)
	_toggle(v, "Reduced flashing", "reduced_flash")
	_toggle(v, "High-contrast outlines", "outlines")
	_toggle(v, "Left-handed layout", "left_handed")
	_toggle(v, "Hold screen edges to hop", "hold_edges")
	_toggle(v, "Double-tap to dash (tap no longer hops)", "double_tap_dash")
	_toggle(v, "Hardcore (one heart)", "hardcore")
	_toggle(v, "30 FPS battery saver", "fps30")
	var done := UiTheme.button("BACK", back)
	outer.add_child(done)
	_focus_first(first)


func _slider(parent: Control, text: String, key: String, lo: float, hi: float) -> HSlider:
	var l := UiTheme.label(text, 26, Color("c9d1e8"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	parent.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = (hi - lo) / 20.0
	s.value = float(GameState.settings[key])
	s.custom_minimum_size = Vector2(0, 48)
	s.value_changed.connect(func(val): GameState.set_setting(key, val))
	parent.add_child(s)
	return s


func _toggle(parent: Control, text: String, key: String) -> void:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = bool(GameState.settings[key])
	b.custom_minimum_size = Vector2(0, 76)
	b.add_theme_font_size_override("font_size", 26)
	var refresh := func(): b.text = ("[ON]   " if b.button_pressed else "[OFF]  ") + text
	refresh.call()
	b.toggled.connect(func(on):
		Audio.play("ui_select")
		GameState.set_setting(key, on)
		refresh.call())
	parent.add_child(b)


# ---------------------------------------------------------------- garage

func show_garage() -> void:
	var root := _new_screen(0.7)
	var v := _center_column(root, 600)
	v.add_child(UiTheme.label("GARAGE", 48, UiTheme.YELLOW))
	v.add_child(UiTheme.label("Costumes unlock with total deliveries", 22, Color("c9d1e8")))
	var preview := RobotPreview.new()
	preview.custom_minimum_size = Vector2(600, 180)
	v.add_child(preview)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	v.add_child(grid)
	var first: Button = null
	for i in GameState.PALETTES.size():
		var p: Dictionary = GameState.PALETTES[i]
		var unlocked := GameState.palette_unlocked(i)
		var label: String = p["name"] if unlocked else "LOCKED (%d)" % p["unlock"]
		var b := UiTheme.button(label, func():
			GameState.set_palette(i)
			preview.queue_redraw()
			show_garage(), 80)
		b.add_theme_font_size_override("font_size", 24)
		b.disabled = not unlocked
		b.custom_minimum_size.x = 290
		if i == int(GameState.save["palette"]):
			b.text = "> " + label
		b.focus_entered.connect(func(): preview.palette = p if unlocked else GameState.palette(); preview.queue_redraw())
		grid.add_child(b)
		if first == null and i == int(GameState.save["palette"]):
			first = b
	var back := UiTheme.button("BACK", show_title)
	v.add_child(back)
	_focus_first(first if first else back)


class RobotPreview:
	extends Control
	var palette: Dictionary = GameState.palette()
	var t := 0.0

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.85)
		var facings := [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1)]
		for i in 3:
			Art.robot(self, c + Vector2((i - 1) * 170, 0), palette, facings[i], absf(sin(t * 3.0 + i)) * 10.0, 0.0, t,
				"happy" if i == 0 else "normal", true, 0.0, 2.2)


class TitleLogo:
	extends Control
	var t := 0.0

	func _process(dt: float) -> void:
		t += dt
		queue_redraw()

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var cx := size.x * 0.5
		var words := ["HIGHWAY", "HAVOC"]
		var cols := [Color.WHITE, UiTheme.YELLOW]
		for i in 2:
			var fs := 92 if i == 0 else 112
			var w := font.get_string_size(words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var p := Vector2(cx - w * 0.5, 100 + i * 110 + sin(t * 2.0 + i) * 4.0)
			draw_string_outline(font, p + Vector2(0, 8), words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 22, Color(0, 0, 0, 0.5))
			draw_string_outline(font, p, words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 18, UiTheme.INK)
			draw_string(font, p, words[i], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, cols[i])
		var hop := absf(sin(t * 4.0)) * 24.0
		Art.robot(self, Vector2(cx + 220, 290), GameState.palette(), Vector2i(-1, 0), hop, 0.0, t, "normal", true, 0.0, 1.6)
