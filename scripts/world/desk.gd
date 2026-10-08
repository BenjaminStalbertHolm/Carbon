extends RefCounted
## Office desk (spec 5.4) and the Desk 4 item table (spec 5.4). Origin at the desk
## centre on the floor. The desk faces north; the chair and player are to the south.
## Desk 4 items are plain models in M2 (interaction is M3).

const Geo := preload("res://scripts/world/geometry.gd")
const TextTex := preload("res://scripts/world/text_texture.gd")

const TOP_Y := 0.74
const COL_CHROME := Color("#A8A8A0")
const COL_BRASS := Color("#8C7340")
const COL_LAMP_SHADE := Color("#2F4F3A")
const COL_INK_PAD := Color("#2A2A2A")
const COL_MARKER := Color("#0E0E0E")
const COL_CORRECTION := Color("#F2EEE2")
const COL_NOTEBOOK := Color("#3B2E24")
const STAMP_APPROVED := Color("#2F3B5C")
const STAMP_DENIED := Color("#8E2A22")


## Desk body: top, steel pedestal with two drawer fronts, left legs, modesty panel,
## collision box, and the desk's north-edge slot for the nameplate.
static func build(parent: Node3D, desk_name: String, centre: Vector3) -> Node3D:
	var desk := Geo.group(parent, desk_name, centre)
	Geo.add(desk, Geo.box(Vector3(1.40, 0.04, 0.75), Geo.TEX_DESK_TOP, Geo.WHITE, 1.0, "Top"), Vector3(0, 0.72, 0))
	Geo.add(desk, Geo.box(Vector3(0.40, 0.70, 0.70), Geo.TEX_STEEL, Geo.WHITE, 1.0, "Pedestal"), Vector3(0.50, 0.35, 0))
	Geo.add(desk, Geo.box(Vector3(0.36, 0.15, 0.02), Geo.TEX_STEEL, Geo.WHITE, 1.0, "DrawerTop"), Vector3(0.50, 0.615, 0.36))
	Geo.add(desk, Geo.box(Vector3(0.36, 0.40, 0.02), Geo.TEX_STEEL, Geo.WHITE, 1.0, "DrawerLower"), Vector3(0.50, 0.30, 0.36))
	Geo.add(desk, Geo.solid(Vector3(0.10, 0.02, 0.02), COL_CHROME, "PullTop"), Vector3(0.50, 0.615, 0.38))
	Geo.add(desk, Geo.solid(Vector3(0.10, 0.02, 0.02), COL_CHROME, "PullLower"), Vector3(0.50, 0.30, 0.38))
	Geo.add(desk, Geo.box(Vector3(0.04, 0.70, 0.04), Geo.TEX_STEEL, Geo.WHITE, 1.0, "LegFrontLeft"), Vector3(-0.68, 0.35, 0.33))
	Geo.add(desk, Geo.box(Vector3(0.04, 0.70, 0.04), Geo.TEX_STEEL, Geo.WHITE, 1.0, "LegBackLeft"), Vector3(-0.68, 0.35, -0.33))
	Geo.add(desk, Geo.box(Vector3(1.00, 0.40, 0.02), Geo.TEX_STEEL, Geo.WHITE, 1.0, "Modesty"), Vector3(-0.20, 0.50, -0.36))
	desk.add_child(Geo.static_box(Vector3(1.40, TOP_Y, 0.75), Vector3(0, TOP_Y * 0.5, 0)))
	return desk


## Desk 4 items (spec 5.4 table), positions relative to the desk centre. Drawers are
## modelled closed; the notebook and filed carbons sit inside them.
static func build_items(desk: Node3D) -> void:
	Geo.add(desk, _open_tray("InboxTray", Vector3(0.26, 0.05, 0.34), 0.01), Vector3(-0.45, TOP_Y, 0.12))
	_flat_sheets(desk, "ReadStack", Vector3(-0.45, TOP_Y, -0.20), 3, Geo.TEX_PAPER)
	_copyholder(desk, Vector3(-0.30, TOP_Y, -0.05))
	Geo.add(desk, Geo.box(Vector3(0.24, 0.03, 0.32), Geo.TEX_STEEL, Geo.WHITE, 1.0, "BlankTray"), Vector3(0.45, TOP_Y + 0.015, -0.22))
	_flat_sheets(desk, "BlankStack", Vector3(0.45, TOP_Y + 0.03, -0.22), 10, Geo.TEX_PAPER)
	_flat_sheets(desk, "CarbonSpot", Vector3(0.45, TOP_Y, 0.18), 5, Geo.TEX_ONIONSKIN)
	_stamp_rack(desk, Vector3(0.30, TOP_Y, -0.32))
	Geo.add(desk, Geo.solid(Vector3(0.10, 0.015, 0.07), COL_INK_PAD, "InkPad"), Vector3(0.42, TOP_Y + 0.0075, -0.32))
	Geo.add(desk, Geo.cylinder(0.008, 0.13, 8, COL_MARKER, "Marker"), Vector3(0.25, TOP_Y + 0.008, 0.28), Vector3(0, 0, 90))
	Geo.add(desk, Geo.cylinder(0.015, 0.05, 8, COL_CORRECTION, "CorrectionBottle"), Vector3(0.36, TOP_Y + 0.025, 0.28))
	Geo.add(desk, Geo.cylinder(0.008, 0.02, 8, COL_INK_PAD, "CorrectionCap"), Vector3(0.36, TOP_Y + 0.06, 0.28))
	_desk_lamp(desk, Vector3(-0.55, TOP_Y, -0.32))
	Geo.add(desk, Geo.solid(Vector3(0.15, 0.015, 0.21), COL_NOTEBOOK, "Notebook"), Vector3(0.50, 0.60, 0.20))
	Geo.add(desk, Geo.box(Vector3(0.21, 0.06, 0.297), Geo.TEX_ONIONSKIN, Geo.WHITE, 1.0, "FiledCarbons"), Vector3(0.50, 0.30, 0.15))



## Open-topped tray: a floor and four walls of thickness t, all steel.
static func _open_tray(tray_name: String, size: Vector3, t: float) -> Node3D:
	var tray := Node3D.new()
	tray.name = tray_name
	var hx := size.x * 0.5
	var hz := size.z * 0.5
	Geo.add(tray, Geo.box(Vector3(size.x, t, size.z), Geo.TEX_STEEL, Geo.WHITE, 1.0, "Floor"), Vector3(0, t * 0.5, 0))
	Geo.add(tray, Geo.box(Vector3(size.x, size.y, t), Geo.TEX_STEEL, Geo.WHITE, 1.0, "WallNorth"), Vector3(0, size.y * 0.5, -hz + t * 0.5))
	Geo.add(tray, Geo.box(Vector3(size.x, size.y, t), Geo.TEX_STEEL, Geo.WHITE, 1.0, "WallSouth"), Vector3(0, size.y * 0.5, hz - t * 0.5))
	Geo.add(tray, Geo.box(Vector3(t, size.y, size.z - 2.0 * t), Geo.TEX_STEEL, Geo.WHITE, 1.0, "WallWest"), Vector3(-hx + t * 0.5, size.y * 0.5, 0))
	Geo.add(tray, Geo.box(Vector3(t, size.y, size.z - 2.0 * t), Geo.TEX_STEEL, Geo.WHITE, 1.0, "WallEast"), Vector3(hx - t * 0.5, size.y * 0.5, 0))
	return tray


## A stack of paper-sized sheets lying flat, each 0.0008 m above the last.
static func _flat_sheets(desk: Node3D, stack_name: String, pos: Vector3, count: int, tex: Texture2D) -> void:
	var stack := Geo.group(desk, stack_name, pos)
	for i in count:
		Geo.add(stack, Geo.quad(0.21, 0.297, tex, Geo.WHITE, 0.0, 0.0, "Sheet%d" % i),
			Vector3(0, 0.0008 * float(i) + 0.0004, 0), Vector3(-90, 0, 0))


## Copyholder: a 0.24 x 0.32 easel panel angled 70 degrees from the desk, with a chrome clip.
static func _copyholder(desk: Node3D, pos: Vector3) -> void:
	var holder := Geo.group(desk, "Copyholder", pos)
	var tilt := -20.0
	var lean := Vector3(0, cos(deg_to_rad(20.0)), sin(deg_to_rad(tilt)))
	Geo.add(holder, Geo.box(Vector3(0.24, 0.32, 0.004), Geo.TEX_STEEL, Geo.WHITE, 1.0, "Easel"),
		Vector3(0, 0.16 * lean.y, 0.16 * lean.z), Vector3(tilt, 0, 0))
	Geo.add(holder, Geo.solid(Vector3(0.05, 0.012, 0.02), COL_CHROME, "Clip"),
		Vector3(0, 0.30 * lean.y, 0.30 * lean.z + 0.01), Vector3(tilt, 0, 0))


## Stamp rack: a 0.24 x 0.10 x 0.04 bar with four stamps, left to right APPROVED,
## DENIED, PROCESSED, RETURNED - UNPROCESSED (spec 5.4).
static func _stamp_rack(desk: Node3D, pos: Vector3) -> void:
	var rack := Geo.group(desk, "StampRack", pos)
	Geo.add(rack, Geo.box(Vector3(0.24, 0.10, 0.04), Geo.TEX_STEEL, Geo.WHITE, 1.0, "Bar"), Vector3(0, 0.05, 0))
	var bands := [STAMP_APPROVED, STAMP_DENIED, STAMP_APPROVED, STAMP_DENIED]
	var names := ["Approved", "Denied", "Processed", "Returned"]
	var xs := [-0.09, -0.03, 0.03, 0.09]
	for i in 4:
		Geo.add(rack, Geo.solid(Vector3(0.05, 0.02, 0.03), COL_INK_PAD, "Base" + names[i]), Vector3(xs[i], 0.11, 0))
		var label := TextTex.stamp_label(bands[i])
		Geo.add(rack, Geo.cylinder(0.015, 0.07, 8, Geo.WHITE, "Handle" + names[i], true, true, label),
			Vector3(xs[i], 0.155, 0))


## Desk lamp: brass base, stem, and a dome shade whose rim sits on the axis (spec 5.4).
## The SpotLight3D (Lamp04) is a child of the hall root, not of the desk.
static func _desk_lamp(desk: Node3D, pos: Vector3) -> void:
	var lamp := Geo.group(desk, "Lamp", pos)
	Geo.add(lamp, Geo.cylinder(0.07, 0.02, 8, COL_BRASS, "LampBase"), Vector3(0, 0.01, 0))
	Geo.add(lamp, Geo.solid(Vector3(0.015, 0.35, 0.015), COL_BRASS, "LampStem"), Vector3(0, 0.195, 0))
	Geo.add(lamp, Geo.half_shell(0.07, 0.22, 6, COL_LAMP_SHADE, "LampShade"), Vector3(0, 0.37, 0))
