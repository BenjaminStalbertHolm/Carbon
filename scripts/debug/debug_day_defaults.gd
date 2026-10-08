extends RefCounted
## Debug "day N" defaults (spec 21). Starts a new game, then gives Days 1 to N-1 the state of a
## compliant run and resolves each day's overnight with DayDirector.run_overnight (spec 14.7), then
## begins Day N. Defaults, all documented in tests/ACCEPTANCE.md:
##  - P-1 tokens: tokens_set true, every P-1 answer blank (CLERK 0412, M. ALDER, QUIET, OTHER).
##  - Transcriptions T-1 to T-4: accuracy 1.0. No transcription original or carbon is recreated.
##  - Batches S-1, S-2: each page holds its batch's Correct column. S-4 approves application A, as
##    the compliant run does (S-4 has no Correct column; the choice is the player's, spec 14.10).
##  - Orders RO-2 to RO-4: first impression PROCESSED; every listed entry redacted (no carried rows).
##  - F-3: Q1 "12", Q2 "NO", Q3 "NO", Q4 blank.
##  - Carbons: none exist to file, so filing is a no-op (the drawer is emptied overnight, spec 14.7).

const Content := preload("res://scripts/logic/content.gd")

const P1_Q4_DEFAULT := "OTHER"
const S4_COMPLIANT := ["APPROVED", "DENIED", "DENIED"]


## Puts the game in the state at the start of day (1 to 5). gs is GameState, dd is DayDirector.
static func prepare(gs: Node, dd: Node, day: int) -> void:
	dd.start_new_game(int(gs.rng_seed))
	for d in range(1, day):
		_apply_results(gs, d)
		dd.run_overnight(d)
	dd.file_carbons()
	dd.begin_day(day)


static func _apply_results(gs: Node, d: int) -> void:
	var content: Dictionary = Content.day(d)
	var docs: Dictionary = content.get("documents", {})
	for task in content.get("tasks", []):
		var id := String(task.id)
		if task.has("transcription"):
			gs.accuracy[id] = 1.0
		elif id == "P-1":
			_blank_tokens(gs)
		elif id == "F-3":
			gs.f3_answers = {"Q1": "12", "Q2": "NO", "Q3": "NO", "Q4": ""}
			gs.f3_had_carbons = false
		elif id == "S-4":
			# S-4 has no Correct column: the choice is the player's (spec 14.10). The compliant run
			# approves application A.
			gs.stamp_results[id] = S4_COMPLIANT.duplicate()
			gs.s4_choice = _s4_choice(S4_COMPLIANT)
		elif id.begins_with("S-"):
			gs.stamp_results[id] = _correct_column(docs, id)
		elif id.begins_with("RO-"):
			_compliant_order(gs, docs, id)


static func _blank_tokens(gs: Node) -> void:
	gs.tokens_set = true
	gs.player_name_raw = ""
	gs.next_of_kin_raw = ""
	gs.fond_word = String(Content.strings().defaults.fond_word)
	gs.p1_q4 = P1_Q4_DEFAULT
	gs.signature_matches = true


static func _correct_column(docs: Dictionary, batch_id: String) -> Array:
	var out: Array = []
	var spec: Dictionary = docs.get(batch_id, {})
	for page in spec.get("pages", []):
		var correct = page.get("correct")
		out.append(String(correct) if correct != null else "NONE")
	return out


static func _s4_choice(results: Array) -> String:
	var approved: Array = []
	for i in range(results.size()):
		if results[i] == "APPROVED":
			approved.append(i)
	if approved.is_empty():
		return "NONE"
	if approved.size() > 1:
		return "MULTIPLE"
	return ["A", "B", "C"][int(approved[0])]


## Every listed entry is redacted, every other entry is not. The result is recorded the way
## DayDirector._process_order records it, so run_overnight reads the same data.
static func _compliant_order(gs: Node, docs: Dictionary, id: String) -> void:
	var spec: Dictionary = docs.get(id, {})
	var listed: Array = spec.get("listed", [])
	var entries := {}
	for e in spec.get("register", []):
		entries[String(e.key)] = listed.has(String(e.key))
	gs.ro_results[id] = {"entries": entries, "listed": listed.duplicate()}
	gs.first_stamp[id] = "PROCESSED"
