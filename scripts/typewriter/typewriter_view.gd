extends Node
## TypewriterView: the Desk 4 typewriter as a presentation of TypewriterModel
## (spec 6.3, 6.4, 7, 8.5, 8.8). It owns the loaded sheet's paper quad, the carriage,
## the platen and the keys, the typing camera and the typing view's input. The rules
## stay in TypewriterModel (scripts/logic/typewriter_model.gd): this view feeds it
## keys and clicks, draws the events it emits, and keeps GameState in step (sheet
## location, fluid_uses).
##
## This node stays in the main scene tree (not under the PsxPipeline SubViewport),
## so it receives window input. The typing camera is a Camera3D added to the hall
## root, inside the pipeline world.
##
## Text assist (spec 6.5, 16.3): in the typing view, a plain panel to the right of the paper shows the
## same text (TextAssist, the same helper as the read view). It follows SaveSystem's "text_assist"
## setting, and the text_assist property when SaveSystem has none.
##
## Setup: add this node to the main tree, then setup(hall, player_camera, pipeline).
## Entry points for the interaction (M3):
##   open_typing_view(doc_id = "") -> bool  Typewriter click. With a sheet loaded, enters the
##                                          typing view. Otherwise loads doc_id (the held
##                                          sheet or form, released from the hand) with the
##                                          0.6 s slide-in, then enters. Returns false when
##                                          there is nothing to show.
##   close_typing_view()                    Esc (spec 6.3): free view, the paper stays loaded.
##   is_typing() -> bool
##   is_loaded() -> bool, loaded_doc_id() -> String
## Hooks, set by the main controller as Callables (the held item is M3's):
##   held_kind_fn: () -> String   ("" when the hand is empty; "fluid", "document", ...)
##   held_id_fn: () -> String     (the held document id)
##   held_hold_fn: (kind, id)     (puts an item in the hand)
##   held_release_fn: () -> String (returns the hand to its home; returns the kind)
## Signals: opened, closed, sheet_loaded(doc_id), sheet_released(doc_id) (spec 7.7).
##
## While a sheet is loaded and the view is closed, the model is still ticked, so ghost
## typing (spec 10.3) runs and plays its sounds. Times come from Time.get_ticks_msec(),
## so Cadence (spec 10.1) sees the real key timing. Tests call use_fake_clock() and
## advance().

const TypewriterModel := preload("res://scripts/logic/typewriter_model.gd")
const CadenceModel := preload("res://scripts/logic/cadence_model.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")
const DocRenderer := preload("res://scripts/doc/doc_renderer.gd")
const PaperQuad := preload("res://scripts/doc/paper_quad.gd")
const TypewriterSounds := preload("res://scripts/typewriter/typewriter_sounds.gd")
const TextTex := preload("res://scripts/world/text_texture.gd")
const TextAssistScript := preload("res://scripts/doc/text_assist.gd")

signal opened
signal closed
signal sheet_loaded(doc_id: String)
signal sheet_released(doc_id: String)

const LOADABLE_KINDS := ["sheet", "free", "form", "ghost"]
const LOAD_MS := 600.0
const EJECT_MS := 600.0
const CAM_MS := 500.0
const PAN_MS := 300.0
const KEY_DOWN_MS := 30.0
const KEY_UP_MS := 60.0
const KEY_TRAVEL := 0.004
const CARRIAGE_STEP := 0.004
const CARRIAGE_CLAMP := 0.20
const CARRIAGE_CENTRE := 32.0
const RETURN_MS := 350.0
const LINES_PER_TURN := 54.0
const PAPER_W := 0.21
const PAPER_H := 0.297
const TYPE_DISTANCE := 0.36
const LEVER_PICK_PX := 26.0
const LOAD_OFFSET := Vector3(0.0, 0.12, 0.10)
const EJECT_OFFSET := Vector3(0.0, 0.30, 0.12)
const INTERNAL_RES := Vector2(320, 240)
## Text assist panel placement and wheel step, the same as ReadView (spec 6.5).
const ASSIST_GAP := 16.0
const ASSIST_MAX_W := 360.0
const ASSIST_MIN_W := 160.0
const ASSIST_SCROLL_STEP := 60.0

const PH_FREE := 0
const PH_LOADING := 1
const PH_CAM_IN := 2
const PH_TYPING := 3
const PH_EJECT := 4
const PH_CAM_OUT := 5

var model: TypewriterModel = TypewriterModel.new()
var held_kind_fn := Callable()
var held_id_fn := Callable()
var held_hold_fn := Callable()
var held_release_fn := Callable()

var _sounds := TypewriterSounds.new()
var _renderer = null
var _hall: Node = null
var _typewriter: Node3D = null
var _carriage: Node3D = null
var _platen: Node3D = null
var _paper: MeshInstance3D = null
var _lever: Node3D = null
var _copyholder: Node3D = null
var _cam: Camera3D = Camera3D.new()
var _player_cam: Camera3D = null
var _pipeline: Node = null
var _keys := {}  # legend character -> {node: Node3D, rest: float, t: float}
var _carriage_rest := Vector3.ZERO
var _paper_rest := Vector3.ZERO
var _platen_basis := Basis.IDENTITY

var _phase := PH_FREE
var _phase_t := 0.0
var _loaded := false
var _sheet_id := ""
var _dirty := false
var _fake := false
var _fake_now := 0.0
var _saved_player_xf := Transform3D.IDENTITY
var _cam_from := Transform3D.IDENTITY
var _cam_to := Transform3D.IDENTITY
var _cam_t := 0.0
var _cam_dur := 0.0
var _cam_done := ""
var _panning := false
var _paper_dir := 0
var _paper_t := 0.0
var _paper_dur := 0.0
var _vis_col := 0.0
var _car_from := 0.0
var _car_t := 0.0
var _car_ms := 0.0
var _vis_line := 0.0
var _pl_from := 0.0
var _pl_t := 0.0
var _pl_ms := 0.0
var _platen_extra := 0.0
var _esc_queued := false  # Esc pressed during the load or the tween in; the exit runs at the typing pose
var _assist_layer: CanvasLayer = null
var _assist: Control = null
var _assist_dirty := true  # the paper text changed since the panel last showed it
var _assist_scroll := 0.0

## Used when SaveSystem has no "text_assist" setting (spec 16.3).
var text_assist := false
## Dev override for tests and screenshots: -1 uses the setting, 0 off, 1 on.
var text_assist_override := -1


func _ready() -> void:
	_renderer = DocRenderer.new()
	add_child(_renderer)
	_assist_layer = CanvasLayer.new()
	_assist_layer.layer = 2  # above the pipeline's presentation layer (layer 1)
	add_child(_assist_layer)
	_assist = TextAssistScript.new()
	_assist.visible = false
	_assist_layer.add_child(_assist)
	var gs = _autoload("GameState")
	if gs != null:
		model.rng = gs.rng
	var cad = _autoload("Cadence")
	if cad != null and "model" in cad and cad.model is CadenceModel:
		model.cadence = cad.model


func _process(delta: float) -> void:
	if _fake:
		return
	_step(delta * 1000.0)


func _exit_tree() -> void:
	if is_instance_valid(_cam):
		_cam.queue_free()


# --- Setup -----------------------------------------------------------------------------

## Finds the typewriter and its parts in the hall (hall_c.gd builds "Typewriter04").
## player_camera is restored when the typing view closes. pipeline (PsxPipeline) gets
## set_focus_view(true) in the typing view (spec 4.1). Returns false when the hall has
## no typewriter.
func setup(hall: Node, player_camera: Camera3D, pipeline: Node = null) -> bool:
	_hall = hall
	_player_cam = player_camera
	_pipeline = pipeline
	if hall == null:
		return false
	_typewriter = hall.find_child("Typewriter04", true, false) as Node3D
	if _typewriter == null:
		push_error("TypewriterView: Typewriter04 not found")
		return false
	_carriage = _typewriter.find_child("Carriage", true, false) as Node3D
	_platen = _typewriter.find_child("Platen", true, false) as Node3D
	_paper = _typewriter.find_child("Paper", true, false) as MeshInstance3D
	_lever = _typewriter.find_child("ReleaseLever", true, false) as Node3D
	_copyholder = hall.find_child("Copyholder", true, false) as Node3D
	var keys_root := _typewriter.find_child("Keys", true, false) as Node3D
	if _carriage != null:
		_carriage_rest = _carriage.position
	if _platen != null:
		_platen_basis = _platen.transform.basis
	if _paper != null:
		_paper_rest = _paper.position
		_paper.visible = _loaded
	_index_keys(keys_root)
	_cam.fov = 60.0
	_cam.near = 0.05
	_cam.far = 30.0
	_cam.current = false
	hall.add_child(_cam)
	if _typewriter.is_inside_tree():
		_sounds.position = _typewriter.global_position
	return true


func _index_keys(keys_root: Node3D) -> void:
	_keys.clear()
	if keys_root == null:
		return
	var legends: Array = TextTex.KEY_LEGENDS
	for r in range(legends.size()):
		var row: Array = legends[r]
		for c in range(row.size()):
			var node := keys_root.find_child("Key%d%d" % [r, c], true, false) as Node3D
			if node == null:
				continue
			_keys[String(row[c]).to_upper()] = {"node": node, "rest": node.position.y, "t": -1.0}


## Test and dev hook: the view runs on a fake clock until advance() is called.
func use_fake_clock(start_ms: float = 100000.0) -> void:
	_fake = true
	_fake_now = start_ms


## Test and dev hook: moves the fake clock and runs one step.
func advance(ms: float) -> void:
	_fake_now += ms
	_step(ms)


func sounds() -> TypewriterSounds:
	return _sounds


# --- Queries ----------------------------------------------------------------------------

func is_typing() -> bool:
	return _phase == PH_TYPING


func is_loaded() -> bool:
	return _loaded


func loaded_doc_id() -> String:
	return _sheet_id if _loaded else ""


## The typing view's own camera (spec 6.3). Gaze looks through it while the typing view is open (spec 9.1),
## so the typewriter is seen while the player types on it.
func typing_camera() -> Camera3D:
	return _cam


# --- Entry points (M3 calls these) ------------------------------------------------------

func open_typing_view(doc_id: String = "") -> bool:
	if _phase != PH_FREE:
		return false
	if not _loaded:
		if doc_id == "":
			return false
		if not load_sheet(doc_id):
			return false
		if held_id_fn.is_valid() and String(held_id_fn.call()) == doc_id and held_release_fn.is_valid():
			held_release_fn.call()
		_begin_load()
		return true
	_enter_typing()
	return true


func close_typing_view() -> void:
	if _phase != PH_TYPING:
		return
	_panning = false
	_phase = PH_CAM_OUT
	_tween_cam(_saved_player_xf, CAM_MS, "cam_out_done")


# --- Loading and ejecting (spec 7.5, 7.7) ----------------------------------------------

## Loads a sheet or form into the model without animation (spec 7.5). Sets the model
## from GameState: the fluid uses, the retired word from Day 3 (spec 8.8) and the Day 5
## substitution options (spec 14.12). Returns false when doc_id cannot be loaded.
func load_sheet(doc_id: String) -> bool:
	var gs = _autoload("GameState")
	if gs == null or _loaded or doc_id == "":
		return false
	if not gs.docs.has(doc_id):
		return false
	var doc: Dictionary = gs.docs[doc_id]
	if not LOADABLE_KINDS.has(String(doc.get("kind", ""))):
		return false
	var carbon: Dictionary = {}
	var twin := String(doc.get("twin", ""))
	if twin != "" and gs.docs.has(twin):
		carbon = gs.docs[twin]
	var opts := _sheet_options(doc_id)
	model.fluid_uses = int(gs.fluid_uses)
	model.retired_active = int(gs.day) >= 3
	model.fond_word = String(gs.fond_word)
	model.field_substitution = opts.get("field_substitution", {})
	model.field_bar = opts.get("field_bar", {})
	model.load_sheet(doc, carbon)
	_loaded = true
	_sheet_id = doc_id
	_dirty = true
	_assist_scroll = 0.0
	gs.place(doc_id, "typewriter")
	if _paper != null:
		_paper.visible = true
	sheet_loaded.emit(doc_id)
	return true


## The release lever (spec 7.7). The paper slides out over 0.6 s, the player holds it,
## and the carbon goes to the carbon spot (DayDirector.paper_removed). Works only in
## the typing view. Returns the document id, or "" when nothing was released.
func eject_sheet() -> String:
	if not _loaded or _phase != PH_TYPING:
		return ""
	_sync_fluid()
	var doc := model.unload()
	var id := String(doc.get("id", _sheet_id))
	_loaded = false
	_sheet_id = ""
	var gs = _autoload("GameState")
	if gs != null:
		gs.place(id, "hand")
	var dd = _autoload("DayDirector")
	if dd != null and dd.has_method("paper_removed"):
		dd.paper_removed(id)
	_sounds.play("paper_out", _sounds.position, 0.0, true)
	_phase = PH_EJECT
	_phase_t = 0.0
	_start_paper_anim(-1, EJECT_MS)
	if held_hold_fn.is_valid():
		held_hold_fn.call("document", id)
	sheet_released.emit(id)
	return id


## Clears the loaded sheet without the release lever: no hand, no carbon move. For scene
## resets and tests only. The player uses eject_sheet(). Returns the id, or "".
func unload_sheet() -> String:
	if not _loaded:
		return ""
	if _phase == PH_TYPING or _phase == PH_CAM_IN:
		_cam_dur = 0.0
		_finish_close()
	_sync_fluid()
	var doc := model.unload()
	var id := String(doc.get("id", _sheet_id))
	_loaded = false
	_sheet_id = ""
	if _paper != null:
		_paper.visible = false
	return id


# --- Typing input (spec 7.2 to 7.5) ------------------------------------------------------

## Types one character (spec 7.2 and 7.3). Only keys of the accepted set do anything.
func type_char(ch: String) -> void:
	if not model.is_loaded():
		return
	model.type_key(ch, _now())
	_consume()


func type_enter() -> void:
	model.enter(_now())
	_consume()


func type_backspace() -> void:
	model.backspace(_now())
	_consume()


## Platen knob: delta -1 (Up) or +1 (Down) (spec 7.4).
func type_platen(delta: int) -> void:
	model.platen(delta)
	_consume()


## Left-click on a cell (spec 7.5): moves the carriage to a form field's start.
func click_cell(line: int, col: int) -> void:
	model.click_cell(line, col, _now())
	_consume()


## Correction fluid on a cell (spec 7.6). Returns true when a use was spent.
func use_fluid(line: int, col: int) -> bool:
	var used := model.fluid_at(line, col, _now())
	_sync_fluid()
	_consume()
	return used


# --- Per-frame work ---------------------------------------------------------------------

func _now() -> float:
	return _fake_now if _fake else float(Time.get_ticks_msec())


func _step(dt: float) -> void:
	var now := _now()
	if model.is_loaded():
		model.tick(now)
		_consume()
	match _phase:
		PH_LOADING:
			_phase_t += dt
			_platen_extra = clampf(_phase_t / LOAD_MS, 0.0, 1.0) * TAU
			if _phase_t >= LOAD_MS:
				_platen_extra = 0.0
				_enter_typing()
		PH_EJECT:
			_phase_t += dt
			if _phase_t >= EJECT_MS:
				_finish_eject()
	_step_cam(dt)
	_step_carriage(dt)
	_step_platen(dt)
	_step_paper(dt)
	_step_keys(dt)
	_sounds.tick(now)
	if _dirty and _loaded:
		_refresh_paper()
	_update_assist()
	_apply_visuals()


func _consume() -> void:
	var ev: Array = model.take_events()
	if ev.is_empty():
		return
	var now := _now()
	_sounds.play_events(ev, now, model.ghost_pending())
	for raw in ev:
		var e: Dictionary = raw
		match String(e.get("t", "")):
			"key":
				_dirty = true
				_key_press(String(e.get("ch", "")))
			"fluid":
				_dirty = true
			"carriage":
				_car_from = _vis_col
				_car_t = 0.0
				_car_ms = float(e.get("ms", 0.0))
			"return":
				_dirty = true
				_car_from = _vis_col
				_car_t = 0.0
				_car_ms = RETURN_MS
				_pl_from = _vis_line
				_pl_t = 0.0
				_pl_ms = RETURN_MS
			"ratchet":
				_pl_from = _vis_line
				_pl_t = 0.0
				_pl_ms = float(e.get("ms", 0.0))
	_sync_fluid()


## GameState.fluid_uses follows the model only while a sheet is loaded (the model
## starts at 12 and must not overwrite GameState before a load).
func _sync_fluid() -> void:
	var gs = _autoload("GameState")
	if gs != null and model.is_loaded():
		gs.fluid_uses = model.fluid_uses


func _key_press(ch: String) -> void:
	var k := ch.to_upper()
	if _keys.has(k):
		_keys[k].t = 0.0


func _step_keys(dt: float) -> void:
	for k in _keys:
		var entry: Dictionary = _keys[k]
		if float(entry.t) < 0.0:
			continue
		entry.t = float(entry.t) + dt
		var t := float(entry.t)
		var off := 0.0
		if t < KEY_DOWN_MS:
			off = KEY_TRAVEL * t / KEY_DOWN_MS
		elif t < KEY_DOWN_MS + KEY_UP_MS:
			off = KEY_TRAVEL * (1.0 - (t - KEY_DOWN_MS) / KEY_UP_MS)
		else:
			entry.t = -1.0
		var node: Node3D = entry.node
		node.position.y = float(entry.rest) - off


func _step_carriage(dt: float) -> void:
	var target := float(model.col)
	if _car_ms <= 0.0 or _car_t >= _car_ms:
		_vis_col = target
		return
	_car_t += dt
	var k := clampf(_car_t / _car_ms, 0.0, 1.0)
	_vis_col = lerpf(_car_from, target, k)


func _step_platen(dt: float) -> void:
	var target := float(model.line)
	if _pl_ms <= 0.0 or _pl_t >= _pl_ms:
		_vis_line = target
		return
	_pl_t += dt
	var k := clampf(_pl_t / _pl_ms, 0.0, 1.0)
	_vis_line = lerpf(_pl_from, target, k)


func _step_paper(dt: float) -> void:
	if _paper_dir == 0:
		return
	if _paper == null:
		_paper_dir = 0
		return
	_paper_t += dt
	var k := clampf(_paper_t / _paper_dur, 0.0, 1.0)
	if _paper_dir > 0:
		_paper.position = _paper_rest + LOAD_OFFSET * (1.0 - k)
	else:
		_paper.position = _paper_rest + EJECT_OFFSET * k
	if k >= 1.0:
		_paper_dir = 0
		if _paper_dur == EJECT_MS and not _loaded:
			_paper.visible = false
		_paper.position = _paper_rest


func _start_paper_anim(dir: int, dur: float) -> void:
	if _paper == null:
		return
	_paper_dir = dir
	_paper_t = 0.0
	_paper_dur = dur


func _apply_visuals() -> void:
	if _carriage != null:
		var off := clampf((CARRIAGE_CENTRE - _vis_col) * CARRIAGE_STEP, -CARRIAGE_CLAMP, CARRIAGE_CLAMP)
		_carriage.position = _carriage_rest + Vector3(off, 0.0, 0.0)
	if _platen != null:
		var ang := -_vis_line / LINES_PER_TURN * TAU - _platen_extra
		_platen.transform = Transform3D(Basis(Vector3.RIGHT, ang) * _platen_basis, _platen.transform.origin)


func _refresh_paper() -> void:
	_dirty = false
	_assist_dirty = true
	if _paper == null or _renderer == null or not model.is_loaded():
		return
	var tex: Texture2D = _renderer.page_texture(model.original, 0)
	if tex != null:
		PaperQuad.set_texture(_paper, tex)


# --- Typing view: camera, input, phases -------------------------------------------------

func _begin_load() -> void:
	_phase = PH_LOADING
	_phase_t = 0.0
	_esc_queued = false
	_start_paper_anim(1, LOAD_MS)
	_sounds.play("paper_in", _sounds.position, 0.0, true)


func _enter_typing() -> void:
	if not _cam_ok():
		_on_typing_entered()
		return
	_phase = PH_CAM_IN
	_phase_t = 0.0
	_saved_player_xf = _xf_of(_player_cam)
	_cam.global_transform = _saved_player_xf
	_cam.current = true
	_set_focus(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_tween_cam(_typing_pose(), CAM_MS, "cam_in_done")


func _finish_eject() -> void:
	if _paper != null:
		_paper.visible = false
		_paper.position = _paper_rest
	_phase = PH_CAM_OUT
	_tween_cam(_saved_player_xf, CAM_MS, "cam_out_done")


func _finish_close() -> void:
	_phase = PH_FREE
	_panning = false
	_esc_queued = false
	if _cam_ok():
		_cam.current = false
	if _player_cam != null:
		_player_cam.make_current()
	_set_focus(false)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _set_focus(on: bool) -> void:
	if _pipeline != null and _pipeline.has_method("set_focus_view"):
		_pipeline.call("set_focus_view", on)


func _cam_ok() -> bool:
	return _cam != null and _cam.is_inside_tree()


func _xf_of(node: Node3D) -> Transform3D:
	if node == null or not node.is_inside_tree():
		return Transform3D.IDENTITY
	return node.global_transform


func _tween_cam(to: Transform3D, dur: float, done_tag: String) -> void:
	if not _cam_ok():
		_cam_dur = 0.0
		_on_cam_done(done_tag)
		return
	_cam_from = _cam.global_transform
	_cam_to = to
	_cam_t = 0.0
	_cam_dur = dur
	_cam_done = done_tag


func _step_cam(dt: float) -> void:
	if _cam_dur <= 0.0:
		return
	_cam_t += dt
	var k := clampf(_cam_t / _cam_dur, 0.0, 1.0)
	var e := k * k * (3.0 - 2.0 * k)
	if _cam_ok():
		_cam.global_transform = _cam_from.interpolate_with(_cam_to, e)
	if _cam_t >= _cam_dur:
		_cam_dur = 0.0
		var tag := _cam_done
		_cam_done = ""
		_on_cam_done(tag)


func _on_cam_done(tag: String) -> void:
	match tag:
		"cam_in_done":
			_on_typing_entered()
		"cam_out_done":
			_finish_close()


## The typing pose is reached. An Esc pressed during the load or the tween in (_queue_esc) runs
## the exit now, as soon as the tween has finished (spec 6.3).
func _on_typing_entered() -> void:
	_phase = PH_TYPING
	opened.emit()
	if _esc_queued:
		_esc_queued = false
		close_typing_view()


## The typing pose (spec 6.3): the camera looks at the paper from its front, about 0.36 m
## away, so the paper fills about 70% of the vertical view.
func _typing_pose() -> Transform3D:
	if _paper == null or not _paper.is_inside_tree() or not _cam_ok():
		return _xf_of(_cam)
	var c := _paper.global_position
	var n := _paper.global_transform.basis.z.normalized()
	var eye := c + n * TYPE_DISTANCE + Vector3.UP * 0.06
	return Transform3D(Basis.looking_at(c - eye, Vector3.UP), eye)


## Right mouse hold (spec 6.3): a close-up of the copyholder.
func _copy_pose() -> Transform3D:
	if _copyholder == null or not _copyholder.is_inside_tree() or not _cam_ok():
		return _xf_of(_cam)
	var c := _copyholder.global_position + Vector3.UP * 0.05
	var from := _saved_player_xf.origin
	var eye := c + (from - c).normalized() * 0.30
	return Transform3D(Basis.looking_at(c - eye, Vector3.UP), eye)


# --- Input ------------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _phase == PH_LOADING or _phase == PH_CAM_IN:
		_queue_esc(event)
		return
	if _phase != PH_TYPING:
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		if _handle_key(k):
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_on_left_press(_window_to_internal(mb.position))
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if mb.pressed:
				_on_right_press()
			else:
				_on_right_release()
		elif _is_wheel(mb) and _assist.visible:
			if mb.pressed:
				_scroll_assist(-ASSIST_SCROLL_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else ASSIST_SCROLL_STEP)
		else:
			return
		get_viewport().set_input_as_handled()


## Esc during the load and the 0.5 s tween in (spec 6.3) is taken here, so the menu does not open on
## it. The exit is queued and runs when the typing pose is reached (_on_typing_entered). Other keys
## and the mouse pass through as before.
func _queue_esc(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var k := event as InputEventKey
	if k.keycode != KEY_ESCAPE:
		return
	if k.pressed and not k.echo:
		_esc_queued = true
	get_viewport().set_input_as_handled()


func _is_wheel(mb: InputEventMouseButton) -> bool:
	return mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN


func _handle_key(k: InputEventKey) -> bool:
	match k.keycode:
		KEY_ESCAPE:
			close_typing_view()
			return true
		KEY_ENTER, KEY_KP_ENTER:
			type_enter()
			return true
		KEY_BACKSPACE:
			type_backspace()
			return true
		KEY_UP:
			type_platen(-1)
			return true
		KEY_DOWN:
			type_platen(1)
			return true
		KEY_LEFT, KEY_RIGHT, KEY_TAB:
			return false
	if k.ctrl_pressed or k.alt_pressed or k.meta_pressed:
		return false
	var u := k.unicode
	if u <= 0:
		return false
	type_char(char(u))
	return true


func _on_left_press(px: Vector2) -> void:
	if _lever_hit(px):
		eject_sheet()
		return
	var page_px := _paper_hit(px)
	if page_px.x < 0.0:
		return
	var cell := DocRenderer.cell_at_px(page_px)
	if cell.x < 0 or cell.x >= DocModel.LINES or cell.y < 0 or cell.y >= DocModel.COLS:
		return
	if _held_kind() == "fluid":
		use_fluid(cell.x, cell.y)
	else:
		click_cell(cell.x, cell.y)


func _on_right_press() -> void:
	if _held_kind() == "fluid" and held_release_fn.is_valid():
		held_release_fn.call()
		return
	_panning = true
	_tween_cam(_copy_pose(), PAN_MS, "")


func _on_right_release() -> void:
	if not _panning:
		return
	_panning = false
	_tween_cam(_typing_pose(), PAN_MS, "")


## Page pixel (768 x 1088) under an internal-resolution point, or (-1, -1). The paper is
## a centred quad with its normal along the +Z face (paper_quad.gd).
func _paper_hit(px: Vector2) -> Vector2:
	if not _cam_ok() or _paper == null or not _paper.is_inside_tree():
		return Vector2(-1.0, -1.0)
	var ro := _cam.project_ray_origin(px)
	var rd := _cam.project_ray_normal(px)
	var n := _paper.global_transform.basis.z.normalized()
	var denom := rd.dot(n)
	if absf(denom) < 1e-6:
		return Vector2(-1.0, -1.0)
	var t := (_paper.global_position - ro).dot(n) / denom
	if t < 0.0:
		return Vector2(-1.0, -1.0)
	var local := _paper.global_transform.affine_inverse() * (ro + rd * t)
	var u := (local.x + PAPER_W * 0.5) / PAPER_W
	var v := (PAPER_H * 0.5 - local.y) / PAPER_H
	if u < 0.0 or u >= 1.0 or v < 0.0 or v >= 1.0:
		return Vector2(-1.0, -1.0)
	return Vector2(u * DocModel.PAGE_W, v * DocModel.PAGE_H)


func _lever_hit(px: Vector2) -> bool:
	if not _cam_ok() or _lever == null or not _lever.is_inside_tree():
		return false
	if _cam.is_position_behind(_lever.global_position):
		return false
	return _cam.unproject_position(_lever.global_position).distance_to(px) <= LEVER_PICK_PX


## Window point to internal (SubViewport) point, the same fit as PsxPipeline's layout.
func _window_to_internal(p: Vector2) -> Vector2:
	var r := _present_rect()
	return (p - r.position) / r.size * _internal_res()


## Internal (SubViewport) point to window point: the inverse of _window_to_internal.
func _internal_to_window(p: Vector2) -> Vector2:
	var r := _present_rect()
	return r.position + p / _internal_res() * r.size


## The window rectangle the internal picture is presented in (PsxPipeline's layout, integer scale).
func _present_rect() -> Rect2:
	var res := _internal_res()
	var window := get_viewport().get_visible_rect().size
	var fit := minf(window.x / res.x, window.y / res.y)
	var factor := floorf(fit) if fit >= 1.0 else fit
	var sz := (res * factor).floor()
	var origin := ((window - sz) * 0.5).floor()
	return Rect2(origin, sz)


func _internal_res() -> Vector2:
	if _pipeline != null and _pipeline.has_method("current_resolution"):
		return Vector2(_pipeline.call("current_resolution"))
	return INTERNAL_RES


# --- Text assist (spec 6.5, 16.3) -------------------------------------------------------

func _text_assist_on() -> bool:
	if text_assist_override >= 0:
		return text_assist_override == 1
	var ss: Node = _autoload("SaveSystem")
	if ss != null and ss.has_method("get_setting"):
		return bool(ss.call("get_setting", "text_assist"))
	return text_assist


## Shows the panel in the typing view only, beside the paper, with the text on the paper. The panel
## is placed each frame, so it follows the paper when the camera pans. Its text is set when the paper
## text changes (the same plain rows as the read view).
func _update_assist() -> void:
	if _phase != PH_TYPING or not _loaded or not model.is_loaded() or not _text_assist_on():
		_assist.visible = false
		return
	if not _layout_assist():
		_assist.visible = false
		return
	if _assist_dirty or not _assist.visible:
		_show_assist_text()
	_assist.visible = true


func _show_assist_text() -> void:
	_assist_dirty = false
	_assist.show_page(model.original, 0)
	# show_page resets the scroll; keep the player's place while they type.
	_assist_scroll = minf(_assist_scroll, _assist.max_scroll())
	_assist.scroll_by(_assist_scroll)


func _scroll_assist(amount: float) -> void:
	_assist.scroll_by(amount)
	_assist_scroll = clampf(_assist_scroll + amount, 0.0, _assist.max_scroll())


## Places the panel to the right of the paper's window rectangle, as ReadView does. Returns false
## when the paper is not on screen.
func _layout_assist() -> bool:
	var pr := _paper_window_rect()
	if pr.size.x <= 0.0 or pr.size.y <= 0.0:
		return false
	var win := get_viewport().get_visible_rect().size
	var x := pr.end.x + ASSIST_GAP
	var w := minf(ASSIST_MAX_W, win.x - x - ASSIST_GAP)
	if w < ASSIST_MIN_W:
		w = ASSIST_MIN_W
		x = maxf(ASSIST_GAP, win.x - w - ASSIST_GAP)
	_assist.position = Vector2(x, pr.position.y)
	_assist.size = Vector2(w, pr.size.y)
	return true


## The paper's rectangle in window pixels: the bounding box of its four projected corners, or an
## empty rectangle when a corner is behind the typing camera.
func _paper_window_rect() -> Rect2:
	if not _cam_ok() or _paper == null or not _paper.is_inside_tree():
		return Rect2()
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for corner in [Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)]:
		var world := _paper.global_transform * Vector3(corner.x * PAPER_W, corner.y * PAPER_H, 0.0)
		if _cam.is_position_behind(world):
			return Rect2()
		var p := _internal_to_window(_cam.unproject_position(world))
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	return Rect2(lo, hi - lo)


func _held_kind() -> String:
	return String(held_kind_fn.call()) if held_kind_fn.is_valid() else ""


# --- Services ---------------------------------------------------------------------------

func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)


func _sheet_options(doc_id: String) -> Dictionary:
	var dd = _autoload("DayDirector")
	if dd != null and dd.has_method("sheet_options"):
		return dd.call("sheet_options", doc_id)
	return {}
