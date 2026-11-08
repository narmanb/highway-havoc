class_name RoadGenerator
extends RefCounted
## Builds crossing segments from hand-authored lane templates, randomises the
## parameters with a deterministic seed, and keeps re-rolling (then easing off)
## until SafePathValidator confirms a humane crossing exists.
##
## Template row codes:  "L:<mix>" road lane, "L:<mix>:g" lane controlled by the
## crosswalk signal, "M" safe median, "S" goal sidewalk. Row 0 (the start
## sidewalk) is implicit: it is the previous segment's goal.

const MIXES := {
	"city":  [["car", 6.0], ["moto", 2.0]],
	"bus":   [["bus", 4.0], ["car", 3.0]],
	"truck": [["truck", 5.0], ["car", 3.0]],
	"fast":  [["moto", 5.0], ["car", 3.0]],
	"mixed": [["car", 4.0], ["truck", 2.0], ["bus", 1.0], ["moto", 1.0]],
}
const MIX_SPEED := {"city": 1.0, "bus": 0.8, "truck": 0.9, "fast": 1.3, "mixed": 1.0}

const TEMPLATES := {
	"Quiet Block":    ["L:city:g", "L:truck:g", "M", "L:city", "S"],
	"Main Street":    ["L:city:g", "L:mixed:g", "L:bus:g", "M", "L:truck", "L:fast", "S"],
	"Bus Corridor":   ["L:bus", "L:city", "M", "L:truck:g", "L:mixed:g", "L:bus:g", "S"],
	"Delivery Alley": ["L:city:g", "L:truck:g", "L:truck:g", "M", "L:fast", "L:city", "L:mixed", "S"],
	"Twin Avenues":   ["L:city:g", "L:fast:g", "M", "L:truck", "L:mixed", "M", "L:bus", "L:city", "S"],
}
const INTRO_TEMPLATE := "Quiet Block"
const ROTATION := ["Main Street", "Bus Corridor", "Delivery Alley", "Twin Avenues"]

static var stats := {"generated": 0, "rerolls": 0, "eased": 0}


static func level_speed_mult(level: int) -> float:
	return minf(1.0 + 0.055 * float(level - 1), 1.6)


static func make_start_row(rng: RandomNumberGenerator) -> Dictionary:
	return {"type": C.Row.SIDEWALK, "blocked": _random_props(rng, [C.CENTER_COL], 2, OUTER_COLS), "button": -1,
		"locker": -1, "deco_seed": rng.randi()}


const OUTER_COLS := [0, 1, 7, 8]


## Sidewalk props stay in the outer columns so the walkway is never split down the middle.
static func _random_props(rng: RandomNumberGenerator, keep_free: Array, max_props: int, allowed: Array = []) -> Array:
	var out: Array = []
	var count := rng.randi_range(0, max_props)
	var guard := 0
	while out.size() < count and guard < 20:
		guard += 1
		var c: int = allowed[rng.randi() % allowed.size()] if not allowed.is_empty() else rng.randi_range(0, C.COLS - 1)
		if keep_free.has(c) or out.has(c):
			continue
		out.append(c)
	return out


## start_row: the previous segment's goal row dictionary (it is reused, not copied).
static func generate(run_seed: int, index: int, level: int, template_name: String, start_row: Dictionary) -> Dictionary:
	var spec := {}
	for attempt in 12:
		var ease := maxi(0, attempt - 5)  # after six honest re-rolls, start easing traffic
		spec = _build(run_seed, index, level, template_name, start_row, attempt, ease)
		var res := SafePathValidator.validate(spec)
		if res["ok"]:
			spec["validation"] = res
			spec["attempts"] = attempt + 1
			stats["generated"] += 1
			stats["rerolls"] += attempt
			if ease > 0:
				stats["eased"] += 1
			return spec
	# Last resort (never observed in tests): a gentle version of the template.
	spec = _build(run_seed, index, 1, template_name, start_row, 99, 8)
	spec["validation"] = SafePathValidator.validate(spec)
	spec["attempts"] = 13
	return spec


static func _build(run_seed: int, index: int, level: int, template_name: String, start_row: Dictionary, attempt: int, ease: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([run_seed, index, attempt, template_name])
	var tmpl: Array = TEMPLATES[template_name]
	var smult := level_speed_mult(level) * pow(0.88, ease)
	var gap_min := maxf(C.MIN_GAP_SECONDS, 1.55 - 0.05 * float(level - 1)) + 0.15 * ease
	var gap_max := maxf(gap_min + 0.9, 3.4 - 0.12 * float(level - 1)) + 0.3 * ease

	var rows: Array = [start_row]
	var light_rows: Array = []
	var dir := 1 if rng.randf() < 0.5 else -1
	var has_truck := false
	for code in tmpl:
		var parts: PackedStringArray = (code as String).split(":")
		match parts[0]:
			"L":
				var mix_name := parts[1]
				if mix_name == "truck" or mix_name == "mixed":
					has_truck = true
				var base := rng.randf_range(115.0, 190.0) * float(MIX_SPEED[mix_name])
				rows.append({
					"type": C.Row.ROAD, "dir": dir, "speed": base * smult,
					"mix": MIXES[mix_name], "mix_name": mix_name,
					"gap_min": gap_min, "gap_max": gap_max,
					"seed": rng.randi(), "deco_seed": rng.randi(),
				})
				if parts.size() > 2 and parts[2] == "g":
					light_rows.append(rows.size() - 1)
				if rng.randf() < 0.72:
					dir = -dir
			"M":
				rows.append({"type": C.Row.MEDIAN, "blocked": _random_props(rng, [], 2), "deco_seed": rng.randi(), "button": -1})
			"S":
				var locker := rng.randi_range(1, C.COLS - 2)
				rows.append({"type": C.Row.SIDEWALK, "blocked": _random_props(rng, [C.CENTER_COL, locker], 2, OUTER_COLS),
					"button": -1, "locker": locker, "deco_seed": rng.randi()})
	if not has_truck:
		# Milestone promise: every crossing offers at least one rideable roof.
		for i in range(1, rows.size()):
			if rows[i]["type"] == C.Row.ROAD and rows[i]["mix_name"] == "city":
				rows[i]["mix"] = MIXES["mixed"]
				rows[i]["mix_name"] = "mixed"
				break

	var light := {}
	if not light_rows.is_empty():
		var col := rng.randi_range(2, C.COLS - 3)
		var below: int = light_rows[0] - 1
		var brow: Dictionary = rows[below]
		# The button pad sits at the foot of the crosswalk; keep it clear of props.
		var blocked: Array = brow.get("blocked", [])
		if blocked.has(col) or brow.get("locker", -1) == col:
			col = C.CENTER_COL if not blocked.has(C.CENTER_COL) else col
			blocked.erase(col)
		brow["button"] = col
		light = {"lanes": light_rows, "column": col, "button_row": below}

	# Optional pickups (bolts) on road cells.
	var pickups: Array = []
	for i in rng.randi_range(1, 2):
		var lane_rows: Array = []
		for j in rows.size():
			if rows[j]["type"] == C.Row.ROAD:
				lane_rows.append(j)
		pickups.append(Vector2i(lane_rows[rng.randi() % lane_rows.size()], rng.randi_range(0, C.COLS - 1)))

	var road_count := 0
	for r in rows:
		if r["type"] == C.Row.ROAD:
			road_count += 1
	return {
		"template": template_name, "level": level, "seed": run_seed, "index": index,
		"rows": rows, "light": light, "pickups": pickups,
		"par_time": 5.0 + 1.6 * float(road_count), "start_col": C.CENTER_COL,
	}
