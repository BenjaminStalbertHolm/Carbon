extends Node
## AudioDirector (autoload): one-shot SFX pools, ambient beds, hum pitch per day, master volume,
## seamless loops (the marker drag) and the debug loudness checker (spec 11). All players are
## children of this node. Positional sounds are heard by the listener of the viewport that contains
## them: call set_spatial_parent() with that viewport's 3D node if the 3D world is not in the root viewport.

const SfxPool := preload("res://scripts/audio/sfx_pool.gd")
const LoudnessChecker := preload("res://scripts/audio/loudness_checker.gd")

const MASTER_BUS := &"Master"
const SFX_BUS := &"SFX"
const AMBIENT_BUS := &"Ambient"
const GHOST_GAIN_DB := -20.0
const SILENT_DB := -80.0
const FIXTURE_COUNT := 6
const VENT_POSITION := Vector3(5.25, 3.19, 3.5)
## Every bed fades in from silence over this many seconds when it starts (the 2.0 s of the spec 13.1
## fade-in). The fade is the bed's attack for Rule A (spec 11.1), see LoudnessChecker.BED_RAMP_MS.
const BED_RAMP_S := 2.0

var _pool: SfxPool
var _checker: LoudnessChecker
var _rng := RandomNumberGenerator.new()
var _streams: Dictionary = {}
var _loop_streams: Dictionary = {}
var _beds: Dictionary = {}
var _bed_ramp: Dictionary = {}  # bed name -> start fade fraction, 0 (silent) to 1 (full)
var _bed_tweens: Dictionary = {}  # bed name -> the tween running its start fade
var _hum_pitch := 1.0
var _fixtures_lit := FIXTURE_COUNT


func _ready() -> void:
	_rng.randomize()
	_ensure_buses()
	_pool = SfxPool.new()
	_pool.setup(self)
	_checker = LoudnessChecker.new()
	var room := AudioStreamPlayer.new()
	room.bus = AMBIENT_BUS
	add_child(room)
	_beds["room_tone"] = room
	var hum := AudioStreamPlayer.new()
	hum.bus = AMBIENT_BUS
	add_child(hum)
	_beds["hum"] = hum
	var vent := AudioStreamPlayer3D.new()
	vent.bus = AMBIENT_BUS
	SfxPool.configure_spatial(vent)
	add_child(vent)
	vent.global_position = VENT_POSITION
	_beds["vent_shepard"] = vent
	for bed_name in _beds.keys():
		_bed_ramp[bed_name] = 1.0
		_apply_bed_volume(bed_name)


## Plays a one-shot from assets/audio/<sound>.wav. gain_db adds to the file level.
## key_clack, key_clack_1..4: random variant 1-4, pitch x0.92-1.08, volume -2 to 0 dB (spec 7.3).
## player_caused marks sounds from player input for the loudness checker (Rule B instead of Rule A).
func play(sound: String, pos: Vector3 = Vector3.ZERO, positional: bool = true, gain_db: float = 0.0, player_caused: bool = false) -> void:
	var file_name := sound
	var pitch := 1.0
	var volume := gain_db
	if sound.begins_with("key_clack"):
		file_name = "key_clack_%d" % _rng.randi_range(1, 4)
		pitch = _rng.randf_range(0.92, 1.08)
		volume += _rng.randf_range(-2.0, 0.0)
	var stream := _stream(file_name)
	if stream == null:
		return
	var player = _pool.take(positional)
	player.stream = stream
	player.pitch_scale = pitch
	player.volume_db = volume
	if positional:
		player.global_position = pos
	if _checker.is_active():
		_checker.record(file_name, "3D" if positional else "flat", stream, volume, player_caused)
	player.play()


## Ghost-typed sounds (spec 11.1): key_clack, carriage_return and bell get -20 dB extra gain.
## Other sounds play exactly as play() would, as not player-caused.
func play_ghost(sound: String, pos: Vector3 = Vector3.ZERO, positional: bool = true, gain_db: float = 0.0) -> void:
	var extra := GHOST_GAIN_DB if _is_ghost_sound(sound) else 0.0
	play(sound, pos, positional, gain_db + extra, false)


## Starts a seamless loop of assets/audio/<sound>.wav (spec 11.3, marker_stroke). The loop is held
## until stop_loop(handle), or until max_seconds have passed when max_seconds is above 0. A loop is
## player-caused (the marker is dragged by the player, spec 8.2). Returns the handle, 0 if the sound is missing.
func start_loop(sound: String, pos: Vector3 = Vector3.ZERO, positional: bool = false, gain_db: float = 0.0, max_seconds: float = 0.0) -> int:
	var stream := _loop_stream(sound)
	if stream == null:
		return 0
	if _checker.is_active():
		_checker.record(sound, "loop 3D" if positional else "loop", stream, gain_db, true)
	var handle := _pool.start_loop(stream, positional, gain_db, pos)
	if max_seconds > 0.0 and is_inside_tree():
		get_tree().create_timer(max_seconds).timeout.connect(stop_loop.bind(handle))
	return handle


func stop_loop(handle: int) -> void:
	_pool.stop_loop(handle)


func is_loop_playing(handle: int) -> bool:
	return _pool.is_loop_playing(handle)


## Starts a bed (spec 11.2). The bed fades in from silence over BED_RAMP_S, so its attack is at least
## 150 ms (Rule A, spec 11.1); it then settles at bed_target_db().
func start_bed(bed_name: String) -> void:
	var bed = _beds.get(bed_name)
	if bed == null:
		push_error("AudioDirector: unknown bed %s" % bed_name)
		return
	if bed.playing:
		return
	var stream := _bed_stream(bed_name)
	if stream == null:
		return
	bed.stream = stream
	if _checker.is_active():
		_checker.record(bed_name, "bed 3D" if bed is AudioStreamPlayer3D else "bed", stream,
			bed_target_db(bed_name), false, LoudnessChecker.BED_RAMP_MS)
	_start_fade_in(bed_name)
	bed.play()


func stop_bed(bed_name: String) -> void:
	var bed = _beds.get(bed_name)
	if bed != null:
		_stop_fade_in(bed_name)
		bed.stop()


func is_bed_playing(bed_name: String) -> bool:
	var bed = _beds.get(bed_name)
	return bed != null and bed.playing


## The level a bed settles at, in dB: room_tone and the vent at the file level, the hum at its lit
## fraction (spec 11.2). A started bed fades up to this level.
func bed_target_db(bed_name: String) -> float:
	return _db_for_gain(_bed_gain(bed_name))


## Hum pitch for a day (spec 11.2): days 1-2 1.000, day 3 0.990, day 4 0.980, day 5 0.965.
func set_hum_pitch(day: int) -> void:
	_hum_pitch = hum_pitch_for_day(day)
	var hum = _beds["hum"]
	hum.pitch_scale = _hum_pitch


static func hum_pitch_for_day(day: int) -> float:
	if day <= 2:
		return 1.0
	if day == 3:
		return 0.990
	if day == 4:
		return 0.980
	return 0.965


## Hum amplitude = base x (lit fixtures / 6). 0 lit means silent. Takes effect immediately.
func set_fixtures_lit(count: int) -> void:
	_fixtures_lit = clampi(count, 0, FIXTURE_COUNT)
	_apply_bed_volume("hum")


## The vent above Desk 4 (spec 11.2): Days 4-5 only. The caller decides when.
func set_vent_active(on: bool) -> void:
	if on:
		start_bed("vent_shepard")
	else:
		stop_bed("vent_shepard")


## Master bus volume, 0-100 as linear_to_db(v / 100). 0 is silent (-80 dB, the floor).
func set_master_volume_percent(v: int) -> void:
	var linear := clampf(float(v), 0.0, 100.0) / 100.0
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index(MASTER_BUS), maxf(linear_to_db(linear), SILENT_DB))


## Moves the positional players under the 3D node that holds the listener. Call before playing.
func set_spatial_parent(parent: Node) -> void:
	_pool.reparent_all(parent)
	_beds["vent_shepard"].reparent(parent, true)


## Debug loudness checker (spec 11.1). Only active in debug builds.
func set_checker_enabled(on: bool) -> void:
	_checker.enabled = on


func get_checker_playbacks() -> int:
	return _checker.playbacks


func get_checker_violations() -> int:
	return _checker.violations


func get_checker_exempt_playbacks() -> int:
	return _checker.exempt_playbacks


func active_one_shots() -> int:
	return _pool.active_count()


func bed_player(bed_name: String) -> Node:
	return _beds.get(bed_name)


func _ensure_buses() -> void:
	for bus_name in [SFX_BUS, AMBIENT_BUS]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.get_bus_count() - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, MASTER_BUS)


## Steady amplitude of a bed: 1.0 for room_tone and the vent, lit fixtures / 6 for the hum.
func _bed_gain(bed_name: String) -> float:
	if bed_name == "hum":
		return float(_fixtures_lit) / FIXTURE_COUNT
	return 1.0


## Sets a bed's volume from its steady gain times its start fade. Zero is silent.
func _apply_bed_volume(bed_name: String) -> void:
	var bed = _beds[bed_name]
	bed.volume_db = _db_for_gain(_bed_gain(bed_name) * float(_bed_ramp[bed_name]))


static func _db_for_gain(gain: float) -> float:
	return SILENT_DB if gain <= 0.0 else maxf(linear_to_db(gain), SILENT_DB)


func _start_fade_in(bed_name: String) -> void:
	_stop_fade_in(bed_name)
	_bed_ramp[bed_name] = 0.0
	_apply_bed_volume(bed_name)
	var tween := create_tween()
	tween.tween_method(_set_bed_fade.bind(bed_name), 0.0, 1.0, BED_RAMP_S)
	_bed_tweens[bed_name] = tween


func _stop_fade_in(bed_name: String) -> void:
	var tween = _bed_tweens.get(bed_name)
	if tween != null and tween.is_valid():
		tween.kill()
	_bed_tweens.erase(bed_name)


func _set_bed_fade(fraction: float, bed_name: String) -> void:
	_bed_ramp[bed_name] = fraction
	_apply_bed_volume(bed_name)


func _stream(sound: String) -> AudioStreamWAV:
	if _streams.has(sound):
		return _streams[sound]
	var path := "res://assets/audio/%s.wav" % sound
	if not ResourceLoader.exists(path):
		push_error("AudioDirector: missing sound %s" % path)
		return null
	var stream := ResourceLoader.load(path) as AudioStreamWAV
	_streams[sound] = stream
	return stream


## Beds loop forever: forward loop over the whole file (spec 11.2).
func _bed_stream(bed_name: String) -> AudioStreamWAV:
	var stream := _stream(bed_name)
	if stream != null:
		_set_whole_file_loop(stream)
	return stream


## A seamless loop for the marker drag. It is a copy of the one-shot stream, so the one-shot
## marker_stroke stays unlooped.
func _loop_stream(sound: String) -> AudioStreamWAV:
	if _loop_streams.has(sound):
		return _loop_streams[sound]
	var source := _stream(sound)
	if source == null:
		return null
	var stream := source.duplicate() as AudioStreamWAV
	_set_whole_file_loop(stream)
	_loop_streams[sound] = stream
	return stream


static func _set_whole_file_loop(stream: AudioStreamWAV) -> void:
	if stream.loop_mode == AudioStreamWAV.LOOP_FORWARD:
		return
	var sample_bytes := 1 if stream.format == AudioStreamWAV.FORMAT_8_BITS else 2
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = stream.data.size() / (sample_bytes * (2 if stream.stereo else 1))


static func _is_ghost_sound(sound: String) -> bool:
	return sound.begins_with("key_clack") or sound == "carriage_return" or sound == "bell" or sound == "key_jam"
