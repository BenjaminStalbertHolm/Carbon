class_name PsxPipeline
extends Node
## Renders the 3D world into a SubViewport at PS1 resolution and shows it with
## the colour post shader (spec 4.1 and 4.3). Put 3D content under `world`.
##
## Resolution: 320x240 normally. Focus views (spec 6.3) and the HIGH setting
## (spec 16.3) use 640x480. The SubViewport texture is shown at the largest
## integer scale that fits, centred with black bars. If no integer scale of
## at least 1 fits, it is scaled to fit and keeps 4:3.

const LOW_RES := Vector2i(320, 240)
const HIGH_RES := Vector2i(640, 480)
const POST_SHADER := preload("res://shaders/psx_post.gdshader")

## 3D content lives here and renders inside the SubViewport.
var world: Node3D

var _viewport: SubViewport
var _present: TextureRect
var _post: ShaderMaterial
var _high_setting := false
var _focus_view := false
var _resolution := Vector2i.ZERO
var _snap_grid := Vector2.ZERO


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.msaa_3d = Viewport.MSAA_DISABLED
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	_viewport.use_debanding = false
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	world = Node3D.new()
	_viewport.add_child(world)

	_post = ShaderMaterial.new()
	_post.shader = POST_SHADER
	_present = TextureRect.new()
	_present.texture = _viewport.get_texture()
	_present.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_present.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_present.stretch_mode = TextureRect.STRETCH_SCALE
	_present.material = _post
	var layer := CanvasLayer.new()
	add_child(layer)
	layer.add_child(_present)

	get_viewport().size_changed.connect(_layout)
	set_dither(true)
	_apply_resolution()


func set_focus_view(active: bool) -> void:
	_focus_view = active
	_apply_resolution()


func set_high_resolution(enabled: bool) -> void:
	_high_setting = enabled
	_apply_resolution()


func set_dither(enabled: bool) -> void:
	_post.set_shader_parameter("dither_on", enabled)


func is_dither_on() -> bool:
	return _post.get_shader_parameter("dither_on")


func current_resolution() -> Vector2i:
	return _resolution


func snap_grid() -> Vector2:
	return _snap_grid


func _apply_resolution() -> void:
	var target := HIGH_RES if (_focus_view or _high_setting) else LOW_RES
	if target == _resolution:
		return
	_resolution = target
	_viewport.size = target
	_snap_grid = Vector2(target) * 0.5
	RenderingServer.global_shader_parameter_set("psx_snap_grid", _snap_grid)
	_post.set_shader_parameter("internal_res", Vector2(target))
	_layout()


func _layout() -> void:
	var window := get_viewport().get_visible_rect().size
	var internal := Vector2(_resolution)
	var fit := minf(window.x / internal.x, window.y / internal.y)
	var factor := floorf(fit) if fit >= 1.0 else fit
	var size := (internal * factor).floor()
	_present.size = size
	_present.position = ((window - size) * 0.5).floor()


## A SubViewport does not get window input by itself, so the 3D world (the player's keys and mouse
## look, in particular) would never see it. Keys and mouse events the window did not consume are
## pushed into the viewport here. Mouse positions are mapped from the window to the internal
## resolution; relative motion stays in window pixels, as the look code expects.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey or event is InputEventMouse):
		return
	var pushed := event.duplicate() as InputEvent
	if pushed is InputEventMouse:
		var mouse := pushed as InputEventMouse
		mouse.position = _to_internal(mouse.position)
		mouse.global_position = mouse.position
	_viewport.push_input(pushed)


func _to_internal(window_pos: Vector2) -> Vector2:
	var rect := _present.get_global_rect()
	if rect.size.x <= 0.0 or rect.size.y <= 0.0:
		return window_pos
	return (window_pos - rect.position) / rect.size * Vector2(_resolution)
