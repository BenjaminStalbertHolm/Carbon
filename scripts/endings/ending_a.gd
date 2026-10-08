extends RefCounted
## Ending A, CONTINUITY (spec 15.1). A sequence only: it waits on the clock and emits one signal
## per visible or audible action. endings_presentation.gd carries the signals out. The ghost line
## is typed by the presentation's typewriter queue (spec 10.2); ghost_idle() reports when it is done.
##
## Setup order: setup(clock, lit, ghost_text, title_text, has_paper, ghost_idle, key_delay_ms, rng),
## then run(). lit maps "1".."6" to true for each fixture that is lit when the sequence starts.

signal fixture_off(index: int)
## player_caused is false here: the eject is scripted (QUESTION-68).
signal paper_ejected(player_caused: bool)
signal blank_sheet_loaded
signal ghost_typed(text: String)
signal lamp_off
signal faded_to_black(seconds: float)
signal final_shot
## The final shot comes in from black over FINAL_FADE_S (QUESTION-59).
signal faded_in(seconds: float)
signal clerk_key(letter: String, delay_ms: float)
signal cut_to_black
signal title_typed(text: String, ms_per_char: float)
signal title_cleared
signal set_input_mode(mode: String)
signal ending_set(id: String)
signal credits_requested

const FIXTURE_ORDER := [5, 6, 3, 4, 1, 2]
const FIRST_OFF_S := 3.0
const SWITCH_GAP_S := 2.0
const EJECT_S := 0.6
const PAPER_IN_S := 0.6
const LAMP_AFTER_TEXT_S := 3.0
const LAMP_HOLD_S := 2.0
const FADE_S := 2.0
const FINAL_FADE_S := 1.5
const FINAL_HOLD_S := 12.0
const TITLE_MS_PER_CHAR := 140.0
const TITLE_HOLD_S := 3.0
const STREAM_LETTERS := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

var clock = null
var lit := {}
var ghost_text := ""
var title_text := ""
var _has_paper := Callable()
var _ghost_idle := Callable()
var _key_delay := Callable()
var _rng: RandomNumberGenerator = null


func setup(clock_ref, lit_state: Dictionary, ghost_line: String, title_line: String, paper_loaded: Callable, idle: Callable, delay_ms: Callable, rng_ref: RandomNumberGenerator) -> void:
	clock = clock_ref
	lit = lit_state.duplicate()
	ghost_text = ghost_line
	title_text = title_line
	_has_paper = paper_loaded
	_ghost_idle = idle
	_key_delay = delay_ms
	_rng = rng_ref


## Runs the whole ending. The caller awaits it; credits_requested is the last signal.
func run() -> void:
	# Step 2: the lit fixtures go off in order, 2.0 s apart. Skipped ones take no time.
	await clock.wait(FIRST_OFF_S)
	for f in FIXTURE_ORDER:
		if not bool(lit.get(str(f), false)):
			continue
		lit[str(f)] = false
		fixture_off.emit(f)
		await clock.wait(SWITCH_GAP_S)
	# Step 3: 2.0 s after the last fixture, the loaded paper comes out and a blank sheet slides in.
	if bool(_has_paper.call()):
		paper_ejected.emit(false)
		await clock.wait(EJECT_S)
	blank_sheet_loaded.emit()
	await clock.wait(PAPER_IN_S)
	# Step 4: ghost-type the line, whether or not the typewriter is in view.
	ghost_typed.emit(ghost_text)
	await clock.wait_until(_ghost_idle)
	# Step 5: lamp off 3.0 s after the last character, hold, then fade to black.
	await clock.wait(LAMP_AFTER_TEXT_S)
	lamp_off.emit()
	await clock.wait(LAMP_HOLD_S)
	faded_to_black.emit(FADE_S)
	await clock.wait(FADE_S)
	# Step 6: final shot (input disabled), then 12.0 s of the Desk 4 clerk typing to ghost timing.
	set_input_mode.emit("off")
	final_shot.emit()
	faded_in.emit(FINAL_FADE_S)
	await _final_stream()
	# Step 7: cut to black, the title, hold, clear, then credits.
	cut_to_black.emit()
	title_typed.emit(title_text, TITLE_MS_PER_CHAR)
	await clock.wait(title_text.length() * TITLE_MS_PER_CHAR / 1000.0)
	await clock.wait(TITLE_HOLD_S)
	title_cleared.emit()
	ending_set.emit("A")
	credits_requested.emit()


## The clerk's keys during the final shot: an endless stream of random letters, each timed by the
## ghost delay (spec 10.2). The stream stops at the end of the 12.0 s hold.
func _final_stream() -> void:
	var end_t: float = clock.now() + FINAL_HOLD_S
	var prev := ""
	while clock.now() < end_t:
		var ch := STREAM_LETTERS.substr(_rng.randi_range(0, STREAM_LETTERS.length() - 1), 1)
		var ms := float(_key_delay.call(prev, ch))
		var delay := ms / 1000.0
		if clock.now() + delay > end_t:
			# The next key would land after the hold, so the hold ends first.
			await clock.wait(end_t - clock.now())
			break
		await clock.wait(delay)
		clerk_key.emit(ch, ms)
		prev = ch
	await clock.wait(end_t - clock.now())
