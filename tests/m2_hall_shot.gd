extends Node
## M2 screenshot scene (dev only). Puts Hall C inside a PsxPipeline, shows it from the
## Desk 4 seated eye position looking north, then from the room centre looking
## north-east, and saves a PNG for each view. Run under xvfb-run.
## Arguments after "--": --shot=<png> --shot2=<png> --top=<png> --frames=<n> (default 30).
## --top gives a plan view from above with the ceiling hidden (layout check only).

const Hall := preload("res://scripts/world/hall_c.gd")
const PipelineScript := preload("res://scripts/rendering/psx_pipeline.gd")

const SEATED_EYE := Vector3(5.25, 1.15, 4.10)
const SEATED_TARGET := Vector3(5.25, 1.15, -2.0)
const ROOM_CENTRE := Vector3(0.0, 1.62, 0.0)
const ROOM_TARGET := Vector3(6.0, 1.2, -6.0)

var _pipeline: Node
var _shot := ""
var _shot2 := ""
var _top := ""
var _frames := 30
var _hall: Node


func _ready() -> void:
	_pipeline = PipelineScript.new()
	add_child(_pipeline)
	_hall = Hall.build(_pipeline.world, {})
	_parse_args()
	_run()


func _run() -> void:
	var seated := _camera(SEATED_EYE, SEATED_TARGET)
	seated.current = true
	await _wait(_frames)
	if _shot != "":
		_save(_shot)
	var centre := _camera(ROOM_CENTRE, ROOM_TARGET)
	centre.current = true
	await _wait(_frames)
	if _shot2 != "":
		_save(_shot2)
	if _top != "":
		seated.current = false
		centre.current = false
		(_hall.get_node("Ceiling") as Node3D).visible = false
		var plan := _camera(Vector3(0.0, 12.0, 0.0), Vector3(0.0, 0.0, 0.0), Vector3(0, 0, -1))
		plan.current = true
		await _wait(_frames)
		_save(_top)
	get_tree().quit(0)


func _camera(pos: Vector3, target: Vector3, up: Vector3 = Vector3.UP) -> Camera3D:
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.near = 0.05
	cam.far = 30.0
	_pipeline.world.add_child(cam)
	cam.position = pos
	cam.look_at(target, up)
	return cam


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			_shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--shot2="):
			_shot2 = arg.trim_prefix("--shot2=")
		elif arg.begins_with("--top="):
			_top = arg.trim_prefix("--top=")
		elif arg.begins_with("--frames="):
			_frames = int(arg.trim_prefix("--frames="))


func _wait(count: int) -> void:
	for i in count:
		await RenderingServer.frame_post_draw


func _save(path: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	print("saved %s (%dx%d), error %d" % [path, image.get_width(), image.get_height(), err])
