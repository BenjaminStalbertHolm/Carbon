extends SceneTree
## Headless checks for the ending and door hooks in interaction.gd (spec 15.1 step 1, 15.2 step 1,
## 8.13, 11.1) and the gains of QUESTION-29. The endings flags come from a stub controller, so each
## lock is set directly. Run: godot --headless --path /home/user/Carbon --script res://tests/player/hooks_test.gd
## Exit 0 only when every check passes. Prints "HOOKS: N checks, M failures".
const MainScript := preload("res://scripts/main.gd")
const Interaction := preload("res://scripts/player/interaction.gd")
const TypewriterView := preload("res://scripts/typewriter/typewriter_view.gd")

var _checks := 0
var _fails := 0
var _started := false
var _main = null
var _gs = null
var _dd = null
var _ad = null
var _fake = null


## Stands in for main.gd as the interaction's controller: the endings flags and a focus flag.
class FakeController extends Node:
	var typing := false
	var lamp := false
	var focus_calls := 0

	func typing_locked() -> bool:
		return typing

	func lamp_locked() -> bool:
		return lamp

	func is_focus_open() -> bool:
		return false

	func set_typing_focus(_on: bool) -> void:
		focus_calls += 1

	func open_read_view(_docs: Array, _index: int, _mode: String) -> void:
		pass

	func open_menu() -> void:
		pass


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


func _run() -> void:
	_gs = root.get_node("GameState")
	_dd = root.get_node("DayDirector")
	_ad = root.get_node("AudioDirector")
	_main = MainScript.new()
	_main.auto_boot = false
	root.add_child(_main)
	await process_frame
	_main.debug_start_game(4242)
	await process_frame
	_fake = FakeController.new()
	root.add_child(_fake)
	await _checks_typing_lock()
	_checks_lamp_lock()
	_checks_supervisor_door()
	_checks_constants()
	_teardown()
	print("HOOKS: %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)


# --- Hook 1: typing view while Ending A locks typing (spec 15.1 step 1) --------------------

func _checks_typing_lock() -> void:
	_main.interaction.controller = _fake
	_main.interaction.dispatch_click("blank_tray")
	var sheet: String = _main.interaction.hand_id()
	_check(_main.interaction.hand_kind() == "document" and sheet != "", "the typing lock test holds a blank sheet")
	_fake.typing = true
	_main.interaction.dispatch_click("typewriter")
	_check(not _main.typewriter.is_loaded(), "a locked typewriter click does not load the held sheet")
	_check(_main.interaction.hand_kind() == "document", "a locked typewriter click leaves the sheet in the hand")
	_check(not _main.typewriter.is_typing() and _fake.focus_calls == 0, "a locked typewriter click does not enter typing view")
	_fake.typing = false
	_main.interaction.dispatch_click("typewriter")
	_check(_main.interaction.hand_kind() == "", "with the lock released the typewriter click loads the sheet")
	await create_timer(1.6).timeout
	_main.typewriter.close_typing_view()
	await create_timer(0.8).timeout
	_main.interaction.controller = _main


# --- Hook 2: the lamp after the refusal (spec 15.2 step 1) ---------------------------------

func _checks_lamp_lock() -> void:
	_main.interaction.controller = _fake
	var clicks := [0]
	var counter := func() -> void:
		clicks[0] += 1
	_dd.lamp_click.connect(counter)
	_gs.lamp_on = true
	_fake.lamp = true
	_main.interaction.dispatch_click("lamp")
	_check(clicks[0] == 0, "a locked lamp makes no lamp_click (no sound, no DayDirector click)")
	_check(bool(_gs.lamp_on), "a locked lamp leaves the lamp as it was")
	_fake.lamp = false
	_main.interaction.dispatch_click("lamp")
	_check(clicks[0] == 1, "with the lock released the lamp click is made")
	_dd.lamp_click.disconnect(counter)
	_main.interaction.controller = _main


# --- Hook 5: the supervisor door handle (spec 8.13) ---------------------------------------

func _checks_supervisor_door() -> void:
	var it = _main.interaction
	_gs.day = 3
	var before: int = _ad.get_checker_playbacks()
	_ad.set_checker_enabled(true)
	it.on_door_handle_clicked("supervisor")
	_check(int(_ad.get_checker_playbacks()) - before == 1, "Day 3: a supervisor click plays one door_rattle")
	_check(it._clack_in < 0.0, "Day 3: no key_clack follows the rattle")
	it.on_door_handle_clicked("exit")
	_check(it._clack_in < 0.0 and int(_ad.get_checker_playbacks()) - before == 1, "the exit handle does nothing in the supervisor hook")
	_gs.day = 4
	before = _ad.get_checker_playbacks()
	it.on_door_handle_clicked("supervisor")
	_check(int(_ad.get_checker_playbacks()) - before == 1, "Day 4: the rattle plays at once")
	_check(absf(it._clack_in - Interaction.SUPERVISOR_CLACK_DELAY_S) < 0.0001, "Day 4: the key_clack is due 1.2 s after the rattle")
	it._process(1.0)
	_check(int(_ad.get_checker_playbacks()) - before == 1, "Day 4: no key_clack before 1.2 s")
	it._process(0.25)
	_check(int(_ad.get_checker_playbacks()) - before == 2, "Day 4: one key_clack plays 1.2 s after the rattle")
	_check(it._clack_in < 0.0, "Day 4: the key_clack is played once")
	_ad.set_checker_enabled(false)


func _checks_constants() -> void:
	var rattle := _file_peak_db("res://assets/audio/door_rattle.wav")
	var clack := _file_peak_db("res://assets/audio/key_clack_1.wav")
	_check(absf(rattle - Interaction.DOOR_RATTLE_PEAK_DB) < 0.05, "door_rattle.wav peaks at -22 dBFS (%.2f)" % rattle)
	_check(absf(clack - Interaction.KEY_CLACK_PEAK_DB) < 0.05, "key_clack_1.wav peaks at -10 dBFS (%.2f)" % clack)
	_check(absf(Interaction.SUPERVISOR_RATTLE_DB - Interaction.DOOR_RATTLE_PEAK_DB) < 0.0001, "the rattle gain is 0 dB, so it plays at -22 dBFS")
	_check(absf((Interaction.SUPERVISOR_CLACK_DB - Interaction.KEY_CLACK_PEAK_DB) - (-20.0)) < 0.0001, "the key_clack gain is -20 dB, so it plays at -30 dBFS")
	_check(absf(TypewriterView.CAM_MS - 500.0) < 0.0001, "typing view camera tween is 0.5 s (spec 6.3, entry and Esc exit)")


## Peak of a 16-bit mono WAV in dBFS, read from the imported stream.
func _file_peak_db(path: String) -> float:
	var stream = load(path)
	if not (stream is AudioStreamWAV):
		return 0.0
	var data: PackedByteArray = (stream as AudioStreamWAV).data
	var peak := 0.0
	var i := 0
	while i + 1 < data.size():
		var s := absf(float(data.decode_s16(i)) / 32768.0)
		peak = maxf(peak, s)
		i += 2
	return 20.0 * log(peak) / log(10.0)


func _teardown() -> void:
	_main.interaction.controller = _main
	if is_instance_valid(_fake):
		_fake.queue_free()
	if _main != null:
		_main.queue_free()
