extends Control
## PaperMenu: one printed paper sheet with a column of rows (spec 16.2, 16.3).
## Option rows are selectable: the selected one starts with "> ", the others with
## two spaces, so the text never shifts. Rows that are not options print as they
## are. The owner positions and sizes this Control, and handles the keys. Mouse
## hover and clicks come back through row_hovered and row_clicked.

const PAPER := preload("res://assets/textures/paper.png")
const FONT := preload("res://assets/fonts/SpecialElite-Regular.ttf")
const INK := Color("#1C1B19")
const PRINT_SIZE := 22
const SELECTED_PREFIX := "> "
const PLAIN_PREFIX := "  "

signal row_hovered(option: int)
signal row_clicked(option: int, x_fraction: float)

var _margin: MarginContainer
var _box: VBoxContainer
var _option_labels: Array = []
var _option_texts: Array = []
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
	_margin.add_theme_constant_override("margin_left", int(round(size.x * 0.12)))
	_margin.add_theme_constant_override("margin_right", int(round(size.x * 0.12)))
	_margin.add_theme_constant_override("margin_top", int(round(size.y * 0.1)))
	_margin.add_theme_constant_override("margin_bottom", int(round(size.y * 0.1)))


## rows: Array of {text: String, option: bool}. Option rows are numbered in order.
func set_rows(rows: Array) -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	_option_labels = []
	_option_texts = []
	for row in rows:
		var text := String(row.text)
		var label := Label.new()
		label.add_theme_font_override("font", FONT)
		label.add_theme_font_size_override("font_size", PRINT_SIZE)
		label.add_theme_color_override("font_color", INK)
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		label.custom_minimum_size = Vector2(0, FONT.get_height(PRINT_SIZE))
		if bool(row.get("option", false)):
			var index := _option_texts.size()
			_option_texts.append(text)
			_option_labels.append(label)
			label.mouse_filter = Control.MOUSE_FILTER_STOP
			label.mouse_entered.connect(_on_row_entered.bind(index))
			label.gui_input.connect(_on_row_input.bind(index))
		else:
			label.text = text
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
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


func _refresh() -> void:
	for i in range(_option_labels.size()):
		var prefix: String = SELECTED_PREFIX if i == _selected else PLAIN_PREFIX
		_option_labels[i].text = prefix + String(_option_texts[i])


func _on_row_entered(index: int) -> void:
	row_hovered.emit(index)


func _on_row_input(event: InputEvent, index: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var label: Label = _option_labels[index]
		var width := maxf(1.0, label.size.x)
		row_clicked.emit(index, clampf(event.position.x / width, 0.0, 1.0))
		accept_event()
