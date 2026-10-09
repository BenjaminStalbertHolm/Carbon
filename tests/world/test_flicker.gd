extends SceneTree
## Headless checks for the fixture flicker (spec 8.12) and REDUCE FLICKER (spec 16.3, 17).
## The pattern of every fixture on every day is compared with the pattern table in
## CARBON_SPEC.md, read at run time. Also checked: 10 steps per second on a fixed clock, the
## loop, the values applied to the light and the tube, REDUCE FLICKER, the held state and
## an off fixture.
## Run: godot --headless --path /home/user/Carbon --script res://tests/world/test_flicker.gd
## Prints one PASS or FAIL line per check, then "FLICKER: N checks, M failures".
## Exit code 0 only when every check passes.

const Hall := preload("res://scripts/world/hall_c.gd")
const Fixture := preload("res://scripts/world/fixture.gd")

const SPEC_PATH := "res://CARBON_SPEC.md"
const STEP := 0.1
const SAMPLES := 30
const EPS := 0.0001

var _checks := 0
var _failures := 0
var _letters_ok := true
var _gs = null
var _ss = null
var _holder: Node3D = null


func _initialize() -> void:
	call_deferred("_run")


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


func _run() -> void:
	_gs = root.get_node("GameState")
	_ss = root.get_node("SaveSystem")
	var orig_day: int = _gs.day
	var orig_reduce: bool = bool(_ss.get_setting("reduce_flicker"))
	_holder = Node3D.new()
	_holder.name = "FlickerTestHolder"
	root.add_child(_holder)
	var hall: Node = Hall.build(_holder, {})
	_ss.set_setting("reduce_flicker", false)

	var spec := _spec_patterns()
	_check(spec.size() == 6, "spec 8.12 table: 6 flicker pattern rows read from CARBON_SPEC.md (got %d)" % spec.size())
	_check_hall(hall)
	_check_sequences(spec)
	_check_loops(spec)
	_check(_letters_ok, "every multiplier sampled is 1.00, 0.55 or 0.25")
	_check_clock()
	_check_applied(spec)
	_check_reduce()
	_check_held_and_off(spec)

	_gs.day = orig_day
	_ss.set_setting("reduce_flicker", orig_reduce)
	print("FLICKER: %d checks, %d failures" % [_checks, _failures])
	quit(0 if _failures == 0 else 1)


## "day:fixture" -> pattern string, from the flicker table in spec 8.12.
func _spec_patterns() -> Dictionary:
	var out := {}
	var f := FileAccess.open(SPEC_PATH, FileAccess.READ)
	if f == null:
		return out
	var re := RegEx.new()
	re.compile("\\|\\s*(\\d+)\\s*\\|\\s*F(\\d)\\s*\\|\\s*`([mkh]+)`\\s*\\|")
	while not f.eof_reached():
		var m := re.search(f.get_line())
		if m != null:
			out["%s:%s" % [m.get_string(1), m.get_string(2)]] = m.get_string(3)
	f.close()
	return out


func _check_hall(hall: Node) -> void:
	var drivers := true
	var base := true
	for i in range(1, 7):
		var light := hall.get_node_or_null("Fixture%d" % i) as OmniLight3D
		if light == null or Fixture.driver_of(light) == null:
			drivers = false
		elif absf(light.light_energy - 1.2) > EPS:
			base = false
	_check(drivers, "Hall C: Fixture1 to Fixture6 each have a Flicker driver")
	_check(base, "Hall C: every fixture starts at its base energy 1.2")


## Multiplier letter of a value; any value other than 1.00, 0.55 or 0.25 clears _letters_ok.
func _letter_of(m: float) -> String:
	if absf(m - 1.0) < EPS:
		return "m"
	if absf(m - 0.55) < EPS:
		return "k"
	if absf(m - 0.25) < EPS:
		return "h"
	_letters_ok = false
	return "?"


## Letters of the multipliers at steps 0 to count-1 of a fresh fixture on a day, one 0.1 s step
## per sample, through the driver's own advance.
func _sample(index: int, day: int, count: int) -> String:
	var light: OmniLight3D = Fixture.build(_holder, index, Vector2.ZERO)
	var driver = Fixture.driver_of(light)
	_gs.day = day
	var out := ""
	for i in count:
		out += _letter_of(driver.multiplier())
		driver.advance(STEP)
	return out


func _check_sequences(spec: Dictionary) -> void:
	for day in range(1, 6):
		for index in range(1, 7):
			var pat: String = spec.get("%d:%d" % [day, index], "m")
			var want := ""
			for s in SAMPLES:
				want += pat.substr(s % pat.length(), 1)
			var got := _sample(index, day, SAMPLES)
			var label := "day %d F%d: steps 0 to 29 match the spec pattern" % [day, index]
			if got != want:
				label += " (got %s, want %s)" % [got, want]
			_check(got == want, label)


func _check_loops(spec: Dictionary) -> void:
	var bad := ""
	for key in spec:
		var parts: PackedStringArray = String(key).split(":")
		var pat: String = spec[key]
		var n := pat.length()
		var got := _sample(int(parts[1]), int(parts[0]), 2 * n + 7)
		var want := ""
		for s in got.length():
			want += pat.substr(s % n, 1)
		if got != want and bad == "":
			var at := 0
			while at < got.length() and got[at] == want[at]:
				at += 1
			bad = "day %s F%s differs at step %d" % [parts[0], parts[1], at]
	_check(bad == "", "each spec pattern loops: two full loops plus 7 steps repeat the string" + ("" if bad == "" else " (" + bad + ")"))


func _check_clock() -> void:
	_gs.day = 2
	var light: OmniLight3D = Fixture.build(_holder, 4, Vector2.ZERO)
	var driver = Fixture.driver_of(light)
	var frame := 1.0 / 60.0
	for i in 180:
		driver._process(frame)
	_check(driver.step_index() == 30, "clock: 3.0 s of fixed 1/60 s frames gives 30 steps (got %d)" % driver.step_index())


func _check_applied(spec: Dictionary) -> void:
	_gs.day = 2
	var pat: String = spec["2:4"]
	var light: OmniLight3D = Fixture.build(_holder, 4, Vector2.ZERO)
	var driver = Fixture.driver_of(light)
	for i in 31:
		driver.advance(STEP)
	var tube := light.get_node("Tube") as MeshInstance3D
	var emission := float((tube.material_override as ShaderMaterial).get_shader_parameter("emission_strength"))
	var mult := Fixture.multiplier_for(pat, driver.step_index())
	_check(pat.substr(31, 1) == "k", "day 2 F4: the spec pattern dips to k at step 31")
	_check(absf(light.light_energy - 1.2 * mult) < EPS, "day 2 F4 at step 31: light energy is 1.2 x 0.55 (got %f)" % light.light_energy)
	_check(absf(emission - 1.0 * mult) < EPS, "day 2 F4 at step 31: tube emission is 1.0 x 0.55 (got %f)" % emission)


func _check_reduce() -> void:
	_ss.set_setting("reduce_flicker", true)
	var ok := true
	for day in range(1, 6):
		for index in range(1, 7):
			if _sample(index, day, SAMPLES) != "m".repeat(SAMPLES):
				ok = false
	_check(ok, "REDUCE FLICKER on: every fixture is at 1.00 for 30 steps on days 1 to 5")
	_gs.day = 2
	var light: OmniLight3D = Fixture.build(_holder, 4, Vector2.ZERO)
	var driver = Fixture.driver_of(light)
	for i in 31:
		driver.advance(STEP)
	_check(absf(light.light_energy - 1.2) < EPS, "REDUCE FLICKER on: day 2 F4 at step 31 stays at energy 1.2")
	_ss.set_setting("reduce_flicker", false)


func _check_held_and_off(spec: Dictionary) -> void:
	_gs.day = 2
	var light: OmniLight3D = Fixture.build(_holder, 4, Vector2.ZERO)
	var driver = Fixture.driver_of(light)
	Fixture.set_held(light, true)
	var held_ok := true
	for i in SAMPLES:
		if absf(driver.multiplier() - 1.0) > EPS:
			held_ok = false
		driver.advance(STEP)
	_check(held_ok, "a held fixture is at 1.00 for 30 steps")
	Fixture.set_held(light, false)
	var pat: String = spec["2:4"]
	var want := Fixture.multiplier_for(pat, driver.step_index())
	_check(absf(driver.multiplier() - want) < EPS, "a released fixture follows its pattern again")
	light.visible = false
	light.light_energy = 0.0
	driver.advance(STEP * 3.0)
	_check(light.light_energy == 0.0, "an off fixture (visible false) is not lit by the flicker")
