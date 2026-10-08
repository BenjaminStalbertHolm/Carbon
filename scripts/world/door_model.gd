extends RefCounted
## Doors (spec 6.1, 8.13 and 5.5). Each door root sits on its wall's room-side face,
## and its local +Z points into the room. Panels are quads, so each wall stays a solid
## box. Collision is a box covering the door leaf.

const Geo := preload("res://scripts/world/geometry.gd")
const TextTex := preload("res://scripts/world/text_texture.gd")

const COL_CHROME := Color("#A8A8A0")
const DOOR_WIDTH := 1.0
const DOOR_HEIGHT := 2.1
const GLASS_BOTTOM := 1.05
const HANDLE_X := 0.38
const HANDLE_Y := 1.0
## Local z of the panels: a hair in front of the wall so they do not z-fight.
const PANEL_Z := 0.02


## Supervisor door: north wall, centred x = 0. Steel lower half, frosted glass upper half
## with the SUPERVISOR label. Always locked. The unlit room behind it is never enterable.
static func build_supervisor(parent: Node3D) -> Node3D:
	var door := Geo.group(parent, "SupervisorDoor", Vector3(0.0, 0.0, -6.0))
	Geo.add(door, Geo.quad(DOOR_WIDTH, GLASS_BOTTOM, Geo.TEX_STEEL, Geo.WHITE, 1.0, 0.0, "Panel"),
		Vector3(0, GLASS_BOTTOM * 0.5, PANEL_Z))
	Geo.add(door, Geo.quad(DOOR_WIDTH, DOOR_HEIGHT - GLASS_BOTTOM, Geo.TEX_FROSTED, Geo.WHITE, 1.0, 0.0, "Glass"),
		Vector3(0, (DOOR_HEIGHT + GLASS_BOTTOM) * 0.5, PANEL_Z))
	var label := TextTex.supervisor_label(door)
	Geo.add(door, Geo.quad(0.40, 0.075, label, Geo.WHITE, 0.0, 0.0, "Label"),
		Vector3(0, (DOOR_HEIGHT + GLASS_BOTTOM) * 0.5, PANEL_Z + 0.004))
	_handle(door)
	door.add_child(Geo.static_box(Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.04), Vector3(0, DOOR_HEIGHT * 0.5, 0), "Collision"))
	# The unlit box room behind the supervisor door (3 x 3 x 3.2), beyond the north wall.
	Geo.add(parent, Geo.solid(Vector3(3.0, 3.0, 3.2), Color("#2A2A26"), "SupervisorRoom"), Vector3(0, 1.5, -7.8))
	return door


## Exit door: south wall at x = -6, steel, chrome handle on the room side, EXIT sign above.
## Locked except in Ending B (M10). The root is turned 180 degrees so +Z faces north.
static func build_exit(parent: Node3D) -> Node3D:
	var door := Geo.group(parent, "ExitDoor", Vector3(-6.0, 0.0, 6.0), Vector3(0, 180, 0))
	Geo.add(door, Geo.quad(DOOR_WIDTH, DOOR_HEIGHT, Geo.TEX_STEEL, Geo.WHITE, 1.0, 0.0, "Panel"),
		Vector3(0, DOOR_HEIGHT * 0.5, PANEL_Z))
	_handle(door)
	var sign_tex := TextTex.exit_sign(door)
	Geo.add(door, Geo.quad(0.32, 0.12, sign_tex, Geo.WHITE, 0.0, 0.0, "Sign"),
		Vector3(0, 2.45, PANEL_Z))
	door.add_child(Geo.static_box(Vector3(DOOR_WIDTH, DOOR_HEIGHT, 0.04), Vector3(0, DOOR_HEIGHT * 0.5, 0), "Collision"))
	return door


## Chrome lever handle on the room side (local +Z), on a small rose plate.
static func _handle(door: Node3D) -> void:
	Geo.add(door, Geo.solid(Vector3(0.03, 0.10, 0.01), COL_CHROME, "Rose"), Vector3(HANDLE_X, HANDLE_Y, PANEL_Z + 0.005))
	Geo.add(door, Geo.solid(Vector3(0.02, 0.02, 0.06), COL_CHROME, "Lever"), Vector3(HANDLE_X, HANDLE_Y, PANEL_Z + 0.04))
