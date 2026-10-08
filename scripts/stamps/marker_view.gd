extends Node
## MarkerView: the redaction marker in read view (spec 8.2). With the marker held, a
## left-click-and-drag horizontally on a redaction order (doc.redactable) adds a black
## bar with Doc.add_bar: from the press x to the release x, on the text line nearest
## the press point. DocRenderer draws the bar (16 px, centred on the line). Bars are
## permanent.
##
## Sound (spec 8.2, QUESTION-23 decision B): marker_stroke loops from the press until
## the release or 1.2 s, whichever comes first. AudioDirector.start_loop(name, pos,
## gain) and stop_loop(handle) are used when present. Without them, a one-shot plays.
##
## Right-click in read view while holding the marker returns it, as with stamps
## (spec 8.2). close_on_right_click is kept in step with the hand (see stamp_view.gd).
##
## Use: add to the main tree, call attach(read_view), set the hand hooks:
##   held_kind_fn: () -> String   ("marker" when held)
##   held_release_fn: () -> String

const DocModel := preload("res://scripts/logic/doc_model.gd")
const DocRenderer := preload("res://scripts/doc/doc_renderer.gd")

signal bar_drawn(doc_id: String, page_index: int, line: int)

const MAX_STROKE_MS := 1200.0
const STROKE_GAIN_DB := 0.0
const DESK_TOP := Vector3(5.25, 0.76, 3.5)

var held_kind_fn := Callable()
var held_release_fn := Callable()
var stroke_position := DESK_TOP

var _read_view = null
var _prev_down := false
var _stroke_handle = null
var _stroke_ms := 0.0


func _process(delta: float) -> void:
	if _read_view == null:
		return
	_read_view.close_on_right_click = not _holding_any()
	var down := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if down and not _prev_down and holding_marker() and _press_on_page():
		_start_stroke()
	elif not down and _prev_down:
		_stop_stroke()
	if _stroke_handle != null:
		_stroke_ms += delta * 1000.0
		if _stroke_ms >= MAX_STROKE_MS:
			_stop_stroke()
	_prev_down = down


## Connects to a ReadView (doc/read_view.gd). Safe to call once.
func attach(read_view) -> void:
	_read_view = read_view
	if read_view == null:
		return
	if not read_view.page_dragged.is_connected(_on_page_dragged):
		read_view.page_dragged.connect(_on_page_dragged)
	if not read_view.right_clicked.is_connected(_on_right_clicked):
		read_view.right_clicked.connect(_on_right_clicked)


func holding_marker() -> bool:
	return _held_kind() == "marker"


## Draws a bar on the page of the read view (spec 8.2). from_px and to_px are page
## pixels. Returns the line the bar sits on, or -1 when the page cannot take a bar.
func draw_bar(page_index: int, from_px: Vector2, to_px: Vector2) -> int:
	if _read_view == null:
		return -1
	var doc: Dictionary = _read_view.current_doc()
	if doc.is_empty() or not bool(doc.get("redactable", false)):
		return -1
	if page_index < 0 or page_index >= doc.pages.size():
		return -1
	var page: Dictionary = doc.pages[page_index]
	var line := nearest_line(from_px.y)
	var x0 := clampf(minf(from_px.x, to_px.x), 0.0, float(DocModel.PAGE_W))
	var x1 := clampf(maxf(from_px.x, to_px.x), 0.0, float(DocModel.PAGE_W))
	if x1 <= x0:
		return -1
	DocModel.add_bar(page, line, x0, x1)
	_read_view.refresh()
	bar_drawn.emit(String(doc.id), page_index, line)
	return line


## The typed line whose centre is nearest a page y (spec 8.2).
static func nearest_line(y: float) -> int:
	var best := 0
	var best_d := INF
	for line in range(DocModel.LINES):
		var d := absf(DocRenderer.typed_bar_centre_y(line) - y)
		if d < best_d:
			best_d = d
			best = line
	return best


func _on_page_dragged(page_index: int, from_px: Vector2, to_px: Vector2) -> void:
	if holding_marker():
		draw_bar(page_index, from_px, to_px)


func _on_right_clicked() -> void:
	if holding_marker() and held_release_fn.is_valid():
		_stop_stroke()
		held_release_fn.call()


func _press_on_page() -> bool:
	if _read_view == null or not _read_view.is_open():
		return false
	return _read_view.page_rect().has_point(_read_view.get_viewport().get_mouse_position())


func _start_stroke() -> void:
	_stop_stroke()
	var audio = _autoload("AudioDirector")
	if audio == null:
		return
	if audio.has_method("start_loop"):
		_stroke_handle = audio.call("start_loop", "marker_stroke", stroke_position, STROKE_GAIN_DB)
	else:
		audio.call("play", "marker_stroke", stroke_position, true, STROKE_GAIN_DB, true)
		_stroke_handle = true
	_stroke_ms = 0.0


func _stop_stroke() -> void:
	if _stroke_handle == null:
		return
	var audio = _autoload("AudioDirector")
	if audio != null and audio.has_method("stop_loop"):
		audio.call("stop_loop", _stroke_handle)
	_stroke_handle = null
	_stroke_ms = 0.0


func _holding_any() -> bool:
	var kind := _held_kind()
	return kind == "marker" or kind.begins_with("stamp:")


func _held_kind() -> String:
	return String(held_kind_fn.call()) if held_kind_fn.is_valid() else ""


func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
