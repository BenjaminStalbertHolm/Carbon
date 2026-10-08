extends Node
## M8 dev-only screenshot harness (spec 20 tests 8 and 9, spec 19 M8). Builds Hall C under
## the PS1 pipeline, places the camera at the Desk 4 seated eye position facing north, and
## saves three PNGs:
##   m8_1_day1.png        Day 1 start
##   m8_2a_apparition_seated.png  seated view: Desk 8's clerk hides the Desk 12 figure
##   m8_2_apparition.png  Day 3 after RO-3: the Desk 12 figure from a standing view, after the player looked away 2.5 s
##   m8_3_unison.png      Day 3 after F-3: unison typing clerks, looked at from Desk 4
## Dev-only and excluded from export (tests/*). The one-shot task_sent calls run on the
## first frame of their stage, not inside a time window.
## Run: xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . res://tests/world/m8_shots.tscn -- --out=<dir>

const PsxPipeline := preload("res://scripts/rendering/psx_pipeline.gd")
const HallC := preload("res://scripts/world/hall_c.gd")
const ClerkBehaviour := preload("res://scripts/world/clerk_behaviour.gd")
const ClockBehaviour := preload("res://scripts/world/clock_behaviour.gd")

const EYE := Vector3(5.25, 1.15, 4.10)
const DESK12 := Vector3(5.25, 1.00, -2.50)
const AWAY := Vector3(5.25, 1.15, 12.0)
## Standing position behind Desk 4, looking over the typewriter at the clerk rows.
const STAND := Vector3(5.25, 1.55, 2.4)
const CLERK_ROWS := Vector3(3.0, 0.95, -2.0)
const NORTH := Vector3(5.25, 1.15, -6.0)
const LOOK_AWAY_S := 2.5
## Standing view over the Desk 8 clerk's head, so the Desk 12 figure is not hidden.
const APP_STAND := Vector3(5.25, 1.90, 3.00)

var _out_dir := "/tmp"
var _pipeline = null
var _hall = null
var _camera: Camera3D = null
var _clerk = null
var _clock = null
var _gs = null
var _un = null
var _stage := 0
var _t := 0.0
var _entered_stage := -1
var _log: Array = []
var _checks_run := 0
var _checks_failed := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	_gs = get_node("/root/GameState")
	_un = get_node("/root/UnseenChanges")
	_gs.new_game(4242)
	_pipeline = PsxPipeline.new()
	add_child(_pipeline)
	_hall = HallC.build(_pipeline.world, {})
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.near = 0.05
	_camera.far = 40.0
	_pipeline.world.add_child(_camera)
	_camera.current = true
	_clerk = ClerkBehaviour.new()
	add_child(_clerk)
	_clerk.setup(_hall)
	_clock = ClockBehaviour.new()
	add_child(_clock)
	_clock.setup(_hall)
	_un.bind_hall(_hall)
	get_node("/root/Gaze").set_camera(_camera)
	_look(NORTH)


func _look(target: Vector3) -> void:
	_camera.global_position = EYE
	_camera.look_at(target, Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	match _stage:
		0:
			if _t >= 1.0:
				_shot("m8_1_day1.png")
				_log.append("day1: clock_time=%s" % _gs.clock_time)
				_next(1)
		1:
			if _once():
				_gs.day = 3
				_un._on_task_sent("RO-3")
				_log.append("RO-3 sent: %s" % str(_status("D3-U1")))
			_look(AWAY)
			if _t >= LOOK_AWAY_S:
				_look(DESK12)
				_next(2)
		2:
			if _t >= 0.6:
				_shot("m8_2a_apparition_seated.png")
				_camera.global_position = APP_STAND
				_camera.look_at(DESK12, Vector3.UP)
				_next(25)
		25:
			if _t >= 0.6:
				_shot("m8_2_apparition.png")
				_log.append("apparition: %s" % str(_status("D3-U1")))
				_next(3)
		3:
			if _once():
				_un._on_task_sent("F-3")
				_log.append("F-3 sent: %s" % str(_status("D3-U2")))
			_look(AWAY)
			if _t >= LOOK_AWAY_S:
				_look(NORTH)
				_next(4)
		4:
			if _once():
				_camera.global_position = STAND
				_camera.look_at(CLERK_ROWS, Vector3.UP)
			if _t >= 1.2:
				_shot("m8_3_unison.png")
				_log.append("unison: %s flag=%s any_clerk_looked=%s" % [str(_status("D3-U2")), str(_gs.flags.get("unison_typing", false)), str(_any_looked())])
				_checks()
				for l in _log:
					print("M8SHOTS: ", l)
				get_tree().quit(0)


## True once per stage: the first frame that asks for it.
func _once() -> bool:
	if _entered_stage == _stage:
		return false
	_entered_stage = _stage
	return true


func _next(s: int) -> void:
	_stage = s
	_t = 0.0


func _status(id: String) -> Dictionary:
	for row in _un.status():
		if String(row.id) == id:
			return row
	return {}


## Extra checks for the changes the stills do not show. Each prints PASS or FAIL.
func _checks() -> void:
	# Nameplate rewrite (D4-U1 style) keeps GameState and the visual in step.
	_un.set_nameplate_visual(4, "TEST")
	_check("nameplate rebuilt once", _hall.get_node("Desk04").get_children().filter(func(c): return c.name == "Nameplate").size() == 1)
	# D1-U1 chair: pulled out to 0.55 m and yawed 30 degrees.
	_un._op_d1_u1({})
	var chair = _hall.get_node("Chair12")
	_check("D1-U1 chair offset 0.55 m", is_equal_approx(chair.position.z - (-2.5), 0.55))
	_check("D1-U1 chair yaw 30 degrees", is_equal_approx(chair.rotation_degrees.y, 30.0))
	# D2-U2 clock override: hour hand shows 03:10 (hour angle 95 degrees).
	_gs.flags["clock_override"] = "03:10"
	_clock._process(0.05)
	_check("D2-U2 hour hand shows 03:10", is_equal_approx(fposmod(-_hall.get_node("ClockHourHand").rotation_degrees.z, 360.0), _clock_angle("03:10")))
	_gs.flags["clock_override"] = ""
	_clock._process(0.05)
	_check("D2-U2 revert returns the hour hand to the correct time", is_equal_approx(fposmod(-_hall.get_node("ClockHourHand").rotation_degrees.z, 360.0), fposmod(float(_clock_angle(_gs.clock_time)), 360.0)))
	# D4-U2 silhouette: exists under the supervisor door, flat, 0.05 m behind the glass plane.
	_un._op_d4_u2({})
	var sil = _hall.get_node("SupervisorDoor").get_node_or_null("DoorSilhouette")
	_check("D4-U2 silhouette added under the supervisor door", sil != null and sil.mesh != null)
	if sil != null:
		var aabb: AABB = sil.mesh.get_aabb()
		_check("D4-U2 silhouette fits a 0.45 x 0.95 m quad", is_equal_approx(aabb.size.x, 0.45) and is_equal_approx(aabb.size.y, 0.95))
	# Unison: every typing clerk shows the same hand pose.
	var poses := []
	for d in [1, 2, 3, 5, 6, 7, 8, 9, 10, 11]:
		var c = _hall.get_node_or_null("Clerk%02d" % d)
		if c != null:
			poses.append(snappedf(c.get_node("HandL").position.y, 0.0001))
	var same := true
	for p in poses:
		same = same and is_equal_approx(p, poses[0])
	_check("unison: all typing clerks share one hand pose", same and poses.size() == 10)
	_log.append("CHECKS: %d run, %d failed" % [_checks_run, _checks_failed])


func _clock_angle(hhmm: String) -> float:
	var parts := hhmm.split(":")
	var h := int(parts[0]) % 12
	var m := int(parts[1])
	return (float(h) + float(m) / 60.0) * 30.0


func _check(label: String, ok: bool) -> void:
	_checks_run += 1
	if not ok:
		_checks_failed += 1
	_log.append("%s  %s" % ["PASS" if ok else "FAIL", label])


func _any_looked() -> bool:
	var gaze = get_node("/root/Gaze")
	for n in range(1, 12):
		var c = _hall.get_node_or_null("Clerk%02d" % n)
		if c != null and gaze.is_looked_at(c):
			return true
	return false


func _shot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_out_dir.path_join(file_name))
	_log.append("saved %s err=%d" % [file_name, err])
