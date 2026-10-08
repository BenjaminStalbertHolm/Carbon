extends SceneTree
## Unit checks for the typewriter model (spec 7, 8.5, 8.8, 10.2, 10.3).
## Headless: godot --headless --path . --script res://tests/unit/test_typewriter.gd

const DocModel := preload("res://scripts/logic/doc_model.gd")
const CadenceModel := preload("res://scripts/logic/cadence_model.gd")
const TypewriterModel := preload("res://scripts/logic/typewriter_model.gd")

var _failures := 0
var _ran := false


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _check_eq(actual: Variant, expected: Variant, label: String) -> void:
	_check(actual == expected, label)
	if actual != expected:
		print("      expected: %s" % str(expected))
		print("      actual:   %s" % str(actual))


func _sheet(lines_text: Array) -> Dictionary:
	var d := DocModel.new_doc("T", "sheet")
	var p := DocModel.new_page()
	d.pages.append(p)
	return d


func _new_model(seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var cad := CadenceModel.new()
	var tw := TypewriterModel.new(cad, rng)
	return [tw, cad, rng]


func _run() -> void:
	var parts := _new_model(412)
	var tw: TypewriterModel = parts[0]
	var cad: CadenceModel = parts[1]
	var rng: RandomNumberGenerator = parts[2]

	# Typing and advancing (7.3).
	var doc := _sheet([])
	tw.load_sheet(doc, {})
	tw.type_key("a", 0.0)
	_check(DocModel.cell_char(doc.pages[0], 0, 0) == "A" and tw.col == 1, "lowercase is typed as uppercase and the carriage advances")
	tw.type_key("#", 10.0)
	_check(tw.col == 1, "characters outside the accepted set do nothing")
	var ev := tw.take_events()
	_check(ev.size() == 1 and ev[0].t == "key", "a typed key emits one key event")

	# Overstrike with the fourth glyph ignored (6.5).
	tw.col = 5
	tw.type_key("X", 20.0)
	tw.col = 5
	tw.type_key("Y", 30.0)
	tw.col = 5
	tw.type_key("Z", 40.0)
	tw.col = 5
	tw.type_key("W", 50.0)
	_check(DocModel.cell_char(doc.pages[0], 0, 5) == "Z" and doc.pages[0].cells["0:5"].g.size() == 3, "overstrike keeps 3 glyphs and the last is read")

	# Enter and line limits (7.4).
	tw.enter(100.0)
	_check(tw.line == 1 and tw.col == 0, "Enter returns the carriage and advances the line")
	tw.line = 53
	tw.enter(200.0)
	_check(tw.line == 53, "Enter at line 53 does nothing")
	tw.line = 0
	tw.col = 64
	tw.type_key("Q", 300.0)
	_check(DocModel.cell_char(doc.pages[0], 0, 63) == " ", "typing past column 63 does nothing")

	# Timing capture (10.1): 50 ms apart keeps the interval.
	var cad2 := CadenceModel.new()
	cad2.record("A", 0.0)
	cad2.record("B", 100.0)
	cad2.record("C", 4000.0)
	_check(cad2.intervals.size() == 1 and is_equal_approx(float(cad2.intervals[0]), 100.0), "gaps over 1500 ms are not recorded and intervals are kept")
	_check(cad2.bigram.has("AB"), "bigram recorded for the pair")

	# Carbon mirroring (8.5).
	var parts2 := _new_model(7)
	var tw2: TypewriterModel = parts2[0]
	var orig := _sheet([])
	var carb := DocModel.make_carbon(orig, "C")
	tw2.load_sheet(orig, carb)
	tw2.type_key("H", 0.0)
	tw2.type_key("I", 10.0)
	_check(DocModel.cell_char(carb.pages[0], 0, 0) == "H" and DocModel.cell_char(carb.pages[0], 0, 1) == "I", "carbon mirrors each glyph in the same cell")
	_check(String(carb.pages[0].cells["0:0"].g[0].ink) == "carbon", "carbon glyphs use carbon ink")
	tw2.col = 0
	tw2.fluid_at(0, 0, 20.0)
	_check(carb.pages[0].cells["0:0"].w and carb.pages[0].cells["0:0"].g.is_empty(), "correction fluid whites out the carbon too")

	# Correction fluid (7.6): uses and the 2 s cell lock.
	var parts3 := _new_model(9)
	var tw3: TypewriterModel = parts3[0]
	var doc3 := _sheet([])
	tw3.load_sheet(doc3, {})
	tw3.fluid_uses = 12
	_check(tw3.fluid_at(2, 2, 1000.0), "fluid can be used on any cell")
	_check(tw3.fluid_uses == 11, "fluid use decrements the count")
	tw3.line = 2
	tw3.col = 2
	tw3.type_key("A", 1500.0)
	_check(not DocModel.has_glyph(doc3.pages[0], 2, 2), "a cell refuses glyphs for 2.0 s after fluid")
	tw3.type_key("A", 3100.0)
	_check(DocModel.has_glyph(doc3.pages[0], 2, 2), "after drying, typing writes over the blob")
	tw3.fluid_uses = 0
	_check(not tw3.fluid_at(4, 4, 4000.0), "fluid with no uses left does nothing")

	# Forms (7.5): carriage starts in the first field, cannot pass its end.
	var parts4 := _new_model(11)
	var tw4: TypewriterModel = parts4[0]
	var form := _sheet([])
	DocModel.add_printed_lines(form.pages[0], ["1. FULL NAME", "   {{F1:4}}", "2. NEXT", "   {{F2:6}}"])
	tw4.load_sheet(form, {})
	_check(tw4.line == 1 and tw4.col == 3, "form carriage starts at the first field's first cell")
	for ch in "ABCDEF":
		tw4.type_key(ch, 0.0)
	_check(DocModel.field_value(form.pages[0], DocModel.field_by_id(form.pages[0], "F1")) == "ABCD", "form field takes only its own cells")
	tw4.enter(100.0)
	_check(tw4.line == 3 and tw4.col == 3, "Enter in a form moves to the next field")
	tw4.enter(200.0)
	_check(tw4.line == 3 and tw4.col == 3, "Enter from the last field does nothing")

	# Retired word (8.8): typing the fond word jams, locks for 3 s and X-outs.
	var parts5 := _new_model(13)
	var tw5: TypewriterModel = parts5[0]
	var doc5 := _sheet([])
	tw5.load_sheet(doc5, {})
	tw5.retired_active = true
	tw5.fond_word = "LANTERN"
	var t := 0.0
	for ch in "LANTERN":
		tw5.type_key(ch, t)
		t += 100.0
	tw5.take_events()
	tw5.type_key(" ", t)
	var jam_events := tw5.take_events()
	var has_jam := false
	for e in jam_events:
		if e.t == "jam":
			has_jam = true
	_check(has_jam or tw5.is_locked(t + 1.0), "typing the fond word then a space jams the typewriter")
	_check(tw5.is_locked(t + 1000.0), "input is locked for 3 s after the jam")
	tw5.tick(t + 2000.0)
	var xs := 0
	for e in tw5.take_events():
		if e.t == "key" and e.ch == "X":
			xs += 1
	_check(xs == 7, "each letter of the fond word is X-struck (found %d)" % xs)
	_check(doc5.pages[0].cells["0:0"].g.size() == 2 and doc5.pages[0].cells["0:0"].g[0].c == "L" and doc5.pages[0].cells["0:0"].g[1].c == "X", "X overstrikes the letter, which stays under it")
	_check(not tw5.is_locked(t + 3100.0), "lock ends after 3 s")

	# Ghost typing (10.2): runs only while started, resumes from the same character.
	var parts6 := _new_model(21)
	var tw6: TypewriterModel = parts6[0]
	var cad6: CadenceModel = parts6[1]
	var doc6 := _sheet([])
	tw6.load_sheet(doc6, {})
	tw6.enqueue_ghost_text("AB")
	tw6.ghost_set_running(false, 0.0)
	tw6.tick(10000.0)
	_check(not DocModel.has_glyph(doc6.pages[0], 0, 0), "ghost typing does not run while stopped")
	tw6.ghost_set_running(true, 10000.0)
	tw6.tick(10000.0 + 1000.0)
	_check(DocModel.cell_char(doc6.pages[0], 0, 0) == "A", "ghost typing types the first character when running")
	_check(tw6.ghost_pending(), "ghost typing keeps its place in the queue")
	tw6.ghost_set_running(false, 11000.0)
	tw6.tick(20000.0)
	_check(not DocModel.has_glyph(doc6.pages[0], 0, 1), "stopping mid-string leaves the rest untyped")

	# Day 5 name substitution (spec 14.12): the original shows H. VANCE, the carbon the typed name.
	var parts7 := _new_model(31)
	var tw7: TypewriterModel = parts7[0]
	var form7 := _sheet([])
	DocModel.add_printed_lines(form7.pages[0], ["1. FULL NAME", "   {{F1:24}}"])
	var carbon7 := DocModel.make_carbon(form7, "C7")
	tw7.load_sheet(form7, carbon7)
	tw7.field_substitution = {"F1": "H. VANCE"}
	var typed7 := "ANNA"
	for ch in typed7:
		tw7.type_key(ch, 0.0)
	var f7 := DocModel.field_by_id(form7.pages[0], "F1")
	_check_eq(DocModel.field_value(form7.pages[0], f7), "H. V", "original shows the first four characters of H. VANCE for four typed characters")
	_check_eq(DocModel.field_value(carbon7.pages[0], f7), "ANNA", "carbon shows exactly what the player typed")
	tw7.col = int(f7.col) + 8
	tw7.type_key("Z", 0.0)
	_check(not DocModel.has_glyph(form7.pages[0], int(f7.line), int(f7.col) + 8), "original renders nothing past the 8th substitute character")
	_check(DocModel.has_glyph(carbon7.pages[0], int(f7.line), int(f7.col) + 8), "carbon still records a character past the 8th")
	tw7.field_bar = {"F1": true}
	tw7.col = int(f7.col)
	tw7.type_key("Q", 0.0)
	_check(String(form7.pages[0].cells[DocModel.cell_key(int(f7.line), int(f7.col))].g[-1].c) == TypewriterModel.BAR_GLYPH, "with H. VANCE redacted, typed cells become solid bars on the original")

	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)
