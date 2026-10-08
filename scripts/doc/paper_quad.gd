extends RefCounted
## PaperQuad: a 3D paper quad showing a rendered document page (spec 5.4, 6.5).
## The quad is 0.21 x 0.297 m, faces +Z, and uses psx_spatial.gdshader with the
## page texture as albedo_tex. The desk code places and tilts it. The texture
## comes from DocRenderer.page_texture(); after the document changes, call
## set_texture() with the new one.

const PSX_SHADER := preload("res://shaders/psx_spatial.gdshader")
const SIZE := Vector2(0.21, 0.297)


## A MeshInstance3D holding the page texture. size is in metres.
static func make(texture: Texture2D, size: Vector2 = SIZE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = size
	mi.mesh = quad
	mi.material_override = _material(texture)
	return mi


## Swaps the texture of a quad made by make().
static func set_texture(mi: MeshInstance3D, texture: Texture2D) -> void:
	var mat := mi.material_override as ShaderMaterial
	if mat == null:
		mi.material_override = _material(texture)
		return
	mat.set_shader_parameter("albedo_tex", texture)


static func _material(texture: Texture2D) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PSX_SHADER
	mat.set_shader_parameter("albedo_tex", texture)
	mat.set_shader_parameter("albedo_color", Color.WHITE)
	mat.set_shader_parameter("uv_scale", Vector2.ONE)
	mat.set_shader_parameter("emission_strength", 0.0)
	return mat
