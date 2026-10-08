extends SceneTree
## Acceptance test 9 (spec 20): ghost typing on Day 3 (spec 10.2, 10.3, 9.3 D3-U3). The player types F-3 on the
## typewriter; the ghost sheet then arrives (D3-U3, once the typewriter has been unseen 1.5 s), and looking away from
## the typewriter for 6 s starts line 1, IS THIS HOW YOU TYPE. Looking back stops it mid-line. Looking away for 6 s
## again resumes it at the same character. This test runs in real time, because GhostTyper reads the engine clock
## (Time.get_ticks_msec) for its cadence. The real Gaze, UnseenChanges and GhostTyper run from their own callbacks, with
## a fake camera that the test turns. Checked:
##   - the ghost sheet loads into the typewriter view's model once the typewriter has been unseen 1.5 s;
##   - no ghost key is typed in the first 5.5 s away, and the first one comes at 6.0 s (within 0.6 s);
##   - looking back stops the typing (no key in the 2 s after the stop), before the end of the line;
##   - looking away for 6 s again resumes at the same character, and the line completes as written.
## What the player sees on screen, and the cadence itself, are MANUAL (see tests/ACCEPTANCE.md).
## Headless (about 25 s):
##   godot --headless --path . --script res://tests/acceptance/test_ghost_look_away.gd
## Prints one PASS or FAIL line per check, then "RESULT: PASS, N failure(s)". Exit 0 only when N is 0.

const DebugDays := preload("res://scripts/debug/debug_day_defaults.gd")
const Play := preload("res://tests/acceptance/playthrough_helpers.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")
const GhostTyper := preload("res://scripts/world/ghost_typer.gd")
const GazeScript := preload("res://scripts/autoload/gaze.gd")
const HallC := preload("res://scripts/world/hall_c.gd")
const Content := preload("res://scripts/logic/content.gd")

const LINE := "IS THIS HOW YOU TYPE"
const LINE_SPEC := "IS THIS HOW YOU TYPE"
## The player at Desk 4, 1.5 m south of the typewriter (spec 6.1), facing north at it.
const EYE := Vector3(5.25, 1.2, 5.0)
const TRIGGER_S := 6.0
const SHEET_S := 1.5
const TOL := 0.6

var _checks := 0
var _failures := 0
var _ran := false
var _gs
var _gaze
var _un
var _tw_node: Node3D
var _cam: Camera3D
var _model  # the typewriter model: the one the typing view holds, which the ghost typer writes on
var _ghost_keys := 0
var _sheet_loaded := false


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _run() -> void:
	_gs = root.get_node("GameState")
	_un = root.get_node("UnseenChanges")
	_gaze = root.get_node("Gaze")
	var dd = root.get_node("DayDirector")

	var holder := Node3D.new()
	root.add_child(holder)
	var hall: Node3D = HallC.build(holder, {})
	_un.bind_hall(hall)
	_tw_node = hall.find_child("Typewriter04", true, false)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_gaze.set_camera(_cam)

	# Day 3 as the player has it after RO-3: F-3 is typed and sent. Its task_sent makes the ghost sheet pending.
	DebugDays.prepare(_gs, dd, 3)
	dd.tick(10.0)
	dd.tick(5.0)
	var run := Play.new(_gs, dd)
	run.transcription("ST-3", false)
	dd.tick(5.0)
	run.order("RO-3", [], "RETURNED")
	dd.tick(5.0)
	run.form("F-3", {"F1": "12", "F2": "NO", "F3": "NO", "F4": Play.NAME})
	_model = run.tw
	var ghost_typer := GhostTyper.new()
	root.add_child(ghost_typer)
	ghost_typer.setup(_model, _tw_node)
	_check(String(Content.strings().ghost_lines["3"][0]) == LINE_SPEC, "test 9: Day 3 ghost line 1 is IS THIS HOW YOU TYPE (spec 10.3)")
	_check(_row("D3-U3")["pending"] and not _row("D3-U3")["applied"], "test 9: the ghost sheet change is pending once F-3 is sent")

	# The player is at the typewriter: the sheet cannot arrive while it is in view.
	_cam.look_at_from_position(EYE, GazeScript.world_aabb(_tw_node).get_center(), Vector3.UP)
	await _wait(0.5)
	_check(not _sheet_loaded and _ghost_keys == 0, "test 9: nothing is typed while the typewriter is in view")

	# Look away: the ghost sheet arrives once the typewriter has been unseen 1.5 s.
	var t0 := _now()
	_look_away()
	var sheet_ok: bool = await _until(func(): return _sheet_loaded, 4.0)
	var sheet_s := _now() - t0
	_check(sheet_ok and absf(sheet_s - SHEET_S) <= TOL,
		"test 9: the ghost sheet loads in the typewriter after 1.5 s unseen (at %.2f s)" % sheet_s)
	_check(String(_model.original.get("kind", "")) == "ghost", "test 9: the loaded sheet is the Day 3 ghost sheet")

	# The first ghost key comes when the typewriter has been unseen 6.0 s.
	await _wait(TRIGGER_S - 0.5 - (_now() - t0))
	_check(_ghost_keys == 0, "test 9: no ghost key in the first 5.5 s away")
	var typed: bool = await _until(func(): return _ghost_keys > 0, 4.0)
	var start_s := _now() - t0
	_check(typed and absf(start_s - TRIGGER_S) <= TOL,
		"test 9: looking away for 6 s starts the ghost typing (first key at %.2f s)" % start_s)
	_check(_prefix_matches(_ghost_keys), "test 9: the first characters typed are the start of line 1")

	# Let it type, then look back: the typing stops at once.
	await _wait(2.0)
	var mid := _ghost_keys
	_check(mid > 0 and mid < LINE.length(), "test 9: the line is typing in the middle when the player looks back (%d of %d)" % [mid, LINE.length()])
	_look_at_typewriter()
	await _wait(0.5)
	var stopped := _ghost_keys
	await _wait(2.0)
	_check(_ghost_keys == stopped, "test 9: looking back stops the ghost typing (no key in the 2 s after)")
	_check(stopped < LINE.length() and _prefix_matches(stopped), "test 9: it stopped mid-line, after the characters already typed")

	# Look away for 6 s again: the same line resumes from the same character, and finishes.
	_look_away()
	await _wait(TRIGGER_S - 0.5)
	_check(_ghost_keys == stopped, "test 9: no ghost key in the 5.5 s after the look away, before the next trigger")
	var resumed: bool = await _until(func(): return _ghost_keys > stopped, 4.0)
	_check(resumed and _prefix_matches(_ghost_keys), "test 9: after the next 6 s away the line resumes at the same character")
	var done: bool = await _until(func(): return int(_gs.ghost_lines_done.get("3", 0)) >= 1, 8.0)
	_check(done and _ghost_keys == LINE.length(), "test 9: the line completes once the typing has resumed (%d keys)" % _ghost_keys)
	_check(_row_text(0, LINE.length()) == LINE, "test 9: the sheet reads IS THIS HOW YOU TYPE on its first line, as written")

	print("ACCEPTANCE TEST 9 (ghost typing on Day 3): %d checks, %d failure(s)" % [_checks, _failures])
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _now() -> float:
	return Time.get_ticks_msec() / 1000.0


func _look_away() -> void:
	_cam.look_at_from_position(EYE, EYE + Vector3(0.0, 0.0, 1.0), Vector3.UP)


func _look_at_typewriter() -> void:
	_cam.look_at_from_position(EYE, GazeScript.world_aabb(_tw_node).get_center(), Vector3.UP)


## Waits for seconds, pumping the typewriter model on the same clock GhostTyper uses (spec 7.3, 10.2).
func _wait(seconds: float) -> void:
	var end := _now() + seconds
	while _now() < end:
		await process_frame
		_pump()


## Waits until pred is true, or timeout seconds. Returns whether pred became true.
func _until(pred: Callable, timeout: float) -> bool:
	var end := _now() + timeout
	while not bool(pred.call()) and _now() < end:
		await process_frame
		_pump()
	return bool(pred.call())


func _pump() -> void:
	_sync_ghost_sheet()
	var ms := float(Time.get_ticks_msec())
	_model.tick(ms)
	for ev in _model.take_events():
		if String(ev.get("t", "")) == "key" and bool(ev.get("ghost", false)):
			_ghost_keys += 1


## The typewriter view loads a ghost sheet placed on the typewriter (spec 9.3 D3-U3). Here the test does that load.
func _sync_ghost_sheet() -> void:
	if _sheet_loaded or _model.is_loaded():
		return
	var id := String(_gs.loc.typewriter)
	if id == "" or not _gs.docs.has(id) or String(_gs.docs[id].kind) != "ghost":
		return
	_model.load_sheet(_gs.docs[id], {})
	_sheet_loaded = true


## The first n characters of the ghost line are on the sheet's first line, in order.
func _prefix_matches(n: int) -> bool:
	if not _sheet_loaded:
		return false
	return _row_text(0, n) == LINE.substr(0, n)


func _row_text(line: int, n: int) -> String:
	var page: Dictionary = _model.original.pages[0]
	var out := ""
	for k in range(n):
		out += DocModel.cell_char(page, line, k)
	return out


func _row(id: String) -> Dictionary:
	for row in _un.status():
		if String(row.id) == id:
			return row
	return {}
