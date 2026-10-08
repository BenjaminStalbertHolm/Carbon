extends Node
## M8 dev-only screenshot harness (spec 20 tests 8 and 9, spec 19 M8). Builds Hall C under
## the PS1 pipeline, places the camera at the Desk 4 seated eye position facing north, and
## saves three PNGs:
##   m8_1_day1.png       Day 1 start
##   m8_2_apparition.png Day 3 after RO-3: the Desk 12 figure, after the player looked away 1.5 s
##   m8_3_unison.png     Day 3 after F-3: unison typing clerks, looked at from Desk 4
## Dev-only and excluded from export (tests/*).
## Run: xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . res://tests/world/m8_shots.tscn -- --out=<dir>

const PsxPipeline := preload("res://scripts/rendering/psx_pipeline.gd")
const HallC := preload("res://scripts/world/hall_c.gd")
const ClerkBehaviour := preload("res://scripts/world/clerk_behaviour.gd")
const ClockBehaviour := preload("res://scripts/world/clock_behaviour.gd")

const EYE := Vector3(5.25, 1.15, 4.10)
const DESK12 := Vector3(5.25, 1.00, -2.50)
const AWAY := Vector3(5.25, 1.15, 12.0)
const NORTH := Vector3(0.0, 1.00, -6.0)

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
var _log: Array = []


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
	_add_camera(_pipeline.world)
	_clerk = ClerkBehaviour.new()
	add_child(_clerk)
	_clerk.setup(_hall)
	_clock = ClockBehaviour.new()
	add_child(_clock)
	_clock.setup(_hall)
	_un.bind_hall(_hall)
	get_node("/root/Gaze").set_camera(_camera)
	_look(NORTH)


func _add_camera(world: Node3D) -> void:
	_camera = Camera3D.new()
	_camera.fov = 60.0
	_camera.near = 0.05
	_camera.far = 40.0
	world.add_child(_camera)
	_camera.global_position = EYE
	_camera.current = true


func _look(target: Vector3) -> void:
	_camera.global_position = EYE
	_camera.look_at(target, Vector3.UP)


func _process(delta: float) -> void:
	_t += delta
	match _stage:
		0:
			if _t >= 1.0:
				_shot("m8_1_day1.png")
				_log.append("day1: clock=%s hands=%s" % [_gs.clock_time, str(_hall.get_node("ClockHourHand").rotation_degrees.z)])
				_begin_stage(1)
		1:
			# Day 3 after RO-3: the player looks away (south, wall behind) for 2.0 s.
			_look(AWAY)
			if _t == 0.0 or _t < 0.1:
				_gs.day = 3
				_un._on_task_sent("RO-3")
			if _t >= 2.5:
				_look(DESK12)
				_begin_stage(2)
		2:
			if _t >= 0.6:
				_shot("m8_2_apparition.png")
				_log.append("apparition: %s" % str(_status("D3-U1")))
				_begin_stage(3)
		3:
			_look(AWAY)
			if _t < 0.1:
				_un._on_task_sent("F-3")
			if _t >= 2.5:
				_look(NORTH)
				_begin_stage(4)
		4:
			if _t >= 1.2:
				_shot("m8_3_unison.png")
				_log.append("unison: %s" % str(_status("D3-U2")))
				_log.append("unison flag=%s clerk-freeze(any clerk looked)=%s" % [str(_gs.flags.get("unison_typing", false)), _any_looked()])
				for l in _log:
					print("M8SHOTS: ", l)
				get_tree().quit(0)


func _begin_stage(s: int) -> void:
	_stage = s
	_t = 0.0


func _status(id: String) -> Dictionary:
	for row in _un.status():
		if String(row.id) == id:
			return row
	return {}


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
