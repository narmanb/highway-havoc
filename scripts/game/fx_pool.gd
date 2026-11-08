class_name FXPool
extends Node2D
## Pooled lightweight particles and floating score text, drawn in one canvas item.
## Counts scale with the Effects quality preset (Low / Medium / High).

const CAPS := [60, 160, 320]

var parts: Array = []     # each: [pos, vel, life, max_life, color, size, gravity, kind]
var texts: Array = []     # each: [pos, text, color, life, size]
var decals: Decals


class Decals:
	extends Node2D
	## Skid marks on the asphalt (below vehicles). Bounded and fading.
	var marks: Array = []   # [rect, life]

	func add(r: Rect2) -> void:
		marks.append([r, 3.0])
		if marks.size() > 40:
			marks.pop_front()

	func _process(dt: float) -> void:
		if marks.is_empty():
			return
		for m in marks:
			m[1] -= dt
		while not marks.is_empty() and marks[0][1] <= 0.0:
			marks.pop_front()
		queue_redraw()

	func _draw() -> void:
		for m in marks:
			draw_rect(m[0], Color(0.05, 0.05, 0.06, 0.45 * clampf(m[1] / 1.5, 0.0, 1.0)))

	func clear() -> void:
		marks.clear()
		queue_redraw()


func _cap() -> int:
	return CAPS[GameState.quality()]


func _scaled(n: int) -> int:
	return maxi(1, int(n * [0.35, 0.7, 1.0][GameState.quality()]))


func _add(pos: Vector2, vel: Vector2, life: float, col: Color, size: float, grav: float, kind := 0) -> void:
	if parts.size() >= _cap():
		parts.pop_front()
	parts.append([pos, vel, life, life, col, size, grav, kind])


func dust(pos: Vector2, n := 6) -> void:
	for i in _scaled(n):
		var a := randf_range(PI * 0.9, PI * 2.1)
		_add(pos + Vector2(randf_range(-10, 10), 0), Vector2(cos(a), sin(a) * 0.4) * randf_range(30, 90),
			0.35, Color(0.85, 0.82, 0.75, 0.7), randf_range(4, 7), -30.0, 1)


func sparks(pos: Vector2, dir: float) -> void:
	for i in _scaled(18):
		var v := Vector2(dir * randf_range(80, 420), randf_range(-380, -60))
		_add(pos, v, randf_range(0.3, 0.6), Color("ffd84a").lerp(Color("ff6a2a"), randf()), randf_range(2, 4), 900.0)
	for i in _scaled(6):
		var v2 := Vector2(dir * randf_range(60, 260), randf_range(-420, -160))
		_add(pos, v2, 0.9, [Color("c8874a"), Color("6fd6ff"), Color("3a3f4b")][i % 3], randf_range(4, 7), 1100.0, 2)


func confetti(pos: Vector2) -> void:
	var cols := [Color("ffd23f"), Color("ff5d73"), Color("3fd6c4"), Color("8a5cff"), Color("ffffff")]
	for i in _scaled(48):
		var a := randf_range(-PI * 0.95, -PI * 0.05)
		_add(pos, Vector2(cos(a), sin(a)) * randf_range(180, 520), randf_range(0.8, 1.4), cols[i % cols.size()],
			randf_range(4, 7), 700.0, 2)


func sparkle(pos: Vector2) -> void:
	for i in _scaled(12):
		var a := TAU * float(i) / 12.0
		_add(pos, Vector2(cos(a), sin(a)) * 160.0, 0.4, Color("fff2a0"), 3.0, 0.0)


func popup(pos: Vector2, text: String, col := Color.WHITE, size := 30) -> void:
	texts.append([pos, text, col, 1.1, size])
	if texts.size() > 12:
		texts.pop_front()


func skid(pos: Vector2, length: float, dir: float) -> void:
	if decals == null:
		return
	var x0 := pos.x - (length if dir > 0 else 0.0)
	decals.add(Rect2(x0, pos.y + 12, length, 4))
	decals.add(Rect2(x0, pos.y - 14, length, 4))


func clear() -> void:
	parts.clear()
	texts.clear()
	if decals:
		decals.clear()


func _process(dt: float) -> void:
	var i := 0
	while i < parts.size():
		var p: Array = parts[i]
		p[2] -= dt
		if p[2] <= 0.0:
			parts.remove_at(i)
			continue
		p[1].y += p[6] * dt
		p[0] += p[1] * dt
		if p[7] == 1:
			p[1] *= 0.9
		i += 1
	var j := 0
	while j < texts.size():
		var t: Array = texts[j]
		t[3] -= dt
		t[0].y -= 60.0 * dt
		if t[3] <= 0.0:
			texts.remove_at(j)
			continue
		j += 1
	queue_redraw()


func _draw() -> void:
	for p in parts:
		var f: float = p[2] / p[3]
		var col: Color = p[4]
		col.a *= clampf(f * 1.5, 0.0, 1.0)
		match p[7]:
			1: draw_circle(p[0], p[5] * (1.6 - f * 0.6), col)
			2: draw_rect(Rect2(p[0], Vector2(p[5], p[5] * 0.6)), col)
			_: draw_rect(Rect2(p[0], Vector2(p[5], p[5])), col)
	var font := ThemeDB.fallback_font
	for t in texts:
		var a := clampf(float(t[3]) / 0.4, 0.0, 1.0)
		var col: Color = t[2]
		col.a = a
		var size: int = t[4]
		var w := font.get_string_size(t[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var pos: Vector2 = t[0] - Vector2(w * 0.5, 0)
		draw_string_outline(font, pos, t[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size, 8, Color(0.05, 0.05, 0.1, a))
		draw_string(font, pos, t[1], HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)
