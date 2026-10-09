extends SceneTree
## Inert pick checks (spec 6.2, 6.4). A pick whose click would do nothing in the current state is
## skipped by the seated centre ray, so it does not hide the pick behind it. The rule is
## interaction.gd's _is_inert: the inbox with no documents; the read stack empty with nothing in hand;
## the carbon spot with no carbons and the lower drawer shut; the blank tray at zero; the copyholder
## with nothing in hand and nothing clipped. Every other pick still blocks. Real left clicks
## (InputEventMouseButton through Input.parse_input_event) drive the ray, as test_pick_reach.gd does.
## Run: godot --headless --path /home/user/Carbon --script res://tests/player/test_inert_picks.gd
## Exit 0 only when every check passes. Prints one PASS or FAIL line per check and then
## "INERT PICKS: N checks, M failures". Lines starting with two spaces are diagnostics, not checks.

const MainScript := preload("res://scripts/main.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")

const TEST_SAVE := "user://inert_picks_test_save.json"
## The 5 x 5 aim grid over a pick's top face (the same grid as test_pick_reach.gd).
const GRID := [-0.8, -0.4, 0.0, 0.4, 0.8]

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
	await _checks_free_view()
	await _checks_read_stack_past_copyholder()
	await _checks_copyholder_blocks()
	await _checks_inbox()
	await _checks_copyholder_click_changes_nothing()
	await _checks_rule_table()
	await _checks_still_blocking()
	await _teardown()
	print("INERT PICKS: %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)


# --- Helpers ---------------------------------------------------------------------------

func _doc(id: String, kind: String = "memo") -> Dictionary:
	var doc := DocModel.new_doc(id, kind, "typed", "black")
	doc.pages.append(DocModel.new_page())
	return doc


func _add_doc(id: String, location: String, kind: String = "memo") -> void:
	_gs.add_doc(_doc(id, kind), location)


## Puts a new document in the hand, as a pick-up from the read stack would.
func _hold_doc(id: String) -> void:
	_add_doc(id, "read_stack")
	_main.interaction.hand_hold("document", id, "read_stack")


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


## Aims at each of the 25 grid points of a pick's top face. Returns [{point, action}] in grid order.
func _grid_actions(pick: Node3D) -> Array:  # of Dictionary
	var box := (pick.get_child(0) as CollisionShape3D).shape as BoxShape3D
	var half := Vector2(box.size.x, box.size.z) * 0.5
	var out := []
	for u in GRID:
		for v in GRID:
			var p: Vector3 = pick.global_transform * Vector3(u * half.x, 0.0, v * half.y)
			await _aim_at(p)
			out.append({"point": p, "action": _ray_action()})
	return out


## Counts the grid points whose ray hits the wanted action. ok and point name the first such point.
func _find_reach(pick: Node3D, action: String) -> Dictionary:
	var hits: Array = await _grid_actions(pick)
	var count := 0
	var first := Vector3.ZERO
	var ok := false
	var tally := {}
	for h in hits:
		var seen := String(h.action)
		tally[seen] = int(tally.get(seen, 0)) + 1
		if seen == action:
			count += 1
			if not ok:
				ok = true
				first = h.point
	print("  sample hits for the %s grid: %s" % [action, str(tally)])
	return {"ok": ok, "point": first, "count": count, "total": hits.size(), "tally": tally}


## The id of the document the read view shows ("" when no read view is open).
func _shown_id() -> String:
	return String(_main.read_view.current_doc().get("id", "")) if _main.read_view.is_open() else ""


func _close_read() -> void:
	if _main.read_view.is_open():
		_main.read_view.close()
		await process_frame


## interaction.gd's _is_inert. Until it exists, every check that uses it fails.
func _inert(action: String) -> bool:
	return _main.interaction.has_method("_is_inert") and bool(_main.interaction.call("_is_inert", action))


## Everything that a click on the desk could change: the hand, the stacks, the copyholder,
## the blank tray count, the drawers and the read view.
func _snapshot() -> Array:
	var it = _main.interaction
	return [
		_gs.loc.duplicate(true), int(_gs.tray_count), it.hand_kind(), it.hand_id(), _gs.docs.size(),
		_main.desk.drawer_open("top"), _main.desk.drawer_open("lower"), _main.read_view.is_open(),
	]


## Empties the inbox, the read stack, the carbon spot, the copyholder and the hand, refills the
## blank tray and shuts both drawers. Every check starts from this state.
func _clean_desk() -> void:
	await _close_read()
	if _main.interaction.holding():
		_main.interaction.hand_release()
	for key in ["hand", "copyholder"]:
		var id := String(_gs.loc[key])
		if id != "":
			_gs.remove_doc(id)
	for stack in ["inbox", "read_stack", "carbon_spot"]:
		for id in _gs.loc[stack].duplicate():
			_gs.remove_doc(String(id))
	_gs.tray_count = 10
	var toggled := false
	for which in ["top", "lower"]:
		if _main.desk.drawer_open(which):
			_main.desk.toggle_drawer(which)
			toggled = true
	if toggled:
		await _wait(0.5)
	await process_frame


# --- Checks ----------------------------------------------------------------------------

func _checks_free_view() -> void:
	_check(_main.player.is_seated() and _main.interaction.enabled, "free view is live: seated and interaction enabled")
	await _clean_desk()
	_check(_gs.loc.inbox.is_empty() and String(_gs.loc.copyholder) == "" and not _main.interaction.holding(),
		"the desk is cleared: empty inbox, empty copyholder, nothing in hand")


## Acceptance 1: from the seat, nothing in hand, one document on the read stack, the empty copyholder
## and the empty inbox in front. A real click on the read stack opens the read view on that document.
func _checks_read_stack_past_copyholder() -> void:
	await _clean_desk()
	_add_doc("INERT-READ", "read_stack")
	var found := await _find_reach(_pick("Desk04/ReadStack/Pick"), "read_stack")
	print("  REACH read stack from the seat: %d of %d aim points (empty inbox and copyholder, one document on the stack, nothing in hand)" % [found.count, found.total])
	_check(found.ok, "1. the read stack is reached from the seat past the empty copyholder and inbox (%d of %d aim points)" % [found.count, found.total])
	_check(int(found.tally.get("copyholder", 0)) == 0, "1. no aim point on the read stack is stopped by the empty copyholder (%d such points)" % int(found.tally.get("copyholder", 0)))
	if found.ok:
		await _aim_at(found.point)
		await _click()
	var shown := _shown_id()
	_check(shown == "INERT-READ", "1. a real left click on the read stack opens the read view on that document (shown: %s)" % shown)
	await _close_read()


## Acceptance 2: the same aim with the copyholder holding a clipped document. The copyholder is active
## and blocks, so the read stack is not opened; a click opens the copyholder's read view instead.
func _checks_copyholder_blocks() -> void:
	await _clean_desk()
	_add_doc("INERT-READ", "read_stack")
	var stack := _pick("Desk04/ReadStack/Pick")
	var empty_hits: Array = await _grid_actions(stack)
	_add_doc("INERT-CLIP", "copyholder")
	var clipped_hits: Array = await _grid_actions(stack)
	var point := Vector3.ZERO
	var found := false
	for i in empty_hits.size():
		if String(empty_hits[i].action) == "read_stack" and String(clipped_hits[i].action) == "copyholder":
			point = empty_hits[i].point
			found = true
			break
	_check(found, "2. an aim point that reaches the read stack past the empty copyholder hits the copyholder once a document is clipped to it")
	var hit := ""
	if found:
		await _aim_at(point)
		hit = _ray_action()
		await _click()
	var shown := _shown_id()
	_check(found and hit == "copyholder", "2. with a document clipped to the copyholder, the same aim hits the copyholder (ray: %s)" % hit)
	_check(shown == "INERT-CLIP", "2. a real click there opens the copyholder's read view, not the read stack (shown: %s)" % shown)
	await _close_read()


## Acceptance 3: an empty inbox does not block. With one document in the inbox, its click opens the
## read view on that document. With the inbox empty, the aim at the inbox tray reaches the read stack.
func _checks_inbox() -> void:
	await _clean_desk()
	_add_doc("INERT-READ", "read_stack")
	var found := await _find_reach(_pick("Desk04/InboxTray/Pick"), "read_stack")
	_check(found.ok, "3. with an empty inbox, the aim at the inbox tray reaches the read stack behind it (%d of %d aim points)" % [found.count, found.total])
	if found.ok:
		await _aim_at(found.point)
		await _click()
	var shown := _shown_id()
	_check(shown == "INERT-READ", "3. a real click on that aim point opens the read view on the stack's document (shown: %s)" % shown)
	await _close_read()

	await _clean_desk()
	_add_doc("INERT-READ", "read_stack")
	_add_doc("INERT-INBOX", "inbox")
	var hit := await _aim_click(_pick("Desk04/InboxTray/Pick"))
	shown = _shown_id()
	_check(shown == "INERT-INBOX", "3. with a document in the inbox, a seated click on the inbox opens its read view (ray hit: %s, shown: %s)" % [hit, shown])
	await _close_read()


## Acceptance 4: a click on the copyholder with nothing clipped and nothing in hand does nothing.
## The read stack is empty, so nothing behind the copyholder can answer the click.
func _checks_copyholder_click_changes_nothing() -> void:
	await _clean_desk()
	var before := _snapshot()
	var seen := await _aim_click(_pick("Desk04/Copyholder/Pick"))
	_check(not _main.read_view.is_open(), "4. a real click on the empty copyholder opens no read view (ray hit: %s)" % seen)
	_check(_snapshot() == before, "4. a real click on the empty copyholder changes no state")
	await _clean_desk()
	before = _snapshot()
	_main.interaction.dispatch_click("copyholder")
	_check(not _main.read_view.is_open() and _snapshot() == before, "4. dispatch_click on the empty copyholder changes no state and opens no read view")


## interaction.gd's _is_inert, one state at a time (the rule table of the brief).
func _checks_rule_table() -> void:
	await _clean_desk()
	_check(_inert("inbox"), "rule: an inbox with no documents is inert")
	_add_doc("INERT-INBOX", "inbox")
	_check(not _inert("inbox"), "rule: an inbox with a document is not inert")
	_gs.remove_doc("INERT-INBOX")

	await _clean_desk()
	_check(_inert("read_stack"), "rule: an empty read stack with nothing in hand is inert")
	_add_doc("INERT-READ", "read_stack")
	_check(not _inert("read_stack"), "rule: a read stack with a document is not inert")
	_gs.remove_doc("INERT-READ")
	_hold_doc("INERT-HAND")
	_check(not _inert("read_stack"), "rule: an empty read stack is not inert while a document is in hand")
	await _clean_desk()

	await _clean_desk()
	_check(_inert("carbon_spot"), "rule: an empty carbon spot with the lower drawer shut is inert")
	_add_doc("INERT-CARBON", "carbon_spot", "carbon")
	_check(not _inert("carbon_spot"), "rule: a carbon spot with a carbon is not inert")
	_gs.remove_doc("INERT-CARBON")
	_main.desk.toggle_drawer("lower")
	await _wait(0.5)
	_check(not _inert("carbon_spot"), "rule: an empty carbon spot with the lower drawer open is not inert (a click there files)")
	_main.desk.toggle_drawer("lower")
	await _wait(0.5)
	_check(_inert("carbon_spot"), "rule: an empty carbon spot is inert again once the lower drawer is shut")

	await _clean_desk()
	_gs.tray_count = 0
	_check(_inert("blank_tray"), "rule: a blank tray at zero is inert")
	_gs.tray_count = 1
	_check(not _inert("blank_tray"), "rule: a blank tray with one sheet is not inert")

	await _clean_desk()
	_check(_inert("copyholder"), "rule: an empty copyholder with nothing in hand is inert")
	_add_doc("INERT-CLIP", "copyholder")
	_check(not _inert("copyholder"), "rule: a copyholder with a clipped document is not inert")
	_gs.remove_doc("INERT-CLIP")
	_hold_doc("INERT-HAND")
	_check(not _inert("copyholder"), "rule: an empty copyholder is not inert while a document is in hand")
	await _clean_desk()


## Every pick outside the rule keeps blocking (never inert), in the same empty desk state.
func _checks_still_blocking() -> void:
	await _clean_desk()
	var others := ["marker", "fluid", "stamp:APPROVED", "stamp:RETURNED", "drawer_top", "drawer_lower",
		"lamp", "notebook", "typewriter", "tube_receiver", "chair_04", "door_exit"]
	var inert_ones := []
	for a in others:
		if _inert(a):
			inert_ones.append(a)
	_check(inert_ones.is_empty(), "every other pick keeps blocking (inert: %s)" % str(inert_ones))

	# Positive evidence that the rule is narrow: these picks are still hit by the ray.
	await _clean_desk()
	_add_doc("INERT-READ", "read_stack")
	_hold_doc("INERT-HAND")
	var stack_hits: Array = await _grid_actions(_pick("Desk04/ReadStack/Pick"))
	_check(_count_action(stack_hits, "read_stack") > 0, "an empty read stack still blocks while a document is in hand (%d of 25 aim points hit it)" % _count_action(stack_hits, "read_stack"))

	await _clean_desk()
	_add_doc("INERT-CARBON", "carbon_spot", "carbon")
	var spot_hits: Array = await _grid_actions(_pick("Desk04/CarbonSpot/Pick"))
	_check(_count_action(spot_hits, "carbon_spot") > 0, "a carbon spot with a carbon still blocks (%d of 25 aim points hit it)" % _count_action(spot_hits, "carbon_spot"))

	await _clean_desk()
	_hold_doc("INERT-HAND")
	var holder_hits: Array = await _grid_actions(_pick("Desk04/Copyholder/Pick"))
	_check(_count_action(holder_hits, "copyholder") > 0, "an empty copyholder still blocks while a document is in hand (%d of 25 aim points hit it)" % _count_action(holder_hits, "copyholder"))

	await _clean_desk()
	_gs.tray_count = 10
	await _aim_at(_pick("Desk04/BlankTray/Pick").global_position)
	_check(_ray_action() == "blank_tray", "a blank tray with sheets still blocks the centre ray (ray: %s)" % _ray_action())


func _count_action(hits: Array, action: String) -> int:
	var n := 0
	for h in hits:
		if String(h.action) == action:
			n += 1
	return n


func _teardown() -> void:
	await _clean_desk()
	if FileAccess.file_exists(TEST_SAVE):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVE))
	_main.queue_free()
	await process_frame
