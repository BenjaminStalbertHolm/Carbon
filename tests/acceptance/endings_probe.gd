extends RefCounted
## A presentation stand-in for EndingsController (spec 15) used by the acceptance tests. It records every call with
## the virtual time it was made (an EndingClock in virtual mode, so each sequence runs to its end inside the call that
## starts it). The controller connects each sequence signal to the method of the same name here. duplicate_hall_set
## also runs on a real EndingsPresentation when one is given, so the Desk 4 nameplate and the clerk are set by the
## scene code. Not a headless test (it does not extend SceneTree).
##   const Probe := preload("res://tests/acceptance/endings_probe.gd")

const CHAR_S := 0.15  # ghost typing speed of the probe: seconds per character

## Virtual clock (EndingClock) shared with the controller.
var clock = null
var log: Array = []
var paper := false  # a sheet is loaded in the typewriter
var ghost_end := 0.0
var crossed_at := INF  # time at which the player crosses z = 6.1 (spec 15.2 step 3)
var distance := 10.0  # the player's floor distance to the Desk 4 figure (spec 15.2 step 5)
var hall_pres = null  # an EndingsPresentation on a built hall, or null


func reset() -> void:
	log = []
	ghost_end = 0.0
	crossed_at = INF
	distance = 10.0


func _rec(fn: String, args: Array = []) -> void:
	log.append({"t": clock.now(), "name": fn, "args": args})


func times(fn: String) -> Array:
	var out: Array = []
	for e in log:
		if e.name == fn:
			out.append(float(e.t))
	return out


func args_of(fn: String) -> Array:
	var out: Array = []
	for e in log:
		if e.name == fn:
			out.append(e.args)
	return out


func has_called(fn: String) -> bool:
	return not times(fn).is_empty()


# --- Queries the sequences make ------------------------------------------------------------

func has_paper() -> bool:
	return paper


func ghost_idle() -> bool:
	return clock.now() >= ghost_end


func key_delay_ms(_prev: String, _ch: String) -> float:
	return CHAR_S * 1000.0


func player_crossed() -> bool:
	return clock.now() >= crossed_at


func figure_distance() -> float:
	return distance


# --- Actions (each one logged) -----------------------------------------------------------

func fixture_off(index: int) -> void:
	_rec("fixture_off", [index])


func fixture_on(index: int) -> void:
	_rec("fixture_on", [index])


func paper_ejected(player_caused: bool) -> void:
	_rec("paper_ejected", [player_caused])


func blank_sheet_loaded() -> void:
	_rec("blank_sheet_loaded")


func ghost_typed(text: String) -> void:
	_rec("ghost_typed", [text])
	ghost_end = clock.now() + text.length() * CHAR_S


func lamp_off() -> void:
	_rec("lamp_off")


func faded_to_black(seconds: float) -> void:
	_rec("faded_to_black", [seconds])


func faded_in(seconds: float) -> void:
	_rec("faded_in", [seconds])


func final_shot() -> void:
	_rec("final_shot")


func clerk_key(letter: String, delay_ms: float) -> void:
	_rec("clerk_key", [letter, delay_ms])


func cut_to_black() -> void:
	_rec("cut_to_black")


func title_typed(text: String, ms_per_char: float) -> void:
	_rec("title_typed", [text, ms_per_char])


func title_cleared() -> void:
	_rec("title_cleared")


func carbon_stack_moved() -> void:
	_rec("carbon_stack_moved")


func carbon_loaded() -> void:
	_rec("carbon_loaded")


func camera_to_typing(seconds: float) -> void:
	_rec("camera_to_typing", [seconds])


func camera_to_free(seconds: float) -> void:
	_rec("camera_to_free", [seconds])


func silence() -> void:
	_rec("silence")


func restore_record(desks: Array) -> void:
	_rec("restore_record", [desks])


func refusal_memo() -> void:
	_rec("refusal_memo")


func exit_unlocked() -> void:
	_rec("exit_unlocked")


func door_swing(seconds: float) -> void:
	_rec("door_swing", [seconds])


func door_rattle() -> void:
	_rec("door_rattle")


func duplicate_hall_set() -> void:
	_rec("duplicate_hall_set")
	if hall_pres != null:
		hall_pres.duplicate_hall_set()


## Stands in for the player: seated or standing (spec 15.3 needs seated).
class FakePlayer extends Node:
	var seated := true

	func is_seated() -> bool:
		return seated


## Stands in for the desk: the lower drawer is closed unless set open (spec 15.3).
class FakeDesk extends Node:
	var lower_open := false

	func drawer_open(_which: String) -> bool:
		return lower_open


## Stands in for the interaction node, which emits action_pressed on a click (spec 8.13).
class FakeInteraction extends Node:
	signal action_pressed(action: String, node: Variant, hit_position: Variant)
