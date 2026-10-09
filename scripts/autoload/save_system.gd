extends Node
## SaveSystem: autosave, load and settings persistence (spec 16.3, 16.4). Autoload.
##
## Save: one slot at user://save.json, the JSON of GameState.to_dict() plus any
## data registered with register_extra() (for example "cadence"). Autosave runs on
## DayDirector.day_started (spec 13.1 step 6), so every day start, including Monday
## of a new game, writes the slot. A save that does not parse, has another version
## or fails GameState.from_dict counts as no save and shows nothing (spec 16.4).
##
## Settings: user://settings.cfg, written at once on every change (spec 16.3).
## Consumers read them with get_setting(). Master volume and fullscreen are
## applied here; the rest are read by the systems that use them.

const GameStateScript := preload("res://scripts/autoload/game_state.gd")

const SAVE_PATH := "user://save.json"
const SETTINGS_PATH := "user://settings.cfg"
const SETTINGS_SECTION := "settings"

const SETTING_DEFAULTS := {
	"mouse_sensitivity": 0.6,
	"invert_mouse_y": false,
	"master_volume": 80,
	"fullscreen": false,
	"internal_high": false,
	"dither": true,
	"reduce_flicker": false,
	"text_assist": false,
}

# Keys of GameState.to_dict() that must hold these container types (spec 16.4).
const DICT_KEYS := [
	"accuracy", "stamp_results", "ro_results", "first_stamp", "f3_answers",
	"ghost_lines_done", "ghost_sheet_removed_by_player", "docs", "loc",
	"desk_removed", "clerk_present", "clerk_faces_player", "nameplate",
	"fixture_lit", "fixture_pattern", "flags",
]
const ARRAY_KEYS := [
	"carried_forward", "free_mail_sent", "redacted_names", "redacted_desks", "refused_desks",
]
const LOCATION_KEYS := ["inbox", "read_stack", "carbon_spot", "drawer", "removed", "attached"]

signal setting_changed(key: String, value: Variant)

## Tests and the screenshot harness point these at scratch files.
var save_path: String = SAVE_PATH
var settings_path: String = SETTINGS_PATH

var _settings: Dictionary = {}
var _extra_writers: Dictionary = {}
var _extra_readers: Dictionary = {}
var _observed_fullscreen := false  # the window mode seen at the last poll
var _fs_pending := false  # a request for the wanted window mode has not yet been held
var _fs_asked_ms := 0  # when the request was sent
var _fs_last_send_ms := 0  # when the request was last sent
var _fs_held_ms := -1  # when the window first showed the wanted mode while the request was pending (-1: not yet)

const FULLSCREEN_HOLD_MS := 1000  # the wanted mode must hold this long before the window's own changes count
const FULLSCREEN_SETTLE_MS := 5000  # the request is given up after this long
const FULLSCREEN_RETRY_MS := 500  # while the request is pending, it is sent again after this


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # the window mode is followed while the menu folder pauses the tree
	load_settings()
	var director = _autoload("DayDirector")
	if director != null:
		director.day_started.connect(_on_day_started)


func _on_day_started(_day: int) -> void:
	save_game()


# --- Save slot -----------------------------------------------------------------------

## True when the slot holds a save that parses, has the current version and that
## GameState accepts. Nothing in GameState changes while this runs.
func has_save() -> bool:
	return not _read_valid_save().is_empty()


## The day of the valid save, or 0 when there is none (CONTINUE shows its name).
func saved_day() -> int:
	var d := _read_valid_save()
	return int(d.day) if not d.is_empty() else 0


## Writes the slot. Returns false when the file cannot be written.
func save_game() -> bool:
	var data: Dictionary = _gs().to_dict()
	data.merge(extra_save_data())
	var tmp := save_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(data))
	file.close()
	return _replace_file(tmp, save_path)


## Loads the slot into GameState and the registered extras. False on any failure.
func load_game() -> bool:
	var d := _read_valid_save()
	if d.is_empty():
		return false
	if not _gs().from_dict(d):
		return false
	for key in _extra_readers.keys():
		var reader: Callable = _extra_readers[key]
		if d.has(key) and reader.is_valid():
			reader.call(d[key])
	return true


## Removes the slot (spec 15.4 after the credits, and the BEGIN erase).
func delete_save() -> void:
	for path in [save_path, save_path + ".tmp"]:
		if FileAccess.file_exists(path):
			var dir := DirAccess.open(String(path).get_base_dir())
			if dir != null:
				dir.remove(String(path).get_file())


## Other autoloads add their data to the save. writer returns a JSON-safe value
## at save time, and reader receives it at load time.
func register_extra(key: String, writer: Callable, reader: Callable) -> void:
	_extra_writers[key] = writer
	_extra_readers[key] = reader


func extra_save_data() -> Dictionary:
	var out := {}
	for key in _extra_writers.keys():
		var writer: Callable = _extra_writers[key]
		if writer.is_valid():
			out[key] = writer.call()
	return out


func _read_valid_save() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var text := FileAccess.get_file_as_string(save_path)
	var json := JSON.new()
	if json.parse(text) != OK:
		return {}
	if not _is_valid(json.data):
		return {}
	return json.data


func _is_valid(d: Variant) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	if not d.has("version") or not _is_num(d.version):
		return false
	if int(d.version) != GameStateScript.SAVE_VERSION:
		return false
	var probe: Node = GameStateScript.new()
	var template: Dictionary = probe.to_dict()
	probe.free()
	for key in template.keys():
		if not d.has(key):
			return false
	for key in DICT_KEYS:
		if typeof(d[key]) != TYPE_DICTIONARY:
			return false
	for key in ARRAY_KEYS:
		if typeof(d[key]) != TYPE_ARRAY:
			return false
	for key in LOCATION_KEYS:
		if not d.loc.has(key):
			return false
	if not _is_num(d.day) or int(d.day) < 1 or int(d.day) > 5:
		return false
	var check: Node = GameStateScript.new()
	var accepted: bool = check.from_dict(d)
	check.free()
	return accepted


static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT


func _replace_file(from: String, to: String) -> bool:
	var dir := DirAccess.open(from.get_base_dir())
	if dir == null:
		return false
	if FileAccess.file_exists(to):
		dir.remove(to.get_file())
	return dir.rename(from.get_file(), to.get_file()) == OK


# --- Settings ------------------------------------------------------------------------

func load_settings() -> void:
	_settings = SETTING_DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		for key in SETTING_DEFAULTS.keys():
			if cfg.has_section_key(SETTINGS_SECTION, key):
				_settings[key] = _clean(key, cfg.get_value(SETTINGS_SECTION, key))
	_apply_settings()


func get_setting(key: String) -> Variant:
	return _settings.get(key, SETTING_DEFAULTS.get(key))


## Stores one setting and writes the file at once. Returns false when the file
## could not be written. Unknown keys are refused. Only the setting that changed is applied.
func set_setting(key: String, value: Variant) -> bool:
	if not SETTING_DEFAULTS.has(key):
		push_error("SaveSystem: unknown setting %s" % key)
		return false
	var clean: Variant = _clean(key, value)
	var ok := _store(key, clean)
	if key == "master_volume":
		_apply_volume()
	elif key == "fullscreen":
		_request_fullscreen(bool(clean))
	setting_changed.emit(key, clean)
	return ok


func _store(key: String, clean: Variant) -> bool:
	_settings[key] = clean
	var cfg := ConfigFile.new()
	cfg.load(settings_path)  # a missing file is fine; the other keys stay
	cfg.set_value(SETTINGS_SECTION, key, clean)
	return cfg.save(settings_path) == OK


## Spec 16.3 ranges: mouse sensitivity 0.1 to 2.0 in steps of 0.1, master volume
## 0 to 100 in steps of 10. Booleans stay booleans.
static func _clean(key: String, value: Variant) -> Variant:
	match key:
		"mouse_sensitivity":
			return clampf(snappedf(float(value), 0.1), 0.1, 2.0)
		"master_volume":
			return clampi(int(round(float(value) / 10.0)) * 10, 0, 100)
		_:
			return bool(value)


func _apply_settings() -> void:
	_apply_volume()
	if _is_headless():
		return
	# Only asks the window when it is not already in the wanted mode, so a window that was made
	# fullscreen another way is not turned back at a title load.
	if _window_is_fullscreen() != bool(get_setting("fullscreen")):
		_request_fullscreen(bool(get_setting("fullscreen")))
	_observed_fullscreen = _window_is_fullscreen()


func _apply_volume() -> void:
	var bus := AudioServer.get_bus_index("Master")
	if bus >= 0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(float(get_setting("master_volume")) / 100.0))


func _request_fullscreen(on: bool) -> void:
	if _is_headless():
		return
	_send_window_mode(on)
	_fs_pending = true
	_fs_asked_ms = Time.get_ticks_msec()
	_fs_last_send_ms = _fs_asked_ms
	_fs_held_ms = -1


func _send_window_mode(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


## Spec 16.3: the FULLSCREEN setting reflects the real window mode. A change made another way (the
## green button, Ctrl+Cmd+F, a window manager) is taken into the setting and saved. A new request is
## sent again while the window has not shown its mode; once it has shown it for FULLSCREEN_HOLD_MS
## (a window can revert once at start), or after FULLSCREEN_SETTLE_MS, the window's mode is the truth.
func _process(_delta: float) -> void:
	if _is_headless():
		return
	var real := _window_is_fullscreen()
	var want := bool(get_setting("fullscreen"))
	var now := Time.get_ticks_msec()
	if _fs_pending:
		if real == want:
			if _fs_held_ms < 0:
				_fs_held_ms = now
			if now - _fs_held_ms >= FULLSCREEN_HOLD_MS:
				_fs_pending = false
		else:
			_fs_held_ms = -1
			if now - _fs_asked_ms >= FULLSCREEN_SETTLE_MS:
				_fs_pending = false
			elif now - _fs_last_send_ms >= FULLSCREEN_RETRY_MS:
				_fs_last_send_ms = now
				_send_window_mode(want)
		if _fs_pending:
			_observed_fullscreen = real
			return
	if real != _observed_fullscreen:
		_observed_fullscreen = real
		_adopt_fullscreen(real)
	elif real != want:
		_adopt_fullscreen(real)


func _adopt_fullscreen(real: bool) -> void:
	if bool(get_setting("fullscreen")) == real:
		return
	_store("fullscreen", real)
	setting_changed.emit("fullscreen", real)


func _window_is_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


func _is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


# --- Helpers -------------------------------------------------------------------------

func _gs() -> Node:
	return _autoload("GameState")


func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null(node_name)
