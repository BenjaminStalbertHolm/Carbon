extends RefCounted
## Ending C, CARBON (spec 15.3). A sequence only: it waits on the clock and emits one signal per
## visible or audible action. Setup: setup(clock, lines, restore_desks, lit, paper_loaded,
## ghost_idle, end_line). lines are the ghost lines from endings.gd (ending_c_lines). restore_desks
## are the desk numbers from endings.gd (desks_to_restore). lit maps "1".."6" to the lit state.

signal paper_ejected
signal carbon_stack_moved
signal carbon_loaded
signal camera_to_typing(seconds: float)
signal ghost_typed(text: String)
signal silence
signal restore_record(desks: Array)
signal fixture_on(index: int)
signal camera_to_free(seconds: float)
signal set_input_mode(mode: String)
signal faded_to_black(seconds: float)
signal title_typed(text: String, ms_per_char: float)
signal title_cleared
signal ending_set(id: String)
signal credits_requested

const TRAVEL_S := 0.8
const PAPER_IN_S := 0.6
const CAMERA_IN_S := 0.5
const AFTER_TEXT_S := 1.0
const FIXTURE_GAP_S := 1.5
const FIXTURE_ORDER := [2, 1, 4, 3, 6, 5]
const CAMERA_FREE_S := 0.8
const LOOK_HOLD_S := 20.0
const FADE_S := 4.0
const END_HOLD_S := 4.0
const TITLE_MS_PER_CHAR := 140.0

var clock = null
var lines: Array = []
var restore: Array = []
var lit := {}
var _paper_loaded := false
var _ghost_idle := Callable()
var end_line := ""


func setup(clock_ref, ghost_lines: Array, desks: Array, lit_state: Dictionary, has_paper: bool, idle: Callable, title_line: String) -> void:
	clock = clock_ref
	lines = ghost_lines.duplicate()
	restore = desks.duplicate()
	lit = lit_state.duplicate()
	_paper_loaded = has_paper
	_ghost_idle = idle
	end_line = title_line


## Runs the whole ending after the carbon stack is clicked while seated (spec 15.3).
func run() -> void:
	set_input_mode.emit("off")
	# Step 1: a loaded paper comes out, the carbon stack travels 0.8 s and loads (paper_in).
	if _paper_loaded:
		paper_ejected.emit()
	carbon_stack_moved.emit()
	await clock.wait(TRAVEL_S)
	carbon_loaded.emit()
	await clock.wait(PAPER_IN_S)
	# Step 2: the camera tweens to the typing view pose.
	camera_to_typing.emit(CAMERA_IN_S)
	await clock.wait(CAMERA_IN_S)
	# Step 3: the record, one line per entry, typed on the carbon's top sheet.
	var text := ""
	for i in range(lines.size()):
		text += ("\n" if i > 0 else "") + String(lines[i])
	ghost_typed.emit(text)
	await clock.wait_until(_ghost_idle)
	# Step 4: the room goes silent. Only player-caused sounds remain.
	silence.emit()
	# Step 5: the redacted desks and clerks return, through the unseen rule.
	restore_record.emit(restore)
	# Step 6: unlit fixtures switch on one at a time, 1.0 s after the silence.
	await clock.wait(AFTER_TEXT_S)
	for f in FIXTURE_ORDER:
		if bool(lit.get(str(f), false)):
			continue
		lit[str(f)] = true
		fixture_on.emit(f)
		await clock.wait(FIXTURE_GAP_S)
	# Step 7: the camera returns to the seated free view. Looking only.
	camera_to_free.emit(CAMERA_FREE_S)
	set_input_mode.emit("look_only")
	await clock.wait(CAMERA_FREE_S)
	# Step 8: 20.0 s later, fade, the last line, hold, clear, credits.
	await clock.wait(LOOK_HOLD_S)
	set_input_mode.emit("off")
	faded_to_black.emit(FADE_S)
	await clock.wait(FADE_S)
	title_typed.emit(end_line, TITLE_MS_PER_CHAR)
	await clock.wait(end_line.length() * TITLE_MS_PER_CHAR / 1000.0)
	await clock.wait(END_HOLD_S)
	title_cleared.emit()
	ending_set.emit("C")
	credits_requested.emit()
