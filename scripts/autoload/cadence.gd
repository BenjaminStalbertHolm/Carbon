extends Node
## Cadence: keystroke timing capture and ghost-typing delays (spec 10). Autoload.
## Wraps one CadenceModel. Save data is to_dict() / from_dict().
##
## Double-record guard: TypewriterModel.type_key() and enter() already record into the
## model it was given. If the typewriter view passes Cadence.model to TypewriterModel,
## a later record() call for the same key at the same time is skipped, so no key is
## counted twice. A typewriter built with its own CadenceModel is unaffected.

const CadenceModel := preload("res://scripts/logic/cadence_model.gd")

var model: CadenceModel = CadenceModel.new()


## Records one accepted player key (spec 10.1). ch is the character, or CadenceModel.ENTER.
func record(ch: String, now_ms: float) -> void:
	var key := ch if ch == CadenceModel.ENTER else ch.to_upper()
	if model._prev_ms == now_ms and model._prev_char == key:
		return
	model.record(key, now_ms)


## Delay in ms before typing ch after prev during ghost playback (spec 10.2).
func delay_for(prev: String, ch: String) -> float:
	var gs = get_node_or_null("/root/GameState")
	var rng: RandomNumberGenerator = gs.rng if gs != null else RandomNumberGenerator.new()
	return model.delay_for(prev, ch, rng)


func to_dict() -> Dictionary:
	return model.to_dict()


func from_dict(d: Dictionary) -> void:
	model.from_dict(d)
