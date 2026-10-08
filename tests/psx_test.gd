extends Node
## M1 check scene (spec 19, M1): a textured cube on a long textured floor under
## the PS1 pipeline. Dev-only and excluded from export.
##
## Keys: 1 = 320x240, 2 = 640x480 (HIGH setting), 3 = focus view, D = dither.
## Arguments after "--":
##   --res=high  --focus  --dither=off  --wobble=0  --frames=<n>
##   --shot=<png path>   save a screenshot after n frames, then quit
##   --selftest          check the toggles and exit with 0 on success

const FLOOR_TEXTURE := preload("res://assets/textures/floor_lino.png")
const PSX_SPATIAL := preload("res://shaders/psx_spatial.gdshader")

var _pipeline: PsxPipeline
var _cube: MeshInstance3D
var _spin := true
var _focus := false
var _shot_path := ""
var _frames := 30


func _ready() -> void:
	_pipeline = PsxPipeline.new()
	add_child(_pipeline)
	_build_world(_pipeline.world)
	_parse_args()
	if "--selftest" in OS.get_cmdline_user_args():
		_run_selftest()
	elif _shot_path != "":
		_capture()


func _process(delta: float) -> void:
	if _spin:
		_cube.rotation.y += delta * 0.6


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		_on_key(event.keycode)


func _on_key(keycode: Key) -> bool:
	match keycode:
		KEY_1:
			_pipeline.set_high_resolution(false)
		KEY_2:
			_pipeline.set_high_resolution(true)
		KEY_3:
			_focus = not _focus
			_pipeline.set_focus_view(_focus)
		KEY_D:
			_pipeline.set_dither(not _pipeline.is_dither_on())
		_:
			return false
	print("resolution %s, dither %s" % [_pipeline.current_resolution(), _pipeline.is_dither_on()])
	return true


func _build_world(world: Node3D) -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#3A3A34")
	environment.ambient_light_energy = 1.0
	var env_node := WorldEnvironment.new()
	env_node.environment = environment
	world.add_child(env_node)

	var camera := Camera3D.new()
	camera.fov = 60.0
	camera.near = 0.05
	camera.far = 30.0
	world.add_child(camera)
	camera.position = Vector3(0.0, 1.0, 3.0)
	camera.look_at(Vector3(0.0, 0.4, 0.0))
	camera.current = true

	var light := OmniLight3D.new()
	light.light_color = Color("#E8F0E0")
	light.light_energy = 1.2
	light.omni_range = 6.0
	light.omni_attenuation = 1.0
	light.shadow_enabled = false
	light.position = Vector3(1.5, 2.0, 1.5)
	world.add_child(light)

	var box := BoxMesh.new()
	box.size = Vector3.ONE
	_cube = MeshInstance3D.new()
	_cube.mesh = box
	_cube.material_override = _material(FLOOR_TEXTURE, Vector2.ONE)
	_cube.position = Vector3(0.0, 0.5, 0.0)
	_cube.rotation.y = 0.5
	world.add_child(_cube)

	var floor_mesh := PlaneMesh.new()
	floor_mesh.size = Vector2(20.0, 20.0)
	var floor_node := MeshInstance3D.new()
	floor_node.mesh = floor_mesh
	floor_node.material_override = _material(_checker_texture(), Vector2(10.0, 10.0))
	world.add_child(floor_node)


## High-contrast checker for the floor, so the affine (non-perspective) warp
## of the texture is visible. Dev-only, generated in code, not a game asset.
func _checker_texture() -> Texture2D:
	var image := Image.create(64, 64, false, Image.FORMAT_RGB8)
	for y in 64:
		for x in 64:
			var dark := ((x / 16) + (y / 16)) % 2 == 0
			image.set_pixel(x, y, Color("#4E5A48") if dark else Color("#8E8B7B"))
	return ImageTexture.create_from_image(image)


func _material(texture: Texture2D, uv_scale: Vector2) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PSX_SPATIAL
	mat.set_shader_parameter("albedo_tex", texture)
	mat.set_shader_parameter("uv_scale", uv_scale)
	return mat


func _parse_args() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg == "--res=high":
			_pipeline.set_high_resolution(true)
		elif arg == "--focus":
			_focus = true
			_pipeline.set_focus_view(true)
		elif arg == "--dither=off":
			_pipeline.set_dither(false)
		elif arg == "--wobble=0":
			_spin = false
		elif arg.begins_with("--shot="):
			_shot_path = arg.trim_prefix("--shot=")
		elif arg.begins_with("--frames="):
			_frames = int(arg.trim_prefix("--frames="))


func _capture() -> void:
	for i in _frames:
		await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_shot_path)
	print("saved %s (%dx%d), error %d" % [_shot_path, image.get_width(), image.get_height(), err])
	get_tree().quit(err)


func _run_selftest() -> void:
	var failures := 0
	var cases := [
		["starts at 320x240", _pipeline.current_resolution() == Vector2i(320, 240)],
		["snap grid 160x120 at 320x240", _pipeline.snap_grid() == Vector2(160, 120)],
		["dither starts on", _pipeline.is_dither_on()],
	]
	_on_key(KEY_2)
	cases.append(["HIGH setting gives 640x480", _pipeline.current_resolution() == Vector2i(640, 480)])
	cases.append(["snap grid 320x240 at 640x480", _pipeline.snap_grid() == Vector2(320, 240)])
	_on_key(KEY_1)
	cases.append(["key 1 returns to 320x240", _pipeline.current_resolution() == Vector2i(320, 240)])
	_on_key(KEY_3)
	cases.append(["focus view gives 640x480", _pipeline.current_resolution() == Vector2i(640, 480)])
	_on_key(KEY_3)
	cases.append(["leaving focus gives 320x240", _pipeline.current_resolution() == Vector2i(320, 240)])
	_on_key(KEY_D)
	cases.append(["key D turns dither off", not _pipeline.is_dither_on()])
	_on_key(KEY_D)
	cases.append(["key D turns dither back on", _pipeline.is_dither_on()])
	for case in cases:
		print("%s  %s" % ["PASS" if case[1] else "FAIL", case[0]])
		if not case[1]:
			failures += 1
	print("RESULT: %s, %d failure(s)" % ["PASS" if failures == 0 else "FAIL", failures])
	get_tree().quit(failures)
