extends SceneTree
## Pick reach checks (spec 6.2, 6.4, 12). From the seated pose, real left clicks (InputEventMouseButton
## through Input.parse_input_event) reach the top drawer, the notebook, the lower drawer and the read
## stack. Every body with an "action" meta sits on the pick layer. Walking is still stopped by the desk
## box and by the chair.
## Run: godot --headless --path /home/user/Carbon --script res://tests/player/test_pick_reach.gd
## Exit 0 only when every check passes. Prints one PASS or FAIL line per check and then
## "PICK REACH: N checks, M failures". Lines starting with two spaces are diagnostics, not checks.

const MainScript := preload("res://scripts/main.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")

const PICK_LAYER := 2
const TEST_SAVE := "user://pick_reach_test_save.json"
const MIN_PICK_BODIES := 30

var _checks := 0
var _fails := 0
var _started := false
var _main = null
var _gs = null
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
	_ss = root.get_node("SaveSystem")
	_ss.save_path = TEST_SAVE
	_main = MainScript.new()
	_main.auto_boot = false
	root.add_child(_main)
	await process_frame
	_main.debug_start_game(4242)
	await process_frame
	_main._begin_running()
	await _wait(0.2)
	await _checks_pick_layers()
	await _checks_seated_clicks()
	await _checks_walk_blocked()
	_teardown()
	print("PICK REACH: %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)


# --- Helpers ---------------------------------------------------------------------------

func _doc(id: String, kind: String = "memo") -> Dictionary:
	var doc := DocModel.new_doc(id, kind, "typed", "black")
	doc.pages.append(DocModel.new_page())
	return doc


func _pick(path: String) -> Node3D:
	return _main.hall.get_node_or_null(path) as Node3D


## Turns the seated camera so that its centre ray points at target (world space).
func _aim_at(target: Vector3) -> void:
	var cam: Camera3D = _main.player.camera()
	var d := target - cam.global_position
	var h := Vector2(d.x, d.z).length()
	_main.player.set_look(rad_to_deg(atan2(-d.x, -d.z)), rad_to_deg(atan2(d.y, h)))
	await physics_frame


## The action the centre ray would act on now (empty when it hits nothing).
func _ray_action() -> String:
	var hit: Dictionary = _main.interaction._raycast()
	if hit.is_empty():
		return "(nothing)"
	var action := String(hit.get("action", ""))
	return action if action != "" else "(no action)"


## A real left click: press, then release, as the mouse would send them.
func _click() -> void:
	var pos := root.get_visible_rect().size * 0.5
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		ev.position = pos
		ev.global_position = pos
		Input.parse_input_event(ev)
		await process_frame


## Aims at the node's current world centre, then clicks it. Returns what the ray hit before the click.
func _aim_click(node: Node3D) -> String:
	await _aim_at(node.global_position)
	var hit := _ray_action()
	await _click()
	return hit


## Searches a 5 x 5 grid over a pick body's top face for a point the seated ray reaches with the wanted action.
func _find_reach(pick: Node3D, action: String) -> Dictionary:
	var box := (pick.get_child(0) as CollisionShape3D).shape as BoxShape3D
	var half := Vector2(box.size.x, box.size.z) * 0.5
	var total := 0
	var count := 0
	var first := Vector3.ZERO
	var ok := false
	var tally := {}
	for u in [-0.8, -0.4, 0.0, 0.4, 0.8]:
		for v in [-0.8, -0.4, 0.0, 0.4, 0.8]:
			total += 1
			var p: Vector3 = pick.global_transform * Vector3(u * half.x, 0.0, v * half.y)
			await _aim_at(p)
			var seen := _ray_action()
			tally[seen] = int(tally.get(seen, 0)) + 1
			if seen == action:
				count += 1
				if not ok:
					ok = true
					first = p
	print("  sample hits for the %s grid: %s" % [action, str(tally)])
	return {"ok": ok, "point": first, "count": count, "total": total}


func _collect_actions(node: Node, out: Array) -> void:
	if node.has_meta("action"):
		out.append(node)
	for c in node.get_children():
		_collect_actions(c, out)


# --- Checks ----------------------------------------------------------------------------

func _checks_pick_layers() -> void:
	var bodies: Array = []
	_collect_actions(_main, bodies)
	var off := 0
	for n in bodies:
		var layer := -1
		if n is CollisionObject3D:
			layer = (n as CollisionObject3D).collision_layer
		var on := layer >= 0 and (layer & PICK_LAYER) != 0
		if not on:
			off += 1
		print("  %-52s %-24s layer %d %s" % [str(_main.get_path_to(n)), String(n.get_meta("action")), layer,
			"" if on else "(NOT on the pick layer)"])
	_check(bodies.size() >= MIN_PICK_BODIES and off == 0,
		"every body with an action meta has the pick layer bit (%d bodies, %d without)" % [bodies.size(), off])
	var cc := _pick("Chair04/ChairCollision") as CollisionObject3D
	_check(cc != null and (cc.collision_layer & 1) != 0, "ChairCollision keeps physics layer 1 (walking)")


func _checks_seated_clicks() -> void:
	var player = _main.player
	var drawers = _main.desk.drawers
	_check(player.is_seated() and _main.interaction.enabled, "free view is live: seated and interaction enabled")
	_check(_pick("Chair04/ChairCollision") != null, "the chair is in place")

	var top := _pick("Desk04/DrawerTop/Pick")
	var hit := await _aim_click(top)
	await _wait(0.5)
	_check(drawers.is_open("top"), "1. a seated click on the top drawer opens it (ray hit: %s)" % hit)
	var was_open: bool = drawers.is_open("top")
	hit = await _aim_click(top)
	await _wait(0.5)
	_check(was_open and not drawers.is_open("top"), "1. a second seated click closes it (ray hit: %s)" % hit)

	hit = await _aim_click(top)
	await _wait(0.5)
	_check(drawers.is_open("top"), "2. top drawer open for the notebook check (ray hit: %s)" % hit)
	hit = await _aim_click(_pick("Desk04/Notebook/Pick"))
	_check(_main.read_view.is_open(), "2. with the top drawer open, a seated click on the notebook opens its read view (ray hit: %s)" % hit)
	_main.read_view.close()
	await process_frame
	was_open = drawers.is_open("top")
	hit = await _aim_click(top)
	await _wait(0.5)
	_check(was_open and not drawers.is_open("top"), "top drawer closed again before the lower drawer (ray hit: %s)" % hit)

	var lower := _pick("Desk04/DrawerLower/Pick")
	hit = await _aim_click(lower)
	await _wait(0.5)
	_check(drawers.is_open("lower"), "3. a seated click on the lower drawer opens it, chair in place (ray hit: %s)" % hit)
	was_open = drawers.is_open("lower")
	hit = await _aim_click(lower)
	await _wait(0.5)
	_check(was_open and not drawers.is_open("lower"), "3. a second seated click closes the lower drawer (ray hit: %s)" % hit)

	_add_doc("PR-TEST-A")
	var stack := _pick("Desk04/ReadStack/Pick")
	var found := await _find_reach(stack, "read_stack")
	_check(found.ok, "4. the read stack is reachable from the seat (%d of %d sample points)" % [found.count, found.total])
	if found.ok:
		await _aim_at(found.point)
		await _click()
	var shown := String(_main.read_view.current_doc().get("id", "")) if _main.read_view.is_open() else ""
	_check(shown == "PR-TEST-A", "4. with a document on the read stack, a seated click opens the read view on it (shown: %s)" % shown)
	_main.read_view.close()
	await process_frame
	await _reach_table()


## Diagnostics only (no PASS or FAIL): where the seated centre ray lands on each other Desk 4 pick.
func _reach_table() -> void:
	var paths := [
		"Desk04/InboxTray/Pick", "Desk04/BlankTray/Pick", "Desk04/CarbonSpot/Pick", "Desk04/Copyholder/Pick",
		"Desk04/StampRack/HandleApproved/Pick", "Desk04/StampRack/HandleDenied/Pick",
		"Desk04/StampRack/HandleProcessed/Pick", "Desk04/StampRack/HandleReturned/Pick",
		"Desk04/Marker/Pick", "Desk04/CorrectionBottle/Pick", "Desk04/Lamp/Pick",
		"Desk04/DrawerTop/Pick", "Desk04/DrawerLower/Pick", "Typewriter04/Body/Pick", "Tube04/Receiver/Pick",
	]
	for p in paths:
		var node := _pick(p)
		if node == null:
			print("  reach table: %s is missing" % p)
			continue
		await _aim_at(node.global_position)
		print("  reach table: %-40s centre aim hits %s" % [p, _ray_action()])
	for pair in [["Desk04/CarbonSpot/Pick", "carbon_spot"], ["Desk04/BlankTray/Pick", "blank_tray"]]:
		var found := await _find_reach(_pick(pair[0]), pair[1])
		print("  reach table: %-40s grid reaches it at %d of %d points" % [pair[0], found.count, found.total])


func _add_doc(id: String) -> void:
	_gs.add_doc(_doc(id), "read_stack")


func _checks_walk_blocked() -> void:
	var player = _main.player
	var hall = _main.hall
	player.try_space()
	await _wait(0.8)
	_check(player.is_standing(), "the player stands up (Space) for the walk checks")
	var desk_root = hall.get_node_or_null("Desk04")
	var chair_body = hall.get_node_or_null("Chair04/ChairCollision")

	player.global_position = Vector3(4.55, 0.0, 4.60)
	await physics_frame
	var kc := KinematicCollision3D.new()
	var hit_desk: bool = player.test_move(player.global_transform, Vector3(0.0, 0.0, -1.0), kc)
	var by_desk: bool = hit_desk and desk_root != null and kc.get_collider() is Node \
		and (kc.get_collider() as Node).get_parent() == desk_root
	_check(by_desk, "6. a walk north towards the desk is stopped by the desk box")

	player.global_position = Vector3(5.25, 0.0, 4.90)
	await physics_frame
	var kc2 := KinematicCollision3D.new()
	var hit_chair: bool = player.test_move(player.global_transform, Vector3(0.0, 0.0, -1.0), kc2)
	_check(hit_chair and kc2.get_collider() == chair_body, "6. a walk north is stopped by the chair body")


func _teardown() -> void:
	if _gs.docs.has("PR-TEST-A"):
		_gs.remove_doc("PR-TEST-A")
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	_main.queue_free()
