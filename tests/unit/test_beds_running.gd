extends SceneTree
## Headless checks for the ambient beds in the running game (spec 11.2, 8.12, 9.3, 16.2). The room tone and
## the hum start when a day runs; the vent starts on Days 4-5 only; the title stops every bed; the menu
## folder pauses the tree and with it the beds (spec 16.2: all audio pauses), and closing the folder resumes
## them; the loudness checker finds no violation in a 20 s run of the real day timeline.
## Real key events drive the menu (Escape opens and closes it). Run:
##   godot --headless --path /home/user/Carbon --script res://tests/unit/test_beds_running.gd
## Prints one PASS or FAIL line per check, then a summary. Exit 0 only when every check passes.

const MainScript := preload("res://scripts/main.gd")
const RUN_SECONDS := 20.0

var _checks := 0
var _fails := 0
var _started := false
var _main = null
var _gs = null
var _dd = null
var _ad = null


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


func _playing(bed: String) -> bool:
	return _ad.is_bed_playing(bed)


func _none_playing() -> bool:
	return not _playing("room_tone") and not _playing("hum") and not _playing("vent_shepard")


## Sends a real Escape key press and lets two frames pass, so the menu folder or the free view handles it.
func _press_escape() -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_ESCAPE
	key.physical_keycode = KEY_ESCAPE
	key.pressed = true
	Input.parse_input_event(key)
	await process_frame
	await process_frame


func _run() -> void:
	_gs = root.get_node("GameState")
	_dd = root.get_node("DayDirector")
	_ad = root.get_node("AudioDirector")
	_ad.set_checker_enabled(true)
	_check(OS.is_debug_build(), "this run is a debug build, so the loudness checker is on")
	var violations_at_start: int = _ad.get_checker_violations()

	_main = MainScript.new()
	_main.auto_boot = false
	root.add_child(_main)
	await process_frame
	_main.debug_start_game(4242)
	await process_frame
	_check(_none_playing(), "before any day runs, no bed plays")

	# --- Day 1: the beds start with the world -------------------------------------------------
	_main._begin_running()
	_check(_playing("room_tone"), "day 1: the room tone bed plays once the day runs")
	_check(_playing("hum"), "day 1: the hum bed plays once the day runs")
	_check(not _playing("vent_shepard"), "day 1: the vent bed does not play (spec 11.2: Days 4-5)")
	_check(absf(_ad.bed_player("hum").pitch_scale - 1.0) < 0.0001, "day 1: the hum pitch is 1.000")
	_check(absf(_ad.bed_target_db("hum")) < 0.01, "day 1: the hum settles at full level with all six fixtures lit")

	# --- The title stops every bed (spec 16.2: no background audio on the title) ----------------
	_main._on_quit_to_title()
	await process_frame
	_check(_none_playing(), "on the title no bed plays")
	_main.title.hide_title()
	_main._begin_running()
	_check(_playing("room_tone") and _playing("hum"), "a day that starts after the title plays the room tone and hum again")

	# --- Menu folder: the tree pause pauses the beds, and closing the folder resumes them ------
	await _press_escape()
	_check(_main.menu.is_open() and paused, "Esc opens the menu folder and pauses the tree")
	_check(not _playing("room_tone") and not _playing("hum"),
		"the menu folder pause stops the room tone and hum (spec 16.2: audio pauses)")
	await _press_escape()
	_check(not _main.menu.is_open() and not paused, "Esc closes the menu folder and unpauses the tree")
	_check(_playing("room_tone") and _playing("hum"), "returning from the menu folder restarts the room tone and hum")

	# --- Day 4: the vent joins on Days 4-5 (spec 11.2), and the hum takes the Day 4 pitch -------
	_dd.begin_day(4)
	_main._begin_running()
	# The engine can drop a tree pause that lands in the frame a 3D bed starts, so the folder opens a frame later.
	# A player cannot open it earlier: the folder needs a later input event.
	await process_frame
	_check(_playing("vent_shepard"), "day 4: the vent bed plays (spec 11.2: Days 4-5)")
	_check(_playing("room_tone") and _playing("hum"), "day 4: the room tone and hum still play")
	_check(absf(_ad.bed_player("hum").pitch_scale - 0.98) < 0.0001, "day 4: the hum pitch is 0.980")

	await _press_escape()
	_check(_main.menu.is_open() and paused, "day 4: Esc opens the menu folder and pauses the tree")
	_check(_none_playing(), "day 4: the menu folder pause stops all three beds, the vent included")
	await _press_escape()
	_check(not paused, "day 4: Esc closes the menu folder and unpauses the tree")
	_check(_playing("room_tone") and _playing("hum") and _playing("vent_shepard"),
		"day 4: returning from the menu folder restarts all three beds")

	# --- A 20 s run of the real day timeline, with the loudness checker on --------------------
	await create_timer(RUN_SECONDS).timeout
	_check(_playing("room_tone") and _playing("hum") and _playing("vent_shepard"),
		"the three beds still play after a %d s run" % int(RUN_SECONDS))
	var violations: int = _ad.get_checker_violations() - violations_at_start
	_check(violations == 0, "the loudness checker reports no violations from the first bed start to the end of a %d s run (%d found)"
		% [int(RUN_SECONDS), violations])
	_check(_ad.get_checker_playbacks() >= 3, "the checker judged the beds (%d playbacks)" % _ad.get_checker_playbacks())

	for bed in ["room_tone", "hum", "vent_shepard"]:
		_ad.stop_bed(bed)
	print("BEDS: %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)
