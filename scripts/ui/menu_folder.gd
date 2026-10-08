extends CanvasLayer
## MenuFolder (spec 16.2): the Esc menu in free view. A manila folder (#C9B58A, 70%
## of the window height, tab PERSONNEL — 0412) holds a paper with RESUME,
## SETTINGS, QUIT TO TITLE and QUIT TO DESKTOP. The two quits first show the
## progress warning with YES / NO. Esc or RESUME closes the folder.
##
## The folder does not pause the tree. It reports pause_requested(true) on open()
## and pause_requested(false) on close(), and the controller pauses the tree.
## quit_to_title_confirmed is emitted before the close, when the player confirms
## QUIT TO TITLE. QUIT TO DESKTOP calls get_tree().quit() after YES.
##
## The caller opens the folder on Esc in free view, and must not open it again while
## it is already open (open() ignores that). Scene: scenes/ui/menu_folder.tscn.

const Content := preload("res://scripts/logic/content.gd")
const PaperMenu := preload("res://scripts/ui/paper_menu.gd")
const SettingsPage := preload("res://scripts/ui/settings_page.gd")
const FONT := preload("res://assets/fonts/SpecialElite-Regular.ttf")

const FOLDER_COLOR := Color("#C9B58A")
const INK := Color("#1C1B19")
const FOLDER_HEIGHT := 0.7
const FOLDER_ASPECT := 0.75
const TAB_HEIGHT := 0.07
const INSET := 0.06
const TAB_FONT_SIZE := 22
const MENU_KEYS := ["resume", "settings", "quit_title", "quit_desktop"]

signal opened
signal closed
signal pause_requested(paused: bool)
signal quit_to_title_confirmed

var _dim: ColorRect
var _folder: Control
var _body: ColorRect
var _tab: ColorRect
var _tab_label: Label
var _sheet: PaperMenu
var _settings: Control
var _mode := "menu"  # "menu", "warning" or "settings"
var _ids: Array = []
var _sel := 0
var _return_sel := 0
var _quit_target := ""  # "title" or "desktop" while the warning shows


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 120
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.5)
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)
	_folder = Control.new()
	_folder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_folder)
	_body = ColorRect.new()
	_body.color = FOLDER_COLOR
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_folder.add_child(_body)
	_tab = ColorRect.new()
	_tab.color = FOLDER_COLOR
	_tab.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_folder.add_child(_tab)
	_tab_label = Label.new()
	_tab_label.text = String(Content.strings().folder.tab)
	_tab_label.add_theme_font_override("font", FONT)
	_tab_label.add_theme_font_size_override("font_size", TAB_FONT_SIZE)
	_tab_label.add_theme_color_override("font_color", INK)
	_tab_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tab_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab.add_child(_tab_label)
	_sheet = PaperMenu.new()
	_sheet.row_hovered.connect(_on_hover)
	_sheet.row_clicked.connect(_on_click)
	_folder.add_child(_sheet)
	_settings = SettingsPage.new()
	_settings.back_requested.connect(_on_settings_back)
	add_child(_settings)
	get_viewport().size_changed.connect(_layout)
	_layout()
	visible = false


func is_open() -> bool:
	return visible


## Opens the folder at RESUME and reports the pause.
func open() -> void:
	if visible:
		return
	_mode = "menu"
	_sel = 0
	_quit_target = ""
	_settings.visible = false
	_folder.visible = true
	_build()
	visible = true
	pause_requested.emit(true)
	opened.emit()


func close() -> void:
	if not visible:
		return
	visible = false
	pause_requested.emit(false)
	closed.emit()


## Selects a row and activates it, as a click would (also used by the screenshot
## harness). Only meaningful while the folder is open.
func choose(option: int) -> void:
	_on_hover(option)
	_activate(option)


func _build() -> void:
	var st: Dictionary = Content.strings()
	var rows: Array = []
	_ids = []
	if _mode == "menu":
		for i in range(MENU_KEYS.size()):
			_ids.append(MENU_KEYS[i])
			rows.append({"text": String(st.folder.options[i]), "option": true})
	else:
		var warning := String(st.folder.quit_warning).replace("{DAYNAME}", _day_name())
		rows.append({"text": warning, "option": false})
		rows.append({"text": "", "option": false})
		_ids = ["yes", "no"]
		rows.append({"text": String(st.yes), "option": true})
		rows.append({"text": String(st.no), "option": true})
	_sheet.set_rows(rows)
	_sel = clampi(_sel, 0, maxi(0, _ids.size() - 1))
	_sheet.set_selected(_sel)


func _activate(option: int) -> void:
	if option < 0 or option >= _ids.size():
		return
	var id := String(_ids[option])
	if _mode == "menu":
		match id:
			"resume":
				close()
			"settings":
				_show_settings()
			"quit_title":
				_ask_quit("title", option)
			"quit_desktop":
				_ask_quit("desktop", option)
	elif _mode == "warning":
		if id == "yes":
			if _quit_target == "title":
				quit_to_title_confirmed.emit()
				close()
			else:
				get_tree().quit()
		else:
			_mode = "menu"
			_sel = _return_sel
			_build()


func _ask_quit(target: String, option: int) -> void:
	_quit_target = target
	_return_sel = option
	_mode = "warning"
	_sel = 0
	_build()


func _show_settings() -> void:
	_mode = "settings"
	_folder.visible = false
	_settings.show_page(0.0)


func _on_settings_back() -> void:
	_mode = "menu"
	_settings.visible = false
	_folder.visible = true
	_build()


func _on_hover(option: int) -> void:
	if _mode == "settings":
		return
	_sel = option
	_sheet.set_selected(option)


func _on_click(option: int, _x_fraction: float) -> void:
	if _mode == "settings":
		return
	_on_hover(option)
	_activate(option)


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	get_viewport().set_input_as_handled()
	if event.keycode == KEY_ESCAPE:
		close()
		return
	if _mode == "settings":
		_settings.key_pressed(event.keycode)
		return
	match event.keycode:
		KEY_UP:
			_move(-1)
		KEY_DOWN:
			_move(1)
		KEY_ENTER, KEY_KP_ENTER:
			_activate(_sel)


func _move(step: int) -> void:
	_sel = clampi(_sel + step, 0, maxi(0, _ids.size() - 1))
	_sheet.set_selected(_sel)


func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	var fh := vp.y * FOLDER_HEIGHT
	var fw := fh * FOLDER_ASPECT
	_folder.position = (vp - Vector2(fw, fh)) * 0.5
	_folder.size = Vector2(fw, fh)
	var tab_h := fh * TAB_HEIGHT
	var text_w := FONT.get_string_size(String(_tab_label.text), HORIZONTAL_ALIGNMENT_LEFT, -1, TAB_FONT_SIZE).x
	var tab_w := minf(fw * 0.8, text_w + fw * 0.1)
	_tab.position = Vector2(fw * INSET, 0.0)
	_tab.size = Vector2(tab_w, tab_h)
	_tab_label.position = Vector2(fw * 0.04, 0.0)
	_tab_label.size = Vector2(tab_w - fw * 0.04, tab_h)
	_body.position = Vector2(0.0, tab_h)
	_body.size = Vector2(fw, fh - tab_h)
	var inset := fw * INSET
	_sheet.position = Vector2(inset, tab_h + inset)
	_sheet.size = Vector2(fw - 2.0 * inset, fh - tab_h - 2.0 * inset)


func _day_name() -> String:
	var day := int(Engine.get_main_loop().root.get_node("GameState").day)
	return String(Content.strings().day_titles[str(day)])
