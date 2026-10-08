extends SceneTree
## Acceptance runner (spec 20, milestone M11). It finds every headless test under tests/ at run time,
## runs each as its own Godot process, runs tools/check_text.py (spec test 13), and prints one PASS,
## FAIL or MANUAL line per spec test 1 to 13. MANUAL means the automated part passed and a human step
## is still needed (see tests/acceptance/ACCEPTANCE.md). Exit 0 only when every automatable test passes.
##   godot --headless --path . --script res://tests/acceptance/acceptance_runner.gd

const TIMEOUT_S := 600
const CHECK_TEXT := "tools/check_text.py"

## Spec 20 tests. "auto" lists headless tests (paths under tests/) that must pass. "manual" is the step
## a human still does. A spec test with no manual step and every auto test passing is PASS.
const SPEC := [
	{"n": 1, "title": "Compliant run",
		"auto": ["unit/test_playthrough_compliant.gd", "unit/test_playthrough_day1.gd", "unit/test_acceptance_logic.gd"],
		"manual": "final shot on screen (fixtures, desks 7 and 8, nameplate 0413) and Ending A played"},
	{"n": 2, "title": "Refusal run with carbons",
		"auto": ["endings/endings_test.gd", "unit/test_acceptance_logic.gd", "unit/test_logic.gd"],
		"manual": "on-screen carbon stack to Ending C, and the figure at Desk 7 turning to Desk 4"},
	{"n": 3, "title": "Refusal run without carbons",
		"auto": ["endings/endings_test.gd", "player/hooks_test.gd"],
		"manual": "exit leads to Ending B on screen, and the duplicate hall shows the typed name at Desk 4"},
	{"n": 4, "title": "Mixed run for the Ending C list",
		"auto": ["unit/test_acceptance_logic.gd", "world/room_test.gd", "endings/endings_test.gd"],
		"manual": "silence after typing, seen and heard, on screen"},
	{"n": 5, "title": "Retired word",
		"auto": ["unit/test_acceptance_logic.gd", "unit/test_typewriter.gd"],
		"manual": "the jam and the X-out seen and heard when LANTERN is typed on Day 3"},
	{"n": 6, "title": "Defaults",
		"auto": ["unit/test_acceptance_logic.gd"],
		"manual": ""},
	{"n": 7, "title": "Day 5 substitution",
		"auto": ["acceptance/test_spec_extras.gd"],
		"manual": "the carbon shows the typed name, and the original shows H. VANCE on screen"},
	{"n": 8, "title": "Unseen rule",
		"auto": ["unit/test_unseen.gd"],
		"manual": "60 s stare at Desk 12 in play; the Desk 12 apparition, door silhouette and clock revert are not automated (see ACCEPTANCE.md)"},
	{"n": 9, "title": "Ghost typing",
		"auto": ["unit/test_typewriter.gd"],
		"manual": "look away for 6 s on Day 3 in play (depends on Gaze, not wired in main.gd)"},
	{"n": 10, "title": "Free mail",
		"auto": ["unit/test_acceptance_logic.gd", "tube/m6_test.gd"],
		"manual": ""},
	{"n": 11, "title": "No startle audit",
		"auto": ["unit/test_audio.gd", "unit/test_unseen.gd"],
		"manual": "zero loudness violations over a full playthrough (no test runs the checker over one)"},
	{"n": 12, "title": "Save and continue",
		"auto": ["unit/test_save.gd", "acceptance/test_spec_extras.gd"],
		"manual": "quit from the title and continue on a real window"},
	{"n": 13, "title": "Text fidelity",
		"auto": [CHECK_TEXT],
		"manual": ""},
]

var _godot := ""
var _project := ""
var _results := {}  # relative path under tests/ (or CHECK_TEXT) -> {status, detail}
var _order := PackedStringArray()


func _initialize() -> void:
	_godot = OS.get_executable_path()
	_project = ProjectSettings.globalize_path("res://").rstrip("/")
	var tests: Array = []
	_collect("res://tests", tests)
	tests.sort()
	print("ACCEPTANCE RUNNER: %d headless test file(s) found under tests/" % tests.size())
	for path in tests:
		var rel: String = String(path).trim_prefix("res://tests/")
		_run_test(rel, path)
	_run_check_text()
	_report()


## Headless tests: test_*.gd, *_test.gd and tests/run_tests.gd that extend SceneTree. Shot scripts
## (visual captures that need a window) and scene-based scripts are not headless tests.
func _collect(dir: String, out: Array) -> void:
	var da := DirAccess.open(dir)
	if da == null:
		return
	da.list_dir_begin()
	var name := da.get_next()
	while name != "":
		var path := dir + "/" + name
		if da.current_is_dir():
			if not name.begins_with("."):
				_collect(path, out)
		elif _is_headless_test(name, path):
			out.append(path)
		name = da.get_next()
	da.list_dir_end()


func _is_headless_test(name: String, path: String) -> bool:
	if not name.ends_with(".gd") or name.contains("shot"):
		return false
	if not (name.begins_with("test_") or name.ends_with("_test.gd") or name == "run_tests.gd"):
		return false
	return FileAccess.get_file_as_string(path).contains("extends SceneTree")


func _run_test(rel: String, path: String) -> void:
	var args := PackedStringArray(["--headless", "--path", _project, "--script", path])
	var res := _exec(_godot, args)
	var text: String = res.text
	var summary := ""
	var failed := false
	for line in text.split("\n"):
		var l := line.strip_edges()
		if l.begins_with("FAIL") or l.contains("SCRIPT ERROR") or l.contains("Parse Error") or l.contains("Compile Error"):
			failed = true
		if l.contains("RESULT:") or l.contains("checks") or l.contains("failed") or l.contains("failure(s)"):
			summary = l
	if int(res.code) != 0:
		failed = true
	_results[rel] = {"status": "FAIL" if failed else "PASS", "detail": "exit %d: %s" % [int(res.code), summary if summary != "" else "no summary line"]}
	_order.append(rel)
	print("%s  tests/%s  (%s)" % [_results[rel].status, rel, _results[rel].detail])


func _run_check_text() -> void:
	var script := _project + "/" + CHECK_TEXT
	var res := _exec("python3", PackedStringArray([script]))
	var text: String = res.text
	var line := ""
	for l in text.split("\n"):
		if l.contains("TEXT FIDELITY:"):
			line = l.strip_edges()
	var ok := int(res.code) == 0 and line.contains(", 0 failed")
	_results[CHECK_TEXT] = {"status": "PASS" if ok else "FAIL", "detail": line if line != "" else "no TEXT FIDELITY line (exit %d)" % int(res.code)}
	_order.append(CHECK_TEXT)
	print("%s  %s  (%s)" % [_results[CHECK_TEXT].status, CHECK_TEXT, _results[CHECK_TEXT].detail])


## Runs one command, under timeout when it exists, and returns its exit code and output.
func _exec(program: String, args: PackedStringArray) -> Dictionary:
	var output: Array = []
	var code := 0
	if FileAccess.file_exists("/usr/bin/timeout"):
		var timed := PackedStringArray(["--kill-after=15", str(TIMEOUT_S), program])
		timed.append_array(args)
		code = OS.execute("/usr/bin/timeout", timed, output, true)
	else:
		code = OS.execute(program, args, output, true)
	return {"code": code, "text": "\n".join(PackedStringArray(output))}


func _report() -> void:
	var auto_fail := 0
	for rel in _order:
		if _results[rel].status != "PASS":
			auto_fail += 1
	print("")
	print("SPEC 20 TESTS")
	var spec_fail := 0
	var spec_manual := 0
	var spec_pass := 0
	for spec in SPEC:
		var missing := PackedStringArray()
		var failing := PackedStringArray()
		for rel in spec.auto:
			if not _results.has(rel):
				missing.append(String(rel))
			elif _results[rel].status != "PASS":
				failing.append(String(rel))
		var status := "PASS"
		var note := "automated: %d file(s) passing" % spec.auto.size()
		if not missing.is_empty() or not failing.is_empty():
			status = "FAIL"
			note = "failing or missing: %s" % ", ".join(missing + failing)
		elif String(spec.manual) != "":
			status = "MANUAL"
			note = "automated part passes; manual: %s" % String(spec.manual)
		match status:
			"PASS":
				spec_pass += 1
			"MANUAL":
				spec_manual += 1
			_:
				spec_fail += 1
		print("%-6s  spec test %2d  %s  |  %s" % [status, int(spec.n), String(spec.title), note])
	print("")
	var all_pass := auto_fail == 0 and spec_fail == 0
	print("SUMMARY: %d headless test(s) and text check, %d not passing; spec tests: %d PASS, %d MANUAL, %d FAIL" % [
		_order.size(), auto_fail, spec_pass, spec_manual, spec_fail])
	print("ACCEPTANCE RUNNER RESULT: %s" % ("PASS" if all_pass else "FAIL"))
	quit(0 if all_pass else 1)
