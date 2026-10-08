extends SceneTree
## Endings headless checks (spec 15, 8.13, 8.12, 13.5). The controller runs on a virtual clock with a
## fake presentation that logs every call with its time. The checks cover the order and timing of
## Ending A, the refusal, the exit and the duplicate hall (Ending B), Ending C with the mixed run of
## acceptance test 4, the lock flags, the exit door geometry and the standing guard.
## Run: godot --headless --path /home/user/Carbon --script res://tests/endings/endings_test.gd
## Exit 0 only when every check passes. Prints "ENDINGS: N checks, M failures".

const EndingClock := preload("res://scripts/endings/ending_clock.gd")
const EndingsController := preload("res://scripts/endings/endings_controller.gd")
const EndingsPresentation := preload("res://scripts/endings/endings_presentation.gd")
const StandingGuard := preload("res://scripts/endings/standing_guard.gd")
const ExitDoor := preload("res://scripts/endings/exit_door.gd")
const DoorModel := preload("res://scripts/world/door_model.gd")
const HallC := preload("res://scripts/world/hall_c.gd")
const Content := preload("res://scripts/logic/content.gd")

const TOL := 0.05
const CHAR_S := 0.15  # ghost delay per character in the fake presentation
const TITLE_CHAR_S := 0.14

var _checks := 0
var _fails := 0
var _started := false
var _fake: Fake = null
var _clock: EndingClock = null
var _ctl = null
var _gs = null
var _dd = null
var _tt = null


## A presentation that logs each call with the virtual time. Its typing takes CHAR_S per character.
class Fake extends RefCounted:
	var clock = null
	var log: Array = []
	var paper := false
	var ghost_end := 0.0
	var crossed_at := INF
	var distance := 10.0
	var rattles := 0

	func reset() -> void:
		log = []
		ghost_end = 0.0
		crossed_at = INF
		distance = 10.0
		rattles = 0

	func _rec(fn: String, args: Array = []) -> void:
		log.append({"t": clock.now(), "name": fn, "args": args})

	func times(fn: String) -> Array:
		var out: Array = []
		for e in log:
			if e.name == fn:
				out.append(float(e.t))
		return out

	func args_of(fn: String) -> Array:
		var out: Array = []
		for e in log:
			if e.name == fn:
				out.append(e.args)
		return out

	func has_called(fn: String) -> bool:
		return not times(fn).is_empty()

	func has_paper() -> bool:
		return paper

	func ghost_idle() -> bool:
		return clock.now() >= ghost_end

	func key_delay_ms(_prev: String, _ch: String) -> float:
		return CHAR_S * 1000.0

	func player_crossed() -> bool:
		return clock.now() >= crossed_at

	func figure_distance() -> float:
		return distance

	func fixture_off(index: int) -> void:
		_rec("fixture_off", [index])

	func fixture_on(index: int) -> void:
		_rec("fixture_on", [index])

	func paper_ejected() -> void:
		_rec("paper_ejected")

	func blank_sheet_loaded() -> void:
		_rec("blank_sheet_loaded")

	func ghost_typed(text: String) -> void:
		_rec("ghost_typed", [text])
		ghost_end = clock.now() + text.length() * CHAR_S

	func lamp_off() -> void:
		_rec("lamp_off")

	func faded_to_black(seconds: float) -> void:
		_rec("faded_to_black", [seconds])

	func faded_in(seconds: float) -> void:
		_rec("faded_in", [seconds])

	func final_shot() -> void:
		_rec("final_shot")

	func clerk_key(letter: String, delay_ms: float) -> void:
		_rec("clerk_key", [letter, delay_ms])

	func cut_to_black() -> void:
		_rec("cut_to_black")

	func title_typed(text: String, ms_per_char: float) -> void:
		_rec("title_typed", [text, ms_per_char])

	func title_cleared() -> void:
		_rec("title_cleared")

	func carbon_stack_moved() -> void:
		_rec("carbon_stack_moved")

	func carbon_loaded() -> void:
		_rec("carbon_loaded")

	func camera_to_typing(seconds: float) -> void:
		_rec("camera_to_typing", [seconds])

	func camera_to_free(seconds: float) -> void:
		_rec("camera_to_free", [seconds])

	func silence() -> void:
		_rec("silence")

	func restore_record(desks: Array) -> void:
		_rec("restore_record", [desks])

	func refusal_memo() -> void:
		_rec("refusal_memo")

	func exit_unlocked() -> void:
		_rec("exit_unlocked")

	func door_swing(seconds: float) -> void:
		_rec("door_swing", [seconds])

	func duplicate_hall_set() -> void:
		_rec("duplicate_hall_set")

	func door_rattle() -> void:
		rattles += 1
		_rec("door_rattle")


## Stands in for the player (seated) and the desk (drawer closed) when a click is simulated.
class FakePlayer extends Node:
	var seated := true

	func is_seated() -> bool:
		return seated


class FakeDesk extends Node:
	var lower_open := false

	func drawer_open(_which: String) -> bool:
		return lower_open


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: ", label)


func _near(a: float, b: float) -> bool:
	return absf(a - b) <= TOL


## Fresh virtual clock, fake presentation and controller state for one scenario.
func _scenario(paper_loaded: bool, lit_all: bool) -> void:
	_clock = EndingClock.new(true, null)
	_fake = Fake.new()
	_fake.clock = _clock
	_fake.paper = paper_loaded
	_ctl.clock = _clock
	_ctl.reset()
	_ctl.set_credits_enabled(false)
	_gs.new_game(777)
	for f in range(1, 7):
		_gs.fixture_lit[str(f)] = lit_all
	_ctl.presentation = _fake
	_returned = 0


func _run() -> void:
	_gs = root.get_node("GameState")
	_dd = root.get_node("DayDirector")
	_tt = root.get_node("TextTokens")
	_ctl = EndingsController.new()
	root.add_child(_ctl)
	_ctl.setup(null, null)
	_ctl.returned_to_title.connect(_on_returned)
	_ctl.bind_interaction(null, null, null)
	_ctl.set_credits_enabled(false)
	_test_ending_a()
	_test_ending_a_skips()
	_test_ending_a_no_paper()
	_test_refusal_and_exit()
	_test_duplicate_timeout()
	_test_ending_c_mixed_run()
	_test_ending_c_refused_without_carbons()
	_test_standing_guard()
	_test_exit_door_geometry()
	_test_presentation_hall()
	print("ENDINGS: ", _checks, " checks, ", _fails, " failures")
	quit(0 if _fails == 0 else 1)


var _returned := 0


func _on_returned() -> void:
	_returned += 1


# --- Ending A ---------------------------------------------------------------------------------

func _test_ending_a() -> void:
	_scenario(true, true)
	_dd.ro5_sent.emit(true)
	var offs := _fake.args_of("fixture_off")
	var off_t := _fake.times("fixture_off")
	_check(offs == [[5], [6], [3], [4], [1], [2]], "A: fixture order F5, F6, F3, F4, F1, F2")
	for i in range(off_t.size()):
		_check(_near(off_t[i], 3.0 + 2.0 * i), "A: fixture %d off at %.1f s (got %.2f)" % [i, 3.0 + 2.0 * i, off_t[i]])
	var last_off: float = off_t[off_t.size() - 1]
	var eject := _fake.times("paper_ejected")
	_check(eject.size() == 1 and _near(eject[0], last_off + 2.0), "A: paper ejected 2.0 s after the last fixture")
	var blank := _fake.times("blank_sheet_loaded")
	_check(blank.size() == 1 and _near(blank[0], last_off + 2.0 + 0.6), "A: blank sheet slides in after the 0.6 s eject")
	var ghost_lines: Array = _fake.args_of("ghost_typed")
	var expect_ghost: String = String(Content.endings()["A"]["ghost_lines"][0])
	_check(ghost_lines.size() == 1 and String(ghost_lines[0][0]) == expect_ghost, "A: ghost line is the one in endings.json")
	var ghost_t: float = _fake.times("ghost_typed")[0]
	_check(_near(ghost_t, last_off + 2.0 + 0.6 + 0.6), "A: ghost typing starts after the paper_in")
	var ghost_done: float = ghost_t + expect_ghost.length() * CHAR_S
	var lamp := _fake.times("lamp_off")
	_check(lamp.size() == 1 and _near(lamp[0], ghost_done + 3.0), "A: lamp off 3.0 s after the last character")
	var fade := _fake.times("faded_to_black")
	_check(fade.size() == 1 and _near(fade[0], lamp[0] + 2.0), "A: fade to black 2.0 s after the lamp hold")
	var fade_args: Array = _fake.args_of("faded_to_black")
	_check(not fade_args.is_empty() and _near(float(fade_args[0][0]), 2.0), "A: fade lasts 2.0 s")
	var final := _fake.times("final_shot")
	_check(final.size() == 1 and _near(final[0], fade[0] + 2.0), "A: final shot after the fade")
	_check(_ctl.input_off() and _ctl.standing_locked() and _ctl.typing_locked(), "A: input off, standing and typing locked in the final shot")
	var keys := _fake.times("clerk_key")
	_check(keys.size() > 10, "A: the clerk stream types through the final shot (%d keys)" % keys.size())
	var all_in := true
	for k in keys:
		if k < final[0] - 1e-6 or k > final[0] + 12.0 + 1e-6:
			all_in = false
	_check(all_in, "A: every clerk key falls inside the 12.0 s final hold")
	var cut := _fake.times("cut_to_black")
	_check(cut.size() == 1 and _near(cut[0], final[0] + 12.0), "A: cut to black after the 12.0 s hold")
	var title: Array = _fake.args_of("title_typed")
	var expect_title: String = String(Content.endings()["A"]["title_lines"][0])
	_check(title.size() == 1 and String(title[0][0]) == expect_title and float(title[0][1]) == 140.0, "A: title is CONTINUITY IS EVERYTHING. at 140 ms per character")
	var cleared := _fake.times("title_cleared")
	_check(cleared.size() == 1 and _near(cleared[0], cut[0] + expect_title.length() * TITLE_CHAR_S + 3.0), "A: title held 3.0 s, then cleared")
	_check(_ctl.ending_id == "A" and _gs.ending == "A", "A: ending set to A")
	_check(_returned == 1, "A: credits (disabled in this test) then the title")
	_check(not _fake.has_called("carbon_stack_moved"), "A: no carbon movement in Ending A")
	_check(_fake.rattles == 0, "A: no door rattle in Ending A")


func _test_ending_a_skips() -> void:
	_scenario(true, true)
	_gs.fixture_lit["5"] = false
	_gs.fixture_lit["3"] = false
	_ctl.reset()
	_dd.ro5_sent.emit(true)
	var offs := _fake.args_of("fixture_off")
	_check(offs == [[6], [4], [1], [2]], "A skip: already-off fixtures F5 and F3 are skipped")
	var off_t := _fake.times("fixture_off")
	_check(_near(off_t[0], 3.0) and _near(off_t[1], 5.0) and _near(off_t[3], 9.0), "A skip: the remaining switches stay 2.0 s apart from 3.0 s")
	_check(_near(_fake.times("paper_ejected")[0], off_t[3] + 2.0), "A skip: eject 2.0 s after the last actual switch")


func _test_ending_a_no_paper() -> void:
	_scenario(false, true)
	_ctl.reset()
	_dd.ro5_sent.emit(true)
	_check(not _fake.has_called("paper_ejected"), "A no paper: nothing is ejected")
	var blank := _fake.times("blank_sheet_loaded")
	_check(blank.size() == 1 and _near(blank[0], 13.0 + 2.0), "A no paper: blank sheet 2.0 s after the last fixture (13.0 s + 2.0)")


# --- Refusal and Ending B -----------------------------------------------------------------------
## In virtual mode a sequence runs to its end inside the call that starts it, so the refusal runs at
## RO-5 (memo and unlock at 5.0 s), and the exit route runs inside the exit click.

func _test_refusal_and_exit() -> void:
	_scenario(false, true)
	_ctl.reset()
	_fake.distance = 2.4  # within 2.5 m of the figure as soon as the walk begins
	_fake.crossed_at = 7.0
	_dd.ro5_sent.emit(false)
	_check(_ctl.menu_locked(), "B: the menu is locked from RO-5")
	_check(_ctl.lamp_locked(), "B: the lamp is locked after the refusal")
	var memo := _fake.times("refusal_memo")
	var unlock := _fake.times("exit_unlocked")
	_check(memo.size() == 1 and _near(memo[0], 5.0), "B: refusal memo at 5.0 s")
	_check(unlock.size() == 1 and _near(unlock[0], 5.0), "B: exit unlocks at the same moment as the memo")
	_check(_ctl.exit_unlocked, "B: controller records the unlock")
	_check(not _ctl.standing_locked() and not _ctl.typing_locked() and not _ctl.desk_locked(), "B: after the refusal, standing, typing and the desk are free")
	_ctl._on_action("door_exit", null, Vector3.ZERO)
	var swing := _fake.times("door_swing")
	_check(swing.size() == 1 and _near(swing[0], 5.0) and _fake.args_of("door_swing")[0][0] == 1.2, "B exit: the door swings for 1.2 s at the click")
	var fade := _fake.times("faded_to_black")
	_check(fade.size() >= 1 and _near(fade[0], 7.0) and _fake.args_of("faded_to_black")[0][0] == 1.5, "B exit: fade to black over 1.5 s once the camera crosses z = 6.1 (at 7.0 s)")
	var dup := _fake.times("duplicate_hall_set")
	_check(dup.size() == 1 and _near(dup[0], 8.5), "B exit: the duplicate hall is set after the fade")
	var fin := _fake.times("faded_in")
	_check(fin.size() == 1 and _near(fin[0], 8.5) and _fake.args_of("faded_in")[0][0] == 1.5, "B exit: fade in over 1.5 s")
	var walk_start := 10.0
	_check(fade.size() == 2 and _near(fade[1], walk_start), "B exit: the figure is within 2.5 m at once, so the walk ends at 10.0 s (got %s)" % str(fade))
	var title: Array = _fake.args_of("title_typed")
	_check(title.size() == 1 and String(title[0][0]) == "CLERK 0412 IS AT THEIR DESK." and float(title[0][1]) == 140.0, "B exit: end line CLERK 0412 IS AT THEIR DESK.")
	var cleared := _fake.times("title_cleared")
	_check(cleared.size() == 1 and _near(cleared[0], fade[1] + 3.0 + "CLERK 0412 IS AT THEIR DESK.".length() * TITLE_CHAR_S + 4.0), "B exit: fade 3.0 s, type, hold 4.0 s, clear")
	_check(_ctl.ending_id == "B" and _gs.ending == "B", "B exit: ending set to B")
	_check(_returned == 1, "B exit: back to the title after the credits")


func _test_duplicate_timeout() -> void:
	# The figure is never within 2.5 m: the walk ends 180 s after the fade-in.
	_scenario(false, true)
	_ctl.reset()
	_fake.distance = 10.0
	_fake.crossed_at = 7.0
	_dd.ro5_sent.emit(false)
	_fake.reset()
	_fake.crossed_at = 7.0
	_ctl._on_action("door_exit", null, Vector3.ZERO)
	var fade := _fake.times("faded_to_black")
	_check(fade.size() == 2 and _near(fade[1], 10.0 + 180.0), "B timeout: the walk ends 180 s after the fade-in (got %s)" % str(fade))
	_check(_ctl.ending_id == "B", "B timeout: ending B")


func _test_ending_c_mixed_run() -> void:
	# Acceptance test 4: redact DOBRA, J. ABEL and the next of kin; keep three carbons; refuse RO-5.
	_scenario(false, true)
	_ctl.reset()
	_gs.next_of_kin_raw = "TESTER NOK"
	_gs.carbons_kept_at_final = 3
	_gs.ro_results = {
		"RO-2": {"entries": {"03": true}, "listed": ["03", "05"]},
		"RO-3": {"entries": {"07": true}, "listed": ["07", "08"]},
		"RO-4": {"entries": {"02": true, "04": false}, "listed": ["02", "04"]},
	}
	_gs.fixture_lit["4"] = false
	_gs.fixture_lit["6"] = false
	var player := FakePlayer.new()
	var desk := FakeDesk.new()
	root.add_child(player)
	root.add_child(desk)
	_ctl.bind_interaction(null, player, desk)
	_dd.ro5_sent.emit(false)
	_fake.reset()
	_ctl._on_action("carbon_spot", null, Vector3.ZERO)
	var ghost: Array = _fake.args_of("ghost_typed")
	_check(ghost.size() == 1, "C: the ghost record starts after the carbon click")
	var expect_name := String(_tt.substitute("{NEXT_OF_KIN}"))
	var expect := ["RECORD RESTORED", "DOBRA, KASIMIR", "J. ABEL", expect_name, "CLERK 0412"]
	var got: PackedStringArray = String(ghost[0][0]).split("\n")
	_check(Array(got) == expect, "C: lines are RECORD RESTORED, DOBRA, KASIMIR, J. ABEL, the next of kin, CLERK 0412 (got %s)" % str(Array(got)))
	var restore := _fake.args_of("restore_record")
	_check(restore.size() == 1 and restore[0][0] == ["7"], "C: only Desk 7 comes back (J. ABEL)")
	var silence := _fake.times("silence")
	var ghost_end := _fake.ghost_end
	_check(silence.size() == 1 and _near(silence[0], ghost_end), "C: silence when the last line finishes")
	var on_t := _fake.times("fixture_on")
	var on_args := _fake.args_of("fixture_on")
	_check(on_args == [[4], [6]], "C: unlit F4 and F6 switch on, in the order F2, F1, F4, F3, F6, F5")
	_check(on_t.size() == 2 and _near(on_t[0], silence[0] + 1.0) and _near(on_t[1], on_t[0] + 1.5), "C: fixtures start 1.0 s after the silence, 1.5 s apart")
	var free := _fake.times("camera_to_free")
	_check(free.size() == 1 and _near(free[0], on_t[1] + 1.5), "C: camera back to the free view after the last fixture")
	var fade := _fake.times("faded_to_black")
	_check(fade.size() == 1 and _near(fade[0], free[0] + 0.8 + 20.0), "C: fade 20.0 s after the camera returns to free view")
	var title: Array = _fake.args_of("title_typed")
	_check(title.size() == 1 and String(title[0][0]) == "THE RECORD IS KEPT.", "C: end line THE RECORD IS KEPT.")
	_check(_ctl.ending_id == "C" and _gs.ending == "C", "C: ending set to C")
	_check(_returned == 1, "C: back to the title after the credits")
	_check(_ctl.input_off() and _ctl.standing_locked(), "C: input off after the ending")
	root.remove_child(player)
	root.remove_child(desk)
	player.free()
	desk.free()


func _test_ending_c_refused_without_carbons() -> void:
	_scenario(false, true)
	_ctl.reset()
	_gs.carbons_kept_at_final = 2
	var player := FakePlayer.new()
	var desk := FakeDesk.new()
	root.add_child(player)
	root.add_child(desk)
	_ctl.bind_interaction(null, player, desk)
	# Before RO-5 the exit is locked, so its handle rattles.
	_ctl._on_action("door_exit", null, Vector3.ZERO)
	_check(_fake.rattles == 1, "exit: a locked door rattles")
	_dd.ro5_sent.emit(false)
	_fake.reset()
	_ctl._on_action("carbon_spot", null, Vector3.ZERO)
	_check(not _fake.has_called("ghost_typed") and not _ctl.ending_running(), "C: two carbons is not enough, so the click does not start Ending C")
	_gs.carbons_kept_at_final = 3
	desk.lower_open = true
	_ctl._on_action("carbon_spot", null, Vector3.ZERO)
	_check(not _fake.has_called("ghost_typed"), "C: with the lower drawer open, the click does not start Ending C")
	desk.lower_open = false
	player.seated = false
	_ctl._on_action("carbon_spot", null, Vector3.ZERO)
	_check(not _fake.has_called("ghost_typed"), "C: standing, the click does not start Ending C")
	root.remove_child(player)
	root.remove_child(desk)
	player.free()
	desk.free()


# --- Standing guard and exit door ----------------------------------------------------------------

func _test_standing_guard() -> void:
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	_check(StandingGuard.is_space_press(space), "guard: a fresh Space press is recognised")
	var echo := InputEventKey.new()
	echo.keycode = KEY_SPACE
	echo.pressed = true
	echo.echo = true
	_check(not StandingGuard.is_space_press(echo), "guard: an auto-repeat is not a press")
	var other := InputEventKey.new()
	other.keycode = KEY_A
	other.pressed = true
	_check(not StandingGuard.is_space_press(other), "guard: other keys pass")
	# Propagation: a child guard swallows Space before its parent sees it while standing is locked.
	var probe := ProbeParent.new()
	root.add_child(probe)
	var guard := StandingGuard.new()
	var stub := StandLock.new()
	guard.controller = stub
	probe.add_child(guard)
	stub.locked = true
	root.push_input(space)
	_check(probe.count == 0, "guard: Space is swallowed by the guard while standing is locked")
	stub.locked = false
	root.push_input(space)
	_check(probe.count == 1, "guard: Space reaches the player when standing is free")
	root.remove_child(probe)
	probe.free()


class StandLock extends RefCounted:
	var locked := false

	func standing_locked() -> bool:
		return locked


class ProbeParent extends Node:
	var count := 0

	func _unhandled_input(event: InputEvent) -> void:
		if StandingGuard.is_space_press(event):
			count += 1


func _test_exit_door_geometry() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	DoorModel.build_exit(holder)
	var door := ExitDoor.new()
	_check(door.setup(holder), "exit: the door has a Leaf to swing")
	var leaf := holder.get_node("ExitDoor/Leaf") as Node3D
	var closed := door.free_edge_world()
	_check(_near(closed.x, -5.5) and _near(closed.z, 6.0), "exit: closed, the free edge is at x -5.5, z 6.0 (got %s)" % str(closed))
	leaf.rotation.y = deg_to_rad(-90.0)
	var open := door.free_edge_world()
	_check(_near(open.x, -6.5) and _near(open.z, 7.0), "exit: 90 degrees open, the free edge lies south at x -6.5, z 7.0 (got %s)" % str(open))
	door.reset_closed_locked()
	_check(not door.is_unlocked() and not door.is_open() and _near(leaf.rotation.y, 0.0), "exit: reset closes and locks the door")
	door.unlock()
	_check(door.is_unlocked(), "exit: unlock")
	root.remove_child(holder)
	holder.free()


# --- Presentation on the real hall ----------------------------------------------------------------

func _test_presentation_hall() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var hall := HallC.build(holder, {})
	var pres := EndingsPresentation.new()
	root.add_child(pres)
	pres.setup(null, hall, null, null, null, null)
	_gs.new_game(4242)
	pres.fixture_off(3)
	var light := hall.get_node("Fixture3") as OmniLight3D
	_check(not light.visible and _gs.fixture_lit["3"] == false, "hall: fixture_off switches the light off")
	pres.fixture_on(3)
	_check(light.visible and _gs.fixture_lit["3"] == true, "hall: fixture_on switches it back on")
	pres.duplicate_hall_set()
	_check(hall.get_node_or_null("Clerk04") != null, "hall: the duplicate hall has a clerk at Desk 4")
	_check(String(_gs.nameplate["4"]) == String(_tt.token_values().PLAYER_NAME), "hall: Desk 4 nameplate reads the player name")
	_check(bool(_gs.lamp_on), "hall: the lamp is on in the duplicate hall")
	var door := hall.get_node("ExitDoor/Leaf") as Node3D
	_check(_near(door.rotation.y, 0.0), "hall: the exit door is closed in the duplicate hall")
	pres.final_shot()
	_check(String(_gs.nameplate["4"]) == "0413", "hall: the final shot reads 0413")
	pres.free()
	holder.free()
