extends SceneTree
## Checks for spec 20 tests that no other headless file reaches: test 7 (the Day 5 name substitution
## on P-1D, the logic part) and test 12 (continue restarts the day from its beginning, with the
## day's earlier results intact). Headless:
##   godot --headless --path . --script res://tests/acceptance/test_spec_extras.gd
## Exit 0 means every check passed. The save check writes user://save.json and deletes it after.

const DebugDays := preload("res://scripts/debug/debug_day_defaults.gd")

var _failures := 0
var _checks := 0
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
	var save = root.get_node("SaveSystem")

	# --- Test 7: Day 5 substitution on P-1D (spec 14.12) ---
	dd.start_new_game(412)
	gs.day = 5
	gs.redacted_names = ["vance"]
	var opts: Dictionary = dd.sheet_options("P-1D")
	_check(String(opts.get("field_substitution", {}).get("F1", "")) == "H. VANCE", "test 7: the P-1D original shows H. VANCE in field 1")
	_check(bool(opts.get("field_bar", {}).get("F1", false)), "test 7: field 1 is barred when H. VANCE was redacted")
	gs.redacted_names = []
	opts = dd.sheet_options("P-1D")
	_check(not bool(opts.get("field_bar", {}).get("F1", true)), "test 7: field 1 is not barred when H. VANCE was not redacted")
	_check(dd.sheet_options("P-1").is_empty(), "test 7: no substitution on P-1 or on any other day")

	# --- Test 12: save, quit, continue (spec 16.4, 20 test 12) ---
	save.delete_save()
	DebugDays.prepare(gs, dd, 3)
	dd.tick(50.0)
	var ro_before: Dictionary = gs.ro_results.duplicate(true)
	_check(bool(save.save_game()), "test 12: the game saves mid Day 3")
	gs.new_game(1)
	_check(not gs.ro_results.has("RO-2"), "test 12: a new game clears the results (the quit)")
	_check(bool(save.has_save()) and int(save.saved_day()) == 3, "test 12: the save holds Day 3")
	_check(bool(save.load_game()), "test 12: the save loads")
	_check(int(gs.day) == 3, "test 12: the loaded game is on Day 3")
	dd.begin_day(int(gs.day))
	_check(is_equal_approx(float(dd.now), 0.0) and dd.active_task == "", "test 12: continue restarts Day 3 at its beginning")
	_check(dd.pending_events() == 2, "test 12: the day's bell and morning canister are scheduled again")
	_check(gs.ro_results == ro_before, "test 12: Day 2 results (RO-2) are intact after continue")
	save.delete_save()

	print("ACCEPTANCE SPEC EXTRAS: %d checks, %d failure(s)" % [_checks, _failures])
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
