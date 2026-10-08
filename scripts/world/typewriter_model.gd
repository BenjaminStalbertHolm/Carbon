extends RefCounted
## Typewriter model (spec 5.4). Origin at the desk centre; offsets are desk-relative.
## Keys are 8-segment cylinders whose legends come from one shared atlas texture.
## The paper is built but hidden (not loaded in M2). Interaction is M5.

const Geo := preload("res://scripts/world/geometry.gd")
const TextTex := preload("res://scripts/world/text_texture.gd")

const COL_BODY := Color("#4B5340")
const COL_KEYCAP := Color("#1E1E1C")
const COL_CHROME := Color("#A8A8A0")
const COL_PLATEN := Color("#141414")

const KEY_BASE_Y := 0.86
const KEY_PITCH := 0.032
## Each key row sits one key height higher than the row nearer the player (QUESTION-14).
const ROW_STEP := 0.012
## Desk-relative z of the four key rows, row 0 (numbers) furthest from the player.
const ROW_Z := [0.12, 0.15, 0.18, 0.21]
const SPACE_Z := 0.24
const CARRIAGE_Y := 0.885
const CARRIAGE_Z := -0.02


static func build(parent: Node3D, node_name: String, desk_centre: Vector3, atlas: Texture2D) -> Node3D:
	var tw := Geo.group(parent, node_name, desk_centre)
	Geo.add(tw, Geo.solid(Vector3(0.44, 0.12, 0.34), COL_BODY, "Body"), Vector3(0, 0.80, 0.10))
	_keys(tw, atlas)
	Geo.add(tw, Geo.solid(Vector3(0.22, 0.015, 0.03), COL_KEYCAP, "SpaceBar"), Vector3(0, KEY_BASE_Y + 0.0075, SPACE_Z))
	_carriage(tw)
	return tw


## 40 keycaps: four rows of ten in height steps, each with its legend from the atlas.
## Row 0 (numbers) is the highest step; row 3, nearest the player, is the lowest.
static func _keys(tw: Node3D, atlas: Texture2D) -> void:
	var keys := Geo.group(tw, "Keys")
	var side_uv := TextTex.keycap_side_uv()
	for r in 4:
		var y := KEY_BASE_Y + 0.006 + ROW_STEP * float(3 - r)
		for c in 10:
			var x := (float(c) - 4.5) * KEY_PITCH
			var cap := Geo.cylinder(0.009, 0.012, 8, Geo.WHITE, "Key%d%d" % [r, c], true, false,
				atlas, side_uv, TextTex.keycap_uv(r, c))
			Geo.add(keys, cap, Vector3(x, y, ROW_Z[r]))


static func _carriage(tw: Node3D) -> void:
	var carriage := Geo.group(tw, "Carriage", Vector3(0, CARRIAGE_Y, CARRIAGE_Z))
	Geo.add(carriage, Geo.solid(Vector3(0.52, 0.05, 0.08), COL_CHROME, "Frame"))
	Geo.add(carriage, Geo.cylinder(0.025, 0.48, 8, COL_PLATEN, "Platen"), Vector3.ZERO, Vector3(0, 0, 90))
	Geo.add(carriage, Geo.cylinder(0.02, 0.03, 8, COL_KEYCAP, "KnobLeft"), Vector3(-0.255, 0, 0), Vector3(0, 0, 90))
	Geo.add(carriage, Geo.cylinder(0.02, 0.03, 8, COL_KEYCAP, "KnobRight"), Vector3(0.255, 0, 0), Vector3(0, 0, 90))
	# Carriage return lever on the left end, angled 30 degrees up at its free end.
	Geo.add(carriage, Geo.solid(Vector3(0.10, 0.015, 0.015), COL_CHROME, "ReturnLever"),
		Vector3(-0.24, 0.0275, 0), Vector3(0, 0, -30))
	# Paper release lever on the right end.
	Geo.add(carriage, Geo.solid(Vector3(0.04, 0.04, 0.01), COL_CHROME, "ReleaseLever"), Vector3(0.24, 0.045, 0))
	_paper(carriage)


## Paper sheet, hidden in M2. Its bottom edge sits on the platen top and it leans back 15 degrees.
static func _paper(carriage: Node3D) -> void:
	var lean := deg_to_rad(15.0)
	var platen_top := Vector3(0, 0.025, 0)
	var centre := platen_top + Vector3(0, cos(lean), -sin(lean)) * 0.1485
	var sheet := Geo.quad(0.21, 0.297, Geo.TEX_PAPER, Geo.WHITE, 0.0, 0.0, "Paper")
	sheet.visible = false
	Geo.add(carriage, sheet, centre, Vector3(-15, 0, 0))
