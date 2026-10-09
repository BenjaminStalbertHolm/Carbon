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
const RAY_SKIP_MAX := 8  # pick bodies the ray may skip (unusable in this pose) before it gives up
const HOLDABLE := ["inbox", "read_stack", "carbon_spot"]
const STANDING_ACTIONS := ["chair_04", "door_supervisor", "door_exit"]
const DOOR_HANDLE_PICK := Vector3(0.38, 1.0, 0.06)  # door-local, on the room side
const NO_POS := Vector3(INF, INF, INF)
## Spec 8.13 supervisor door. The played levels are the spec's; the gains are played minus the file
## peak (QUESTION-29). door_rattle.wav peaks at -22 dBFS, key_clack_1..4.wav at -10 dBFS.
const SUPERVISOR_RATTLE_DB := -22.0
const SUPERVISOR_CLACK_DB := -30.0
const DOOR_RATTLE_PEAK_DB := -22.0
const KEY_CLACK_PEAK_DB := -10.0
const SUPERVISOR_CLACK_DELAY_S := 1.2
const SUPERVISOR_CLACK_FROM_DAY := 4
const SUPERVISOR_DOOR := "SupervisorDoor"
const BEHIND_DOOR_OFFSET := Vector3(0.0, 1.0, -0.5)  # world offset from the door root, into the room behind

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
var _read_opened_id := ""  # the inbox item the read view opened on (QUESTION-52)
var _pressed := false
var _press_action := ""
var _press_node = null
var _press_pos := Vector3.ZERO
var _press_t := 0.0
var _press_fired := false
var _hall: Node = null
var _clack_in := -1.0  # seconds until the Day 4 key_clack after a rattle; below 0 when none is due
var _clack_pos := Vector3.ZERO


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


## Wires the presentation nodes. hall is the HallC root (its Chair04 and doors get pick bodies).
func setup(ctl, hall: Node, player_node, desk_node, held_node, typewriter_node, tube_node, carbon_node) -> void:
	controller = ctl
	_hall = hall
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
## item goes back to its place. A sheet with no origin (blank or ejected) goes on top of the
## read stack (QUESTION-54).
func dispatch_right_click() -> void:
	if _hand_kind == "":
		return
	if _hand_kind == "document":
		_gs().place(_hand_id, _document_home())
	hand_release(true)


## Where a held document goes back to: its origin, or the read stack when it has none (QUESTION-54).
func _document_home() -> String:
	return _hand_origin if _hand_origin != "" else "read_stack"


func _home_action() -> String:
	if _hand_kind == "document":
		return _document_home()
	return _hand_kind


# --- Dispatch --------------------------------------------------------------------------

## Runs the action of a click (spec 6.4 table). Gated by the seated or standing rule.
func dispatch_click(action: String, node: Node3D = null, hit_position: Vector3 = Vector3.ZERO) -> void:
	if not _allowed(action) or _blocked():
		return
	# Spec 15.2 step 1: from the refusal on, the lamp does nothing: no click, no sound, no day end.
	if action == "lamp" and _lamp_locked():
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
## spot. A hold on the carbon spot picks up the top carbon even with the lower drawer open (QUESTION-55).
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
			var id: String = carbon_view.pick_up_top_carbon()
			if id != "":
				_hand_origin = "carbon_spot"


## Spec 8.13. A click on the supervisor handle (standing only, as _allowed enforces) plays
## door_rattle at -22 dBFS played level. From Day 4 on, one key_clack from behind the door follows
## 1.2 s later at -30 dBFS played level. The rattle is player-caused; the key_clack is not.
## The exit handle is the endings controller's (spec 15.2), so this does nothing for it.
func on_door_handle_clicked(which: String) -> void:
	if which != "supervisor":
		return
	var door: Node3D = null
	if _hall != null:
		door = _hall.get_node_or_null(SUPERVISOR_DOOR) as Node3D
	var pos := Vector3.ZERO
	if door != null and door.is_inside_tree():
		pos = door.global_position + BEHIND_DOOR_OFFSET
	_play_sound("door_rattle", pos, SUPERVISOR_RATTLE_DB - DOOR_RATTLE_PEAK_DB, true)
	if _current_day() >= SUPERVISOR_CLACK_FROM_DAY:
		_clack_pos = pos
		_clack_in = SUPERVISOR_CLACK_DELAY_S


func _current_day() -> int:
	var gs = _gs()
	return int(gs.day) if gs != null else 0


func _play_sound(sound: String, pos: Vector3, gain_db: float, player_caused: bool) -> void:
	var ad = _autoload("AudioDirector")
	if ad != null and ad.has_method("play"):
		ad.play(sound, pos, true, gain_db, player_caused)


## The endings flags (main.gd forwards them to endings_controller.gd, spec 15).
func _typing_locked() -> bool:
	return controller != null and controller.has_method("typing_locked") and bool(controller.typing_locked())


func _lamp_locked() -> bool:
	return controller != null and controller.has_method("lamp_locked") and bool(controller.lamp_locked())


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
	if typewriter == null or _typing_locked():
		return  # spec 15.1 step 1: typing view is disabled during Ending A
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
	if from_inbox and not docs.is_empty():
		_read_opened_id = String(docs[clampi(index, 0, docs.size() - 1)].id)
	controller.open_read_view(docs, index, mode)


## Closing read view (spec 6.4, QUESTION-52): the inbox item the view opened on moves to the read
## stack, even if the player turned to other pages.
func _on_read_view_closed(_doc_id: String) -> void:
	var from_inbox := _read_from_inbox
	var opened := _read_opened_id
	_read_from_inbox = false
	_read_opened_id = ""
	if from_inbox and opened != "" and _gs().location_of(opened) == "inbox":
		_gs().place(opened, "read_stack")


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
	if _clack_in >= 0.0:
		_clack_in -= delta
		if _clack_in < 0.0:
			_clack_in = -1.0
			_play_sound("key_clack", _clack_pos, SUPERVISOR_CLACK_DB - KEY_CLACK_PEAK_DB, false)
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
## Only pick bodies (PICK_LAYER) are tested, so the desk box, the walls and the chair bodies never
## hide an item. A pick the player cannot use in this pose (the chair while seated, spec 6.2), or
## whose click does nothing in the current state (_is_inert), is skipped, so it does not hide what is
## behind it (the lower drawer, the read stack behind an empty inbox). With no usable pick on the
## ray, the first pick hit is returned, as before.
func _raycast() -> Dictionary:
	if player == null:
		return {}
	var cam: Camera3D = player.camera()
	if cam == null or not cam.is_inside_tree():
		return {}
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * float(player.ray_length())
	var space := cam.get_world_3d().direct_space_state
	var exclude: Array[RID] = [player.get_rid()]
	var first := {}
	for _i in RAY_SKIP_MAX + 1:
		var q := PhysicsRayQueryParameters3D.create(from, to, PICK_LAYER, exclude)
		q.collide_with_bodies = true
		q.collide_with_areas = false
		var res := space.intersect_ray(q)
		if res.is_empty():
			break
		var hit := _hit_info(res)
		if first.is_empty():
			first = hit
		if _allowed(String(hit.action)) and not _is_inert(String(hit.action)):
			return hit
		exclude.append(res.rid)
	return first


func _hit_info(res: Dictionary) -> Dictionary:
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


## A pick whose click does nothing in the current state (spec 6.4 table). The ray skips it, so it
## does not hide the pick behind it (the same skip as _allowed). Clicks are not changed: a click on
## an inert pick is dispatched as before, and does nothing. Rules:
## inbox with no documents; read stack empty with nothing in hand; carbon spot with no carbons while
## the lower drawer is shut (a click on an open drawer files); blank tray at zero; copyholder with
## nothing in hand and nothing clipped. Every other pick is never inert.
func _is_inert(action: String) -> bool:
	var gs = _gs()
	if gs == null:
		return false
	match action:
		"inbox":
			return _stack_ids("inbox").is_empty()
		"read_stack":
			return _stack_ids("read_stack").is_empty() and not holding()
		"carbon_spot":
			return _stack_ids("carbon_spot").is_empty() and not _lower_drawer_open()
		"blank_tray":
			return int(gs.tray_count) <= 0
		"copyholder":
			return not holding() and String(gs.loc.copyholder) == ""
	return false


func _lower_drawer_open() -> bool:
	return desk != null and desk.has_method("drawer_open") and bool(desk.drawer_open("lower"))


func _blocked() -> bool:
	return controller != null and controller.has_method("is_focus_open") and bool(controller.is_focus_open())


func _add_standing_picks(hall: Node) -> void:
	if hall == null:
		return
	var chair_body := hall.get_node_or_null("Chair04/ChairCollision") as CollisionObject3D
	if chair_body != null:
		# Physical (layer 1, the walking collision) and a pick (PICK_LAYER, spec 6.4).
		chair_body.collision_layer = 1 | PICK_LAYER
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
