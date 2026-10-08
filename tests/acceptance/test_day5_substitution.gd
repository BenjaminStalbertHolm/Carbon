extends SceneTree
## Acceptance test 7 (spec 20): the Day 5 name substitution on P-1D field F1 (spec 14.12). The run is the one of
## test 2 up to Day 5 (the refusal run), with RO-3 either leaving H. VANCE unredacted, or redacting him. On Day 5 the
## player types a name into P-1D field F1 through the real TypewriterModel, with the Day 5 settings DayDirector gives
## the typewriter (sheet_options). Checked:
##   - the form arrives with its carbon attached (spec 14.4: "pre-assembled with a carbon");
##   - the original shows H. VANCE in the typed cells, one character per cell, for the first 8 typed characters, and
##     nothing after them (spec 14.12);
##   - with H. VANCE redacted on RO-3, every typed cell of the original is a solid bar (spec 14.12);
##   - the carbon shows exactly what was typed, in both runs;
##   - the carbon leaves with the form when the form is removed (spec 7.7).
## The look of the bars and of the letters on screen is MANUAL, see tests/ACCEPTANCE.md.
## Headless:
##   godot --headless --path . --script res://tests/acceptance/test_day5_substitution.gd
## Prints one PASS or FAIL line per check, then "RESULT: PASS, N failure(s)". Exit 0 only when N is 0.

const Play := preload("res://tests/acceptance/playthrough_helpers.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")

const FORM := "P-1D"
const SUBSTITUTE := "H. VANCE"
const BAR := "█"

var _checks := 0
var _failures := 0
var _ran := false
var _gs
var _dd


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
	_gs = root.get_node("GameState")
	_dd = root.get_node("DayDirector")

	# Variant A: H. VANCE is not redacted on RO-3, so the original shows his name.
	var plain := _day5_form(false)
	_check(plain.carbon_ok, "test 7: P-1D arrives with its carbon attached (spec 14.4: pre-assembled with a carbon)")
	_check(plain.opts_sub == SUBSTITUTE and not plain.opts_bar,
		"test 7: the Day 5 options substitute H. VANCE in field 1, with no bars, when H. VANCE was not redacted")
	var sub_ok := true
	for k in range(Play.NAME.length()):
		var want := SUBSTITUTE.substr(k, 1) if k < SUBSTITUTE.length() else " "
		if String(plain.original[k]) != want:
			sub_ok = false
	_check(sub_ok, "test 7: the original shows H. VANCE, the k-th typed character showing the k-th letter, and nothing past 8 (got %s)" % str(plain.original))
	_check(plain.carbon == Array(Play.NAME.split("")), "test 7: the carbon shows exactly what was typed (got %s)" % str(plain.carbon))
	_check(plain.carbon_at_spot, "test 7: the carbon goes to the carbon spot with the form (spec 7.7)")

	# Variant B: H. VANCE is redacted on RO-3, so every typed cell of the original is a bar.
	var barred := _day5_form(true)
	_check(barred.opts_bar and barred.opts_sub == SUBSTITUTE,
		"test 7: with H. VANCE redacted, the Day 5 options give field 1 bars (spec 14.12)")
	var all_bars := true
	for k in range(Play.NAME.length()):
		if String(barred.original[k]) != BAR:
			all_bars = false
	_check(all_bars, "test 7: with H. VANCE redacted, every typed cell of the original is a solid bar (got %s)" % str(barred.original))
	_check(barred.carbon == Array(Play.NAME.split("")), "test 7: the carbon still shows what was typed, under the bars")

	print("ACCEPTANCE TEST 7 (Day 5 substitution): %d checks, %d failure(s)" % [_checks, _failures])
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


## Days 1 to 4 as the refusal run (RO-3 redacts H. VANCE only when redact_vance), then Day 5's P-1D: the player types
## the name in field 1 and removes the form. Returns the characters read back from the original and the carbon.
func _day5_form(redact_vance: bool) -> Dictionary:
	var run := Play.new(_gs, _dd)
	run.run_days_1_to_4(false, ["H. VANCE"] if redact_vance else [])
	_dd.tick(5.0)  # the P-1D canister arrives
	var carbon_ok := false
	var carbon_id := String(_gs.docs.get(FORM, {}).get("twin", ""))
	if carbon_id != "" and _gs.docs.has(carbon_id):
		var c: Dictionary = _gs.docs[carbon_id]
		carbon_ok = bool(c.carbon) and String(c.origin) == FORM
	var opts: Dictionary = _dd.sheet_options(FORM)
	var sub := String(opts.get("field_substitution", {}).get("F1", ""))
	var bar := bool(opts.get("field_bar", {}).get("F1", false))

	run.load_sheet(FORM)
	var page: Dictionary = _gs.docs[FORM].pages[0]
	var field := DocModel.field_by_id(page, "F1")
	run.tw.click_cell(int(field.line), int(field.col), run.now)
	run.type_text(Play.NAME)

	var original: Array = []
	for k in range(Play.NAME.length()):
		original.append(DocModel.cell_char(page, int(field.line), int(field.col) + k))
	var carbon: Array = []
	if carbon_ok:
		var cpage: Dictionary = _gs.docs[carbon_id].pages[0]
		for k in range(Play.NAME.length()):
			carbon.append(DocModel.cell_char(cpage, int(field.line), int(field.col) + k))

	run.remove_and_send(FORM)
	var at_spot: bool = carbon_ok and String(_gs.location_of(carbon_id)) == "carbon_spot"
	return {
		"carbon_ok": carbon_ok,
		"opts_sub": sub,
		"opts_bar": bar,
		"original": original,
		"carbon": carbon,
		"carbon_at_spot": at_spot,
	}
