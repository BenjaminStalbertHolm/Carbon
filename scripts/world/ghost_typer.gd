extends Node
## Ghost typing presentation glue (spec 10.2, 10.3, 11.1). Days 3 and 4 only.
##
## The typing itself is TypewriterModel's job (ghost_set_running, enqueue_ghost_text,
## enqueue_ghost_x, tick). This node decides when to start and stop, which line is next,
## when a line counts as finished, and which player-typed cells get an X first.
##
## Usage (the lead, or the typewriter view): var gt := GhostTyper.new(); add_child(gt);
##   gt.setup(typewriter_model, typewriter_node3d); the view calls gt.set_typing_view(bool)
##   when the typing view opens or closes, and passes each event batch through
##   gt.play_ghost_sounds(events). The view must not play sounds for events flagged
##   "ghost": true, because play_ghost_sounds plays them with the -20 dB ghost gain.
##
## Times are Time.get_ticks_msec() as float. The view must tick the model on the same clock.

const Content := preload("res://scripts/logic/content.gd")

const UNSEEN_TRIGGER_S := 6.0
const FAR_TRIGGER_M := 4.0
const FAR_TRIGGER_S := 3.0


## Trigger state (spec 10.3). One trigger per look-away: it fires when the typewriter
## has been unseen for 6.0 s, or when the player has been more than 4.0 m away for 3.0 s
## continuously. It re-arms once the typewriter is in the frustum again.
class Trigger:
	extends RefCounted
	var latched := false
	var far_time := 0.0

	func step(delta: float, unseen: float, distance: float, in_frustum: bool) -> bool:
		if in_frustum:
			latched = false
		if distance > FAR_TRIGGER_M:
			far_time += delta
		else:
			far_time = 0.0
		if latched or in_frustum:
			return false
		if unseen >= UNSEEN_TRIGGER_S or far_time >= FAR_TRIGGER_S:
			latched = true
			return true
		return false


## The ghost state machine, with no nodes. update() takes plain numbers, so it can run
## under a test with a real TypewriterModel and fake camera values.
class Core:
	extends RefCounted
	var model = null  # TypewriterModel
	var day := 0
	var lines: Array = []
	var done := 0
	var running := false
	var line_active := false
	var typing_view := false
	var sheet_id := ""
	var trig := Trigger.new()
	var on_line_finished := Callable()

	func set_day(new_day: int, new_lines: Array, done_count: int) -> void:
		day = new_day
		lines = new_lines
		done = done_count
		line_active = false

	## Opening the typing view stops ghost writes at once, so no ghost glyph can land while
	## the player types, even before the next update.
	func set_typing_view(on: bool) -> void:
		if on and not typing_view:
			_stop(float(Time.get_ticks_msec()))
		typing_view = on

	## One frame. delta in seconds, now in ms. unseen and distance come from Gaze.
	func update(delta: float, now: float, unseen: float, distance: float, in_frustum: bool, removed: bool) -> void:
		if not _loaded_ghost():
			line_active = false
			running = false
			return
		_check_sheet()
		if typing_view:
			_stop(now)
			return
		if line_active and not model.ghost_pending():
			_finish_line(now)
		if in_frustum:
			_stop(now)
		var fired := trig.step(delta, unseen, distance, in_frustum)
		if removed:
			_stop(now)
			return
		if in_frustum or not fired:
			return
		if done >= lines.size():
			return
		if not line_active:
			_enqueue_line(now)
		_run(now)

	func _loaded_ghost() -> bool:
		return model != null and model.is_loaded() and String(model.original.get("kind", "")) == "ghost"

	func _check_sheet() -> void:
		var sid := String(model.original.get("id", ""))
		if sid != sheet_id:
			sheet_id = sid
			trig.latched = false
			line_active = false
			running = false

	## One X-out pass (spec 10.3, QUESTION-42), queued ahead of the next line: an X over each
	## cell the player typed since the previous pass, in reading order. The model records
	## player keys only, so ghost writes and ghost X glyphs are never player typing.
	func _enqueue_line(_now: float) -> void:
		var cells: Array = model.take_typed_cells()
		cells.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
		if not cells.is_empty():
			model.enqueue_ghost_x(cells)
		model.enqueue_ghost_text(String(lines[done]) + "\n")
		line_active = true

	func _run(now: float) -> void:
		if not running:
			model.ghost_set_running(true, now)
			running = true

	func _stop(now: float) -> void:
		if running:
			model.ghost_set_running(false, now)
			running = false

	func _finish_line(now: float) -> void:
		var index := done
		done += 1
		line_active = false
		_stop(now)
		if on_line_finished.is_valid():
			on_line_finished.call(index)


var _core := Core.new()
var _model = null
var _tw: Node3D = null


func setup(model, typewriter_node: Node3D) -> void:
	_model = model
	_tw = typewriter_node
	_core.model = model
	_core.on_line_finished = Callable(self, "_on_line_finished")
	var gaze = get_node_or_null("/root/Gaze")
	if gaze != null and _tw != null:
		gaze.track(_tw)


## The typewriter view calls this when the typing view opens (true) or closes (false).
func set_typing_view(on: bool) -> void:
	_core.set_typing_view(on)


## Plays the ghost-typed sounds of an event batch (spec 11.1): key_clack, bell and
## carriage_return at the typewriter, each with the -20 dB ghost gain.
func play_ghost_sounds(events: Array) -> void:
	if _tw == null:
		return
	var ad = get_node_or_null("/root/AudioDirector")
	if ad == null or not ad.has_method("play_ghost"):
		return
	for ev in events:
		if not bool(ev.get("ghost", false)):
			continue
		var sfx := ""
		match String(ev.get("t", "")):
			"key":
				sfx = "key_clack"
			"bell":
				sfx = "bell"
			"return":
				sfx = "carriage_return"
		if sfx != "":
			ad.call("play_ghost", sfx, _tw.global_position, true, 0.0)


func _process(delta: float) -> void:
	if _model == null or _tw == null:
		return
	var gs = get_node_or_null("/root/GameState")
	var gaze = get_node_or_null("/root/Gaze")
	if gs == null or gaze == null:
		return
	var day := int(gs.day)
	if day != _core.day:
		_core.set_day(day, _lines_for(day), int(gs.ghost_lines_done.get(str(day), 0)))
	var removed := bool(gs.ghost_sheet_removed_by_player.get(str(day), false))
	_core.update(delta, float(Time.get_ticks_msec()), gaze.unseen_time(_tw),
		gaze.distance_to_camera(_tw), gaze.is_in_frustum(_tw), removed)


func _lines_for(day: int) -> Array:
	var raw: Dictionary = Content.load_json("res://data/strings.json")
	var ghost: Dictionary = raw.get("ghost_lines", {})
	var tt = get_node_or_null("/root/TextTokens")
	var out: Array = []
	for line in ghost.get(str(day), []):
		out.append(tt.substitute(String(line)) if tt != null else String(line))
	return out


func _on_line_finished(index: int) -> void:
	var gs = get_node_or_null("/root/GameState")
	var dd = get_node_or_null("/root/DayDirector")
	if gs == null:
		return
	var day := int(gs.day)
	gs.ghost_lines_done[str(day)] = index + 1
	if dd != null:
		dd.call("ghost_line_finished", day, index)
