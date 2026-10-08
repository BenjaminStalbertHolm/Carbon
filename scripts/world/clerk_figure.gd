extends Node3D
## Seated clerk figure (spec 5.4 and 8.9), built from primitives in chair-local
## coordinates. The origin is the chair centre on the floor and the figure faces north.
## Two states in M2: the seated typing pose facing north (set_seated_facing_north) and
## the facing-player pose with hands on the thighs (set_facing_player). The typing
## animation is M8 and is not here. The figure and its chair turn together.
## Build with the static build(); the node has this script attached.

const Geo := preload("res://scripts/world/geometry.gd")

const SELF_PATH := "res://scripts/world/clerk_figure.gd"
const COL_SUIT := Color("#3A3A38")
const COL_SKIN := Color("#8F8B80")
## Desk 4 seated eye position (spec 6.1). A clerk facing the player turns to this point.
const PLAYER_EYE := Vector3(5.25, 1.15, 4.10)

var _chair: Node3D = null
var _arm := {}


## Creates a clerk under parent at pos, wired to its chair, facing north.
static func build(parent: Node3D, node_name: String, pos: Vector3, chair: Node3D):
	var clerk = Node3D.new()
	clerk.set_script(load(SELF_PATH))
	clerk.name = node_name
	clerk.position = pos
	parent.add_child(clerk)
	clerk.populate()
	clerk.set_chair(chair)
	clerk.set_seated_facing_north()
	return clerk


func set_chair(chair: Node3D) -> void:
	_chair = chair


## Seated, typing pose, facing north (the default, spec 8.9).
func set_seated_facing_north() -> void:
	rotation.y = 0.0
	if _chair != null:
		_chair.rotation.y = 0.0
	_set_arm_pose(false)


## Turns the figure and its chair to face Desk 4's seated eye position, with the hands
## resting on the thighs (spec 8.9). Rotation about Y only.
func set_facing_player() -> void:
	var here: Vector3 = global_position if is_inside_tree() else position
	var dx := PLAYER_EYE.x - here.x
	var dz := PLAYER_EYE.z - here.z
	var yaw := atan2(-dx, -dz)
	rotation.y = yaw
	if _chair != null:
		_chair.rotation.y = yaw
	_set_arm_pose(true)


## Builds the torso, head, legs and arm chains. Called once by build().
func populate() -> void:
	_add(Geo.solid(Vector3(0.40, 0.55, 0.24), COL_SUIT, "Torso"), Vector3(0, 0.775, 0.06))
	_add(Geo.sphere(0.11, COL_SKIN, "Head"), Vector3(0, 1.22, 0.06))
	_add(Geo.solid(Vector3(0.15, 0.12, 0.42), COL_SUIT, "ThighL"), Vector3(0.09, 0.54, 0.0))
	_add(Geo.solid(Vector3(0.15, 0.12, 0.42), COL_SUIT, "ThighR"), Vector3(-0.09, 0.54, 0.0))
	_add(Geo.solid(Vector3(0.13, 0.46, 0.13), COL_SUIT, "ShinL"), Vector3(0.09, 0.37, -0.145))
	_add(Geo.solid(Vector3(0.13, 0.46, 0.13), COL_SUIT, "ShinR"), Vector3(-0.09, 0.37, -0.145))
	for side in [1.0, -1.0]:
		var key := "L" if side > 0.0 else "R"
		_arm["upper" + key] = _add(Geo.solid(Vector3(0.09, 0.30, 0.09), COL_SUIT, "UpperArm" + key), Vector3.ZERO)
		_arm["fore" + key] = _add(Geo.solid(Vector3(0.08, 0.28, 0.08), COL_SUIT, "Forearm" + key), Vector3.ZERO)
		_arm["hand" + key] = _add(Geo.solid(Vector3(0.08, 0.03, 0.10), COL_SKIN, "Hand" + key), Vector3.ZERO)
	_set_arm_pose(false)


func _add(node: Node3D, pos: Vector3) -> Node3D:
	node.position = pos
	add_child(node)
	return node


## Places each arm chain. Typing: hands reach the keyboard. Lap: forearms lie along the thighs.
func _set_arm_pose(lap: bool) -> void:
	for side in [1.0, -1.0]:
		var key := "L" if side > 0.0 else "R"
		var shoulder := Vector3(0.22 * side, 1.00, 0.02)
		var elbow: Vector3
		var wrist: Vector3
		var hand: Vector3
		if lap:
			elbow = Vector3(0.22 * side, 0.66, 0.10)
			wrist = Vector3(0.10 * side, 0.64, -0.16)
			hand = Vector3(0.10 * side, 0.625, -0.19)
		else:
			elbow = Vector3(0.22 * side, 0.80, -0.10)
			wrist = Vector3(0.10 * side, 0.88, -0.33)
			hand = Vector3(0.10 * side, 0.89, -0.36)
		_place_limb(_arm["upper" + key], shoulder, elbow)
		_place_limb(_arm["fore" + key], elbow, wrist)
		var hand_node: Node3D = _arm["hand" + key]
		hand_node.transform = Transform3D(Basis.IDENTITY, hand)


## Centres a box whose long axis is Y on the segment a to b.
func _place_limb(node: Node3D, a: Vector3, b: Vector3) -> void:
	var dir := (b - a).normalized()
	node.transform = Transform3D(Geo.basis_along(dir), (a + b) * 0.5)
