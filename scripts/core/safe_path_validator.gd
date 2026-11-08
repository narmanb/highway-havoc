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

const DT := 0.15
const MARGIN := 14.0
const START_TIMES := [0.0, 2.6, 5.2, 7.8, 10.4]
const BUDGET_S := 24.0


static func build_lanes(spec: Dictionary) -> Dictionary:
	var lanes := {}
	var rows: Array = spec["rows"]
	for i in rows.size():
		var r: Dictionary = rows[i]
		if r["type"] == C.Row.ROAD:
			var l := LaneSim.new()
			l.setup(r["dir"], r["speed"], r["mix"], r["gap_min"], r["gap_max"], r["seed"])
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
		if r["type"] == C.Row.ROAD:
			run += 1
			if run > C.MAX_LANES_WITHOUT_REFUGE:
				result["reason"] = "too many lanes without refuge"
				return result
		else:
			run = 0
	# Structural rule: every safe row must leave at least two open cells.
	for r in rows:
		if r["type"] != C.Row.ROAD and (r.get("blocked", []) as Array).size() > C.COLS - 2:
			result["reason"] = "safe row blocked"
			return result

	var lanes := build_lanes(spec)
	var budget_steps := int(BUDGET_S / DT)
	var last_start := int(START_TIMES[START_TIMES.size() - 1] / DT)
	var total_steps := last_start + budget_steps + 1

	# Predict swept lethal intervals per lane per step.
	var sweeps := {}  # row index -> Array[PackedFloat32Array]
	var view := C.PLAY_HALF_W + 260.0
	for i in lanes:
		var l: LaneSim = lanes[i]
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
		var steps := _search(rows, sweeps, k0, budget_steps, start_col)
		if steps < 0:
			result["reason"] = "no humane path from t=%.1f" % t0
			return result
		result["worst_steps"] = maxi(result["worst_steps"], steps)
	result["ok"] = true
	return result


static func _cell_safe(rows: Array, sweeps: Dictionary, row: int, col: int, k: int) -> bool:
	var r: Dictionary = rows[row]
	if r["type"] != C.Row.ROAD:
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
