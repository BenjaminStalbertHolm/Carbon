extends SceneTree
## Headless logic playthrough of Day 1 and the Day 2 morning (acceptance test 1,
## part). Drives DayDirector and GameState through the real content in data/.
##   godot --headless --path . --script res://tests/unit/test_playthrough_day1.gd

const DocModel := preload("res://scripts/logic/doc_model.gd")
const CadenceModel := preload("res://scripts/logic/cadence_model.gd")
const TypewriterModel := preload("res://scripts/logic/typewriter_model.gd")

var _failures := 0
var _ran := false
var _gs: Node
var _dd: Node
var _tw: TypewriterModel
var _now := 0.0


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _check_eq(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
	if actual != expected:
		print("      expected: %s" % str(expected))
		print("      actual:   %s" % str(actual))


## Types text into the loaded sheet. Lines break at word boundaries within 64
## columns, as a player would type them. Newlines in the text are Enter.
func _type(text: String) -> void:
	var lines := DocModel.wrap_text(text, DocModel.COLS)
	for li in range(lines.size()):
		if li > 0:
			_tw.enter(_now)
			_now += 150.0
		for ch in String(lines[li]):
			_tw.type_key(ch, _now)
			_now += 150.0
			_tw.tick(_now)



## Memo lines longer than 64 columns wrap onto two printed lines (spec 6.5), so a
## check looks for the wording in the joined text as well as in single lines.
func _has_text(lines: Array, expected: String) -> bool:
	if lines.has(expected):
		return true
	return " ".join(PackedStringArray(lines)).contains(expected)


func _run() -> void:
	_gs = get_root().get_node("GameState")
	_dd = get_root().get_node("DayDirector")
	_tw = TypewriterModel.new(CadenceModel.new(), _gs.rng)

	_dd.start_new_game(412)
	_check_eq(_gs.day, 1, "new game starts on Day 1")

	_dd.tick(4.0)
	_check_eq(_gs.clock_time, "09:00", "start bell moves the clock to 09:00")
	_dd.tick(6.0)
	_check(_gs.location_of("M1-WELCOME") == "inbox", "Day 1 morning canister delivers the welcome memo")
	_dd.tick(5.0)
	_check(_gs.location_of("P-1") == "inbox", "first task canister (Form P-1) arrives 5 s after the morning")
	_check_eq(_dd.active_task, "P-1", "Form P-1 is the active task")

	# Form P-1. Answers chosen so the signature matches and Q4 is NO.
	var form: Dictionary = _gs.docs["P-1"]
	_gs.place("P-1", "typewriter")
	_tw.load_sheet(form, {})
	var answers := {"F1": "ANNA MARIA TESTER", "F2": "JOHN TESTER", "F3": "LANTERN", "F4": "NO", "F5": "ANNA MARIA TESTER"}
	for fid in ["F1", "F2", "F3", "F4", "F5"]:
		var field := DocModel.field_by_id(form.pages[0], fid)
		_tw.click_cell(int(field.line), int(field.col), _now)
		_type(String(answers[fid]))
	_check_eq(DocModel.field_values(form.pages[0]).F1, "ANNA MARIA TESTER", "field F1 holds the typed name")
	_check_eq(DocModel.field_values(form.pages[0]).F3, "LANTERN", "field F3 holds the fond word")
	_tw.unload()
	_gs.place("P-1", "hand")
	_dd.send_document("P-1")
	_check(_gs.tokens_set, "sending Form P-1 sets the tokens")
	_check_eq(_gs.player_name_raw, "ANNA MARIA TESTER", "player name is stored from F1")
	_check_eq(_gs.fond_word, "LANTERN", "fond word is stored from F3")
	_check_eq(_gs.p1_q4, "NO", "question 4 answered NO is classified NO")
	_check(_gs.signature_matches, "signature matches the name")
	_check_eq(_gs.nameplate["4"], "ANNA MARIA TES", "desk 4 nameplate becomes the name truncated to 14 characters")
	_check_eq(_gs.clock_time, "11:40", "clock advances to 11:40 after task 1 of 3")

	# Transcription T-1 (spec 14.5, Task 2).
	_dd.tick(5.0)
	_check(_gs.location_of("L-1") == "inbox", "T-1 canister (cover and letter L-1) arrives")
	var sheet_id: String = _dd.take_blank_sheet()
	_check_eq(sheet_id, "SHEET-1", "blank tray gives a sheet and carbon set for a transcription task")
	var sheet: Dictionary = _gs.docs[sheet_id]
	var carbon_id: String = sheet.twin
	_gs.place(sheet_id, "typewriter")
	_tw.load_sheet(sheet, _gs.docs[carbon_id])
	var source: String = _dd._source_text("L-1", false)
	_type(source)
	_tw.unload()
	_dd.paper_removed(sheet_id)
	_check(_gs.location_of(carbon_id) == "carbon_spot", "removing the sheet puts its carbon on the carbon spot")
	_gs.place(sheet_id, "hand")
	_dd.send_document(sheet_id)
	_check(_gs.accuracy.has("T-1"), "sending the T-1 original records an accuracy")
	_check(float(_gs.accuracy.get("T-1", 0.0)) >= 0.999, "a faithful copy scores 1.0 (got %s)" % str(_gs.accuracy.get("T-1")))
	_check(_gs.location_of(sheet_id) == "removed", "the T-1 original waits in the removed store for its return")

	# Batch S-1 (spec 14.5, Task 3): stamp every page correctly.
	_dd.tick(5.0)
	_check(_gs.location_of("S-1") == "inbox", "S-1 batch arrives")
	var stamps := ["APPROVED", "DENIED", "APPROVED", "DENIED", "APPROVED"]
	for i in range(stamps.size()):
		_check(_dd.stamp_document("S-1", i, stamps[i], 300.0, 400.0, 0.0, 0.9), "stamp applied to batch page %d" % (i + 1))
	_dd.send_document("S-1")
	_check_eq(_gs.stamp_results["S-1"], stamps, "batch results are recorded per page")
	_check_eq(_gs.contradictory_stamps, 0, "no contradictory stamps on the batch")
	_check_eq(_gs.clock_time, "17:00", "clock advances to 17:00 after the last task")

	# End of shift and lamp (spec 13.4, 13.5).
	_dd.tick(5.0)
	_check(_gs.end_of_shift_arrived, "End of Shift memo arrives 5 s after the last task")
	_check_eq(_gs.clock_time, "16:58", "clock moves to 16:58 when End of Shift arrives")

	# Carbons must be filed before the night (spec 8.5 and 14.7).
	_gs.place(String(_gs.loc.carbon_spot[0]), "drawer") if not _gs.loc.carbon_spot.is_empty() else null
	_dd.click_lamp()
	_check(_dd.pending_events() > 0, "lamp after End of Shift schedules the day end")
	_dd.tick(1.5)
	_check_eq(_gs.lamp_on, false, "lamp switches off after End of Shift")

	_dd.start_next_day()
	_check_eq(_gs.day, 2, "Day 2 begins")
	_check(not _gs.carbons_unfiled_flag, "filed carbons do not set the unfiled flag")
	_check(_gs.docs.has(carbon_id) == false, "the lower drawer is emptied overnight")
	_dd.tick(10.0)
	_check(_gs.location_of("M2") == "inbox", "Day 2 morning memo M2 arrives")
	var memo: Dictionary = _gs.docs["M2"]
	var lines: Array = []
	for entry in memo.pages[0].printed:
		lines.append(String(entry.text))
	_check(_has_text(lines, "TRANSCRIPTION T-1: ACCEPTABLE."), "M2 carries the T-1 ACCEPTABLE line")
	_check(_has_text(lines, "BATCH S-1: CORRECT."), "M2 carries the S-1 CORRECT line")
	_check(_has_text(lines, "APPLICATION MORAVEC, A. WAS DATED TOMORROW. THIS HAS BEEN OVERLOOKED."), "M2 carries the dated-tomorrow line for an approved page 3")
	_check(_has_text(lines, "ACCURACY IS CONTINUITY."), "M2 ends with the closing line")
	_check(_gs.location_of("SHEET-1") == "inbox", "the returned T-1 original arrives on Day 2")
	var returned: Dictionary = _gs.docs["SHEET-1"]
	_check(returned.pages[0].inserts.size() > 0, "the returned T-1 original carries the Management corrections")
	_check(returned.pages[0].strikes.size() > 0, "the corrections strike the matched text")

	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
