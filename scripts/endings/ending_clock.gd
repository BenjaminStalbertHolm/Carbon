extends RefCounted
## Time source for the ending sequences (spec 15). Real mode awaits SceneTree timers.
## Virtual mode (tests) keeps its own clock: wait() moves time forward at once and calls
## on_advance(seconds), so a fake presentation can finish its typing. The sequences only use
## wait(), wait_until() and now(), so every timing check runs headless in a fraction of a second.

var virtual := false
var on_advance := Callable()
var _t := 0.0
var _tree: SceneTree = null


func _init(is_virtual: bool = false, tree: SceneTree = null) -> void:
	virtual = is_virtual
	_tree = tree


## Seconds on this clock.
func now() -> float:
	if virtual:
		return _t
	return Time.get_ticks_msec() / 1000.0


## Waits seconds. A zero or negative wait returns at once.
func wait(seconds: float) -> void:
	if seconds <= 0.0:
		return
	if virtual:
		_advance(seconds)
		return
	await _scene_tree().create_timer(seconds).timeout


## Waits until pred returns true. Virtual mode steps by step seconds, up to limit seconds, so a
## predicate that never becomes true cannot hang a test. Real mode checks once per frame.
func wait_until(pred: Callable, step: float = 0.02, limit: float = 600.0) -> void:
	var waited := 0.0
	if virtual:
		while not bool(pred.call()) and waited < limit:
			_advance(step)
			waited += step
		return
	while not bool(pred.call()):
		await _scene_tree().process_frame


func _advance(seconds: float) -> void:
	_t += seconds
	if on_advance.is_valid():
		on_advance.call(seconds)


func _scene_tree() -> SceneTree:
	if _tree == null:
		_tree = Engine.get_main_loop() as SceneTree
	return _tree
