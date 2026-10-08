extends RefCounted
## Debug console commands (spec 21). run(line) runs one command line and returns its result lines.
## Every command checks DebugGuard first. main is the CARBON main controller (scripts/main.gd).
## Commands: day N, set <var> <value>, skip, ending A|B|C, gaze, changes, audio_check, tris.
## References to autoloads and to main are untyped, so member access is checked at run time.

const DebugGuard := preload("res://scripts/debug/debug_guard.gd")
const DebugDays := preload("res://scripts/debug/debug_day_defaults.gd")
const Content := preload("res://scripts/logic/content.gd")
const EndingsLogic := preload("res://scripts/logic/endings.gd")
const Geo := preload("res://scripts/world/geometry.gd")

const TRIS_BUDGET := 20000
const UNKNOWN := "unknown command"

var _main = null


func _init(main = null) -> void:
	_main = main


## Runs one command line. Empty input gives no lines. Unknown input gives "unknown command".
func run(line: String) -> PackedStringArray:
	if not DebugGuard.enabled():
		return PackedStringArray(["debug tools are not available in this build"])
	var parts := line.strip_edges().split(" ", false)
	if parts.is_empty():
		return PackedStringArray()
	var args := parts.slice(1)
	match parts[0].to_lower():
		"day":
			return _cmd_day(args)
		"set":
			return _cmd_set(args)
		"skip":
			return _cmd_skip()
		"ending":
			return _cmd_ending(args)
		"gaze":
			return _cmd_gaze()
		"changes":
			return _cmd_changes()
		"audio_check":
			return _cmd_audio_check()
		"tris":
			return _cmd_tris()
	return PackedStringArray([UNKNOWN])


# --- day N -----------------------------------------------------------------------------

func _cmd_day(args: PackedStringArray) -> PackedStringArray:
	if args.size() != 1 or not args[0].is_valid_int() or int(args[0]) < 1 or int(args[0]) > 5:
		return PackedStringArray(["usage: day N (N is 1 to 5)"])
	var day := int(args[0])
	var gs = _autoload("GameState")
	var dd = _autoload("DayDirector")
	if _main == null or gs == null or dd == null:
		return PackedStringArray(["day: no game is loaded"])
	_close_views()
	DebugDays.prepare(gs, dd, day)
	_autoload("UnseenChanges").apply_day_start(day)
	_main.endings.reset()
	_main.clerk_world.apply_day_state(day)
	_main.clerk_world.reset_silence()
	_main.clock_world.reset_silence()
	_main.player.reset_seated()
	_main.debug_run(true)
	return PackedStringArray(["day %d: prior orders processed, carbons filed, tokens default" % day])


func _close_views() -> void:
	if _main.interaction != null and _main.interaction.holding():
		_main.interaction.hand_release(false)
	if _main.read_view != null and _main.read_view.is_open():
		_main.read_view.close()
	if _main.typewriter != null:
		_main.typewriter.close_typing_view()
	_main.set_typing_focus(false)


# --- set <var> <value> -----------------------------------------------------------------

func _cmd_set(args: PackedStringArray) -> PackedStringArray:
	var gs = _autoload("GameState")
	if args.size() < 2 or gs == null:
		return PackedStringArray(["usage: set <var> <value>"])
	var path := args[0].split(".", false)
	if path.is_empty():
		return PackedStringArray(["usage: set <var> <value>"])
	var root_name := path[0]
	if not _has_property(gs, root_name):
		return PackedStringArray(["unknown variable: %s" % root_name])
	var raw := " ".join(args.slice(1))
	if path.size() == 1:
		gs.set(root_name, _coerce(raw, gs.get(root_name)))
		return PackedStringArray(["set %s = %s" % [root_name, str(gs.get(root_name))]])
	var holder = gs.get(root_name)
	for i in range(1, path.size() - 1):
		if typeof(holder) != TYPE_DICTIONARY or not holder.has(path[i]):
			return PackedStringArray(["unknown key: %s" % args[0]])
		holder = holder[path[i]]
	if typeof(holder) != TYPE_DICTIONARY:
		return PackedStringArray(["not a dictionary: %s" % args[0]])
	var last := path[path.size() - 1]
	holder[last] = _coerce(raw, holder.get(last))
	return PackedStringArray(["set %s = %s" % [args[0], str(holder[last])]])


## Turns the typed text into a value of the same type as the current value. A JSON array or
## object is parsed. An unset key is guessed: true or false, an integer, a float, or text.
static func _coerce(raw: String, current: Variant) -> Variant:
	var text := raw.strip_edges()
	if typeof(current) == TYPE_STRING:
		return text
	if text.begins_with("[") or text.begins_with("{"):
		var parsed: Variant = JSON.parse_string(text)
		if parsed != null:
			return parsed
	match typeof(current):
		TYPE_BOOL:
			return text.to_lower() in ["true", "1", "yes", "on"]
		TYPE_INT:
			if text.is_valid_int():
				return int(text)
		TYPE_FLOAT:
			if text.is_valid_float():
				return float(text)
	if text.to_lower() == "true" or text.to_lower() == "false":
		return text.to_lower() == "true"
	if text.is_valid_int():
		return int(text)
	if text.is_valid_float():
		return float(text)
	return text


static func _has_property(obj: Object, property: String) -> bool:
	for info in obj.get_property_list():
		if String(info.name) == property:
			return true
	return false


# --- skip ------------------------------------------------------------------------------

## Completes the active task with its output as-is (spec 21), and adds no typing. For a transcription the
## output is the task's sheet + carbon set. A sheet of the task that is already out (in hand, on the
## typewriter, on the copyholder or on the read stack) is sent with its current contents, after it is
## removed as spec 7.7 removes it: its carbon goes to the carbon spot and is not filed. When no such sheet
## is out, one sheet + carbon set is taken from the tray and sent blank.
func _cmd_skip() -> PackedStringArray:
	var gs = _autoload("GameState")
	var dd = _autoload("DayDirector")
	if gs == null or dd == null:
		return PackedStringArray(["skip: no game is loaded"])
	var tid := String(dd.active_task)
	if tid == "":
		return PackedStringArray(["skip: no task is active"])
	var spec := _task_spec(int(gs.day), tid)
	if spec.is_empty():
		return PackedStringArray(["skip: task %s is not in day %d" % [tid, int(gs.day)]])
	if spec.has("transcription"):
		return _skip_transcription(gs, dd, tid)
	var out_id := String(spec.get("output", ""))
	if out_id == "" or not gs.docs.has(out_id):
		return PackedStringArray(["skip: the output of %s is not in the world" % tid])
	dd.send_document(out_id)
	return PackedStringArray(["skip: sent %s (task %s)" % [out_id, tid]])


func _skip_transcription(gs, dd, tid: String) -> PackedStringArray:
	var sid := _task_sheet_out(gs, tid)
	var origin := "the sheet out"
	if sid == "":
		sid = String(dd.take_blank_sheet())
		if sid == "":
			return PackedStringArray(["skip: no sheet of %s is out, and the blank paper tray is empty" % tid])
		origin = "a blank sheet from the tray"
	dd.paper_removed(sid)
	gs.place(sid, "hand")
	dd.send_document(sid)
	var acc := float(gs.accuracy.get(tid, 0.0))
	return PackedStringArray(["skip: sent %s (%s) for %s, accuracy %.3f" % [sid, origin, tid, acc]])


## The original sheet of the task, if one is out of the tray: in hand, on the typewriter, on the copyholder
## or on the read stack. Carbons are never returned here. Returns "" when none is out.
func _task_sheet_out(gs, tid: String) -> String:
	for where in ["typewriter", "hand", "copyholder", "read_stack"]:
		var holder = gs.loc.get(where)
		var ids: Array = []
		if typeof(holder) == TYPE_ARRAY:
			ids = holder
		elif String(holder) != "":
			ids = [holder]
		for id in ids:
			var doc: Dictionary = gs.docs.get(String(id), {})
			if String(doc.get("kind", "")) == "sheet" and String(doc.get("task", "")) == tid and not bool(doc.get("carbon", false)):
				return String(id)
	return ""


func _task_spec(day: int, task_id: String) -> Dictionary:
	for task in Content.day(day).get("tasks", []):
		if String(task.id) == task_id:
			return task
	return {}


# --- ending A|B|C ----------------------------------------------------------------------

## Starts an ending from the current state. A and B start as RO-5 does (spec 15.1, 15.2). C needs
## the refusal and then a click on the carbon stack, so it starts only when carbons_kept_at_final
## is at least 3 (spec 15.3).
func _cmd_ending(args: PackedStringArray) -> PackedStringArray:
	var which := args[0].to_upper() if args.size() == 1 else ""
	if not (which in ["A", "B", "C"]):
		return PackedStringArray(["usage: ending A|B|C"])
	var gs = _autoload("GameState")
	var dd = _autoload("DayDirector")
	if _main == null or gs == null or dd == null or _main.endings == null:
		return PackedStringArray(["ending: no game is loaded"])
	if which == "C" and not EndingsLogic.ending_c_available(int(gs.carbons_kept_at_final)):
		return PackedStringArray(["ending C is unavailable: carbons_kept_at_final is %d, needs 3" % int(gs.carbons_kept_at_final)])
	_main.endings.reset()
	if which == "A":
		dd.ro5_sent.emit(true)
		return PackedStringArray(["ending A: started with the current state" if _main.endings.ending_running() else "ending A: not started"])
	dd.ro5_sent.emit(false)
	if which == "B":
		return PackedStringArray(["ending B: refusal started (the exit unlocks after 5.0 s)"])
	_main.player.sit_down(true)
	_main.interaction.action_pressed.emit("carbon_spot", null, Vector3.ZERO)
	if _main.endings.ending_running():
		return PackedStringArray(["ending C: started from the carbon stack, after the refusal"])
	return PackedStringArray(["ending C: not started (the lower drawer is open, or a click is held)"])


# --- gaze, changes, audio_check, tris ----------------------------------------------------

func _cmd_gaze() -> PackedStringArray:
	var gaze = _autoload("Gaze")
	if gaze == null:
		return PackedStringArray(["gaze: no Gaze autoload"])
	var now_on := not bool(gaze.get("_overlay_on"))
	gaze.set_overlay(now_on)
	return PackedStringArray(["gaze overlay %s" % _on_off(now_on)])


func _cmd_changes() -> PackedStringArray:
	var un = _autoload("UnseenChanges")
	if un == null:
		return PackedStringArray(["changes: no UnseenChanges autoload"])
	var pending := PackedStringArray()
	var applied := PackedStringArray()
	var reverted := PackedStringArray()
	for row in un.status():
		if row.pending:
			pending.append(String(row.id))
		if row.applied:
			applied.append(String(row.id))
		if row.reverted:
			reverted.append(String(row.id))
	return PackedStringArray([
		"pending: %s" % _list(pending),
		"applied: %s" % _list(applied),
		"reverted: %s" % _list(reverted),
	])


func _cmd_audio_check() -> PackedStringArray:
	var ad = _autoload("AudioDirector")
	if ad == null:
		return PackedStringArray(["audio_check: no AudioDirector autoload"])
	# The checker is enabled by default in debug builds (loudness_checker.gd), so the toggle reads
	# its current state and flips it.
	var checker = ad.get("_checker")
	var now_on := checker != null and not bool(checker.enabled)
	ad.set_checker_enabled(now_on)
	return PackedStringArray(["loudness logger %s (playbacks %d, violations %d)" % [
		_on_off(now_on), int(ad.get_checker_playbacks()), int(ad.get_checker_violations())]])


func _cmd_tris() -> PackedStringArray:
	if _main == null or _main.hall == null:
		return PackedStringArray(["tris: the hall is not built"])
	var n := _count_visible(_main.hall)
	var note := "" if n <= TRIS_BUDGET else " (over the budget of %d)" % TRIS_BUDGET
	return PackedStringArray(["visible triangles: %d%s" % [n, note]])


static func _count_visible(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D and (node as MeshInstance3D).is_visible_in_tree() and (node as MeshInstance3D).mesh != null:
		total += Geo.triangle_count((node as MeshInstance3D).mesh)
	for child in node.get_children():
		total += _count_visible(child)
	return total


# --- helpers ---------------------------------------------------------------------------

static func _on_off(on: bool) -> String:
	return "on" if on else "off"


static func _list(items: PackedStringArray) -> String:
	return ", ".join(items) if items.size() > 0 else "none"


func _autoload(node_name: String):
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
