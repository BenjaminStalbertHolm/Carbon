extends Control
## PaperMenu: one printed paper sheet with a column of rows (spec 16.2, 16.3).
## Option rows are selectable. Each option row has a marker column as wide as "> ": the
## selected row draws "> " in it, the others draw nothing, so every option's text starts
## at the same x and does not shift. Rows that are not options print as they are, flush
## left. The owner positions and sizes this Control (every sheet keeps A4_ASPECT), and
## handles the keys. Mouse hover and clicks come back through row_hovered and row_clicked.

const PAPER := preload("res://assets/textures/paper.png")
const FONT := preload("res://assets/fonts/SpecialElite-Regular.ttf")
const INK := Color("#1C1B19")
## Print size on a sheet of REFERENCE_SHEET_H, the title sheet at the default 1280x960 window (60% of
## the height). Larger or smaller sheets scale the text with the paper; a sheet too narrow or too short
## for its rows shrinks the text until every word and row fits (nothing is clipped or runs off the paper).
const PRINT_SIZE := 22
const REFERENCE_SHEET_H := 576.0
const MIN_PRINT_SIZE := 4
const MARGIN_X := 0.12
const MARGIN_Y := 0.1
const SELECTED_PREFIX := "> "
## Document page ratio, 768 x 1088 px (spec 6.5). Every paper sheet is sized to it.
const A4_ASPECT := 768.0 / 1088.0

signal row_hovered(option: int)
signal row_clicked(option: int, x_fraction: float)

var _margin: MarginContainer
var _box: VBoxContainer
var _option_rows: Array = []  # HBoxContainer per option: marker column, then text
var _option_labels: Array = []  # text Label per option
var _option_markers: Array = []  # marker Label per option
var _option_texts: Array = []
var _row_defs: Array = []  # {text, option, index} per row, in print order
var _text_labels: Array = []  # every text Label on the sheet
var _marker_labels: Array = []  # every "> " marker Label
var _selected := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var paper := TextureRect.new()
	paper.texture = PAPER
	paper.stretch_mode = TextureRect.STRETCH_TILE
	paper.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(paper)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_margin)
	_box = VBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_margin.add_child(_box)
	resized.connect(_relayout)
	_relayout()


func _relayout() -> void:
	_margin.add_theme_constant_override("margin_left", int(round(size.x * MARGIN_X)))
	_margin.add_theme_constant_override("margin_right", int(round(size.x * MARGIN_X)))
	_margin.add_theme_constant_override("margin_top", int(round(size.y * MARGIN_Y)))
	_margin.add_theme_constant_override("margin_bottom", int(round(size.y * MARGIN_Y)))
	_apply_font()


## rows: Array of {text: String, option: bool}. Option rows are numbered in order.
func set_rows(rows: Array) -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_option_rows = []
	_option_labels = []
	_option_markers = []
	_option_texts = []
	_row_defs = []
	_text_labels = []
	_marker_labels = []
	for row in rows:
		var text := String(row.text)
		if bool(row.get("option", false)):
			var index := _option_texts.size()
			_option_texts.append(text)
			_row_defs.append({"text": text, "option": true, "index": index})
			var marker := _new_label(false)
			_marker_labels.append(marker)
			marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var label := _new_label(true)
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var line := HBoxContainer.new()
			line.mouse_filter = Control.MOUSE_FILTER_STOP
			line.add_child(marker)
			line.add_child(label)
			line.mouse_entered.connect(_on_row_entered.bind(index))
			line.gui_input.connect(_on_row_input.bind(index))
			_option_rows.append(line)
			_option_labels.append(label)
			_option_markers.append(marker)
			_text_labels.append(label)
			_box.add_child(line)
		else:
			var label := _new_label(true)
			label.text = text
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_row_defs.append({"text": text, "option": false, "index": -1})
			_text_labels.append(label)
			_box.add_child(label)
	_refresh()


func set_selected(option: int) -> void:
	_selected = option
	_refresh()


## Replaces the text of one option row (a value that changed, for example).
func set_option_text(option: int, text: String) -> void:
	_option_texts[option] = text
	_refresh()


func option_count() -> int:
	return _option_texts.size()


func _new_label(wrap: bool) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_color_override("font_color", INK)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	return label


func _marker_width(fs: int) -> float:
	return FONT.get_string_size(SELECTED_PREFIX, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x


func _refresh() -> void:
	for i in range(_option_labels.size()):
		_option_markers[i].text = SELECTED_PREFIX if i == _selected else ""
		_option_labels[i].text = String(_option_texts[i])
	_apply_font()


## Sets the print size of every label: PRINT_SIZE scaled to the sheet height, cut back until the
## widest word and the wrapped rows fit the sheet's content box (see the constants above).
func _apply_font() -> void:
	if _margin == null or _text_labels.is_empty():
		return
	var fs := _fit_font_size()
	for label in _text_labels:
		label.add_theme_font_size_override("font_size", fs)
		label.custom_minimum_size = Vector2(0, FONT.get_height(fs))
	for marker in _marker_labels:
		marker.add_theme_font_size_override("font_size", fs)
		marker.custom_minimum_size.x = _marker_width(fs)


func _fit_font_size() -> int:
	var fs := maxi(MIN_PRINT_SIZE, floori(size.y * float(PRINT_SIZE) / REFERENCE_SHEET_H))
	var content_w := size.x * (1.0 - 2.0 * MARGIN_X)
	var content_h := size.y * (1.0 - 2.0 * MARGIN_Y)
	while fs > MIN_PRINT_SIZE and not _rows_fit(fs, content_w, content_h):
		fs -= 1
	return fs


func _rows_fit(fs: int, content_w: float, content_h: float) -> bool:
	var line_h := FONT.get_height(fs)
	var total := 0.0
	for row in _row_defs:
		var text := String(row.text)
		var avail := content_w
		if bool(row.option):
			avail -= _marker_width(fs)
		if avail <= 0.0:
			return false
		for word in text.split(" ", false):
			if FONT.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > avail:
				return false
		var width := FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		total += maxi(1, ceili(width / avail)) * line_h
	return total <= content_h


func _on_row_entered(index: int) -> void:
	row_hovered.emit(index)


func _on_row_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var line: Control = _option_rows[index]
		var width := maxf(1.0, line.size.x)
		row_clicked.emit(index, clampf(event.position.x / width, 0.0, 1.0))
		accept_event()
