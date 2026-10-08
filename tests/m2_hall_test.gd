extends SceneTree
## M2 gate (spec 19, M2): builds Hall C headless, checks the layout and object
## coordinates against the spec numbers, and prints the visible triangle count.
## Run: godot --headless --path /home/user/Carbon --script res://tests/m2_hall_test.gd
## Exit code 0 when every check passes, 1 otherwise.

const Hall := preload("res://scripts/world/hall_c.gd")
const Geo := preload("res://scripts/world/geometry.gd")

const EPS := 0.0005
const DESK_CENTRES := {
	1: Vector3(-5.25, 0.0, 3.5), 2: Vector3(-1.75, 0.0, 3.5), 3: Vector3(1.75, 0.0, 3.5), 4: Vector3(5.25, 0.0, 3.5),
	5: Vector3(-5.25, 0.0, 0.5), 6: Vector3(-1.75, 0.0, 0.5), 7: Vector3(1.75, 0.0, 0.5), 8: Vector3(5.25, 0.0, 0.5),
	9: Vector3(-5.25, 0.0, -2.5), 10: Vector3(-1.75, 0.0, -2.5), 11: Vector3(1.75, 0.0, -2.5), 12: Vector3(5.25, 0.0, -2.5),
}
const FIXTURE_XZ := [
	Vector2(-3.5, 3.5), Vector2(3.5, 3.5), Vector2(-3.5, 0.5),
	Vector2(3.5, 0.5), Vector2(-3.5, -2.5), Vector2(3.5, -2.5),
]
const DESK4_ITEMS := [
	"InboxTray", "ReadStack", "Copyholder", "BlankTray", "BlankStack", "CarbonSpot",
	"StampRack", "InkPad", "Marker", "CorrectionBottle", "CorrectionCap", "Lamp",
	"Notebook", "FiledCarbons",
]

var _checks := 0
var _failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var holder := Node3D.new()
	holder.name = "TestHolder"
	get_root().add_child(holder)
	var hall: Node = Hall.build(holder, {})
	_check_desks(hall)
	_check_chairs(hall)
	_check_typewriters_and_tubes(hall)
	_check_desk4(hall)
	_check_clerks(hall)
	_check_lighting(hall)
	_check_room(hall)
	_check_doorways(hall)
	_check_clock_and_boards(hall)
	var tris := _count_triangles(hall)
	print("TRIANGLES: %d" % tris)
	_expect(tris <= 20000, "triangle budget <= 20000 (got %d)" % tris)
	_check_facing(hall)
	print("RESULT: %s, %d check(s), %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _checks, _failures])
	quit(0 if _failures == 0 else 1)


func _expect(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


func _near(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps


func _vnear(a: Vector3, b: Vector3, eps: float = EPS) -> bool:
	return a.distance_to(b) <= eps


func _top_y(mi: MeshInstance3D) -> float:
	return (mi.global_transform * mi.get_aabb()).end.y


func _bottom_y(mi: MeshInstance3D) -> float:
	return (mi.global_transform * mi.get_aabb()).position.y


func _check_desks(hall: Node) -> void:
	for n in range(1, 13):
		var desk := hall.get_node_or_null("Desk%02d" % n) as Node3D
		_expect(desk != null, "Desk%02d exists" % n)
		if desk == null:
			continue
		_expect(_vnear(desk.global_position, DESK_CENTRES[n]),
			"Desk%02d centre at %s (got %s)" % [n, DESK_CENTRES[n], desk.global_position])
		var top := desk.get_node_or_null("Top") as MeshInstance3D
		_expect(top != null and _near(_top_y(top), 0.74), "Desk%02d top surface at y 0.74" % n)


func _check_chairs(hall: Node) -> void:
	for n in range(1, 13):
		var chair := hall.get_node_or_null("Chair%02d" % n) as Node3D
		var offset := 0.20 if n == 12 else 0.55
		var expected: Vector3 = DESK_CENTRES[n] + Vector3(0.0, 0.0, offset)
		_expect(chair != null and _vnear(chair.global_position, expected),
			"Chair%02d centre %.2f m south of its desk (Desk 12 at 0.20)" % [n, offset])
		var seat: Node = null
		if chair != null:
			seat = chair.get_node_or_null("Seat")
		_expect(seat != null and _near((seat as Node3D).global_position.y, 0.46), "Chair%02d seat centre y 0.46" % n)


func _check_typewriters_and_tubes(hall: Node) -> void:
	for n in range(1, 13):
		var tw := hall.get_node_or_null("Typewriter%02d" % n) as Node3D
		_expect(tw != null and _vnear(tw.global_position, DESK_CENTRES[n]), "Typewriter%02d at desk centre" % n)
		if tw != null:
			var body := tw.get_node_or_null("Body") as MeshInstance3D
			_expect(body != null and _near(_top_y(body), 0.86) and _near(body.global_position.z, DESK_CENTRES[n].z + 0.10),
				"Typewriter%02d body top 0.86, centred 0.10 m south" % n)
			var keys := tw.get_node_or_null("Keys")
			_expect(keys != null and keys.get_child_count() == 40, "Typewriter%02d has 40 keycaps" % n)
		var tube := hall.get_node_or_null("Tube%02d" % n) as Node3D
		_expect(tube != null, "Tube%02d exists" % n)
		if tube == null:
			continue
		var receiver := tube.get_node_or_null("Receiver") as MeshInstance3D
		_expect(receiver != null and _vnear(receiver.global_position, DESK_CENTRES[n] + Vector3(-0.62, 0.865, -0.30)),
			"Tube%02d receiver at desk left-back corner" % n)
		var pipe := tube.get_node_or_null("Tube") as MeshInstance3D
		_expect(pipe != null and _near(_top_y(pipe), 3.2) and _near(_bottom_y(pipe), 1.10),
			"Tube%02d runs from y 3.2 down to y 1.10" % n)


func _check_desk4(hall: Node) -> void:
	var desk: Node = hall.get_node_or_null("Desk04")
	for item in DESK4_ITEMS:
		_expect(desk != null and desk.get_node_or_null(item) != null, "Desk 4 item %s" % item)
	var rack: Node = null
	if desk != null:
		rack = desk.get_node_or_null("StampRack")
	_expect(rack != null and rack.get_child_count() == 9, "stamp rack has bar, four bases and four handles")
	var lamp := hall.get_node_or_null("Lamp04") as SpotLight3D
	_expect(lamp != null and _vnear(lamp.global_position, Vector3(4.70, 1.13, 3.18)), "Lamp04 inside the desk lamp shade")
	if lamp != null:
		_expect(_near(lamp.spot_angle, 50.0) and _near(lamp.spot_range, 1.5) and _near(lamp.light_energy, 0.8),
			"Lamp04 angle 50, range 1.5, energy 0.8")
		_expect(lamp.light_color.is_equal_approx(Color("#F0E2C0")), "Lamp04 colour #F0E2C0")
		var beam := -lamp.global_transform.basis.z
		_expect(_near(beam.y, -sin(deg_to_rad(75.0)), 0.001), "Lamp04 points down 75 degrees below horizontal")


func _check_clerks(hall: Node) -> void:
	for n in range(1, 13):
		var clerk := hall.get_node_or_null("Clerk%02d" % n) as Node3D
		var should_exist := n != 4 and n != 12
		_expect((clerk != null) == should_exist, "Clerk%02d %s" % [n, "present" if should_exist else "absent"])
		if clerk != null:
			var tris := _count_triangles(clerk)
			_expect(tris <= 300, "Clerk%02d triangles %d <= 300" % [n, tris])
			_expect(_vnear(clerk.global_position, DESK_CENTRES[n] + Vector3(0.0, 0.0, 0.55)),
				"Clerk%02d sits on its chair" % n)
	_expect(hall.get_node_or_null("Clerk04") == null, "no clerk at the player's Desk 4")


func _check_lighting(hall: Node) -> void:
	for i in range(1, 7):
		var fx := hall.get_node_or_null("Fixture%d" % i) as OmniLight3D
		var xz: Vector2 = FIXTURE_XZ[i - 1]
		_expect(fx != null and _vnear(fx.global_position, Vector3(xz.x, 3.0, xz.y)), "Fixture%d at (%s, 3.0, %s)" % [i, xz.x, xz.y])
		if fx != null:
			_expect(_near(fx.light_energy, 1.2) and _near(fx.omni_range, 6.0) and _near(fx.omni_attenuation, 1.0)
				and not fx.shadow_enabled and fx.light_color.is_equal_approx(Color("#E8F0E0")),
				"Fixture%d energy 1.2, range 6, attenuation 1, no shadows, #E8F0E0" % i)
	var we := hall.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_expect(we != null and we.environment != null, "WorldEnvironment present")
	if we != null and we.environment != null:
		var env := we.environment
		_expect(env.ambient_light_color.is_equal_approx(Color("#3A3A34")) and _near(env.ambient_light_energy, 1.0),
			"ambient #3A3A34 energy 1.0")
		_expect(not env.ssao_enabled and not env.ssr_enabled and not env.sdfgi_enabled and not env.glow_enabled,
			"no SSAO, SSR, SDFGI or glow")


func _check_room(hall: Node) -> void:
	for wall in ["WallNorth", "WallSouth", "WallEast", "WallWest"]:
		_expect(hall.get_node_or_null(wall) != null, "%s exists" % wall)
	var ceiling := hall.get_node_or_null("Ceiling") as MeshInstance3D
	_expect(ceiling != null and _near(ceiling.global_position.y, 3.2), "Ceiling at y 3.2")
	var floor_mi := hall.get_node_or_null("Floor") as MeshInstance3D
	_expect(floor_mi != null and _near(floor_mi.global_position.y, 0.0), "Floor at y 0")
	var zs := [-4.5, -1.5, 1.5, 4.5]
	for i in 4:
		var w := hall.get_node_or_null("Windows/Window%d" % (i + 1)) as Node3D
		_expect(w != null and _vnear(w.global_position, Vector3(8.99, 2.3, zs[i])), "Window%d on east wall" % (i + 1))
	var vent := hall.get_node_or_null("VentGrille") as Node3D
	_expect(vent != null and _vnear(vent.global_position, Vector3(5.25, 3.19, 3.5)), "VentGrille above Desk 4")
	var sup := hall.get_node_or_null("SupervisorDoor") as Node3D
	_expect(sup != null and _vnear(sup.global_position, Vector3(0.0, 0.0, -6.0)), "SupervisorDoor on the north wall at x 0")
	if sup != null:
		_expect(sup.global_transform.basis.z.is_equal_approx(Vector3(0, 0, 1)), "SupervisorDoor faces the room (south)")
	var exit_door := hall.get_node_or_null("ExitDoor") as Node3D
	_expect(exit_door != null and _vnear(exit_door.global_position, Vector3(-6.0, 0.0, 6.0)), "ExitDoor on the south wall at x -6")
	if exit_door != null:
		_expect(exit_door.global_transform.basis.z.is_equal_approx(Vector3(0, 0, -1)), "ExitDoor faces the room (north)")
	_expect(hall.get_node_or_null("SupervisorRoom") != null, "unlit supervisor room box exists")


## QUESTION-39 (spec 6.1, 15.2): the north and south walls are cut for the two doorways. No
## wall mesh stands in an opening, the walls alone leave each opening open, and the collision
## blocks every point of each wall while the doors are closed. The exit doorway is filled
## from outside by the black box of spec 15.2.
func _check_doorways(hall: Node) -> void:
	var doorways := [
		{"wall": "WallNorth", "door": "SupervisorDoor", "centre": 0.0, "z": -6.01, "zone": AABB(Vector3(-0.5, 0.0, -6.2), Vector3(1.0, 2.1, 0.2))},
		{"wall": "WallSouth", "door": "ExitDoor", "centre": -6.0, "z": 6.01, "zone": AABB(Vector3(-6.5, 0.0, 6.0), Vector3(1.0, 2.1, 0.2))},
	]
	for d in doorways:
		var wall := hall.get_node_or_null(d.wall) as Node3D
		var door := hall.get_node_or_null(d.door) as Node3D
		_expect(wall != null and door != null, "%s and %s exist" % [d.wall, d.door])
		if wall == null or door == null:
			continue
		var zone: AABB = (d.zone as AABB).grow(-0.002)
		var clear := true
		for mi in _meshes(wall, []):
			if (mi.global_transform * mi.get_aabb()).intersects(zone):
				clear = false
		_expect(clear, "%s has no wall mesh in its doorway" % d.wall)
		var wall_shapes := _box_shapes(wall, [])
		var all_shapes: Array = wall_shapes + _box_shapes(door, [])
		var gap_open := true
		var all_blocked := true
		for i in range(180):
			var x := -8.95 + 0.1 * float(i)
			for j in range(32):
				var p := Vector3(x, 0.05 + 0.1 * float(j), float(d.z))
				var in_gap: bool = absf(x - float(d.centre)) < 0.5 and p.y < 2.1
				if in_gap and _inside_any(p, wall_shapes):
					gap_open = false
				if not _inside_any(p, all_shapes):
					all_blocked = false
		_expect(gap_open, "%s: the walls alone leave the doorway open" % d.wall)
		_expect(all_blocked, "%s: collision blocks the whole wall while the door is closed" % d.wall)
	var beyond := hall.get_node_or_null("ExitBeyond") as MeshInstance3D
	_expect(beyond != null and _vnear(beyond.global_position, Vector3(-6.0, 1.05, 6.7))
		and beyond.get_aabb().size.is_equal_approx(Vector3(1.2, 2.1, 1.0)),
		"ExitBeyond: the 1.2 x 2.1 x 1.0 m box sits beyond the exit doorway")
	var beyond_mat = beyond.material_override if beyond != null else null
	_expect(beyond_mat is ShaderMaterial and (beyond_mat as ShaderMaterial).get_shader_parameter("albedo_color") == Color(0, 0, 0, 1),
		"ExitBeyond is black (#000000)")


## Every MeshInstance3D under node, appended to out.
func _meshes(node: Node, out: Array) -> Array:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		out.append(node)
	for c in node.get_children():
		_meshes(c, out)
	return out


## Every box collision shape under node, as [global transform, box size], appended to out.
func _box_shapes(node: Node, out: Array) -> Array:
	if node is CollisionShape3D and (node as CollisionShape3D).shape is BoxShape3D:
		var size := ((node as CollisionShape3D).shape as BoxShape3D).size
		out.append([(node as Node3D).global_transform, size])
	for c in node.get_children():
		_box_shapes(c, out)
	return out


## True when point p lies inside any of the box shapes ([transform, size] pairs).
func _inside_any(p: Vector3, shapes: Array) -> bool:
	for s in shapes:
		var local: Vector3 = (s[0] as Transform3D).affine_inverse() * p
		var half: Vector3 = (s[1] as Vector3) * 0.5
		if absf(local.x) <= half.x and absf(local.y) <= half.y and absf(local.z) <= half.z:
			return true
	return false


func _check_clock_and_boards(hall: Node) -> void:
	var clock := hall.get_node_or_null("Clock") as Node3D
	_expect(clock != null and _vnear(clock.global_position, Vector3(0.0, 2.55, -5.88)), "Clock centre (0, 2.55, -5.88)")
	if clock != null:
		_expect(clock.global_transform.basis.z.is_equal_approx(Vector3(0, 0, 1)), "Clock faces south")
	var hour := hall.get_node_or_null("ClockHourHand") as Node3D
	var minute := hall.get_node_or_null("ClockMinuteHand") as Node3D
	_expect(hour != null and _near(rad_to_deg(hour.rotation.z), -269.0, 0.01), "ClockHourHand at 8h58 (269 degrees clockwise)")
	_expect(minute != null and _near(rad_to_deg(minute.rotation.z), -348.0, 0.01), "ClockMinuteHand at 58 minutes (348 degrees clockwise)")
	var board := hall.get_node_or_null("QuotaBoard") as Node3D
	_expect(board != null and _vnear(board.global_position, Vector3(-8.88, 1.6, 0.0)), "QuotaBoard centre (-8.88, 1.6, 0)")
	if board != null:
		_expect(board.global_transform.basis.z.is_equal_approx(Vector3(1, 0, 0)), "QuotaBoard faces east")


## Turns Clerk01 to the player and back. Runs last, after the triangle count.
func _check_facing(hall: Node) -> void:
	var clerk = hall.get_node_or_null("Clerk01")
	var chair := hall.get_node_or_null("Chair01") as Node3D
	if clerk == null or chair == null:
		_expect(false, "facing check: Clerk01 and Chair01 exist")
		return
	clerk.set_facing_player()
	_expect(_near(clerk.rotation.y, -PI * 0.5, 0.01) and _near(chair.rotation.y, -PI * 0.5, 0.01),
		"Clerk01 and its chair turn to face Desk 4 (yaw -90 degrees, got %.3f)" % clerk.rotation.y)
	clerk.set_seated_facing_north()
	_expect(_near(clerk.rotation.y, 0.0) and _near(chair.rotation.y, 0.0), "Clerk01 returns to facing north")


## Sum of the visible triangles of every MeshInstance3D under node (index count / 3).
func _count_triangles(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree() and (node as MeshInstance3D).mesh != null:
		total += Geo.triangle_count((node as MeshInstance3D).mesh)
	for child in node.get_children():
		total += _count_triangles(child)
	return total
