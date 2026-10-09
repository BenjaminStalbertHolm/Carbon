extends SceneTree
## Text assist in the typing view (spec 6.5, 16.3) and Esc during the camera tween (spec 6.3, 12).
## Real time, in Hall C with the typing camera. Checks, one PASS or FAIL line each:
##   - with the setting off, the overlay is not visible in the typing view;
##   - with the setting on, it is visible, to the right of the paper and inside the window at 1280x960
##     and at 640x480, and the paper stays inside the window at both sizes;
##   - its rows are the paper's typed text (a typed line is sampled, and the next line follows the next key);
##   - Esc 0.1 s after the typing view opens (during the 0.5 s tween in) is queued: the view reaches the
##     typing pose, then closes after the exit tween, and the key does not reach the menu;
##   - without Esc the typing view stays open after the tween;
##   - Esc pressed while the sheet is still sliding in (0.6 s, the load) is queued the same way.
## The pipeline is a stub that presents the internal picture at window size (the real PsxPipeline makes
## the dummy renderer print mesh errors headless). Headless (about 8 s):
##   godot --headless --path /home/user/Carbon --script res://tests/typewriter/test_text_assist_typing.gd
## Prints one PASS or FAIL line per check, then "RESULT: PASS, N failure(s)". Exit 0 only when N is 0.

const DocModel := preload("res://scripts/logic/doc_model.gd")
const DocRenderer := preload("res://scripts/doc/doc_renderer.gd")
const TypewriterView := preload("res://scripts/typewriter/typewriter_view.gd")
const HallC := preload("res://scripts/world/hall_c.gd")

const EYE := Vector3(5.25, 1.2, 5.0)
const TIMEOUT_S := 4.0
const WINDOW_BIG := Vector2i(1280, 960)
const WINDOW_SMALL := Vector2i(640, 480)

var _checks := 0
var _failures := 0
var _ran := false
var _gs
var _view
var _stub
var _probe
var _opened_ms := -1
var _closed_ms := -1


## Stands in for PsxPipeline: the internal resolution is the window size, so the presentation is 1:1.
class StubPipeline extends Node:
	func current_resolution() -> Vector2i:
		return Vector2i(get_window().size)

	func set_focus_view(_active: bool) -> void:
		pass


## Records the Esc presses that reach unhandled input, that is, the ones the typing view did not take.
class EscProbe extends Node:
	var esc := 0

	func _unhandled_input(event: InputEvent) -> void:
		var k := event as InputEventKey
		if k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			esc += 1


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


func _sheet(id: String) -> Dictionary:
	var doc := DocModel.new_doc(id, "sheet", "typed", "black")
	doc.pages.append(DocModel.new_page())
	return doc


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _wait(sec: float) -> void:
	await create_timer(sec).timeout


## Waits until cond holds, for at most limit_s seconds. Returns cond's last value.
func _until(cond: Callable, limit_s: float) -> bool:
	var end := Time.get_ticks_msec() + int(limit_s * 1000.0)
	while not bool(cond.call()):
		if Time.get_ticks_msec() > end:
			return false
		await process_frame
	return true


func _on_opened() -> void:
	_opened_ms = Time.get_ticks_msec()


func _on_closed() -> void:
	_closed_ms = Time.get_ticks_msec()


func _reset_stamps() -> void:
	_opened_ms = -1
	_closed_ms = -1


## One Esc press and release, sent as real key events.
func _press_esc() -> void:
	for pressed in [true, false]:
		var ev := InputEventKey.new()
		ev.keycode = KEY_ESCAPE
		ev.physical_keycode = KEY_ESCAPE
		ev.pressed = pressed
		Input.parse_input_event(ev)


func _setup() -> void:
	root.size = WINDOW_BIG
	_gs = root.get_node("GameState")
	_gs.new_game(777)
	_gs.day = 1
	_gs.fond_word = "BOTTLE"
	_gs.fluid_uses = 12
	_stub = StubPipeline.new()
	root.add_child(_stub)
	var holder := Node3D.new()
	root.add_child(holder)
	var hall: Node3D = HallC.build(holder, {})
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.05
	cam.far = 30.0
	holder.add_child(cam)
	var tw := hall.find_child("Typewriter04", true, false) as Node3D
	cam.look_at_from_position(EYE, tw.global_position, Vector3.UP)
	cam.current = true
	_view = TypewriterView.new()
	root.add_child(_view)
	_view.setup(hall, cam, _stub)
	_view.sounds().silent = true
	_view.held_kind_fn = func(): return ""
	_view.held_id_fn = func(): return ""
	_view.opened.connect(_on_opened)
	_view.closed.connect(_on_closed)
	_probe = EscProbe.new()
	root.add_child(_probe)
	_gs.add_doc(_sheet("TA-1"), "hand")
	_view.load_sheet("TA-1")


## Opens the typing view on the loaded sheet and waits for the typing pose.
func _open_and_wait() -> bool:
	_reset_stamps()
	_view.open_typing_view("")
	return await _until(func(): return _view.is_typing(), TIMEOUT_S)


func _close_and_wait() -> void:
	_view.close_typing_view()
	await _until(func(): return not _view.is_typing() and _view._phase == TypewriterView.PH_FREE, TIMEOUT_S)
	await _frames(2)


## The paper and the overlay on screen at the current window size (spec 6.5: the overlay is beside the paper).
func _check_layout(tag: String) -> void:
	await _frames(3)
	var screen := Rect2(Vector2.ZERO, root.get_visible_rect().size)
	var paper: Rect2 = _view._paper_window_rect()
	var panel := Rect2(_view._assist.position, _view._assist.size)
	_check(paper.size.x > 0.0 and paper.size.y > 0.0, "%s: the paper is on screen in the typing view" % tag)
	_check(screen.encloses(paper), "%s: the paper stays inside the window (%s in %s)" % [tag, str(paper), str(screen)])
	_check(_view._assist.visible, "%s: the overlay is visible" % tag)
	_check(panel.position.x >= paper.end.x and screen.encloses(panel),
		"%s: the overlay is to the right of the paper and inside the window (%s)" % [tag, str(panel)])


func _run() -> void:
	await _frames(2)
	_setup()
	await _frames(2)

	# --- Setting off (spec 16.3: default OFF) ----------------------------------------------
	_view.text_assist_override = 0
	var opened: bool = await _open_and_wait()
	_check(opened, "the typing view opens on the loaded sheet")
	await _frames(3)
	_check(not _view._assist.visible, "with the setting off, the text assist overlay is not visible in the typing view")
	await _close_and_wait()

	# --- Setting on: placement at both window sizes (spec 6.5) -----------------------------
	_view.text_assist_override = 1
	await _open_and_wait()
	root.size = WINDOW_BIG
	await _check_layout("1280x960")
	root.size = WINDOW_SMALL
	await _check_layout("640x480")
	root.size = WINDOW_BIG
	await _frames(3)

	# --- Text: the paper's typed text, and the updates as the player types -----------------
	_check(_view._assist.rows().is_empty() or String(_view._assist.rows()[0]) == "", "before typing, the overlay has no text")
	for ch in String("THE QUICK BROWN FOX"):
		_view.type_char(ch)
	await _frames(2)
	var page: Dictionary = _view.model.original.pages[0]
	var line0 := DocRenderer.row_text(page, 0).rstrip(" ")
	var rows: Array = _view._assist.rows()
	_check(line0.begins_with("THE QUICK BROWN FOX"), "the typed line is on the paper: %s" % line0)
	_check(not rows.is_empty() and String(rows[0]) == line0, "the overlay's first row is the paper's typed line (%s)" % (String(rows[0]) if not rows.is_empty() else "none"))

	_view.type_enter()
	for ch in String("JUMPS OVER"):
		_view.type_char(ch)
	await _frames(2)
	var line1 := DocRenderer.row_text(page, 1).rstrip(" ")
	rows = _view._assist.rows()
	_check(rows.size() >= 2 and String(rows[1]) == line1 and line1 == "JUMPS OVER", "the overlay follows the keys: the second line reads the paper's text (%s)" % line1)
	await _close_and_wait()
	_check(not _view._assist.visible, "after the view closes, the overlay is hidden again")

	# --- Esc 0.1 s after the view opens (the 0.5 s tween in), spec 6.3 --------------------
	_view.text_assist_override = 0
	_probe.esc = 0
	_reset_stamps()
	var t0 := Time.get_ticks_msec()
	_view.open_typing_view("")
	await _wait(0.1)
	_press_esc()
	var closed: bool = await _until(func(): return _closed_ms >= 0, TIMEOUT_S)
	await _frames(2)
	_check(_opened_ms - t0 >= 450, "the typing pose is reached only after the 0.5 s tween (at %d ms)" % (_opened_ms - t0))
	_check(closed and _closed_ms - _opened_ms >= 450, "Esc pressed during the tween closes the view after the tween finishes")
	_check(not _view.is_typing() and _view._phase == TypewriterView.PH_FREE and _view.is_loaded(), "the view is closed and the paper stays loaded")
	_check(_probe.esc == 0, "the Esc is taken by the typing view and does not reach the menu")

	# Control: without Esc the view stays open after its tween.
	await _open_and_wait()
	await _wait(0.6)
	_check(_view.is_typing(), "without Esc the typing view stays open after the tween")
	await _close_and_wait()

	# --- Esc while the sheet is still sliding in (the 0.6 s load before the tween) ----------
	_view.unload_sheet()
	_gs.add_doc(_sheet("TA-2"), "hand")
	_probe.esc = 0
	_reset_stamps()
	t0 = Time.get_ticks_msec()
	_view.open_typing_view("TA-2")
	await _wait(0.1)
	_press_esc()
	closed = await _until(func(): return _closed_ms >= 0, TIMEOUT_S)
	await _frames(2)
	_check(closed and _opened_ms - t0 >= 1000, "Esc during the slide-in: the view opens after the slide and the tween, then closes")
	_check(not _view.is_typing() and _probe.esc == 0, "Esc during the slide-in does not reach the menu and leaves the view closed")

	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(0 if _failures == 0 else 1)
