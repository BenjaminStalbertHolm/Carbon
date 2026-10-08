extends CharacterBody3D
## PlayerController (spec 6.2, 6.4, 12, 16.3): the two body states and mouse look.
##
## SEATED (default): the camera sits at the Desk 4 seated eye (5.25, 1.15, 4.10). Mouse look
## clamps yaw to +-110 degrees from north and pitch to -60..+40. No translation.
## STANDING: Space while seated (the main controller enables input only in free view) raises
## the camera over 0.6 s to 1.62 m, 0.3 m south of the seated position. WASD walks at 1.6 m/s.
## Space within 1.2 m of Desk 4's chair, or a click on the chair (sit_down(true)), sits again:
## the camera moves over 0.8 s to the seated pose, yaw north.
##
## Units are metres and degrees. Pitch is positive up, so a negative pitch looks down.
## The main controller calls set_input_enabled(); it is off in every focus view, in the menu and
## during the day transitions. Tests drive the body through try_space(), look(), sit_down() and
## debug_set_move().

enum { SEATED, RISING, STANDING, SITTING }

const SEAT_ROOT := Vector3(5.25, 0.0, 4.10)
const STAND_ROOT := Vector3(5.25, 0.0, 4.40)
const CHAIR_XZ := Vector2(5.25, 4.05)
const SEAT_EYE_Y := 1.15
const STAND_EYE_Y := 1.62
const RISE_S := 0.6
const SIT_S := 0.8
const WALK_SPEED := 1.6
const SIT_RANGE := 1.2
const RADIUS := 0.25
const HEIGHT := 1.7
const BOB_AMP := 0.02
const BOB_HZ := 1.8
const STEP_S := 0.6
const SEAT_YAW_LIMIT := 110.0
const SEAT_PITCH := Vector2(-60.0, 40.0)
const STAND_PITCH := Vector2(-70.0, 70.0)
const SEAT_PITCH_START := -10.0
const DEG_PER_PIXEL_AT_1 := 0.15
const DEFAULT_SENSITIVITY := 0.6
const RAY_SEATED := 1.6
const RAY_STANDING := 2.0
const FOV := 60.0

signal stood_up
signal sat_down

## Set by the main controller. Look, walk and Space need it.
var input_enabled := false

var _state: int = SEATED
var _t := 0.0
var _yaw := 0.0
var _pitch := SEAT_PITCH_START
var _sit_yaw := 0.0
var _sit_pitch := 0.0
var _camera: Camera3D
var _shape: CollisionShape3D
var _bob_phase := 0.0
var _bob_weight := 0.0
var _step_timer := 0.0
var _step_index := 0
var _debug_move := Vector2.ZERO
var _debug_on := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	var capsule := CapsuleShape3D.new()
	capsule.radius = RADIUS
	capsule.height = HEIGHT
	_shape = CollisionShape3D.new()
	_shape.name = "Capsule"
	_shape.shape = capsule
	_shape.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	_shape.disabled = true
	add_child(_shape)
	_camera = Camera3D.new()
	_camera.name = "Camera"
	_camera.fov = FOV
	_camera.near = 0.05
	_camera.far = 30.0
	add_child(_camera)
	position = SEAT_ROOT
	_camera.position = Vector3(0.0, SEAT_EYE_Y, 0.0)
	_apply_look()
	_camera.make_current()


# --- Queries -------------------------------------------------------------------------

func camera() -> Camera3D:
	return _camera


func is_seated() -> bool:
	return _state == SEATED


func is_standing() -> bool:
	return _state == STANDING


func is_transitioning() -> bool:
	return _state == RISING or _state == SITTING


## Length of the centre-screen ray: 1.6 m seated, 2.0 m standing (spec 6.4).
func ray_length() -> float:
	return RAY_STANDING if _state == STANDING or _state == RISING else RAY_SEATED


func near_chair() -> bool:
	return Vector2(position.x, position.z).distance_to(CHAIR_XZ) <= SIT_RANGE


func yaw_degrees() -> float:
	return _yaw


func pitch_degrees() -> float:
	return _pitch


# --- Control -------------------------------------------------------------------------

func set_input_enabled(on: bool) -> void:
	input_enabled = on
	if not on:
		velocity = Vector3.ZERO


## Space (spec 12): stands up while seated; sits again while standing within 1.2 m of the chair.
func try_space() -> void:
	match _state:
		SEATED:
			_state = RISING
			_t = 0.0
			_shape.disabled = true
		STANDING:
			sit_down(false)


## Sits down while standing. Without force the player must be within 1.2 m of the chair.
## Returns true when the sit started.
func sit_down(force: bool = false) -> bool:
	if _state != STANDING or (not force and not near_chair()):
		return false
	_state = SITTING
	_t = 0.0
	_sit_yaw = _yaw
	_sit_pitch = _pitch
	_shape.disabled = true
	velocity = Vector3.ZERO
	return true


## Puts the body in the seated pose at once: yaw north, pitch -10 (spec 13.1 step 7). Used at the
## start of a day and after a continue.
func reset_seated() -> void:
	_state = SEATED
	_t = 0.0
	_yaw = 0.0
	_pitch = SEAT_PITCH_START
	_debug_on = false
	_shape.disabled = true
	position = SEAT_ROOT
	velocity = Vector3.ZERO
	_camera.position = Vector3(0.0, SEAT_EYE_Y, 0.0)
	_apply_look()


## Mouse look (spec 6.2). rel is the mouse motion in pixels.
func look(rel: Vector2) -> void:
	if _state != SEATED and _state != STANDING:
		return
	var dpp := DEG_PER_PIXEL_AT_1 * _setting_sensitivity()
	var pitch_sign := 1.0 if _setting_invert() else -1.0
	_yaw -= rel.x * dpp
	_pitch += rel.y * dpp * pitch_sign
	if _state == SEATED:
		_yaw = clampf(_yaw, -SEAT_YAW_LIMIT, SEAT_YAW_LIMIT)
		_pitch = clampf(_pitch, SEAT_PITCH.x, SEAT_PITCH.y)
	else:
		_yaw = wrapf(_yaw, -180.0, 180.0)
		_pitch = clampf(_pitch, STAND_PITCH.x, STAND_PITCH.y)
	_apply_look()


## Dev and test hook: sets the look direction (yaw from north, pitch up) within the clamps of
## the current state.
func set_look(yaw: float, pitch: float) -> void:
	if _state != SEATED and _state != STANDING:
		return
	_yaw = wrapf(yaw, -180.0, 180.0)
	_pitch = pitch
	if _state == SEATED:
		_yaw = clampf(_yaw, -SEAT_YAW_LIMIT, SEAT_YAW_LIMIT)
		_pitch = clampf(_pitch, SEAT_PITCH.x, SEAT_PITCH.y)
	else:
		_pitch = clampf(_pitch, STAND_PITCH.x, STAND_PITCH.y)
	_apply_look()


## Test hook: walks with the given direction (x right, y forward, each -1..1) instead of WASD.
func debug_set_move(dir: Vector2) -> void:
	_debug_move = dir
	_debug_on = true


func debug_clear_move() -> void:
	_debug_on = false
	_debug_move = Vector2.ZERO


# --- Motion --------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			look((event as InputEventMouseMotion).relative)
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_SPACE:
			try_space()
			get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	match _state:
		RISING:
			_t += delta
			var e := _ease(_t / RISE_S)
			position = SEAT_ROOT.lerp(STAND_ROOT, e)
			_camera.position.y = lerpf(SEAT_EYE_Y, STAND_EYE_Y, e)
			if _t >= RISE_S:
				_t = 0.0
				_state = STANDING
				_shape.disabled = false
				position = STAND_ROOT
				_camera.position.y = STAND_EYE_Y
				stood_up.emit()
		SITTING:
			_t += delta
			var e := _ease(_t / SIT_S)
			position = STAND_ROOT.lerp(SEAT_ROOT, e)
			_camera.position.y = lerpf(STAND_EYE_Y, SEAT_EYE_Y, e)
			_yaw = lerpf(_sit_yaw, 0.0, e)
			_pitch = lerpf(_sit_pitch, clampf(_sit_pitch, SEAT_PITCH.x, SEAT_PITCH.y), e)
			_apply_look()
			if _t >= SIT_S:
				_t = 0.0
				_state = SEATED
				_yaw = 0.0
				_pitch = clampf(_sit_pitch, SEAT_PITCH.x, SEAT_PITCH.y)
				position = SEAT_ROOT
				_camera.position.y = SEAT_EYE_Y
				_apply_look()
				sat_down.emit()
		STANDING:
			_update_bob(delta)
			_update_steps(delta)
		_:
			pass


func _physics_process(_delta: float) -> void:
	if _state != STANDING or not _is_moving():
		velocity = Vector3.ZERO
		return
	var v := _move_input()
	var heading := Basis(Vector3.UP, deg_to_rad(_yaw))
	velocity = heading * Vector3(v.x, 0.0, -v.y) * WALK_SPEED
	move_and_slide()


func _move_input() -> Vector2:
	if _debug_on:
		return _debug_move
	if not input_enabled:
		return Vector2.ZERO
	var v := Vector2.ZERO
	if Input.is_key_pressed(KEY_D):
		v.x += 1.0
	if Input.is_key_pressed(KEY_A):
		v.x -= 1.0
	if Input.is_key_pressed(KEY_W):
		v.y += 1.0
	if Input.is_key_pressed(KEY_S):
		v.y -= 1.0
	return v.limit_length(1.0)


func _is_moving() -> bool:
	return _state == STANDING and _move_input().length() > 0.01


func _update_bob(delta: float) -> void:
	var moving := _is_moving()
	if moving:
		_bob_phase += delta * TAU * BOB_HZ
	_bob_weight = move_toward(_bob_weight, 1.0 if moving else 0.0, delta * 4.0)
	_camera.position.y = STAND_EYE_Y + BOB_AMP * sin(_bob_phase) * _bob_weight


func _update_steps(delta: float) -> void:
	if not _is_moving():
		_step_timer = 0.0
		return
	_step_timer -= delta
	if _step_timer <= 0.0:
		_step_timer = STEP_S
		_play("footstep_%d" % (_step_index + 1))
		_step_index = 1 - _step_index


func _apply_look() -> void:
	rotation_degrees = Vector3(0.0, _yaw, 0.0)
	_camera.rotation_degrees = Vector3(_pitch, 0.0, 0.0)


func _ease(k: float) -> float:
	var x := clampf(k, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


# --- Services --------------------------------------------------------------------------

func _play(sound: String) -> void:
	var ad = _autoload("AudioDirector")
	if ad != null and ad.has_method("play"):
		ad.play(sound, global_position, false, 0.0, true)


func _setting_sensitivity() -> float:
	var ss = _autoload("SaveSystem")
	if ss != null and ss.has_method("get_setting"):
		var v = ss.get_setting("mouse_sensitivity")
		if v != null:
			return float(v)
	return DEFAULT_SENSITIVITY


func _setting_invert() -> bool:
	var ss = _autoload("SaveSystem")
	if ss != null and ss.has_method("get_setting"):
		return bool(ss.get_setting("invert_mouse_y"))
	return false


func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
