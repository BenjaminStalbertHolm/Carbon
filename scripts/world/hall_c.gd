extends Node3D
## Hall C builder (spec 6.1, 5.4, 8.9 to 8.13). build() creates the whole hall under
## a parent and returns its root node, named HallC. Coordinates are metres, +X east,
## +Y up, -Z north, origin at the centre of the floor (spec 3.5).
##
## Named nodes are direct children of the root so later code can find them:
## Desk01..Desk12, Chair01..Chair12, Clerk01..Clerk11 (no Clerk04 or Clerk12),
## Typewriter01..Typewriter12, Tube01..Tube12, Lamp04, Fixture1..Fixture6, Clock,
## ClockHourHand, ClockMinuteHand, QuotaBoard, SupervisorDoor, ExitDoor, VentGrille,
## WallNorth, WallSouth, WallEast, WallWest, Ceiling, Floor, Windows (with Window1..4).
## Desk parts are children of their desk (Desk04/Top, Desk04/Nameplate, ...).
##
## Options: "nameplates" (Dictionary desk number string -> text), "occupied_desks"
## (Array of ints, default all except 12) and "player_name" (String, default "0412").
## The player's desk (4) is always occupied.

const Geo := preload("res://scripts/world/geometry.gd")
const TextTex := preload("res://scripts/world/text_texture.gd")
const DeskModel := preload("res://scripts/world/desk.gd")
const ChairModel := preload("res://scripts/world/chair.gd")
const TypewriterModel := preload("res://scripts/world/typewriter_model.gd")
const TubeModel := preload("res://scripts/world/tube_terminal_model.gd")
const ClerkFigure := preload("res://scripts/world/clerk_figure.gd")
const ClockModel := preload("res://scripts/world/clock_model.gd")
const FixtureModel := preload("res://scripts/world/fixture.gd")
const DoorModel := preload("res://scripts/world/door_model.gd")
const Nameplate := preload("res://scripts/world/nameplate.gd")
const Content := preload("res://scripts/logic/content.gd")

const PLAYER_DESK := 4
const DESK_X := [-5.25, -1.75, 1.75, 5.25]
const DESK_Z := [3.5, 0.5, -2.5]
const CHAIR_OFFSET := 0.55
const CHAIR_OFFSET_DESK_12 := 0.20
const NAMEPLATE_POS := Vector3(0.0, 0.77, -0.36)
const WALL_HEIGHT := 3.2
const DADO_Y := 1.1
const DADO_HEIGHT := 0.04
const DADO_DEPTH := 0.02
const COL_DADO := Color("#3F4637")
const COL_VENT := Color("#3F3F3A")
const COL_SLAT := Color("#1E1E1C")
const COL_WINDOW := Color("#B8C0BC")
const FIXTURE_XZ := [
	Vector2(-3.5, 3.5), Vector2(3.5, 3.5), Vector2(-3.5, 0.5),
	Vector2(3.5, 0.5), Vector2(-3.5, -2.5), Vector2(3.5, -2.5),
]
## Day 1 nameplate text (spec 8.9), read from data/strings.json. Desk 4 is replaced
## by player_name. Desk 12 is blank.
static func default_nameplates() -> Dictionary:
	return Content.strings().nameplates.duplicate()


## Builds Hall C under parent and returns the HallC root node.
static func build(parent: Node3D, options: Dictionary = {}) -> Node:
	var root := Node3D.new()
	root.name = "HallC"
	parent.add_child(root)
	var occupied := _occupied_list(options)
	var texts := _nameplate_texts(options)
	_add_environment(root)
	_add_shell(root)
	_add_windows(root)
	_add_boards(root, occupied)
	_add_clock_and_vent(root)
	_add_fixtures(root)
	_add_desks(root, occupied, texts)
	return root


## Centre of desk n (1..12), spec 6.1: Desks 1-4 south row, 5-8 middle, 9-12 north, west to east.
static func desk_centre(n: int) -> Vector3:
	var col := (n - 1) % 4
	var row := (n - 1) / 4
	return Vector3(DESK_X[col], 0.0, DESK_Z[row])


static func _occupied_list(options: Dictionary) -> Array:
	var given: Array = options.get("occupied_desks", [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
	var list: Array = []
	for n in given:
		if not list.has(int(n)):
			list.append(int(n))
	if not list.has(PLAYER_DESK):
		list.append(PLAYER_DESK)
	return list


static func _nameplate_texts(options: Dictionary) -> Dictionary:
	var texts: Dictionary = default_nameplates()
	var given: Dictionary = options.get("nameplates", {})
	for key in given:
		texts[str(key)] = str(given[key])
	texts["4"] = str(options.get("player_name", texts["4"]))
	return texts


static func _add_environment(root: Node3D) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#3A3A34")
	env.ambient_light_energy = 1.0
	env.fog_enabled = false
	env.ssao_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	env.glow_enabled = false
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	root.add_child(world_env)


## Walls, dado rails, floor and ceiling (spec 6.1 and 5.7).
static func _add_shell(root: Node3D) -> void:
	_wall(root, "WallNorth", Vector3(0.0, 0.0, -6.1), Vector3(18.4, WALL_HEIGHT, 0.2), Vector3(0, 0, 1), 18.0)
	_wall(root, "WallSouth", Vector3(0.0, 0.0, 6.1), Vector3(18.4, WALL_HEIGHT, 0.2), Vector3(0, 0, -1), 18.0)
	_wall(root, "WallEast", Vector3(9.1, 0.0, 0.0), Vector3(0.2, WALL_HEIGHT, 12.0), Vector3(-1, 0, 0), 12.0)
	_wall(root, "WallWest", Vector3(-9.1, 0.0, 0.0), Vector3(0.2, WALL_HEIGHT, 12.0), Vector3(1, 0, 0), 12.0)
	Geo.add(root, Geo.quad(18.0, 12.0, Geo.TEX_FLOOR, Geo.WHITE, 1.0, 0.0, "Floor"), Vector3.ZERO, Vector3(-90, 0, 0))
	Geo.add(root, Geo.quad(18.0, 12.0, Geo.TEX_CEILING, Geo.WHITE, 0.6, 0.0, "Ceiling"),
		Vector3(0.0, WALL_HEIGHT, 0.0), Vector3(90, 0, 0))


## One wall: lower box (wall_lower below 1.1 m), upper box (wall_upper above), a
## collision box, and a dado rail on the room-side face. inward is the unit vector
## pointing into the room; rail_len is the interior length of the rail.
static func _wall(root: Node3D, wall_name: String, centre: Vector3, size: Vector3, inward: Vector3, rail_len: float) -> void:
	var wall := Geo.group(root, wall_name)
	var upper_h := WALL_HEIGHT - DADO_Y
	Geo.add(wall, Geo.box(Vector3(size.x, DADO_Y, size.z), Geo.TEX_WALL_LOWER, Geo.WHITE, 1.5, "Lower"),
		Vector3(centre.x, DADO_Y * 0.5, centre.z))
	Geo.add(wall, Geo.box(Vector3(size.x, upper_h, size.z), Geo.TEX_WALL_UPPER, Geo.WHITE, 1.5, "Upper"),
		Vector3(centre.x, DADO_Y + upper_h * 0.5, centre.z))
	# The rail sits 0.01 m inside the interior face, with thickness DADO_DEPTH.
	var along_x := absf(inward.z) > 0.5
	var rail_size := Vector3(rail_len, DADO_HEIGHT, DADO_DEPTH) if along_x else Vector3(DADO_DEPTH, DADO_HEIGHT, rail_len)
	var rail_centre := Vector3(centre.x, DADO_Y, centre.z) + inward * 0.11
	Geo.add(wall, Geo.solid(rail_size, COL_DADO, "Dado"), rail_centre)
	wall.add_child(Geo.static_box(size, Vector3(centre.x, WALL_HEIGHT * 0.5, centre.z), "Collision"))


static func _add_windows(root: Node3D) -> void:
	var windows := Geo.group(root, "Windows")
	var zs := [-4.5, -1.5, 1.5, 4.5]
	for i in 4:
		Geo.add(windows, Geo.quad(1.2, 1.0, Geo.TEX_FROSTED, COL_WINDOW, 0.0, 0.25, "Window%d" % (i + 1)),
			Vector3(8.99, 1.8 + 0.5, zs[i]), Vector3(0, -90, 0))


## Quota board on the west wall (spec 8.11) and the supervisor and exit doors.
static func _add_boards(root: Node3D, occupied: Array) -> void:
	var seated := 0
	for n in occupied:
		if n >= 1 and n <= 11:
			seated += 1
	var board := Geo.quad(1.6, 1.0, TextTex.quota_board(root, seated), Geo.WHITE, 0.0, 0.0, "QuotaBoard")
	Geo.add(root, board, Vector3(-8.88, 1.6, 0.0), Vector3(0, 90, 0))
	DoorModel.build_supervisor(root)
	DoorModel.build_exit(root)


static func _add_clock_and_vent(root: Node3D) -> void:
	ClockModel.build(root, "08:58")
	var vent := Geo.group(root, "VentGrille", Vector3(5.25, 3.19, 3.5))
	Geo.add(vent, Geo.quad(0.4, 0.4, Geo.TEX_WHITE, COL_VENT, 0.0, 0.0, "Grille"), Vector3.ZERO, Vector3(90, 0, 0))
	for i in 5:
		var z := -0.16 + 0.08 * float(i)
		Geo.add(vent, Geo.solid(Vector3(0.36, 0.004, 0.012), COL_SLAT, "Slat%d" % i), Vector3(0, -0.002, z))


static func _add_fixtures(root: Node3D) -> void:
	for i in 6:
		FixtureModel.build(root, i + 1, FIXTURE_XZ[i])


## Desks, nameplates, chairs, typewriters, tube terminals, clerks and the Desk 4 lamp.
static func _add_desks(root: Node3D, occupied: Array, texts: Dictionary) -> void:
	var atlas := TextTex.keycap_atlas(root)
	for n in range(1, 13):
		var centre := desk_centre(n)
		var key := str(n)
		var desk := DeskModel.build(root, "Desk%02d" % n, centre)
		var text: String = texts[key]
		Nameplate.build(desk, text, NAMEPLATE_POS)
		if n == PLAYER_DESK:
			DeskModel.build_items(desk)
			_add_desk4_lamp(root, centre)
		var offset := CHAIR_OFFSET_DESK_12 if n == 12 else CHAIR_OFFSET
		var chair := ChairModel.build(root, "Chair%02d" % n, centre + Vector3(0, 0, offset))
		TypewriterModel.build(root, "Typewriter%02d" % n, centre, atlas)
		TubeModel.build(root, "Tube%02d" % n, centre)
		if n != PLAYER_DESK and n != 12 and occupied.has(n):
			ClerkFigure.build(root, "Clerk%02d" % n, centre + Vector3(0, 0, CHAIR_OFFSET), chair)


## Desk lamp light (spec 8.12): SpotLight3D inside the shade, pointing down 75 degrees.
static func _add_desk4_lamp(root: Node3D, desk_centre_pos: Vector3) -> void:
	var lamp := SpotLight3D.new()
	lamp.name = "Lamp04"
	lamp.position = desk_centre_pos + Vector3(-0.55, 1.13, -0.32)
	lamp.rotation_degrees = Vector3(-75, 0, 0)
	lamp.light_color = Color("#F0E2C0")
	lamp.light_energy = 0.8
	lamp.spot_range = 1.5
	lamp.spot_angle = 50.0
	lamp.shadow_enabled = false
	root.add_child(lamp)
