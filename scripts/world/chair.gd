extends RefCounted
## Office chair (spec 5.4). Origin at the chair centre on the floor, facing north.
## The seat top is at y 0.48 and the seat centre at y 0.46.

const Geo := preload("res://scripts/world/geometry.gd")

const COL_FRAME := Color("#2E2E2C")


static func build(parent: Node3D, chair_name: String, pos: Vector3) -> Node3D:
	var chair := Geo.group(parent, chair_name, pos)
	Geo.add(chair, Geo.box(Vector3(0.44, 0.04, 0.42), Geo.TEX_WOOD, Geo.WHITE, 1.0, "Seat"), Vector3(0, 0.46, 0))
	# Backrest rises from the seat's south edge, its south face flush with that edge.
	Geo.add(chair, Geo.box(Vector3(0.42, 0.36, 0.03), Geo.TEX_WOOD, Geo.WHITE, 1.0, "Back"), Vector3(0, 0.66, 0.195))
	var i := 0
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			Geo.add(chair, Geo.solid(Vector3(0.03, 0.46, 0.03), COL_FRAME, "Leg%d" % i), Vector3(0.20 * sx, 0.23, 0.19 * sz))
			i += 1
	# Chair body collision, shared with the clerk seated in it (spec 6.1).
	chair.add_child(Geo.static_box(Vector3(0.44, 0.84, 0.42), Vector3(0, 0.42, 0), "ChairCollision"))
	return chair
