extends RefCounted
## Morning memo lines for Days 2 to 5 (spec 14.6, 14.9, 14.10 and 14.11). Pure
## function. Every template comes from data/strings.json "morning" (passed in as
## M), so no player-visible text lives in this file.
##
## inputs keys (all optional values are ignored when a day does not use them):
##   accuracy_id (String, "T-1".."T-3"), accuracy (float)        -- the previous transcription
##   batch_id (String, "S-1"/"S-2"/"S-4"), batch_correct (int), batch_total (int)
##   moravec_p3 ("APPROVED"/"DENIED"/"NONE")                     -- Day 2 only
##   p1_q4 ("YES"/"NO"/"OTHER")                                  -- Day 2 only
##   signature_matches (bool)                                    -- Day 2 only
##   ro: {listed (int), redacted (int), first_stamp (String)}    -- Day 3 (RO-2), Day 4 (RO-3), Day 5 (RO-4)
##   f3_q1, f3_q2, f3_q3 (normalised answers), f3_q4_matches (bool), f3_had_carbons (bool)
##   s4_choice ("A"/"B"/"C"/"NONE"/"MULTIPLE")                    -- Day 5
##   ghost_deleted (bool)                                        -- Day 5
##   carbons_unfiled (bool), contradictions (int)                -- from the previous day
##
## Returns {lines: Array[String], set_p1_q4_no: bool}. set_p1_q4_no is true when
## Form P-1 question 4 was OTHER on Day 2 (spec 14.6 line 4).


static func build(day: int, inputs: Dictionary, m: Dictionary) -> Dictionary:
	var lines: Array = []
	var set_no := false
	match day:
		2:
			lines.append(_accuracy(String(inputs.accuracy_id), float(inputs.accuracy), m))
			lines.append(_batch(String(inputs.batch_id), int(inputs.batch_correct), int(inputs.batch_total), m))
			if String(inputs.moravec_p3) == "APPROVED":
				lines.append(String(m.moravec_approved))
			else:
				lines.append(String(m.moravec_not_approved))
			var q4 := String(inputs.p1_q4)
			if q4 == "YES":
				lines.append(String(m.p1_q4_yes))
			elif q4 == "OTHER":
				lines.append(String(m.p1_q4_other))
				set_no = true
			if not bool(inputs.signature_matches):
				lines.append(String(m.signature_mismatch))
			_tail(lines, inputs, m)
		3:
			lines.append(_accuracy(String(inputs.accuracy_id), float(inputs.accuracy), m))
			lines.append(_ro(inputs.ro, "2", m))
			lines.append(_batch(String(inputs.batch_id), int(inputs.batch_correct), int(inputs.batch_total), m))
			_tail(lines, inputs, m)
		4:
			lines.append(_accuracy(String(inputs.accuracy_id), float(inputs.accuracy), m))
			lines.append(_ro(inputs.ro, "3", m))
			lines.append(_f3_q1(String(inputs.f3_q1), m))
			lines.append(_f3_q2(String(inputs.f3_q2), m))
			lines.append(_f3_q3(String(inputs.f3_q3), bool(inputs.f3_had_carbons), m))
			lines.append(_f3_q4(bool(inputs.f3_q4_matches), m))
			_tail(lines, inputs, m)
		5:
			lines.append(String(m.t4_no_longer))
			lines.append(_ro(inputs.ro, "4", m))
			lines.append(_s4(String(inputs.s4_choice), m))
			if bool(inputs.ghost_deleted):
				lines.append(String(m.letter_sent))
			_tail(lines, inputs, m)
		_:
			push_error("morning_memo: no morning memo for day %d" % day)
	return {"lines": lines, "set_p1_q4_no": set_no}


static func _fmt(template: String, values: Dictionary) -> String:
	var s := template
	for key in values.keys():
		s = s.replace("{" + String(key) + "}", str(values[key]))
	return s


## Spec 14.6 "Accuracy line". a >= 0.98 acceptable. 0.90 <= a < 0.98 noted.
## a < 0.90 noted, with the owner clause.
static func _accuracy(id: String, a: float, m: Dictionary) -> String:
	if a >= 0.98:
		return _fmt(String(m.accuracy_ok), {"X": id})
	if a >= 0.90:
		return _fmt(String(m.accuracy_errors), {"X": id})
	var owner := String(m.owner.get(id, ""))
	return _fmt(String(m.accuracy_errors_owner), {"X": id, "OWNER": owner})


## Spec 14.6 "Batch line". All correct gives CORRECT. Otherwise n of total.
static func _batch(id: String, correct: int, total: int, m: Dictionary) -> String:
	if correct == total:
		return _fmt(String(m.batch_correct), {"X": id})
	return _fmt(String(m.batch_partial), {"X": id, "n": correct, "total": total})


## Spec 14.9 RO-2, 14.10 RO-3, 14.11 RO-4. num is "2", "3" or "4". k is the
## number not redacted. n is the number listed.
static func _ro(ro: Dictionary, num: String, m: Dictionary) -> String:
	var listed := int(ro.listed)
	var redacted := int(ro.redacted)
	var remaining := listed - redacted
	var stem := "ro" + num + "_"
	if redacted == listed:
		if String(ro.first_stamp) == "PROCESSED":
			return String(m[stem + "processed"])
		return String(m[stem + "complete"])
	if redacted >= 1:
		return _fmt(String(m[stem + "remain"]), {"k": remaining, "n": listed})
	return String(m[stem + "returned"])


static func _f3_q1(answer: String, m: Dictionary) -> String:
	if answer == "12" or answer == "TWELVE":
		return String(m.f3_q1_correct)
	return String(m.f3_q1_wrong)


static func _f3_q2(answer: String, m: Dictionary) -> String:
	if answer == "YES":
		return String(m.f3_q2_yes)
	if answer == "NO":
		return String(m.f3_q2_correct)
	return String(m.f3_q2_other)


static func _f3_q3(answer: String, had_carbons: bool, m: Dictionary) -> String:
	if answer == "YES" and had_carbons:
		return String(m.f3_q3_thanks)
	if answer == "NO" and had_carbons:
		return String(m.f3_q3_count)
	if answer == "NO":
		return String(m.f3_q3_correct)
	if answer == "YES":
		return String(m.f3_q3_nothing)
	return String(m.f3_q3_other)


static func _f3_q4(matches: bool, m: Dictionary) -> String:
	return String(m.f3_q4_confirmed) if matches else String(m.f3_q4_noted)


static func _s4(choice: String, m: Dictionary) -> String:
	match choice:
		"A":
			return String(m.s4_a)
		"B":
			return String(m.s4_b)
		"C":
			return String(m.s4_c)
		"MULTIPLE":
			return String(m.s4_multiple)
		_:
			return String(m.s4_none)


## Carbons line, contradiction line and closing line, in that order.
static func _tail(lines: Array, inputs: Dictionary, m: Dictionary) -> void:
	if bool(inputs.get("carbons_unfiled", false)):
		lines.append(String(m.carbons_unfiled))
	if int(inputs.get("contradictions", 0)) > 0:
		lines.append(String(m.contradiction))
	lines.append(String(m.closing))
