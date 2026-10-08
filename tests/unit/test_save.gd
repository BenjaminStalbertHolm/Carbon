extends SceneTree
## Unit checks for the save system (spec 16.3, 16.4). Headless:
##   godot --headless --path . --script res://tests/unit/test_save.gd
## Exit code 0 means every check passed. Scratch files are user:// test files, which
## are deleted at the end.

const SaveSystemScript := preload("res://scripts/autoload/save_system.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")

const TEST_SAVE := "user://test_save.json"
const TEST_SETTINGS := "user://test_settings.cfg"

var _failures := 0
var _ran := false


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run()
		print("RESULT: %s (%d failures)" % ["PASS" if _failures == 0 else "FAIL", _failures])
		quit(1 if _failures > 0 else 0)
	return false


func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _run() -> void:
	var gs = root.get_node("GameState")
	_remove_test_files()

	var save = SaveSystemScript.new()
	save.save_path = TEST_SAVE
	save.settings_path = TEST_SETTINGS

	# (a) Round trip: day, tokens, a document's glyph cells, and the RNG state.
	gs.new_game(412)
	gs.day = 3
	gs.tokens_set = true
	gs.player_name_raw = "ADA LOVELACE"
	gs.fond_word = "QUIET"
	var doc := DocModel.new_doc("TEST-SHEET", "sheet")
	var page := DocModel.new_page()
	doc.pages.append(page)
	var rng: RandomNumberGenerator = gs.rng
	for i in range(5):
		DocModel.write_glyph(page, 1, i, "ABCDE".substr(i, 1), rng)
	gs.add_doc(doc, "inbox")
	rng.randi()
	var cells_before: Dictionary = page.cells.duplicate(true)
	_check(save.save_game(), "save_game writes the slot")
	var expected_next: int = rng.randi()

	gs.new_game(7)
	_check(save.has_save(), "has_save is true for a valid slot")
	_check(save.load_game(), "load_game returns true")
	_check(int(gs.day) == 3, "day round-trips (3)")
	_check(bool(gs.tokens_set) and String(gs.player_name_raw) == "ADA LOVELACE", "tokens round-trip")
	_check(String(gs.fond_word) == "QUIET", "fond word round-trips")
	_check(gs.docs.has("TEST-SHEET"), "document round-trips into GameState.docs")
	var cells_after: Dictionary = gs.docs["TEST-SHEET"].pages[0].cells
	_check(_same_cells(cells_before, cells_after), "document glyph cells round-trip")
	_check(gs.location_of("TEST-SHEET") == "inbox", "document location round-trips (inbox)")
	_check(int(gs.rng.randi()) == expected_next, "RNG state round-trips")
	_check(int(save.saved_day()) == 3, "saved_day reads the day from the slot")

	# Save file carries the version.
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	_check(parsed is Dictionary and int(parsed.get("version", -1)) == 1, "slot holds \"version\": 1")

	# (b) Corrupt and wrong-version slots count as no save.
	_write_text(TEST_SAVE, "{ this is not json")
	_check(not save.has_save(), "corrupt JSON: has_save is false")
	_check(not save.load_game(), "corrupt JSON: load_game is false")
	var good: Dictionary = gs.to_dict()
	good.version = 999
	_write_text(TEST_SAVE, JSON.stringify(good))
	_check(not save.has_save(), "wrong version: has_save is false")
	_check(not save.load_game(), "wrong version: load_game is false")
	var missing: Dictionary = gs.to_dict()
	missing.erase("docs")
	_write_text(TEST_SAVE, JSON.stringify(missing))
	_check(not save.has_save(), "missing key: has_save is false")
	_check(not save.load_game(), "missing key: load_game is false")
	_check(not save.has_save() and save.saved_day() == 0, "no valid save: saved_day is 0")

	# (c) Settings persist at once, and read back in a new object.
	_check(save.save_game(), "slot rewritten after the corruption checks")
	_check(save.has_save(), "has_save is true again after a valid save")
	_check(bool(save.get_setting("dither")) and not bool(save.get_setting("internal_high")), "defaults before any change")
	_check(save.set_setting("mouse_sensitivity", 1.4), "set_setting writes the file")
	save.set_setting("invert_mouse_y", true)
	save.set_setting("master_volume", 50)
	save.set_setting("dither", false)
	save.set_setting("internal_high", true)
	save.set_setting("mouse_sensitivity", 9.0)
	var reread = SaveSystemScript.new()
	reread.settings_path = TEST_SETTINGS
	reread.load_settings()
	_check(is_equal_approx(float(reread.get_setting("mouse_sensitivity")), 2.0), "mouse sensitivity read back (clamped to 2.0)")
	_check(bool(reread.get_setting("invert_mouse_y")), "invert_mouse_y read back (ON)")
	_check(int(reread.get_setting("master_volume")) == 50, "master_volume read back (50)")
	_check(not bool(reread.get_setting("dither")), "dither read back (OFF)")
	_check(bool(reread.get_setting("internal_high")), "internal_high read back (HIGH)")
	_check(not bool(reread.get_setting("fullscreen")), "untouched setting keeps its default")
	_check(not save.set_setting("no_such_key", 1), "unknown setting key is refused")
	reread.free()

	# (d) delete_save removes the slot.
	save.delete_save()
	_check(not FileAccess.file_exists(TEST_SAVE), "delete_save removes the file")
	_check(not save.has_save(), "has_save is false after delete_save")

	# Restore the in-game defaults for the other autoloads, then clean up.
	save.set_setting("mouse_sensitivity", 0.6)
	save.set_setting("invert_mouse_y", false)
	save.set_setting("master_volume", 80)
	save.set_setting("dither", true)
	save.set_setting("internal_high", false)
	save.free()
	_remove_test_files()


## JSON has one number type, so an int field comes back as a float with the same
## value (for example a cell's ws). Numbers compare by value, to 1e-9.
func _same_cells(a: Variant, b: Variant) -> bool:
	var numeric := [TYPE_INT, TYPE_FLOAT]
	if numeric.has(typeof(a)) and numeric.has(typeof(b)):
		return absf(float(a) - float(b)) < 1e-9
	if typeof(a) != typeof(b):
		return false
	if typeof(a) == TYPE_DICTIONARY:
		if a.size() != b.size():
			return false
		for key in a.keys():
			if not b.has(key) or not _same_cells(a[key], b[key]):
				return false
		return true
	if typeof(a) == TYPE_ARRAY:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _same_cells(a[i], b[i]):
				return false
		return true
	return a == b


func _write_text(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove_test_files() -> void:
	for path in [TEST_SAVE, TEST_SAVE + ".tmp", TEST_SETTINGS]:
		if FileAccess.file_exists(path):
			DirAccess.open("user://").remove(String(path).get_file())
