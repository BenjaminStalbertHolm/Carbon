extends Control
## The debug console (spec 21): one input line, toggled by F9, shown at the bottom of the screen.
## Debug builds only: main.gd adds it to the root when OS.is_debug_build(), and the guard below
## frees it in any other build. Enter runs the command. Results show above the line and are
## printed to the Godot output. While the console is open the tree is paused, so the player and
## the day clock do not move while a command is typed.

const DebugGuard := preload("res://scripts/debug/debug_guard.gd")
const DebugCommands := preload("res://scripts/debug/debug_commands.gd")

const LAYER := 128
const SHOW_LINES := 8
const LINE_HEIGHT := 18
const PANEL_HEIGHT := 200.0

## The CARBON main controller. main.gd sets it before the console enters the tree.
var main = null

var _commands = null
var _history := PackedStringArray()
var _log: Label = null
var _line: LineEdit = null
var _layer: CanvasLayer = null  # a CanvasLayer does not inherit the visibility of its parent Control
var _was_paused := false


func _ready() -> void:
	if not DebugGuard.enabled():
		queue_free()
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	add_child(layer)
	_layer = layer
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)
	var panel := ColorRect.new()
	panel.color = Color(0.0, 0.0, 0.0, 0.82)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_bottom(panel)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_anchor_bottom(box)
	root.add_child(box)
	_log = Label.new()
	_log.add_theme_color_override("font_color", Color(0.85, 0.9, 0.85))
	_log.add_theme_font_size_override("font_size", 14)
	_log.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_log.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_log)
	_line = LineEdit.new()
	_line.placeholder_text = "debug"
	_line.add_theme_font_size_override("font_size", 16)
	_line.text_submitted.connect(_on_submitted)
	box.add_child(_line)
	visible = false
	_layer.visible = false


## F9 toggles the console. The input is read before the GUI, so the line edit does not swallow it.
func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not DebugGuard.enabled():
		return
	if key.pressed and not key.echo and key.keycode == KEY_F9:
		set_open(not visible)
		get_viewport().set_input_as_handled()


func set_open(on: bool) -> void:
	if on == visible or not DebugGuard.enabled():
		return
	visible = on
	_layer.visible = on
	if on:
		_was_paused = get_tree().paused
		get_tree().paused = true
		_line.grab_focus()
	else:
		_line.release_focus()
		get_tree().paused = _was_paused


func is_open() -> bool:
	return visible


## Runs one line as typed and returns its result lines (also shown and printed).
func run_line(text: String) -> PackedStringArray:
	if not DebugGuard.enabled():
		return PackedStringArray()
	if _commands == null:
		_commands = DebugCommands.new(main)
	var lines: PackedStringArray = _commands.run(text)
	if text.strip_edges() != "":
		_append("> " + text.strip_edges())
	for l in lines:
		print("[debug] " + l)
		_append(l)
	return lines


func _on_submitted(text: String) -> void:
	_line.clear()
	run_line(text)


func _append(text: String) -> void:
	_history.append(text)
	while _history.size() > SHOW_LINES:
		_history.remove_at(0)
	if _log != null:
		_log.text = "\n".join(_history)


func _anchor_bottom(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 1.0
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_right = 0.0
	c.offset_top = -PANEL_HEIGHT
	c.offset_bottom = 0.0
