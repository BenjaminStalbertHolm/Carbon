extends Node
## Swallows the Space key while standing is locked (spec 15.1 step 1, and the seated look-only
## state of spec 15.3). It is a child of the player, so Godot delivers unhandled input to it before
## the player controller, and set_input_as_handled() stops the event there.

var controller = null


func _unhandled_input(event: InputEvent) -> void:
	if controller == null or not bool(controller.standing_locked()):
		return
	if is_space_press(event):
		get_viewport().set_input_as_handled()


## True for a fresh Space press (not an auto-repeat), the key the player controller uses to stand.
static func is_space_press(event: InputEvent) -> bool:
	if not (event is InputEventKey):
		return false
	var k := event as InputEventKey
	return k.pressed and not k.echo and k.keycode == KEY_SPACE
