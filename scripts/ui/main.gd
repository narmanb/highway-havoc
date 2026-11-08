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

func show_settings(back: Callable, focus_touch := false) -> void:
	# Everything fits on one screen: compact slider rows (label | slider | value)
	# and toggles in two columns. D-pad sliders only appear in D-pad mode.
	var root := _new_screen(0.8)
	var m := UiTheme.safe_margins(get_viewport())
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_top", int(m["top"]) + 18)
	margin.add_theme_constant_override("margin_bottom", int(m["bottom"]) + 18)
	margin.add_theme_constant_override("margin_left", int(m["left"]) + 22)
	margin.add_theme_constant_override("margin_right", int(m["right"]) + 22)
	root.add_child(margin)
	var cc := CenterContainer.new()
	margin.add_child(cc)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(660, 0)
	v.add_theme_constant_override("separation", 8)
	cc.add_child(v)
	v.add_child(UiTheme.label("SETTINGS", 40, UiTheme.YELLOW))

	# Touch scheme
	var tm: String = GameState.settings["touch_mode"]
	var tb := UiTheme.button("Touch: %s" % GameState.TOUCH_MODE_NAMES[tm], func():
		var i := GameState.TOUCH_MODES.find(GameState.settings["touch_mode"])
		GameState.set_setting("touch_mode", GameState.TOUCH_MODES[(i + 1) % GameState.TOUCH_MODES.size()])
		show_settings(back, true), 68)
	tb.add_theme_font_size_override("font_size", 28)
	v.add_child(tb)
	var help := UiTheme.label(GameState.TOUCH_MODE_HELP[tm], 19, Color("c9d1e8"))
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size = Vector2(660, 0)
	v.add_child(help)

	var pct := func(x: float) -> String: return "%d%%" % roundi(x * 100.0)
	var set_key := func(key: String): return func(x: float): GameState.set_setting(key, x)
	var get_key := func(key: String): return func() -> float: return float(GameState.settings[key])
	var first := _slider_row(v, "Music", 0.0, 1.0, 0.05, get_key.call("music_vol"), set_key.call("music_vol"), pct)
	_slider_row(v, "Sound FX", 0.0, 1.0, 0.05, get_key.call("sfx_vol"), set_key.call("sfx_vol"), pct)
	_slider_row(v, "Screen shake", 0.0, 1.5, 0.05, get_key.call("shake"), set_key.call("shake"), pct)
	# Repeat speed is shown as hops per second, so right = faster.
	_slider_row(v, "Repeat speed", 3.0, 10.0, 0.5,
		func() -> float: return 1.0 / float(GameState.settings["repeat_rate"]),
		func(x: float): GameState.set_setting("repeat_rate", 1.0 / x),
		func(x: float) -> String: return "%.1f hops/s" % x)
	_slider_row(v, "Repeat starts", 0.12, 0.45, 0.01, get_key.call("repeat_delay"), set_key.call("repeat_delay"),
		func(x: float) -> String: return "after %.2fs" % x)
	if tm == "dpad":
		var preview := DpadPreview.new()
		root.add_child(preview)
		var poke := func(x: float, key: String):
			GameState.set_setting(key, x)
			preview.flash()
		_slider_row(v, "D-pad size", 90.0, 170.0, 5.0, get_key.call("dpad_size"), poke.bind("dpad_size"),
			func(x: float) -> String: return "%d" % roundi(x))
		_slider_row(v, "Arrow spread", 0.0, 1.0, 0.05, get_key.call("dpad_spread"), poke.bind("dpad_spread"), pct)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	v.add_child(grid)
	var q := ["LOW", "MEDIUM", "HIGH"]
	var qb := _small_button("Effects: %s" % q[GameState.quality()])
	qb.pressed.connect(func():
		Audio.play("ui_select")
		GameState.set_setting("quality", (GameState.quality() + 1) % 3)
		qb.text = "Effects: %s" % q[GameState.quality()])
	grid.add_child(qb)
	_toggle(grid, "Reduced flashing", "reduced_flash")
	_toggle(grid, "High contrast", "outlines")
	_toggle(grid, "Left-handed", "left_handed")
	if tm == "swipe":
		_toggle(grid, "Hold edges to hop", "hold_edges")
		_toggle(grid, "Double-tap dash", "double_tap_dash")
	_toggle(grid, "Hardcore (1 heart)", "hardcore")
	_toggle(grid, "30 FPS saver", "fps30")
	var done := UiTheme.button("BACK", back, 76)
	v.add_child(done)
	_focus_first(tb if focus_touch else first)


func _small_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(325, 62)
	b.add_theme_font_size_override("font_size", 23)
	b.focus_entered.connect(func(): Audio.play("ui_move"))
	return b


## One compact row: label | slider | live value.
func _slider_row(parent: Control, text: String, lo: float, hi: float, step: float,
		getter: Callable, setter: Callable, fmt: Callable) -> HSlider:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UiTheme.label(text, 23, Color("c9d1e8"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.custom_minimum_size = Vector2(170, 52)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = clampf(getter.call(), lo, hi)
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.custom_minimum_size = Vector2(0, 44)
	var val := UiTheme.label(fmt.call(s.value), 21, Color.WHITE)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.custom_minimum_size = Vector2(150, 52)
	s.value_changed.connect(func(x):
		setter.call(x)
		val.text = fmt.call(x))
	row.add_child(l)
	row.add_child(s)
	row.add_child(val)
	parent.add_child(row)
	return s


func _toggle(parent: Control, text: String, key: String) -> void:
	var b := _small_button("")
	b.toggle_mode = true
	b.button_pressed = bool(GameState.settings[key])
	var refresh := func(): b.text = ("ON  " if b.button_pressed else "OFF  ") + text
	refresh.call()
	b.toggled.connect(func(on):
		Audio.play("ui_select")
		GameState.set_setting(key, on)
		refresh.call())
	parent.add_child(b)


## Shows the real in-game D-pad (position, size and spread) while its sliders move.
class DpadPreview:
	extends Control
	var _t := 0.0

	func _init() -> void:
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func flash() -> void:
		_t = 1.6

	func _process(dt: float) -> void:
		if _t > 0.0:
			_t -= dt
			queue_redraw()

	func _draw() -> void:
		if _t <= 0.0:
			return
		var dl := UiTheme.dpad_layout(get_viewport())
		UiTheme.draw_dpad(self, dl["center"], dl["outer"], dl["inner"], Vector2i.ZERO, clampf(_t / 0.4, 0.0, 1.0))


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
