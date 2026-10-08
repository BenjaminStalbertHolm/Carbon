extends SceneTree
## Acceptance test 1 (spec 20): a compliant run through all five days, driven at
## the logic level. The player types everything correctly, files every carbon,
## redacts every listed entry, stamps PROCESSED, and approves what the batches
## ask for. Headless:
##   godot --headless --path . --script res://tests/unit/test_playthrough_compliant.gd

const DocModel := preload("res://scripts/logic/doc_model.gd")
const Redaction := preload("res://scripts/logic/redaction.gd")
const CadenceModel := preload("res://scripts/logic/cadence_model.gd")
const TypewriterModel := preload("res://scripts/logic/typewriter_model.gd")

var _failures := 0
var _ran := false
var _gs: Node
var _dd: Node
var _tw: TypewriterModel
var _now := 0.0
var _ro5_desk4 := false
var _ro5_fired := false


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


func _printed_lines(doc_id: String) -> Array:
	var out: Array = []
	for entry in _gs.docs[doc_id].pages[0].printed:
		out.append(String(entry.text))
	return out


## Types text into the loaded sheet, breaking lines at word boundaries.
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


func _load_typewriter(doc_id: String, carbon_id: String) -> void:
	_gs.place(doc_id, "typewriter")
	_tw.retired_active = int(_gs.day) >= 3
	_tw.fond_word = String(_gs.fond_word)
	_tw.load_sheet(_gs.docs[doc_id], _gs.docs[carbon_id] if carbon_id != "" else {})


func _form(doc_id: String, answers: Dictionary) -> void:
	_load_typewriter(doc_id, "")
	var form: Dictionary = _gs.docs[doc_id]
	for fid in ["F1", "F2", "F3", "F4", "F5"]:
		if not answers.has(fid):
			continue
		var field := DocModel.field_by_id(form.pages[0], fid)
		_tw.click_cell(int(field.line), int(field.col), _now)
		_type(String(answers[fid]))
	_tw.unload()
	_gs.place(doc_id, "hand")
	_dd.send_document(doc_id)


func _transcription(source_doc: String, skip_first: bool) -> String:
	var sid: String = _dd.take_blank_sheet()
	var sheet: Dictionary = _gs.docs[sid]
	_load_typewriter(sid, String(sheet.twin))
	# The typewriter has no em dash key (spec 7.2): a player types a hyphen instead.
	_type(String(_dd._source_text(source_doc, skip_first)).replace("—", "-"))
	_tw.unload()
	_dd.paper_removed(sid)
	_gs.place(sid, "hand")
	_dd.send_document(sid)
	return sid


func _batch(batch_id: String, results: Array) -> void:
	for i in range(results.size()):
		_dd.stamp_document(batch_id, i, String(results[i]), 300.0, 400.0, 0.0, 0.9)
	_dd.send_document(batch_id)


func _order(order_id: String, names: Array, stamp: String) -> void:
	var doc: Dictionary = _gs.docs[order_id]
	var page: Dictionary = doc.pages[0]
	for name in names:
		var ext := Redaction.name_extent(page, String(name))
		if ext.is_empty():
			_check(false, "order %s: name %s is printed" % [order_id, name])
			continue
		DocModel.add_bar(page, int(ext[0]), float(ext[1]), float(ext[2]))
	_dd.stamp_document(order_id, 0, stamp, 300.0, 400.0, 0.0, 0.9)
	_dd.send_document(order_id)


func _lamp_and_night() -> void:
	_dd.file_carbons()
	_dd.click_lamp()
	_dd.tick(1.5)
	_dd.start_next_day()



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
	_dd.ro5_sent.connect(func(desk4): _ro5_fired = true; _ro5_desk4 = desk4)

	_dd.start_new_game(412)
	_dd.tick(4.0)
	_dd.tick(6.0)
	_check(_gs.location_of("M1-WELCOME") == "inbox", "day 1: the welcome memo arrives in the morning")
	_dd.tick(5.0)

	# --- Day 1 ----------------------------------------------------------------
	_form("P-1", {"F1": "ANNA MARIA TESTER", "F2": "JOHN TESTER", "F3": "LANTERN", "F4": "NO", "F5": "ANNA MARIA TESTER"})
	_dd.tick(5.0)
	_transcription("L-1", false)
	_check(float(_gs.accuracy.get("T-1", 0.0)) >= 0.999, "day 1: transcription T-1 is accurate")
	_dd.tick(5.0)
	_batch("S-1", ["APPROVED", "DENIED", "APPROVED", "DENIED", "APPROVED"])
	_check_eq(_gs.clock_time, "17:00", "day 1: clock reaches 17:00 after the last task")
	_dd.tick(5.0)
	_check(_gs.end_of_shift_arrived, "day 1: End of Shift arrives")
	_lamp_and_night()
	_check_eq(_gs.day, 2, "day 1 ends and day 2 begins")

	# --- Day 2 ----------------------------------------------------------------
	_dd.tick(10.0)
	var m2 := _printed_lines("M2")
	_check(_has_text(m2, "TRANSCRIPTION T-1: ACCEPTABLE."), "M2: T-1 accuracy line ACCEPTABLE")
	_check(_has_text(m2, "BATCH S-1: CORRECT."), "M2: S-1 batch line CORRECT")
	_check(_has_text(m2, "APPLICATION MORAVEC, A. WAS DATED TOMORROW. THIS HAS BEEN OVERLOOKED."), "M2: page 3 approved gives the dated-tomorrow line")
	_check(not _gs.carbons_unfiled_flag, "M2: no unfiled carbon line")
	_check(_gs.location_of("SHEET-1") == "inbox", "day 2: the T-1 original comes back")
	_check(_gs.docs["SHEET-1"].pages[0].inserts.size() > 0, "day 2: the returned T-1 original carries Management corrections")

	_dd.tick(5.0)
	_transcription("C-22", true)
	# The C-22 source contains an em dash that the typewriter cannot type (spec 7.2). See QUESTION-10.
	_check(float(_gs.accuracy.get("T-2", 0.0)) >= 0.99, "day 2: transcription T-2 (C-22 with the fond word) is accurate apart from the em dash (got %s)" % str(_gs.accuracy.get("T-2")))
	_dd.tick(5.0)
	_order("RO-2", ["DOBRA, KASIMIR", "FELL, ODETTE", "MORAVEC, AUREL", "MORAVEC, ILSE"], "PROCESSED")
	_check(_gs.first_stamp.get("RO-2", "") == "PROCESSED", "day 2: RO-2 first impression PROCESSED")
	_check(bool(_gs.ro_results["RO-2"].entries.get("09", false)), "day 2: MORAVEC, AUREL entry is redacted")
	_check(_gs.carried_forward.is_empty(), "day 2: nothing carried forward from a full redaction")
	_dd.tick(5.0)
	_batch("S-2", ["DENIED", "APPROVED", "DENIED", "DENIED"])
	_dd.tick(5.0)
	_check(_gs.end_of_shift_arrived, "day 2: End of Shift arrives")
	_lamp_and_night()

	# --- Day 3 ----------------------------------------------------------------
	_dd.tick(10.0)
	var m3 := _printed_lines("M3")
	_check(_has_text(m3, "TRANSCRIPTION T-2: ACCEPTABLE."), "M3: T-2 accuracy line ACCEPTABLE")
	_check(_has_text(m3, "ORDER RO-2: PROCESSED. THANK YOU."), "M3: RO-2 processed line")
	_check(_has_text(m3, "BATCH S-2: CORRECT."), "M3: S-2 batch line CORRECT")
	_check(_printed_lines("M1-WELCOME").has("YOU HAVE NO PREDECESSOR."), "day 3: welcome memo drift applied")
	_check(_gs.clock_time == "09:00" or _gs.clock_time == "08:58", "day 3: the clock starts the day")
	_dd.tick(5.0)
	_transcription("ST-3", false)
	_check(float(_gs.accuracy.get("T-3", 0.0)) >= 0.999, "day 3: transcription T-3 is accurate")
	_dd.tick(5.0)
	_order("RO-3", ["J. ABEL", "N. FERRAND", "H. VANCE"], "PROCESSED")
	_check(_gs.first_stamp.get("RO-3", "") == "PROCESSED", "day 3: RO-3 first impression PROCESSED")
	_dd.file_carbons()
	_dd.tick(5.0)
	_form("F-3", {"F1": "12", "F2": "NO", "F3": "NO", "F4": "ANNA MARIA TESTER"})
	_check_eq(_gs.f3_answers.get("Q1", ""), "12", "day 3: F-3 question 1 answer stored")
	_check(not _gs.f3_had_carbons, "day 3: no carbons outside the drawer at F-3")
	_dd.tick(5.0)
	_check(_gs.location_of("GHOST-MEMO") == "inbox", "day 3: the ghost memo arrives 5 s after F-3")
	_dd.tick(125.0)
	_check(_gs.end_of_shift_arrived, "day 3: End of Shift arrives 120 s after the ghost memo")
	_lamp_and_night()

	# --- Day 4 ----------------------------------------------------------------
	_dd.tick(10.0)
	var m4 := _printed_lines("M4")
	_check(_has_text(m4, "TRANSCRIPTION T-3: ACCEPTABLE."), "M4: T-3 accuracy line ACCEPTABLE")
	_check(_has_text(m4, "ORDER RO-3: PROCESSED. THANK YOU."), "M4: RO-3 processed line")
	_check(_has_text(m4, "F-3 QUESTION 1: CORRECT."), "M4: F-3 question 1 correct")
	_check(_has_text(m4, "F-3 QUESTION 2: CORRECT."), "M4: F-3 question 2 correct")
	_check(_has_text(m4, "F-3 QUESTION 3: CORRECT."), "M4: F-3 question 3 correct")
	_check(_has_text(m4, "F-3 QUESTION 4: CONFIRMED."), "M4: F-3 question 4 confirmed")
	_check(not _gs.clerk_present.get("7", true), "day 4: the Desk 7 clerk is redacted and gone")
	_check(not _gs.clerk_present.get("8", true), "day 4: the Desk 8 clerk is redacted and gone")
	_check(_gs.nameplate.get("12", "x") == "", "day 4: Desk 12 nameplate is blank after H. VANCE is redacted")
	_dd.tick(5.0)
	_transcription("L-4", false)
	_check(float(_gs.accuracy.get("T-4", 0.0)) >= 0.999, "day 4: transcription T-4 is accurate")
	_dd.tick(5.0)
	_order("RO-4", ["JOHN TESTER", "HALVORSEN, PETRA", "WEISS, CORA"], "PROCESSED")
	_check(_gs.first_stamp.get("RO-4", "") == "PROCESSED", "day 4: RO-4 first impression PROCESSED")
	_dd.tick(5.0)
	_batch("S-4", ["APPROVED", "DENIED", "DENIED"])
	_check_eq(_gs.s4_choice, "A", "day 4: the S-4 choice is A")
	_dd.tick(125.0)
	_check(_gs.end_of_shift_arrived, "day 4: End of Shift arrives 120 s after S-4 (no ghost lines typed)")
	_lamp_and_night()

	# --- Day 5 ----------------------------------------------------------------
	_dd.tick(10.0)
	var m5 := _printed_lines("M5")
	_check(_has_text(m5, "TRANSCRIPTION T-4: CORRESPONDENCE OF THIS KIND WILL NO LONGER BE DELIVERED."), "M5: the T-4 no-longer-delivered line")
	_check(_has_text(m5, "ORDER RO-4: PROCESSED. THANK YOU."), "M5: RO-4 processed line")
	_check(_has_text(m5, "BATCH S-4: YOU APPROVED THE APPLICATION NUMBERED 0412000. THE OTHERS HAVE BEEN WITHDRAWN."), "M5: S-4 approved line A")
	_check(not _gs.flags.get("ghost4_deleted", false), "day 5: no ghost sheet was deleted, so no letter line")
	_check(_gs.desk_removed.get("7", false) and _gs.desk_removed.get("8", false), "day 5: desks 7 and 8 are removed")
	_check(not _gs.clerk_present.get("9", true), "day 5: the Desk 9 clerk is redacted on RO-4")
	_check(not _gs.fixture_lit.get("4", true), "day 5: fixture F4 is off (desks 7 and 8 empty)")
	_check(_gs.fixture_lit.get("5", false), "day 5: fixture F5 stays on (desk 10 occupied)")
	_check_eq(int(_gs.flags.get("quota_occupied", -1)), 8, "day 5: quota board shows 8/12")
	_dd.tick(5.0)
	_form("P-1D", {"F1": "ANNA MARIA TESTER", "F2": "JOHN TESTER", "F3": "LANTERN", "F4": "NO", "F5": "ANNA MARIA TESTER"})
	_dd.tick(5.0)
	_order("RO-5", ["ANNA MARIA TESTER"], "PROCESSED")
	_check(_ro5_fired, "day 5: RO-5 sent")
	_check(_ro5_desk4, "day 5: the Desk 4 entry is redacted, which leads to Ending A")
	_check_eq(_gs.carbons_kept_at_final, 0, "day 5: no transcription carbons kept at the final order")

	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
