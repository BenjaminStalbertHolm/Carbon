extends Node
## UnseenChanges: applies the spec 9.3 world changes when their targets are unobserved
## (spec 9.2). Autoload. The registry below is the 9.3 table, one entry per change.
##
## Each entry: id, day, after ("day_start" or "task_sent:<id>"), target (node name, or
## "@clerks" for every clerk figure), operation (Callable applying the change), revert
## (Callable or null) and distance_rule_waived.
##
## Per-change state lives in GameState.flags["unseen"][id] so it survives save and load:
## pending, applied, reverted, mark (revert marked) and acc (accumulated seen seconds).
## Operations are idempotent, so restore_visuals() can re-run them after a rebuild.

## World scripts are loaded lazily so that this autoload compiles even while the hall is
## being edited. Values below mirror hall_c.gd (spec 6.1 and 8.9).
const GEOMETRY_PATH := "res://scripts/world/geometry.gd"
const HALL_PATH := "res://scripts/world/hall_c.gd"
const CLERK_PATH := "res://scripts/world/clerk_figure.gd"
const NAMEPLATE_PATH := "res://scripts/world/nameplate.gd"
const Content := preload("res://scripts/logic/content.gd")
## The flags this registry writes (GameState.flags). A new game clears them with the rest of the state.
const OWNED_FLAGS := ["unseen", "desk12_chair_out", "clock_override", "unison_typing", "tray_line"]
const DESK12_CENTRE := Vector3(5.25, 0.0, -2.5)
const NAMEPLATE_POS := Vector3(0.0, 0.77, -0.36)

const UNSEEN_MIN_S := 1.5
const DISTANCE_MIN_M := 2.0
const APPARITION_HIDE_DISTANCE_M := 3.0
const APPARITION_HIDE_UNSEEN_S := 0.5
const DOOR_SEEN_TOTAL_S := 2.0
const CLOCK_SEEN_MARK_S := 1.0
const DESK12_CHAIR_OFFSET := 0.55
const DESK12_CHAIR_YAW_DEG := 30.0
const SILHOUETTE_COLOUR := Color("#3A3D38")
const GHOST_IDS := ["D3-U3", "D4-U3"]

var _hall: Node3D = null
var _changes: Array = []
var _chair12_built := {}  # Chair12's position and rotation as the hall was built (set by bind_hall)


func _ready() -> void:
	_changes = _build_changes()
	var dd = _dd()
	if dd != null:
		dd.connect("task_sent", Callable(self, "_on_task_sent"))
		dd.connect("ghost_sheet_due", Callable(self, "_on_ghost_sheet_due"))


## Spec 9.2 apply rule, pure: the target has been unseen for at least 1.5 s and is at
## least 2.0 m away, unless the change waives the distance rule.
static func apply_ready(unseen: float, distance: float, waived: bool) -> bool:
	return unseen >= UNSEEN_MIN_S and (waived or distance >= DISTANCE_MIN_M)


## The registry as data (for tests and the debug console). Operations are Callables.
func changes() -> Array:
	return _changes


## The hall root built by hall_c.gd. Named nodes are looked up under it, and the
## targets and clerks are tracked by Gaze.
## Called once, right after hall_c.gd builds the hall, before any change applies (the built
## Chair12 transform is read here).
func bind_hall(root: Node3D) -> void:
	_hall = root
	var chair = _node("Chair12")
	if chair != null:
		_chair12_built = {"position": chair.position, "rotation": chair.rotation}
	for n in ["Desk04", "Desk12", "Chair12", "Clock", "SupervisorDoor", "Typewriter04"]:
		_track(_node(n))
	for c in _clerk_nodes():
		_track(c)


## A new game (spec 16.2): clears every applied and pending change, its flags and its visuals, and returns
## the hall's unseen changes to the built state (Chair12 pushed under the desk, no Clerk12 apparition, no
## door silhouette). Call after GameState.new_game() and before the day's world is applied. The nameplates
## go back to the names the hall was built with (spec 8.9): GameState.new_game leaves desks 1-11 blank.
func reset() -> void:
	var gs = _gs()
	if gs != null:
		for key in OWNED_FLAGS:
			gs.flags.erase(key)
		_reset_nameplates(gs)
	_restore_chair12()
	_remove_apparition()
	_remove_silhouette()


func _reset_nameplates(gs) -> void:
	var names: Dictionary = Content.strings()["nameplates"]
	for n in range(1, 13):
		var text := String(names.get(str(n), ""))
		gs.nameplate[str(n)] = text
		set_nameplate_visual(n, text)


func _restore_chair12() -> void:
	var chair = _node("Chair12")
	if chair == null or _chair12_built.is_empty():
		return
	chair.position = _chair12_built["position"]
	chair.rotation = _chair12_built["rotation"]


func _remove_apparition() -> void:
	var fig = _node("Clerk12")
	if fig == null:
		return
	var gaze = _gaze()
	if gaze != null:
		gaze.untrack(fig)
	if fig.get_parent() != null:
		fig.get_parent().remove_child(fig)
	fig.queue_free()


func _remove_silhouette() -> void:
	var door = _node("SupervisorDoor")
	if door == null:
		return
	var mi = door.get_node_or_null("DoorSilhouette")
	if mi != null:
		door.remove_child(mi)
		mi.queue_free()


## Called by the lead during the day-transition black screen (spec 9.2): applies the
## changes whose trigger is day_start for this day, and removes the Desk 12 apparition
## when it is still visible at the start of Day 4 or later (spec 9.3 D3-U1).
func apply_day_start(day: int) -> void:
	for c in _changes:
		if int(c.day) == day and String(c.after) == "day_start" and not _state(c.id).applied:
			_apply(c)
	if day >= 4:
		_remove_apparition_overnight()


## Called by the lead at the end of a day (spec 9.2): applies every pending change
## now. Ghost changes are not applied here because DayDirector.run_overnight files the
## pending ghost sheet itself (flags.ghost_pending).
func flush_pending() -> void:
	for c in _changes:
		var st := _state(c.id)
		if st.applied or not st.pending:
			continue
		if GHOST_IDS.has(String(c.id)):
			st.applied = true
			st.pending = false
		else:
			_apply(c)
	var gs = _gs()
	if gs != null and int(gs.day) >= 3:
		_remove_apparition_overnight()


## Re-runs the visual part of every applied change that has not reverted. Call after the
## hall is rebuilt on load. Ghost changes are skipped (the typewriter holds that state).
func restore_visuals() -> void:
	for c in _changes:
		var st := _state(c.id)
		if st.applied and not st.reverted and not GHOST_IDS.has(String(c.id)):
			c.operation.call(c)


## Per-change status rows for the debug console: id, pending, applied, reverted.
func status() -> Array:
	var rows: Array = []
	for c in _changes:
		var st := _state(c.id)
		rows.append({"id": c.id, "pending": st.pending, "applied": st.applied, "reverted": st.reverted})
	return rows


## Rewrites one desk's nameplate with the given text (spec 5.5). Removes the old plate
## first so the new one takes the name "Nameplate".
func set_nameplate_visual(desk: int, text: String) -> void:
	var desk_node = _node("Desk%02d" % desk)
	if desk_node == null:
		return
	var old = desk_node.get_node_or_null("Nameplate")
	if old != null:
		desk_node.remove_child(old)
		old.queue_free()
	load(NAMEPLATE_PATH).build(desk_node, text, NAMEPLATE_POS)


func _on_task_sent(task_id: String) -> void:
	for c in _changes:
		var st := _state(c.id)
		if String(c.after) == "task_sent:" + task_id and not st.applied:
			st.pending = true


func _on_ghost_sheet_due(day: int) -> void:
	for c in _changes:
		var st := _state(c.id)
		if GHOST_IDS.has(String(c.id)) and int(c.day) == day and not st.applied:
			st.pending = true


func _process(delta: float) -> void:
	if _hall == null or _gs() == null:
		return
	for c in _changes:
		var st := _state(c.id)
		if st.applied or not st.pending:
			continue
		var m := _metrics(c)
		if apply_ready(m.x, m.y, bool(c.distance_rule_waived)):
			_apply(c)
	_check_reverts(delta)


func _apply(c: Dictionary) -> bool:
	var st := _state(c.id)
	if st.applied:
		return true
	var ok: bool = bool(c.operation.call(c))
	if ok:
		st.applied = true
		st.pending = false
	return ok


func _revert(c: Dictionary) -> void:
	var st := _state(c.id)
	if c.revert == null or st.reverted:
		return
	c.revert.call(c)
	st.reverted = true
	st.mark = false


func _check_reverts(delta: float) -> void:
	var gaze = _gaze()
	if gaze == null:
		return
	# D2-U2: the clock reverts once its seen time reaches 1.0 s and it is unseen for 1.5 s.
	var c2 := _change("D2-U2")
	var st2 := _state("D2-U2")
	if st2.applied and not st2.reverted:
		var clock = _node("Clock")
		if clock != null:
			if gaze.seen_time(clock) >= CLOCK_SEEN_MARK_S:
				st2.mark = true
			if st2.mark and gaze.unseen_time(clock) >= UNSEEN_MIN_S:
				_revert(c2)
	# D4-U2: the silhouette goes once the door glass has been seen for 2.0 s in total.
	var c4 := _change("D4-U2")
	var st4 := _state("D4-U2")
	if st4.applied and not st4.reverted:
		var door = _node("SupervisorDoor")
		if door != null:
			if gaze.is_looked_at(door):
				st4.acc = float(st4.acc) + delta
			if float(st4.acc) >= DOOR_SEEN_TOTAL_S:
				st4.mark = true
			if st4.mark and gaze.unseen_time(door) >= UNSEEN_MIN_S:
				_revert(c4)
	# D3-U1: the apparition hides when the player is within 3.0 m of Desk 12 and the
	# figure has been unseen for 0.5 s. It never reappears. The distance is floor-plane,
	# from the camera to the centre of Desk 12 (QUESTION-44, QUESTION-67).
	var c3 := _change("D3-U1")
	var st3 := _state("D3-U1")
	if st3.applied and not st3.reverted:
		var fig = _node("Clerk12")
		var desk12 = _node("Desk12")
		if fig != null and desk12 != null:
			if gaze.camera_floor_distance(desk12.global_position) < APPARITION_HIDE_DISTANCE_M and gaze.unseen_time(fig) >= APPARITION_HIDE_UNSEEN_S:
				_revert(c3)


func _remove_apparition_overnight() -> void:
	var st := _state("D3-U1")
	if st.applied and not st.reverted:
		_revert(_change("D3-U1"))


## Metrics for the apply rule: Vector2(unseen, distance), the distance on the floor plane
## (QUESTION-67, Gaze.distance_to_camera). The worst case over every target, so a group counts
## as unseen only when all of its members are.
func _metrics(c: Dictionary) -> Vector2:
	var gaze = _gaze()
	var nodes := _target_nodes(c)
	if gaze == null or nodes.is_empty():
		return Vector2(0.0, 0.0)
	var unseen := INF
	var dist := INF
	for n in nodes:
		_track(n)
		unseen = minf(unseen, gaze.unseen_time(n))
		dist = minf(dist, gaze.distance_to_camera(n))
	return Vector2(unseen, dist)


func _target_nodes(c: Dictionary) -> Array:
	var out: Array = []
	var t := String(c.target)
	if t == "@clerks":
		out = _clerk_nodes()
	else:
		var n = _node(t)
		if n != null:
			out.append(n)
	return out


func _clerk_nodes() -> Array:
	var out: Array = []
	if _hall == null:
		return out
	for n in range(1, 12):
		var c = _hall.get_node_or_null("Clerk%02d" % n)
		if c != null:
			out.append(c)
	return out


func _track(n) -> void:
	var gaze = _gaze()
	if gaze != null and n != null:
		gaze.track(n)


func _node(node_name: String):
	if _hall == null:
		return null
	return _hall.find_child(node_name, true, false)


func _change(id: String) -> Dictionary:
	for c in _changes:
		if String(c.id) == id:
			return c
	return {}


# --- Operations (each takes its registry entry and returns true when applied) -------

func _op_d1_u0(_c: Dictionary) -> bool:
	var name := _player_name_14()
	_set_plate(4, name)
	return true


func _op_d1_u1(_c: Dictionary) -> bool:
	var chair = _node("Chair12")
	if chair == null:
		return false
	chair.position = DESK12_CENTRE + Vector3(0.0, 0.0, DESK12_CHAIR_OFFSET)
	chair.rotation_degrees = Vector3(0.0, DESK12_CHAIR_YAW_DEG, 0.0)
	_flag_set("desk12_chair_out", true)
	return true


func _op_d2_u1(_c: Dictionary) -> bool:
	_set_plate(12, "0411")
	return true


func _op_d2_u2(_c: Dictionary) -> bool:
	_flag_set("clock_override", "03:10")
	return true


func _rev_d2_u2(_c: Dictionary) -> bool:
	_flag_set("clock_override", "")
	return true


func _op_d3_u1(_c: Dictionary) -> bool:
	if _hall == null:
		return false
	if _node("Clerk12") != null:
		return true
	var fig = load(CLERK_PATH).build(_hall, "Clerk12", DESK12_CENTRE + Vector3(0.0, 0.0, DESK12_CHAIR_OFFSET), null)
	fig.add_to_group("apparition")
	_track(fig)
	return true


func _rev_d3_u1(_c: Dictionary) -> bool:
	_remove_apparition()
	return true


func _op_d3_u2(_c: Dictionary) -> bool:
	_flag_set("unison_typing", true)
	return true


func _op_ghost(c: Dictionary) -> bool:
	var dd = _dd()
	if dd == null:
		return false
	var sheet := String(dd.call("apply_ghost_sheet", int(c.day)))
	if sheet == "":
		return false
	var tw = _node("Typewriter04")
	if tw != null:
		var paper = tw.find_child("Paper", true, false)
		if paper != null:
			paper.visible = true
	return true


func _op_d4_u1(_c: Dictionary) -> bool:
	_set_plate(4, "0412")
	return true


func _op_d4_u2(_c: Dictionary) -> bool:
	var door = _node("SupervisorDoor")
	if door == null:
		return false
	if door.get_node_or_null("DoorSilhouette") == null:
		var mi := silhouette_mesh()
		mi.position = Vector3(0.0, 1.05, -0.03)
		door.add_child(mi)
	return true


func _rev_d4_u2(_c: Dictionary) -> bool:
	_remove_silhouette()
	return true


func _op_d5_u1(_c: Dictionary) -> bool:
	# DayDirector.run_overnight sets flags.tray_line at Day 5 start. Confirm only.
	_flag_set("tray_line", true)
	return true


func _op_d5_u2(_c: Dictionary) -> bool:
	var gs = _gs()
	if gs == null:
		return false
	gs.clock_frozen = true
	return true


func _build_changes() -> Array:
	return [
		_reg("D1-U0", 1, "task_sent:P-1", "Desk04", "_op_d1_u0", "", true),
		_reg("D1-U1", 1, "task_sent:T-1", "Chair12", "_op_d1_u1", "", false),
		_reg("D2-U1", 2, "day_start", "Desk12", "_op_d2_u1", "", false),
		_reg("D2-U2", 2, "task_sent:RO-2", "Clock", "_op_d2_u2", "_rev_d2_u2", false),
		_reg("D3-U1", 3, "task_sent:RO-3", "Desk12", "_op_d3_u1", "_rev_d3_u1", false),
		_reg("D3-U2", 3, "task_sent:F-3", "@clerks", "_op_d3_u2", "", false),
		_reg("D3-U3", 3, "task_sent:F-3", "Typewriter04", "_op_ghost", "", true),
		_reg("D4-U1", 4, "task_sent:RO-4", "Desk04", "_op_d4_u1", "", false),
		_reg("D4-U2", 4, "task_sent:T-4", "SupervisorDoor", "_op_d4_u2", "_rev_d4_u2", false),
		_reg("D4-U3", 4, "task_sent:T-4", "Typewriter04", "_op_ghost", "", true),
		_reg("D5-U1", 5, "day_start", "Desk04", "_op_d5_u1", "", false),
		_reg("D5-U2", 5, "task_sent:P-1D", "Clock", "_op_d5_u2", "", false),
	]


func _reg(id: String, day: int, after: String, target: String, op: String, revert: String, waived: bool) -> Dictionary:
	return {
		"id": id,
		"day": day,
		"after": after,
		"target": target,
		"operation": Callable(self, op),
		"revert": Callable(self, revert) if revert != "" else null,
		"distance_rule_waived": waived,
	}


## Head-and-shoulders silhouette (spec 9.3 D4-U2): a flat mesh within a 0.45 x 0.95 quad.
## The outline is a rounded rectangle 0.45 x 0.60 with its bottom edge at y = 0, and a head
## circle r = 0.11 sitting atop it, its lowest point on the rectangle's top edge (QUESTION-40).
## The outline is therefore 0.82 m tall, with its bottom on the bottom of the 0.95 m bounds.
## Faces +Z (the room side).
static func silhouette_mesh() -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var body := _rounded_rect_points(0.225, 0.60, 0.10)
	_fan(st, Vector2(0.0, 0.30), body)
	var head := _circle_points(Vector2(0.0, 0.71), 0.11, 16)
	_fan(st, Vector2(0.0, 0.71), head)
	st.set_normal(Vector3(0.0, 0.0, 1.0))
	var mesh := st.commit()
	var geo = load(GEOMETRY_PATH)
	return geo.instance(mesh, geo.flat(SILHOUETTE_COLOUR), "DoorSilhouette")


static func _fan(st: SurfaceTool, centre: Vector2, ring: Array) -> void:
	for i in range(ring.size()):
		var a: Vector2 = ring[i]
		var b: Vector2 = ring[(i + 1) % ring.size()]
		# Clockwise seen from +Z, the front face the room sees; cull_back keeps it (QUESTION-45).
		for p in [centre, b, a]:
			st.set_normal(Vector3(0.0, 0.0, 1.0))
			st.add_vertex(Vector3(p.x, p.y, 0.0))


static func _circle_points(centre: Vector2, r: float, segments: int) -> Array:
	var out: Array = []
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		out.append(centre + Vector2(cos(a), sin(a)) * r)
	return out


## Counter-clockwise outline of a rounded rectangle with bottom edge at y = 0.
static func _rounded_rect_points(half_w: float, h: float, r: float) -> Array:
	var out: Array = []
	var corners := [
		[Vector2(half_w - r, r), -90.0],
		[Vector2(half_w - r, h - r), 0.0],
		[Vector2(-half_w + r, h - r), 90.0],
		[Vector2(-half_w + r, r), 180.0],
	]
	for corner in corners:
		var centre: Vector2 = corner[0]
		var start: float = corner[1]
		for s in range(0, 4):
			var a := deg_to_rad(start + 90.0 * float(s) / 3.0)
			out.append(centre + Vector2(cos(a), sin(a)) * r)
	return out


func _set_plate(desk: int, text: String) -> void:
	var gs = _gs()
	if gs != null:
		gs.nameplate[str(desk)] = text
	set_nameplate_visual(desk, text)


func _player_name_14() -> String:
	var tt = get_node_or_null("/root/TextTokens")
	if tt == null:
		return ""
	var name := String(tt.token_values()["PLAYER_NAME"])
	return name.substr(0, 14)


func _flag_set(key: String, value: Variant) -> void:
	var gs = _gs()
	if gs != null:
		gs.flags[key] = value


func _state(id: String) -> Dictionary:
	var gs = _gs()
	if gs == null:
		return {"pending": false, "applied": false, "reverted": false, "mark": false, "acc": 0.0}
	var flags: Dictionary = gs.flags
	if not flags.has("unseen"):
		flags["unseen"] = {}
	var all: Dictionary = flags["unseen"]
	if not all.has(id):
		all[id] = {"pending": false, "applied": false, "reverted": false, "mark": false, "acc": 0.0}
	return all[id]


func _gs():
	return get_node_or_null("/root/GameState")


func _dd():
	return get_node_or_null("/root/DayDirector")


func _gaze():
	return get_node_or_null("/root/Gaze")
