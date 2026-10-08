extends RefCounted
## The typewriter as a pure, time-driven model (spec 7, 8.5, 8.8, 10.2, 10.3).
## Presentation calls the input methods and tick(now_ms), then reads the events
## the model emits with take_events(). Glyphs go straight into the page
## Dictionaries of the loaded documents, and carbons are mirrored cell by cell.
##
## Times are milliseconds from any monotonic clock. Tests pass them explicitly.
## Event types (dictionary key "t"):
##   key {ch, ghost}             a glyph was written (clack sound, key animation)
##   jam {}                      key_jam
##   bell {ghost}                bell
##   carriage {line, col, ms}    carriage moves to a new cell over ms
##   return {line, col, ghost}   carriage return sound and motion (0.35 s)
##   ratchet {count}             platen_ratchet per line passed
##   backspace {}                backspace_click
##   fluid {line, col}           fluid_brush (correction fluid used)

const DocModel := preload("res://scripts/logic/doc_model.gd")
const CadenceModel := preload("res://scripts/logic/cadence_model.gd")

const ENTER := CadenceModel.ENTER
const ACCEPTED_PUNCT := ".,-'/?:;()&\"! "
const BELL_COLUMN := 58
const FLUID_LOCK_MS := 2000.0
const JAM_LOCK_MS := 3000.0
const JAM_BELL_GAP_MS := 300.0
const JAM_X_START_MS := 600.0
const X_STEP_MS := 120.0
const RETURN_MS := 350.0

var original := {}  # the loaded document (reference)
var carbon := {}  # the carbon of the loaded original, or {}
var page := {}  # the loaded page (reference into original.pages)
var carbon_page := {}  # the carbon page (reference), or {}
var line := 0
var col := 0
var fluid_uses := 12
var retired_active := false  # Day 3 onward (spec 8.8)
var fond_word := ""

var cadence: CadenceModel = null
var rng: RandomNumberGenerator = null

var _events: Array = []
var _cell_lock := {}  # "line:col" -> ms until which the cell refuses glyphs
var _locked_until := -1.0  # retired-word lock (spec 8.8)
var _run_text := ""
var _run_cells: Array = []  # Array of [line, col] for the current letter run
var _pending: Array = []  # Array of {at: float, op: String, args: Dictionary}
var _ghost_queue: Array = []  # Array of {op: "type", ch} or {op: "x", line, col}
var _ghost_running := false
var _ghost_next_at := 0.0
var _ghost_prev := ""


func _init(cadence_model: CadenceModel = null, rng_ref: RandomNumberGenerator = null) -> void:
	cadence = cadence_model if cadence_model != null else CadenceModel.new()
	rng = rng_ref if rng_ref != null else RandomNumberGenerator.new()


func is_loaded() -> bool:
	return not page.is_empty()


func is_locked(now: float) -> bool:
	return now < _locked_until


## Loads a sheet (spec 7.5). The carriage starts at the first field's first
## cell for forms, and at (0, 0) otherwise. carbon_doc may be {}.
func load_sheet(doc: Dictionary, carbon_doc: Dictionary) -> void:
	original = doc
	carbon = carbon_doc
	page = doc.pages[0]
	carbon_page = carbon_doc.pages[0] if not carbon_doc.is_empty() else {}
	line = 0
	col = 0
	if not page.fields.is_empty():
		line = int(page.fields[0].line)
		col = int(page.fields[0].col)
	_run_text = ""
	_run_cells = []
	_pending = []
	_ghost_queue = []
	_ghost_running = false


## Removes the sheet from the machine and returns the original document.
func unload() -> Dictionary:
	var d := original
	original = {}
	carbon = {}
	page = {}
	carbon_page = {}
	_pending = []
	_ghost_queue = []
	_ghost_running = false
	return d


func take_events() -> Array:
	var out := _events
	_events = []
	return out


# --- Player input -------------------------------------------------------------

## A typed key (spec 7.2 and 7.3). raw is the key's unicode character.
func type_key(raw: String, now: float) -> void:
	if not is_loaded():
		return
	if raw.length() != 1:
		return
	var ch := raw.to_upper()
	if not _accepted(ch):
		return
	if is_locked(now):
		_emit({"t": "jam"})
		return
	if _cell_locked(now):
		_emit({"t": "jam"})
		return
	if col >= DocModel.COLS:
		_emit({"t": "jam"})
		return
	if not page.fields.is_empty() and _field_at(line, col).is_empty():
		_emit({"t": "jam"})
		return
	var letter := _is_letter(ch)
	var before := [line, col]
	_write(ch, now, false)
	if letter and retired_active:
		_run_text += ch
		_run_cells.append(before)
	if cadence != null:
		cadence.record(ch, now)
	if retired_active and not letter:
		_finish_run(now)


## Enter (spec 7.4 and 7.5). A form moves to the next field's start. From the
## last field, Enter does nothing. Otherwise the carriage returns and the line
## advances. At line 53, Enter plays key_jam and does nothing.
func enter(now: float) -> void:
	if not is_loaded():
		return
	if is_locked(now):
		_emit({"t": "jam"})
		return
	if retired_active:
		_finish_run(now)
	if not page.fields.is_empty():
		var nxt := _next_field_start(line, col)
		if nxt.is_empty():
			return
		_return_to(int(nxt[0]), int(nxt[1]), now, false)
	else:
		if line >= DocModel.LINES - 1:
			_emit({"t": "jam"})
			return
		_return_to(line + 1, 0, now, false)
	if cadence != null:
		cadence.record(ENTER, now)


func backspace(now: float) -> void:
	if not is_loaded():
		return
	if retired_active:
		_finish_run(now)
	_emit({"t": "backspace"})
	if col > 0:
		col -= 1


## Platen knob: line -1 or +1, clamped to 0..53. Column unchanged (spec 7.4).
func platen(delta: int) -> void:
	if not is_loaded():
		return
	var target := clampi(line + delta, 0, DocModel.LINES - 1)
	if target != line:
		line = target
		_emit({"t": "ratchet", "count": 1})


## Clicking a cell inside a form field moves the carriage to the field start
## (spec 7.5). Clicks on free paper do nothing.
func click_cell(target_line: int, target_col: int, now: float) -> void:
	if not is_loaded() or page.fields.is_empty():
		return
	var f := _field_at(target_line, target_col)
	if f.is_empty():
		return
	var fl := int(f.line)
	var fc := int(f.col)
	var lines_passed := absi(fl - line)
	if fl != line or fc != col:
		_emit({"t": "ratchet", "count": lines_passed, "ms": 400.0 if lines_passed > 0 else 0.0})
		line = fl
		col = fc
		_emit({"t": "carriage", "line": line, "col": col, "ms": 400.0})


## Correction fluid on a cell (spec 7.6). Returns true when it was used.
func fluid_at(target_line: int, target_col: int, now: float) -> bool:
	if not is_loaded() or fluid_uses <= 0:
		return false
	DocModel.whiteout(page, target_line, target_col, rng)
	if not carbon_page.is_empty():
		var ccell := DocModel.cell(carbon_page, target_line, target_col)
		ccell.g = []
		ccell.w = true
		ccell.ws = int(DocModel.cell(page, target_line, target_col).ws)
	_cell_lock[DocModel.cell_key(target_line, target_col)] = now + FLUID_LOCK_MS
	fluid_uses -= 1
	_emit({"t": "fluid", "line": target_line, "col": target_col})
	return true


# --- Ghost typing (spec 10.2, 10.3) ---------------------------------------------

## Adds a string to the ghost queue. A newline becomes ENTER.
func enqueue_ghost_text(text: String) -> void:
	for i in range(text.length()):
		var ch := text.substr(i, 1)
		_ghost_queue.append({"op": "type", "ch": ENTER if ch == "\n" else ch.to_upper()})


## Adds an X over each given cell, in the given order (spec 10.3).
func enqueue_ghost_x(cells: Array) -> void:
	for c in cells:
		_ghost_queue.append({"op": "x", "line": int(c[0]), "col": int(c[1])})


func ghost_set_running(running: bool, now: float) -> void:
	if running and not _ghost_running:
		_ghost_next_at = now + _ghost_delay_for_next()
	_ghost_running = running


func ghost_pending() -> bool:
	return not _ghost_queue.is_empty()


## Advances timed work: pending jam steps and the ghost queue (spec 8.8, 10.2).
func tick(now: float) -> void:
	_pending.sort_custom(func(a, b): return a.at < b.at)
	while not _pending.is_empty() and float(_pending[0].at) <= now:
		var item: Dictionary = _pending.pop_front()
		_run_pending(item, now)
	if _ghost_running and not _ghost_queue.is_empty() and now >= _ghost_next_at:
		var op: Dictionary = _ghost_queue.pop_front()
		_run_ghost(op, now)
		if not _ghost_queue.is_empty():
			_ghost_next_at = now + _ghost_delay_for_next()


# --- Internals ----------------------------------------------------------------

func _emit(event: Dictionary) -> void:
	_events.append(event)


func _accepted(ch: String) -> bool:
	var c := ch.unicode_at(0)
	if c >= 65 and c <= 90:
		return true
	if c >= 48 and c <= 57:
		return true
	return ACCEPTED_PUNCT.contains(ch)


static func _is_letter(ch: String) -> bool:
	var c := ch.unicode_at(0)
	return c >= 65 and c <= 90


func _cell_locked(now: float) -> bool:
	var k := DocModel.cell_key(line, col)
	return _cell_lock.has(k) and now < float(_cell_lock[k])


## The field whose cells contain (target_line, target_col), or {}.
func _field_at(target_line: int, target_col: int) -> Dictionary:
	for f in page.fields:
		if int(f.line) == target_line and target_col >= int(f.col) and target_col < int(f.col) + int(f.len):
			return f
	return {}


## Next field start in reading order after the current carriage position, or [].
func _next_field_start(cur_line: int, cur_col: int) -> Array:
	var best: Array = []
	for f in page.fields:
		var fl := int(f.line)
		var fc := int(f.col)
		var after := fl > cur_line or (fl == cur_line and fc > cur_col)
		if after and (best.is_empty() or fl < int(best[0]) or (fl == int(best[0]) and fc < int(best[1]))):
			best = [fl, fc]
	return best


## Writes one glyph at the carriage (spec 7.3 steps 1 to 4). Mirrors to the carbon
## (spec 8.5). ghost marks glyphs written by ghost typing (no cadence capture).
func _write(ch: String, now: float, ghost: bool) -> void:
	var c := DocModel.cell(page, line, col)
	var glyph := DocModel.make_glyph(ch, rng, "black")
	if c.g.size() < DocModel.MAX_GLYPHS:
		c.g.append(glyph)
	if not carbon_page.is_empty():
		var cc := DocModel.cell(carbon_page, line, col)
		if cc.g.size() < DocModel.MAX_GLYPHS:
			var copy := glyph.duplicate()
			copy.ink = "carbon"
			cc.g.append(copy)
	_emit({"t": "key", "ch": ch, "ghost": ghost})
	if col == BELL_COLUMN:
		_emit({"t": "bell", "ghost": ghost})
	col += 1


func _return_to(target_line: int, target_col: int, now: float, ghost: bool) -> void:
	line = target_line
	col = target_col
	_emit({"t": "return", "line": line, "col": col, "ghost": ghost})


## Spec 8.8: a run of letters that equals the fond word jams the machine.
func _finish_run(now: float) -> void:
	var run := _run_text
	var cells := _run_cells.duplicate()
	_run_text = ""
	_run_cells = []
	if fond_word == "" or run != fond_word:
		return
	_emit({"t": "jam"})
	_pending.append({"at": now + JAM_BELL_GAP_MS - 300.0, "op": "bell", "args": {}})
	_pending.append({"at": now + JAM_BELL_GAP_MS, "op": "bell", "args": {}})
	_locked_until = now + JAM_LOCK_MS
	var saved_line := line
	var saved_col := col
	var t := now + JAM_X_START_MS
	for i in range(cells.size() - 1, -1, -1):
		_pending.append({"at": t, "op": "x", "args": {"line": int(cells[i][0]), "col": int(cells[i][1])}})
		t += X_STEP_MS
	_pending.append({"at": t, "op": "return", "args": {"line": saved_line, "col": saved_col}})


func _run_pending(item: Dictionary, now: float) -> void:
	match String(item.op):
		"bell":
			_emit({"t": "bell", "ghost": false})
		"x":
			var target_line := int(item.args.line)
			var target_col := int(item.args.col)
			line = target_line
			col = target_col
			_emit({"t": "carriage", "line": line, "col": col, "ms": X_STEP_MS})
			_write_overstrike_x(now)
		"return":
			_return_to(int(item.args.line), int(item.args.col), now, false)


func _write_overstrike_x(now: float) -> void:
	var c := DocModel.cell(page, line, col)
	var glyph := DocModel.make_glyph("X", rng, "black")
	if c.g.size() < DocModel.MAX_GLYPHS:
		c.g.append(glyph)
	if not carbon_page.is_empty():
		var cc := DocModel.cell(carbon_page, line, col)
		if cc.g.size() < DocModel.MAX_GLYPHS:
			var copy := glyph.duplicate()
			copy.ink = "carbon"
			cc.g.append(copy)
	_emit({"t": "key", "ch": "X", "ghost": true})


func _run_ghost(op: Dictionary, now: float) -> void:
	if String(op.op) == "type":
		var ch := String(op.ch)
		_ghost_prev = ch
		if ch == ENTER:
			if line >= DocModel.LINES - 1:
				_emit({"t": "jam"})
				return
			_return_to(line + 1, 0, now, true)
			return
		if col >= DocModel.COLS:
			_emit({"t": "jam"})
			return
		_write(ch, now, true)
	else:
		line = int(op.line)
		col = int(op.col)
		_emit({"t": "carriage", "line": line, "col": col, "ms": X_STEP_MS})
		_write_overstrike_x(now)
		_ghost_prev = "X"


func _ghost_delay_for_next() -> float:
	if _ghost_queue.is_empty() or cadence == null:
		return 0.0
	var nxt: Dictionary = _ghost_queue[0]
	if String(nxt.op) == "x":
		return X_STEP_MS
	return cadence.delay_for(_ghost_prev, String(nxt.ch), rng)
