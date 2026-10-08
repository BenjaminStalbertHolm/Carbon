extends RefCounted
## SettingsPage (spec 16.3): the "NAME [VALUE]" lines and BACK, drawn on the paper sheet the
## page was opened from (the title sheet, or the paper inside the menu folder). The page has
## no sheet or backdrop of its own. show_on() replaces the sheet's rows, and hide_page() ends
## the page so the owner rebuilds its own rows. While showing(), the owner sends the sheet's
## hover and click to hovered() and clicked(), and the keys to key_pressed().
## Left and Right, or a click on the left or right half of a line, decrease, increase or
## toggle it. BACK, Enter on BACK, or a click on BACK emits back_requested. Each change is
## persisted at once by SaveSystem.

const Content := preload("res://scripts/logic/content.gd")
const PaperMenu := preload("res://scripts/ui/paper_menu.gd")

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

var _sheet: PaperMenu = null
var _sel := 0


## True while the page is drawn on a sheet.
func showing() -> bool:
	return _sheet != null


## Draws the page on sheet, replacing its rows. The owner hides its own rows first.
func show_on(sheet: PaperMenu) -> void:
	_sheet = sheet
	_sel = 0
	refresh()


## Ends the page. The owner rebuilds its own rows.
func hide_page() -> void:
	_sheet = null


## Rebuilds every row from the current settings.
func refresh() -> void:
	if _sheet == null:
		return
	var rows: Array = []
	for i in range(ROWS.size()):
		rows.append({"text": _row_text(i), "option": true})
	_sheet.set_rows(rows)
	_sheet.set_selected(_sel)


## Pointer hover over a line selects it.
func hovered(option: int) -> void:
	if _sheet == null:
		return
	_sel = option
	_sheet.set_selected(option)


## A click: BACK returns, a toggle flips, a value steps by the side of the line that was clicked.
func clicked(option: int, x_fraction: float) -> void:
	if _sheet == null:
		return
	hovered(option)
	var kind := String(ROWS[option].kind)
	if kind == "back":
		back_requested.emit()
	elif kind == "toggle":
		_adjust(option, 1)
	else:
		_adjust(option, -1 if x_fraction < 0.5 else 1)


## Returns true when the key was used. Enter does nothing on a value line; Esc is never used here.
func key_pressed(code: int) -> bool:
	if _sheet == null:
		return false
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


func _save() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("SaveSystem")
