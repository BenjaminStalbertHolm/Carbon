extends SceneTree
## Acceptance test 2 (spec 20): the refusal run with carbons. The run types every transcription accurately, keeps
## every transcription carbon (none is filed), redacts nothing, and stamps every order RETURNED. It drives the real
## DayDirector and GameState (the logic of Days 1 to 5), the real TypewriterModel for the typing, and the real
## EndingsController for RO-5 and the endings. Checked:
##   - RO-2 entries that were not redacted carry into RO-4 as 08 to 11 (spec 14.6);
##   - J. ABEL (Desk 7) and N. FERRAND (Desk 8) face Desk 4 from Day 4, and WEISS, CORA (Desk 9) from Day 5 (spec 8.9);
##   - four carbons are kept at RO-5, so the refusal leaves Ending C available (spec 15);
##   - the exit still leads to Ending B on the same run, and the carbon stack leads to Ending C with only
##     RECORD RESTORED and the player's name typed (spec 15.3, steps 3 and 5).
## The on-screen parts (the carbon stack, the figure at Desk 7 turning) are MANUAL, see tests/ACCEPTANCE.md.
## Headless:
##   godot --headless --path . --script res://tests/acceptance/test_refusal_carbons.gd
## Prints one PASS or FAIL line per check, then "RESULT: PASS, N failure(s)". Exit 0 only when N is 0.

const Play := preload("res://tests/acceptance/playthrough_helpers.gd")
const Probe := preload("res://tests/acceptance/endings_probe.gd")
const EndingClock := preload("res://scripts/endings/ending_clock.gd")
const EndingsController := preload("res://scripts/endings/endings_controller.gd")

const CARRIED_KEYS := ["08", "09", "10", "11"]
const CARRIED_NAMES := ["DOBRA, KASIMIR", "FELL, ODETTE", "MORAVEC, AUREL", "MORAVEC, ILSE"]
const RECORD_LINE := "RECORD RESTORED"
const END_C_LINE := "THE RECORD IS KEPT."
const KEPT_AT_RO5 := 4
const TOL := 0.05

var _checks := 0
var _failures := 0
var _ran := false
var _gs
var _dd
var _tt
var _ctl
var _probe
var _interaction


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
	_gs = root.get_node("GameState")
	_dd = root.get_node("DayDirector")
	_tt = root.get_node("TextTokens")
	var clock := EndingClock.new(true, null)
	_probe = Probe.new()
	_probe.clock = clock
	var player := Probe.FakePlayer.new()
	var desk := Probe.FakeDesk.new()
	_interaction = Probe.FakeInteraction.new()
	root.add_child(player)
	root.add_child(desk)
	root.add_child(_interaction)
	_ctl = EndingsController.new()
	root.add_child(_ctl)
	_ctl.setup(_probe, clock)
	_ctl.bind_interaction(_interaction, player, desk)
	_ctl.set_credits_enabled(false)

	# The run up to RO-5, with the carbon stack's record checked at Day 2, 4 and 5 (spec 14.6, 8.9).
	var first := _refusal_game(false, "carbon")
	var snaps: Dictionary = first.out.snaps
	var carried: Array = snaps[3].carried
	var keys: Array = []
	var names: Array = []
	for c in carried:
		keys.append(String(c.key))
		names.append(String(c.name))
	_check(keys == CARRIED_KEYS, "test 2: RO-2 entries not redacted carry into RO-4 as 08 to 11 (got %s)" % str(keys))
	_check(names == CARRIED_NAMES, "test 2: the carried entries are DOBRA, FELL, MORAVEC A. and MORAVEC I., in order")
	var rows: Array = first.out.ro4_rows
	var rows_ok := true
	for i in range(CARRIED_KEYS.size()):
		var found := false
		for line in rows:
			if String(line).begins_with(CARRIED_KEYS[i] + " ") and String(line).contains(CARRIED_NAMES[i]):
				found = true
		rows_ok = rows_ok and found
	_check(rows_ok, "test 2: the RO-4 order prints each carried row under its new key 08 to 11")
	_check(bool(_gs_flag_all_false(first.ro2_entries)), "test 2: nothing is redacted on RO-2 (the stamp is RETURNED)")
	_check(String(first.first_stamp_ro2) == "RETURNED", "test 2: RO-2 first impression is RETURNED")
	_check(snaps[4].redacted.is_empty() and snaps[5].redacted.is_empty(), "test 2: no entity is redacted in the refusal run")

	var d4: Dictionary = snaps[4]
	_check(bool(d4.faces.get("7", false)) and bool(d4.faces.get("8", false)),
		"test 2: J. ABEL (Desk 7) and N. FERRAND (Desk 8) face Desk 4 from Day 4")
	_check(d4.refused.has(7) and d4.refused.has(8), "test 2: Desks 7 and 8 are on the refused list at the start of Day 4")
	_check(bool(d4.present.get("7", false)) and bool(d4.present.get("8", false)),
		"test 2: the refused clerks stay at their desks (only a redacted clerk leaves)")
	_check(not bool(d4.faces.get("9", false)), "test 2: WEISS does not face Desk 4 on Day 4")
	var d5: Dictionary = snaps[5]
	_check(bool(d5.faces.get("9", false)) and d5.refused.has(9),
		"test 2: WEISS, CORA (Desk 9) faces Desk 4 from Day 5")

	_check(int(first.kept) == KEPT_AT_RO5, "test 2: four transcription carbons are kept at RO-5 (got %d)" % int(first.kept))
	_check(int(first.gs_kept_at_final) == KEPT_AT_RO5, "test 2: GameState records four carbons kept at the final order")
	_check(bool(first.refused), "test 2: RO-5 is refused (Desk 4 entry not redacted)")
	_check(first.unlock_times.size() == 1 and absf(float(first.unlock_times[0]) - 5.0) <= TOL,
		"test 2: the refusal memo and the exit unlock 5.0 s after RO-5")

	# The carbon stack: Ending C with the spec lines (spec 15.3 step 3).
	var expect_lines := [RECORD_LINE, String(_tt.token_values().PLAYER_NAME)]
	_check(String(_tt.token_values().PLAYER_NAME) == "ANNA MARIA TESTER", "test 2: the player's name is the one typed on P-1")
	_check(Array(first.ghost_lines) == expect_lines,
		"test 2: the carbon stack types only RECORD RESTORED and the player's name (got %s)" % str(first.ghost_lines))
	_check(first.restore_desks == [], "test 2: nothing is restored (nothing was redacted)")
	_check(first.silence_count == 1, "test 2: the room goes silent once the record has been typed")
	_check(String(first.ending) == "C" and String(first.gs_ending) == "C", "test 2: the carbon stack reaches Ending C")
	_check(String(first.title) == END_C_LINE, "test 2: Ending C ends on THE RECORD IS KEPT.")

	# The same refusal, with the exit (spec 15.2): still Ending B, with four carbons kept.
	var second := _refusal_game(false, "exit")
	_check(int(second.kept) == KEPT_AT_RO5 and bool(second.refused), "test 2: the exit run is the same refusal, with four carbons kept")
	_check(String(second.ending) == "B" and String(second.gs_ending) == "B",
		"test 2: the exit still leads to Ending B on the refusal run with carbons")
	_check(not bool(second.ghost_typed), "test 2: the exit does not start Ending C")

	print("ACCEPTANCE TEST 2 (refusal run with carbons): %d checks, %d failure(s)" % [_checks, _failures])
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## One refusal game from a new start: Days 1 to 5 as the refusal run (file_carbons decides whether carbons are filed),
## RO-5 refused, then one click: "carbon" on the carbon stack, or "exit" on the exit door. Returns what the run showed.
func _refusal_game(file_carbons: bool, click: String) -> Dictionary:
	_ctl.reset()
	_probe.reset()
	var run := Play.new(_gs, _dd)
	var out: Dictionary = run.run_days_1_to_4(file_carbons, [])
	_dd.tick(5.0)
	run.form("P-1D", {"F1": Play.NAME, "F2": Play.KIN, "F3": "LANTERN", "F4": "NO", "F5": Play.NAME})
	_dd.tick(5.0)
	var kept: int = run.transcription_carbons_kept()
	var ro2: Dictionary = _gs.ro_results.get("RO-2", {"entries": {}})
	var result := {
		"out": out,
		"kept": kept,
		"ro2_entries": ro2.get("entries", {}),
		"first_stamp_ro2": String(_gs.first_stamp.get("RO-2", "")),
	}
	run.order("RO-5", [], "RETURNED")
	result.gs_kept_at_final = _gs.carbons_kept_at_final
	result.refused = _ctl.refused
	result.unlock_times = _probe.times("exit_unlocked")
	_probe.crossed_at = 7.0
	if click == "carbon":
		_interaction.action_pressed.emit("carbon_spot", null, Vector3.ZERO)
	elif click == "exit":
		_interaction.action_pressed.emit("door_exit", null, Vector3.ZERO)
	var ghost: Array = _probe.args_of("ghost_typed")
	result.ghost_typed = not ghost.is_empty()
	result.ghost_lines = Array(String(ghost[0][0]).split("\n")) if not ghost.is_empty() else []
	var restores: Array = _probe.args_of("restore_record")
	result.restore_desks = restores[0][0] if not restores.is_empty() else null
	result.silence_count = _probe.times("silence").size()
	var title: Array = _probe.args_of("title_typed")
	result.title = String(title[0][0]) if not title.is_empty() else ""
	result.ending = _ctl.ending_id
	result.gs_ending = _gs.ending
	return result


func _gs_flag_all_false(entries: Dictionary) -> bool:
	for key in entries.keys():
		if bool(entries[key]):
			return false
	return true
