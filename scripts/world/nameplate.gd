extends RefCounted
## Desk nameplate (spec 5.4 and 5.5): a 0.24 x 0.06 x 0.03 body with the name on both
## faces, so it reads from either side of the desk. Empty text gives a blank plate.

const Geo := preload("res://scripts/world/geometry.gd")
const TextTex := preload("res://scripts/world/text_texture.gd")

const BODY_SIZE := Vector3(0.24, 0.06, 0.03)


## pos is the plate centre, relative to the parent desk.
static func build(parent: Node3D, text: String, pos: Vector3) -> Node3D:
	var plate := Geo.group(parent, "Nameplate", pos)
	Geo.add(plate, Geo.solid(BODY_SIZE, TextTex.COL_PLATE_BODY, "Body"))
	var tex := TextTex.nameplate(plate, text)
	var half := BODY_SIZE.z * 0.5 + 0.0001
	Geo.add(plate, Geo.quad(BODY_SIZE.x, BODY_SIZE.y, tex, Geo.WHITE, 0.0, 0.0, "FaceSouth"), Vector3(0, 0, half))
	Geo.add(plate, Geo.quad(BODY_SIZE.x, BODY_SIZE.y, tex, Geo.WHITE, 0.0, 0.0, "FaceNorth"), Vector3(0, 0, -half), Vector3(0, 180, 0))
	return plate
