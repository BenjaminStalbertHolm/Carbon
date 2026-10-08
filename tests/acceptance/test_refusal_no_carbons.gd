extends SceneTree
## Acceptance test 3 (spec 20): the refusal run without carbons. Every carbon is filed into the drawer before each
## lamp (spec 8.5), so none is kept at RO-5. It drives the real DayDirector, GameState, TypewriterModel and
## EndingsController, and the real EndingsPresentation on a built Hall C for the duplicate hall. Checked:
##   - on RO-5 the refusal unlocks the exit (5.0 s), and clicking the carbon stack does not start Ending C (spec 15.3);
##   - the exit door leads to Ending B, with the door swing, the fade, the duplicate hall and CLERK 0412 IS AT THEIR DESK.;
##   - the duplicate hall shows the player's name at Desk 4, truncated to 14 characters (spec 15.2 step 4), with a clerk
##     at Desk 4 and the Desk 4 lamp on.
## What is seen on screen (the exit door and the name's pixels on the nameplate) is MANUAL, see tests/ACCEPTANCE.md.
## Headless:
##   godot --headless --path . --script res://tests/acceptance/test_refusal_no_carbons.gd
## Prints one PASS or FAIL line per check, then "RESULT: PASS, N failure(s)". Exit 0 only when N is 0.

const Play := preload("res://tests/acceptance/playthrough_helpers.gd")
const Probe := preload("res://tests/acceptance/endings_probe.gd")
const EndingClock := preload("res://scripts/endings/ending_clock.gd")
const EndingsController := preload("res://scripts/endings/endings_controller.gd")
const EndingsPresentation := preload("res://scripts/endings/endings_presentation.gd")
const HallC := preload("res://scripts/world/hall_c.gd")

const NAMEPLATE_LIMIT := 14
const END_B_LINE := "CLERK 0412 IS AT THEIR DESK."
const TOL := 0.05

var _checks := 0
var _failures := 0
var _ran := false


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _run() -> void:
	var gs = root.get_node("GameState")
	var dd = root.get_node("DayDirector")
	var un = root.get_node("UnseenChanges")

	# The hall the duplicate hall is set in: the built Hall C, bound to the unseen registry as in the game.
	var holder := Node3D.new()
	root.add_child(holder)
	var hall: Node3D = HallC.build(holder, {})
	un.bind_hall(hall)
	var pres := EndingsPresentation.new()
	root.add_child(pres)
	pres.setup(null, hall, null, null, null, null)

	var clock := EndingClock.new(true, null)
	var probe := Probe.new()
	probe.clock = clock
	probe.hall_pres = pres
	var player := Probe.FakePlayer.new()
	var desk := Probe.FakeDesk.new()
	var interaction := Probe.FakeInteraction.new()
	root.add_child(player)
	root.add_child(desk)
	root.add_child(interaction)
	var ctl := EndingsController.new()
	root.add_child(ctl)
	ctl.setup(probe, clock)
	ctl.bind_interaction(interaction, player, desk)
	ctl.set_credits_enabled(false)

	# Days 1 to 5 with every carbon filed at each lamp, then RO-5 is refused.
	var run := Play.new(gs, dd)
	var out: Dictionary = run.run_days_1_to_4(true, [])
	var snaps: Dictionary = out.snaps
	_check(run.transcription_carbons_kept() == 0, "test 3: the carbons were filed each day, none is kept at the lamp of Day 4")
	_check(snaps[5].carbons_kept == 0, "test 3: no transcription carbon is outside the drawer on Day 5 (overnight deleted the drawer)")
	dd.tick(5.0)
	run.form("P-1D", {"F1": Play.NAME, "F2": Play.KIN, "F3": "LANTERN", "F4": "NO", "F5": Play.NAME})
	dd.tick(5.0)
	run.order("RO-5", [], "RETURNED")
	_check(gs.carbons_kept_at_final == 0, "test 3: GameState records no carbons kept at the final order")
	_check(ctl.refused and ctl.menu_locked(), "test 3: RO-5 is refused: the menu is locked and the refusal runs")
	var unlock: Array = probe.times("exit_unlocked")
	_check(unlock.size() == 1 and absf(float(unlock[0]) - 5.0) <= TOL, "test 3: the exit unlocks with the refusal memo, 5.0 s after RO-5")

	# The carbon stack does not lead to Ending C without carbons (spec 15.3).
	probe.crossed_at = 7.0
	interaction.action_pressed.emit("carbon_spot", null, Vector3.ZERO)
	_check(not probe.has_called("ghost_typed") and not ctl.ending_running(),
		"test 3: clicking the carbon stack with no carbons kept does not start Ending C")
	_check(ctl.ending_id == "none" and gs.ending == "none", "test 3: the ending is still unset after the carbon stack click")

	# The exit leads to Ending B (spec 15.2).
	interaction.action_pressed.emit("door_exit", null, Vector3.ZERO)
	var swing: Array = probe.times("door_swing")
	_check(swing.size() == 1 and absf(float(swing[0]) - 5.0) <= TOL, "test 3: the exit door swings at the click (1.2 s)")
	var fades: Array = probe.times("faded_to_black")
	_check(fades.size() == 2 and absf(float(fades[0]) - 7.0) <= TOL, "test 3: the fade to black starts as the camera crosses z = 6.1")
	_check(probe.times("duplicate_hall_set").size() == 1, "test 3: the duplicate hall is set once, after the fade")
	var title: Array = probe.args_of("title_typed")
	_check(title.size() == 1 and String(title[0][0]) == END_B_LINE, "test 3: Ending B ends on CLERK 0412 IS AT THEIR DESK.")
	_check(ctl.ending_id == "B" and gs.ending == "B", "test 3: the exit leads to Ending B")

	# The duplicate hall: the player's name at Desk 4 (spec 15.2 step 4).
	var expect_plate := String(root.get_node("TextTokens").token_values().PLAYER_NAME).substr(0, NAMEPLATE_LIMIT)
	_check(expect_plate == "ANNA MARIA TES", "test 3: the Desk 4 text is the player's name truncated to 14 characters (got %s)" % expect_plate)
	_check(String(gs.nameplate.get("4", "")) == expect_plate,
		"test 3: the duplicate hall shows the player's name at Desk 4 (got '%s')" % String(gs.nameplate.get("4", "")))
	var desk4: Node = hall.find_child("Desk04", true, false)
	_check(desk4 != null and desk4.get_node_or_null("Nameplate") != null, "test 3: the Desk 4 nameplate is rebuilt in the hall with the name")
	_check(hall.find_child("Clerk04", true, false) != null, "test 3: a clerk sits at Desk 4 in the duplicate hall")
	_check(bool(gs.lamp_on), "test 3: the Desk 4 lamp is on in the duplicate hall")

	print("ACCEPTANCE TEST 3 (refusal run without carbons): %d checks, %d failure(s)" % [_checks, _failures])
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	pres.free()
	holder.free()
	quit(1 if _failures > 0 else 0)
