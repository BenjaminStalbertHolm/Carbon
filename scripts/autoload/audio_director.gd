extends Node
## AudioDirector (autoload): one-shot SFX pools, ambient beds, hum pitch per day, master volume and
## the debug loudness checker (spec 11). All players are children of this node. Positional sounds are
## heard by the listener of the viewport that contains them: call set_spatial_parent() with that
## viewport's 3D node if the 3D world is not in the root viewport.

const SfxPool := preload("res://scripts/audio/sfx_pool.gd")
const LoudnessChecker := preload("res://scripts/audio/loudness_checker.gd")

const MASTER_BUS := &"Master"
const SFX_BUS := &"SFX"
const AMBIENT_BUS := &"Ambient"
const GHOST_GAIN_DB := -20.0
const SILENT_DB := -80.0
const FIXTURE_COUNT := 6
const VENT_POSITION := Vector3(5.25, 3.19, 3.5)

var _pool: SfxPool
var _checker: LoudnessChecker
var _rng := RandomNumberGenerator.new()
var _streams: Dictionary = {}
var _beds: Dictionary = {}
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
	_apply_hum_volume()


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
		_checker.record(bed_name, "bed 3D" if bed is AudioStreamPlayer3D else "bed", stream, bed.volume_db, false)
	bed.play()


func stop_bed(bed_name: String) -> void:
	var bed = _beds.get(bed_name)
	if bed != null:
		bed.stop()


func is_bed_playing(bed_name: String) -> bool:
	var bed = _beds.get(bed_name)
	return bed != null and bed.playing


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
	_apply_hum_volume()


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


func _apply_hum_volume() -> void:
	var hum = _beds["hum"]
	hum.volume_db = SILENT_DB if _fixtures_lit == 0 else linear_to_db(float(_fixtures_lit) / FIXTURE_COUNT)


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
	if stream != null and stream.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		var sample_bytes := 1 if stream.format == AudioStreamWAV.FORMAT_8_BITS else 2
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = stream.data.size() / (sample_bytes * (2 if stream.stereo else 1))
	return stream


static func _is_ghost_sound(sound: String) -> bool:
	return sound.begins_with("key_clack") or sound == "carriage_return" or sound == "bell"
