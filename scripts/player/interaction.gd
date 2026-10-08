extends Node
## Interaction (spec 6.3, 6.4, 12): the centre-screen raycast, click and hold dispatch, the hand
## (at most one held item) and the Desk 4 item table. Rules stay in GameState and DayDirector.
##
## Raw input (only while enabled, which the main controller sets in free view): a left press
## raycasts from the screen centre (1.6 m seated, 2.0 m standing). Inbox, read stack and carbon
## spot act on release (a click) or after a 0.4 s hold (a pick-up); every other item acts on press.
## A right press returns the held item to its home. Esc opens the menu through the controller.
##
## Action strings (the M3 brief): "inbox", "read_stack", "blank_tray", "typewriter", "copyholder",
## "stamp:APPROVED|DENIED|PROCESSED|RETURNED", "marker", "fluid", "tube_receiver", "carbon_spot",
## "drawer_top", "drawer_lower", "lamp", "notebook", "chair_04", "clerk_figure:<desk>",
## "door_supervisor", "door_exit". action_pressed(action, node, hit_position) fires for each one
## that passes the seated or standing rule. Tests call dispatch_click() and dispatch_hold() directly.
##
## The hand_* functions are the Callables that the typewriter, stamp, marker, tube and carbon views
## call (held_kind_fn, held_id_fn, held_hold_fn, held_release_fn). Kinds: "document", "fluid",
## "marker", "stamp:<RESULT>".

const NotebookView := preload("res://scripts/doc/notebook_view.gd")

signal action_pressed(action: String, node: Node3D, hit_position: Vector3)

const HOLD_S := 0.4
const PICK_LAYER := 2
const HOLDABLE := ["inbox", "read_stack", "carbon_spot"]
const STANDING_ACTIONS := ["chair_04", "door_supervisor", "door_exit"]
const DOOR_HANDLE_PICK := Vector3(0.38, 1.0, 0.06)  # door-local, on the room side
const NO_POS := Vector3(INF, INF, INF)

var enabled := false
var controller = null  # main.gd: open_read_view, open_menu, set_typing_focus, is_focus_open, read_view

var player = null
var desk = null
var held = null
var typewriter = null
var tube = null
var carbon_view = null

var _hand_kind := ""
var _hand_id := ""
var _hand_origin := ""
var _read_from_inbox := false
var _pressed := false
var _press_action := ""
var _press_node = null
var _press_pos := Vector3.ZERO
var _press_t := 0.0
var _press_fired := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Wires the presentation nodes. hall is the HallC root (its Chair04 and doors get pick bodies).
func setup(ctl, hall: Node, player_node, desk_node, held_node, typewriter_node, tube_node, carbon_node) -> void:
	controller = ctl
	player = player_node
	desk = desk_node
	held = held_node
	typewriter = typewriter_node
	tube = tube_node
	carbon_view = carbon_node
	_add_standing_picks(hall)
	if controller != null and controller.has_signal("read_view_closed"):
		controller.read_view_closed.connect(_on_read_view_closed)


func set_enabled(on: bool) -> void:
	enabled = on
	if not on:
		_pressed = false


# --- Hand (the one held item) --------------------------------------------------------

func hand_kind() -> String:
	return _hand_kind


func hand_id() -> String:
	return _hand_id


func holding() -> bool:
	return _hand_kind != ""


## Puts an item in the hand. A document is recorded in GameState.loc.hand. origin names the
## place it came from ("inbox", "read_stack", "carbon_spot"), which is its home (spec 6.4).
func hand_hold(kind: String, id: String = "", origin: String = "") -> void:
	if _hand_kind != "":
		hand_release()
	_hand_kind = kind
	_hand_id = id
	_hand_origin = origin
	if held == null:
		return
	if kind == "document":
		if id != "":
			_gs().place(id, "hand")
		held.hold("document", id, desk.page_texture(id) if desk != null else null)
	else:
		held.hold(kind, id, null)
	if desk != null:
		desk.set_item_hidden(kind, true)


## Empties the hand and returns its visual. animate slides it to its home first.
## Returns the kind that was held ("" when empty).
func hand_release(animate: bool = false) -> String:
	if _hand_kind == "":
		return ""
	var k := _hand_kind
	var home := NO_POS
	if animate and desk != null:
		home = desk.home_world(_home_action())
	if held != null:
		if home.is_finite():
			held.release_home(home)
		else:
			held.release()
	if desk != null:
		desk.set_item_hidden(k, false)
	_hand_kind = ""
	_hand_id = ""
	_hand_origin = ""
	return k


## Right-click in free view (spec 6.4): a document goes back to where it came from, and the
## item goes back to its place. A sheet with no origin stays in the hand (see QUESTIONS_FOR_OPUS).
func dispatch_right_click() -> void:
	if _hand_kind == "":
		return
	if _hand_kind == "document":
		# TODO(QUESTION): spec 6.4 names a home only for items taken from a place. A blank or
		# ejected sheet has none, so it stays in the hand (neutral placeholder).
		if _hand_origin == "":
			return
		_gs().place(_hand_id, _hand_origin)
	hand_release(true)


func _home_action() -> String:
	if _hand_kind == "document":
		return _hand_origin
	return _hand_kind


# --- Dispatch --------------------------------------------------------------------------

## Runs the action of a click (spec 6.4 table). Gated by the seated or standing rule.
func dispatch_click(action: String, node: Node3D = null, hit_position: Vector3 = Vector3.ZERO) -> void:
	if not _allowed(action) or _blocked():
		return
	action_pressed.emit(action, node, hit_position)
	match action:
		"inbox":
			_click_inbox()
		"read_stack":
			_click_read_stack()
		"blank_tray":
			_click_blank_tray()
		"typewriter":
			_click_typewriter()
		"copyholder":
			_click_copyholder()
		"carbon_spot":
			_click_carbon_spot()
		"tube_receiver":
			_click_tube()
		"drawer_top":
			if desk != null:
				desk.toggle_drawer("top")
		"drawer_lower":
			if desk != null:
				desk.toggle_drawer("lower")
		"lamp":
			_dd().click_lamp()
		"notebook":
			_click_notebook()
		"marker", "fluid":
			_pick_item(action)
		"chair_04":
			if player != null:
				player.sit_down(true)
		"door_supervisor":
			on_door_handle_clicked("supervisor")
		"door_exit":
			on_door_handle_clicked("exit")
		_:
			if action.begins_with("stamp:"):
				_pick_item(action)


## Runs the action of a hold (spec 6.4): picks up the top document of inbox, read stack or carbon
## spot. A hold on the carbon spot is not a pick-up while the lower drawer is open (filing).
func dispatch_hold(action: String, node: Node3D = null, hit_position: Vector3 = Vector3.ZERO) -> void:
	if not _allowed(action) or _blocked():
		return
	action_pressed.emit(action, node, hit_position)
	match action:
		"inbox":
			if _hand_kind == "" and not _stack_ids("inbox").is_empty():
				_pick_top_doc("inbox")
		"read_stack":
			if _hand_kind == "" and not _stack_ids("read_stack").is_empty():
				_pick_top_doc("read_stack")
		"carbon_spot":
			if _hand_kind != "" or carbon_view == null:
				return
			if desk != null and desk.drawer_open("lower"):
				return
			var id: String = carbon_view.pick_up_top_carbon()
			if id != "":
				_hand_origin = "carbon_spot"


## Hook for the doors agent (spec 8.13). M3 only reports the handle click. The door rattle and
## the Day 4 key_clack are not built here.
func on_door_handle_clicked(which: String) -> void:
	pass


# --- Action bodies ---------------------------------------------------------------------

func _click_inbox() -> void:
	var ids := _stack_ids("inbox")
	var docs := _docs_of(ids)
	if docs.is_empty():
		return
	_open_read(docs, docs.size() - 1, "stack", true)


func _click_read_stack() -> void:
	if _hand_kind == "document":
		_gs().place(_hand_id, "read_stack")
		hand_release()
		return
	var docs := _docs_of(_stack_ids("read_stack"))
	if docs.is_empty():
		return
	_open_read(docs, docs.size() - 1, "stack", false)


func _click_blank_tray() -> void:
	if _hand_kind != "":
		return
	var id: String = _dd().take_blank_sheet()
	if id != "":
		hand_hold("document", id, "")


func _click_typewriter() -> void:
	if typewriter == null:
		return
	var doc_id := _hand_id if _hand_kind == "document" else ""
	if typewriter.open_typing_view(doc_id):
		if controller != null and controller.has_method("set_typing_focus"):
			controller.set_typing_focus(true)


func _click_copyholder() -> void:
	var gs = _gs()
	if _hand_kind == "document":
		var prev := String(gs.loc.copyholder)
		if prev != "" and prev != _hand_id:
			gs.place(prev, "read_stack")
		gs.place(_hand_id, "copyholder")
		hand_release()
		return
	if _hand_kind != "":
		return
	var id := String(gs.loc.copyholder)
	if id == "":
		return
	var docs := _docs_of([id])
	if not docs.is_empty():
		_open_read(docs, 0, "single", false)


func _click_carbon_spot() -> void:
	if carbon_view == null:
		return
	var filed: int = carbon_view.carbon_spot_clicked()
	if filed >= 0:
		return  # the lower drawer was open: the carbons were filed (spec 8.5)
	var docs := _docs_of(_stack_ids("carbon_spot"))
	if docs.is_empty():
		return
	_open_read(docs, docs.size() - 1, "stack", false)


func _click_tube() -> void:
	if _hand_kind != "document" or tube == null:
		return
	tube.press_receiver()


func _click_notebook() -> void:
	if desk == null or not desk.notebook_clickable():
		return
	var day := int(_gs().day)
	_open_read(NotebookView.page_docs(day), NotebookView.open_index(day), "stack", false)


func _pick_item(kind: String) -> void:
	if _hand_kind != "":
		return
	hand_hold(kind, "", "")


func _pick_top_doc(stack: String) -> void:
	var ids := _stack_ids(stack)
	var id := String(ids[ids.size() - 1])
	_gs().place(id, "hand")
	hand_hold("document", id, stack)


# --- Read view -------------------------------------------------------------------------

func _open_read(docs: Array, index: int, mode: String, from_inbox: bool) -> void:
	if controller == null or not controller.has_method("open_read_view"):
		return
	_read_from_inbox = from_inbox
	controller.open_read_view(docs, index, mode)


## Closing read view (spec 6.4): the inbox item on show moves to the read stack.
func _on_read_view_closed(doc_id: String) -> void:
	var from_inbox := _read_from_inbox
	_read_from_inbox = false
	if from_inbox and doc_id != "" and _gs().location_of(doc_id) == "inbox":
		_gs().place(doc_id, "read_stack")


# --- Raw input -------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_left_down()
			else:
				_left_up()
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			dispatch_right_click()
			get_viewport().set_input_as_handled()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			if controller != null and controller.has_method("open_menu"):
				controller.open_menu()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _pressed or _press_fired or not HOLDABLE.has(_press_action):
		return
	_press_t += delta
	if _press_t >= HOLD_S:
		_press_fired = true
		dispatch_hold(_press_action, _press_node, _press_pos)


func _left_down() -> void:
	var hit := _raycast()
	_pressed = false
	_press_fired = false
	_press_t = 0.0
	_press_action = String(hit.get("action", ""))
	_press_node = hit.get("node", null)
	_press_pos = hit.get("pos", Vector3.ZERO)
	if _press_action == "":
		# TODO(QUESTION): spec 6.3 lists "a document held in hand" as a read view entry but no
		# click target. Placeholder: a click with nothing under the centre opens the held document.
		if _hand_kind == "document" and not _blocked():
			_open_held_document()
		return
	if HOLDABLE.has(_press_action):
		_pressed = true
	else:
		dispatch_click(_press_action, _press_node, _press_pos)


func _left_up() -> void:
	if not _pressed:
		return
	_pressed = false
	if not _press_fired and HOLDABLE.has(_press_action):
		dispatch_click(_press_action, _press_node, _press_pos)


func _open_held_document() -> void:
	var docs := _docs_of([_hand_id])
	if not docs.is_empty():
		_open_read(docs, 0, "single", false)


## Centre-screen ray (spec 6.4). Returns {action, node, pos} or {} when nothing is hit.
func _raycast() -> Dictionary:
	if player == null:
		return {}
	var cam: Camera3D = player.camera()
	if cam == null or not cam.is_inside_tree():
		return {}
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * float(player.ray_length())
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = [player.get_rid()]
	var res := cam.get_world_3d().direct_space_state.intersect_ray(q)
	if res.is_empty():
		return {}
	var col = res.collider
	var action := ""
	var node = null
	if col is Node:
		var n := col as Node
		if n.has_meta("action"):
			action = String(n.get_meta("action"))
		node = n.get_parent()
	return {"action": action, "node": node, "pos": res.position}


func _allowed(action: String) -> bool:
	if action.begins_with("clerk_figure:"):
		return true
	if player == null:
		return false
	if STANDING_ACTIONS.has(action):
		return player.is_standing()
	return player.is_seated()


func _blocked() -> bool:
	return controller != null and controller.has_method("is_focus_open") and bool(controller.is_focus_open())


func _add_standing_picks(hall: Node) -> void:
	if hall == null:
		return
	var chair_body := hall.get_node_or_null("Chair04/ChairCollision")
	if chair_body != null:
		chair_body.set_meta("action", "chair_04")
	for pair in [["SupervisorDoor", "door_supervisor"], ["ExitDoor", "door_exit"]]:
		var door := hall.get_node_or_null(pair[0]) as Node3D
		if door == null:
			continue
		var body := StaticBody3D.new()
		body.name = "HandlePick"
		body.collision_layer = PICK_LAYER
		body.collision_mask = 0
		body.set_meta("action", pair[1])
		body.position = DOOR_HANDLE_PICK
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.10, 0.20, 0.10)
		shape.shape = box
		body.add_child(shape)
		door.add_child(body)


# --- Services --------------------------------------------------------------------------

func _stack_ids(stack: String) -> Array:
	var gs = _gs()
	match stack:
		"inbox":
			return gs.loc.inbox
		"read_stack":
			return gs.loc.read_stack
		"carbon_spot":
			return gs.loc.carbon_spot
	return []


func _docs_of(ids: Array) -> Array:
	var gs = _gs()
	var out: Array = []
	for id in ids:
		var d = gs.docs.get(String(id), null)
		if d is Dictionary:
			out.append(d)
	return out


func _gs():
	return _autoload("GameState")


func _dd():
	return _autoload("DayDirector")


func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
