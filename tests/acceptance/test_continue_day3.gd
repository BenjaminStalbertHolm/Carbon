extends SceneTree
## Acceptance test 12 (spec 20): save in the middle of Day 3, quit, continue from the save. The test plays the
## real save and continue path of the logic layer: SaveSystem.save_game(), a new game (the quit), SaveSystem.load_game(),
## and DayDirector.begin_day(day) as the continue does (main.gd _on_continue). Then it checks that the day, the
## inbox, the read stack and the carbons are the same as they were at the save, and that Day 3 restarts from its
## beginning. The save goes to a scratch file, not to the player's save slot. Headless:
##   godot --headless --path . --script res://tests/acceptance/test_continue_day3.gd
## Prints one PASS or FAIL line per check, then the summary. Exit 0 only when every check passes.
## Not covered here: the title screen's CONTINUE button and the fades on a real window (spec 20 test 12, MANUAL).

const DocModel := preload("res://scripts/logic/doc_model.gd")
const CadenceModel := preload("res://scripts/logic/cadence_model.gd")
const TypewriterModel := preload("res://scripts/logic/typewriter_model.gd")
const DebugDays := preload("res://scripts/debug/debug_day_defaults.gd")

const SCRATCH_SAVE := "user://acceptance_continue_day3.json"
const DEFAULT_SAVE := "user://save.json"
const MID_DAY_S := 50.0  # DayDirector seconds into Day 3: the morning has come and the first task is active
const TYPED_TEXT := "TRANSCRIBED BEFORE SAVE"
const KEY_STEP_MS := 150.0

var _failures := 0
var _checks := 0
var _ran := false
var _gs
var _dd
var _save
var _tw: TypewriterModel
var _now := 0.0


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


func _check_eq(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
	if actual != expected:
		print("      expected: %s" % str(expected))
		print("      actual:   %s" % str(actual))


## Types text into the loaded sheet through the typewriter model, one key at a time.
func _type(text: String) -> void:
	for ch in text:
		_tw.type_key(ch, _now)
		_now += KEY_STEP_MS
		_tw.tick(_now)
		_tw.take_events()


## DayDirector.tick() moves the clock by the whole delta before it runs the events due, so a large step would
## schedule the events that follow relative to the end of the step. The day is run in one-second steps instead.
func _run_day(seconds: float) -> void:
	for i in range(int(round(seconds))):
		_dd.tick(1.0)


## What the player can see of the desk: the day, where every paper is, and what is typed on the papers on the
## read stack and in the inbox (the carbons have their own locations).
func _snapshot() -> Dictionary:
	var loc: Dictionary = _gs.loc
	var carbons := {}
	var read_text := {}
	for id in _gs.docs.keys():
		var doc: Dictionary = _gs.docs[id]
		if bool(doc.get("carbon", false)):
			carbons[String(id)] = _gs.location_of(String(id))
	for id in loc.read_stack:
		var doc: Dictionary = _gs.docs.get(String(id), {})
		if not doc.is_empty() and not doc.get("pages", []).is_empty():
			read_text[String(id)] = DocModel.typed_text(doc.pages[0])
	return {
		"day": int(_gs.day),
		"inbox": loc.inbox.duplicate(),
		"read_stack": loc.read_stack.duplicate(),
		"carbon_spot": loc.carbon_spot.duplicate(),
		"drawer": loc.drawer.duplicate(),
		"hand": String(loc.hand),
		"typewriter": String(loc.typewriter),
		"carbons": carbons,
		"read_text": read_text,
	}


func _run() -> void:
	_gs = root.get_node("GameState")
	_dd = root.get_node("DayDirector")
	_save = root.get_node("SaveSystem")
	_tw = TypewriterModel.new(CadenceModel.new(), _gs.rng)
	_save.save_path = SCRATCH_SAVE
	_save.delete_save()

	# --- Mid Day 3: the day's defaults for Days 1 and 2, then the morning and the first task ---
	DebugDays.prepare(_gs, _dd, 3)
	_run_day(MID_DAY_S)
	_check(int(_gs.day) == 3, "the game is on Day 3")
	_check_eq(_dd.active_task, "T-3", "mid Day 3: the first task T-3 is active")
	_check(String(_gs.location_of("M3")) == "inbox", "mid Day 3: the morning memo M3 is in the inbox")

	# The first sheet of T-3 is typed, taken off the typewriter (spec 7.7), and put on the read stack. Its carbon
	# goes to the carbon spot (spec 8.5): kept, not filed.
	var sid1: String = _dd.take_blank_sheet()
	var carbon1 := String(_gs.docs[sid1].twin)
	_gs.place(sid1, "typewriter")
	_tw.retired_active = true
	_tw.fond_word = String(_gs.fond_word)
	_tw.load_sheet(_gs.docs[sid1], _gs.docs[carbon1])
	_type(TYPED_TEXT)
	_tw.unload()
	_dd.paper_removed(sid1)
	_gs.place(sid1, "read_stack")
	# A second sheet of T-3 is in hand, and its carbon is picked up and put on the read stack.
	var sid2: String = _dd.take_blank_sheet()
	var carbon2 := String(_gs.docs[sid2].twin)
	_gs.place(carbon2, "read_stack")
	_check(String(_gs.location_of(carbon1)) == "carbon_spot", "mid Day 3: the carbon of the first sheet is on the carbon spot")
	_check(String(_gs.location_of(sid1)) == "read_stack", "mid Day 3: the first sheet is on the read stack")
	_check(String(_gs.location_of(carbon2)) == "read_stack", "mid Day 3: the second carbon is on the read stack")

	# --- Save in the middle of Day 3 ---
	var before := _snapshot()
	_check(bool(_save.save_game()), "the game saves in the middle of Day 3")
	_check(_save.has_save() and int(_save.saved_day()) == 3, "the save holds Day 3")
	_check(before.read_stack.size() == 2 and before.carbon_spot.size() == 1, "the saved desk has two papers on the read stack and one carbon on the carbon spot")
	_check(bool(before.read_text.get(sid1, "").begins_with(TYPED_TEXT)), "the saved read stack sheet has its typed text")

	# --- Quit, then continue from the save ---
	_gs.new_game(1)
	_check(int(_gs.day) == 1 and _gs.loc.read_stack.is_empty() and _gs.docs.is_empty(), "the quit clears the desk (a new game)")
	_check(bool(_save.load_game()), "the save loads")
	_dd.begin_day(int(_gs.day))
	var after := _snapshot()
	_check_eq(after.day, before.day, "continue: the day is the same as at the save")
	_check_eq(after.inbox, before.inbox, "continue: the inbox is the same as at the save")
	_check_eq(after.read_stack, before.read_stack, "continue: the read stack is the same as at the save")
	_check_eq(after.read_text, before.read_text, "continue: the typed text on the read stack is the same")
	_check_eq(after.carbons, before.carbons, "continue: the carbons and their places are the same")
	_check_eq(after.carbon_spot, before.carbon_spot, "continue: the carbon spot is the same")
	_check_eq(after.drawer, before.drawer, "continue: the drawer is the same")
	_check_eq(after.hand, before.hand, "continue: the paper in hand is the same")
	_check_eq(after.typewriter, before.typewriter, "continue: the typewriter is the same (empty)")

	# Day 3 restarts from its beginning: time is back at 0, no task is active, and the bell and the morning are due.
	_check(is_equal_approx(float(_dd.now), 0.0) and _dd.active_task == "", "continue restarts Day 3 at its beginning")
	_check(_dd.pending_events() == 2, "continue schedules the day's bell and morning canister again")

	# The restarted day runs its morning; the papers the player kept are still where they were.
	_run_day(10.0)
	_check(int(_gs.day) == 3, "the restarted Day 3 is still Day 3 after its morning")
	_check(String(_gs.location_of("M3")) == "inbox", "the restarted morning brings the memo M3 to the inbox")
	var later := _snapshot()
	_check_eq(later.read_stack, before.read_stack, "the restarted morning leaves the read stack as it was")
	_check_eq(later.carbons, before.carbons, "the restarted morning leaves the carbons where they were")

	_save.delete_save()
	_save.save_path = DEFAULT_SAVE
	print("CONTINUE DAY 3: %d checks, %d failure(s)" % [_checks, _failures])
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
