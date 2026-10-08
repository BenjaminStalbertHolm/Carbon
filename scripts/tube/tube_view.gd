extends Node
## TubeView: the pneumatic tube terminal on Desk 4 (spec 8.4). Presentation only.
##
## Sending: press_receiver() (the receiver is clicked, with a document held). The flap
## opens (0.2 s), the paper is drawn in, the flap closes, DayDirector.send_document runs
## (the document leaves the world), tube_send plays (0.8 s) and the canister travels up
## and out of sight. Nothing is refused (spec 8.4). The rules are DayDirector's.
##
## Arrivals: DayDirector.canister_arrived(ids). The ids are already placed by
## DayDirector. The canister whooshes (tube_arrive_whoosh, 1.0 s), drops into the receiver
## with tube_thunk, the flap opens, the arrived documents slide to the inbox tray (0.5 s),
## and the canister leaves with tube_send at -30 dBFS (spec 8.4).
##
## NO SUCH ADDRESSEE (spec 8.4): DayDirector writes that stamp into the returned
## free sheets' page data, and DocRenderer draws it. This view draws nothing for it.
##
## Use: add to the main tree, call setup(hall), then set the hand hooks:
##   held_kind_fn: () -> String   ("document" when a document is held)
##   held_id_fn: () -> String     (its id)
##   held_release_fn: () -> String (clears the hand)

const TypewriterSounds := preload("res://scripts/typewriter/typewriter_sounds.gd")
const DocRenderer := preload("res://scripts/doc/doc_renderer.gd")
const PaperQuad := preload("res://scripts/doc/paper_quad.gd")

signal send_started(doc_id: String)
signal arrival_shown(doc_ids: Array)

## Receiver and canister positions (tube_terminal_model.gd): desk-relative corner.
const CANISTER_REST_Y := 1.10
const CANISTER_TOP_Y := 2.60
const FLAP_OPEN_DEG := -70.0
const FLAP_MS := 200.0
const SEND_PAPER_AT := 400.0
const SEND_SOUND_AT := 600.0
const SEND_MS := 800.0
const WHOOSH_MS := 1000.0
const DROP_MS := 300.0
const SLIDE_MS := 500.0
const DOC_SIZE := Vector2(0.21, 0.297)

var held_kind_fn := Callable()
var held_id_fn := Callable()
var held_release_fn := Callable()

var _sounds := TypewriterSounds.new()
var _renderer = null
var _hall: Node = null
var _root: Node3D = null
var _receiver: Node3D = null
var _flap: Node3D = null
var _canister: Node3D = null
var _flap_basis := Basis.IDENTITY
var _canister_rest := Vector3.ZERO
var _slides: Array = []
var _clock := 0.0
var _fake := false
var _events: Array = []  # [at_ms, Callable]
var _tweens: Array = []  # [t0_ms, dur_ms, Callable(k)]
var _busy := false
var _arrival_free_at := 0.0


func _ready() -> void:
	_renderer = DocRenderer.new()
	add_child(_renderer)


func _process(delta: float) -> void:
	if _fake:
		return
	_step(delta * 1000.0)


## Finds Tube04 (tube_terminal_model.gd) in the hall and listens to DayDirector.
func setup(hall: Node) -> bool:
	_hall = hall
	if hall == null:
		return false
	_root = hall.find_child("Tube04", true, false) as Node3D
	if _root == null:
		push_error("TubeView: Tube04 not found")
		return false
	_receiver = _root.find_child("Receiver", true, false) as Node3D
	_flap = _root.find_child("Flap", true, false) as Node3D
	_canister = _root.find_child("Canister", true, false) as Node3D
	if _flap != null:
		_flap_basis = _flap.transform.basis
	if _canister != null:
		_canister_rest = _canister.position
		_canister.visible = false
	if _receiver != null and _receiver.is_inside_tree():
		_sounds.position = _receiver.global_position
	listen()
	return true


## Connects arrivals from DayDirector.canister_arrived (setup() calls this).
func listen() -> void:
	var dd = _autoload("DayDirector")
	if dd != null and not dd.canister_arrived.is_connected(_on_canister_arrived):
		dd.canister_arrived.connect(_on_canister_arrived)


func use_fake_clock() -> void:
	_fake = true


## Test and dev hook: advances the tube timeline by ms.
func advance(ms: float) -> void:
	_step(ms)


func sounds() -> TypewriterSounds:
	return _sounds


## True while a send or an arrival sequence is running.
func busy() -> bool:
	return _busy or _clock < _arrival_free_at


func canister_visible() -> bool:
	return _canister != null and _canister.visible


# --- Sending (spec 8.4) -----------------------------------------------------------------

## The receiver is clicked. Returns true when a send started. Only a held document can be
## sent (spec 8.4): the document leaves the world through DayDirector.send_document.
func press_receiver() -> bool:
	if _busy:
		return false
	var kind := _held_kind()
	if kind != "document" and kind != "sheet":
		return false
	var doc_id := _held_id()
	if doc_id == "":
		return false
	_busy = true
	var t := _clock
	_tween(t, FLAP_MS, func(k): _set_flap(lerpf(0.0, FLAP_OPEN_DEG, k)))
	_tween(t + SEND_PAPER_AT - FLAP_MS, FLAP_MS, func(k): _set_flap(lerpf(FLAP_OPEN_DEG, 0.0, k)))
	_at(t + SEND_PAPER_AT, func(): _send_now(doc_id))
	_at(t + SEND_SOUND_AT, func(): _sounds.play("tube_send", _sounds.position, 0.0, true))
	_tween(t + SEND_SOUND_AT, SEND_MS, func(k): _set_canister(lerpf(CANISTER_REST_Y, CANISTER_TOP_Y, k)))
	_at(t + SEND_SOUND_AT, func(): _show_canister(true))
	_at(t + SEND_SOUND_AT + SEND_MS, func(): _finish_send())
	return true


func _send_now(doc_id: String) -> void:
	if _held_kind() != "" and held_release_fn.is_valid():
		held_release_fn.call()
	var dd = _autoload("DayDirector")
	if dd != null:
		dd.send_document(doc_id)
	send_started.emit(doc_id)


func _finish_send() -> void:
	_show_canister(false)
	_busy = false


# --- Arrivals (spec 8.4) ----------------------------------------------------------------

func _on_canister_arrived(doc_ids: Array) -> void:
	var start := maxf(_clock, _arrival_free_at)
	var ids := doc_ids.duplicate()
	var drop_at := start + WHOOSH_MS
	var thunk_at := drop_at + DROP_MS
	var slide_at := thunk_at + FLAP_MS
	var leave_at := slide_at + SLIDE_MS
	_at(start, func(): _sounds.play("tube_arrive_whoosh", _sounds.position, 0.0, false))
	_at(start, func(): _start_canister_at_top())
	_tween(drop_at, DROP_MS, func(k): _set_canister(lerpf(CANISTER_TOP_Y, CANISTER_REST_Y, k * k)))
	_at(thunk_at, func(): _sounds.play("tube_thunk", _sounds.position, 0.0, false))
	_tween(thunk_at, FLAP_MS, func(k): _set_flap(lerpf(0.0, FLAP_OPEN_DEG, k)))
	_at(slide_at, func(): _spawn_slides(ids))
	_tween(slide_at, SLIDE_MS, func(k): _move_slides(k))
	_at(leave_at, func(): _remove_slides())
	_tween(leave_at, FLAP_MS, func(k): _set_flap(lerpf(FLAP_OPEN_DEG, 0.0, k)))
	_at(leave_at, func(): _sounds.play_tube_leave(_sounds.position))
	_tween(leave_at, SEND_MS, func(k): _set_canister(lerpf(CANISTER_REST_Y, CANISTER_TOP_Y, k)))
	_at(leave_at + SEND_MS, func(): _finish_arrival(ids))
	_arrival_free_at = leave_at + SEND_MS


func _start_canister_at_top() -> void:
	_set_canister(CANISTER_TOP_Y)
	_show_canister(true)


func _finish_arrival(ids: Array) -> void:
	_show_canister(false)
	arrival_shown.emit(ids)


# --- Presentation helpers ---------------------------------------------------------------

func _set_flap(angle_deg: float) -> void:
	if _flap == null:
		return
	_flap.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(angle_deg)) * _flap_basis, _flap.transform.origin)


func _set_canister(y: float) -> void:
	if _canister != null:
		_canister.position = Vector3(_canister_rest.x, y, _canister_rest.z)


func _show_canister(on: bool) -> void:
	if _canister != null:
		_canister.visible = on


## The arrived documents: a flat paper quad per document, from the receiver to the inbox
## tray. The quads are presentation only; the documents themselves are DayDirector's.
func _spawn_slides(ids: Array) -> void:
	_remove_slides()
	if _hall == null or _receiver == null or _renderer == null:
		return
	var tray := _hall.find_child("InboxTray", true, false) as Node3D
	if tray == null or not tray.is_inside_tree() or not _receiver.is_inside_tree():
		return
	var gs = _autoload("GameState")
	if gs == null:
		return
	for raw in ids:
		var doc_id := String(raw)
		if not gs.docs.has(doc_id):
			continue
		var tex = _renderer.page_texture(gs.docs[doc_id], 0)
		if tex == null:
			continue
		var quad := PaperQuad.make(tex, DOC_SIZE)
		quad.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		_hall.add_child(quad)
		quad.global_position = _receiver.global_position + Vector3(0.0, 0.03, 0.0)
		_slides.append({"node": quad, "from": _receiver.global_position + Vector3(0.0, 0.03, 0.0), "to": tray.global_position + Vector3(0.0, 0.03, 0.0)})


func _move_slides(k: float) -> void:
	for s in _slides:
		var node: MeshInstance3D = s.node
		if is_instance_valid(node):
			node.global_position = (s.from as Vector3).lerp(s.to as Vector3, k)


func _remove_slides() -> void:
	for s in _slides:
		var node: Node = s.node
		if is_instance_valid(node):
			node.queue_free()
	_slides = []


# --- Timeline ---------------------------------------------------------------------------

func _at(t: float, fn: Callable) -> void:
	_events.append([t, fn])


func _tween(t0: float, dur: float, fn: Callable) -> void:
	_tweens.append([t0, maxf(dur, 1.0), fn])


func _step(dt: float) -> void:
	_clock += dt
	_events.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	while not _events.is_empty() and float(_events[0][0]) <= _clock:
		var ev: Array = _events.pop_front()
		(ev[1] as Callable).call()
	var still: Array = []
	for tw in _tweens:
		var t0 := float(tw[0])
		var dur := float(tw[1])
		if _clock < t0:
			still.append(tw)
			continue
		var k := clampf((_clock - t0) / dur, 0.0, 1.0)
		(tw[2] as Callable).call(k)
		if k < 1.0:
			still.append(tw)
	_tweens = still


# --- Services ---------------------------------------------------------------------------

func _held_kind() -> String:
	return String(held_kind_fn.call()) if held_kind_fn.is_valid() else ""


func _held_id() -> String:
	return String(held_id_fn.call()) if held_id_fn.is_valid() else ""


func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
