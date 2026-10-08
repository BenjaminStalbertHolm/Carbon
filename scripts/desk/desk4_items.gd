extends Node
## Desk 4 presentation (spec 5.4, 6.4, 7.9, 8.4, 8.5). The rules stay in GameState and DayDirector.
## This node shows the state:
##   - the inbox, read stack and carbon spot stacks follow the counts in GameState, and their top
##     paper shows the front page of the top document (DocRenderer.page_texture);
##   - the blank tray shows 0.002 m per remaining sheet (GameState.tray_count, spec 7.9);
##   - the copyholder clips the document in GameState.loc.copyholder;
##   - the filed carbons show in the lower drawer when GameState.loc.drawer is not empty;
##   - the Desk 4 nameplate follows GameState.nameplate["4"];
##   - a desk the redaction state removed (GameState.desk_removed) is hidden (spec 14.11).
## It also builds the pick bodies for every interactive item. Each pick body is on physics layer 2
## and carries the action string as metadata ("action"), which interaction.gd reads from the
## centre-screen ray. Items that are held are hidden with set_item_hidden().
##
## Setup: add to the main tree, then setup(hall) (hall = the HallC root from hall_c.gd).

const Geo := preload("res://scripts/world/geometry.gd")
const TextTex := preload("res://scripts/world/text_texture.gd")
const DocRenderer := preload("res://scripts/doc/doc_renderer.gd")
const PaperQuad := preload("res://scripts/doc/paper_quad.gd")
const Drawers := preload("res://scripts/desk/drawers.gd")

const PICK_LAYER := 2
const STACK_CAP := 40
const PAPER_SIZE := Vector2(0.21, 0.297)
const SHEET_SPACING := 0.0008
const BLANK_SPACING := 0.002
const INBOX_FLOOR := 0.011
const TOP_REFRESH_S := 0.25
const DESK_NODE_PREFIXES := ["Desk", "Chair", "Typewriter", "Tube", "Clerk"]
const INF_POS := Vector3(INF, INF, INF)

## Node paths (relative to Desk04) of the parts a held item hides, by action string.
const ITEM_PATHS := {
	"stamp:APPROVED": ["StampRack/HandleApproved"],
	"stamp:DENIED": ["StampRack/HandleDenied"],
	"stamp:PROCESSED": ["StampRack/HandleProcessed"],
	"stamp:RETURNED": ["StampRack/HandleReturned"],
	"marker": ["Marker"],
	"fluid": ["CorrectionBottle", "CorrectionCap"],
}

var renderer: DocRenderer = null
var drawers: Node = null

var _hall: Node = null
var _desk: Node3D = null
var _last_sig: Array = []
var _nameplate_text := ""
var _top_timer := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## hall is the HallC root. Returns false when the hall has no Desk04.
func setup(hall: Node) -> bool:
	_hall = hall
	_desk = (hall.get_node_or_null("Desk04") as Node3D) if hall != null else null
	if _desk == null:
		push_error("Desk4Items: Desk04 not found")
		return false
	renderer = DocRenderer.new()
	renderer.name = "Docs"
	add_child(renderer)
	drawers = Drawers.new()
	drawers.name = "Drawers"
	add_child(drawers)
	drawers.setup(_desk)
	_clear_hall_sheets()
	_build_picks()
	refresh()
	return true


## Rebuilds the stacks, the clipped copyholder, the nameplate and the desk visibility from
## GameState. Called on every change (process polls for them).
func refresh() -> void:
	var gs := _gs()
	if gs == null or _desk == null:
		return
	var loc: Dictionary = gs.loc
	_fill_stack(_desk.get_node_or_null("InboxTray"), loc.inbox, loc.inbox.size(), SHEET_SPACING, INBOX_FLOOR)
	_fill_stack(_desk.get_node_or_null("ReadStack"), loc.read_stack, loc.read_stack.size(), SHEET_SPACING, 0.0)
	_fill_stack(_desk.get_node_or_null("CarbonSpot"), loc.carbon_spot, loc.carbon_spot.size(), SHEET_SPACING, 0.0)
	_fill_stack(_desk.get_node_or_null("BlankStack"), [], int(gs.tray_count), BLANK_SPACING, 0.0)
	_refresh_copyholder()
	var filed := _desk.get_node_or_null("FiledCarbons") as Node3D
	if filed != null:
		filed.visible = not loc.drawer.is_empty()
	_refresh_nameplate()
	_sync_desks()
	_last_sig = _signature()


## Front-page texture of a document (spec 6.5), or blank paper for an unknown id.
func page_texture(doc_id: String) -> Texture2D:
	var gs := _gs()
	if gs == null or renderer == null:
		return Geo.TEX_PAPER
	var doc: Dictionary = gs.docs.get(doc_id, {})
	if doc.is_empty() or (doc.get("pages", []) as Array).is_empty():
		return Geo.TEX_PAPER
	return renderer.page_texture(doc, 0)


## Opens or closes a drawer: "top" or "lower" (spec 6.4).
func toggle_drawer(which: String) -> void:
	if drawers != null:
		drawers.toggle(which)


func drawer_open(which: String) -> bool:
	return drawers != null and bool(drawers.is_open(which))


func notebook_clickable() -> bool:
	return drawers != null and bool(drawers.notebook_clickable())


## Hides or shows the desk part a held item came from ("stamp:APPROVED", "marker", "fluid").
func set_item_hidden(action: String, hidden: bool) -> void:
	for node in _item_nodes(action):
		node.visible = not hidden
		_set_pick_enabled(node, not hidden)


## World position of the home of an item, for the return slide. INF when there is none.
func home_world(action: String) -> Vector3:
	if _desk == null:
		return INF_POS
	var path := ""
	match action:
		"inbox":
			path = "InboxTray"
		"read_stack":
			path = "ReadStack"
		"carbon_spot":
			path = "CarbonSpot"
		"copyholder":
			path = "Copyholder"
		_:
			var nodes := _item_nodes(action)
			if not nodes.is_empty():
				return (nodes[0] as Node3D).global_position
			return INF_POS
	var node := _desk.get_node_or_null(path) as Node3D
	return node.global_position if node != null else INF_POS


# --- Process ---------------------------------------------------------------------------

func _process(delta: float) -> void:
	var sig := _signature()
	if sig != _last_sig:
		refresh()
		return
	_top_timer -= delta
	if _top_timer <= 0.0:
		_top_timer = TOP_REFRESH_S
		_update_tops()


func _signature() -> Array:
	var gs := _gs()
	if gs == null:
		return []
	var loc: Dictionary = gs.loc
	return [
		int(gs.tray_count), loc.inbox.duplicate(), loc.read_stack.duplicate(),
		loc.carbon_spot.duplicate(), loc.drawer.duplicate(), String(loc.copyholder),
		gs.desk_removed.duplicate(), String(gs.nameplate.get("4", "")),
	]


# --- Stacks ----------------------------------------------------------------------------

## Removes the flat sheets the hall built, so the stacks here are the only sheets.
func _clear_hall_sheets() -> void:
	for host_name in ["ReadStack", "BlankStack", "CarbonSpot"]:
		var host := _desk.get_node_or_null(host_name)
		if host == null:
			continue
		for child in host.get_children():
			if String(child.name).begins_with("Sheet"):
				child.queue_free()


## Rebuilds the stack under host. ids are the documents in stack order (the last is on top);
## count is the number of sheets to show (blank tray: the tray count, ids empty).
func _fill_stack(host: Node3D, ids: Array, count: int, spacing: float, base_y: float) -> void:
	if host == null:
		return
	var old := host.get_node_or_null("Stack")
	if old != null:
		old.name = "StackOld"
		old.queue_free()
	var stack := Node3D.new()
	stack.name = "Stack"
	host.add_child(stack)
	var n := mini(count, STACK_CAP)
	var top_id := String(ids[ids.size() - 1]) if not ids.is_empty() else ""
	for i in n:
		var sheet: MeshInstance3D
		if i == n - 1 and top_id != "":
			sheet = PaperQuad.make(page_texture(top_id), PAPER_SIZE)
			sheet.name = "Top"
		else:
			sheet = Geo.quad(PAPER_SIZE.x, PAPER_SIZE.y, Geo.TEX_PAPER, Geo.WHITE, 0.0, 0.0, "Sheet%d" % i)
		sheet.position = Vector3(0.0, base_y + spacing * (float(i) + 0.5), 0.0)
		sheet.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		stack.add_child(sheet)


## Keeps the top sheets of the stacks showing the current front page (a stamp or a
## correction changes it in place).
func _update_tops() -> void:
	var gs := _gs()
	if gs == null:
		return
	var tops := {
		"InboxTray": gs.loc.inbox, "ReadStack": gs.loc.read_stack, "CarbonSpot": gs.loc.carbon_spot,
	}
	for host_name in tops.keys():
		var host := _desk.get_node_or_null(String(host_name))
		var ids: Array = tops[host_name]
		if host == null or ids.is_empty():
			continue
		var stack := host.get_node_or_null("Stack")
		var top: MeshInstance3D = null
		if stack != null:
			top = stack.get_node_or_null("Top") as MeshInstance3D
		if top != null:
			PaperQuad.set_texture(top, page_texture(String(ids[ids.size() - 1])))


func _refresh_copyholder() -> void:
	var gs := _gs()
	var holder := _desk.get_node_or_null("Copyholder") as Node3D
	if holder == null:
		return
	var old := holder.get_node_or_null("Clipped")
	if old != null:
		old.name = "ClippedOld"
		old.queue_free()
	var id := String(gs.loc.copyholder)
	if id == "":
		return
	# The easel of desk.gd: its centre and tilt. The paper sits 4 mm off its front face.
	var tilt := -20.0
	var centre := Vector3(0.0, 0.16 * cos(deg_to_rad(20.0)), 0.16 * sin(deg_to_rad(tilt)))
	var normal := Basis.from_euler(Vector3(deg_to_rad(tilt), 0.0, 0.0)) * Vector3(0.0, 0.0, 0.004)
	var quad := PaperQuad.make(page_texture(id), PAPER_SIZE)
	quad.name = "Clipped"
	quad.position = centre + normal
	quad.rotation_degrees = Vector3(tilt, 0.0, 0.0)
	holder.add_child(quad)


func _refresh_nameplate() -> void:
	var gs := _gs()
	var text := String(gs.nameplate.get("4", ""))
	if text == _nameplate_text:
		return
	_nameplate_text = text
	var plate := _desk.get_node_or_null("Nameplate") as Node3D
	if plate == null:
		return
	var tex := TextTex.nameplate(plate, text)
	for face in ["FaceSouth", "FaceNorth"]:
		var mi := plate.get_node_or_null(face) as MeshInstance3D
		if mi != null and mi.material_override is ShaderMaterial:
			(mi.material_override as ShaderMaterial).set_shader_parameter("albedo_tex", tex)


## A desk removed by the redaction state (spec 14.11) hides its nodes. Its chair, typewriter,
## tube and clerk go with it.
func _sync_desks() -> void:
	var gs := _gs()
	if gs == null or _hall == null:
		return
	for n in range(1, 13):
		var gone := bool(gs.desk_removed.get(str(n), false))
		for prefix in DESK_NODE_PREFIXES:
			var node := _hall.get_node_or_null("%s%02d" % [prefix, n]) as Node3D
			if node != null:
				node.visible = not gone


# --- Pick bodies -----------------------------------------------------------------------

func _build_picks() -> void:
	_pick(_desk.get_node_or_null("InboxTray"), "inbox", Vector3(0.26, 0.05, 0.34), Vector3(0.0, 0.025, 0.0))
	_pick(_desk.get_node_or_null("ReadStack"), "read_stack", Vector3(0.21, 0.04, 0.297), Vector3(0.0, 0.02, 0.0))
	_pick(_desk.get_node_or_null("BlankTray"), "blank_tray", Vector3(0.24, 0.03, 0.32), Vector3(0.0, 0.02, 0.0))
	_pick(_desk.get_node_or_null("CarbonSpot"), "carbon_spot", Vector3(0.21, 0.02, 0.297), Vector3(0.0, 0.01, 0.0))
	_pick(_desk.get_node_or_null("Copyholder"), "copyholder", Vector3(0.24, 0.32, 0.01),
		Vector3(0.0, 0.15, -0.055), Vector3(-20.0, 0.0, 0.0))
	var handles := {
		"stamp:APPROVED": "HandleApproved", "stamp:DENIED": "HandleDenied",
		"stamp:PROCESSED": "HandleProcessed", "stamp:RETURNED": "HandleReturned",
	}
	var rack := _desk.get_node_or_null("StampRack")
	for action in handles.keys():
		if rack != null:
			_pick(rack.get_node_or_null(handles[action]), action, Vector3(0.03, 0.08, 0.03), Vector3.ZERO)
	_pick(_desk.get_node_or_null("Marker"), "marker", Vector3(0.13, 0.03, 0.03), Vector3.ZERO)
	_pick(_desk.get_node_or_null("CorrectionBottle"), "fluid", Vector3(0.04, 0.09, 0.04), Vector3(0.0, 0.02, 0.0))
	_pick(_desk.get_node_or_null("Lamp"), "lamp", Vector3(0.16, 0.40, 0.16), Vector3(0.0, 0.2, 0.0))
	_pick(_hall.get_node_or_null("Typewriter04/Body"), "typewriter", Vector3(0.44, 0.12, 0.34), Vector3.ZERO)
	_pick(_hall.get_node_or_null("Tube04/Receiver"), "tube_receiver", Vector3(0.20, 0.25, 0.20), Vector3.ZERO)
	for n in [1, 2, 3, 5, 6, 7, 8, 9, 10, 11]:
		_pick(_hall.get_node_or_null("Clerk%02d" % n), "clerk_figure:%d" % n, Vector3(0.45, 1.5, 0.45),
			Vector3(0.0, 0.75, 0.0))


func _pick(parent: Node3D, action: String, size: Vector3, pos: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> void:
	if parent == null or parent.get_node_or_null("Pick") != null:
		return
	var body := StaticBody3D.new()
	body.name = "Pick"
	body.collision_layer = PICK_LAYER
	body.collision_mask = 0
	body.set_meta("action", action)
	body.position = pos
	body.rotation_degrees = rot_deg
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	parent.add_child(body)


func _set_pick_enabled(node: Node, on: bool) -> void:
	var pick := node.get_node_or_null("Pick")
	if pick == null:
		return
	for c in pick.get_children():
		if c is CollisionShape3D:
			(c as CollisionShape3D).disabled = not on


func _item_nodes(action: String) -> Array:
	var out: Array = []
	if _desk == null or not ITEM_PATHS.has(action):
		return out
	for path in ITEM_PATHS[action]:
		var node := _desk.get_node_or_null(String(path)) as Node3D
		if node != null:
			out.append(node)
	return out


func _gs() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("GameState")
