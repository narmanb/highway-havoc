extends Node
## Pooled sound effects (flat and positional), looping music and traffic ambience.
## Positional players pan honks and crashes toward the vehicle that made them.

const NAMES := ["hop", "dash", "bonk", "honk", "crash", "skid", "nearmiss", "pickup", "ride", "button",
	"signal_wait", "signal_walk", "signal_end", "respawn", "deliver", "ui_move", "ui_select"]

var streams := {}
var _flat: Array = []
var _pos: Array = []
var _music: AudioStreamPlayer
var _amb: AudioStreamPlayer
var _i := 0
var _j := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		var path := "res://assets/audio/%s.wav" % n
		if ResourceLoader.exists(path):
			streams[n] = load(path)
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_flat.append(p)
	for i in 6:
		var p2 := AudioStreamPlayer2D.new()
		p2.bus = "SFX"
		p2.max_distance = 1800.0
		p2.attenuation = 0.6
		add_child(p2)
		_pos.append(p2)
	_music = _looping("res://assets/audio/music_loop.wav", "Music", -3.0)
	_amb = _looping("res://assets/audio/traffic_amb.wav", "SFX", -10.0)


func _looping(path: String, bus: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = db
	add_child(p)
	if ResourceLoader.exists(path):
		var s: AudioStreamWAV = load(path)
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = int(s.get_length() * s.mix_rate)
		p.stream = s
	return p


func play(n: String, pitch_var := 0.0) -> void:
	if not streams.has(n):
		return
	var p: AudioStreamPlayer = _flat[_i]
	_i = (_i + 1) % _flat.size()
	p.stream = streams[n]
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func play_at(n: String, pos: Vector2, pitch_var := 0.0) -> void:
	if not streams.has(n):
		return
	var p: AudioStreamPlayer2D = _pos[_j]
	_j = (_j + 1) % _pos.size()
	p.stream = streams[n]
	p.global_position = pos
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	p.play()


func start_music() -> void:
	if _music.stream and not _music.playing:
		_music.play()
	if _amb.stream and not _amb.playing:
		_amb.play()
