extends SceneTree
## Acceptance test 11 (spec 20): the playthrough part of the no-startle audit. A scripted compliant run goes
## through all five days by the game's own flow:
##   - DayDirector runs the days: the timeline, the canisters, the batches and orders, the carbons, the lamp
##     and the overnight resolution (start_next_day).
##   - TypewriterModel takes every key of every sheet, and TypewriterSounds maps its events to AudioDirector
##     as TypewriterView does (typing, the platen, returns, ghost typing, paper in and out).
##   - The other sounds the game plays are sent to AudioDirector with the gains and player-caused flags of
##     their scripts: stamps, the carbon stack, the tube, the lamp, the clerks' typing, the clock, the beds
##     and the vent.
## The loudness checker is on in this debug build, so every playback is judged against spec 11.1 Rules A and B.
## The test passes when the checker judged playbacks and found zero violations. Exempt playbacks (the documented
## exceptions in LoudnessChecker.EXEMPTIONS, such as tube_thunk) are counted and printed, not failures.
## Not covered here: Ending A and the other endings' sequences (scripts/endings), whose sounds are scripted with
## their own timers; they are recorded as not covered in tests/ACCEPTANCE.md.
## Headless:
##   godot --headless --path . --script res://tests/acceptance/test_full_loudness.gd
## Prints one PASS or FAIL line per check, then the summary. Exit 0 only when every check passes.

const DocModel := preload("res://scripts/logic/doc_model.gd")
const CadenceModel := preload("res://scripts/logic/cadence_model.gd")
const TypewriterModel := preload("res://scripts/logic/typewriter_model.gd")
const Redaction := preload("res://scripts/logic/redaction.gd")
const Content := preload("res://scripts/logic/content.gd")
const TypewriterSounds := preload("res://scripts/typewriter/typewriter_sounds.gd")
const ClerkBehaviour := preload("res://scripts/world/clerk_behaviour.gd")
const ClockBehaviour := preload("res://scripts/world/clock_behaviour.gd")
const LampView := preload("res://scripts/desk/lamp.gd")

const KEY_STEP_MS := 150.0  # virtual time between typed keys, as in the compliant run
const GHOST_STEP_MS := 100.0
const MAX_GHOST_STEPS := 20000
const WAIT_STEP_S := 1.0  # DayDirector seconds per step while the day runs
const CLERK_RETURN_EVERY_S := 15
const LAMP_WAIT_S := 2
const CLOCK_POS := Vector3(5.25, 2.2, 0.5)
const CLERK_POS := Vector3(3.0, 0.9, 2.0)
const TUBE_POS := Vector3(5.25, 2.4, 3.0)
const LAMP_POS := Vector3(4.6, 1.9, 1.0)

var _failures := 0
var _checks := 0
var _ran := false
var _gs
var _dd
var _ad
var _tt
var _tw: TypewriterModel
var _sounds: TypewriterSounds
var _now := 0.0
var _seconds := 0
var _arrivals := 0
var _ro5_fired := false
var _ro5_desk4 := false


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


# --- Typing, through the typewriter model and its sound mapping ----------------------------

## Plays the model's pending events as the typewriter view does each frame.
func _flush_typing() -> void:
	var events: Array = _tw.take_events()
	_sounds.play_events(events, _now, _tw.ghost_pending())
	_sounds.tick(_now)


func _advance_typing(ms: float) -> void:
	_now += ms
	_tw.tick(_now)
	_flush_typing()


## Types text into the loaded sheet, breaking lines at word boundaries (spec 6.5).
func _type(text: String) -> void:
	var lines := DocModel.wrap_text(text, DocModel.COLS)
	for li in range(lines.size()):
		if li > 0:
			_tw.enter(_now)
			_advance_typing(KEY_STEP_MS)
		for ch in String(lines[li]):
			_tw.type_key(ch, _now)
			_advance_typing(KEY_STEP_MS)


## Loads a document into the typewriter: GameState places it, the model loads it, and the paper goes in.
func _load(doc_id: String, carbon_id: String) -> void:
	_gs.place(doc_id, "typewriter")
	_tw.retired_active = int(_gs.day) >= 3
	_tw.fond_word = String(_gs.fond_word)
	_tw.load_sheet(_gs.docs[doc_id], _gs.docs[carbon_id] if carbon_id != "" else {})
	_sounds.play("paper_in", _sounds.position, 0.0, true)
	_flush_typing()


## Removes the paper as spec 7.7 does: the original goes to the hand, and its carbon to the carbon spot.
func _release(doc_id: String) -> void:
	_tw.unload()
	_flush_typing()
	_sounds.play("paper_out", _sounds.position, 0.0, true)
	_dd.paper_removed(doc_id)
	_gs.place(doc_id, "hand")


func _form(doc_id: String, answers: Dictionary) -> void:
	_load(doc_id, "")
	var form: Dictionary = _gs.docs[doc_id]
	for fid in ["F1", "F2", "F3", "F4", "F5"]:
		if not answers.has(fid):
			continue
		var field := DocModel.field_by_id(form.pages[0], fid)
		_tw.click_cell(int(field.line), int(field.col), _now)
		_flush_typing()
		_type(String(answers[fid]))
	_release(doc_id)
	_send(doc_id)


func _transcription(source_doc: String, skip_first: bool) -> String:
	var sid: String = _dd.take_blank_sheet()
	_load(sid, String(_gs.docs[sid].twin))
	# The typewriter has no em dash key (spec 7.2): a player types a hyphen instead.
	_type(String(_dd._source_text(source_doc, skip_first)).replace("—", "-"))
	_release(sid)
	_send(sid)
	return sid


## Ghost typing (spec 10.2, 11.1): the day's ghost lines are typed on a free sheet in the typewriter, with the
## ghost gain on each key, return and bell. Each finished line is reported to DayDirector as the ghost typer does.
func _ghost_typing(day: int) -> void:
	var sid: String = _dd.take_blank_sheet()
	_load(sid, "")
	var lines: Array = Content.load_json("res://data/strings.json").get("ghost_lines", {}).get(str(day), [])
	for index in range(lines.size()):
		_tw.enqueue_ghost_text(String(_tt.substitute(String(lines[index]))) + "\n")
		_tw.ghost_set_running(true, _now)
		var steps := 0
		while _tw.ghost_pending() and steps < MAX_GHOST_STEPS:
			_now += GHOST_STEP_MS
			_tw.tick(_now)
			_flush_typing()
			steps += 1
		_tw.ghost_set_running(false, _now)
		_gs.ghost_lines_done[str(day)] = index + 1
		_dd.ghost_line_finished(day, index)
	_tw.unload()
	_flush_typing()
	_gs.remove_doc(sid)


# --- Other sounds of the game ------------------------------------------------------------------

## A document leaves by tube (spec 8.4): the player's send click, and the departing canister.
func _send(doc_id: String) -> void:
	_sounds.play("tube_send", _sounds.position, 0.0, true)
	_sounds.play_tube_leave(_sounds.position)
	_dd.send_document(doc_id)


func _batch(batch_id: String, results: Array) -> void:
	for i in range(results.size()):
		_dd.stamp_document(batch_id, i, String(results[i]), 300.0, 400.0, 0.0, 0.9)
		_ad.play("stamp_thud", _sounds.position, true, 0.0, true)
	_send(batch_id)


func _order(order_id: String, names: Array, stamp: String) -> void:
	var page: Dictionary = _gs.docs[order_id].pages[0]
	for name in names:
		var ext := Redaction.name_extent(page, String(name))
		if ext.is_empty():
			_check(false, "order %s: name %s is printed" % [order_id, name])
			continue
		DocModel.add_bar(page, int(ext[0]), float(ext[1]), float(ext[2]))
	_dd.stamp_document(order_id, 0, stamp, 300.0, 400.0, 0.0, 0.9)
	_ad.play("stamp_thud", _sounds.position, true, 0.0, true)
	_send(order_id)


## The carbons go to the drawer (spec 8.5): a player click, so the stack's sound is player-caused.
func _file_carbons() -> void:
	if _dd.file_carbons() > 0:
		_ad.play("paper_shuffle", _sounds.position, true, 0.0, true)


## The lamp (spec 13.5), then the overnight step and the next day (spec 13.1).
func _lamp_and_night() -> void:
	_file_carbons()
	_dd.click_lamp()
	_ad.play("lamp_click", LAMP_POS, false, LampView.CLICK_GAIN_DB, true)
	_wait(LAMP_WAIT_S)
	_dd.start_next_day()


## Runs the day for the given number of DayDirector seconds, one step at a time. Each step the wall clock ticks
## (clock_tick) and the clerks type (key_clack, and a carriage return now and then), as the room does.
func _wait(seconds: float) -> void:
	var steps := int(round(seconds / WAIT_STEP_S))
	for i in range(steps):
		_dd.tick(WAIT_STEP_S)
		_seconds += 1
		_ad.play("clock_tick", CLOCK_POS, true, ClockBehaviour.TICK_DB, false)
		_ad.play("key_clack", CLERK_POS, true, ClerkBehaviour.KEY_DB, false)
		if _seconds % CLERK_RETURN_EVERY_S == 0:
			_ad.play("carriage_return", CLERK_POS, true, ClerkBehaviour.CR_DB, false)


# --- Signals from DayDirector ----------------------------------------------------------------

func _on_day_started(day: int) -> void:
	_ad.set_hum_pitch(day)
	_ad.set_fixtures_lit(_lit_fixtures())
	_ad.set_vent_active(day >= 4)


## A canister arrives by tube (spec 8.4): the whoosh, then the thunk, which is always preceded by the whoosh.
func _on_canister_arrived(ids: Array) -> void:
	if ids.is_empty():
		return
	_arrivals += 1
	_ad.play("tube_arrive_whoosh", TUBE_POS, true, 0.0, false)
	_ad.play("tube_thunk", TUBE_POS, true, 0.0, false)


func _lit_fixtures() -> int:
	var lit := 0
	for f in _gs.fixture_lit.keys():
		if bool(_gs.fixture_lit[f]):
			lit += 1
	return lit


# --- The playthrough ---------------------------------------------------------------------------

func _run() -> void:
	_gs = root.get_node("GameState")
	_dd = root.get_node("DayDirector")
	_ad = root.get_node("AudioDirector")
	_tt = root.get_node("TextTokens")
	_tw = TypewriterModel.new(CadenceModel.new(), _gs.rng)
	_sounds = TypewriterSounds.new()
	_dd.day_started.connect(_on_day_started)
	_dd.canister_arrived.connect(_on_canister_arrived)
	_dd.ro5_sent.connect(func(desk4: bool): _ro5_fired = true; _ro5_desk4 = desk4)

	_check(OS.is_debug_build(), "this run is a debug build, so the loudness checker is on")
	_ad.set_checker_enabled(true)
	var playbacks_at_start := int(_ad.get_checker_playbacks())
	_ad.start_bed("room_tone")
	_ad.start_bed("hum")

	# --- Day 1 ----------------------------------------------------------------
	_dd.start_new_game(412)
	_wait(10)
	_wait(5)
	_form("P-1", {"F1": "ANNA MARIA TESTER", "F2": "JOHN TESTER", "F3": "LANTERN", "F4": "NO", "F5": "ANNA MARIA TESTER"})
	_wait(5)
	_transcription("L-1", false)
	_check(float(_gs.accuracy.get("T-1", 0.0)) >= 0.999, "day 1: transcription T-1 is typed accurately")
	_wait(5)
	_batch("S-1", ["APPROVED", "DENIED", "APPROVED", "DENIED", "APPROVED"])
	_wait(5)
	_check(_gs.end_of_shift_arrived, "day 1: End of Shift arrives")
	_lamp_and_night()
	_check_eq(_gs.day, 2, "day 1 ends and day 2 begins")

	# --- Day 2 ----------------------------------------------------------------
	_wait(10)
	_wait(5)
	_transcription("C-22", true)
	var t2 := float(_gs.accuracy.get("T-2", 0.0))
	# The C-22 source keeps its em dash, which the typewriter cannot type (QUESTION-10): ACCEPTABLE, not 1.0.
	_check(t2 >= 0.98, "day 2: transcription T-2 is ACCEPTABLE (accuracy %.3f)" % t2)
	_wait(5)
	_order("RO-2", ["DOBRA, KASIMIR", "FELL, ODETTE", "MORAVEC, AUREL", "MORAVEC, ILSE"], "PROCESSED")
	_wait(5)
	_batch("S-2", ["DENIED", "APPROVED", "DENIED", "DENIED"])
	_wait(5)
	_check(_gs.end_of_shift_arrived, "day 2: End of Shift arrives")
	_lamp_and_night()
	_check_eq(_gs.day, 3, "day 2 ends and day 3 begins")

	# --- Day 3 ----------------------------------------------------------------
	_wait(10)
	_wait(5)
	_transcription("ST-3", false)
	_check(float(_gs.accuracy.get("T-3", 0.0)) >= 0.999, "day 3: transcription T-3 is typed accurately")
	_wait(5)
	_order("RO-3", ["J. ABEL", "N. FERRAND", "H. VANCE"], "PROCESSED")
	_file_carbons()
	_wait(5)
	_form("F-3", {"F1": "12", "F2": "NO", "F3": "NO", "F4": "ANNA MARIA TESTER"})
	_wait(5)
	_ghost_typing(3)
	_wait(125)
	_check(_gs.end_of_shift_arrived, "day 3: End of Shift arrives")
	_lamp_and_night()
	_check_eq(_gs.day, 4, "day 3 ends and day 4 begins")

	# --- Day 4 ----------------------------------------------------------------
	_wait(10)
	_wait(5)
	_transcription("L-4", false)
	_check(float(_gs.accuracy.get("T-4", 0.0)) >= 0.999, "day 4: transcription T-4 is typed accurately")
	_wait(5)
	_order("RO-4", ["JOHN TESTER", "HALVORSEN, PETRA", "WEISS, CORA"], "PROCESSED")
	_wait(5)
	_batch("S-4", ["APPROVED", "DENIED", "DENIED"])
	_ghost_typing(4)
	_wait(125)
	_check(_gs.end_of_shift_arrived, "day 4: End of Shift arrives")
	_lamp_and_night()
	_check_eq(_gs.day, 5, "day 4 ends and day 5 begins")

	# --- Day 5 ----------------------------------------------------------------
	_wait(10)
	_wait(5)
	_form("P-1D", {"F1": "ANNA MARIA TESTER", "F2": "JOHN TESTER", "F3": "LANTERN", "F4": "NO", "F5": "ANNA MARIA TESTER"})
	_wait(5)
	_order("RO-5", ["ANNA MARIA TESTER"], "PROCESSED")
	_wait(5)
	_check(_ro5_fired, "day 5: RO-5 is sent")
	_check(_ro5_desk4, "day 5: the Desk 4 entry is redacted, which leads to Ending A")

	# --- The checker's verdict -----------------------------------------------------
	var playbacks := int(_ad.get_checker_playbacks()) - playbacks_at_start
	var violations := int(_ad.get_checker_violations())
	var exempt := int(_ad.get_checker_exempt_playbacks())
	_check(playbacks > 0, "the checker judged the playbacks of the run (%d)" % playbacks)
	_check(_arrivals > 0, "canisters arrived by tube during the run (%d)" % _arrivals)
	_check(violations == 0, "zero Rule A and B violations over the playthrough (%d playbacks, %d exempt)" % [playbacks, exempt])
	print("FULL LOUDNESS: %d playbacks, %d violation(s), %d exempt, %d day seconds" % [playbacks, violations, exempt, _seconds])
	print("FULL LOUDNESS: %d checks, %d failure(s)" % [_checks, _failures])
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
