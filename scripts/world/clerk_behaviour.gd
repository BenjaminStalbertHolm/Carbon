extends Node
## Clerk behaviour (spec 5.4, 8.9, 4.6). Drives the 11 typing clerk figures built by
## hall_c.gd (Clerk01..Clerk11, no Clerk04). Responsibilities:
##   - the 15 fps typing animation (4 hand poses, random offset per clerk; hands only),
##   - the ambient typing sound (key_clack and carriage_return, positional at the typewriter),
##   - the watched freeze from Day 2 (a looked-at clerk freezes; resumes 0.5 s after),
##   - unison typing after F-3 (flags.unison_typing): one timing source, one pose, and
##     one freeze for all clerks when any one is looked at,
##   - refused clerks (GameState.clerk_faces_player) excluded from typing and freezing,
##   - apply_day_state(day): day-start rotations, redacted removals and nameplates. Only
##     called during the black day-transition screen, never in view.
##
## Usage (the lead): var cb := ClerkBehaviour.new(); add_child(cb); cb.setup(hall_root);
## then cb.apply_day_state(day) during the transition.

const FPS := 15.0
const HAND_OFFSET := 0.02
const RESUME_S := 0.5
const KEY_DB := -34.0
const CR_DB := -32.0
const FREEZE_FROM_DAY := 2
const TYPING_DESKS := [1, 2, 3, 5, 6, 7, 8, 9, 10, 11]
## Hand offsets per pose A, B, C, D (spec 5.4): A left down / right up, C right down / left up.
const LEFT_OFFS := [-0.02, 0.0, 0.02, 0.0]
const RIGHT_OFFS := [0.02, 0.0, -0.02, 0.0]

var _hall: Node3D = null
var _clerks := {}  # desk number -> state dictionary
var _unison_stream := {}
var _unison_on := false
var _unison_frozen := false
var _unison_resume := 0.0
var _t := 0.0
var _fallback_rng := RandomNumberGenerator.new()


func setup(hall_root: Node3D) -> void:
	_hall = hall_root
	_clerks.clear()
	var gaze = get_node_or_null("/root/Gaze")
	for desk in TYPING_DESKS:
		var fig = _hall.get_node_or_null("Clerk%02d" % desk)
		var tw = _hall.get_node_or_null("Typewriter%02d" % desk)
		var chair = _hall.get_node_or_null("Chair%02d" % desk)
		if fig == null or tw == null:
			continue
		var hand_l = fig.get_node_or_null("HandL")
		var hand_r = fig.get_node_or_null("HandR")
		if hand_l == null or hand_r == null:
			continue
		if chair != null:
			fig.set_meta("gaze_own", [chair])
		if gaze != null:
			gaze.track(fig)
		_clerks[desk] = {
			"desk": desk, "fig": fig, "tw": tw, "hand_l": hand_l, "hand_r": hand_r,
			"rest_l": hand_l.position, "rest_r": hand_r.position,
			"offset": _rnd().randi_range(0, 3), "frozen": false, "resume": 0.0,
			"stream": _new_stream(),
		}
	_unison_stream = _new_stream()


func _process(delta: float) -> void:
	if _hall == null:
		return
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	var gaze = get_node_or_null("/root/Gaze")
	_t += delta
	var freeze_on: bool = int(gs.day) >= FREEZE_FROM_DAY
	var unison: bool = bool(gs.flags.get("unison_typing", false))
	if unison and not _unison_on:
		_unison_on = true
		_unison_stream = _new_stream()
		for desk in _clerks:
			_clerks[desk]["offset"] = 0
			_clerks[desk]["frozen"] = false
	elif not unison:
		_unison_on = false
	var step := int(floor(_t * FPS))
	var active := _active_states(gs)
	if unison:
		_run_unison(active, step, delta, freeze_on, gaze)
	else:
		for st in active:
			var looked: bool = freeze_on and gaze != null and gaze.is_looked_at(st["fig"])
			if looked:
				st["frozen"] = true
				st["resume"] = 0.0
			elif st["frozen"]:
				st["resume"] = float(st["resume"]) + delta
				if float(st["resume"]) >= RESUME_S:
					st["frozen"] = false
			if not st["frozen"]:
				_set_pose(st, (int(st["offset"]) + step) % 4)
				_stream_run(st["stream"], delta, [st])


## Spec 8.9 day-start state. Rotates refused clerks to face Desk 4, removes redacted
## clerks (figure and chair; the whole desk on Day 5), and syncs every nameplate with
## GameState.nameplate. Idempotent.
func apply_day_state(_day: int) -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null or _hall == null:
		return
	for desk in range(1, 13):
		var key := str(desk)
		if desk == 4 or desk == 12:
			continue
		if bool(gs.desk_removed.get(key, false)):
			for n in ["Desk%02d", "Typewriter%02d", "Tube%02d", "Chair%02d", "Clerk%02d"]:
				_remove_named(n % desk)
			_clerks.erase(desk)
			continue
		if not bool(gs.clerk_present.get(key, false)):
			_remove_named("Clerk%02d" % desk)
			_remove_named("Chair%02d" % desk)
			_clerks.erase(desk)
			continue
		if bool(gs.clerk_faces_player.get(key, false)):
			var fig = _hall.get_node_or_null("Clerk%02d" % desk)
			if fig != null:
				fig.set_facing_player()
	var un = get_node_or_null("/root/UnseenChanges")
	if un != null:
		for desk in range(1, 13):
			if _hall.get_node_or_null("Desk%02d" % desk) != null:
				un.call("set_nameplate_visual", desk, String(gs.nameplate.get(str(desk), "")))


func _run_unison(active: Array, step: int, delta: float, freeze_on: bool, gaze) -> void:
	var any_looked := false
	if freeze_on and gaze != null:
		for st in active:
			if gaze.is_looked_at(st["fig"]):
				any_looked = true
	if any_looked:
		_unison_frozen = true
		_unison_resume = 0.0
	elif _unison_frozen:
		_unison_resume += delta
		if _unison_resume >= RESUME_S:
			_unison_frozen = false
	if not freeze_on:
		_unison_frozen = false
	if _unison_frozen or active.is_empty():
		return
	for st in active:
		_set_pose(st, step % 4)
	_stream_run(_unison_stream, delta, active)


func _active_states(gs) -> Array:
	var out: Array = []
	for desk in _clerks:
		var st: Dictionary = _clerks[desk]
		if bool(gs.clerk_faces_player.get(str(desk), false)):
			continue
		if not is_instance_valid(st["fig"]) or not st["fig"].is_inside_tree():
			continue
		out.append(st)
	return out


func _set_pose(st: Dictionary, pose: int) -> void:
	st["hand_l"].position = st["rest_l"] + Vector3(0.0, LEFT_OFFS[pose], 0.0)
	st["hand_r"].position = st["rest_r"] + Vector3(0.0, RIGHT_OFFS[pose], 0.0)


## One stream of keystrokes (spec 8.9): intervals of 90 to 260 ms, a 1.5 to 4.0 s pause
## every 20 to 60 keystrokes, and a carriage_return every 40 to 64 keystrokes. Each
## keystroke sounds at every typewriter in descs (more than one only in unison).
func _stream_run(stream: Dictionary, delta: float, descs: Array) -> void:
	stream["t"] = float(stream["t"]) - delta
	while float(stream["t"]) <= 0.0:
		stream["n"] = int(stream["n"]) + 1
		for st in descs:
			_play("key_clack", st["tw"].global_position, KEY_DB)
		if int(stream["n"]) >= int(stream["cr_at"]):
			for st in descs:
				_play("carriage_return", st["tw"].global_position, CR_DB)
			stream["cr_at"] = int(stream["n"]) + _rnd().randi_range(40, 64)
		if int(stream["n"]) >= int(stream["pause_at"]):
			stream["t"] = float(stream["t"]) + _rnd().randf_range(1.5, 4.0)
			stream["pause_at"] = int(stream["n"]) + _rnd().randi_range(20, 60)
		else:
			stream["t"] = float(stream["t"]) + _rnd().randf_range(0.090, 0.260)


func _new_stream() -> Dictionary:
	return {
		"t": _rnd().randf_range(0.090, 0.260),
		"n": 0,
		"pause_at": _rnd().randi_range(20, 60),
		"cr_at": _rnd().randi_range(40, 64),
	}


func _remove_named(node_name: String) -> void:
	var n = _hall.get_node_or_null(node_name)
	if n == null:
		return
	var gaze = get_node_or_null("/root/Gaze")
	if gaze != null:
		gaze.untrack(n)
	_hall.remove_child(n)
	n.queue_free()


func _rnd() -> RandomNumberGenerator:
	var gs = get_node_or_null("/root/GameState")
	if gs != null and gs.rng != null:
		return gs.rng
	return _fallback_rng


func _play(sfx: String, pos: Vector3, gain_db: float) -> void:
	var ad = get_node_or_null("/root/AudioDirector")
	if ad != null and ad.has_method("play"):
		ad.call("play", sfx, pos, true, gain_db, false)
