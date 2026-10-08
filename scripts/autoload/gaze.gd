extends Node
## Gaze: per-frame visibility queries for tracked nodes (spec 9.1). Autoload.
## Computed in _physics_process so the look raycast uses the camera's physics space.
##
## A node's extent is the union of the world AABBs of its visible MeshInstance3D
## descendants. Own colliders (every CollisionObject3D under the node, plus any node
## listed in the meta "gaze_own", such as a clerk's shared chair body) are ignored
## by the look raycast.

const LOOK_ANGLE_DEG := 12.0
const DEBUG_LAYER := 100

var _camera: Camera3D = null
var _tracked: Array = []
var _data := {}  # instance id -> {in, looked, unseen, seen, dist}
var _overlay_open := false
var _overlay_exempt: Node = null
var _overlay_on := false
var _overlay_layer: CanvasLayer = null
var _overlay_label: Label = null


func track(node: Node3D) -> void:
	if node == null or _tracked.has(node):
		return
	_tracked.append(node)
	_data[node.get_instance_id()] = {"in": false, "looked": false, "unseen": 0.0, "seen": 0.0, "dist": INF}


func untrack(node: Node3D) -> void:
	if node == null:
		return
	_tracked.erase(node)
	_data.erase(node.get_instance_id())


func set_camera(cam: Camera3D) -> void:
	_camera = cam


## Read view or other overlay open: every tracked node counts as out of frustum,
## except exempt (the typewriter while the typing view is open, spec 9.1).
func overlay_open(on: bool, exempt: Node = null) -> void:
	_overlay_open = on
	_overlay_exempt = exempt if on else null


func is_in_frustum(node: Node) -> bool:
	return bool(_entry(node).get("in", false))


func is_looked_at(node: Node) -> bool:
	return bool(_entry(node).get("looked", false))


func unseen_time(node: Node) -> float:
	return float(_entry(node).get("unseen", 0.0))


func seen_time(node: Node) -> float:
	return float(_entry(node).get("seen", 0.0))


## Floor-plane distance (x and z only) from the camera to the node's box centre, in metres, as of the
## last physics frame (QUESTION-67). The ghost trigger (spec 10.3), the apply rule (spec 9.2) and the
## Desk 12 rule (spec 9.3 D3-U1) all read this.
func distance_to_camera(node: Node) -> float:
	return float(_entry(node).get("dist", INF))


## Floor-plane distance from the live camera to a point, in metres (INF without a camera).
func camera_floor_distance(point: Vector3) -> float:
	if _camera == null or not _camera.is_inside_tree():
		return INF
	return floor_distance(_camera.global_transform.origin, point)


## Floor-plane distance between two points: their x and z components only (QUESTION-67).
static func floor_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


func set_overlay(on: bool) -> void:
	_overlay_on = on
	if on and _overlay_layer == null:
		_overlay_layer = CanvasLayer.new()
		_overlay_layer.layer = DEBUG_LAYER
		_overlay_label = Label.new()
		_overlay_label.position = Vector2(8, 8)
		_overlay_layer.add_child(_overlay_label)
		add_child(_overlay_layer)
	if _overlay_layer != null:
		_overlay_layer.visible = on


func _entry(node: Node) -> Dictionary:
	if node == null or not is_instance_valid(node):
		return {}
	return _data.get(node.get_instance_id(), {})


func _physics_process(delta: float) -> void:
	_prune()
	var planes: Array = []
	var cam_pos := Vector3.ZERO
	var forward := Vector3.FORWARD
	var space: PhysicsDirectSpaceState3D = null
	var have_cam := _camera != null and _camera.is_inside_tree()
	if have_cam:
		planes = _camera.get_frustum()
		cam_pos = _camera.global_transform.origin
		forward = -_camera.global_transform.basis.z
		space = _camera.get_world_3d().direct_space_state
	for node in _tracked:
		var d: Dictionary = _data[node.get_instance_id()]
		var box := world_aabb(node)
		var has_box := box.size != Vector3.ZERO
		var inside := false
		var looked := false
		var dist := INF
		if has_box and have_cam:
			dist = floor_distance(cam_pos, box.get_center())
			if not _overlay_open or node == _overlay_exempt:
				inside = aabb_in_planes(box, planes)
		if inside:
			looked = _is_looked_at(node, box, cam_pos, forward, space)
		d["in"] = inside
		d["looked"] = looked
		d["dist"] = dist
		d["unseen"] = 0.0 if inside else float(d["unseen"]) + delta
		d["seen"] = (float(d["seen"]) + delta) if looked else 0.0
	if _overlay_on:
		_update_overlay()


## True when the box is at least partly inside every plane. Plane normals point
## outward, so a point is inside when Plane.distance_to(point) <= 0.
static func aabb_in_planes(box: AABB, planes: Array) -> bool:
	var c := box.get_center()
	var e := box.size * 0.5
	for p in planes:
		var pl: Plane = p
		var n := pl.normal
		var most_inside := c - Vector3(signf(n.x) * e.x, signf(n.y) * e.y, signf(n.z) * e.z)
		if pl.distance_to(most_inside) > 0.0:
			return false
	return true


## World-space bounds of the visible mesh descendants of node. Zero size when none.
static func world_aabb(node: Node) -> AABB:
	var out := AABB()
	var first := true
	var stack: Array = [node]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			if mi.mesh != null and mi.is_visible_in_tree():
				var box: AABB = mi.global_transform * mi.get_aabb()
				if first:
					out = box
					first = false
				else:
					out = out.merge(box)
		for c in n.get_children():
			stack.append(c)
	return out


func _is_looked_at(node: Node, box: AABB, cam_pos: Vector3, forward: Vector3, space: PhysicsDirectSpaceState3D) -> bool:
	var target := box.get_center()
	var to := target - cam_pos
	var dist := to.length()
	if dist < 0.0001:
		return true
	if forward.dot(to / dist) < cos(deg_to_rad(LOOK_ANGLE_DEG)):
		return false
	if space == null:
		return true
	var q := PhysicsRayQueryParameters3D.create(cam_pos, target)
	q.exclude = _own_colliders(node)
	q.collide_with_areas = false
	return space.intersect_ray(q).is_empty()


func _own_colliders(node: Node) -> Array[RID]:
	var out: Array[RID] = []
	_collect_rids(node, out)
	if node.has_meta("gaze_own"):
		for extra in node.get_meta("gaze_own"):
			if extra is Node and is_instance_valid(extra):
				_collect_rids(extra, out)
	return out


static func _collect_rids(n: Node, out: Array[RID]) -> void:
	if n is CollisionObject3D:
		out.append((n as CollisionObject3D).get_rid())
	for c in n.get_children():
		_collect_rids(c, out)


func _prune() -> void:
	var keep: Array = []
	for node in _tracked:
		if is_instance_valid(node):
			keep.append(node)
	_tracked = keep
	for id in _data.keys():
		if not is_instance_id_valid(id):
			_data.erase(id)


func _update_overlay() -> void:
	var lines := PackedStringArray()
	for node in _tracked:
		var d: Dictionary = _data[node.get_instance_id()]
		lines.append("%s in=%s look=%s unseen=%.1f seen=%.1f" % [
			node.name, str(d["in"]), str(d["looked"]), float(d["unseen"]), float(d["seen"])])
	_overlay_label.text = "\n".join(lines)
