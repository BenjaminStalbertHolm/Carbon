extends RefCounted
## Pneumatic tube terminal model (spec 5.4). Origin at the desk centre; offsets are
## desk-relative. The tube runs from the ceiling (y 3.2) down to y 1.10 at the desk's
## left-back corner (x - 0.62, z - 0.30). The canister is hidden until a tube
## arrival or send (M6).

const Geo := preload("res://scripts/world/geometry.gd")

const COL_BRASS := Color("#8C7340")
const CORNER := Vector3(-0.62, 0.0, -0.30)
const TUBE_TOP := 3.2
const TUBE_BOTTOM := 1.10


static func build(parent: Node3D, node_name: String, desk_centre: Vector3) -> Node3D:
	var root := Geo.group(parent, node_name, desk_centre)
	var length := TUBE_TOP - TUBE_BOTTOM
	# The top cap is hidden against the ceiling, so it is not built.
	Geo.add(root, Geo.cylinder(0.06, length, 8, COL_BRASS, "Tube", false, true),
		CORNER + Vector3(0, TUBE_BOTTOM + length * 0.5, 0))
	Geo.add(root, Geo.solid(Vector3(0.20, 0.25, 0.20), COL_BRASS, "Receiver"),
		CORNER + Vector3(0, 0.74 + 0.125, 0))
	# Hinged front flap on the south face of the receiver.
	Geo.add(root, Geo.solid(Vector3(0.16, 0.18, 0.01), COL_BRASS, "Flap"),
		CORNER + Vector3(0, 0.74 + 0.125, 0.105))
	var canister := Geo.cylinder(0.05, 0.22, 8, COL_BRASS, "Canister")
	canister.visible = false
	Geo.add(root, canister, CORNER + Vector3(0, 1.10, 0))
	return root
