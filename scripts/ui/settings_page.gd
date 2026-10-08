extends Control
## SettingsPage (spec 16.3): a paper page of "NAME [VALUE]" rows and BACK. Each
## change is persisted at once by SaveSystem. Left and Right, or a click on the
## left or right half of a row, decrease, increase or toggle it. BACK, or a click
## on it, emits back_requested.
##
## The owner (title screen or menu folder) shows and hides this Control, and sends
## keys to key_pressed() while it is showing.

const Content := preload("res://scripts/logic/content.gd")
const PaperMenu := preload("res://scripts/ui/paper_menu.gd")

const SHEET_HEIGHT := 0.8
const SHEET_ASPECT := 0.75
const FLOAT_STEP := 0.1
const INT_STEP := 10

## One entry per row of strings.json settings.names, in the same order. on_index is
## the position in settings.values of the ON state (DITHER lists ON first).
const ROWS := [
	{"key": "mouse_sensitivity", "kind": "float"},
	{"key": "invert_mouse_y", "kind": "toggle", "on_index": 1},
	{"key": "master_volume", "kind": "int"},
	{"key": "fullscreen", "kind": "toggle", "on_index": 1},
	{"key": "internal_high", "kind": "toggle", "on_index": 1},
	{"key": "dither", "kind": "toggle", "on_index": 0},
	{"key": "reduce_flicker", "kind": "toggle", "on_index": 1},
	{"key": "text_assist", "kind": "toggle", "on_index": 1},
	{"key": "", "kind": "back"},
]

signal back_requested

var _dim: ColorRect
var _sheet: PaperMenu
var _sel := 0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.0)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)
	_sheet = PaperMenu.new()
	_sheet.row_hovered.connect(_on_hover)
	_sheet.row_clicked.connect(_on_click)
	add_child(_sheet)
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false


## Shows the page. dim_alpha darkens what is behind it (1.0 on the title screen).
func show_page(dim_alpha: float) -> void:
	_dim.color = Color(0, 0, 0, dim_alpha)
	_sel = 0
	refresh()
	visible = true


## Rebuilds every row from the current settings.
func refresh() -> void:
	var rows: Array = []
	for i in range(ROWS.size()):
		rows.append({"text": _row_text(i), "option": true})
	_sheet.set_rows(rows)
	_sheet.set_selected(_sel)


## Returns true when the key was used.
func key_pressed(code: int) -> bool:
	match code:
		KEY_UP:
			_move(-1)
		KEY_DOWN:
			_move(1)
		KEY_LEFT:
			_adjust(_sel, -1)
		KEY_RIGHT:
			_adjust(_sel, 1)
		KEY_ENTER, KEY_KP_ENTER:
			if String(ROWS[_sel].kind) != "back":
				return false
			back_requested.emit()
		_:
			return false
	return true


func _layout() -> void:
	var vp := get_viewport_rect().size
	var h := vp.y * SHEET_HEIGHT
	var w := h * SHEET_ASPECT
	_sheet.position = (vp - Vector2(w, h)) * 0.5
	_sheet.size = Vector2(w, h)


func _move(step: int) -> void:
	_sel = clampi(_sel + step, 0, ROWS.size() - 1)
	_sheet.set_selected(_sel)


func _adjust(i: int, direction: int) -> void:
	var row: Dictionary = ROWS[i]
	var key := String(row.key)
	var save := _save()
	if save == null:
		return
	match String(row.kind):
		"float":
			save.set_setting(key, float(save.get_setting(key)) + FLOAT_STEP * direction)
		"int":
			save.set_setting(key, int(save.get_setting(key)) + INT_STEP * direction)
		"toggle":
			save.set_setting(key, not bool(save.get_setting(key)))
		_:
			return
	_sel = i
	_sheet.set_selected(i)
	_sheet.set_option_text(i, _row_text(i))


func _row_text(i: int) -> String:
	var st: Dictionary = Content.strings().settings
	var name := String(st.names[i])
	var row: Dictionary = ROWS[i]
	var save := _save()
	if String(row.kind) == "back" or save == null:
		return name
	var value := ""
	match String(row.kind):
		"float":
			value = "%.1f" % float(save.get_setting(row.key))
		"int":
			value = str(int(save.get_setting(row.key)))
		"toggle":
			var on := bool(save.get_setting(row.key))
			var index := int(row.on_index) if on else 1 - int(row.on_index)
			value = String(st.values[name][index])
	return "%s [%s]" % [name, value]


func _on_hover(option: int) -> void:
	_sel = option
	_sheet.set_selected(option)


func _on_click(option: int, x_fraction: float) -> void:
	_on_hover(option)
	var kind := String(ROWS[option].kind)
	if kind == "back":
		back_requested.emit()
	elif kind == "toggle":
		_adjust(option, 1)
	else:
		_adjust(option, -1 if x_fraction < 0.5 else 1)


func _save() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("SaveSystem")
