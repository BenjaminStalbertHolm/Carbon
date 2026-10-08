extends SceneTree
## Checks for the debug console commands (spec 21) and the day jump (spec 20, test 1 state). Each
## command is run through debug_commands.gd, the same code the console calls. Headless:
##   godot --headless --path . --script res://tests/acceptance/test_debug_console.gd
## Exit 0 means every check passed.

const MainScript := preload("res://scripts/main.gd")
const DebugCommands := preload("res://scripts/debug/debug_commands.gd")
const DebugConsole := preload("res://scripts/debug/debug_console.gd")
const DebugGuard := preload("res://scripts/debug/debug_guard.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")

var _failures := 0
var _checks := 0
var _ran := false
var _main
var _cmd
var _gs
var _dd


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


func _first(text: String) -> String:
	var lines: PackedStringArray = _cmd.run(text)
	return lines[0] if lines.size() > 0 else ""


func _write_text(sheet: Dictionary, text: String) -> void:
	for i in range(text.length()):
		DocModel.write_glyph(sheet.pages[0], 0, i, text.substr(i, 1), _gs.rng)


func _all(text: String) -> String:
	return "\n".join(_cmd.run(text))


func _run() -> void:
	_gs = root.get_node("GameState")
	_dd = root.get_node("DayDirector")
	_main = MainScript.new()
	_main.auto_boot = false
	root.add_child(_main)
	_cmd = DebugCommands.new(_main)

	# --- Guard and unknown commands ---
	_check(DebugGuard.enabled() == OS.is_debug_build(), "the guard reports the build flag")
	_check(DebugGuard.enabled(), "this check runs in a debug build (the console exists only there)")
	_check(_first("bogus") == "unknown command", "an unknown command prints 'unknown command'")
	_check(_cmd.run("").is_empty(), "an empty line prints nothing")
	_check(_first("day 9").begins_with("usage"), "day outside 1 to 5 prints the usage line")
	_check(_first("day x").begins_with("usage"), "day with text prints the usage line")

	# --- day N: the state of a compliant run (spec 20, test 1) ---
	_check(_first("day 3").begins_with("day 3"), "day 3 reports the jump")
	_check(_gs.day == 3, "day 3 sets GameState.day to 3")
	_check(_gs.ro_results.has("RO-2") and not _gs.ro_results.has("RO-3"), "day 3: RO-2 is processed, RO-3 is not")
	_check(bool(_gs.ro_results["RO-2"].entries.get("03", false)), "day 3: the RO-2 DOBRA entry is redacted")
	_check(bool(_gs.clerk_present.get("7", false)), "day 3: the Desk 7 clerk is still present")
	_check(_gs.nameplate.get("12", "") == "0411", "day 3: the Desk 12 nameplate reads 0411 (D2-U1)")
	_check(_gs.tokens_set and _gs.player_name_raw == "", "day 3: tokens set with a blank player name")
	_check(String(root.get_node("TextTokens").token_values().PLAYER_NAME) == "CLERK 0412", "day 3: PLAYER_NAME is CLERK 0412")
	_check(_dd.pending_events() == 2, "day 3 starts with the bell and the morning canister on the timeline")

	_check(_first("day 4").begins_with("day 4"), "day 4 reports the jump")
	_check(_gs.ro_results.has("RO-3"), "day 4: RO-3 is processed")
	_check(not bool(_gs.clerk_present.get("7", true)) and not bool(_gs.clerk_present.get("8", true)), "day 4: the Desk 7 and Desk 8 clerks are redacted")
	_check(_gs.nameplate.get("12", "x") == "", "day 4: the Desk 12 nameplate is blank (H. VANCE redacted)")
	_check(_gs.redacted_names.has("vance"), "day 4: vance is in redacted_names")

	_check(_first("day 5").begins_with("day 5"), "day 5 reports the jump")
	_check(bool(_gs.desk_removed.get("7", false)) and bool(_gs.desk_removed.get("8", false)), "day 5: desks 7 and 8 are removed")
	_check(not bool(_gs.fixture_lit.get("4", true)), "day 5: fixture F4 is off")
	_check(bool(_gs.fixture_lit.get("5", false)), "day 5: fixture F5 is on")
	_check(int(_gs.flags.get("quota_occupied", -1)) == 8, "day 5: the quota board counts 8 occupied desks")
	_check(bool(_gs.flags.get("tray_line", false)), "day 5: the blank sheets carry the typed name line (D5-U1)")
	_check(not bool(_gs.clerk_present.get("9", true)), "day 5: the Desk 9 clerk is redacted on RO-4")

	# --- skip: complete the active task with its output as it is (spec 21) ---
	_first("day 1")
	_dd.tick(10.0)
	_dd.tick(5.0)
	_check(_dd.active_task == "P-1", "day 1: P-1 is the active task after the morning")
	_check(_first("skip").begins_with("skip: sent P-1"), "skip sends the P-1 form")
	_check(_gs.last_task_done == "P-1", "skip completes P-1")
	_dd.tick(5.0)
	_check(_dd.active_task == "T-1", "day 1: T-1 is the active task")
	# A sheet of T-1 is already out, with text typed on it: skip sends it with that text, adds none,
	# and leaves its carbon on the carbon spot (spec 7.7 removal, not filed).
	var out_sid := String(_dd.take_blank_sheet())
	var out_carbon := String(_gs.docs[out_sid].twin)
	_write_text(_gs.docs[out_sid], "HELLO")
	_check(_gs.location_of(out_carbon) == "attached", "a sheet taken from the tray has its carbon attached")
	var sent_out := _first("skip")
	_check(sent_out.begins_with("skip: sent %s (the sheet out) for T-1" % out_sid), "skip sends the sheet of T-1 that is out")
	_check(_gs.location_of(out_carbon) == "carbon_spot", "skip leaves the carbon of the sent sheet on the carbon spot, not filed")
	_check(_gs.location_of(out_sid) == "removed", "skip takes the sent sheet out of the world")
	_check(DocModel.typed_text(_gs.docs[out_sid].pages[0]).begins_with("HELLO"), "skip sends the sheet with its typed text as it is")
	_check(float(_gs.accuracy.get("T-1", 1.0)) < 0.5, "skip adds no text: T-1 scores on the text typed, not on the source (%.3f)" % float(_gs.accuracy.get("T-1", 1.0)))
	_check(_gs.last_task_done == "T-1", "skip completes T-1")
	_check(_first("skip") == "skip: no task is active", "skip with no active task sends nothing")

	# With no sheet of the task out, skip takes one sheet and carbon set from the tray and sends it blank.
	_first("day 2")
	_dd.tick(10.0)
	_dd.tick(5.0)
	_check(_dd.active_task == "T-2", "day 2: T-2 is the active task after the morning")
	var tray_before := int(_gs.tray_count)
	var blank := _first("skip")
	var blank_id := blank.get_slice(" ", 2)
	_check(blank.begins_with("skip: sent SHEET-") and blank.contains("(a blank sheet from the tray) for T-2"), "skip with no sheet out takes a blank sheet from the tray and sends it")
	_check(int(_gs.tray_count) == tray_before - 1, "the blank sheet comes from the tray")
	_check(float(_gs.accuracy.get("T-2", 1.0)) == 0.0, "the blank sheet scores 0: skip types nothing")
	_check(DocModel.typed_text(_gs.docs[blank_id].pages[0]) == "", "the sent blank sheet has no text")
	_check(_gs.location_of(String(_gs.docs[blank_id].twin)) == "carbon_spot", "the carbon of the blank sheet is on the carbon spot, not filed")
	_check(_gs.last_task_done == "T-2", "skip completes T-2")

	# --- ending A|B|C ---
	_check(_first("ending C").begins_with("ending C is unavailable"), "ending C is refused while carbons_kept_at_final is below 3")
	_check(_first("ending Q").begins_with("usage"), "ending with an unknown letter prints the usage line")
	_check(_first("ending B").begins_with("ending B: refusal started"), "ending B starts the refusal")
	_check(bool(_main.endings.refused), "ending B sets the refused flag on the endings controller")
	_check(_first("ending A").begins_with("ending A"), "ending A starts")
	_check(bool(_main.endings.ro5_sent), "ending A sets the RO-5 flag")
	_check(_first("set carbons_kept_at_final 3").begins_with("set carbons_kept_at_final = 3"), "set carbons_kept_at_final 3")
	_check(_first("ending C").begins_with("ending C: started"), "ending C starts from the carbon stack once there are three carbons")
	_check(bool(_main.endings.ending_running()), "ending C leaves an ending running")

	# --- set <var> <value> ---
	_check(_first("set flags.test_key true") == "set flags.test_key = true", "set flags.test_key true sets a dotted flag")
	_check(bool(_gs.flags.get("test_key", false)), "the dotted flag holds true")
	_check(_first("set player_name_raw ANNA MARIA") == "set player_name_raw = ANNA MARIA", "set keeps the spaces of a text value")
	_check(_gs.player_name_raw == "ANNA MARIA", "the text value is stored as typed")
	_check(_first("set accuracy.T-9 0.5") == "set accuracy.T-9 = 0.5", "set accepts a dotted dictionary key with a hyphen")
	_check(is_equal_approx(float(_gs.accuracy["T-9"]), 0.5), "the float value is stored")
	_check(_first("set nothere 1") == "unknown variable: nothere", "set refuses an unknown variable")
	_check(_first("set flags").begins_with("usage"), "set without a value prints the usage line")

	# --- gaze, changes, audio_check, tris ---
	_check(_first("gaze") == "gaze overlay on", "gaze toggles the overlay on")
	_check(_first("gaze") == "gaze overlay off", "gaze toggles the overlay off")
	var changes := _all("changes").split("\n")
	_check(changes.size() == 3 and changes[0].begins_with("pending: ") and changes[1].begins_with("applied: "), "changes lists pending and applied ids")
	_check(_first("audio_check").begins_with("loudness logger off"), "audio_check turns the Rule A/B logger off (it starts on in debug builds)")
	_check(_first("audio_check").begins_with("loudness logger on"), "audio_check turns the logger back on")
	var tris_line := _first("tris")
	var tris := int(tris_line.get_slice(": ", 1).get_slice(" ", 0)) if tris_line.begins_with("visible triangles: ") else -1
	_check(tris > 0 and tris <= 20000, "tris prints the visible triangle count within the 20000 budget (%s)" % tris_line)

	# --- The console: F9 toggles, the tree pauses while it is open, lines run ---
	var con = DebugConsole.new()
	con.main = _main
	root.add_child(con)
	_check(not con.is_open(), "the console starts closed")
	var ev := InputEventKey.new()
	ev.keycode = KEY_F9
	ev.pressed = true
	con._input(ev)
	_check(con.is_open(), "F9 opens the console")
	_check(root.get_tree().paused, "the tree is paused while the console is open")
	var ran := con.run_line("day 2")
	_check(ran.size() == 1 and ran[0].begins_with("day 2"), "the console runs a typed line and returns its result")
	_check(con.run_line("nope")[0] == "unknown command", "the console prints 'unknown command'")
	con._input(ev)
	_check(not con.is_open(), "F9 closes the console")
	_check(not root.get_tree().paused, "the tree is unpaused when the console closes")

	print("ACCEPTANCE DEBUG CONSOLE: %d checks, %d failure(s)" % [_checks, _failures])
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
