class_name SafePathValidator
extends RefCounted
## Fairness guard. Rebuilds a segment's lanes with the exact runtime LaneSim code,
## predicts the traffic, and searches for a crossing that works with *human* timing:
##   * time advances in coarse 0.15 s decisions (slower than a 0.11 s hop),
##   * every vehicle hitbox is inflated by a safety margin on both ends,
##   * truck roofs are treated as lethal (riding is a bonus, never a requirement),
##   * the crosswalk button is never pressed (signals only ever remove danger),
##   * the crossing must succeed from several different start times, so whenever
##     the player arrives, a reachable opening appears within the time budget.
##   * Riverfront: on water the robot drifts with its platform, so crossings with
##     water use a search over continuous x (quantised to 6 px) that follows the drift.
##     The robot's centre must be at least 12 px inside a deck to count as aboard,
##     and it may never be carried within half a tile of the play edge.

const DT := 0.15
const MARGIN := 14.0
const START_TIMES := [0.0, 2.6, 5.2, 7.8, 10.4]
const BUDGET_S := 24.0
const PLATFORM_MARGIN := 12.0
const Q := 6.0


static func build_lanes(spec: Dictionary) -> Dictionary:
	var lanes := {}
	var rows: Array = spec["rows"]
	for i in rows.size():
		var r: Dictionary = rows[i]
		if r["type"] == C.Row.ROAD or r["type"] == C.Row.WATER:
			var l := LaneSim.new()
			l.setup(r["dir"], r["speed"], r["mix"], r["gap_min"], r["gap_max"], r["seed"], r["type"] == C.Row.WATER)
			l.prewarm()
			lanes[i] = l
	return lanes


static func validate(spec: Dictionary) -> Dictionary:
	var rows: Array = spec["rows"]
	var n := rows.size()
	var result := {"ok": false, "reason": "", "worst_steps": 0}

	# Structural rule: refuge rows must appear often enough.
	var run := 0
	for r in rows:
		if r["type"] == C.Row.ROAD or r["type"] == C.Row.WATER:
			run += 1
			if run > C.MAX_LANES_WITHOUT_REFUGE:
				result["reason"] = "too many lanes without refuge"
				return result
		else:
			run = 0
	# Structural rule: every safe row must leave at least two open cells.
	for r in rows:
		if _is_safe(r) and (r.get("blocked", []) as Array).size() > C.COLS - 2:
			result["reason"] = "safe row blocked"
			return result

	var lanes := build_lanes(spec)
	var budget_steps := int(BUDGET_S / DT)
	var last_start := int(START_TIMES[START_TIMES.size() - 1] / DT)
	var total_steps := last_start + budget_steps + 1

	# Predict swept lethal intervals per lane per step.
	var sweeps := {}  # row index -> Array[PackedFloat32Array]
	var covers := {}  # water row index -> Array[PackedFloat32Array] of deck intervals at each step boundary
	var drifts := {}  # water row index -> px moved per step
	var view := C.PLAY_HALF_W + 260.0
	for i in lanes:
		var l: LaneSim = lanes[i]
		if l.water:
			var cov: Array = []
			cov.resize(total_steps + 1)
			for k in total_steps + 1:
				var arr2 := PackedFloat32Array()
				for v in l.vehicles:
					var a2: float = v.x - v.length * 0.5 + PLATFORM_MARGIN
					var b2: float = v.x + v.length * 0.5 - PLATFORM_MARGIN
					if b2 < -view or a2 > view:
						continue
					arr2.append(a2)
					arr2.append(b2)
				cov[k] = arr2
				l.step(DT)
			covers[i] = cov
			drifts[i] = l.dir * l.speed * DT
			continue
		var per_step: Array = []
		per_step.resize(total_steps)
		for k in total_steps:
			var before := {}
			for v in l.vehicles:
				before[v.id] = Vector2(v.hit_min(), v.hit_max())
			l.step(DT)
			var arr := PackedFloat32Array()
			for v in l.vehicles:
				var a: float = v.hit_min()
				var b: float = v.hit_max()
				if before.has(v.id):
					a = minf(a, before[v.id].x)
					b = maxf(b, before[v.id].y)
				if b < -view or a > view:
					continue
				arr.append(a - MARGIN)
				arr.append(b + MARGIN)
			per_step[k] = arr
		sweeps[i] = per_step

	var start_col := int(spec.get("start_col", C.CENTER_COL))
	for t0 in START_TIMES:
		var k0 := int(t0 / DT)
		var steps: int
		if covers.is_empty():
			steps = _search(rows, sweeps, k0, budget_steps, start_col)
		else:
			steps = _search_drift(rows, sweeps, covers, drifts, k0, budget_steps, C.col_to_x(start_col))
		if steps < 0:
			result["reason"] = "no humane path from t=%.1f" % t0
			return result
		result["worst_steps"] = maxi(result["worst_steps"], steps)
	result["ok"] = true
	return result


static func _is_safe(r: Dictionary) -> bool:
	return r["type"] == C.Row.SIDEWALK or r["type"] == C.Row.MEDIAN


static func _cell_safe(rows: Array, sweeps: Dictionary, row: int, col: int, k: int) -> bool:
	var r: Dictionary = rows[row]
	if _is_safe(r):
		return not (r.get("blocked", []) as Array).has(col)
	var cx := C.col_to_x(col)
	var a := cx - C.PLAYER_HALF_W
	var b := cx + C.PLAYER_HALF_W
	var arr: PackedFloat32Array = sweeps[row][k]
	var j := 0
	while j < arr.size():
		if arr[j + 1] > a and arr[j] < b:
			return false
		j += 2
	return true


## Breadth-first search over (row, col) per time step. Returns steps taken or -1.
static func _search(rows: Array, sweeps: Dictionary, k0: int, budget: int, start_col: int) -> int:
	var n := rows.size()
	var goal := n - 1
	var reach := {}
	reach[Vector2i(0, start_col)] = true
	for s in budget:
		var k := k0 + s
		var nxt := {}
		for cell in reach:
			var r: int = cell.x
			var c: int = cell.y
			if not _cell_safe(rows, sweeps, r, c, k):
				continue
			for d in [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nr: int = r + d.x
				var nc: int = c + d.y
				if nr < 0 or nr >= n or nc < 0 or nc >= C.COLS:
					continue
				if _cell_safe(rows, sweeps, nr, nc, k):
					if nr == goal:
						return s + 1
					nxt[Vector2i(nr, nc)] = true
		if nxt.is_empty():
			return -1
		reach = nxt
	return -1


static func _road_clear(arr: PackedFloat32Array, x: float) -> bool:
	var a := x - C.PLAYER_HALF_W
	var b := x + C.PLAYER_HALF_W
	var j := 0
	while j < arr.size():
		if arr[j + 1] > a and arr[j] < b:
			return false
		j += 2
	return true


static func _on_deck(arr: PackedFloat32Array, x: float) -> bool:
	var j := 0
	while j < arr.size():
		if x >= arr[j] and x <= arr[j + 1]:
			return true
		j += 2
	return false


## Search over (row, continuous x) for crossings with water. Mirrors the game's
## movement rules: snapping to columns on safe rows, free x on roads and decks,
## drifting with the platform while waiting on water. Returns steps or -1.
static func _search_drift(rows: Array, sweeps: Dictionary, covers: Dictionary, drifts: Dictionary,
		k0: int, budget: int, start_x: float) -> int:
	var n := rows.size()
	var goal := n - 1
	var lim := C.PLAY_HALF_W - C.TILE * 0.5
	var reach := {Vector2i(0, roundi(start_x / Q)): start_x}
	var moves := [Vector2i(0, 0), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
	for s in budget:
		var k := k0 + s
		var nxt := {}
		for key in reach:
			var r: int = key.x
			var x: float = reach[key]
			var src: Dictionary = rows[r]
			var src_water: bool = src["type"] == C.Row.WATER
			if src["type"] == C.Row.ROAD and not _road_clear(sweeps[r][k], x):
				continue
			var drift: float = drifts.get(r, 0.0)
			for d in moves:
				var nr: int = r + d.x
				if nr < 0 or nr >= n:
					continue
				var dst: Dictionary = rows[nr]
				var tx: float
				if d.x != 0:
					tx = x
					if _is_safe(dst):
						var c := C.x_to_col(x)
						var bl: Array = dst.get("blocked", [])
						if bl.has(c):
							var alt := c + (1 if x > C.col_to_x(c) else -1)
							if alt < 0 or alt >= C.COLS or bl.has(alt) or absf(C.col_to_x(alt) - x) >= C.TILE * 0.8:
								continue
							c = alt
						tx = C.col_to_x(c)
					else:
						tx = clampf(x, -lim, lim)
				elif d.y != 0:
					if _is_safe(src):
						var c2: int = C.x_to_col(x) + d.y
						if c2 < 0 or c2 >= C.COLS or (src.get("blocked", []) as Array).has(c2):
							continue
						tx = C.col_to_x(c2)
					else:
						tx = x + d.y * C.TILE + (drift if src_water else 0.0)
				else:
					tx = x + drift
				if absf(tx) > lim + 0.5 and not _is_safe(dst):
					continue
				match int(dst["type"]):
					C.Row.ROAD:
						if not _road_clear(sweeps[nr][k], tx):
							continue
					C.Row.WATER:
						if not _on_deck(covers[nr][k + 1], tx):
							continue
				if nr == goal:
					return s + 1
				nxt[Vector2i(nr, roundi(tx / Q))] = tx
		if nxt.is_empty():
			return -1
		reach = nxt
	return -1
