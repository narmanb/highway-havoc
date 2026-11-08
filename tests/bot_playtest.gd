extends Node
## End-to-end playtest: a simple "careful human" bot plays the real Game scene
## (real input path, collisions, signals, deliveries, background generation).
## Run:  godot --headless --path . --fixed-fps 60 res://tests/bot_playtest.tscn
## Prints a report and exits 0 if the bot made steady progress.

const SIM_SECONDS := 240.0
const REACTION := 0.2   # the bot only reacts every 0.2 s, like a human

var game: Game
var t := 0.0
var think := 0.0
var deaths := 0
var causes := {}
var mounts := 0
var signals := 0
var runs := 1
var careful_deaths := -1
var freeway_deliveries := 0


func _ready() -> void:
	_start()


func _start() -> void:
	if game:
		game.queue_free()
	game = Game.new()
	add_child(game)
	game.setup("arcade")
	game.player.died.connect(func(c, _v): deaths += 1; causes[c] = causes.get(c, 0) + 1)
	game.player.mounted.connect(func(_v): mounts += 1)
	game.delivered.connect(func(_i): if game.segments[game.cur - 1]["spec"]["district"] == "freeway": freeway_deliveries += 1)
	game.game_over.connect(func(_s): runs += 1; _start())


func _danger(r: int, x: float, horizon: float) -> bool:
	var rs: RowState = game.row_state(r)
	if rs == null:
		return true
	if rs.type != C.Row.ROAD:
		return rs.blocked(C.x_to_col(x))
	var a := x - C.PLAYER_HALF_W - 8.0
	var b := x + C.PLAYER_HALF_W + 8.0
	for v in rs.lane.vehicles:
		var lo: float = v.hit_min()
		var hi: float = v.hit_max()
		var d: float = v.speed * horizon * rs.lane.dir
		lo = minf(lo, lo + d)
		hi = maxf(hi, hi + d)
		if hi > a and lo < b:
			return true
	return false


func _process(dt: float) -> void:
	t += dt
	if t >= SIM_SECONDS:
		_report()
		return
	var p := game.player
	if p.state == PlayerHopController.S.DEAD or p.state == PlayerHopController.S.HOP or game.over:
		return
	think -= dt
	if think > 0.0:
		return
	think = REACTION
	if t > SIM_SECONDS - 50.0 and careful_deaths < 0:
		careful_deaths = deaths
	if t > SIM_SECONDS - 50.0:
		# Reckless phase: exercises death, respawn, game over and restart.
		game._on_move(Vector2i(0, 1))
		return
	var x := p.px
	var here := p.row
	var on_road := game.row_state(here).type == C.Row.ROAD and not p.is_riding()
	var up_ok := here + 1 <= game.max_row() and not _danger(here + 1, x, 0.45)
	# Wait for the walk signal when standing on a button pad.
	var rs: RowState = game.row_state(here)
	if rs.button_light != null and C.x_to_col(x) == rs.button_col():
		if rs.button_light.state != TrafficLight.GREEN and not rs.button_light.walk_safe():
			return
	if up_ok:
		game._on_move(Vector2i(0, 1))
		return
	if on_road and _danger(here, x, 0.4):
		for d in [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0)]:
			var nr: int = here + d.y
			var nx: float = x + d.x * C.TILE
			if nr >= game.min_row() and C.in_play_x(nx) and not _danger(nr, nx, 0.45):
				game._on_move(d)
				return
	if not on_road and not p.is_riding() and rs.type != C.Row.ROAD:
		# Head toward the crosswalk button sometimes, to exercise the signal.
		if rs.button_light != null and rs.button_light.can_press():
			var bc := rs.button_col()
			var c := C.x_to_col(x)
			if c != bc:
				game._on_move(Vector2i(signi(bc - c), 0))
				return


func _report() -> void:
	set_process(false)
	var s := game.score
	var total_deliveries := int(GameState.save["total_deliveries"])
	print("BOT PLAYTEST (%.0fs simulated)" % SIM_SECONDS)
	print("  runs started: %d   deaths: %d %s" % [runs, deaths, causes])
	print("  deliveries (all runs): %d   current score: %d   streak best: %d" % [total_deliveries, s.score, s.best_streak])
	print("  roof mounts: %d   near misses: %d   signals used: %d" % [mounts, s.near_misses, s.signals_used])
	print("  careful-phase deaths: %d   freeway deliveries: %d" % [careful_deaths, freeway_deliveries])
	print("  generator: ", RoadGenerator.stats)
	var ok := total_deliveries >= 8 and deaths >= 3 and runs >= 2 and freeway_deliveries >= 3
	print("RESULT: ", "PASS" if ok else "FAIL")
	get_tree().quit(0 if ok else 1)
