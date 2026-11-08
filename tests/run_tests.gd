extends SceneTree
## Headless logic tests. Run with:
##   godot --headless --path . -s tests/run_tests.gd
## Exits with code 0 when every check passes, 1 otherwise.

var failures := 0
var checks := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	test_lane_spacing()
	test_traffic_light_never_lies()
	test_generator_fairness()
	test_validator_rejects_unfair()
	test_determinism()
	test_districts()
	test_score()
	print("\n%d checks, %d failures (%.1fs)" % [checks, failures, (Time.get_ticks_msec() - t0) / 1000.0])
	quit(1 if failures > 0 else 0)


## Vehicles never overlap and (without signals) keep at least MIN_GAP_SECONDS apart.
func test_lane_spacing() -> void:
	var worst_gap_s := INF
	for s in 40:
		var l := LaneSim.new()
		var spd := 110.0 + s * 6.0
		l.setup(1 if s % 2 == 0 else -1, spd, RoadGenerator.MIXES["mixed"], 1.0, 2.5, 1000 + s)
		l.prewarm()
		for k in 1200:
			l.step(1.0 / 60.0)
			for i in range(1, l.vehicles.size()):
				var a: LaneSim.Vehicle = l.vehicles[i - 1]
				var b: LaneSim.Vehicle = l.vehicles[i]
				var gap := (a.x * l.dir - a.length * 0.5) - (b.x * l.dir + b.length * 0.5)
				worst_gap_s = minf(worst_gap_s, gap / spd)
	check(worst_gap_s >= C.MIN_GAP_SECONDS - 0.01, "min lane gap %.3fs >= %.2fs" % [worst_gap_s, C.MIN_GAP_SECONDS])
	print("lane spacing: worst gap %.2fs" % worst_gap_s)


## While the walk signal shows, no controlled-lane vehicle overlaps the crosswalk,
## and vehicles never overlap each other while queueing.
func test_traffic_light_never_lies() -> void:
	var walk_frames := 0
	var violations := 0
	var overlaps := 0
	var cycles := 0
	for s in 30:
		var lanes: Array = []
		for j in 3:
			var l := LaneSim.new()
			l.setup(1 if (s + j) % 2 == 0 else -1, 120.0 + 20.0 * j + s * 3.0,
				RoadGenerator.MIXES[["city", "bus", "mixed"][j]], 1.0, 2.6, s * 31 + j)
			lanes.append(l)
		var light := TrafficLight.new()
		light.setup(2 + s % 5, lanes)
		for l in lanes:
			l.prewarm()
		var rng := RandomNumberGenerator.new()
		rng.seed = s
		for k in 60 * 90:
			if light.can_press() and rng.randf() < 0.01:
				light.press()
				cycles += 1
			light.step(1.0 / 60.0)
			for l in lanes:
				l.step(1.0 / 60.0)
				for i in range(1, l.vehicles.size()):
					var a: LaneSim.Vehicle = l.vehicles[i - 1]
					var b: LaneSim.Vehicle = l.vehicles[i]
					if (a.x * l.dir - a.length * 0.5) < (b.x * l.dir + b.length * 0.5) - 0.5:
						overlaps += 1
			if light.walk_safe():
				walk_frames += 1
				var a2 := light.x - C.TILE * 0.5
				var b2 := light.x + C.TILE * 0.5
				for l in lanes:
					if l.vehicle_overlapping(a2, b2) != null:
						violations += 1
	check(cycles > 50, "signal cycled (%d)" % cycles)
	check(walk_frames > 1000, "walk phase reached (%d frames)" % walk_frames)
	check(violations == 0, "walk signal never lies (%d violations)" % violations)
	check(overlaps == 0, "queued vehicles never overlap (%d)" % overlaps)
	print("traffic light: %d cycles, %d walk frames, %d violations" % [cycles, walk_frames, violations])


## Every generated segment, at every difficulty, has a humane path.
func test_generator_fairness() -> void:
	RoadGenerator.stats = {"generated": 0, "rerolls": 0, "eased": 0}
	var count := 0
	var fails := 0
	var names: Array = RoadGenerator.TEMPLATES.keys()
	for name in names:
		for level in [1, 4, 8, 12, 18]:
			for s in 6:
				var rng := RandomNumberGenerator.new()
				rng.seed = s
				var start := RoadGenerator.make_start_row(rng)
				var spec := RoadGenerator.generate(777 + s, s, level, name, start)
				count += 1
				var res := SafePathValidator.validate(spec)
				if not res["ok"]:
					fails += 1
					printerr("  unfair: %s L%d s%d: %s" % [name, level, s, res["reason"]])
				# Structure checks.
				var rows: Array = spec["rows"]
				check(rows[0]["type"] == C.Row.SIDEWALK and rows[rows.size() - 1]["type"] == C.Row.SIDEWALK, "segment bounded by sidewalks")
				for r in rows:
					var pl: Array = r.get("planters", [])
					for c in pl:
						check(not (r.get("blocked", []) as Array).has(c) and r.get("button", -1) != c, "planters never overlap trees or the button")
				check(spec["district"] == RoadGenerator.district_of_template(name), "district tagged")
				if not spec["light"].is_empty():
					var br: Dictionary = rows[spec["light"]["button_row"]]
					check(not (br.get("blocked", []) as Array).has(spec["light"]["column"]), "button cell is free")
	check(fails == 0, "all %d generated segments validated (%d unfair)" % [count, fails])
	print("generator: %d segments, rerolls %d, eased %d" % [count, RoadGenerator.stats["rerolls"], RoadGenerator.stats["eased"]])


## A deliberately impossible lane setup must be rejected.
func test_validator_rejects_unfair() -> void:
	var rng := RandomNumberGenerator.new()
	var rows: Array = [RoadGenerator.make_start_row(rng)]
	for i in 5:
		rows.append({"type": C.Row.ROAD, "dir": 1, "speed": 200.0, "mix": [["bus", 1.0]], "gap_min": 1.0, "gap_max": 1.0, "seed": i})
	rows.append({"type": C.Row.SIDEWALK, "blocked": [], "button": -1, "locker": 3})
	var res := SafePathValidator.validate({"rows": rows, "start_col": 4})
	check(not res["ok"], "five lanes without refuge rejected")
	# The drift search: a river with no decks can never be crossed; a solid deck can.
	var wrows: Array = [RoadGenerator.make_start_row(rng), {"type": C.Row.WATER}, {"type": C.Row.SIDEWALK, "blocked": [], "button": -1}]
	var empty_cov: Array = []
	var full_cov: Array = []
	for k in 200:
		empty_cov.append(PackedFloat32Array())
		full_cov.append(PackedFloat32Array([-1000.0, 1000.0]))
	check(SafePathValidator._search_drift(wrows, {}, {1: empty_cov}, {1: 10.0}, 0, 150, 0.0) == -1, "drift search rejects a river with no decks")
	check(SafePathValidator._search_drift(wrows, {}, {1: full_cov}, {1: 10.0}, 0, 150, 0.0) == 2, "drift search crosses a solid deck in two hops")
	# A deck that drifts the robot into the edge before the far bank is reachable is rejected.
	var edge_cov: Array = []
	for k in 200:
		edge_cov.append(PackedFloat32Array([-30.0 + k * 400.0, 30.0 + k * 400.0]))
	check(SafePathValidator._search_drift(wrows, {}, {1: edge_cov}, {1: 400.0}, 0, 150, 0.0) == -1, "drift search never boards a deck that leaves immediately")
	wrows[1] = {"type": C.Row.WATER, "dir": 1, "speed": 80.0, "mix": [["barge", 1.0]], "gap_min": 0.3, "gap_max": 0.3, "seed": 3}
	# ...and a real river packed with barges is accepted.
	check(SafePathValidator.validate({"rows": wrows, "start_col": 4})["ok"], "dense barge river accepted")
	# A goal sidewalk that is completely blocked is rejected structurally.
	var rows3: Array = rows.slice(0, 3)
	rows3.append({"type": C.Row.SIDEWALK, "blocked": [0, 1, 2, 3, 4, 5, 6, 7, 8], "button": -1, "locker": 3})
	check(not SafePathValidator.validate({"rows": rows3, "start_col": 4})["ok"], "blocked goal rejected")
	# The search itself: a lane that is permanently covered can never be crossed.
	var srows: Array = [rows[0], {"type": C.Row.ROAD}, rows[rows.size() - 1]]
	var covered: Array = []
	for k in 200:
		covered.append(PackedFloat32Array([-5000.0, 5000.0]))
	check(SafePathValidator._search(srows, {1: covered}, 0, 150, 4) == -1, "search rejects a permanently covered lane")
	var open_lane: Array = []
	for k in 200:
		open_lane.append(PackedFloat32Array([-5000.0, -4000.0]))
	check(SafePathValidator._search(srows, {1: open_lane}, 0, 150, 4) == 2, "search finds a two-hop path over an empty lane")


func test_districts() -> void:
	check(RoadGenerator.district_for(0, "arcade") == "downtown" and RoadGenerator.district_for(4, "arcade") == "downtown", "crossings 1-5 downtown")
	check(RoadGenerator.district_for(5, "arcade") == "freeway" and RoadGenerator.district_for(9, "arcade") == "freeway", "crossings 6-10 freeway")
	check(RoadGenerator.district_for(10, "arcade") == "riverfront" and RoadGenerator.district_for(14, "arcade") == "riverfront", "crossings 11-15 riverfront")
	check(RoadGenerator.district_for(15, "arcade") == "downtown", "then back to downtown")
	check(RoadGenerator.district_for(4, "rush") == "riverfront" and RoadGenerator.district_for(2, "rush") == "freeway", "rush visits all three")
	var rng := RandomNumberGenerator.new()
	var spec := RoadGenerator.generate(99, 5, 6, "Truck Convoy", RoadGenerator.make_start_row(rng))
	var dirs := []
	for r in spec["rows"]:
		if r["type"] == C.Row.ROAD:
			dirs.append(r["dir"])
		elif r.get("style", "") == "barrier":
			dirs.append(0)
	# Freeway carriageways: one direction per side of each barrier.
	check(dirs == [dirs[0], dirs[0], 0, -dirs[0], -dirs[0], 0, dirs[0], dirs[0]], "freeway lanes flip only at barriers %s" % [dirs])


func test_determinism() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var a := RoadGenerator.generate(4242, 3, 6, "Main Street", RoadGenerator.make_start_row(rng))
	rng.seed = 5
	var b := RoadGenerator.generate(4242, 3, 6, "Main Street", RoadGenerator.make_start_row(rng))
	var same: bool = a["rows"].size() == b["rows"].size()
	for i in a["rows"].size():
		if a["rows"][i]["type"] == C.Row.ROAD:
			same = same and is_equal_approx(a["rows"][i]["speed"], b["rows"][i]["speed"]) and a["rows"][i]["seed"] == b["rows"][i]["seed"]
	check(same, "same seed -> same segment")


func test_score() -> void:
	var s := ScoreAndStreak.new()
	s.add_near_miss(1)
	s.add_near_miss(1)  # same vehicle: capped
	check(s.near_misses == 1, "near miss capped per vehicle")
	var d := s.deliver(10.0, 1, false)
	check(d["total"] > 0 and s.streak == 1, "delivery scores and advances streak")
	s.deliver(5.0, 2, true)
	check(s.streak == 2 and s.multiplier() > 1.0, "streak multiplier grows")
	s.lose_life()
	check(s.streak == 0 and is_equal_approx(s.multiplier(), 1.0), "streak resets on hit")
