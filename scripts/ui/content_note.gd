extends Node
## ContentNote (spec 16.1): a black screen with the content note typed centred,
## Special Elite 28 px, #C8C2AE, 30 ms per character, no sound. Any key or click
## while typing completes the text at once; after that a key or click proceeds.
##
## Coroutine: await note.run(), then show the title. Signals: typed (all lines are
## on screen), finished (the player pressed through).

const Content := preload("res://scripts/logic/content.gd")
const BlackScreen := preload("res://scripts/ui/black_screen.gd")

const FONT_SIZE := 28
const MS_PER_CHAR := 30

signal typed
signal finished
signal _proceed

var _screen: Node
var _can_proceed := false
var _running := false


func run() -> void:
	_running = true
	_can_proceed = false
	_screen = BlackScreen.new()
	add_child(_screen)
	_screen.set_shade(1.0)
	await _screen.type_lines(Content.strings().content_note, FONT_SIZE, MS_PER_CHAR, false)
	typed.emit()
	_can_proceed = true
	await _proceed
	_can_proceed = false
	_running = false
	_screen.queue_free()
	finished.emit()


func _input(event: InputEvent) -> void:
	if not _running or not _is_press(event):
		return
	get_viewport().set_input_as_handled()
	if _screen.is_typing():
		_screen.fast_forward()
	elif _can_proceed:
		_can_proceed = false
		_proceed.emit()


static func _is_press(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed and not event.echo
	if event is InputEventMouseButton:
		return event.pressed and event.button_index != MOUSE_BUTTON_WHEEL_UP and event.button_index != MOUSE_BUTTON_WHEEL_DOWN
	return false
