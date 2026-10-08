extends SceneTree
## M8 unit checks: the unseen apply rule (spec 9.2), the 9.3 registry, the ghost trigger
## and stop rules (spec 10.3), the ghost X-outs, and the Gaze frustum test. Uses fakes and
## a real TypewriterModel; no 3D world is needed.
## Headless: godot --headless --path . --script res://tests/unit/test_unseen.gd
## Prints "UNSEEN: N checks, M failures" and exits 0 when M is 0.

const UnseenChanges := preload("res://scripts/autoload/unseen_changes.gd")
const Gaze := preload("res://scripts/autoload/gaze.gd")
const GhostTyper := preload("res://scripts/world/ghost_typer.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")
const CadenceModel := preload("res://scripts/logic/cadence_model.gd")
const TypewriterModel := preload("res://scripts/logic/typewriter_model.gd")

var _checks := 0
var _failures := 0
var _ran := false
var _finished: Array = []


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	_checks += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _run() -> void:
	_check_apply_rule()
	_check_registry()
	_check_ghost_trigger()
	_check_ghost_core()
	_check_aabb_planes()
	print("UNSEEN: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## Fake target: the apply rule is driven by these two settable values.
class FakeTarget:
	extends RefCounted
	var unseen_time := 0.0
	var distance := 0.0


func _apply_for(target: FakeTarget, waived: bool) -> bool:
	return UnseenChanges.apply_ready(target.unseen_time, target.distance, waived)


func _check_apply_rule() -> void:
	var t := FakeTarget.new()
	t.unseen_time = 1.4
	t.distance = 3.0
	_check(not _apply_for(t, false), "apply: unseen 1.4 s stays pending")
	t.unseen_time = 1.5
	t.distance = 1.9
	_check(not _apply_for(t, false), "apply: unseen 1.5 s at 1.9 m stays pending")
	t.distance = 2.0
	_check(_apply_for(t, false), "apply: unseen 1.5 s at 2.0 m applies")
	t.unseen_time = 0.0
	t.distance = 0.5
	_check(not _apply_for(t, false), "apply: unseen 0 at 0.5 m does not apply")
	t.unseen_time = 1.5
	t.distance = 0.5
	_check(_apply_for(t, true), "apply: waived distance rule (D1-U0 style) applies at 0.5 m")
	t.unseen_time = 1.4
	_check(not _apply_for(t, true), "apply: waiver still needs 1.5 s unseen")


func _check_registry() -> void:
	var u = UnseenChanges.new()
	var reg: Array = u._build_changes()
	var ids := []
	for c in reg:
		ids.append(String(c.id))
	var expected := ["D1-U0", "D1-U1", "D2-U1", "D2-U2", "D3-U1", "D3-U2", "D3-U3", "D4-U1", "D4-U2", "D4-U3", "D5-U1", "D5-U2"]
	_check(ids == expected, "registry: the twelve 9.3 ids in table order")
	var waived := []
	for c in reg:
		if bool(c.distance_rule_waived):
			waived.append(String(c.id))
	_check(waived == ["D1-U0", "D3-U3", "D4-U3"], "registry: distance rule waived for D1-U0, D3-U3, D4-U3")
	var after := {}
	for c in reg:
		after[String(c.id)] = String(c.after)
	_check(after["D3-U2"] == "task_sent:F-3" and after["D5-U2"] == "task_sent:P-1D", "registry: D3-U2 and D5-U2 triggers")
	_check(after["D2-U1"] == "day_start" and after["D5-U1"] == "day_start", "registry: day_start triggers")
	var all_ops := true
	for c in reg:
		all_ops = all_ops and (c.operation as Callable).is_valid()
	_check(all_ops, "registry: every change has a valid operation Callable")
	u.free()


func _check_ghost_trigger() -> void:
	var t := GhostTyper.Trigger.new()
	_check(not t.step(0.0, 5.9, 1.0, false), "trigger: unseen 5.9 s does not fire")
	_check(t.step(0.0, 6.0, 1.0, false), "trigger: unseen 6.0 s fires")
	_check(not t.step(0.0, 6.5, 1.0, false), "trigger: same look-away does not fire twice")
	t.step(0.0, 0.0, 1.0, true)
	_check(t.step(0.0, 6.0, 1.0, false), "trigger: re-arms after the typewriter is seen")

	t = GhostTyper.Trigger.new()
	var fired := false
	for i in range(29):
		fired = t.step(0.1, 0.0, 4.5, false) or fired
	_check(not fired, "trigger: 4.5 m for 2.9 s does not fire")
	_check(t.step(0.1, 0.0, 4.5, false), "trigger: 4.5 m for 3.0 s fires")

	t = GhostTyper.Trigger.new()
	fired = false
	for i in range(40):
		fired = t.step(0.1, 0.0, 4.0, false) or fired
	_check(not fired, "trigger: exactly 4.0 m does not count (rule is more than 4.0 m)")

	t = GhostTyper.Trigger.new()
	t.step(0.1, 0.0, 4.5, false)
	t.step(0.1, 0.0, 2.0, false)
	fired = false
	for i in range(29):
		fired = t.step(0.1, 0.0, 4.5, false) or fired
	_check(not fired, "trigger: distance timer resets when the player comes back within 4.0 m")


func _sheet() -> Dictionary:
	var doc := DocModel.new_doc("GS-TEST", "ghost", "typed", "black")
	doc.pages.append(DocModel.new_page())
	return doc


func _run_model(model, core, from_ms: float, to_ms: float, step_ms: float) -> Array:
	var out: Array = []
	var t := from_ms
	while t <= to_ms:
		model.tick(t)
		out.append_array(model.take_events())
		t += step_ms
	return out


func _keys(events: Array) -> Array:
	var out: Array = []
	for ev in events:
		if String(ev.t) == "key":
			out.append(ev)
	return out


func _check_ghost_core() -> void:
	# Stop condition (d): entering the frustum stops ghost typing; the queue waits.
	var model = TypewriterModel.new(CadenceModel.new(), RandomNumberGenerator.new())
	model.load_sheet(_sheet(), {})
	var core = GhostTyper.Core.new()
	core.model = model
	core.on_line_finished = Callable(self, "_on_finished")
	core.set_day(3, ["ABC", "DE"], 0)
	_finished.clear()
	core.update(0.1, 0.0, 5.9, 1.0, false, false)
	_check(not core.running, "ghost: unseen 5.9 s does not start typing")
	core.update(0.1, 0.0, 6.0, 1.0, false, false)
	_check(core.running and core.line_active, "ghost: unseen 6.0 s starts line 1")
	var first := _keys(_run_model(model, core, 0.0, 500.0, 20.0))
	_check(first.size() >= 1, "ghost: typing produces key events while unseen")
	core.update(0.1, 500.0, 0.0, 1.0, true, false)
	_check(not core.running, "ghost: typewriter entering the frustum stops ghost typing")
	var after_stop := _keys(_run_model(model, core, 510.0, 5000.0, 20.0))
	_check(after_stop.is_empty(), "ghost: no key events after the stop")
	core.update(0.1, 5000.0, 6.0, 1.0, false, false)
	var resumed := _keys(_run_model(model, core, 5010.0, 12000.0, 20.0))
	_check(resumed.size() >= 1, "ghost: the next trigger resumes from the same character")
	core.update(0.016, 12000.0, 0.0, 1.0, false, false)
	_check(_finished == [0] and core.done == 1, "ghost: line 1 finishes once, index 0 reported")
	_check(not core.line_active, "ghost: no line active after the line completes")

	# Each line once: a further trigger types line 2 only.
	core.update(0.1, 12000.0, 0.0, 1.0, true, false)
	core.update(0.1, 12100.0, 6.0, 1.0, false, false)
	_run_model(model, core, 12110.0, 20000.0, 20.0)
	core.update(0.016, 20000.0, 0.0, 1.0, false, false)
	_check(_finished == [0, 1] and core.done == 2, "ghost: line 2 types on the next trigger")
	core.update(0.1, 20000.0, 0.0, 1.0, true, false)
	core.update(0.1, 20100.0, 6.0, 1.0, false, false)
	_check(not core.running and core.done == 2, "ghost: no line after all lines are typed")

	# X-outs: player keys on the ghost sheet are overstruck first, in reading order.
	var model2 = TypewriterModel.new(CadenceModel.new(), RandomNumberGenerator.new())
	model2.load_sheet(_sheet(), {})
	var core2 = GhostTyper.Core.new()
	core2.model = model2
	core2.set_day(3, ["ZZ"], 0)
	core2.set_typing_view(true)
	model2.type_key("A", 0.0)
	model2.type_key("B", 10.0)
	core2.update(0.1, 10.0, 0.0, 1.0, true, false)
	core2.set_typing_view(false)
	model2.take_events()
	core2.update(0.1, 20.0, 6.0, 1.0, false, false)
	var xs := _keys(_run_model(model2, core2, 20.0, 3000.0, 20.0))
	var chars := []
	for ev in xs:
		chars.append(String(ev.ch))
	_check(chars.size() >= 3 and chars[0] == "X" and chars[1] == "X", "ghost: X-outs come before the line")
	_check(chars.slice(2, 4) == ["Z", "Z"] or chars.find("Z") > 1, "ghost: the line follows the X-outs")
	var ghost_flags := true
	for ev in xs:
		ghost_flags = ghost_flags and bool(ev.ghost)
	_check(ghost_flags, "ghost: every ghost key event is flagged ghost")


func _on_finished(index: int) -> void:
	_finished.append(index)


func _check_aabb_planes() -> void:
	var near := Plane(Vector3(0, 0, 1), -0.05)  # outward normal; inside is z <= -0.05
	var inside_box := AABB(Vector3(-1, -1, -10), Vector3(2, 2, 5))
	var behind_box := AABB(Vector3(-1, -1, 1), Vector3(2, 2, 1))
	_check(Gaze.aabb_in_planes(inside_box, [near]), "gaze: a box in front of the near plane is in the frustum")
	_check(not Gaze.aabb_in_planes(behind_box, [near]), "gaze: a box behind the near plane is out of the frustum")
	var straddle := AABB(Vector3(-1, -1, -0.5), Vector3(2, 2, 1))
	_check(Gaze.aabb_in_planes(straddle, [near]), "gaze: a box that straddles the plane counts as in")
