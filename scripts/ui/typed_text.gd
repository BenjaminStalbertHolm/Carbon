extends Control
## TypedText: centred lines that type themselves one character at a time (spec
## 13.1, 15.4, 16.1). Every line is laid out in full and revealed through
## visible_characters, so the centring does not move while typing.
##
## type_lines() is a coroutine: await it. When clack is true each character plays
## key_clack. fast_forward() completes the current typing at once (spec 16.1).

const KeyClack := preload("res://scripts/ui/key_clack.gd")
const FONT := preload("res://assets/fonts/SpecialElite-Regular.ttf")

signal finished

var _box: VBoxContainer
var _typing := false
var _skip := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box = VBoxContainer.new()
	_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_box)


func is_typing() -> bool:
	return _typing


## Removes every line. A typing run in progress stops.
func clear_text() -> void:
	_skip = true
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()


## Types lines one after another, centred, in the given size and colour.
func type_lines(lines: Array, font_size: int, color: Color, ms_per_char: int, clack: bool) -> void:
	clear_text()
	_skip = false
	_typing = true
	var labels: Array = []
	for line in lines:
		var label := _make_label(String(line), font_size, color)
		_box.add_child(label)
		labels.append(label)
	for label in labels:
		var total := String(label.text).length()
		for c in range(total):
			if _skip or not is_inside_tree() or not is_instance_valid(label):
				break
			label.visible_characters = c + 1
			if clack:
				KeyClack.play(self)
			await get_tree().create_timer(ms_per_char / 1000.0).timeout
		if _skip:
			break
	_typing = false
	finished.emit()


## Shows all the text at once. The running type_lines() returns after its current
## character delay.
func fast_forward() -> void:
	if not _typing:
		return
	_skip = true
	for child in _box.get_children():
		child.visible_characters = -1


func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	# Blank lines keep their height.
	label.custom_minimum_size = Vector2(0, FONT.get_height(font_size))
	label.visible_characters = 0 if text != "" else -1
	return label
