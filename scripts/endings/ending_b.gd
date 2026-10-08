extends RefCounted
## Refusal and Ending B, DUPLICATE (spec 15.2). Three coroutine entry points:
##   run_refusal()  5.0 s after RO-5 is sent: the refusal memo arrives and the exit unlocks, together.
##   run_exit()     the exit handle is clicked while standing: swing, walk through z = 6.1, the
##                  duplicate hall, and the end (steps 2 to 6).
## Setup: setup(clock, end_line, player_crossed, figure_distance). player_crossed() is true once the
## camera is past z = 6.1 inside the doorway. figure_distance() gives metres to the Desk 4 figure.

signal refusal_memo
signal exit_unlocked
signal door_swing(seconds: float)
signal faded_to_black(seconds: float)
signal faded_in(seconds: float)
signal duplicate_hall_set
signal set_input_mode(mode: String)
signal title_typed(text: String, ms_per_char: float)
signal title_cleared
signal ending_set(id: String)
signal credits_requested

const REFUSAL_DELAY_S := 5.0
const SWING_S := 1.2
const WALK_FADE_S := 1.5
const FADE_IN_S := 1.5
const NEAR_FIGURE_M := 2.5
const WAIT_LIMIT_S := 180.0
const END_FADE_S := 3.0
const END_HOLD_S := 4.0
const TITLE_MS_PER_CHAR := 140.0

var clock = null
var end_line := ""
var _player_crossed := Callable()
var _figure_distance := Callable()
var _walk_start := 0.0


func setup(clock_ref, end_text: String, crossed: Callable, distance: Callable) -> void:
	clock = clock_ref
	end_line = end_text
	_player_crossed = crossed
	_figure_distance = distance


## Step 1: the memo and the unlock arrive together, 5.0 s after RO-5.
func run_refusal() -> void:
	await clock.wait(REFUSAL_DELAY_S)
	refusal_memo.emit()
	exit_unlocked.emit()


## Steps 2 to 6, from the exit handle click on.
func run_exit() -> void:
	door_swing.emit(SWING_S)
	await clock.wait(SWING_S)
	await clock.wait_until(_player_crossed)
	set_input_mode.emit("off")
	faded_to_black.emit(WALK_FADE_S)
	await clock.wait(WALK_FADE_S)
	await _duplicate_hall()


func _duplicate_hall() -> void:
	duplicate_hall_set.emit()
	faded_in.emit(FADE_IN_S)
	await clock.wait(FADE_IN_S)
	set_input_mode.emit("walk_look")
	_walk_start = clock.now()
	await clock.wait_until(_near_or_timeout)
	set_input_mode.emit("off")
	faded_to_black.emit(END_FADE_S)
	await clock.wait(END_FADE_S)
	title_typed.emit(end_line, TITLE_MS_PER_CHAR)
	await clock.wait(end_line.length() * TITLE_MS_PER_CHAR / 1000.0)
	await clock.wait(END_HOLD_S)
	title_cleared.emit()
	ending_set.emit("B")
	credits_requested.emit()


## The end of the walk: within 2.5 m of the Desk 4 figure, or 180 s after the fade-in.
func _near_or_timeout() -> bool:
	if clock.now() - _walk_start >= WAIT_LIMIT_S:
		return true
	return float(_figure_distance.call()) <= NEAR_FIGURE_M
