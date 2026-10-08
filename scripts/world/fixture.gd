extends RefCounted
## Fluorescent fixture (spec 8.12). The light is an OmniLight3D named FixtureN at
## y 3.0. Its housing box (flush to the ceiling) and emissive tube quad are children,
## positioned relative to the light. Flicker and the off rule are later milestones.

const Geo := preload("res://scripts/world/geometry.gd")

const LIGHT_COLOUR := Color("#E8F0E0")
const HOUSING_COLOUR := Color("#C9C6B5")
const LIGHT_Y := 3.0


static func build(parent: Node3D, index: int, xz: Vector2) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "Fixture%d" % index
	light.position = Vector3(xz.x, LIGHT_Y, xz.y)
	light.light_color = LIGHT_COLOUR
	light.light_energy = 1.2
	light.omni_range = 6.0
	light.omni_attenuation = 1.0
	light.shadow_enabled = false
	parent.add_child(light)
	# Housing 1.2 x 0.08 x 0.25 with its top at the ceiling (3.2).
	Geo.add(light, Geo.solid(Vector3(1.2, 0.08, 0.25), HOUSING_COLOUR, "Housing"), Vector3(0, 0.16, 0))
	# Emissive tube strip under the housing, facing down.
	Geo.add(light, Geo.quad(1.12, 0.18, Geo.TEX_WHITE, LIGHT_COLOUR, 0.0, 1.0, "Tube"),
		Vector3(0, 0.118, 0), Vector3(90, 0, 0))
	return light
