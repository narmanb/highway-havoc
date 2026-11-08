extends Node
## Settings, persistent save data (high scores, unlocks), robot palettes and the
## input map. Everything is stored locally: no account or internet needed.

signal settings_changed

const SAVE_PATH := "user://save.cfg"

const PALETTES := [
	{"name": "Courier Teal", "body": Color("2ec4b6"), "accent": Color("ff9f1c"), "eye": Color("8ff7ff"), "unlock": 0},
	{"name": "Express Red", "body": Color("e84855"), "accent": Color("ffd23f"), "eye": Color("ffe7a0"), "unlock": 5},
	{"name": "Night Shift", "body": Color("3d4b7a"), "accent": Color("b388ff"), "eye": Color("c9b6ff"), "unlock": 15},
	{"name": "Sunny Side", "body": Color("ffc93c"), "accent": Color("3a86ff"), "eye": Color("9fd0ff"), "unlock": 30},
	{"name": "Mint Mail", "body": Color("9be564"), "accent": Color("ff5d8f"), "eye": Color("e0ffd0"), "unlock": 50},
	{"name": "Chrome Bolt", "body": Color("c9ced6"), "accent": Color("ff3b30"), "eye": Color("ff9a9a"), "unlock": 80},
]

var settings := {
	"music_vol": 0.6, "sfx_vol": 0.85, "shake": 1.0, "reduced_flash": false, "quality": 2,
	"left_handed": false, "hold_edges": false, "double_tap_dash": false, "outlines": false,
	"hardcore": false, "fps30": false, "repeat_rate": 0.16, "touch_mode": "swipe",
	"repeat_delay": 0.24, "dpad_size": 125.0, "dpad_spread": 0.45,
}
var save := {"high_score": 0, "best_streak": 0, "total_deliveries": 0, "rush_best": 0, "palette": 0, "games": 0, "districts": ["downtown"]}
var last_device_pad := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	_load()
	apply_settings()


func _input(event: InputEvent) -> void:
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		last_device_pad = true
	elif event is InputEventScreenTouch or event is InputEventMouseButton:
		last_device_pad = false


func _setup_input() -> void:
	var keys := {
		"move_up": [KEY_UP, KEY_W], "move_down": [KEY_DOWN, KEY_S],
		"move_left": [KEY_LEFT, KEY_A], "move_right": [KEY_RIGHT, KEY_D],
		"dash": [KEY_SPACE, KEY_J], "brake": [KEY_SHIFT, KEY_K], "pause": [KEY_ESCAPE, KEY_P, KEY_BACK],
	}
	var pads := {
		"move_up": [JOY_BUTTON_DPAD_UP], "move_down": [JOY_BUTTON_DPAD_DOWN],
		"move_left": [JOY_BUTTON_DPAD_LEFT], "move_right": [JOY_BUTTON_DPAD_RIGHT],
		"dash": [JOY_BUTTON_A], "brake": [JOY_BUTTON_B], "pause": [JOY_BUTTON_START],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.5)
		for code in keys[action]:
			var k := InputEventKey.new()
			if code == KEY_BACK:
				k.keycode = code   # Android back button
			else:
				k.physical_keycode = code
			InputMap.action_add_event(action, k)
		for b in pads[action]:
			var j := InputEventJoypadButton.new()
			j.button_index = b
			j.device = -1
			InputMap.action_add_event(action, j)


const TOUCH_MODES := ["swipe", "relative", "dpad"]
const TOUCH_MODE_NAMES := {"swipe": "Swipe", "relative": "Tap toward robot", "dpad": "On-screen D-pad"}
const TOUCH_MODE_HELP := {
	"swipe": "Swipe to hop. Tap hops forward.",
	"relative": "Touch anywhere: the robot hops toward your finger (closest of 4 directions). Hold to keep going.",
	"dpad": "Big see-through D-pad. Press, hold to repeat, or slide your thumb between arms.",
}


func quality() -> int:
	return int(settings["quality"])


func palette() -> Dictionary:
	return PALETTES[clampi(int(save["palette"]), 0, PALETTES.size() - 1)]


func palette_unlocked(i: int) -> bool:
	return int(save["total_deliveries"]) >= int(PALETTES[i]["unlock"])


func set_setting(key: String, value) -> void:
	settings[key] = value
	apply_settings()
	_save()
	settings_changed.emit()


func apply_settings() -> void:
	Engine.max_fps = 30 if settings["fps30"] else 60
	_bus("Music", settings["music_vol"])
	_bus("SFX", settings["sfx_vol"])
	Art.outline_mode = settings["outlines"]


func _bus(bus_name: String, vol: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(vol, 0.0001)))
	AudioServer.set_bus_mute(idx, vol <= 0.001)


func unlock_district(id: String) -> void:
	var d: Array = save["districts"]
	if not d.has(id):
		d.append(id)
		_save()


func add_delivery() -> void:
	save["total_deliveries"] = int(save["total_deliveries"]) + 1


## Returns true when this run set a new best for its mode.
func record_run(summary: Dictionary) -> bool:
	save["games"] = int(save["games"]) + 1
	save["best_streak"] = maxi(int(save["best_streak"]), int(summary["best_streak"]))
	var key := "rush_best" if summary["mode"] == "rush" else "high_score"
	var new_high: bool = int(summary["score"]) > int(save[key])
	if new_high:
		save[key] = int(summary["score"])
	_save()
	return new_high


func set_palette(i: int) -> void:
	save["palette"] = i
	_save()


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK:
		return
	for k in settings:
		settings[k] = cf.get_value("settings", k, settings[k])
	for k in save:
		save[k] = cf.get_value("save", k, save[k])


func _save() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("settings", k, settings[k])
	for k in save:
		cf.set_value("save", k, save[k])
	cf.save(SAVE_PATH)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		_save()
