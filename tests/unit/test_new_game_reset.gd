extends SceneTree
## New game reset checks (spec 9.2, 9.3, 8.9, 16.2). Boots the real main scene with the front end off and plays
## to a state with the unseen changes applied (Chair12 pulled out, the Clerk12 apparition, the ghost sheet, the
## door silhouette, the clock at 03:10, unison typing), with Desk 5 removed by redaction and Clerk 6 gone. Then it
## starts a new game through the real _on_new_game and checks that the unseen registry is clear and the world is
## back to its built state. Headless:
##   godot --headless --path . --script res://tests/unit/test_new_game_reset.gd
## Prints one PASS or FAIL line per check, then "NEW GAME RESET: N checks, M failure(s)". Exit 0 only when M is 0.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const Content := preload("res://scripts/logic/content.gd")
const SETTLE_FRAMES := 6
const TRANSITION_TIMEOUT_S := 60.0
const TYPING_DESKS := [1, 2, 3, 5, 6, 7, 8, 9, 10, 11]

var _main
var _gs
var _dd
var _un
var _hall: Node3D = null
var _step := 0
var _frames := 0
var _waited := 0.0
var _checks := 0
var _failures := 0
var _built_chair12 := {}
var _built_clerk_yaw := 0.0


func _process(delta: float) -> bool:
	_frames += 1
	match _step:
		0:
			_boot()
			_step = 1
		1:
			if _frames >= SETTLE_FRAMES:
				_play_to_day_four()
				_check_played_state()
				_main._on_new_game()
				_step = 2
		2:
			_waited += delta
			if _waited > TRANSITION_TIMEOUT_S:
				_check(false, "the new game transition finishes within %d s" % int(TRANSITION_TIMEOUT_S))
				_finish()
				return true
			if not bool(_main.get("_transition")):
				_check_new_game_state()
				_finish()
				return true
	return false


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _finish() -> void:
	print("NEW GAME RESET: %d checks, %d failure(s)" % [_checks, _failures])
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _boot() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.auto_boot = false
	root.add_child(_main)
	_gs = root.get_node("GameState")
	_dd = root.get_node("DayDirector")
	_un = root.get_node("UnseenChanges")
	_main.debug_start_game(4242)
	_main.debug_run(true)
	_hall = _main.hall
	_built_chair12 = _pose(_node("Chair12"))
	_built_clerk_yaw = _node("Clerk01").rotation.y


## Plays the world to Day 4 with the changes of Days 1 to 4 applied through the registry's own apply path
## (the distance and unseen timing are not what this test checks). The redaction of Desk 5 and Clerk 6 is set in
## GameState as RO-3 and RO-4 would set it, and the day start then applies it (ClerkBehaviour.apply_day_state).
func _play_to_day_four() -> void:
	_dd.task_sent.emit("T-1")
	_un.flush_pending()
	_gs.day = 2
	_dd.task_sent.emit("RO-2")
	_apply_change("D2-U2")
	_gs.day = 3
	_dd.task_sent.emit("RO-3")
	_dd.task_sent.emit("F-3")
	_apply_change("D3-U1")
	_apply_change("D3-U2")
	_apply_change("D3-U3")
	_gs.day = 4
	_dd.task_sent.emit("T-4")
	_apply_change("D4-U2")
	_dd.task_sent.emit("RO-4")
	_gs.desk_removed["5"] = true
	_gs.clerk_present["5"] = false
	_gs.clerk_present["6"] = false
	_main.clerk_world.apply_day_state(4)


func _check_played_state() -> void:
	_check(not _same_pose(_node("Chair12"), _built_chair12), "played state: Chair12 is pulled out of its built place")
	_check(_node("Clerk12") != null, "played state: the Clerk12 apparition is present")
	_check(_silhouette() != null, "played state: the door silhouette is present")
	_check(_main.typewriter.loaded_doc_id() != "", "played state: the ghost sheet is loaded on the typewriter")
	_check(bool(_gs.flags.get("unison_typing", false)), "played state: unison typing is on")
	_check(String(_gs.flags.get("clock_override", "")) == "03:10", "played state: the clock shows the 03:10 override")
	_check(_node("Desk05") == null and _node("Clerk05") == null and _node("Clerk06") == null and _node("Chair06") == null,
		"played state: Desk 5 is removed, and Clerk 6 and Chair 6 are removed")
	_check(_applied("D3-U1") and _applied("D4-U2"), "played state: D3-U1 and D4-U2 are applied in the registry")
	_check(_applied("D4-U1") or _pending("D4-U1"), "played state: D4-U1 is pending or applied (a pending change to reset)")


## The new game (spec 16.2): every registry row is clear, and the hall is back in its built state.
func _check_new_game_state() -> void:
	_check(_registry_clear(), "new game: every unseen change is neither pending, applied nor reverted")
	_check(not bool(_gs.flags.get("unison_typing", false)), "new game: the unison typing flag is cleared")
	_check(String(_gs.flags.get("clock_override", "")) == "", "new game: the clock override is cleared")
	_check(not _gs.flags.has("desk12_chair_out") and not _gs.flags.has("tray_line"),
		"new game: the Desk 12 chair and tray flags are cleared")

	_check(_same_pose(_node("Chair12"), _built_chair12), "new game: Chair12 is back at its built position and rotation")
	_check(_node("Clerk12") == null, "new game: the Clerk12 apparition is gone")
	_check(_silhouette() == null, "new game: the door silhouette is gone")

	_check(_gs.loc.typewriter == "" and _main.typewriter.loaded_doc_id() == "",
		"new game: no ghost sheet is loaded on the typewriter")
	var paper: Node3D = _main.typewriter_node.find_child("Paper", true, false) as Node3D
	_check(paper != null and not paper.visible, "new game: the typewriter paper is hidden")

	var names: Dictionary = Content.strings()["nameplates"]
	var names_ok := true
	for n in range(1, 13):
		if String(_gs.nameplate.get(str(n), "")) != String(names.get(str(n), "")):
			names_ok = false
	_check(names_ok, "new game: every nameplate is back to its built name (Desk 4 0412, Desk 12 blank)")

	var parts_ok := true
	for n in range(1, 13):
		for prefix in ["Desk", "Chair", "Typewriter", "Tube"]:
			if _node("%s%02d" % [prefix, n]) == null:
				parts_ok = false
	_check(parts_ok, "new game: every desk, chair, typewriter and tube terminal is in the hall (Desks 1 to 12)")

	var clerks_ok := true
	for n in TYPING_DESKS:
		if _node("Clerk%02d" % n) == null:
			clerks_ok = false
	_check(clerks_ok, "new game: all 10 typing clerks are back, Clerk 5 and Clerk 6 included")
	var clerk_map: Dictionary = _main.clerk_world.get("_clerks")
	_check(clerk_map.size() == TYPING_DESKS.size(), "new game: the clerk behaviour registers all 10 typing clerks")
	var clerk5 = _node("Clerk05")
	_check(clerk5 != null and is_equal_approx(clerk5.rotation.y, _built_clerk_yaw),
		"new game: the restored Clerk 5 sits facing north as built")


func _apply_change(id: String) -> bool:
	var change: Dictionary = _un.call("_change", id)
	return bool(_un.call("_apply", change))


func _applied(id: String) -> bool:
	return _row(id).get("applied", false)


func _pending(id: String) -> bool:
	return _row(id).get("pending", false)


func _row(id: String) -> Dictionary:
	for row in _un.status():
		if String(row.id) == id:
			return row
	return {}


func _registry_clear() -> bool:
	var rows: Array = _un.status()
	if rows.size() != 12:
		return false
	for row in rows:
		if bool(row.pending) or bool(row.applied) or bool(row.reverted):
			return false
	return true


func _silhouette():
	var door = _node("SupervisorDoor")
	return door.get_node_or_null("DoorSilhouette") if door != null else null


func _node(node_name: String):
	return _hall.find_child(node_name, true, false) if _hall != null else null


func _pose(node) -> Dictionary:
	if node == null:
		return {}
	return {"position": node.position, "rotation": node.rotation}


func _same_pose(node, pose: Dictionary) -> bool:
	if node == null or pose.is_empty():
		return false
	return node.position.is_equal_approx(pose["position"]) and node.rotation.is_equal_approx(pose["rotation"])
