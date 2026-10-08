extends Node
## Desk 4 drawers (spec 5.4, 6.4, 8.5, 13.5). The top and lower drawers slide 0.30 m south
## (+Z) in 0.4 s; a click on a drawer front toggles it. The notebook sits in the top drawer
## and is clickable only while that drawer is open. Filed carbons sit in the lower drawer and
## move with it. The drawer parts are children of the Desk04 node, so only their positions move.
## Parent: desk4_items.gd calls setup(desk) once and toggle(which) on each click.

const SLIDE_S := 0.4
const SLIDE_M := 0.30
const PICK_LAYER := 2

const PARTS := {
	"top": ["DrawerTop", "PullTop", "Notebook"],
	"lower": ["DrawerLower", "PullLower", "FiledCarbons"],
}

var _desk: Node3D = null
var _open := {"top": false, "lower": false}
var _k := {"top": 0.0, "lower": 0.0}  # 0 closed, 1 fully open
var _rest := {}  # node name -> rest position in Desk04 space
var _notebook_shape: CollisionShape3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## desk is the Desk04 node. Records the rest positions and builds the drawer pick bodies.
func setup(desk: Node3D) -> bool:
	_desk = desk
	if desk == null:
		return false
	for which in PARTS.keys():
		for part in PARTS[which]:
			var node := desk.get_node_or_null(part) as Node3D
			if node != null:
				_rest[part] = node.position
	_add_pick(desk.get_node_or_null("DrawerTop"), "drawer_top", Vector3(0.36, 0.15, 0.02))
	_add_pick(desk.get_node_or_null("DrawerLower"), "drawer_lower", Vector3(0.36, 0.40, 0.02))
	var notebook := desk.get_node_or_null("Notebook") as Node3D
	var pick := _add_pick(notebook, "notebook", Vector3(0.15, 0.03, 0.21))
	if pick != null:
		_notebook_shape = pick.get_child(0) as CollisionShape3D
		_notebook_shape.disabled = true
	_apply("top", 0.0)
	_apply("lower", 0.0)
	return true


## Toggles one drawer: "top" or "lower". The slide runs over SLIDE_S seconds.
func toggle(which: String) -> void:
	if not _open.has(which):
		return
	_open[which] = not _open[which]
	if which == "top" and _notebook_shape != null:
		_notebook_shape.disabled = not _open["top"]


func is_open(which: String) -> bool:
	return bool(_open.get(which, false))


## Notebook clicks are accepted only while the top drawer is open (spec 6.4).
func notebook_clickable() -> bool:
	return is_open("top")


## Current slide of one drawer in metres (0 closed, 0.30 open). For tests and the screenshots.
func slide_metres(which: String) -> float:
	return SLIDE_M * float(_k.get(which, 0.0))


func _process(delta: float) -> void:
	for which in ["top", "lower"]:
		var target := 1.0 if _open[which] else 0.0
		var k: float = _k[which]
		if k != target:
			k = move_toward(k, target, delta / SLIDE_S)
			_k[which] = k
			_apply(which, k)


func _apply(which: String, k: float) -> void:
	if _desk == null:
		return
	var eased := k * k * (3.0 - 2.0 * k)
	var offset := Vector3(0.0, 0.0, SLIDE_M * eased)
	for part in PARTS[which]:
		var node := _desk.get_node_or_null(part) as Node3D
		if node != null and _rest.has(part):
			node.position = _rest[part] + offset


func _add_pick(parent: Node3D, action: String, size: Vector3) -> StaticBody3D:
	if parent == null:
		return null
	var body := StaticBody3D.new()
	body.name = "Pick"
	body.collision_layer = PICK_LAYER
	body.collision_mask = 0
	body.set_meta("action", action)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)
	return body
