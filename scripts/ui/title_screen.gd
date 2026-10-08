extends CanvasLayer
## TitleScreen (spec 16.2): black background and one printed sheet with BEGIN,
## CONTINUE — {DAYNAME} (only when a save exists), SETTINGS and QUIT. BEGIN with a
## save asks THIS WILL ERASE YOUR WEEK. with YES / NO. The title plays no audio.
##
## The owner listens for:
##   new_game_requested: start a new game (DayDirector.start_new_game), then the
##     Monday transition from spec 13.1 step 3 (run_day_title(1, true)).
##   continue_requested: SaveSystem.load_game(), then spec 13.1 from step 7.
## The owner calls hide_title() when it takes over the screen.
## Keys: Up and Down select, Enter activates. Mouse: hover selects, click activates.

const Content := preload("res://scripts/logic/content.gd")
const PaperMenu := preload("res://scripts/ui/paper_menu.gd")
const SettingsPage := preload("res://scripts/ui/settings_page.gd")

const SHEET_HEIGHT := 0.6
const SHEET_ASPECT := 0.75
const MAIN_KEYS := ["begin", "continue", "settings", "quit"]

signal new_game_requested
signal continue_requested

var _root: Control
var _sheet: PaperMenu
var _settings: Control
var _mode := "main"  # "main" or "erase"
var _ids: Array = []  # option id for each option row
var _sel := 0


func _ready() -> void:
	layer = 110
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(black)
	_sheet = PaperMenu.new()
	_sheet.row_hovered.connect(_on_hover)
	_sheet.row_clicked.connect(_on_click)
	_root.add_child(_sheet)
	_settings = SettingsPage.new()
	_settings.back_requested.connect(_on_settings_back)
	_root.add_child(_settings)
	get_viewport().size_changed.connect(_layout)
	_layout()
	var save = Engine.get_main_loop().root.get_node_or_null("SaveSystem")
	if save != null:
		save.load_settings()
	visible = false


## Shows the title with the options for the current save.
func show_title() -> void:
	_mode = "main"
	_sel = 0
	_settings.visible = false
	_sheet.visible = true
	_build()
	visible = true


func hide_title() -> void:
	visible = false


## Selects an option row and activates it, as a click would (also used by the
## screenshot harness).
func choose(option: int) -> void:
	_on_hover(option)
	_activate(option)


func _build() -> void:
	var st: Dictionary = Content.strings()
	var save := _save()
	var rows: Array = [
		{"text": String(st.title_lines[0]), "option": false},
		{"text": "", "option": false},
	]
	_ids = []
	var options: Array = []
	if _mode == "main":
		var has: bool = save != null and bool(save.has_save())
		var day_name := ""
		if has:
			day_name = String(st.day_titles[str(int(save.saved_day()))])
		for i in range(MAIN_KEYS.size()):
			if MAIN_KEYS[i] == "continue" and not has:
				continue
			_ids.append(MAIN_KEYS[i])
			options.append(String(st.title_options[i]).replace("{DAYNAME}", day_name))
	else:
		rows.append({"text": String(st.erase_prompt), "option": false})
		rows.append({"text": "", "option": false})
		_ids = ["yes", "no"]
		options = [String(st.yes), String(st.no)]
	for text in options:
		rows.append({"text": String(text), "option": true})
	_sheet.set_rows(rows)
	_sel = clampi(_sel, 0, maxi(0, _ids.size() - 1))
	_sheet.set_selected(_sel)


func _activate(option: int) -> void:
	if option < 0 or option >= _ids.size():
		return
	match String(_ids[option]):
		"begin":
			var save := _save()
			if save != null and save.has_save():
				_mode = "erase"
				_sel = 0
				_build()
			else:
				new_game_requested.emit()
		"continue":
			continue_requested.emit()
		"settings":
			_show_settings()
		"quit":
			get_tree().quit()
		"yes":
			var save := _save()
			if save != null:
				save.delete_save()
			new_game_requested.emit()
		"no":
			_mode = "main"
			_sel = 0
			_build()


func _show_settings() -> void:
	_sheet.visible = false
	_settings.show_page(1.0)


func _on_settings_back() -> void:
	_settings.visible = false
	_sheet.visible = true
	_build()


func _on_hover(option: int) -> void:
	_sel = option
	_sheet.set_selected(option)


func _on_click(option: int, _x_fraction: float) -> void:
	_on_hover(option)
	_activate(option)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if _settings.visible:
		if _settings.key_pressed(event.keycode):
			get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_UP:
			_move(-1)
		KEY_DOWN:
			_move(1)
		KEY_ENTER, KEY_KP_ENTER:
			_activate(_sel)
		_:
			return
	get_viewport().set_input_as_handled()


func _move(step: int) -> void:
	_sel = clampi(_sel + step, 0, maxi(0, _ids.size() - 1))
	_sheet.set_selected(_sel)


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var h := vp.y * SHEET_HEIGHT
	var w := h * SHEET_ASPECT
	_sheet.position = (vp - Vector2(w, h)) * 0.5
	_sheet.size = Vector2(w, h)


func _save() -> Node:
	return Engine.get_main_loop().root.get_node_or_null("SaveSystem")
