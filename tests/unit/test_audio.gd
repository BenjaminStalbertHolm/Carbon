extends SceneTree
## Unit checks for the audio layer (spec 11, milestone M9). Headless:
##   godot --headless --path . --script res://tests/unit/test_audio.gd
## (a) every file loads as AudioStreamWAV and its header is 44.1 kHz, 16-bit, mono;
## (b) the file-level Rule A/B check for every file (player-caused files: Rule B; the rest: Rule A),
##     plus the ghost gain (-20 dB) on key_clack, carriage_return and bell;
## (c) AudioDirector calls run without error and behave (buses, beds, hum, vent, pools, master volume,
##     loudness checker).
## Exit 0 only when every Rule A/B problem has a documented exemption (LoudnessChecker.EXEMPTIONS).

const AudioDirectorScript := preload("res://scripts/autoload/audio_director.gd")
const LoudnessAnalyser := preload("res://scripts/audio/loudness_analyser.gd")
const LoudnessChecker := preload("res://scripts/audio/loudness_checker.gd")

## Same list as tests/run_tests.gd AUDIO.
const AUDIO := [
	"key_clack_1", "key_clack_2", "key_clack_3", "key_clack_4", "carriage_return",
	"bell", "backspace_click", "platen_ratchet", "key_jam", "paper_in", "paper_out",
	"paper_shuffle", "page_turn", "stamp_thud", "marker_stroke", "fluid_brush",
	"tube_send", "tube_arrive_whoosh", "tube_thunk", "door_rattle", "footstep_1",
	"footstep_2", "clock_tick", "lamp_click", "drawer_open", "drawer_close",
	"start_bell", "fixture_off", "fixture_on", "door_unlock", "door_open",
	"room_tone", "hum", "vent_shepard",
]

## Player-caused (spec 11.1): triggered by player input, or a direct consequence within 3.5 s.
## Walking (footsteps) and clicks on doors, drawers and lamps are player input.
## door_open is the player opening the exit door (spec 15.2 step 2).
const PLAYER_CAUSED := [
	"key_clack_1", "key_clack_2", "key_clack_3", "key_clack_4", "carriage_return", "bell",
	"backspace_click", "platen_ratchet", "key_jam", "paper_in", "paper_out", "paper_shuffle",
	"page_turn", "stamp_thud", "marker_stroke", "fluid_brush", "tube_send", "door_rattle",
	"footstep_1", "footstep_2", "lamp_click", "drawer_open", "drawer_close", "door_open",
]

## Not player-caused: must obey Rule A (spec 11.1). Beds are continuous ambient sound.
const AMBIENT := [
	"tube_arrive_whoosh", "tube_thunk", "clock_tick", "start_bell", "fixture_off", "fixture_on",
	"door_unlock", "room_tone", "hum", "vent_shepard",
]

const GHOST_GAIN_DB := -20.0

var _failures := 0
var _problems := 0
var _exempt_problems := 0
var _ran := false
var _ad


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run_checks()
	return false


func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _run_checks() -> void:
	_check(OS.is_debug_build(), "debug build (the loudness checker is active)")
	var streams := _check_loads()
	_check_rules(streams)
	_check_director()
	print("AUDIO: %d files, %d Rule A/B problems (%d exempt, %d not exempt)" % [
		AUDIO.size(), _problems, _exempt_problems, _problems - _exempt_problems])
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## (a) every file loads as AudioStreamWAV, and the raw headers match the spec format.
func _check_loads() -> Dictionary:
	var streams := {}
	var header_ok := true
	for sound in AUDIO:
		var stream = ResourceLoader.load("res://assets/audio/%s.wav" % sound)
		streams[sound] = stream
		_check(stream is AudioStreamWAV, "loads as AudioStreamWAV: %s" % sound)
		if _wav_header(sound) != [44100, 16, 1]:
			header_ok = false
			print("FAIL  header is not 44.1 kHz 16-bit mono: %s" % sound)
	_check(header_ok, "all %d files are 44.1 kHz, 16-bit, mono (WAV header)" % AUDIO.size())
	return streams


## Returns [sample_rate, bits_per_sample, channels] from the RIFF fmt chunk, or [] if unreadable.
func _wav_header(sound: String) -> Array:
	var bytes := FileAccess.get_file_as_bytes("res://assets/audio/%s.wav" % sound)
	if bytes.size() < 36 or bytes.slice(0, 4).get_string_from_ascii() != "RIFF":
		return []
	if bytes.slice(12, 16).get_string_from_ascii() != "fmt ":
		return []
	return [bytes.decode_u32(24), bytes.decode_u16(34), bytes.decode_u16(22)]


## (b) file-level Rule A/B for every file, and the ghost gain.
func _check_rules(streams: Dictionary) -> void:
	for sound in AUDIO:
		var stream: AudioStreamWAV = streams.get(sound)
		var player: bool = sound in PLAYER_CAUSED
		if stream == null or not (player or sound in AMBIENT):
			_check(false, "readable and classified as player-caused or ambient: %s" % sound)
			continue
		var info := LoudnessAnalyser.analyse(stream)
		var rule := "B" if player else "A"
		var summary := "%-22s peak %7.2f dBFS  attack %7.1f ms" % [sound, info["peak_db"], info["attack_ms"]]
		var problem := LoudnessChecker.judge(info["peak_db"], info["attack_ms"], player)
		if problem == "":
			_check(true, "Rule %s  %s" % [rule, summary])
		elif LoudnessChecker.is_exempt(sound, problem):
			_problems += 1
			_exempt_problems += 1
			print("EXEMPT  Rule %s  %s -- %s. Exemption: %s" % [rule, summary, problem, LoudnessChecker.EXEMPTIONS[sound]])
		else:
			_problems += 1
			_check(false, "Rule %s  %s -- %s" % [rule, summary, problem])
	for sound in ["key_clack", "carriage_return", "bell"]:
		var file_name: String = "key_clack_1" if sound == "key_clack" else sound
		var info := LoudnessAnalyser.analyse(load("res://assets/audio/%s.wav" % file_name))
		var problem := LoudnessChecker.judge(info["peak_db"] + GHOST_GAIN_DB, info["attack_ms"], false)
		if problem == "":
			_check(true, "ghost %-15s at -20 dB: peak %.2f dBFS (Rule A)" % [sound, info["peak_db"] + GHOST_GAIN_DB])
		else:
			_problems += 1
			_check(false, "ghost %s at -20 dB -- %s" % [sound, problem])


## (c) AudioDirector behaviour, run headless with the dummy audio driver.
func _check_director() -> void:
	_ad = AudioDirectorScript.new()
	get_root().add_child(_ad)
	_check(AudioServer.get_bus_index("SFX") >= 0 and AudioServer.get_bus_index("Ambient") >= 0,
		"buses SFX and Ambient exist (created at runtime)")

	_ad.play("key_clack", Vector3.ZERO, false, -30.0)
	_check(_ad.active_one_shots() >= 1, "play(key_clack) starts a one-shot without error")
	_ad.play("key_clack_3", Vector3(4.0, 1.0, 3.0), true, -24.0, false)
	_ad.play_ghost("bell", Vector3(4.0, 1.0, 3.0))
	_ad.play("carriage_return", Vector3.ZERO, false, 0.0, true)
	_check(_ad.active_one_shots() >= 1, "positional, ghost and player-caused one-shots run without error")
	for i in 40:
		_ad.play("key_clack", Vector3.ZERO, false, -30.0)
	var active: int = _ad.active_one_shots()
	_check(active >= 16 and active <= 32, "pools reuse players: 40 extra clacks leave %d of 32 active" % active)

	_ad.start_bed("room_tone")
	_ad.start_bed("hum")
	_check(_ad.is_bed_playing("room_tone") and _ad.is_bed_playing("hum"), "start_bed starts room_tone and hum")
	var room_stream = _ad.bed_player("room_tone").stream
	_check(room_stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and room_stream.loop_end == 441000,
		"room_tone loops forward over all 441000 frames")
	_ad.set_fixtures_lit(3)
	var hum_db: float = _ad.bed_player("hum").volume_db
	_check(absf(hum_db - linear_to_db(0.5)) < 0.01, "hum follows 3 of 6 fixtures lit (%.2f dB)" % hum_db)
	_ad.set_fixtures_lit(0)
	_check(_ad.bed_player("hum").volume_db <= -80.0, "hum silent with 0 fixtures lit")
	_ad.set_fixtures_lit(6)
	_check(absf(_ad.bed_player("hum").volume_db) < 0.01, "hum at 0 dB with all 6 fixtures lit")
	for pair in [[1, 1.0], [2, 1.0], [3, 0.99], [4, 0.98], [5, 0.965]]:
		_ad.set_hum_pitch(pair[0])
		_check(absf(_ad.bed_player("hum").pitch_scale - pair[1]) < 0.0001,
			"hum pitch on day %d is %.3f" % [pair[0], pair[1]])
	_ad.set_vent_active(true)
	_check(_ad.is_bed_playing("vent_shepard"), "set_vent_active(true) starts vent_shepard")
	_ad.set_vent_active(false)
	_check(not _ad.is_bed_playing("vent_shepard"), "set_vent_active(false) stops vent_shepard")
	_ad.stop_bed("room_tone")
	_check(not _ad.is_bed_playing("room_tone"), "stop_bed stops room_tone")

	_ad.set_master_volume_percent(0)
	var master := AudioServer.get_bus_index("Master")
	_check(AudioServer.get_bus_volume_db(master) <= -80.0,
		"set_master_volume_percent(0) makes Master silent (%.1f dB)" % AudioServer.get_bus_volume_db(master))
	_ad.set_master_volume_percent(80)
	_check(absf(AudioServer.get_bus_volume_db(master) - linear_to_db(0.8)) < 0.01,
		"set_master_volume_percent(80) gives linear_to_db(0.8)")
	_ad.set_master_volume_percent(100)

	_ad.set_checker_enabled(true)
	var v0: int = _ad.get_checker_violations()
	var p0: int = _ad.get_checker_playbacks()
	_ad.play("key_clack_2", Vector3.ZERO, false, 0.0, true)
	_check(_ad.get_checker_violations() == v0 and _ad.get_checker_playbacks() == p0 + 1,
		"checker logs a player-caused key_clack with no violation (Rule B)")
	_ad.play("key_clack_1", Vector3.ZERO, false, 0.0, false)
	_check(_ad.get_checker_violations() == v0 + 1,
		"checker flags a non-player key_clack at 0 dB as a Rule A violation")
	var e0: int = _ad.get_checker_exempt_playbacks()
	_ad.play("tube_thunk", Vector3.ZERO, false, 0.0, false)
	_check(_ad.get_checker_violations() == v0 + 1 and _ad.get_checker_exempt_playbacks() == e0 + 1,
		"checker exempts tube_thunk (documented Rule A exception)")
	_ad.play_ghost("key_clack", Vector3.ZERO, false)
	_check(_ad.get_checker_violations() == v0 + 1, "ghost key_clack at -20 dB passes Rule A")
	_ad.set_checker_enabled(false)
	var p1: int = _ad.get_checker_playbacks()
	_ad.play("key_clack_1", Vector3.ZERO, false, 0.0, false)
	_check(_ad.get_checker_playbacks() == p1, "disabled checker records nothing")
	_ad.set_checker_enabled(true)
	var holder := Node3D.new()
	get_root().add_child(holder)
	_ad.set_spatial_parent(holder)
	_check(_ad.bed_player("vent_shepard").get_parent() == holder, "set_spatial_parent moves the positional players")
	_ad.play("bell", Vector3(4.0, 1.0, 3.0), true, 0.0, true)
	_check(_ad.active_one_shots() >= 1, "positional one-shot plays after set_spatial_parent")
	_ad.stop_bed("hum")
	_ad.stop_bed("vent_shepard")
	for p in holder.get_children():
		p.stop()
	holder.free()
	get_root().remove_child(_ad)
	_ad.free()
