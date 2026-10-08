extends SceneTree
## Wiring checks (spec 9.1, 9.2, 10.2, 11.4, 6.4). Boots the real main scene (scenes/main.tscn, the script
## scripts/main.gd) with the front end off, starts a new game, runs the real day-end transition into Day 2,
## and checks that the systems the game uses are connected:
##   - Gaze has the player's camera, and tracks Desk 12;
##   - the unseen registry is bound to the hall;
##   - positional audio is under the pipeline's world, and the SubViewport is the 3D listener;
##   - a day start applies the Day 2 change (spec 9.3 D2-U1: the Desk 12 nameplate reads 0411);
##   - the ghost typer exists, watches the typewriter and holds the typewriter view's model;
##   - a ghost sheet placed on the typewriter loads into that model (spec 10.2).
## Headless:
##   godot --headless --path . --script res://tests/acceptance/test_wiring.gd
## Prints one PASS or FAIL line per check, then "WIRING: N checks, M failure(s)". Exit 0 only when M is 0.

const MAIN_SCENE := preload("res://scenes/main.tscn")
const UNSEEN_DAY2 := "D2-U1"
const DAY2_NAMEPLATE := "0411"
const SETTLE_FRAMES := 6
const TRANSITION_TIMEOUT_S := 60.0

var _main
var _gs
var _dd
var _un
var _step := 0
var _frames := 0
var _waited := 0.0
var _checks := 0
var _failures := 0


func _process(delta: float) -> bool:
	_frames += 1
	match _step:
		0:
			_boot()
			_step = 1
		1:
			if _frames >= SETTLE_FRAMES:
				_check_wiring()
				_check_day_one_state()
				_begin_day_two()
				_step = 2
		2:
			_waited += delta
			if _waited > TRANSITION_TIMEOUT_S:
				_check(false, "the day transition to Day 2 finishes within %d s" % int(TRANSITION_TIMEOUT_S))
				_step = 3
			elif bool(_main.is_running_for_check()):
				_check_day_two()
				_step = 3
		3:
			_check_ghost_sheet_loads()
			_finish()
			return true
	return false


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _boot() -> void:
	_main = MAIN_SCENE.instantiate()
	_main.auto_boot = false
	root.add_child(_main)
	_gs = root.get_node("GameState")
	_dd = root.get_node("DayDirector")
	_un = root.get_node("UnseenChanges")
	_main.debug_start_game(4242)
	_main.debug_run(true)


func _check_wiring() -> void:
	var gaze = root.get_node("Gaze")
	var player_camera: Camera3D = _main.player.camera()
	_check(player_camera != null and gaze.get("_camera") == player_camera,
		"the gaze has the player's camera")

	var desk12: Node = _main.hall.find_child("Desk12", true, false)
	var tracked: Array = gaze.get("_tracked")
	_check(desk12 != null and tracked.has(desk12), "the gaze tracks Desk 12")

	_check(_un.get("_hall") == _main.hall, "the unseen registry is bound to the hall")

	var audio = root.get_node("AudioDirector")
	_check(audio.spatial_parent() == _main.pipeline.world,
		"the audio spatial parent is the pipeline world")

	var listener := false
	for child in _main.pipeline.get_children():
		if child is SubViewport:
			listener = bool((child as SubViewport).audio_listener_enable_3d)
	_check(listener, "the pipeline SubViewport is the 3D audio listener")

	var ghost = _main.ghost_typer
	_check(ghost != null and ghost.get("_model") == _main.typewriter.model,
		"the ghost typer exists and holds the typewriter view's model")
	_check(ghost != null and ghost.get("_tw") == _main.typewriter_node and _main.typewriter_node.name == "Typewriter04",
		"the ghost typer watches Typewriter04")


func _check_day_one_state() -> void:
	_check(_gs.day == 1 and String(_gs.nameplate.get("12", "")) != DAY2_NAMEPLATE,
		"Day 1: the Desk 12 nameplate is not yet %s" % DAY2_NAMEPLATE)
	_check(not _applied(UNSEEN_DAY2), "Day 1: the D2-U1 change is not applied")


## The real day-end path: the lamp leads to end_day(), the transition runs (flush, overnight, day start), and
## the player is back in play on Day 2.
func _begin_day_two() -> void:
	_dd.end_day()


func _check_day_two() -> void:
	_check(_gs.day == 2, "the transition starts Day 2")
	_check(String(_gs.nameplate.get("12", "")) == DAY2_NAMEPLATE,
		"Day 2 start applies the unseen change: the Desk 12 nameplate reads %s (spec 9.3 D2-U1)" % DAY2_NAMEPLATE)
	_check(_applied(UNSEEN_DAY2), "Day 2 start marks D2-U1 applied in the registry")
	var desk12: Node = _main.hall.find_child("Desk12", true, false)
	_check(desk12 != null and desk12.get_node_or_null("Nameplate") != null,
		"the Desk 12 nameplate is built in the hall")


## Spec 10.2: a ghost sheet that arrives on the typewriter is loaded into the view's model, so that the ghost
## typer can write on it. Day 2 has no ghost lines, so the typing itself does not start here.
func _check_ghost_sheet_loads() -> void:
	var sheet_id: String = String(_dd.apply_ghost_sheet(2))
	_check(sheet_id != "", "a ghost sheet can be placed on the empty typewriter")
	_check(_main.typewriter.loaded_doc_id() == sheet_id and _main.typewriter.model.is_loaded(),
		"the ghost sheet loads into the typewriter view's model")
	_check(String(_main.typewriter.model.original.get("kind", "")) == "ghost",
		"the loaded sheet is the ghost sheet")


func _applied(id: String) -> bool:
	for row in _un.status():
		if String(row.id) == id:
			return bool(row.applied)
	return false


func _finish() -> void:
	print("WIRING: %d checks, %d failure(s)" % [_checks, _failures])
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
