extends CanvasLayer
## ReadView: the full-screen read view (spec 6.3, 6.5, 16.3). A 50% black dim,
## with the page centred at 86% of the window height and its 768:1088 ratio.
##
## open(docs, start_index, mode) shows documents as a flat list of pages:
##   "stack":  every page of every document in order. Left and Right (A and D)
##             step through them. Opens on the first page of docs[start_index].
##   "single": only the pages of docs[start_index].
## Esc closes. A right-click emits right_clicked and closes, unless
## close_on_right_click is false (a stamp in hand returns to the rack first,
## spec 8.1). The mouse wheel scrolls a page taller than the window.
##
## Hooks for stamps and the marker (spec 8.1, 8.2): page_clicked fires on a
## left-click release without a drag, and page_dragged on a release after a
## drag. Positions are in page pixels (768 x 1088). page_index is the page
## within its document, not the position in the flat list. current_doc() gives
## the document on show.
##
## Text assist (spec 16.3) follows SaveSystem's "text_assist" setting. Without
## SaveSystem, the text_assist property is used.

const DocRenderer := preload("res://scripts/doc/doc_renderer.gd")
const TextAssistScript := preload("res://scripts/doc/text_assist.gd")

signal closed
signal page_changed(index: int)  # position in the flat list of pages
signal page_clicked(page_index: int, local_pos_in_page_px: Vector2)
signal page_dragged(page_index: int, from_px: Vector2, to_px: Vector2)
signal right_clicked

const VIEW_FRACTION := 0.86
const DIM := Color(0.0, 0.0, 0.0, 0.5)
const SCROLL_STEP := 60.0
const ASSIST_GAP := 16.0
const ASSIST_MAX_W := 360.0
const ASSIST_MIN_W := 160.0
const DRAG_SLOP := 3.0

## Used when SaveSystem has no "text_assist" setting (spec 16.3).
var text_assist := false
## Dev override for tests and screenshots: -1 uses the setting, 0 off, 1 on.
var text_assist_override := -1
## Set false while a stamp or marker is held, so right-click returns the item first.
var close_on_right_click := true

var _docs: Array = []
var _seq: Array = []  # [doc_index, page_index] pairs, in reading order
var _pos := -1
var _scroll := 0.0
var _renderer: Node
var _dim: ColorRect
var _page: TextureRect
var _assist: Control
var _dragging := false
var _press_px := Vector2.ZERO
var _prev_mouse_mode := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	visible = false
	_renderer = DocRenderer.new()
	add_child(_renderer)
	_dim = ColorRect.new()
	_dim.color = DIM
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_page = TextureRect.new()
	_page.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_page.stretch_mode = TextureRect.STRETCH_SCALE
	_page.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page)
	_assist = TextAssistScript.new()
	_assist.visible = false
	add_child(_assist)
	get_viewport().size_changed.connect(_layout)
	_layout()


## Shows documents. mode is "stack" or "single" (see the header).
func open(docs: Array, start_index: int, mode: String) -> void:
	if docs.is_empty():
		push_warning("ReadView.open: no documents")
		return
	_docs = docs.duplicate()
	_seq = []
	var start := clampi(start_index, 0, _docs.size() - 1)
	var first := -1
	for d in range(_docs.size()):
		if mode == "single" and d != start:
			continue
		var doc: Dictionary = _docs[d]
		for p in range(doc.pages.size()):
			if d == start and p == 0 and first < 0:
				first = _seq.size()
			_seq.append([d, p])
	if _seq.is_empty():
		push_warning("ReadView.open: documents have no pages")
		_docs = []
		return
	_pos = maxi(first, 0)
	if not visible:
		_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	visible = true
	_show_current(false)


## Closes the view and emits closed.
func close() -> void:
	if not visible:
		return
	visible = false
	_dragging = false
	_page.texture = null
	_docs = []
	_seq = []
	_pos = -1
	Input.mouse_mode = _prev_mouse_mode
	closed.emit()


func is_open() -> bool:
	return visible


## The document on show, or {} when closed.
func current_doc() -> Dictionary:
	if _pos < 0 or _pos >= _seq.size():
		return {}
	return _docs[_seq[_pos][0]]


## Index of the document on show within the docs passed to open(), or -1.
func current_doc_index() -> int:
	if _pos < 0 or _pos >= _seq.size():
		return -1
	return int(_seq[_pos][0])


## Page of the document on show, within that document, or -1.
func current_page_index() -> int:
	if _pos < 0 or _pos >= _seq.size():
		return -1
	return int(_seq[_pos][1])


## Position in the flat list of pages, or -1.
func current_position() -> int:
	return _pos


## Shows the current page again (after the document changed, for example a stamp).
func refresh() -> void:
	if visible:
		_show_current(false)


## Steps to another page of the flat list. Emits page_changed on a change.
func step(delta: int) -> void:
	if _seq.is_empty():
		return
	var np := clampi(_pos + delta, 0, _seq.size() - 1)
	if np == _pos:
		return
	_pos = np
	_show_current(true)
	page_changed.emit(_pos)


## Page rectangle in window pixels, centred, 86% of the window height.
func page_rect() -> Rect2:
	var win := get_viewport().get_visible_rect().size
	var ph := win.y * VIEW_FRACTION
	var pw := ph * float(DocRenderer.PAGE_SIZE.x) / float(DocRenderer.PAGE_SIZE.y)
	return Rect2((win.x - pw) * 0.5, (win.y - ph) * 0.5 - _scroll, pw, ph)


func _show_current(_from_step: bool) -> void:
	if _pos < 0 or _pos >= _seq.size():
		return
	var doc: Dictionary = _docs[_seq[_pos][0]]
	var page_index: int = _seq[_pos][1]
	_page.texture = _renderer.page_texture(doc, page_index)
	_scroll = 0.0
	_layout()
	var on := _text_assist_on()
	_assist.visible = on
	if on:
		_assist.show_page(doc, page_index)


func _layout() -> void:
	if _dim == null:
		return
	var win := get_viewport().get_visible_rect().size
	_dim.position = Vector2.ZERO
	_dim.size = win
	var pr := page_rect()
	_page.position = pr.position
	_page.size = pr.size
	var x := pr.end.x + ASSIST_GAP
	var w := minf(ASSIST_MAX_W, win.x - x - ASSIST_GAP)
	if w < ASSIST_MIN_W:
		w = ASSIST_MIN_W
		x = maxf(ASSIST_GAP, win.x - w - ASSIST_GAP)
	_assist.position = Vector2(x, pr.position.y)
	_assist.size = Vector2(w, pr.size.y)


func _text_assist_on() -> bool:
	if text_assist_override >= 0:
		return text_assist_override == 1
	var tree := get_tree()
	var ss: Node = tree.root.get_node_or_null("SaveSystem") if tree != null else null
	if ss != null and ss.has_method("get_setting"):
		return bool(ss.call("get_setting", "text_assist"))
	return text_assist


func _to_page_px(pos: Vector2) -> Vector2:
	var pr := page_rect()
	var local := pos - pr.position
	return Vector2(local.x / pr.size.x * DocRenderer.PAGE_SIZE.x, local.y / pr.size.y * DocRenderer.PAGE_SIZE.y)


func _scroll_by(amount: float) -> void:
	var win := get_viewport().get_visible_rect().size
	var max_scroll := maxf(0.0, win.y * VIEW_FRACTION - win.y)
	_scroll = clampf(_scroll + amount, 0.0, max_scroll)
	_layout()


func _input(event: InputEvent) -> void:
	if not visible or _seq.is_empty():
		return
	if event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_ESCAPE:
				close()
			KEY_LEFT, KEY_A:
				step(-1)
			KEY_RIGHT, KEY_D:
				step(1)
			_:
				return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_scroll_by(-SCROLL_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_scroll_by(SCROLL_STEP)
			MOUSE_BUTTON_RIGHT:
				if mb.pressed:
					right_clicked.emit()
					if close_on_right_click:
						close()
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = page_rect().has_point(mb.position)
					_press_px = _to_page_px(mb.position)
				elif _dragging:
					_dragging = false
					var to_px := _to_page_px(mb.position)
					var page_index := current_page_index()
					if _press_px.distance_to(to_px) > DRAG_SLOP:
						page_dragged.emit(page_index, _press_px, to_px)
					else:
						page_clicked.emit(page_index, _press_px)
			_:
				return
		get_viewport().set_input_as_handled()
