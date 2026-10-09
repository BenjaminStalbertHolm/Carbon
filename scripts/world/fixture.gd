extends RefCounted
## Fluorescent fixture (spec 8.12). The light is an OmniLight3D named FixtureN at
## y 3.0. Its housing box (flush to the ceiling) and emissive tube quad are children,
## positioned relative to the light. A child node named Flicker steps the fixture's flicker
## pattern from the game clock (10 steps per second, looping). Each letter multiplies the
## light's base energy and the tube's base emission strength: m 1.00, k 0.55, h 0.25.
## REDUCE FLICKER (spec 16.3) holds every fixture at constant m. set_held holds one fixture
## at constant m (the endings' no-flicker shots, spec 15.1 step 6 and 15.2 step 4). The off
## rule is a later milestone.

const Geo := preload("res://scripts/world/geometry.gd")

const LIGHT_COLOUR := Color("#E8F0E0")
const HOUSING_COLOUR := Color("#C9C6B5")
const LIGHT_Y := 3.0
const BASE_ENERGY := 1.2
const BASE_EMISSION := 1.0
const STEP_S := 0.1  # 10 steps per second (spec 8.12)
const HELD_META := "flicker_held"
const MULTIPLIER := {"m": 1.0, "k": 0.55, "h": 0.25}

## Flicker patterns (spec 8.12 table), by day, then by fixture number. Every other day and
## fixture is constant m.
const PATTERNS := {
	2: {4: "mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmkmmmmmmmmmmmmmmmmmmmmmmmmmmmm"},
	3: {
		4: "mmmmmmmmmmmmmmmmmmmmmkmmmmmmmmmmmmmmmmmkmmmmmmmmmmmmmmmmmmmm",
		6: "mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmhmmm",
	},
	4: {
		4: "mmmmmmmmmmmkmmmmmmmmmmmmmmmkmmmmmmmmmmmmmkmmmmmmmmmmmmmmmmmm",
		6: "mmmmmmmmmmmmmmmmmmmmhmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmhmmmmm",
	},
	5: {2: "mmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmmkmmmmmmmmmmmm"},
}


## Builds one fixture under parent and returns its light (spec 8.12). The light gets a
## Flicker child that drives it.
static func build(parent: Node3D, index: int, xz: Vector2) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "Fixture%d" % index
	light.position = Vector3(xz.x, LIGHT_Y, xz.y)
	light.light_color = LIGHT_COLOUR
	light.light_energy = BASE_ENERGY
	light.omni_range = 6.0
	light.omni_attenuation = 1.0
	light.shadow_enabled = false
	parent.add_child(light)
	# Housing 1.2 x 0.08 x 0.25 with its top at the ceiling (3.2).
	Geo.add(light, Geo.solid(Vector3(1.2, 0.08, 0.25), HOUSING_COLOUR, "Housing"), Vector3(0, 0.16, 0))
	# Emissive tube strip under the housing, facing down.
	Geo.add(light, Geo.quad(1.12, 0.18, Geo.TEX_WHITE, LIGHT_COLOUR, 0.0, BASE_EMISSION, "Tube"),
		Vector3(0, 0.118, 0), Vector3(90, 0, 0))
	var driver := Flicker.new()
	driver.name = "Flicker"
	driver.fixture = index
	light.add_child(driver)
	return light


## The Flicker node of a fixture light built by build(), or null.
static func driver_of(light: Node) -> Node:
	return light.get_node_or_null("Flicker")


## Holds a fixture at constant m until released (set_held(light, false)).
static func set_held(light: Node, held: bool) -> void:
	light.set_meta(HELD_META, held)


## Flicker pattern of a fixture on a day (spec 8.12 table). Constant m when none is listed.
static func pattern_for(day: int, index: int) -> String:
	return Flicker.pattern_for(day, index)


## Multiplier of the step-th letter of a pattern, looping (spec 8.12).
static func multiplier_for(pattern: String, step: int) -> float:
	return Flicker.multiplier_for(pattern, step)


## Steps one fixture's flicker pattern from the game clock and applies it to its light and
## tube. Child of the light, so it pauses with the tree.
class Flicker extends Node:
	var fixture := 1
	var _acc := 0.0
	var _step := 0

	static func pattern_for(day: int, index: int) -> String:
		var by_fixture: Dictionary = PATTERNS.get(day, {})
		return String(by_fixture.get(index, "m"))

	static func multiplier_for(pattern: String, step: int) -> float:
		var letter := pattern.substr(step % pattern.length(), 1)
		return float(MULTIPLIER.get(letter, MULTIPLIER["m"]))

	func _process(delta: float) -> void:
		advance(delta)

	## Advances the clock by dt seconds, counting whole steps (10 per second), then applies
	## the current multiplier. A fixed dt gives a fixed step count.
	func advance(dt: float) -> void:
		_acc += dt
		while _acc + 0.000001 >= STEP_S:
			_acc -= STEP_S
			_step += 1
		_apply()

	## Number of whole steps taken since the fixture was built.
	func step_index() -> int:
		return _step

	## Multiplier now: 1.00 under REDUCE FLICKER or when the light is held, otherwise the
	## pattern's letter for the current step.
	func multiplier() -> float:
		var light := get_parent()
		if _reduce_flicker() or (light != null and bool(light.get_meta(HELD_META, false))):
			return 1.0
		return multiplier_for(pattern_for(_day(), fixture), _step)

	func _apply() -> void:
		var light := get_parent() as OmniLight3D
		if light == null or not light.visible:
			return
		var m := multiplier()
		light.light_energy = BASE_ENERGY * m
		var tube := light.get_node_or_null("Tube") as MeshInstance3D
		if tube != null and tube.material_override is ShaderMaterial:
			(tube.material_override as ShaderMaterial).set_shader_parameter("emission_strength", BASE_EMISSION * m)

	func _day() -> int:
		var gs = _autoload("GameState")
		return int(gs.day) if gs != null else 1

	func _reduce_flicker() -> bool:
		var ss = _autoload("SaveSystem")
		return ss != null and bool(ss.get_setting("reduce_flicker"))

	func _autoload(node_name: String):
		var tree := Engine.get_main_loop() as SceneTree
		return tree.root.get_node_or_null(node_name) if tree != null else null
