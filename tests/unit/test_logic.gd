extends SceneTree
## Unit checks for the pure logic layer (scripts/logic). Headless:
##   godot --headless --path . --script res://tests/unit/test_logic.gd
## Exit code 0 means every check passed.

const Lev := preload("res://scripts/logic/levenshtein.gd")
const TextNorm := preload("res://scripts/logic/text_norm.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")
const Redaction := preload("res://scripts/logic/redaction.gd")
const Corrections := preload("res://scripts/logic/corrections.gd")
const MorningMemo := preload("res://scripts/logic/morning_memo.gd")
const ClockMath := preload("res://scripts/logic/clock_math.gd")

const MORNING := {
	"accuracy_ok": "TRANSCRIPTION {X}: ACCEPTABLE.",
	"accuracy_errors": "TRANSCRIPTION {X}: ERRORS NOTED.",
	"accuracy_errors_owner": "TRANSCRIPTION {X}: ERRORS NOTED. {OWNER} WORDS ARE NOT YOURS TO CHANGE.",
	"owner": {"T-1": "THE CITIZEN'S", "T-2": "THE BUREAU'S", "T-3": "THE CLERK'S"},
	"batch_correct": "BATCH {X}: CORRECT.",
	"batch_partial": "BATCH {X}: {n} OF {total} CORRECT.",
	"carbons_unfiled": "UNFILED CARBONS WERE FOUND AT DESK 4. THIS HAS BEEN NOTED.",
	"contradiction": "CONTRADICTORY STAMPS WERE FOUND. THE FIRST STAMP HAS BEEN USED.",
	"closing": "ACCURACY IS CONTINUITY.",
	"moravec_not_approved": "APPLICATION MORAVEC, A. HAS BEEN APPROVED REGARDLESS.",
	"moravec_approved": "APPLICATION MORAVEC, A. WAS DATED TOMORROW. THIS HAS BEEN OVERLOOKED.",
	"p1_q4_yes": "FORM P-1: OUR RECORDS SHOW NO PRIOR EMPLOYMENT. PLEASE DO NOT MAKE JOKES ON OFFICIAL FORMS.",
	"p1_q4_other": "FORM P-1: QUESTION 4 REQUIRES YES OR NO. WE HAVE ENTERED NO.",
	"signature_mismatch": "FORM P-1: YOUR SIGNATURE DOES NOT MATCH YOUR NAME. WE HAVE KEPT THE NAME.",
	"ro2_processed": "ORDER RO-2: PROCESSED. THANK YOU.",
	"ro2_complete": "ORDER RO-2: COMPLETE. IT WAS NOT STAMPED CORRECTLY. THIS HAS BEEN OVERLOOKED.",
	"ro2_remain": "ORDER RO-2: {k} OF 4 ENTRIES REMAIN. THEY WILL BE CARRIED FORWARD.",
	"ro2_returned": "ORDER RO-2: RETURNED UNPROCESSED. THE ENTRIES WILL BE CARRIED FORWARD.",
	"f3_q1_correct": "F-3 QUESTION 1: CORRECT.",
	"f3_q1_wrong": "F-3 QUESTION 1: THERE ARE TWELVE. THERE HAVE ALWAYS BEEN TWELVE.",
	"f3_q2_yes": "F-3 QUESTION 2: DESK 12 IS UNASSIGNED. PLEASE REST YOUR EYES.",
	"f3_q2_correct": "F-3 QUESTION 2: CORRECT.",
	"f3_q2_other": "F-3 QUESTION 2: YES OR NO.",
	"f3_q3_thanks": "F-3 QUESTION 3: THANK YOU FOR YOUR HONESTY. FILE THEM.",
	"f3_q3_count": "F-3 QUESTION 3: YOU STATED THAT YOU DO NOT KEEP CARBONS. PLEASE COUNT AGAIN.",
	"f3_q3_correct": "F-3 QUESTION 3: CORRECT.",
	"f3_q3_nothing": "F-3 QUESTION 3: YOU HAVE NOTHING TO KEEP.",
	"f3_q3_other": "F-3 QUESTION 3: YES OR NO.",
	"f3_q4_confirmed": "F-3 QUESTION 4: CONFIRMED.",
	"f3_q4_noted": "F-3 QUESTION 4: NOTED. WE WILL USE THE FIRST ONE.",
	"t4_no_longer": "TRANSCRIPTION T-4: CORRESPONDENCE OF THIS KIND WILL NO LONGER BE DELIVERED.",
	"s4_a": "BATCH S-4: YOU APPROVED THE APPLICATION NUMBERED 0412000. THE OTHERS HAVE BEEN WITHDRAWN.",
	"s4_b": "BATCH S-4: YOU APPROVED THE APPLICATION NUMBERED 0411000. THE OTHERS HAVE BEEN WITHDRAWN.",
	"s4_c": "BATCH S-4: YOU APPROVED THE APPLICATION WITH NO NUMBER. THE OTHERS HAVE BEEN WITHDRAWN.",
	"s4_none": "BATCH S-4: YOU APPROVED NONE. ONE HAS BEEN APPROVED ON YOUR BEHALF.",
	"s4_multiple": "BATCH S-4: YOU APPROVED MORE THAN ONE. ONLY ONE CAN BE CORRECT. ONE HAS BEEN RETAINED.",
	"letter_sent": "YOUR LETTER HAS BEEN SENT.",
}

var _failures := 0
var _ran := false
var _rng := RandomNumberGenerator.new()


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_rng.seed = 412
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _check_eq(actual: Variant, expected: Variant, label: String) -> void:
	var ok: bool = actual == expected
	_check(ok, label)
	if not ok:
		print("      expected: %s" % str(expected))
		print("      actual:   %s" % str(actual))


func _identity(s: String) -> String:
	return s


func _run() -> void:
	_test_levenshtein()
	_test_text_norm()
	_test_doc_model()
	_test_redaction()
	_test_corrections()
	_test_morning_memo()
	_test_clock()
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _test_levenshtein() -> void:
	_check(Lev.distance("KITTEN", "SITTING") == 3, "levenshtein KITTEN/SITTING = 3")
	_check(Lev.distance("", "ABC") == 3, "levenshtein empty = length")
	_check(Lev.distance("ABC", "ABC") == 0, "levenshtein identical = 0")


func _test_text_norm() -> void:
	_check(TextNorm.normalise("  a\n b\t c  ") == "A B C", "normalise uppercases, collapses and trims whitespace")
	_check_eq(TextNorm.sanitize_name("  dr. ilse 3 moravec-kessel's ?? "), "DR. ILSE MORAVEC-KESSEL'", "sanitise keeps only A-Z space - ' . drops digits, then truncates to 24")
	_check(TextNorm.sanitize_name("ABCDEFGHIJKLMNOPQRSTUVWXYZ") == "ABCDEFGHIJKLMNOPQRSTUVWX", "sanitise truncates to 24 characters")
	_check(TextNorm.title_case("MORAVEC  AUREL") == "Moravec Aurel", "title case per part")
	_check(TextNorm.first_part("ILSE MARIA MORAVEC") == "ILSE", "first part")
	_check(is_equal_approx(TextNorm.accuracy("ABCDEFGHIJ", "ABCDEFGHIJ"), 1.0), "accuracy identical = 1.0")
	_check(is_equal_approx(TextNorm.accuracy("ABCDEFGHIX", "ABCDEFGHIJ"), 0.9), "accuracy one wrong of ten = 0.9")
	_check(TextNorm.accuracy("", "ABC") == 0.0, "accuracy empty typed = 0.0")


func _test_doc_model() -> void:
	var page := DocModel.new_page()
	_check(DocModel.write_glyph(page, 0, 0, "A", _rng), "first glyph written")
	_check(DocModel.write_glyph(page, 0, 0, "B", _rng), "overstrike second glyph written")
	_check(DocModel.write_glyph(page, 0, 0, "C", _rng), "overstrike third glyph written")
	_check(not DocModel.write_glyph(page, 0, 0, "D", _rng), "fourth overstrike glyph is ignored")
	_check(DocModel.cell_char(page, 0, 0) == "C", "cell reads its last glyph")
	var g: Dictionary = page.cells["0:0"].g[0]
	_check(g.a >= 0.82 and g.a <= 1.0 and absf(g.x) <= 0.3 and absf(g.y) <= 0.6, "glyph jitter within spec ranges")

	var p2 := DocModel.new_page()
	var fields := DocModel.extract_fields("   {{F1:6}}")
	_check(fields.text == "   " and fields.fields[0].id == "F1" and fields.fields[0].col == 3 and fields.fields[0].len == 6, "form marker parsed to field at its column")
	var next := DocModel.add_printed_lines(p2, ["1. NAME", "   {{F1:6}}"], 0)
	_check(next == 2 and DocModel.field_by_id(p2, "F1").line == 1, "form field recorded at its printed line")
	for i in range(6):
		DocModel.write_glyph(p2, 1, 3 + i, "XY"[i % 2], _rng)
	DocModel.whiteout(p2, 1, 4, _rng)
	_check_eq(DocModel.field_value(p2, DocModel.field_by_id(p2, "F1")), "X XYXY", "field value: last glyph per cell, whiteout as space, runs collapsed")

	var wrapped := DocModel.wrap_text("ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN ELEVEN TWELVE THIRTEEN FOURTEEN FIFTEEN SIXTEEN SEVENTEEN", 64)
	_check(wrapped.size() == 2 and String(wrapped[0]).length() <= 64, "word wrap at 64 columns")

	var p3 := DocModel.new_page()
	DocModel.write_glyph(p3, 0, 0, "H", _rng)
	DocModel.write_glyph(p3, 0, 1, "I", _rng)
	DocModel.write_glyph(p3, 2, 0, "Y", _rng)
	_check_eq(DocModel.typed_text(p3), "HI Y", "typed text joins lines with single spaces")


func _test_redaction() -> void:
	var s := "MORAVEC, AUREL and MORAVEC, A. and AUREL MORAVEC and VANCE in H. VANCE"
	var spans := Redaction.find_entity_spans(s, ["aurel", "vance"], Callable(self, "_identity"))
	_check(spans.size() == 5, "alias matching finds all occurrences (found %d)" % spans.size())
	var none := Redaction.find_entity_spans("MORAVEC, AUREL-ARCHIVE SUMMARY", ["aurel"], Callable(self, "_identity"))
	_check(none.size() == 1, "alias matches before a hyphen (non-letter boundary)")
	var inside := Redaction.find_entity_spans("PAURELA", ["aurel"], Callable(self, "_identity"))
	_check(inside.is_empty(), "alias inside a longer word does not match")
	var h := Redaction.find_entity_spans("— H.V.", ["vance"], Callable(self, "_identity"))
	_check(h.size() == 1, "notebook signature H.V. matches the vance entity")
	var nok := Redaction.find_entity_spans("DEAR M. ALDER I AM FINE", ["nok"], Callable(self, "_identity"))
	_check(nok.is_empty(), "nok alias unsubstituted matches nothing")

	_check(is_equal_approx(Redaction.coverage([{"x0": 0.0, "x1": 50.0}, {"x0": 40.0, "x1": 100.0}], 0.0, 100.0), 1.0), "coverage union is 1.0 for overlapping bars")
	_check(is_equal_approx(Redaction.coverage([{"x0": 0.0, "x1": 30.0}], 0.0, 100.0), 0.3), "coverage of a short bar is 0.3")
	_check(Redaction.coverage([], 0.0, 100.0) == 0.0, "coverage with no bars is 0")

	var page := DocModel.new_page()
	DocModel.add_printed_lines(page, ["03  DOBRA, KASIMIR   3307752"])
	# The name starts at column 4 and is 14 characters long.
	var x0 := DocModel.LEFT + 4.0 * DocModel.COL_W
	var x1 := x0 + 14.0 * DocModel.COL_W
	DocModel.add_bar(page, 0, x0, x0 + 0.79 * (x1 - x0))
	_check(not Redaction.entry_redacted(page, "DOBRA, KASIMIR"), "79% coverage does not redact")
	DocModel.add_bar(page, 0, x0 + 0.79 * (x1 - x0), x1)
	_check(Redaction.entry_redacted(page, "DOBRA, KASIMIR"), "full coverage redacts")


func _test_corrections() -> void:
	# Original typed text, then the spec 14.8 T-1 correction.
	var page := DocModel.new_page()
	var typed := "MY BROTHER, AUREL MORAVEC, LAST SEEN AT THE TRAM STOP. I AM ASKING ONLY THAT YOU LOOK AGAIN."
	var lines := DocModel.wrap_text(typed, 64)
	for i in range(lines.size()):
		for j in range(String(lines[i]).length()):
			DocModel.write_glyph(page, i, j, String(lines[i])[j], _rng)
	Corrections.apply_one(page, "MY BROTHER, AUREL MORAVEC,", "A MAN,", _rng)
	_check(page.strikes.size() >= 1, "correction matched and struck the window")
	_check(page.inserts.size() > 0 and String(page.inserts[0].c) == "A", "replacement written as red insert glyphs")
	_check(String(page.inserts[0].ink) == "red", "insert glyphs are red")

	# Fuzzy match: one character differs in the find text.
	var page2 := DocModel.new_page()
	for j in range(typed.length()):
		DocModel.write_glyph(page2, 0, j, typed[j], _rng)
	Corrections.apply_one(page2, "MY BROTHER, AUREL MORAVAC,", "A MAN,", _rng)
	_check(page2.strikes.size() >= 1, "fuzzy match at similarity >= 0.6 still strikes")

	# No match: text goes to the first empty line, prefixed "ADD: ".
	var page3 := DocModel.new_page()
	DocModel.write_glyph(page3, 0, 0, "A", _rng)
	Corrections.apply_one(page3, "THIS PHRASE IS NOWHERE ON THE PAGE AT ALL", "NEW TEXT", _rng)
	var added := DocModel.line_text(page3, 1).strip_edges()
	_check(added.begins_with("ADD: NEW TEXT"), "unmatched correction writes ADD line on the first empty line")
	_check(String(page3.cells["1:0"].g[0].ink) == "red", "ADD glyphs are red")


func _test_morning_memo() -> void:
	var inputs := {
		"accuracy_id": "T-1", "accuracy": 0.99,
		"batch_id": "S-1", "batch_correct": 4, "batch_total": 5,
		"moravec_p3": "DENIED",
		"p1_q4": "OTHER",
		"signature_matches": false,
		"carbons_unfiled": true,
		"contradictions": 0,
	}
	var out := MorningMemo.build(2, inputs, MORNING)
	var expected := [
		"TRANSCRIPTION T-1: ACCEPTABLE.",
		"BATCH S-1: 4 OF 5 CORRECT.",
		"APPLICATION MORAVEC, A. HAS BEEN APPROVED REGARDLESS.",
		"FORM P-1: QUESTION 4 REQUIRES YES OR NO. WE HAVE ENTERED NO.",
		"FORM P-1: YOUR SIGNATURE DOES NOT MATCH YOUR NAME. WE HAVE KEPT THE NAME.",
		"UNFILED CARBONS WERE FOUND AT DESK 4. THIS HAS BEEN NOTED.",
		"ACCURACY IS CONTINUITY.",
	]
	_check_eq(out.lines, expected, "day 2 memo lines match spec 14.6 order and wording")
	_check(bool(out.set_p1_q4_no), "day 2 OTHER answer sets Form P-1 question 4 to NO")

	var low := MorningMemo.build(2, {"accuracy_id": "T-1", "accuracy": 0.5, "batch_id": "S-1", "batch_correct": 5, "batch_total": 5, "moravec_p3": "APPROVED", "p1_q4": "YES", "signature_matches": true, "carbons_unfiled": false, "contradictions": 2}, MORNING)
	_check(low.lines[0] == "TRANSCRIPTION T-1: ERRORS NOTED. THE CITIZEN'S WORDS ARE NOT YOURS TO CHANGE.", "accuracy under 0.90 carries the owner clause")
	_check(low.lines[1] == "BATCH S-1: CORRECT.", "all-correct batch line")
	_check(low.lines[2] == "APPLICATION MORAVEC, A. WAS DATED TOMORROW. THIS HAS BEEN OVERLOOKED.", "page 3 APPROVED gives the dated-tomorrow line")
	_check(low.lines[low.lines.size() - 2] == "CONTRADICTORY STAMPS WERE FOUND. THE FIRST STAMP HAS BEEN USED.", "contradiction line before closing")

	var ro := MorningMemo.build(3, {"accuracy_id": "T-2", "accuracy": 0.95, "ro": {"listed": 4, "redacted": 2, "first_stamp": "PROCESSED"}, "batch_id": "S-2", "batch_correct": 4, "batch_total": 4, "carbons_unfiled": false, "contradictions": 0}, MORNING)
	_check_eq(ro.lines[1], "ORDER RO-2: 2 OF 4 ENTRIES REMAIN. THEY WILL BE CARRIED FORWARD.", "RO-2 partial redaction line uses the count not redacted")
	var ro_all := MorningMemo.build(3, {"accuracy_id": "T-2", "accuracy": 0.95, "ro": {"listed": 4, "redacted": 4, "first_stamp": "RETURNED"}, "batch_id": "S-2", "batch_correct": 4, "batch_total": 4, "carbons_unfiled": false, "contradictions": 0}, MORNING)
	_check(ro_all.lines[1] == "ORDER RO-2: COMPLETE. IT WAS NOT STAMPED CORRECTLY. THIS HAS BEEN OVERLOOKED.", "RO-2 all redacted but not PROCESSED gives COMPLETE")


func _test_clock() -> void:
	_check(ClockMath.time_after_task(1, 3) == "11:40", "clock after task 1 of 3 = 11:40")
	_check(ClockMath.time_after_task(2, 3) == "14:20", "clock after task 2 of 3 = 14:20")
	_check(ClockMath.time_after_task(3, 3) == "17:00", "clock after task 3 of 3 = 17:00 (QUESTION-5 literal)")
	_check(ClockMath.time_after_task(1, 2) == "13:00", "clock after task 1 of 2 = 13:00")
	var angles := ClockMath.hand_angles("08:58")
	_check(is_equal_approx(float(angles.minute), 348.0), "minute hand at 58 minutes = 348 degrees")
	_check(is_equal_approx(float(angles.hour), (8.0 + 58.0 / 60.0) * 30.0), "hour hand at 08:58")
