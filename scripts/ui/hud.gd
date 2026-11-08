extends Control
## Gameplay HUD: lives, score, parcel streak, crossing, time bonus bar, dash charge,
## pause button, onboarding hint. Touch buttons hide while a gamepad is in use.

var game: Game
var dash_btn: Button
var pause_btn: Button
var score_lbl: Label
var best_lbl: Label
var info_lbl: Label
var hint_lbl: Label
var rush_lbl: Label
var banner_lbl: Label
var _banner_t := 0.0
var _margins := {}


func setup(p_game: Game) -> void:
	game = p_game
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_lbl = UiTheme.label("0", 52)
	best_lbl = UiTheme.label("", 22, Color("c9d1e8"))
	info_lbl = UiTheme.label("", 24, Color("ffd23f"))
	hint_lbl = UiTheme.label("", 34)
	rush_lbl = UiTheme.label("", 24, Color("9de8ff"))
	banner_lbl = UiTheme.label("", 48, Color("ffd23f"))
	for l in [score_lbl, best_lbl, info_lbl, hint_lbl, rush_lbl, banner_lbl]:
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
	hint_lbl.text = "SWIPE  or  TAP  TO HOP" if not GameState.last_device_pad else "D-PAD TO HOP   A TO DASH"
	dash_btn = Button.new()
	dash_btn.text = "DASH"
	dash_btn.focus_mode = Control.FOCUS_NONE
	dash_btn.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	dash_btn.custom_minimum_size = Vector2(150, 150)
	dash_btn.add_theme_font_size_override("font_size", 30)
	dash_btn.pressed.connect(func(): game._on_dash())
	add_child(dash_btn)
	pause_btn = Button.new()
	pause_btn.text = "II"
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.custom_minimum_size = Vector2(96, 96)
	pause_btn.pressed.connect(func(): game.pause_requested.emit())
	add_child(pause_btn)
	game.input.exclusion = [dash_btn, pause_btn]
	game.delivered.connect(_on_delivered)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	_margins = UiTheme.safe_margins(get_viewport())
	var s := get_viewport().get_visible_rect().size
	var top: float = _margins["top"] + 14.0
	var lh: bool = GameState.settings["left_handed"]
	score_lbl.position = Vector2(0, top)
	score_lbl.size = Vector2(s.x, 60)
	best_lbl.position = Vector2(0, top + 58)
	best_lbl.size = Vector2(s.x, 28)
	info_lbl.position = Vector2(0, top + 112)
	info_lbl.size = Vector2(s.x, 30)
	rush_lbl.position = Vector2(0, top + 144)
	rush_lbl.size = Vector2(s.x, 30)
	hint_lbl.position = Vector2(0, s.y * 0.80)
	hint_lbl.size = Vector2(s.x, 50)
	banner_lbl.position = Vector2(0, s.y * 0.3)
	banner_lbl.size = Vector2(s.x, 60)
	var bottom: float = s.y - _margins["bottom"] - 28.0
	var side_r: float = s.x - _margins["right"] - 28.0
	var side_l: float = _margins["left"] + 28.0
	dash_btn.size = dash_btn.custom_minimum_size
	pause_btn.size = pause_btn.custom_minimum_size
	dash_btn.position = Vector2((side_l if lh else side_r - 150.0), bottom - 150.0)
	pause_btn.position = Vector2((side_l if lh else side_r - 96.0), top)


func _on_delivered(info: Dictionary) -> void:
	var m: float = info["multiplier"]
	banner_lbl.text = "DELIVERED!" if m <= 1.0 else "DELIVERED!  x%.1f" % m
	_banner_t = 1.4


func _process(dt: float) -> void:
	if game == null:
		return
	var pad := GameState.last_device_pad
	dash_btn.visible = not pad
	pause_btn.visible = not pad
	dash_btn.text = "DASH\n%d" % game.dash_charges
	dash_btn.disabled = game.dash_charges <= 0
	score_lbl.text = str(game.score.score)
	var best_key := "rush_best" if game.mode == "rush" else "high_score"
	best_lbl.text = "BEST %d" % maxi(int(GameState.save[best_key]), game.score.score)
	var streak := game.score.streak
	info_lbl.text = "CROSSING %d" % game.crossing_number() + ("    STREAK %d  x%.1f" % [streak, game.score.multiplier()] if streak > 0 else "")
	if game.mode == "rush":
		rush_lbl.text = "RUSH %d/%d   %ds   %s (%s)" % [game.score.deliveries, Game.RUSH_DELIVERIES,
			ceili(game.rush_time), game.objective.get("text", ""), game.objective_progress()]
	hint_lbl.visible = not game.has_moved
	if hint_lbl.visible:
		hint_lbl.modulate.a = 0.6 + 0.4 * sin(game.anim_time * 4.0)
	if _banner_t > 0.0:
		_banner_t -= dt
		banner_lbl.modulate.a = clampf(_banner_t / 0.4, 0.0, 1.0)
	banner_lbl.visible = _banner_t > 0.0
	queue_redraw()


func _draw() -> void:
	if game == null:
		return
	var s := get_viewport().get_visible_rect().size
	var top: float = _margins.get("top", 0.0) + 14.0
	var left: float = _margins.get("left", 0.0) + 24.0
	if GameState.settings["left_handed"]:
		left = s.x - _margins.get("right", 0.0) - 24.0 - game.max_lives * 44.0
	# Hearts
	for i in game.max_lives:
		_heart(Vector2(left + 20 + i * 44, top + 30), i < game.lives)
	# Time bonus bar
	var w := minf(s.x * 0.6, 420.0)
	var bx := (s.x - w) * 0.5
	var by := top + 92.0
	var frac := clampf(game.time_left() / maxf(game.par_time, 0.01), 0.0, 1.0)
	draw_rect(Rect2(bx - 3, by - 3, w + 6, 16), UiTheme.INK)
	draw_rect(Rect2(bx, by, w, 10), Color("2a2f40"))
	draw_rect(Rect2(bx, by, w * frac, 10), Color("ff5d5d").lerp(Color("3dff6e"), frac))
	# Dash pips over the button
	if dash_btn.visible:
		var c := dash_btn.position + dash_btn.size * 0.5
		for i in C.MAX_DASH_CHARGES:
			var a := -PI * 0.5 + (i - 1) * 0.5
			var p := c + Vector2(cos(a), sin(a)) * 92.0
			draw_circle(p, 10.0, UiTheme.INK)
			draw_circle(p, 7.0, UiTheme.YELLOW if i < game.dash_charges else Color("3a3f50"))


func _heart(c: Vector2, full: bool) -> void:
	var col := Color("ff4d6d") if full else Color("3a3f50")
	var pts := PackedVector2Array()
	for i in 24:
		var t := TAU * i / 24.0
		pts.append(c + Vector2(16 * pow(sin(t), 3), -(13 * cos(t) - 5 * cos(2 * t) - 2 * cos(3 * t) - cos(4 * t))) * 1.1)
	draw_colored_polygon(pts, UiTheme.INK)
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c + (p - c) * 0.8)
	draw_colored_polygon(inner, col)
	if full:
		draw_circle(c + Vector2(-7, -6), 3.5, Color(1, 1, 1, 0.6))
