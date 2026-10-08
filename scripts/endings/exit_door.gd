extends RefCounted
## The exit door (spec 8.13, 15.2): the handle rattles while the door is locked, and when unlocked
## the leaf swings 90 degrees outward (south) over 1.2 s with door_open. The leaf is the "Leaf" node
## that door_model.gd builds with its hinge at the east edge, so the hinge is the pivot. The free edge
## is then the west edge. Rotation about Y by +90 degrees carries that free edge to the south (QUESTION-64).

const Doc := preload("res://scripts/world/door_model.gd")
const OPEN_YAW_DEG := 90.0
const CLOSED_YAW_DEG := 0.0

var _leaf: Node3D = null
var _anchor: Node = null
var _unlocked := false
var _open := false


## Finds the door in the hall root. Returns false when the hall has no exit door.
func setup(hall: Node) -> bool:
	if hall == null:
		return false
	var door := hall.get_node_or_null("ExitDoor") as Node3D
	if door == null:
		return false
	_anchor = door
	_leaf = door.get_node_or_null("Leaf") as Node3D
	return _leaf != null


func is_unlocked() -> bool:
	return _unlocked


func is_open() -> bool:
	return _open


func unlock() -> void:
	_unlocked = true


## Closed and locked, as at the start of the duplicate hall (spec 15.2 step 4).
func reset_closed_locked() -> void:
	_unlocked = false
	_open = false
	if _leaf != null:
		_leaf.rotation.y = deg_to_rad(CLOSED_YAW_DEG)


## Swings the leaf open over seconds. A second call does nothing.
func swing_open(seconds: float) -> void:
	if _open or _leaf == null or _anchor == null:
		return
	_open = true
	var tween := _anchor.create_tween()
	tween.tween_property(_leaf, "rotation:y", deg_to_rad(OPEN_YAW_DEG), seconds)


## The leaf's free edge in world space, for checks (after the swing it lies south of the hinge).
## The leaf runs from its hinge at leaf-local x 0 to the free edge at leaf-local x DOOR_WIDTH.
func free_edge_world() -> Vector3:
	if _leaf == null:
		return Vector3.ZERO
	return _leaf.to_global(Vector3(Doc.DOOR_WIDTH, 0.0, 0.0))
