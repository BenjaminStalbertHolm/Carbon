extends SceneTree
## Logic-level acceptance checks from spec 20: test 5 (retired word), test 6
## (defaults) and test 10 (free mail). Headless:
##   godot --headless --path . --script res://tests/unit/test_acceptance_logic.gd

const DocModel := preload("res://scripts/logic/doc_model.gd")
const CadenceModel := preload("res://scripts/logic/cadence_model.gd")
const TypewriterModel := preload("res://scripts/logic/typewriter_model.gd")

var _failures := 0
var _ran := false
var _gs: Node
var _dd: Node
var _tt: Node
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


func _printed_text(doc: Dictionary) -> String:
	var parts := PackedStringArray()
	for entry in doc.pages[0].printed:
		parts.append(String(entry.text))
	return " ".join(parts)


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


func _form(doc_id: String, answers: Dictionary) -> void:
	_gs.place(doc_id, "typewriter")
	_tw.load_sheet(_gs.docs[doc_id], {})
	var form: Dictionary = _gs.docs[doc_id]
	for fid in ["F1", "F2", "F3", "F4", "F5"]:
		if answers.has(fid):
			var field := DocModel.field_by_id(form.pages[0], fid)
			_tw.click_cell(int(field.line), int(field.col), _now)
			_type(String(answers[fid]))
	_tw.unload()
	_gs.place(doc_id, "hand")
	_dd.send_document(doc_id)


func _run() -> void:
	_gs = get_root().get_node("GameState")
	_dd = get_root().get_node("DayDirector")
	_tt = get_root().get_node("TextTokens")
	_tw = TypewriterModel.new(CadenceModel.new(), _gs.rng)

	_scenario_defaults()
	_scenario_retired_word()
	_scenario_free_mail()

	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Spec 20 test 6: leave all P-1 fields blank.
func _scenario_defaults() -> void:
	print("-- defaults (test 6)")
	_dd.start_new_game(6)
	_dd.tick(4.0)
	_dd.tick(6.0)
	_dd.tick(5.0)
	_form("P-1", {})
	_check_eq(_tt.token_values().PLAYER_NAME, "CLERK 0412", "blank name gives CLERK 0412")
	_check_eq(_tt.token_values().NEXT_OF_KIN, "M. ALDER", "blank next of kin gives M. ALDER")
	_check_eq(_tt.token_values().FOND_WORD, "QUIET", "blank fond word gives QUIET")
	_check_eq(_gs.p1_q4, "OTHER", "blank question 4 is OTHER")
	_check(_gs.signature_matches, "blank name and blank signature count as matching")
	_check_eq(_gs.nameplate["4"], "CLERK 0412", "desk 4 nameplate reads CLERK 0412")
	_dd.start_next_day()
	_dd.tick(10.0)
	var m2 := _printed_text(_gs.docs["M2"])
	_check(m2.contains("FORM P-1: QUESTION 4 REQUIRES YES OR NO. WE HAVE ENTERED NO."), "day 2 memo carries the OTHER line for question 4")
	_check(not m2.contains("SIGNATURE DOES NOT MATCH"), "day 2 memo has no signature line for blank fields")


## Spec 20 test 5: the retired word, and the reserved word QUIET.
func _scenario_retired_word() -> void:
	print("-- retired word (test 5)")
	_dd.start_new_game(5)
	_dd.tick(4.0)
	_dd.tick(6.0)
	_dd.tick(5.0)
	_form("P-1", {"F1": "ANNA TESTER", "F2": "JOHN TESTER", "F3": "LANTERN", "F4": "NO", "F5": "ANNA TESTER"})
	_check_eq(_gs.fond_word, "LANTERN", "fond word LANTERN is stored")
	var c22: Dictionary = _dd.instantiate("C-22")
	_check(_printed_text(c22).contains("'LANTERN'"), "circular C-22 shows the fond word on day 2")
	_gs.day = 3
	var n3: Dictionary = _dd.instantiate("N-3")
	var n3_line := _printed_text(n3)
	_check(n3_line.contains("'LANTERN'"), "notice N-3 carries the fond word")
	var spans: Array = _tt.bar_spans("THE WORD 'LANTERN' IS RETIRED FROM USE.")
	_check_eq(spans.size(), 1, "from Day 3 the fond word is barred wherever it is printed")

	_dd.start_new_game(51)
	_dd.tick(4.0)
	_dd.tick(6.0)
	_dd.tick(5.0)
	_form("P-1", {"F1": "ANNA TESTER", "F2": "JOHN TESTER", "F3": "THE", "F4": "NO", "F5": "ANNA TESTER"})
	_check_eq(_gs.fond_word, "QUIET", "a three-letter fond word is replaced by QUIET")
	var c22b: Dictionary = _dd.instantiate("C-22")
	_check(_printed_text(c22b).contains("'QUIET'"), "C-22 shows QUIET when the fond word is replaced")


## Spec 20 test 10: a free sheet sent on Day 2 returns on Day 3, stamped.
func _scenario_free_mail() -> void:
	print("-- free mail (test 10)")
	_dd.start_new_game(10)
	_dd.begin_day(2)
	_dd.tick(10.0)
	var fid: String = _dd.take_blank_sheet()
	_check(fid.begins_with("FREE-"), "a blank sheet with no task active is a free sheet")
	_check(_gs.docs[fid].kind == "free", "the free sheet has kind free")
	_gs.place(fid, "hand")
	_gs.docs[fid].pages[0].printed.append({"line": 0, "col": 0, "text": "FREE TEXT", "ink": "black"})
	_dd.send_document(fid)
	_check(_gs.free_mail_sent.has(fid), "the sent free sheet is recorded for return")
	_check(_gs.location_of(fid) == "removed", "the sent free sheet waits in the removed store")
	_dd.start_next_day()
	_dd.tick(10.0)
	_check_eq(_gs.location_of(fid), "inbox", "the free sheet comes back in the Day 3 morning canister")
	var stamps: Array = _gs.docs[fid].pages[0].stamps
	_check(stamps.size() == 1 and String(stamps[0].word) == "NO SUCH ADDRESSEE", "the returned free sheet carries the NO SUCH ADDRESSEE stamp")
	_check_eq(String(stamps[0].ink), "red", "the NO SUCH ADDRESSEE impression is red")
	_check_eq(_gs.free_mail_sent.size(), 0, "free mail is cleared after the return")
