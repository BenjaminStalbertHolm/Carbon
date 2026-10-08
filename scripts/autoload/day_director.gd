extends Node
## DayDirector: day flow, the task sequence, canisters, morning memos, end of
## shift, overnight resolution and the outputs of each task (spec 13, 14.7, 8.4,
## 8.5 and 8.9). Autoload.
##
## Time is virtual. tick(delta) advances it, so headless tests can step whole
## days. Presentation listens to the signals and does the visuals (fades,
## animation, sound). Logic changes state through GameState, and stays out of
## the scene tree.

signal day_started(day: int)
signal bell_rung
signal clock_set(time: String, animate_s: float)
signal canister_arrived(doc_ids: Array)
signal task_activated(task_id: String)
signal task_completed(task_id: String)
signal task_sent(task_id: String)  # fires after completion; UnseenChanges listens
signal doc_sent(doc_id: String)
signal ghost_memo_arrived
signal ghost_sheet_due(day: int)  # D3-U3 and D4-U3 (applied by UnseenChanges)
signal end_of_shift_arrived
signal lamp_click
signal day_ended(day: int)
signal ro5_sent(desk4_redacted: bool)

const Doc := preload("res://scripts/logic/doc_model.gd")
const Content := preload("res://scripts/logic/content.gd")
const MorningMemo := preload("res://scripts/logic/morning_memo.gd")
const ClockMath := preload("res://scripts/logic/clock_math.gd")
const Redaction := preload("res://scripts/logic/redaction.gd")
const Corrections := preload("res://scripts/logic/corrections.gd")
const FondWord := preload("res://scripts/logic/fond_word.gd")
const TextNorm := preload("res://scripts/logic/text_norm.gd")

const START_BELL_AT := 4.0
const MORNING_AT := 10.0
const TASK_ARRIVAL_DELAY := 5.0
const EOS_DELAY := 5.0
const GHOST_MEMO_DELAY := 5.0
const EOS_FALLBACK := 120.0
const LAMP_DELAY := 1.5
const CLOCK_ANIM_S := 2.0
const EXTRA_CLOCK := "16:58"
const DAY_HUM_PITCH := {1: 1.0, 2: 1.0, 3: 0.99, 4: 0.98, 5: 0.965}
const DAY_NAMES := {1: "MONDAY", 2: "TUESDAY", 3: "WEDNESDAY", 4: "THURSDAY", 5: "FRIDAY"}
const FIXTURE_DESKS := {1: [1, 2], 2: [3, 4], 3: [5, 6], 4: [7, 8], 5: [9, 10], 6: [11, 12]}
const PLAYER_DESK := 4
const NAMEPLATE_LIMIT := 14

var now := 0.0
var active_task := ""
var eos_watch_active := false

var _timeline: Array = []
var _tasks: Array = []
var _task_i := -1
var _day_content: Dictionary = {}
var _spec_index: Dictionary = {}
var _eos_scheduled := false
var _ghost_memo_done := false
var _corrections: Dictionary = {}
var _reserved_words: Array = []


func _gs() -> Node:
	return get_node("/root/GameState")


func _tt() -> Node:
	return get_node("/root/TextTokens")


func _strings() -> Dictionary:
	return Content.strings()


# --- Timeline -------------------------------------------------------------------

func schedule(delay: float, fn: Callable) -> void:
	_timeline.append({"at": now + delay, "fn": fn})


func tick(delta: float) -> void:
	now += delta
	var ready := true
	while ready:
		ready = false
		var best := -1
		for i in range(_timeline.size()):
			if float(_timeline[i].at) <= now and (best < 0 or float(_timeline[i].at) < float(_timeline[best].at)):
				best = i
		if best >= 0:
			var item: Dictionary = _timeline[best]
			_timeline.remove_at(best)
			ready = true
			(item.fn as Callable).call()


func pending_events() -> int:
	return _timeline.size()


# --- Game and day flow ----------------------------------------------------------

func start_new_game(seed_value: int = -1) -> void:
	_gs().new_game(seed_value)
	_corrections = Content.load_json("res://data/corrections.json")
	begin_day(1)


## Starts a day at its beginning (spec 13.1 step 7 and 13.2). Callers handle the
## fades and any overnight resolution first (see run_overnight()).
func begin_day(day: int) -> void:
	var g := _gs()
	g.day = day
	_day_content = Content.day(day)
	_tasks = _day_content.get("tasks", [])
	_task_i = -1
	active_task = ""
	eos_watch_active = false
	_eos_scheduled = false
	_ghost_memo_done = false
	_timeline = []
	now = 0.0
	g.clock_time = "08:58"
	g.morning_done = false
	g.end_of_shift_arrived = false
	g.lamp_on = true
	g.hum_pitch = float(DAY_HUM_PITCH.get(day, 1.0))
	g.vent_on = day >= 4
	_reserved_words = _build_reserved_words()
	schedule(START_BELL_AT, _ring_start_bell)
	schedule(MORNING_AT, _morning_canister)
	day_started.emit(day)


func _ring_start_bell() -> void:
	bell_rung.emit()
	_gs().clock_time = "09:00"
	clock_set.emit("09:00", CLOCK_ANIM_S)


func _morning_canister() -> void:
	var g := _gs()
	var day: int = g.day
	var ids: Array = []
	if day >= 2:
		var memo := _build_morning_memo(day)
		g.add_doc(memo, "inbox")
		ids.append(String(memo.id))
	for doc_id in _day_content.get("morning", []):
		var doc := instantiate(String(doc_id))
		g.add_doc(doc, "inbox")
		ids.append(String(doc_id))
	_return_originals(day)
	_return_free_mail(day)
	g.contradictory_stamps = 0
	g.morning_done = true
	canister_arrived.emit(ids)
	if not _tasks.is_empty():
		schedule(TASK_ARRIVAL_DELAY, _activate_next_task)


func _activate_next_task() -> void:
	_task_i += 1
	if _task_i >= _tasks.size():
		return
	var task: Dictionary = _tasks[_task_i]
	active_task = String(task.id)
	var ids: Array = []
	for doc_id in task.get("canister", []):
		var doc := instantiate(String(doc_id))
		_gs().add_doc(doc, "inbox")
		ids.append(String(doc_id))
	canister_arrived.emit(ids)
	task_activated.emit(active_task)


## Lamp (spec 13.5). Before the End of Shift memo it only clicks.
func click_lamp() -> void:
	var g := _gs()
	lamp_click.emit()
	if not g.end_of_shift_arrived or g.day >= 5:
		return
	g.lamp_on = false
	schedule(LAMP_DELAY, end_day)


func end_day() -> void:
	day_ended.emit(_gs().day)


## Overnight resolution (spec 14.7), run during every day transition after
## Monday. Then the next day begins with begin_day().
func start_next_day() -> void:
	var prev: int = _gs().day
	run_overnight(prev)
	begin_day(prev + 1)


# --- Canister contents -----------------------------------------------------------

## Finds a document spec by id in any day file.
func _spec_for(doc_id: String) -> Dictionary:
	if _spec_index.is_empty():
		for n in range(1, 6):
			var day_docs: Dictionary = Content.day(n).get("documents", {})
			for id in day_docs.keys():
				_spec_index[String(id)] = day_docs[id]
	return _spec_index.get(doc_id, {})


## Builds a fresh copy of a document from its spec, with runtime tokens resolved.
## Orders get their register, and RO-4 gets the carried-forward block (spec 14.6).
func instantiate(doc_id: String) -> Dictionary:
	var g := _gs()
	if g.docs.has(doc_id):
		g.remove_doc(doc_id)
	var spec: Dictionary = _spec_for(doc_id).duplicate(true)
	if spec.is_empty():
		push_error("DayDirector: no document spec for %s" % doc_id)
		return Doc.new_doc(doc_id, "printed")
	if doc_id == "RO-4":
		_expand_ro4(spec)
	var st := _strings()
	return Doc.build_doc(doc_id, spec, _tt().subst_callable(), st.memo_header, String(st.memo_re_line), _app_layout())


func _app_layout() -> Array:
	return Content.layouts().app_r2.lines


func _expand_ro4(spec: Dictionary) -> void:
	var g := _gs()
	var keys: Array = []
	for c in g.carried_forward:
		keys.append(String(c.key))
	var carried_ids := ""
	for k in keys:
		carried_ids += ", " + k
	var block := ""
	if not g.carried_forward.is_empty():
		var rows: Array = [""]
		rows.append("CARRIED FORWARD FROM RO-2")
		for c in g.carried_forward:
			rows.append(String(c.row))
		block = "\n".join(rows)
	for page in spec.pages:
		var out: Array = []
		for raw in page.lines:
			var line := String(raw).replace("{CARRIED_IDS}", carried_ids)
			if line == "{CARRIED_BLOCK}":
				if block != "":
					for part in block.split("\n"):
						out.append(part)
				continue
			out.append(line)
		page.lines = out
	spec.listed = spec.get("listed", []).duplicate()
	spec.register = spec.get("register", []).duplicate(true)
	for c in g.carried_forward:
		spec.listed.append(String(c.key))
		spec.register.append({"key": c.key, "name": c.name, "entity": c.entity, "listed": true, "clerk_desk": null})


# --- Blank sheets and sending (spec 7.9, 8.4, 8.5) -----------------------------------

## Blank paper tray (spec 6.4). A transcription task gives a sheet and carbon set.
## Returns the id of the sheet now in hand, or "" when the tray is empty.
func take_blank_sheet() -> String:
	var g := _gs()
	if g.tray_count <= 0:
		return ""
	g.tray_count -= 1
	g.sheet_seq += 1
	var seq: int = g.sheet_seq
	var task := _current_task_spec()
	var sheet: Dictionary
	if task.has("transcription"):
		var sheet_id := "SHEET-%d" % seq
		var carbon_id := "CARBON-%d" % seq
		sheet = Doc.new_doc(sheet_id, "sheet", "typed", "black")
		sheet.task = active_task
		sheet.twin = carbon_id
		sheet.pages.append(Doc.new_page())
		var carbon := Doc.make_carbon(sheet, carbon_id)
		g.add_doc(sheet, "hand")
		g.add_doc(carbon, "attached")
		g.docs[sheet_id].twin = carbon_id
	else:
		sheet = Doc.new_doc("FREE-%d" % seq, "free", "typed", "black")
		sheet.pages.append(Doc.new_page())
		g.add_doc(sheet, "hand")
	if g.day == 5:
		_write_tray_line(sheet)
	return String(sheet.id)


## Spec 8.9 and 14.7 (Day 5): every blank sheet carries the typed name on line 0.
func _write_tray_line(sheet: Dictionary) -> void:
	if not _gs().flags.get("tray_line", false):
		return
	var text := String(_tt().token_values().PLAYER_NAME)
	for i in range(text.length()):
		Doc.write_glyph(sheet.pages[0], 0, i, text.substr(i, 1), _gs().rng)


func _current_task_spec() -> Dictionary:
	for t in _tasks:
		if String(t.id) == active_task:
			return t
	return {}


## Called when a sheet + carbon set leaves the typewriter (spec 7.7): the carbon
## goes to the carbon spot.
func paper_removed(sheet_id: String) -> void:
	var g := _gs()
	if not g.docs.has(sheet_id):
		return
	var sheet: Dictionary = g.docs[sheet_id]
	var twin := String(sheet.get("twin", ""))
	if twin != "" and g.docs.has(twin):
		g.place(twin, "carbon_spot")


## Sends a document by tube (spec 8.4). Outputs complete tasks. Everything else
## leaves the world, and is counted when it is a memo, cover, or returned doc.
func send_document(doc_id: String) -> void:
	var g := _gs()
	if not g.docs.has(doc_id):
		return
	var doc: Dictionary = g.docs[doc_id]
	if bool(doc.carbon):
		g.remove_doc(doc_id)
		doc_sent.emit(doc_id)
		return
	if String(doc.kind) == "ghost":
		g.remove_doc(doc_id)
		doc_sent.emit(doc_id)
		return
	if String(doc.kind) == "free":
		g.free_mail_sent.append(doc_id)
		g.place(doc_id, "removed")
		doc_sent.emit(doc_id)
		return
	var task := _current_task_spec()
	var is_output := false
	if not task.is_empty():
		if task.has("transcription") and String(doc.kind) == "sheet" and String(doc.task) == active_task:
			is_output = true
		elif String(task.get("output", "")) == doc_id:
			is_output = true
	if is_output:
		_complete_task(task, doc)
	else:
		g.misc_sent += 1
		g.remove_doc(doc_id)
	doc_sent.emit(doc_id)


func _complete_task(task: Dictionary, doc: Dictionary) -> void:
	var g := _gs()
	var id := String(task.id)
	var doc_id := String(doc.id)
	if task.has("transcription"):
		_score_transcription(id, doc)
		# T-1 to T-3 come back next morning (spec 14.8). T-4 is never returned.
		doc.returns_on = g.day + 1 if id in ["T-1", "T-2", "T-3"] else 0
		g.place(doc_id, "removed")
	else:
		match id:
			"P-1":
				_process_p1(doc)
			"F-3":
				_process_f3(doc)
			_:
				if id.begins_with("S-"):
					_process_batch(id, doc)
				elif id.begins_with("RO-"):
					_process_order(id, doc)
		g.remove_doc(doc_id)
	g.last_task_done = id
	if (g.day == 3 and id == "F-3") or (g.day == 4 and id == "T-4"):
		# D3-U3 and D4-U3 (spec 9.3). The change waits for an empty typewriter.
		g.flags["ghost_pending"] = g.day
		ghost_sheet_due.emit(g.day)
	var completed := _task_i + 1
	var total := _tasks.size()
	clock_set.emit(ClockMath.time_after_task(completed, total), CLOCK_ANIM_S)
	g.clock_time = ClockMath.time_after_task(completed, total)
	task_completed.emit(id)
	task_sent.emit(id)
	active_task = ""
	_after_task_completion(id)


func _after_task_completion(id: String) -> void:
	var g := _gs()
	if _task_i + 1 < _tasks.size():
		schedule(TASK_ARRIVAL_DELAY, _activate_next_task)
		return
	if g.day == 3 and id == "F-3":
		schedule(GHOST_MEMO_DELAY, _ghost_memo_arrive)
		return
	if g.day == 4 and id == "S-4":
		_begin_eos_watch()
		return
	if g.day == 5:
		return
	schedule(EOS_DELAY, _eos_arrive)


## Transcription accuracy (spec 7.8). The source is the text of the task's source
## document, after token substitution.
func _score_transcription(id: String, doc: Dictionary) -> void:
	var task := _current_task_spec()
	var src: Dictionary = task.transcription
	var source := _source_text(String(src.source_doc), bool(src.get("skip_first_line", false)))
	var typed := Doc.typed_text(doc.pages[0])
	_gs().accuracy[id] = TextNorm.accuracy(typed, source)


func _source_text(source_doc: String, skip_first: bool) -> String:
	var spec := _spec_for(source_doc)
	var parts: Array = []
	for page in spec.get("pages", []):
		var raw: Array = page.get("lines", page.get("paragraphs", []))
		var start := 1 if skip_first and page.has("lines") else 0
		for i in range(start, raw.size()):
			parts.append(_tt().substitute(String(raw[i])))
	return TextNorm.normalise(" ".join(parts))


## Form P-1 (spec 14.5 and 14.1): answers set the tokens and the fond word.
func _process_p1(doc: Dictionary) -> void:
	var g := _gs()
	var values := Doc.field_values(doc.pages[0])
	g.player_name_raw = String(values.get("F1", ""))
	g.next_of_kin_raw = String(values.get("F2", ""))
	g.fond_word = FondWord.compute(String(values.get("F3", "")), _reserved_words)
	g.p1_q4 = _classify_q4(String(values.get("F4", "")))
	var name_clean := TextNorm.sanitize_name(String(values.get("F1", "")))
	var sig_clean := TextNorm.sanitize_name(String(values.get("F5", "")))
	g.signature_matches = name_clean == sig_clean
	g.tokens_set = true
	g.nameplate["4"] = _tt().token_values().PLAYER_NAME.substr(0, NAMEPLATE_LIMIT)


static func _classify_q4(answer: String) -> String:
	if answer.begins_with("Y"):
		return "YES"
	if answer.begins_with("N"):
		return "NO"
	return "OTHER"


## Form F-3 (spec 14.9): the answers are stored, and carbons are noted.
func _process_f3(doc: Dictionary) -> void:
	var g := _gs()
	var values := Doc.field_values(doc.pages[0])
	g.f3_answers = {
		"Q1": String(values.get("F1", "")),
		"Q2": String(values.get("F2", "")),
		"Q3": String(values.get("F3", "")),
		"Q4": String(values.get("F4", "")),
	}
	g.f3_had_carbons = _transcription_carbons_outside_drawer() > 0


## Batch applications (spec 8.1). Each page keeps its first impression's result.
func _process_batch(id: String, doc: Dictionary) -> void:
	var g := _gs()
	var results: Array = []
	for page in doc.pages:
		var r := Doc.first_stamp_result(page)
		results.append(r if r == "APPROVED" or r == "DENIED" else "NONE")
	g.stamp_results[id] = results
	if id == "S-4":
		var approved: Array = []
		for i in range(results.size()):
			if results[i] == "APPROVED":
				approved.append(i)
		if approved.is_empty():
			g.s4_choice = "NONE"
		elif approved.size() > 1:
			g.s4_choice = "MULTIPLE"
		else:
			g.s4_choice = ["A", "B", "C"][int(approved[0])]


## Redaction orders (spec 8.2, 8.3). Each entry's redaction is recorded when the
## order is sent. The first impression's result is recorded too.
func _process_order(id: String, doc: Dictionary) -> void:
	var g := _gs()
	var page: Dictionary = doc.pages[0]
	var entries := {}
	for e in doc.register:
		entries[String(e.key)] = Redaction.entry_redacted(page, String(e.name))
	var listed: Array = doc.listed.duplicate()
	g.ro_results[id] = {"entries": entries, "listed": listed}
	g.first_stamp[id] = _classify_first(Doc.first_stamp_result(page))
	if id == "RO-2":
		_build_carried(doc, entries)
	if id == "RO-5":
		g.carbons_kept_at_final = _transcription_carbons_outside_drawer()
		var desk4_redacted := bool(entries.get("04", false))
		ro5_sent.emit(desk4_redacted)


static func _classify_first(result: String) -> String:
	match result:
		"PROCESSED":
			return "PROCESSED"
		"RETURNED":
			return "RETURNED"
		"APPROVED", "DENIED":
			return "OTHER"
		_:
			return "NONE"


## Spec 14.6: listed entries of RO-2 that are not redacted are carried forward.
## The carried row keeps the RO-2 row's columns, with the key renumbered.
func _build_carried(doc: Dictionary, entries: Dictionary) -> void:
	var g := _gs()
	var carried: Array = []
	var next_key := 8
	var rows := _printed_rows(doc.pages[0])
	for key in doc.listed:
		if bool(entries.get(String(key), false)):
			continue
		var row := String(rows.get(String(key), ""))
		var entity := ""
		var name := ""
		for e in doc.register:
			if String(e.key) == String(key):
				entity = String(e.get("entity", "") if e.get("entity") != null else "")
				name = String(e.name)
		var new_key := "%02d" % next_key
		next_key += 1
		carried.append({"key": new_key, "name": name, "entity": entity, "row": new_key + row.substr(2)})
	g.carried_forward = carried


## Printed register rows by their two-digit key, from the page's printed lines.
func _printed_rows(page: Dictionary) -> Dictionary:
	var rows := {}
	for entry in page.printed:
		var text := String(entry.text)
		if text.length() > 2 and text.substr(0, 2).is_valid_int() and text.substr(2, 1) == " ":
			rows[text.substr(0, 2)] = text
	return rows


# --- Stamps (spec 8.1) ------------------------------------------------------------

const STAMP_WORDS := {
	"APPROVED": "APPROVED",
	"DENIED": "DENIED",
	"PROCESSED": "PROCESSED",
	"RETURNED": "RETURNED — UNPROCESSED",
}


## Stamps a page of a stampable document. The first impression sets the page's
## result. A later one that differs counts as a contradiction (spec 8.1). Returns
## false when the document cannot be stamped.
func stamp_document(doc_id: String, page_index: int, result: String, x: float, y: float, rot: float, a: float) -> bool:
	var g := _gs()
	if not g.docs.has(doc_id) or not STAMP_WORDS.has(result):
		return false
	var doc: Dictionary = g.docs[doc_id]
	if not bool(doc.stampable) or page_index >= doc.pages.size():
		return false
	var page: Dictionary = doc.pages[page_index]
	var first := Doc.first_stamp_result(page)
	if first != "" and first != result:
		g.contradictory_stamps += 1
	var ink := "#8E2A22" if result == "DENIED" or result == "RETURNED" else "#2F3B5C"
	Doc.add_stamp(page, String(STAMP_WORDS[result]), result, ink, x, y, rot, a, g.rng.randi())
	return true


# --- Transcription carbons (spec 8.5) ---------------------------------------------

func _transcription_carbons_outside_drawer() -> int:
	var g := _gs()
	var count := 0
	for id in g.docs.keys():
		var d: Dictionary = g.docs[id]
		if bool(d.carbon) and String(d.origin).begins_with("SHEET") and g.location_of(String(id)) != "drawer":
			count += 1
	return count


## Filing: with the lower drawer open, the carbon spot's carbons move into the
## drawer (spec 8.5). Returns the number of carbons moved.
func file_carbons() -> int:
	var g := _gs()
	var moved := 0
	for id in g.loc.carbon_spot.duplicate():
		g.place(String(id), "drawer")
		moved += 1
	return moved


# --- Morning canister (spec 14.6 onward) -----------------------------------------

func _build_morning_memo(day: int) -> Dictionary:
	var g := _gs()
	var m: Dictionary = _strings().morning
	var inputs := {}
	match day:
		2:
			var counts := _batch_counts("S-1")
			inputs = {
				"accuracy_id": "T-1", "accuracy": float(g.accuracy.get("T-1", 1.0)),
				"batch_id": "S-1", "batch_correct": counts.correct, "batch_total": counts.total,
				"moravec_p3": _page_result("S-1", 2), "p1_q4": g.p1_q4,
				"signature_matches": g.signature_matches,
			}
		3:
			var counts3 := _batch_counts("S-2")
			inputs = {
				"accuracy_id": "T-2", "accuracy": float(g.accuracy.get("T-2", 1.0)),
				"batch_id": "S-2", "batch_correct": counts3.correct, "batch_total": counts3.total,
				"ro": _ro_summary("RO-2"),
			}
		4:
			inputs = {
				"accuracy_id": "T-3", "accuracy": float(g.accuracy.get("T-3", 1.0)),
				"ro": _ro_summary("RO-3"),
				"f3_q1": String(g.f3_answers.get("Q1", "")),
				"f3_q2": String(g.f3_answers.get("Q2", "")),
				"f3_q3": String(g.f3_answers.get("Q3", "")),
				"f3_q4_matches": String(g.f3_answers.get("Q4", "")) == String(_tt().token_values().PLAYER_NAME),
				"f3_had_carbons": g.f3_had_carbons,
			}
		5:
			inputs = {
				"ro": _ro_summary("RO-4"),
				"s4_choice": g.s4_choice,
				"ghost_deleted": bool(g.flags.get("ghost4_deleted", false)),
			}
	inputs["carbons_unfiled"] = g.carbons_unfiled_flag
	inputs["contradictions"] = g.contradictory_stamps
	var result := MorningMemo.build(day, inputs, m)
	g.p1_q4 = "NO" if bool(result.set_p1_q4_no) else g.p1_q4
	var spec := {
		"kind": "memo", "style": "typed", "ink": "red", "header": true,
		"re": String(_strings().morning_re.get("M%d" % day, "")),
		"pages": [{"lines": result.lines}],
	}
	var st := _strings()
	return Doc.build_doc("M%d" % day, spec, _tt().subst_callable(), st.memo_header, String(st.memo_re_line), _app_layout())


func _batch_counts(batch_id: String) -> Dictionary:
	var expected := _expected_results(batch_id)
	var got: Array = _gs().stamp_results.get(batch_id, [])
	var correct := 0
	for i in range(expected.size()):
		if i < got.size() and got[i] == expected[i]:
			correct += 1
	return {"correct": correct, "total": expected.size()}


func _page_result(batch_id: String, index: int) -> String:
	var got: Array = _gs().stamp_results.get(batch_id, [])
	return String(got[index]) if index < got.size() else "NONE"


## The Correct column of the batch cover table (spec 14.5 and 14.6), from the
## batch document's pages.
func _expected_results(batch_id: String) -> Array:
	var out: Array = []
	for page in _spec_for(batch_id).get("pages", []):
		out.append(String(page.get("correct", "NONE")))
	return out


func _ro_summary(ro_id: String) -> Dictionary:
	var g := _gs()
	var record: Dictionary = g.ro_results.get(ro_id, {"entries": {}, "listed": []})
	var listed: Array = record.get("listed", [])
	var redacted := 0
	for key in listed:
		if bool(record.entries.get(String(key), false)):
			redacted += 1
	return {"listed": listed.size(), "redacted": redacted, "first_stamp": String(g.first_stamp.get(ro_id, "NONE"))}


func _return_originals(day: int) -> void:
	var g := _gs()
	for id in g.loc.removed.duplicate():
		var d: Dictionary = g.docs.get(String(id), {})
		if d.is_empty() or int(d.get("returns_on", 0)) != day:
			continue
		var corr: Array = _corrections.get(String(d.task), [])
		Corrections.apply_all(d.pages[0], corr, g.rng)
		d.returns_on = 0
		g.place(String(id), "inbox")
		canister_arrived.emit([String(id)])


func _return_free_mail(day: int) -> void:
	var g := _gs()
	if day < 2:
		return
	for id in g.free_mail_sent.duplicate():
		var d: Dictionary = g.docs.get(String(id), {})
		if d.is_empty():
			continue
		d.pages[0].stamps.append({"word": "NO SUCH ADDRESSEE", "result": "NO SUCH ADDRESSEE", "ink": "red",
			"x": Doc.PAGE_W * 0.5, "y": Doc.PAGE_H / 6.0, "rot": 0.0, "a": 0.9, "seed": g.rng.randi()})
		g.place(String(id), "inbox")
	g.free_mail_sent = []


# --- End of shift, ghost memo, watch -----------------------------------------------

func _ghost_memo_arrive() -> void:
	var g := _gs()
	if _ghost_memo_done:
		return
	_ghost_memo_done = true
	var doc := instantiate("GHOST-MEMO")
	g.add_doc(doc, "inbox")
	canister_arrived.emit(["GHOST-MEMO"])
	ghost_memo_arrived.emit()
	if g.day == 3:
		eos_watch_active = true
		schedule(EOS_FALLBACK, _eos_fallback)


func _begin_eos_watch() -> void:
	eos_watch_active = true
	var g := _gs()
	if int(g.ghost_lines_done.get(str(g.day), 0)) >= 1:
		schedule(EOS_DELAY, _eos_arrive)
	schedule(EOS_FALLBACK, _eos_fallback)


## Ghost typing reports each finished line here (spec 10.3, 14.9, 14.10).
func ghost_line_finished(day: int, index: int) -> void:
	if day != _gs().day or not eos_watch_active or _eos_scheduled:
		return
	if index == 0:
		schedule(EOS_DELAY, _eos_arrive)


func _eos_fallback() -> void:
	_eos_arrive()


func _eos_arrive() -> void:
	var g := _gs()
	if _eos_scheduled or g.end_of_shift_arrived or g.day >= 5:
		return
	_eos_scheduled = true
	g.end_of_shift_arrived = true
	var doc_id := "EOS-DAY4" if g.day == 4 else "EOS-STANDARD"
	var doc := instantiate(doc_id)
	g.add_doc(doc, "inbox")
	clock_set.emit(EXTRA_CLOCK, CLOCK_ANIM_S)
	g.clock_time = EXTRA_CLOCK
	canister_arrived.emit([doc_id])
	end_of_shift_arrived.emit()


## Ghost sheet for D3-U3 and D4-U3 (spec 9.3). UnseenChanges calls this when the
## change applies. It loads into the typewriter only when the typewriter is empty
## (QUESTION-7, decided by the question agent). Returns the ghost sheet id, or ""
## when the change must keep waiting.
func apply_ghost_sheet(day: int) -> String:
	var g := _gs()
	if String(g.loc.typewriter) != "":
		return ""
	var id := "GHOST-SHEET-%d" % day
	var doc := Doc.new_doc(id, "ghost", "typed", "black")
	doc.pages.append(Doc.new_page())
	g.add_doc(doc, "typewriter")
	g.flags["ghost_pending"] = 0
	return id


# --- Overnight resolution (spec 14.7) --------------------------------------------------

func run_overnight(prev_day: int) -> void:
	var g := _gs()
	# 1. Unfiled carbons.
	g.carbons_unfiled_flag = _transcription_carbons_outside_drawer() > 0
	# 2. Delete the lower drawer.
	for id in g.loc.drawer.duplicate():
		g.remove_doc(String(id))
	# 3. Ghost sheet on the typewriter.
	var tw := String(g.loc.typewriter)
	if tw != "" and g.docs.has(tw) and String(g.docs[tw].kind) == "ghost":
		var delete := prev_day == 4 and int(g.ghost_lines_done.get("4", 0)) >= 3
		if delete:
			g.flags["ghost4_deleted"] = true
			g.remove_doc(tw)
		else:
			g.place(tw, "read_stack")
	# 3b. A ghost change still pending at day end: the blank sheet goes on top of the read stack.
	if int(g.flags.get("ghost_pending", 0)) == prev_day:
		var pending_id := "GHOST-SHEET-%d" % prev_day
		var pending := Doc.new_doc(pending_id, "ghost", "typed", "black")
		pending.pages.append(Doc.new_page())
		g.add_doc(pending, "read_stack")
		g.flags["ghost_pending"] = 0
	# 4. Redaction world effects for orders sent this day.
	var order := "RO-%d" % prev_day
	if g.ro_results.has(order):
		var record: Dictionary = g.ro_results[order]
		for e in _register_of(order):
			if not bool(e.get("listed", false)) or e.get("entity") == null or String(e.entity) == "":
				continue
			if bool(record.entries.get(String(e.key), false)) and not g.redacted_names.has(String(e.entity)):
				g.redacted_names.append(String(e.entity))
	# 5. Clerk effects for RO-3 (3 to 4) and RO-4 (4 to 5).
	if prev_day == 3 or prev_day == 4:
		_apply_clerk_effects("RO-%d" % prev_day)
	# 6. H. VANCE: Desk 12's nameplate goes blank when RO-3 redacts him.
	if prev_day == 3 and g.redacted_names.has("vance"):
		g.nameplate["12"] = ""
	# 7. Day 5 desk removals for clerks redacted on RO-3.
	if prev_day == 4:
		for e in _register_of("RO-3"):
			if e.get("clerk_desk") != null and bool(g.ro_results.get("RO-3", {}).get("entries", {}).get(String(e.key), false)):
				g.desk_removed[str(int(e.clerk_desk))] = true
	# 8. Refill the blank paper tray.
	g.tray_count = 10
	# 9. Day-start unseen changes that always apply (spec 9.3 D2-U1, D5-U1).
	var new_day := prev_day + 1
	if new_day == 2:
		g.nameplate["12"] = "0411"
	if new_day == 5:
		g.flags["tray_line"] = true
	# 10. Quota board and fixtures.
	g.flags["quota_occupied"] = _occupied_desks()
	if new_day == 5:
		for f in FIXTURE_DESKS.keys():
			var served: Array = FIXTURE_DESKS[f]
			var any := false
			for desk in served:
				if _seated_occupant(int(desk)):
					any = true
			g.fixture_lit[str(f)] = any
	# 11. Document drift (spec 8.14).
	_apply_drift(new_day)
	# 12. Hum pitch and vent: set in begin_day().
	# 13. Per-day counters: contradictory stamps reset after the morning memo.


func _register_of(order_id: String) -> Array:
	var spec := _spec_for(order_id)
	var out: Array = []
	if order_id == "RO-4":
		out = spec.get("register", []).duplicate(true)
		for c in _gs().carried_forward:
			out.append({"key": c.key, "name": c.name, "entity": c.entity, "listed": true, "clerk_desk": null})
		return out
	return spec.get("register", [])


func _apply_clerk_effects(order_id: String) -> void:
	var g := _gs()
	var record: Dictionary = g.ro_results.get(order_id, {"entries": {}, "listed": []})
	for e in _register_of(order_id):
		if e.get("clerk_desk") == null or not bool(e.get("listed", false)):
			continue
		var desk := int(e.clerk_desk)
		if bool(record.entries.get(String(e.key), false)):
			g.clerk_present[str(desk)] = false
			g.nameplate[str(desk)] = ""
			g.redacted_desks.append(desk)
		else:
			g.clerk_faces_player[str(desk)] = true
			g.refused_desks.append(desk)


## A desk is occupied when a clerk is seated there, or the player is at Desk 4.
## Desk 12 never counts (spec 8.11, 8.12).
func _seated_occupant(desk: int) -> bool:
	var g := _gs()
	if desk == PLAYER_DESK:
		return true
	if desk == 12:
		return false
	return bool(g.clerk_present.get(str(desk), false))


func _occupied_desks() -> int:
	var n := 0
	for desk in range(1, 13):
		if _seated_occupant(desk):
			n += 1
	return n


func _apply_drift(day: int) -> void:
	var drift: Dictionary = Content.load_json("res://data/day1.json").get("drift", {})
	var key := "day%d" % day
	if not drift.has(key):
		return
	var g := _gs()
	if not g.docs.has("M1-WELCOME"):
		return
	var from := String(drift[key].from)
	var to := String(drift[key].to)
	for entry in g.docs["M1-WELCOME"].pages[0].printed:
		entry.text = String(entry.text).replace(from, to)


## Reserved words for the fond-word rule (spec 14.1): whole words of T-3's source,
## T-4's source, and the printed text of RO-3, RO-4, F-3, S-4 and P-1D.
func _build_reserved_words() -> Array:
	var lines: Array = []
	for id in ["ST-3", "L-4", "RO-3", "RO-4", "F-3", "S-4", "P-1D"]:
		var spec := _spec_for(id)
		for page in spec.get("pages", []):
			lines.append_array(page.get("lines", []))
			lines.append_array(page.get("paragraphs", []))
	lines.append_array(Content.layouts().app_r2.lines)
	return FondWord.reserved_words_from(lines)


func _app_layout_lines() -> Array:
	return _app_layout()
