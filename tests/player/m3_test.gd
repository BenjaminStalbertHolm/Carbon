extends SceneTree
## M3 headless checks (spec 6.2 to 6.4, 8.12, 13.5, 12): the Desk 4 action table driven through
## interaction.gd's dispatchers, the hand, the read view, the drawers, the lamp, the tube, and the
## standing walk and the sit back to the seated pose.
## Run: godot --headless --path /home/user/Carbon --script res://tests/player/m3_test.gd
## Exit 0 only when every check passes. Prints "M3: N checks, M failures".

const MainScript := preload("res://scripts/main.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")

const SEAT_EYE := Vector3(5.25, 1.15, 4.10)
const TEST_SAVE := "user://m3_test_save.json"

var _checks := 0
var _fails := 0
var _started := false
var _main = null
var _gs = null
var _dd = null
var _ss = null


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


func _wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func _run() -> void:
	_gs = root.get_node("GameState")
	_dd = root.get_node("DayDirector")
	_ss = root.get_node("SaveSystem")
	_ss.save_path = TEST_SAVE
	_main = MainScript.new()
	_main.auto_boot = false
	root.add_child(_main)
	await process_frame
	_main.debug_start_game(4242)
	await process_frame
	await _checks_hall()
	await _checks_action_table()
	await _checks_inbox_and_read_stack()
	await _checks_blank_tray_and_hand()
	await _checks_copyholder_and_typewriter()
	await _checks_drawers_and_notebook()
	await _checks_lamp()
	await _checks_tube()
	await _checks_walk_and_sit()
	_teardown()
	print("M3: %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)


# --- Helpers ---------------------------------------------------------------------------

func _doc(id: String, kind: String = "free") -> Dictionary:
	var doc := DocModel.new_doc(id, kind, "typed", "black")
	doc.pages.append(DocModel.new_page())
	return doc


func _add_doc(id: String, location: String, kind: String = "memo") -> String:
	_gs.add_doc(_doc(id, kind), location)
	return id


func _close_read() -> void:
	_main.read_view.close()


func _near(a: Vector3, b: Vector3, tol: float) -> bool:
	return a.distance_to(b) <= tol


# --- Checks ----------------------------------------------------------------------------

func _checks_hall() -> void:
	var hall = _main.hall
	_check(hall != null and hall.get_node_or_null("Desk04") != null, "hall has Desk04")
	_check(hall.get_node_or_null("Chair04") != null and hall.get_node_or_null("Typewriter04") != null, "hall has Chair04 and Typewriter04")
	_check(hall.get_node_or_null("Tube04") != null and hall.get_node_or_null("Lamp04") != null, "hall has Tube04 and Lamp04")
	_check(hall.get_node_or_null("Clerk12") == null and hall.get_node_or_null("Clerk04") == null, "no Clerk04 and no Clerk12")
	_check(_near(_main.player.camera().global_position, SEAT_EYE, 0.02), "player starts at the seated eye")
	_check(_main.player.is_seated(), "player starts SEATED")


func _checks_action_table() -> void:
	var hall = _main.hall
	var desk = hall.get_node("Desk04")
	var table := {
		"inbox": desk.get_node("InboxTray"),
		"read_stack": desk.get_node("ReadStack"),
		"blank_tray": desk.get_node("BlankTray"),
		"copyholder": desk.get_node("Copyholder"),
		"carbon_spot": desk.get_node("CarbonSpot"),
		"stamp:APPROVED": desk.get_node("StampRack/HandleApproved"),
		"stamp:DENIED": desk.get_node("StampRack/HandleDenied"),
		"stamp:PROCESSED": desk.get_node("StampRack/HandleProcessed"),
		"stamp:RETURNED": desk.get_node("StampRack/HandleReturned"),
		"marker": desk.get_node("Marker"),
		"fluid": desk.get_node("CorrectionBottle"),
		"lamp": desk.get_node("Lamp"),
		"drawer_top": desk.get_node("DrawerTop"),
		"drawer_lower": desk.get_node("DrawerLower"),
		"notebook": desk.get_node("Notebook"),
		"typewriter": hall.get_node("Typewriter04/Body"),
		"tube_receiver": hall.get_node("Tube04/Receiver"),
	}
	for action in table.keys():
		var node: Node = table[action]
		var pick := node.get_node_or_null("Pick")
		var ok: bool = pick != null and String(pick.get_meta("action", "")) == action
		_check(ok, "pick body for %s" % action)
	_check(String(hall.get_node("Chair04/ChairCollision").get_meta("action", "")) == "chair_04", "pick for chair_04")
	_check(String(hall.get_node("SupervisorDoor/HandlePick").get_meta("action", "")) == "door_supervisor", "pick for door_supervisor")
	_check(String(hall.get_node("ExitDoor/HandlePick").get_meta("action", "")) == "door_exit", "pick for door_exit")


func _checks_inbox_and_read_stack() -> void:
	var id := _add_doc("M3-TEST-A", "inbox")
	_add_doc("M3-TEST-B", "inbox")
	_main.interaction.dispatch_click("inbox")
	_check(_main.read_view.is_open(), "inbox click opens read view")
	var on_show := String(_main.read_view.current_doc().id)
	_check(on_show == "M3-TEST-B", "inbox read view opens on the top (last) item")
	_close_read()
	_check(_gs.location_of("M3-TEST-B") == "read_stack", "closing read view moves the item on show to the read stack")
	_check(_gs.location_of("M3-TEST-A") == "inbox", "the item not shown stays in the inbox")
	_main.interaction.dispatch_click("read_stack")
	_check(_main.read_view.is_open() and String(_main.read_view.current_doc().id) == "M3-TEST-B", "read stack opens on the newest item")
	_close_read()
	_check(_gs.location_of("M3-TEST-B") == "read_stack", "closing a read stack view moves nothing")
	_main.interaction.dispatch_hold("read_stack")
	_check(_main.interaction.hand_kind() == "document" and _main.interaction.hand_id() == "M3-TEST-B", "read stack hold picks up the top item")
	_check(_gs.location_of("M3-TEST-B") == "hand", "a picked-up item is in the hand")
	_main.interaction.dispatch_click("read_stack")
	_check(_gs.location_of("M3-TEST-B") == "read_stack" and _main.interaction.hand_kind() == "", "clicking the read stack with a document puts it there")
	_main.interaction.dispatch_hold("inbox")
	_check(_main.interaction.hand_id() == "M3-TEST-A", "inbox hold picks up the top item")
	_main.interaction.dispatch_right_click()
	_check(_gs.location_of("M3-TEST-A") == "inbox" and _main.interaction.hand_kind() == "", "right-click returns a picked-up inbox item to the inbox")
	_gs.remove_doc("M3-TEST-A")
	_gs.remove_doc("M3-TEST-B")
	_check(id == "M3-TEST-A", "inbox fixtures cleaned up")


func _checks_blank_tray_and_hand() -> void:
	var before := int(_gs.tray_count)
	_main.interaction.dispatch_click("blank_tray")
	_check(int(_gs.tray_count) == before - 1, "blank tray click takes one sheet")
	_check(_main.interaction.hand_kind() == "document", "the sheet is in the hand")
	var held_id: String = _main.interaction.hand_id()
	_main.interaction.dispatch_click("blank_tray")
	_check(int(_gs.tray_count) == before - 1, "a second blank tray click with a sheet in hand takes nothing")
	_main.interaction.hand_release()
	_check(_main.interaction.hand_kind() == "", "hand_release empties the hand")
	_gs.remove_doc(held_id)
	_gs.tray_count = 0
	_main.interaction.dispatch_click("blank_tray")
	_check(_main.interaction.hand_kind() == "", "an empty tray does nothing")
	_gs.tray_count = before - 1
	_main.desk.refresh()
	var stack: Node = _main.hall.get_node("Desk04/BlankStack/Stack")
	_check(stack.get_child_count() == before - 1, "blank stack shows one sheet per remaining count")
	_main.interaction.dispatch_click("stamp:APPROVED")
	_check(_main.interaction.hand_kind() == "stamp:APPROVED", "stamp on the rack is picked up")
	var handle := _main.hall.get_node("Desk04/StampRack/HandleApproved") as Node3D
	_check(not handle.visible, "the picked stamp's handle is hidden on the rack")
	_main.interaction.dispatch_right_click()
	_check(_main.interaction.hand_kind() == "" and handle.visible, "right-click returns the stamp to the rack")
	_main.interaction.dispatch_click("marker")
	_check(_main.interaction.hand_kind() == "marker", "marker is picked up")
	_main.interaction.dispatch_right_click()
	_check(_main.interaction.hand_kind() == "", "right-click returns the marker")
	_main.interaction.dispatch_click("fluid")
	_check(_main.interaction.hand_kind() == "fluid", "correction fluid is picked up")
	_main.interaction.dispatch_right_click()
	_check(_main.interaction.hand_kind() == "", "right-click returns the fluid")
	await process_frame


func _checks_copyholder_and_typewriter() -> void:
	_main.interaction.dispatch_click("blank_tray")
	var id: String = _main.interaction.hand_id()
	_main.interaction.dispatch_click("copyholder")
	_check(String(_gs.loc.copyholder) == id and _main.interaction.hand_kind() == "", "copyholder clips the held document")
	_main.interaction.dispatch_click("copyholder")
	_check(_main.read_view.is_open() and String(_main.read_view.current_doc().id) == id, "empty-hand copyholder click opens read view on the clipped document")
	_close_read()
	_main.interaction.dispatch_click("blank_tray")
	var second: String = _main.interaction.hand_id()
	_main.interaction.dispatch_click("copyholder")
	_check(String(_gs.loc.copyholder) == second and _gs.location_of(id) == "read_stack", "a new clip returns the previous one to the read stack")
	_main.interaction.hand_release()
	_gs.remove_doc(id)
	_gs.remove_doc(second)
	_gs.loc.copyholder = ""
	# Typewriter: a held free sheet is loaded and the view is entered.
	_main.interaction.dispatch_click("blank_tray")
	var sheet: String = _main.interaction.hand_id()
	_main.interaction.dispatch_click("typewriter")
	_check(_main.typewriter.is_loaded() and _main.typewriter.loaded_doc_id() == sheet, "typewriter click loads the held sheet")
	_check(_main.interaction.hand_kind() == "", "the loaded sheet leaves the hand")
	await _wait(1.8)
	_check(_main.typewriter.is_typing(), "the typewriter click enters the typing view")
	_main.typewriter.close_typing_view()
	await _wait(0.8)
	_check(not _main.is_focus_open(), "closing the typing view clears the focus flag")
	_main.typewriter.unload_sheet()
	_gs.remove_doc(sheet)
	_main.interaction.dispatch_click("typewriter")
	_check(not _main.typewriter.is_loaded(), "typewriter with no sheet and an empty hand does nothing")


func _checks_drawers_and_notebook() -> void:
	var desk = _main.hall.get_node("Desk04")
	var notebook := desk.get_node("Notebook") as Node3D
	var rest_z := notebook.position.z
	_main.interaction.dispatch_click("drawer_top")
	await _wait(0.5)
	_check(_main.desk.drawer_open("top"), "top drawer opens on click")
	_check(absf(_main.desk.drawers.slide_metres("top") - 0.30) < 0.005, "top drawer slides 0.30 m")
	_check(absf(notebook.position.z - (rest_z + 0.30)) < 0.005, "the notebook moves with the top drawer")
	_main.interaction.dispatch_click("notebook")
	_check(_main.read_view.is_open(), "notebook opens the read view while the top drawer is open")
	_close_read()
	_main.interaction.dispatch_click("drawer_top")
	await _wait(0.5)
	_check(not _main.desk.drawer_open("top") and absf(_main.desk.drawers.slide_metres("top")) < 0.005, "a second click closes the top drawer")
	_main.interaction.dispatch_click("notebook")
	_check(not _main.read_view.is_open(), "notebook is not clickable while the top drawer is shut")
	_main.interaction.dispatch_click("drawer_lower")
	await _wait(0.5)
	_check(_main.desk.drawer_open("lower"), "lower drawer opens on click")
	_add_doc("M3-TEST-CARBON", "carbon_spot", "carbon")
	var filed: int = _main.carbon_view.carbon_spot_clicked()
	_check(filed == 1 and _gs.location_of("M3-TEST-CARBON") == "drawer", "lower drawer open: the carbon spot files its carbons")
	_gs.remove_doc("M3-TEST-CARBON")
	_gs.loc.drawer.clear()
	_main.interaction.dispatch_click("drawer_lower")
	await _wait(0.5)
	_check(not _main.desk.drawer_open("lower"), "lower drawer closes on the second click")


func _checks_lamp() -> void:
	_gs.end_of_shift_arrived = false
	_main.interaction.dispatch_click("lamp")
	_check(bool(_gs.lamp_on), "lamp before the End of Shift memo does not end the day")
	_gs.end_of_shift_arrived = true
	_main.interaction.dispatch_click("lamp")
	_check(not bool(_gs.lamp_on), "lamp after the End of Shift memo switches the lamp off")
	await _wait(0.1)
	_check(not _main.lamp.is_lit(), "the desk lamp light is off")
	_gs.lamp_on = true
	_gs.end_of_shift_arrived = false
	await _wait(0.1)
	_check(_main.lamp.is_lit(), "the desk lamp light follows GameState")


func _checks_tube() -> void:
	var id := _add_doc("M3-TEST-MEMO", "inbox", "memo")
	var before := int(_gs.misc_sent)
	_gs.place(id, "hand")
	_main.interaction.hand_hold("document", id, "")
	_main.interaction.dispatch_click("tube_receiver")
	await _wait(1.2)
	_check(int(_gs.misc_sent) == before + 1 and not _gs.docs.has(id), "tube receiver sends the held document")
	_check(_main.interaction.hand_kind() == "", "the hand is empty after the send")


func _checks_walk_and_sit() -> void:
	var player = _main.player
	player.set_look(0.0, -10.0)
	player.try_space()
	_check(player.is_transitioning(), "Space starts the rise")
	await _wait(0.8)
	_check(player.is_standing(), "the player stands after the rise")
	_check(_near(player.position, Vector3(5.25, 0.0, 4.40), 0.02), "standing body is 0.3 m south of the seat")
	_check(absf(player.camera().global_position.y - 1.62) < 0.02, "standing eye height is 1.62 m")
	var start: Vector3 = player.position
	player.debug_set_move(Vector2(1.0, 0.0))
	var waited := 0.0
	while Vector2(player.position.x - start.x, player.position.z - start.z).length() < 1.0 and waited < 3.0:
		await physics_frame
		waited += 1.0 / 60.0
	player.debug_clear_move()
	var walked := Vector2(player.position.x - start.x, player.position.z - start.z).length()
	_check(absf(walked - 1.0) < 0.05, "WASD walk covers 1 m (walked %.3f m)" % walked)
	_check(player.near_chair(), "the player is within 1.2 m of the chair after walking")
	player.try_space()
	_check(player.is_transitioning(), "Space within 1.2 m of the chair starts the sit")
	await _wait(1.0)
	_check(player.is_seated(), "the player is seated again")
	_check(_near(player.camera().global_position, SEAT_EYE, 0.02), "the camera is back at the seated eye (0.02 m)")
	_check(absf(player.yaw_degrees()) < 0.01, "the seated pose faces north")
	player.set_look(300.0, 0.0)
	_check(absf(player.yaw_degrees()) <= 110.0 + 0.01, "seated yaw is clamped to +-110 degrees")
	player.set_look(0.0, -200.0)
	_check(player.pitch_degrees() >= -60.0 - 0.01, "seated pitch is clamped at -60 degrees")
	player.set_look(0.0, 0.0)
	await process_frame


func _teardown() -> void:
	if _gs.docs.has("M3-TEST-MEMO"):
		_gs.remove_doc("M3-TEST-MEMO")
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	_main.queue_free()
