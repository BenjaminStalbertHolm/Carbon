extends Node
## CarbonStackView: the carbon spot's filing action and hold pick-up (spec 6.4, 8.5).
## The stack's visuals are desk4_items.gd's (M3). This node does two things.
##
## Filing: with the lower drawer open, a click on the carbon spot moves every carbon on
## the spot into the drawer (DayDirector.file_carbons, 0.6 s, paper_shuffle, spec 8.5).
## Filed carbons leave the game overnight (DayDirector). Calls while a filing runs are
## ignored.
##
## Pick up: a hold on the carbon spot picks up the top carbon (GameState.loc.carbon_spot
## last element, spec 8.5 and QUESTION-8), which the player then moves to the read stack
## or the copyholder with the usual hand rules.
##
## Hooks (Callables, set by the main controller):
##   lower_drawer_open_fn: () -> bool
##   held_kind_fn: () -> String    ("" when the hand is empty)
##   held_hold_fn: (kind, id)      (puts an item in the hand)

const TypewriterSounds := preload("res://scripts/typewriter/typewriter_sounds.gd")

signal filed(count: int)

const FILE_MS := 600.0
## Carbon spot on Desk 4 (desk.gd: CarbonSpot at desk centre + (0.45, 0.74, 0.18)).
const SPOT_POS := Vector3(5.70, 0.76, 3.68)

var lower_drawer_open_fn := Callable()
var held_kind_fn := Callable()
var held_hold_fn := Callable()

var _sounds := TypewriterSounds.new()
var _busy_until := 0.0
var _clock := 0.0
var _fake := false


func _ready() -> void:
	_sounds.position = SPOT_POS


func _process(delta: float) -> void:
	if _fake:
		return
	_clock += delta * 1000.0


func use_fake_clock() -> void:
	_fake = true


func advance(ms: float) -> void:
	_clock += ms


func busy() -> bool:
	return _clock < _busy_until


## Click on the carbon spot. Files the carbons when the lower drawer is open and returns
## the number filed. Returns -1 when the drawer is shut (the caller opens read view).
func carbon_spot_clicked() -> int:
	if not _drawer_open():
		return -1
	return file_carbons()


## Files every carbon on the carbon spot (spec 8.5). Returns the number moved.
func file_carbons() -> int:
	if busy():
		return 0
	var dd = _autoload("DayDirector")
	if dd == null:
		return 0
	var moved: int = dd.file_carbons()
	_busy_until = _clock + FILE_MS
	_sounds.play("paper_shuffle", SPOT_POS, 0.0, true)
	filed.emit(moved)
	return moved


## Hold on the carbon spot: picks up the top carbon when the hand is empty. Returns its id,
## or "" when there is nothing to pick up.
func pick_up_top_carbon() -> String:
	if _held_kind() != "":
		return ""
	var gs = _autoload("GameState")
	if gs == null or gs.loc.carbon_spot.is_empty():
		return ""
	var id := String(gs.loc.carbon_spot[gs.loc.carbon_spot.size() - 1])
	gs.place(id, "hand")
	if held_hold_fn.is_valid():
		held_hold_fn.call("document", id)
	return id


func _drawer_open() -> bool:
	return bool(lower_drawer_open_fn.call()) if lower_drawer_open_fn.is_valid() else false


func _held_kind() -> String:
	return String(held_kind_fn.call()) if held_kind_fn.is_valid() else ""


func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
