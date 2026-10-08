extends Node
## Desk lamp (spec 8.12, 13.5, 6.4). The light is the SpotLight3D Lamp04 that hall_c.gd builds,
## and the shade is Desk04/Lamp/LampShade. The light follows GameState.lamp_on: DayDirector
## switches it off after the End of Shift memo and at the day end, and begins each day lit.
## A click always makes lamp_click (spec 6.4), and DayDirector.click_lamp() decides the rest.
## The click sound is played here, on the DayDirector.lamp_click signal, so it is not played twice.

const LIGHT_ENERGY := 0.8
# TODO(QUESTION): spec 8.12 says the shade emission goes off with the lamp but gives no level.
# Placeholder: 1.0, the same as the lit fluorescent tubes.
const SHADE_EMISSION_ON := 1.0
const SHADE_EMISSION_OFF := 0.0
## Scripted or player click: played at the file's own level (gain 0 dB, QUESTION-29). The file
## peaks at -20 dBFS, which meets Rule B for a player-caused sound (spec 11.1).
const CLICK_GAIN_DB := 0.0

var _light: Light3D = null
var _shade: MeshInstance3D = null
var _last := -1  # -1 unknown, 0 off, 1 on


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## hall is the HallC root. Connects the click sound to DayDirector.lamp_click.
func setup(hall: Node) -> bool:
	_light = hall.get_node_or_null("Lamp04") as Light3D
	var desk := hall.get_node_or_null("Desk04")
	if desk != null:
		_shade = desk.find_child("LampShade", true, false) as MeshInstance3D
	var dd := _autoload("DayDirector")
	if dd != null and not dd.lamp_click.is_connected(_on_lamp_click):
		dd.lamp_click.connect(_on_lamp_click)
	_sync()
	return _light != null


## Whether the lamp is lit right now (for tests and the screenshots).
func is_lit() -> bool:
	return _light != null and _light.visible and _light.light_energy > 0.0


func _process(_delta: float) -> void:
	_sync()


func _sync() -> void:
	var gs := _autoload("GameState")
	if gs == null:
		return
	var on := 1 if bool(gs.lamp_on) else 0
	if on == _last:
		return
	_last = on
	if _light != null:
		_light.visible = on == 1
		_light.light_energy = LIGHT_ENERGY if on == 1 else 0.0
	if _shade != null and _shade.material_override is ShaderMaterial:
		(_shade.material_override as ShaderMaterial).set_shader_parameter(
			"emission_strength", SHADE_EMISSION_ON if on == 1 else SHADE_EMISSION_OFF)


func _on_lamp_click() -> void:
	var ad := _autoload("AudioDirector")
	if ad != null and ad.has_method("play"):
		ad.play("lamp_click", _light.global_position if _light != null else Vector3.ZERO, false, CLICK_GAIN_DB, true)


func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
