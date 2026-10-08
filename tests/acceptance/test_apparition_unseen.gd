extends SceneTree
## Acceptance test 8 (spec 20): the unseen rule for the Desk 12 apparition (spec 9.2, 9.3 D3-U1). Day 3 is begun
## through DayDirector and its transcription and RO-3 are sent by the player (so the change becomes pending through
## task_sent:RO-3, as in the game). The real Gaze and UnseenChanges do the rest, with a fake camera:
##   - looking at Desk 12 (in the frustum, within 12 degrees, unblocked) for 60 s: the figure never appears;
##   - looking away: it appears once Desk 12 has been unseen for 1.5 s (spec 9.2), at 3.1 m, out of the frustum;
##   - at 3.1 m it stays, however long it is unseen (the hide rule needs under 3.0 m);
##   - approaching to 2.5 m and looking away: it is gone once unseen for 0.5 s (spec 9.3 D3-U1);
##   - after that it never reappears.
## Gaze and UnseenChanges are stepped by this test at a fixed 1/60 s (their own process callbacks are disabled), so
## the 60 s stare runs at once. The camera and the figure on screen are MANUAL, see tests/ACCEPTANCE.md.
## Headless:
##   godot --headless --path . --script res://tests/acceptance/test_apparition_unseen.gd
## Prints one PASS or FAIL line per check, then "RESULT: PASS, N failure(s)". Exit 0 only when N is 0.

const DebugDays := preload("res://scripts/debug/debug_day_defaults.gd")
const Play := preload("res://tests/acceptance/playthrough_helpers.gd")
const GazeScript := preload("res://scripts/autoload/gaze.gd")
const HallC := preload("res://scripts/world/hall_c.gd")

const DT := 1.0 / 60.0
const CHANGE := "D3-U1"
const FIGURE := "Clerk12"
const STARE_S := 60.0
const APPEAR_UNSEEN_S := 1.5
const HIDE_UNSEEN_S := 0.5
const TOL := 2.0 * DT
## Floor-plane distances to Desk 12 (centre 5.25, -2.5): 3.1 m (far) and 2.5 m (near, under the 3.0 m hide rule).
const FAR := Vector3(5.25, 1.62, -5.6)
const NEAR := Vector3(5.25, 1.62, -5.0)

var _checks := 0
var _failures := 0
var _ran := false
var _gs
var _un
var _gaze
var _hall: Node3D
var _cam: Camera3D
var _desk12: Node3D


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _run() -> void:
	_gs = root.get_node("GameState")
	var dd = root.get_node("DayDirector")
	_un = root.get_node("UnseenChanges")
	_gaze = root.get_node("Gaze")

	var holder := Node3D.new()
	root.add_child(holder)
	_hall = HallC.build(holder, {})
	_un.bind_hall(_hall)
	_desk12 = _hall.find_child("Desk12", true, false)
	_cam = Camera3D.new()
	root.add_child(_cam)
	_gaze.set_camera(_cam)
	# Gaze and the registry run from _run below, at the fixed step, not from the engine's frames.
	_gaze.process_mode = Node.PROCESS_MODE_DISABLED
	_un.process_mode = Node.PROCESS_MODE_DISABLED

	DebugDays.prepare(_gs, dd, 3)
	# T-1 was completed by the debug defaults, which emit no signals. Its task_sent makes the Day 1 chair change
	# (spec 9.3 D1-U1, Chair12 pulled out from under Desk 12) pending, as the game does. The chair is out of the
	# way of the stare only once it has applied, so the chair is brought out now, before RO-3 is sent.
	dd.task_sent.emit("T-1")
	_cam.look_at_from_position(FAR, FAR + Vector3(0.0, 0.0, -1.0), Vector3.UP)
	for i in range(int(round(2.0 / DT))):
		_step()
	_check(bool(_row("D1-U1")["applied"]), "test 8: the Day 1 chair change (D1-U1) applies when Chair 12 has been unseen (spec 9.2)")
	var chair: Node3D = _hall.find_child("Chair12", true, false)
	_check(absf(chair.position.z - (-2.5 + 0.55)) < 0.01, "test 8: Chair 12 stands 0.55 m out from Desk 12 (D1-U1)")
	# A moved collider reaches the physics queries on a physics frame, so the stare's sight line waits for two.
	await physics_frame
	await physics_frame
	# Day 3 through its morning: T-3 arrives at 15 s (the morning at 10 s, then the arrival 5 s later).
	dd.tick(10.0)
	dd.tick(5.0)
	var run := Play.new(_gs, dd)
	run.transcription("ST-3", false)
	dd.tick(5.0)  # RO-3 arrives
	run.order("RO-3", [], "RETURNED")
	_check(bool(_row()["pending"]) and not bool(_row()["applied"]), "test 8: the Desk 12 change is pending once RO-3 is sent (task_sent:RO-3)")
	_check(not _figure_in_tree(), "test 8: no figure at Desk 12 before the change applies")

	# The stare: 60 s looking at Desk 12 from 3.1 m.
	_cam.look_at_from_position(FAR, GazeScript.world_aabb(_desk12).get_center(), Vector3.UP)
	var frames := 0
	var looked := 0
	var figure_frames := 0
	var applied_frames := 0
	for i in range(int(round(STARE_S / DT))):
		_step()
		frames += 1
		if _gaze.is_looked_at(_desk12):
			looked += 1
		if _figure_in_tree():
			figure_frames += 1
		if bool(_row()["applied"]):
			applied_frames += 1
	_check(looked == frames, "test 8: Desk 12 is looked at in every frame of the 60 s stare (%d of %d)" % [looked, frames])
	_check(figure_frames == 0, "test 8: the figure never appears while Desk 12 is looked at (60 s, %d frames)" % frames)
	_check(applied_frames == 0 and bool(_row()["pending"]), "test 8: the change stays pending during the stare")
	_check(is_zero_approx(_gaze.unseen_time(_desk12)), "test 8: Desk 12's unseen time is zero throughout the stare")

	# Look away from 3.1 m: the figure appears once Desk 12 has been unseen for 1.5 s.
	_cam.look_at_from_position(FAR, FAR + Vector3(0.0, 0.0, -1.0), Vector3.UP)
	var appear_unseen := -1.0
	var appear_in_frustum := true
	for i in range(int(round(3.0 / DT))):
		var was_applied := bool(_row()["applied"])
		_step()
		if not was_applied and bool(_row()["applied"]):
			appear_unseen = _gaze.unseen_time(_desk12)
			appear_in_frustum = _gaze.is_in_frustum(_desk12)
			break
	_check(appear_unseen >= APPEAR_UNSEEN_S - 1e-4 and appear_unseen < APPEAR_UNSEEN_S + TOL,
		"test 8: the figure appears when Desk 12 has been unseen for 1.5 s (appeared at %.3f s unseen)" % appear_unseen)
	_check(not appear_in_frustum, "test 8: the figure appears while out of the frustum")
	_check(_figure_in_tree(), "test 8: the figure stands at Desk 12 once the change applies")
	var figure := _hall.find_child(FIGURE, true, false)

	# At 3.1 m the figure stays, however long it is unseen: the hide rule needs under 3.0 m.
	for i in range(int(round(2.0 / DT))):
		_step()
	_check(_figure_in_tree() and not bool(_row()["reverted"]),
		"test 8: at 3.1 m the figure stays while unseen (the hide rule needs under 3.0 m)")
	_check(_gaze.camera_floor_distance(_desk12.global_position) >= 3.0, "test 8: the camera is 3.0 m or more from Desk 12 here")

	# Look at the figure from 3.1 m for a second: it is in the frustum, so its unseen time restarts.
	_cam.look_at_from_position(FAR, GazeScript.world_aabb(figure).get_center(), Vector3.UP)
	for i in range(int(round(1.0 / DT))):
		_step()
	_check(_figure_in_tree() and _gaze.is_in_frustum(figure), "test 8: the figure stays while it is looked at")

	# Turn away from it, then approach to 2.5 m before its unseen time reaches 0.5 s: it goes once that time is reached.
	_cam.look_at_from_position(FAR, FAR + Vector3(0.0, 0.0, -1.0), Vector3.UP)
	for i in range(int(round(0.3 / DT))):
		_step()
	_check(_figure_in_tree(), "test 8: the figure is still there after 0.3 s unseen at 3.1 m")
	_cam.look_at_from_position(NEAR, NEAR + Vector3(0.0, 0.0, -1.0), Vector3.UP)
	var hide_unseen := -1.0
	for i in range(int(round(3.0 / DT))):
		var unseen_before: float = _gaze.unseen_time(figure)
		_step()
		if not _figure_in_tree():
			hide_unseen = unseen_before + DT
			break
	_check(hide_unseen >= HIDE_UNSEEN_S - TOL and hide_unseen < HIDE_UNSEEN_S + TOL,
		"test 8: within 3.0 m and looking away, the figure is gone once unseen for 0.5 s (gone at %.3f s unseen)" % hide_unseen)
	_check(bool(_row()["reverted"]), "test 8: the change is marked reverted (it never reappears)")
	_check(_gaze.camera_floor_distance(_desk12.global_position) < 3.0, "test 8: the camera is under 3.0 m from Desk 12 when the figure goes")

	# It never reappears: a stare from 2.5 m, then a look away from 3.1 m.
	_cam.look_at_from_position(NEAR, GazeScript.world_aabb(_desk12).get_center(), Vector3.UP)
	var back := 0
	for i in range(int(round(5.0 / DT))):
		_step()
		if _figure_in_tree():
			back += 1
	_cam.look_at_from_position(FAR, FAR + Vector3(0.0, 0.0, -1.0), Vector3.UP)
	for i in range(int(round(3.0 / DT))):
		_step()
		if _figure_in_tree():
			back += 1
	_check(back == 0 and not _figure_in_tree(), "test 8: the figure does not reappear after it has gone")

	print("ACCEPTANCE TEST 8 (unseen rule, Desk 12 apparition): %d checks, %d failure(s)" % [_checks, _failures])
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## One fixed step: Gaze's physics pass, then the registry's frame pass (spec 9.1, 9.2).
func _step() -> void:
	_gaze._physics_process(DT)
	_un._process(DT)


func _row(id: String = CHANGE) -> Dictionary:
	for row in _un.status():
		if String(row.id) == id:
			return row
	return {}


func _figure_in_tree() -> bool:
	var fig := _hall.find_child(FIGURE, true, false)
	return fig != null and fig.is_inside_tree()
