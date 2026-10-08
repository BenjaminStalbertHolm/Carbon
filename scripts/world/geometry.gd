extends RefCounted
## Primitive builders for Hall C (spec 5.3 and 4.2). Meshes are ArrayMesh built in
## code (boxes, cylinders, discs, quads, a half-cylinder shell) or a SphereMesh.
## Every surface uses psx_spatial.gdshader through a ShaderMaterial, except frosted glass,
## which uses psx_spatial_glass.gdshader (alpha blend, QUESTION-45). Every textured surface
## has an albedo colour of white, so the texture shows its own palette colour (spec 5.7).
## Static functions only; this file keeps no state.

const PSX_SPATIAL := preload("res://shaders/psx_spatial.gdshader")
const PSX_SPATIAL_GLASS := preload("res://shaders/psx_spatial_glass.gdshader")
const TEX_WHITE := preload("res://assets/textures/white4.png")
const TEX_FLOOR := preload("res://assets/textures/floor_lino.png")
const TEX_WALL_UPPER := preload("res://assets/textures/wall_upper.png")
const TEX_WALL_LOWER := preload("res://assets/textures/wall_lower.png")
const TEX_CEILING := preload("res://assets/textures/ceiling_tile.png")
const TEX_DESK_TOP := preload("res://assets/textures/desk_top.png")
const TEX_STEEL := preload("res://assets/textures/steel.png")
const TEX_WOOD := preload("res://assets/textures/wood.png")
const TEX_PAPER := preload("res://assets/textures/paper.png")
const TEX_ONIONSKIN := preload("res://assets/textures/onionskin.png")
const TEX_FROSTED := preload("res://assets/textures/frosted.png")
const TEX_CHALK := preload("res://assets/textures/chalk_board.png")

const WHITE := Color(1.0, 1.0, 1.0, 1.0)


## Shader material for one surface. Uniforms per spec 4.2. glass selects the alpha-blended
## frosted glass variant (spec 5.2, QUESTION-45). Its alpha is the colour's alpha times the
## texture's alpha, so a glass colour keeps alpha 1 and the frosted texture (alpha 178, 0.7)
## sets the transmission.
static func material(tex: Texture2D, colour: Color = WHITE, emission: float = 0.0, glass: bool = false) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PSX_SPATIAL_GLASS if glass else PSX_SPATIAL
	mat.set_shader_parameter("albedo_tex", tex)
	mat.set_shader_parameter("albedo_color", colour)
	mat.set_shader_parameter("uv_scale", Vector2.ONE)
	mat.set_shader_parameter("emission_strength", emission)
	return mat


## Flat colour surface: the 4x4 white texture tinted by the colour (spec 5.3).
static func flat(colour: Color, emission: float = 0.0) -> ShaderMaterial:
	return material(TEX_WHITE, colour, emission)


static func instance(mesh: Mesh, mat: Material, node_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	mi.material_override = mat
	return mi


## Axis-aligned box centred on the origin. UVs run in metres divided by `tile`, so
## textures tile at the spec's scale on every face.
static func box(size: Vector3, tex: Texture2D, colour: Color = WHITE, tile: float = 1.0, node_name: String = "Box") -> MeshInstance3D:
	return instance(_box_mesh(size, tile), material(tex, colour), node_name)


## Flat colour box.
static func solid(size: Vector3, colour: Color, node_name: String = "Box") -> MeshInstance3D:
	return instance(_box_mesh(size, 1.0), flat(colour), node_name)


## Quad in the XY plane, facing +Z. tile <= 0 maps the whole texture once. glass makes it a
## frosted glass quad (alpha blend, see material).
static func quad(width: float, height: float, tex: Texture2D, colour: Color = WHITE, tile: float = 0.0, emission: float = 0.0, node_name: String = "Quad", glass: bool = false) -> MeshInstance3D:
	return instance(_quad_mesh(width, height, tile), material(tex, colour, emission, glass), node_name)


## Flat disc in the XY plane, facing +Z. The texture covers the square around the disc.
static func disc(radius: float, segments: int, tex: Texture2D, colour: Color = WHITE, node_name: String = "Disc") -> MeshInstance3D:
	return instance(_disc_mesh(radius, segments), material(tex, colour), node_name)


## Cylinder along Y centred on the origin, CylinderMesh-style with a radial segment
## count of at most 8 (spec 5.3). side_uv and cap_uv are UV rectangles in texture
## space. A zero-size side_uv gives one constant texel.
static func cylinder(radius: float, height: float, segments: int, colour: Color = WHITE, node_name: String = "Cylinder", caps_top: bool = true, caps_bottom: bool = true, tex: Texture2D = TEX_WHITE, side_uv: Rect2 = Rect2(0, 0, 1, 1), cap_uv: Rect2 = Rect2(0, 0, 1, 1)) -> MeshInstance3D:
	return instance(_cylinder_mesh(radius, height, segments, caps_top, caps_bottom, side_uv, cap_uv), material(tex, colour), node_name)


## Sphere with 8 radial segments and 6 rings (spec 5.4), generated in code.
static func sphere(radius: float, colour: Color, node_name: String = "Sphere") -> MeshInstance3D:
	return instance(_sphere_mesh(radius, 8, 6), flat(colour), node_name)


## Upper half of a cylinder along X (a lamp shade). Open at both ends and at the
## rim, which sits on the axis, so the dome faces up and outward.
static func half_shell(radius: float, length: float, segments: int, colour: Color, node_name: String = "Shell") -> MeshInstance3D:
	return instance(_half_shell_mesh(radius, length, segments), flat(colour), node_name)


## Static collision body with one box shape, centred at pos (spec 6.1).
static func static_box(size: Vector3, pos: Vector3, node_name: String = "Collision") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = pos
	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)
	return body


## Empty positioned Node3D used as a named parent.
static func group(parent: Node, node_name: String, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = node_name
	node.position = pos
	node.rotation_degrees = rot_deg
	parent.add_child(node)
	return node


## Positions a node (local to its parent) and adds it. Returns the node.
static func add(parent: Node, node: Node3D, pos: Vector3 = Vector3.ZERO, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	node.position = pos
	node.rotation_degrees = rot_deg
	parent.add_child(node)
	return node


## Orients a box whose long axis is Y so that axis points along dir (unit vector).
static func basis_along(dir: Vector3) -> Basis:
	var x := dir.cross(Vector3.UP)
	if x.length() < 0.001:
		x = dir.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(dir).normalized()
	return Basis(x, dir, z)


## Triangle count of a mesh: index count / 3 when indexed, else vertex count / 3.
## Primitive meshes are counted from their arrays, which works without a renderer.
static func triangle_count(mesh: Mesh) -> int:
	var total := 0
	if mesh is ArrayMesh:
		for s in mesh.get_surface_count():
			var verts: int = mesh.surface_get_array_len(s)
			var idx: int = (mesh as ArrayMesh).surface_get_array_index_len(s)
			total += (idx if idx > 0 else verts) / 3
	elif mesh is PrimitiveMesh:
		var arrays: Array = (mesh as PrimitiveMesh).get_mesh_arrays()
		var index = arrays[Mesh.ARRAY_INDEX]
		var verts_arr: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		total += (index.size() if index != null else verts_arr.size()) / 3
	return total


# ---- mesh generation -------------------------------------------------------

## Godot treats clockwise triangles as front faces (checked against PlaneMesh), so a
## triangle is front-facing when cross(b - a, c - a) points against its normal.
static func _put(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2) -> void:
	st.set_normal(n)
	st.set_uv(uv)
	st.add_vertex(p)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	if (b - a).cross(c - a).dot(n) > 0.0:
		_put(st, a, n, ua)
		_put(st, c, n, uc)
		_put(st, b, n, ub)
	else:
		_put(st, a, n, ua)
		_put(st, b, n, ub)
		_put(st, c, n, uc)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, ua: Vector2, ub: Vector2, uc: Vector2, ud: Vector2) -> void:
	_tri(st, a, b, c, n, ua, ub, uc)
	_tri(st, a, c, d, n, ua, uc, ud)


static func _box_mesh(size: Vector3, tile: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := size * 0.5
	for axis in 3:
		var au := (axis + 1) % 3
		var av := (axis + 2) % 3
		for s in [-1.0, 1.0]:
			var n := Vector3.ZERO
			n[axis] = s
			var eu := Vector3.ZERO
			eu[au] = half[au]
			var ev := Vector3.ZERO
			ev[av] = half[av]
			var centre: Vector3 = n * half[axis]
			var p0: Vector3 = centre - eu - ev
			var p1: Vector3 = centre + eu - ev
			var p2: Vector3 = centre + eu + ev
			var p3: Vector3 = centre - eu + ev
			_quad(st, p0, p1, p2, p3, n,
				_face_uv(p0, au, av, tile), _face_uv(p1, au, av, tile),
				_face_uv(p2, au, av, tile), _face_uv(p3, au, av, tile))
	return st.commit()


static func _face_uv(p: Vector3, au: int, av: int, tile: float) -> Vector2:
	return Vector2(p[au], p[av]) / tile


static func _quad_mesh(width: float, height: float, tile: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hw := width * 0.5
	var hh := height * 0.5
	var a := Vector3(-hw, -hh, 0.0)
	var b := Vector3(hw, -hh, 0.0)
	var c := Vector3(hw, hh, 0.0)
	var d := Vector3(-hw, hh, 0.0)
	var du := tile if tile > 0.0 else width
	var dv := tile if tile > 0.0 else height
	_quad(st, a, b, c, d, Vector3.BACK,
		_quad_uv(a, hw, hh, du, dv), _quad_uv(b, hw, hh, du, dv),
		_quad_uv(c, hw, hh, du, dv), _quad_uv(d, hw, hh, du, dv))
	return st.commit()


static func _quad_uv(p: Vector3, hw: float, hh: float, du: float, dv: float) -> Vector2:
	return Vector2((p.x + hw) / du, (hh - p.y) / dv)


static func _disc_mesh(radius: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := Vector3.BACK
	var centre := Vector3.ZERO
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := Vector3(cos(a0) * radius, sin(a0) * radius, 0.0)
		var p1 := Vector3(cos(a1) * radius, sin(a1) * radius, 0.0)
		_tri(st, centre, p0, p1, n, _square_uv(centre, radius), _square_uv(p0, radius), _square_uv(p1, radius))
	return st.commit()


## Maps a point on a disc of this radius onto the square texture around it.
static func _square_uv(p: Vector3, radius: float) -> Vector2:
	return Vector2(0.5 + 0.5 * p.x / radius, 0.5 - 0.5 * p.y / radius)


static func _cap_uv(d: Vector3, cap: Rect2) -> Vector2:
	return Vector2(cap.position.x + cap.size.x * (0.5 + 0.5 * d.x), cap.position.y + cap.size.y * (0.5 + 0.5 * d.z))


static func _cylinder_mesh(radius: float, height: float, segments: int, caps_top: bool, caps_bottom: bool, side_uv: Rect2, cap_uv: Rect2) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := height * 0.5
	var top_c := Vector3(0.0, half, 0.0)
	var bot_c := Vector3(0.0, -half, 0.0)
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var d0 := Vector3(cos(a0), 0.0, sin(a0))
		var d1 := Vector3(cos(a1), 0.0, sin(a1))
		var n := (d0 + d1).normalized()
		var b0 := d0 * radius + Vector3(0.0, -half, 0.0)
		var b1 := d1 * radius + Vector3(0.0, -half, 0.0)
		var t0 := d0 * radius + Vector3(0.0, half, 0.0)
		var t1 := d1 * radius + Vector3(0.0, half, 0.0)
		var u0 := side_uv.position.x + side_uv.size.x * float(i) / float(segments)
		var u1 := side_uv.position.x + side_uv.size.x * float(i + 1) / float(segments)
		var vb := side_uv.position.y + side_uv.size.y
		var vt := side_uv.position.y
		_quad(st, b0, b1, t1, t0, n, Vector2(u0, vb), Vector2(u1, vb), Vector2(u1, vt), Vector2(u0, vt))
		if caps_top:
			_tri(st, top_c, t0, t1, Vector3.UP, _cap_uv(Vector3.ZERO, cap_uv), _cap_uv(d0, cap_uv), _cap_uv(d1, cap_uv))
		if caps_bottom:
			_tri(st, bot_c, b1, b0, Vector3.DOWN, _cap_uv(Vector3.ZERO, cap_uv), _cap_uv(d1, cap_uv), _cap_uv(d0, cap_uv))
	return st.commit()


static func _half_shell_mesh(radius: float, length: float, segments: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hl := length * 0.5
	for i in segments:
		var t0 := -PI * 0.5 + PI * float(i) / float(segments)
		var t1 := -PI * 0.5 + PI * float(i + 1) / float(segments)
		var tm := (t0 + t1) * 0.5
		var n := Vector3(0.0, cos(tm), sin(tm))
		var pa := Vector3(-hl, radius * cos(t0), radius * sin(t0))
		var pb := Vector3(hl, radius * cos(t0), radius * sin(t0))
		var pc := Vector3(hl, radius * cos(t1), radius * sin(t1))
		var pd := Vector3(-hl, radius * cos(t1), radius * sin(t1))
		var fi := float(i) / float(segments)
		var fj := float(i + 1) / float(segments)
		_quad(st, pa, pb, pc, pd, n, Vector2(fi, 0.0), Vector2(fi, 1.0), Vector2(fj, 1.0), Vector2(fj, 0.0))
	return st.commit()


static func _sphere_mesh(radius: float, radial: int, rings: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for lat in rings:
		var p0 := PI * float(lat) / float(rings)
		var p1 := PI * float(lat + 1) / float(rings)
		for lon in radial:
			var t0 := TAU * float(lon) / float(radial)
			var t1 := TAU * float(lon + 1) / float(radial)
			var a := _sphere_point(radius, p0, t0)
			var b := _sphere_point(radius, p1, t0)
			var c := _sphere_point(radius, p1, t1)
			var d := _sphere_point(radius, p0, t1)
			var n := ((a + b + c + d) * 0.25).normalized()
			_quad(st, a, b, c, d, n,
				Vector2(t0 / TAU, p0 / PI), Vector2(t0 / TAU, p1 / PI),
				Vector2(t1 / TAU, p1 / PI), Vector2(t1 / TAU, p0 / PI))
	return st.commit()


static func _sphere_point(radius: float, phi: float, theta: float) -> Vector3:
	return Vector3(radius * sin(phi) * cos(theta), radius * cos(phi), radius * sin(phi) * sin(theta))
