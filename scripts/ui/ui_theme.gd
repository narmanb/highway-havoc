class_name UiTheme
## Chunky, high-contrast UI theme built in code. Large touch targets everywhere,
## and a bright yellow focus ring so controller navigation is always obvious.

const BG := Color("1d2130")
const PANEL := Color("272c3f")
const YELLOW := Color("ffd23f")
const INK := Color("10131a")


static func _box(bg: Color, border: Color, bw: int, radius := 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.content_margin_left = 24
	s.content_margin_right = 24
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 4
	s.shadow_offset = Vector2(0, 4)
	return s


static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 32
	t.set_stylebox("normal", "Button", _box(Color("323a55"), INK, 3))
	t.set_stylebox("hover", "Button", _box(Color("3f496b"), YELLOW, 4))
	t.set_stylebox("focus", "Button", _box(Color(0, 0, 0, 0), YELLOW, 5))
	t.set_stylebox("pressed", "Button", _box(YELLOW, INK, 3))
	t.set_stylebox("disabled", "Button", _box(Color("2a2f40"), Color("3a3f50"), 3))
	t.set_color("font_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", INK)
	t.set_color("font_disabled_color", "Button", Color("7a7f90"))
	t.set_font_size("font_size", "Button", 34)
	t.set_constant("outline_size", "Label", 8)
	t.set_color("font_outline_color", "Label", Color(0.04, 0.05, 0.09))
	t.set_color("font_color", "Label", Color.WHITE)
	var panel := _box(Color(PANEL, 0.96), INK, 4, 24)
	panel.content_margin_left = 28
	panel.content_margin_right = 28
	panel.content_margin_top = 24
	panel.content_margin_bottom = 24
	t.set_stylebox("panel", "PanelContainer", panel)
	# Sliders
	var track := StyleBoxFlat.new()
	track.bg_color = Color("151824")
	track.set_corner_radius_all(8)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	t.set_stylebox("slider", "HSlider", track)
	var fill := track.duplicate()
	fill.bg_color = YELLOW
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	var focus := _box(Color(0, 0, 0, 0), YELLOW, 4, 10)
	t.set_stylebox("focus", "HSlider", focus)
	t.set_icon("grabber", "HSlider", _dot(18, Color.WHITE))
	t.set_icon("grabber_highlight", "HSlider", _dot(20, YELLOW))
	return t


static func _dot(r: int, col: Color) -> ImageTexture:
	var img := Image.create(r * 2, r * 2, false, Image.FORMAT_RGBA8)
	for y in r * 2:
		for x in r * 2:
			var d := Vector2(x - r + 0.5, y - r + 0.5).length()
			if d <= r - 0.5:
				img.set_pixel(x, y, col if d < r - 3.0 else INK)
	return ImageTexture.create_from_image(img)


static func label(text: String, size := 32, col := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


static func button(text: String, cb: Callable, min_h := 92) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, min_h)
	b.pressed.connect(func():
		Audio.play("ui_select")
		cb.call())
	b.focus_entered.connect(func(): Audio.play("ui_move"))
	return b


## Safe-area margins (notches, rounded corners) in viewport units.
static func safe_margins(vp: Viewport) -> Dictionary:
	var out := {"left": 0.0, "top": 0.0, "right": 0.0, "bottom": 0.0}
	var win := DisplayServer.window_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0 or safe.size.x <= 0 or OS.get_name() not in ["Android", "iOS"]:
		return out
	var vis := vp.get_visible_rect().size
	var sx := vis.x / float(win.x)
	var sy := vis.y / float(win.y)
	out["left"] = maxf(0.0, safe.position.x) * sx
	out["top"] = maxf(0.0, safe.position.y) * sy
	out["right"] = maxf(0.0, win.x - safe.end.x) * sx
	out["bottom"] = maxf(0.0, win.y - safe.end.y) * sy
	return out
