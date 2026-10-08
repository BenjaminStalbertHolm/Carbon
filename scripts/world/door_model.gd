extends RefCounted
## Doors (spec 6.1, 8.13, 5.5 and 15.2). Each door root sits on its wall's room-side face,
## and its local +Z points into the room. Panels are quads, and collision is a box covering
## the door leaf. The north and south walls are cut for the two doorways (hall_c.gd, QUESTION-39).
## Beyond the exit doorway is the unlit black box of spec 15.2, which fills the opening from outside.

const Geo := preload("res://scripts/world/geometry.gd")
const TextTex := preload("res://scripts/world/text_texture.gd")

const COL_CHROME := Color("#A8A8A0")
const DOOR_WIDTH := 1.0
const DOOR_HEIGHT := 2.1
## Centre x of the two doors (spec 6.1).
const SUPERVISOR_X := 0.0
const EXIT_X := -6.0
## Door-local x of the exit leaf's hinge: the east edge (world x -5.5, since the root is turned
## 180 degrees). The leaf swings about this line, and its handle sits near the free west edge (QUESTION-64).
const EXIT_HINGE_X := -0.5
const GLASS_BOTTOM := 1.05
const HANDLE_X := 0.38
const HANDLE_Y := 1.0
## Local z of the panels: a hair in front of the wall so they do not z-fight.
const PANEL_Z := 0.02


## x range of a doorway in a wall, centred on x_centre, as Vector2(x0, x1).
static func opening_span(x_centre: float) -> Vector2:
	return Vector2(x_centre - DOOR_WIDTH * 0.5, x_centre + DOOR_WIDTH * 0.5)


## Supervisor door: north wall, centred x = 0. Steel lower half, frosted glass upper half
## with the SUPERVISOR label. Always locked. The unlit room behind it is never enterable.
static func build_supervisor(parent: Node3D) -> Node3D:
	var door := Geo.group(parent, "SupervisorDoor", Vector3(SUPERVISOR_X, 0.0, -6.0))
	Geo.add(door, Geo.quad(DOOR_WIDTH, GLASS_BOTTOM, Geo.TEX_STEEL, Geo.WHITE, 1.0, 0.0, "Panel"),
		Vector3(0, GLASS_BOTTOM * 0.5, PANEL_Z))
	# Frosted glass (spec 5.2, QUESTION-45): alpha 0.7, so the silhouette 0.05 m behind shows through.
	Geo.add(door, Geo.quad(DOOR_WIDTH, DOOR_HEIGHT - GLASS_BOTTOM, Geo.TEX_FROSTED, Geo.WHITE, 1.0, 0.0, "Glass", true),
		Vector3(0, (DOOR_HEIGHT + GLASS_BOTTOM) * 0.5, PANEL_Z))
	var label := TextTex.supervisor_label(door)
	Geo.add(door, Geo.quad(0.40, 0.075, label, Geo.WHITE, 0.0, 0.0, "Label"),
		Vector3(0, (DOOR_HEIGHT + GLASS_BOTTOM) * 0.5, PANEL_Z + 0.004))
	_handle(door)
	door.add_child(Geo.static_box(Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.04), Vector3(0, DOOR_HEIGHT * 0.5, 0), "Collision"))
	# The unlit box room behind the supervisor door (3 x 3 x 3.2), beyond the north wall. Black
	# (#000000, as the unlit box of spec 15.2) so the figure reads as a faint shape through the glass.
	Geo.add(parent, Geo.solid(Vector3(3.0, 3.0, 3.2), Color("#000000"), "SupervisorRoom"), Vector3(0, 1.5, -7.8))
	return door


## Exit door: south wall at x = -6, steel, chrome handle on the room side, EXIT sign above.
## Locked except in Ending B (M10). The root is turned 180 degrees so +Z faces north.
static func build_exit(parent: Node3D) -> Node3D:
	var door := Geo.group(parent, "ExitDoor", Vector3(EXIT_X, 0.0, 6.0), Vector3(0, 180, 0))
	# The leaf (panel, handle and collision) hinges at its east edge, door-local x = -0.5, so it
	# can swing 90 degrees outward (south) over 1.2 s (spec 15.2 step 2, endings/exit_door.gd).
	var leaf := Geo.group(door, "Leaf", Vector3(EXIT_HINGE_X, 0.0, 0.0))
	var shift := Vector3(EXIT_HINGE_X, 0.0, 0.0)
	Geo.add(leaf, Geo.quad(DOOR_WIDTH, DOOR_HEIGHT, Geo.TEX_STEEL, Geo.WHITE, 1.0, 0.0, "Panel"),
		Vector3(0, DOOR_HEIGHT * 0.5, PANEL_Z) - shift)
	_handle(leaf, shift)
	var sign_tex := TextTex.exit_sign(door)
	Geo.add(door, Geo.quad(0.32, 0.12, sign_tex, Geo.WHITE, 0.0, 0.0, "Sign"),
		Vector3(0, 2.45, PANEL_Z))
	leaf.add_child(Geo.static_box(Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.04), Vector3(0, DOOR_HEIGHT * 0.5, 0) - shift, "Collision"))
	# Beyond the doorway, just outside the south wall face (z 6.2): the unlit black box of spec
	# 15.2 step 2, 1.2 x 2.1 x 1.0 m (#000000). It fills the opening from outside (QUESTION-39).
	Geo.add(parent, Geo.solid(Vector3(1.2, DOOR_HEIGHT, 1.0), Color("#000000"), "ExitBeyond"),
		Vector3(EXIT_X, DOOR_HEIGHT * 0.5, 6.7))
	return door


## Chrome lever handle on the room side (local +Z), on a small rose plate.
static func _handle(door: Node3D, shift: Vector3 = Vector3.ZERO) -> void:
	Geo.add(door, Geo.solid(Vector3(0.03, 0.10, 0.01), COL_CHROME, "Rose"), Vector3(HANDLE_X, HANDLE_Y, PANEL_Z + 0.005) - shift)
	Geo.add(door, Geo.solid(Vector3(0.02, 0.02, 0.06), COL_CHROME, "Lever"), Vector3(HANDLE_X, HANDLE_Y, PANEL_Z + 0.04) - shift)
