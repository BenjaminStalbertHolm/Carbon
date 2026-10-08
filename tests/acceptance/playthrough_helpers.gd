extends RefCounted
## Logic-level playthrough steps for the spec 20 acceptance tests (2, 3, 7, 9). Each method is one thing the
## player does, sent through the real DayDirector and GameState. Typing goes through a real TypewriterModel
## (the same model TypewriterView drives). No scene is needed. This file is not a headless test (it does not
## extend SceneTree), so the runner does not run it. Tests preload it:
##   const Play := preload("res://tests/acceptance/playthrough_helpers.gd")

const DocModel := preload("res://scripts/logic/doc_model.gd")
const Redaction := preload("res://scripts/logic/redaction.gd")
const CadenceModel := preload("res://scripts/logic/cadence_model.gd")
const TypewriterModel := preload("res://scripts/logic/typewriter_model.gd")

## The player's answers on P-1 (spec 14.5). The name is what the tokens and the Desk 4 nameplate then show.
const NAME := "ANNA MARIA TESTER"
const KIN := "JOHN TESTER"

var gs: Node
var dd: Node
var tw: TypewriterModel
var now := 0.0  # ms, on the clock the typewriter model is ticked with


func _init(game_state: Node, day_director: Node) -> void:
	gs = game_state
	dd = day_director
	tw = TypewriterModel.new(CadenceModel.new(), gs.rng)


## Types text as the player does: one key at a time, Enter between wrapped lines (spec 7.3).
func type_text(text: String) -> void:
	var lines := DocModel.wrap_text(text, DocModel.COLS)
	for li in range(lines.size()):
		if li > 0:
			tw.enter(now)
			now += 150.0
		for ch in String(lines[li]):
			tw.type_key(ch, now)
			now += 150.0
			tw.tick(now)


## Puts a sheet or form in the typewriter, with the carbon it is attached to (spec 7.5, 8.5). The model
## settings match TypewriterView.load_sheet: fluid, retired word from Day 3, Day 5 substitution (spec 14.12).
func load_sheet(doc_id: String) -> void:
	var doc: Dictionary = gs.docs[doc_id]
	var carbon: Dictionary = {}
	var twin := String(doc.get("twin", ""))
	if twin != "" and gs.docs.has(twin):
		carbon = gs.docs[twin]
	gs.place(doc_id, "typewriter")
	var opts: Dictionary = dd.sheet_options(doc_id)
	tw.retired_active = int(gs.day) >= 3
	tw.fond_word = String(gs.fond_word)
	tw.field_substitution = opts.get("field_substitution", {})
	tw.field_bar = opts.get("field_bar", {})
	tw.load_sheet(doc, carbon)


## The player lifts the sheet off the typewriter (its carbon goes to the carbon spot, spec 7.7), and sends it.
func remove_and_send(doc_id: String) -> void:
	tw.unload()
	dd.paper_removed(doc_id)
	gs.place(doc_id, "hand")
	dd.send_document(doc_id)


## A form: the answers go in the fields (spec 7.4), then the form is removed and sent.
func form(doc_id: String, answers: Dictionary) -> void:
	load_sheet(doc_id)
	var page: Dictionary = gs.docs[doc_id].pages[0]
	for fid in ["F1", "F2", "F3", "F4", "F5"]:
		if not answers.has(fid):
			continue
		var field := DocModel.field_by_id(page, fid)
		tw.click_cell(int(field.line), int(field.col), now)
		type_text(String(answers[fid]))
	remove_and_send(doc_id)


## A transcription (spec 7.8): takes a blank sheet and types its source text. The typewriter has no em dash
## key (spec 7.2), so the player types a hyphen for it. Returns the id of the sheet.
func transcription(source_doc: String, skip_first: bool) -> String:
	var sid: String = dd.take_blank_sheet()
	load_sheet(sid)
	type_text(String(dd._source_text(source_doc, skip_first)).replace("—", "-"))
	remove_and_send(sid)
	return sid


## A batch (spec 8.1): each page is stamped with its result, then the batch is sent.
func batch(batch_id: String, results: Array) -> void:
	for i in range(results.size()):
		dd.stamp_document(batch_id, i, String(results[i]), 300.0, 400.0, 0.0, 0.9)
	dd.send_document(batch_id)


## A redaction order (spec 8.2): the named entries are barred, the first page is stamped, and the order is sent.
## Returns the names that were not printed on the order.
func order(order_id: String, redact: Array, stamp: String) -> Array:
	var page: Dictionary = gs.docs[order_id].pages[0]
	var missing: Array = []
	for name in redact:
		var ext := Redaction.name_extent(page, String(name))
		if ext.is_empty():
			missing.append(String(name))
			continue
		DocModel.add_bar(page, int(ext[0]), float(ext[1]), float(ext[2]))
	dd.stamp_document(order_id, 0, stamp, 300.0, 400.0, 0.0, 0.9)
	dd.send_document(order_id)
	return missing


## The end of a day (spec 13.5): carbons are filed into the drawer when file_carbons is true, the lamp is
## clicked, and after its delay the overnight resolution runs and the next day begins.
func end_day(file_carbons: bool) -> void:
	if file_carbons:
		dd.file_carbons()
	dd.click_lamp()
	dd.tick(1.5)
	dd.start_next_day()


## The printed lines of a document on its first page.
func printed_lines(doc_id: String) -> Array:
	var out: Array = []
	for entry in gs.docs[doc_id].pages[0].printed:
		out.append(String(entry.text))
	return out


## Transcription carbons outside the lower drawer (spec 8.5, 15.1). Counted from GameState, not from DayDirector.
func transcription_carbons_kept() -> int:
	var n := 0
	for id in gs.docs.keys():
		var d: Dictionary = gs.docs[id]
		if bool(d.carbon) and String(d.origin).begins_with("SHEET") and gs.location_of(String(id)) != "drawer":
			n += 1
	return n


## What the day start shows of the clerks, the carbons and the redactions (spec 8.9, 8.11, 14.7).
func snapshot() -> Dictionary:
	return {
		"day": int(gs.day),
		"faces": gs.clerk_faces_player.duplicate(),
		"refused": gs.refused_desks.duplicate(),
		"present": gs.clerk_present.duplicate(),
		"redacted": gs.redacted_names.duplicate(),
		"carried": gs.carried_forward.duplicate(true),
		"carbons_kept": transcription_carbons_kept(),
	}


## Days 1 to 4 of the refusal run (spec 20 tests 2, 3 and 7). Every transcription is typed accurately and every
## order is stamped RETURNED. redact_ro3 lists the RO-3 entries that are barred (empty for the refusal run).
## file_carbons files each day's carbons into the drawer before the lamp. Starts a new game (seed 412) and ends
## with Day 5 begun and its morning done. Returns {snaps: day -> snapshot at that day's start, ro4_rows: the
## printed lines of RO-4 while it is on the desk}.
func run_days_1_to_4(file_carbons: bool, redact_ro3: Array) -> Dictionary:
	var snaps := {}
	dd.start_new_game(412)
	dd.tick(4.0)
	dd.tick(6.0)
	dd.tick(5.0)
	# Day 1
	form("P-1", {"F1": NAME, "F2": KIN, "F3": "LANTERN", "F4": "NO", "F5": NAME})
	dd.tick(5.0)
	transcription("L-1", false)
	dd.tick(5.0)
	batch("S-1", ["APPROVED", "DENIED", "APPROVED", "DENIED", "APPROVED"])
	dd.tick(5.0)
	end_day(file_carbons)
	snaps[2] = snapshot()
	# Day 2
	dd.tick(10.0)
	dd.tick(5.0)
	transcription("C-22", true)
	dd.tick(5.0)
	order("RO-2", [], "RETURNED")
	dd.tick(5.0)
	batch("S-2", ["DENIED", "APPROVED", "DENIED", "DENIED"])
	dd.tick(5.0)
	end_day(file_carbons)
	snaps[3] = snapshot()
	# Day 3
	dd.tick(10.0)
	dd.tick(5.0)
	transcription("ST-3", false)
	dd.tick(5.0)
	order("RO-3", redact_ro3, "RETURNED")
	dd.tick(5.0)
	form("F-3", {"F1": "12", "F2": "NO", "F3": "NO", "F4": NAME})
	dd.tick(5.0)
	dd.tick(125.0)
	end_day(file_carbons)
	snaps[4] = snapshot()
	# Day 4
	dd.tick(10.0)
	dd.tick(5.0)
	transcription("L-4", false)
	dd.tick(5.0)
	var ro4_rows := printed_lines("RO-4")
	order("RO-4", [], "RETURNED")
	dd.tick(5.0)
	batch("S-4", ["APPROVED", "DENIED", "DENIED"])
	dd.tick(125.0)
	end_day(file_carbons)
	snaps[5] = snapshot()
	# Day 5
	dd.tick(10.0)
	return {"snaps": snaps, "ro4_rows": ro4_rows}
