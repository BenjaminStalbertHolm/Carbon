extends SceneTree
## M5 headless checks (spec 7, 8.5, 8.8, 10.3, 11.1): the typewriter view driven through its
## input methods (type_char, type_enter, click_cell, use_fluid, eject_sheet) with a fake clock.
## Run: godot --headless --path /home/user/Carbon --script res://tests/typewriter/m5_test.gd
## Exit 0 only when every check passes. Prints "M5: N checks, M failures".

const DocModel := preload("res://scripts/logic/doc_model.gd")
const CadenceModel := preload("res://scripts/logic/cadence_model.gd")
const TypewriterView := preload("res://scripts/typewriter/typewriter_view.gd")

var _checks := 0
var _fails := 0
var _gs = null
var _view = null


var _ran := false


## Autoloads are inside the tree from the first frame, so the checks run in _process.
func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run()
		print("M5: %d checks, %d failures" % [_checks, _fails])
		quit(0 if _fails == 0 else 1)
	return false


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


func _calls_named(name: String) -> Array:
	var out: Array = []
	for c in _view.sounds().calls:
		if String(c[0]) == name:
			out.append(c)
	return out


func _count_named(name: String) -> int:
	return _calls_named(name).size()


func _sheet(id: String, kind: String, fields: Array = []) -> Dictionary:
	var doc := DocModel.new_doc(id, kind, "typed", "black")
	var page := DocModel.new_page()
	for f in fields:
		page.fields.append(f)
	doc.pages.append(page)
	return doc


func _cell_glyphs(page: Dictionary, line: int, col: int) -> int:
	return DocModel.cell(page, line, col).g.size()


func _new_view() -> void:
	_gs = root.get_node("GameState")
	_gs.new_game(777)
	_gs.day = 1
	_gs.fond_word = "BOTTLE"
	_gs.fluid_uses = 12
	_view = TypewriterView.new()
	root.add_child(_view)
	_view.model.cadence = CadenceModel.new()
	_view.use_fake_clock(100000.0)
	_view.sounds().silent = true
	_view.sounds().recording = true
	_view.held_kind_fn = func(): return ""
	_view.held_id_fn = func(): return ""


func _load(doc: Dictionary, twin: Dictionary = {}) -> bool:
	if _view.is_loaded():
		_view.unload_sheet()
	_gs.add_doc(doc, "hand")
	if not twin.is_empty():
		_gs.add_doc(twin, "attached")
	# A correction fluid lock is per cell and outlives the sheet (TypewriterModel keeps
	# _cell_lock across loads), so a new sheet starts after the 2.0 s lock has passed.
	_view.advance(2100)
	return _view.load_sheet(String(doc.id))


var _released: Array = []


func _release_stub() -> String:
	_released.append("document")
	return "document"


func _page_of(id: String) -> Dictionary:
	return _gs.docs[id].pages[0]


func _run() -> void:
	_new_view()
	_check(root.get_node_or_null("DayDirector") != null, "autoloads present (DayDirector)")

	# --- Typing basics (spec 7.2 to 7.4) -------------------------------------------------
	_check(_load(_sheet("TEST-A", "sheet")), "load a blank sheet")
	_check(_view.is_loaded() and _view.loaded_doc_id() == "TEST-A", "view reports the loaded sheet")
	_check(_gs.location_of("TEST-A") == "typewriter", "loaded sheet sits in the typewriter location")
	_view.type_char("h")
	_view.advance(180)
	_view.type_char("i")
	var pa := _page_of("TEST-A")
	_check(DocModel.cell_char(pa, 0, 0) == "H" and DocModel.cell_char(pa, 0, 1) == "I", "lowercase keys are typed as uppercase (spec 7.2)")
	_check(_view.model.col == 2 and _view.model.line == 0, "carriage advances one column per key")
	_check(_count_named("key_clack") == 2, "each accepted key plays key_clack")
	_check(_calls_named("key_clack")[0][1] == 0.0 and _calls_named("key_clack")[0][2] == true, "player key_clack has no ghost gain and is player-caused")
	_view.type_char("#")
	_check(_view.model.col == 2 and _count_named("key_clack") == 2, "a rejected character does nothing and makes no sound (spec 7.2)")
	_view.type_enter()
	_check(_view.model.line == 1 and _view.model.col == 0, "Enter returns the carriage and advances the line (spec 7.4)")
	_check(_count_named("carriage_return") == 1, "Enter plays carriage_return")
	_view.type_char("X")
	_view.type_backspace()
	_check(_view.model.col == 0 and DocModel.cell_char(pa, 1, 0) == "X", "Backspace moves back and does not erase (spec 7.4)")
	_check(_count_named("backspace_click") == 1, "Backspace plays backspace_click")
	_view.type_platen(-1)
	_check(_view.model.line == 0, "Up moves the platen one line back")
	_view.type_platen(-1)
	_check(_view.model.line == 0, "Up is clamped at line 0")
	for i in range(60):
		_view.type_platen(1)
	_check(_view.model.line == 53, "Down is clamped at line 53")
	_check(_count_named("platen_ratchet") >= 1, "platen moves play platen_ratchet")
	_view.model.line = 0
	_view.model.col = 0

	# --- Overstrike (spec 6.5) -----------------------------------------------------------
	_view.model.line = 5
	_view.model.col = 0
	_view.type_char("A")
	_view.type_backspace()
	_view.type_char("B")
	_view.type_backspace()
	_view.type_char("C")
	_check(_cell_glyphs(pa, 5, 0) == 3 and DocModel.cell_char(pa, 5, 0) == "C", "a cell holds three overstruck glyphs, last one shown")
	_view.type_backspace()
	_view.type_char("D")
	_check(_cell_glyphs(pa, 5, 0) == 3 and DocModel.cell_char(pa, 5, 0) == "C", "a fourth glyph in the same cell is ignored (spec 6.5)")

	# --- 64 columns, bell at column 58 (spec 7.3) ----------------------------------------
	_check(_load(_sheet("TEST-B", "sheet")), "load a second sheet")
	_view.model.line = 10
	_view.model.col = 0
	_view.sounds().calls.clear()
	for i in range(64):
		_view.type_char("A")
	_check(_view.model.col == 64, "the carriage stops at column 64 after 64 characters")
	_check(_count_named("bell") >= 1, "the bell rings at column 58 (spec 7.3 step 6)")
	_view.type_char("Z")
	_check(_view.model.col == 64 and _count_named("key_jam") >= 1, "a key at column 64 plays key_jam and writes nothing (spec 7.3 step 7)")

	# --- Forms: field limits, Enter, clicks (spec 7.5) -------------------------------------
	var f1 := {"id": "F1", "line": 2, "col": 5, "len": 4}
	var f2 := {"id": "F2", "line": 4, "col": 0, "len": 5}
	_check(_load(_sheet("FORM-1", "form", [f1, f2])), "load a form with two fields")
	_check(_view.model.line == 2 and _view.model.col == 5, "a form starts the carriage at its first field (spec 7.5)")
	for ch in ["A", "B", "C", "D"]:
		_view.type_char(ch)
	var pf := _page_of("FORM-1")
	_check(DocModel.field_value(pf, f1) == "ABCD", "field F1 value reads its cells (spec 7.5)")
	_view.type_char("E")
	_check(_view.model.col == 9 and _count_named("key_jam") >= 2, "a character past the field's last cell jams (spec 7.5)")
	_view.type_enter()
	_check(_view.model.line == 4 and _view.model.col == 0, "Enter inside a form moves to the next field's start")
	_view.type_char("A")
	_view.type_char(" ")
	_view.type_char(" ")
	_view.type_char("B")
	_check(DocModel.field_value(pf, f2) == "A B", "field values collapse internal runs of spaces (spec 7.5)")
	_check(_view.model.col == 4, "the carriage advances inside field F2")
	_view.type_enter()
	_check(_view.model.line == 4, "Enter from the last field does nothing (spec 7.5)")
	_view.sounds().calls.clear()
	_view.click_cell(2, 6)
	_check(_view.model.line == 2 and _view.model.col == 5, "a left-click inside a field moves the carriage to its start (spec 7.5)")
	_view.advance(500)
	_check(_count_named("platen_ratchet") == 2, "moving two lines plays platen_ratchet per line passed (spec 7.5)")
	_view.sounds().calls.clear()
	_view.advance(500)
	_check(_count_named("platen_ratchet") == 0, "the carriage jump queues its clicks at the click time")
	_view.click_cell(0, 0)
	_check(_view.model.line == 2 and _view.model.col == 5, "a click on free paper on a form does nothing")

	# --- Correction fluid (spec 7.6) -----------------------------------------------------
	_check(_load(_sheet("TEST-C", "sheet")), "load a third sheet")
	var pc := _page_of("TEST-C")
	_view.model.line = 0
	_view.model.col = 0
	for ch in ["H", "E", "L", "L", "O"]:
		_view.type_char(ch)
	_view.sounds().calls.clear()
	_check(_view.use_fluid(0, 1), "correction fluid on a glyph is used")
	_check(DocModel.cell(pc, 0, 1).g.is_empty() and bool(DocModel.cell(pc, 0, 1).w), "fluid clears the cell and marks a blob (spec 7.6)")
	_check(_gs.fluid_uses == 11 and _view.model.fluid_uses == 11, "fluid uses are kept in step with GameState (12 to 11)")
	_check(_count_named("fluid_brush") == 1, "fluid plays fluid_brush")
	_view.model.line = 0
	_view.model.col = 1
	_view.type_char("Z")
	_check(DocModel.cell(pc, 0, 1).g.is_empty(), "a cell under fluid refuses glyphs for 2.0 s (key plays key_jam)")
	_view.advance(2100)
	_view.model.col = 1
	_view.type_char("Z")
	_check(DocModel.cell_char(pc, 0, 1) == "Z", "after drying, typing writes over the blob (spec 7.6)")
	_gs.fluid_uses = 1
	_view.model.fluid_uses = 1
	_check(_view.use_fluid(0, 2) and _gs.fluid_uses == 0, "the last fluid use is spent")
	_check(not _view.use_fluid(0, 3) and _gs.fluid_uses == 0, "with no uses left, fluid does nothing")

	# --- Retired word (spec 8.8) ---------------------------------------------------------
	_gs.day = 2
	_check(_load(_sheet("TEST-N", "sheet")), "load a sheet on Day 2")
	_view.sounds().calls.clear()
	_view.model.line = 0
	_view.model.col = 0
	for ch in ["B", "O", "T", "T", "L", "E", " "]:
		_view.type_char(ch)
	_check(_count_named("key_jam") == 0, "the retired word does nothing before Day 3 (spec 8.8)")
	_gs.day = 3
	_check(_load(_sheet("TEST-D", "sheet")), "load a sheet on Day 3")
	_check(_view.model.retired_active and _view.model.fond_word == "BOTTLE", "from Day 3 the typewriter tracks the retired word")
	_view.sounds().calls.clear()
	_view.model.line = 0
	_view.model.col = 0
	for ch in ["B", "O", "T", "T", "L", "E"]:
		_view.type_char(ch)
	_view.type_char(" ")
	var pd: Dictionary = _page_of("TEST-D")
	_check(_count_named("key_jam") >= 1, "the retired word jams the typewriter (spec 8.8 step 1)")
	_check(_view.model.is_locked(_view._now()), "typing is locked for 3.0 s after the jam")
	_view.type_char("Q")
	_check(_view.model.col == 7 and DocModel.cell_char(pd, 0, 7) == " ", "a key during the lock plays key_jam and does nothing")
	_view.advance(400)
	_check(_count_named("bell") == 2, "two bells, 0.3 s apart (spec 8.8 step 1)")
	_view.advance(250)
	_check(DocModel.cell_char(pd, 0, 5) == "X", "X overstrikes start at 600 ms, rightmost cell first")
	_check(DocModel.cell_char(pd, 0, 0) == "B", "the leftmost cell is not struck yet")
	_view.advance(120)
	_check(DocModel.cell_char(pd, 0, 4) == "X" and DocModel.cell_char(pd, 0, 0) == "B", "the next X is one cell left after 120 ms")
	_view.advance(120 * 5 + 400)
	_check(DocModel.cell_char(pd, 0, 0) == "X", "every cell of the word is struck, left cell last")
	_check(_view.model.col == 7 and _view.model.line == 0, "the carriage returns to its pre-lock position")
	_check(_count_named("carriage_return") >= 1, "the return plays carriage_return")
	_view.advance(3000)
	_view.type_char("K")
	_check(DocModel.cell_char(pd, 0, 7) == "K", "typing works again after the lock")

	# --- Carbon mirror (spec 8.5) ---------------------------------------------------------
	if _view.is_loaded():
		_view.unload_sheet()
	_gs.fluid_uses = 5  # set after the unload, which syncs the old model count
	var sheet_e := _sheet("TEST-E", "sheet")
	sheet_e.twin = "CARBON-E"
	var carbon_e := DocModel.make_carbon(sheet_e, "CARBON-E")
	_check(_load(sheet_e, carbon_e), "load a sheet with its carbon")
	_view.model.line = 0
	_view.model.col = 0
	_view.type_char("A")
	_view.type_char("B")
	var ce: Dictionary = _gs.docs["CARBON-E"].pages[0]
	_check(DocModel.cell_char(ce, 0, 0) == "A" and DocModel.cell_char(ce, 0, 1) == "B", "every glyph is mirrored to the carbon in the same cell")
	_check(String(DocModel.cell(ce, 0, 0).g[0].ink) == "carbon", "the mirrored glyph has the carbon ink")
	_view.use_fluid(0, 0)
	_check(DocModel.cell(ce, 0, 0).g.is_empty() and bool(DocModel.cell(ce, 0, 0).w), "fluid on the original whites out the carbon cell too")
	_check(_gs.docs["CARBON-E"].pages[0].bars.is_empty(), "carbons carry no bars (spec 8.7)")

	# --- Ghost typing (spec 10.2, 11.1) -----------------------------------------------------
	_check(_load(_sheet("TEST-F", "ghost")), "load a ghost sheet")
	_view.sounds().calls.clear()
	_view.model.line = 0
	_view.model.col = 0
	_view.model.enqueue_ghost_text("HI")
	_view.model.ghost_set_running(true, _view._now())
	# Ghost delays follow the recorded key gaps (spec 10.2), which reach 1.5 s here. The
	# model runs one ghost step per tick, and the view ticks once per frame, so step in 50 ms frames.
	for i in range(120):
		_view.advance(50)
	var pg := _page_of("TEST-F")
	_check(DocModel.cell_char(pg, 0, 0) == "H" and DocModel.cell_char(pg, 0, 1) == "I", "ghost text is typed onto the sheet")
	var ghost_clacks := 0
	for c in _calls_named("key_clack"):
		if float(c[1]) == -20.0 and not bool(c[2]):
			ghost_clacks += 1
	_check(ghost_clacks == 2, "ghost key_clack gets -20 dB and is not player-caused (spec 11.1)")

	# --- Eject and open (spec 7.7, 6.4 hooks) ----------------------------------------------
	var sheet_h := _sheet("TEST-H", "sheet")
	sheet_h.twin = "CARBON-H"
	var carbon_h := DocModel.make_carbon(sheet_h, "CARBON-H")
	_check(_load(sheet_h, carbon_h), "load a sheet with a carbon for the release test")
	_view.sounds().calls.clear()
	var held_log: Array = []
	_view.held_hold_fn = func(kind, id): held_log.append([kind, id])
	_check(_view.open_typing_view("") and _view.is_typing(), "a click with a sheet loaded enters the typing view (spec 6.4)")
	var released: String = _view.eject_sheet()
	_check(released == "TEST-H", "the release lever returns the loaded sheet (spec 7.7)")
	_check(_gs.location_of("TEST-H") == "hand", "the player holds the released sheet")
	_check(_gs.loc.carbon_spot.has("CARBON-H"), "the carbon goes to the carbon spot (spec 8.5)")
	_check(not _view.is_loaded() and _count_named("paper_out") == 1, "the release plays paper_out and empties the typewriter")
	_check(held_log.size() == 1 and held_log[0][1] == "TEST-H", "the released sheet goes into the hand through the hook")
	_view.advance(700)
	_check(not _view.is_typing(), "after the 0.6 s slide the view is back in free view")

	_gs.add_doc(_sheet("TEST-G", "free"), "hand")
	_view.held_kind_fn = func(): return "document"
	_view.held_id_fn = func(): return "TEST-G"
	_view.held_release_fn = _release_stub
	_released.clear()
	_check(_view.open_typing_view("TEST-G") and _view.is_loaded(), "a held free sheet loads when the typewriter is clicked")
	_check(_released.size() == 1, "the loaded sheet is released from the hand")
	_check(_gs.location_of("TEST-G") == "typewriter", "the loaded sheet moves to the typewriter location")
	_view.advance(700)
	_check(_view.is_typing(), "after the 0.6 s slide-in the view is in the typing view")
	_check(_view.open_typing_view("") == false, "opening again while typing does nothing")
	_view.close_typing_view()
	_view.advance(10)
	_check(not _view.is_typing() and _view.is_loaded(), "Esc leaves the typing view and the paper stays loaded (spec 6.3)")

	_view.unload_sheet()
	_check(not _view.open_typing_view(""), "a click with no paper loaded does nothing (spec 6.3)")
	_check(not _view.load_sheet("NO-SUCH-DOC"), "loading an unknown document fails")
	_check(not _view.model.is_loaded(), "the model is empty after the sheet leaves the typewriter")
