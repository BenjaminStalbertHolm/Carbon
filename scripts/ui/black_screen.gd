extends CanvasLayer
## BlackScreen (spec 13.1 day transition, 15.4 credits, 16.1 content note): a full
## window black layer with centred typed text and fades. Scene:
## scenes/ui/black_paper.tscn. Every timed step is a coroutine, so the caller
## awaits it:  await screen.run_day_title(day, new_game)
##
## Main controller order for a day (spec 13.1): run_day_title(), then the caller
## runs the overnight resolution and the autosave, then fade_in(2.0).

const Content := preload("res://scripts/logic/content.gd")
const TypedText := preload("res://scripts/ui/typed_text.gd")

const INK := Color("#C8C2AE")
const FADE_S := 2.0
const HOLD_BEFORE_S := 1.0
const HOLD_AFTER_S := 2.0
const DAY_FONT_SIZE := 40
const DAY_MS_PER_CHAR := 140

signal day_title_finished(day: int)

var _shade: ColorRect
var _text: Control


func _ready() -> void:
	layer = 100
	_shade = ColorRect.new()
	_shade.color = Color.BLACK
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)
	_text = TypedText.new()
	add_child(_text)


## Sets the opacity of the black overlay at once (1.0 is fully black).
func set_shade(alpha: float) -> void:
	_shade.modulate.a = alpha


## Coroutine: tweens the overlay's opacity over seconds.
func fade_to(alpha: float, seconds: float) -> void:
	if seconds <= 0.0 or not is_inside_tree():
		set_shade(alpha)
		return
	var tween := create_tween()
	tween.tween_property(_shade, "modulate:a", alpha, seconds)
	await tween.finished


## Coroutine: fades the black overlay out (the player is seated, spec 13.1 step 7).
func fade_in(seconds: float = FADE_S) -> void:
	await fade_to(0.0, seconds)


## Coroutine: types lines centred, in INK.
func type_lines(lines: Array, font_size: int, ms_per_char: int, clack: bool) -> void:
	await _text.type_lines(lines, font_size, INK, ms_per_char, clack)


func fast_forward() -> void:
	_text.fast_forward()


func is_typing() -> bool:
	return _text.is_typing()


func clear_text() -> void:
	_text.clear_text()


## Coroutine: waits seconds.
func hold(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


## Spec 13.1 steps 1 to 4. At a new game the caller passes new_game = true: the
## screen is already black, and the sequence starts at step 3 (spec 16.2), so the
## fade and the first hold are skipped. The overnight resolution, the autosave and
## the fade in belong to the caller.
func run_day_title(day: int, new_game: bool) -> void:
	if new_game:
		set_shade(1.0)
	else:
		await fade_to(1.0, FADE_S)
		await hold(HOLD_BEFORE_S)
	var title := String(Content.strings().day_titles[str(day)])
	await type_lines([title], DAY_FONT_SIZE, DAY_MS_PER_CHAR, true)
	await hold(HOLD_AFTER_S)
	clear_text()
	day_title_finished.emit(day)
