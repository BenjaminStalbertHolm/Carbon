extends SceneTree
## M0 acceptance checks (spec section 19). Run from the project root, after
## tools/gen_textures.py and tools/gen_audio.py have written the assets:
##   godot --headless --path . --script res://tests/run_tests.gd
## Exit code 0 means every check passed.

const AUTOLOADS := [
	"GameState", "DayDirector", "AudioDirector", "Gaze",
	"UnseenChanges", "Cadence", "TextTokens", "SaveSystem",
]
const SCENES := [
	"res://scenes/main.tscn",
	"res://scenes/hall_c.tscn",
	"res://scenes/desk.tscn",
	"res://scenes/player_desk.tscn",
	"res://scenes/typewriter.tscn",
	"res://scenes/clerk.tscn",
	"res://scenes/tube_terminal.tscn",
	"res://scenes/ui/read_view.tscn",
	"res://scenes/ui/menu_folder.tscn",
	"res://scenes/ui/black_paper.tscn",
]
const PRESETS := ["Windows Desktop", "Linux", "macOS"]
const DOCS := ["res://CARBON_SPEC.md", "res://QUESTIONS.md", "res://README.md"]
const FONTS := [
	"res://assets/fonts/SpecialElite-Regular.ttf",
	"res://assets/fonts/HomemadeApple-Regular.ttf",
	"res://assets/fonts/LICENSE-SpecialElite.txt",
	"res://assets/fonts/LICENSE-HomemadeApple.txt",
]
const TEXTURES := [
	"floor_lino", "wall_upper", "wall_lower", "ceiling_tile", "desk_top", "steel",
	"wood", "paper", "onionskin", "frosted", "chalk_board", "white4",
]
const AUDIO := [
	"key_clack_1", "key_clack_2", "key_clack_3", "key_clack_4", "carriage_return",
	"bell", "backspace_click", "platen_ratchet", "key_jam", "paper_in", "paper_out",
	"paper_shuffle", "page_turn", "stamp_thud", "marker_stroke", "fluid_brush",
	"tube_send", "tube_arrive_whoosh", "tube_thunk", "door_rattle", "footstep_1",
	"footstep_2", "clock_tick", "lamp_click", "drawer_open", "drawer_close",
	"start_bell", "fixture_off", "fixture_on", "door_unlock", "door_open",
	"room_tone", "hum", "vent_shepard",
]

var _failures := 0
var _ran := false


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run_checks()
	return false


func _run_checks() -> void:
	_check_project_settings()
	_check_autoloads()
	_check_files()
	_check_scenes()
	_check_export_presets()
	print("RESULT: %s, %d failure(s)" % ["PASS" if _failures == 0 else "FAIL", _failures])
	quit(1 if _failures > 0 else 0)


func _check(ok: bool, label: String) -> void:
	print("%s  %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		_failures += 1


func _check_project_settings() -> void:
	_check(ProjectSettings.get_setting("application/config/name") == "CARBON", "project name is CARBON")
	_check(ProjectSettings.get_setting("display/window/size/viewport_width") == 1280, "window width 1280")
	_check(ProjectSettings.get_setting("display/window/size/viewport_height") == 960, "window height 960")
	_check(ProjectSettings.get_setting("display/window/size/mode") == 0, "starts windowed")
	_check(ProjectSettings.get_setting("display/window/size/resizable") == true, "window is resizable")
	_check(ProjectSettings.get_setting("physics/common/physics_ticks_per_second") == 60, "60 physics ticks")
	_check(ProjectSettings.get_setting("application/run/max_fps") == 60, "max FPS 60")
	_check(ProjectSettings.get_setting("display/window/vsync/vsync_mode") == DisplayServer.VSYNC_ENABLED, "V-Sync on")
	_check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility", "Compatibility renderer")
	_check(ProjectSettings.get_setting("rendering/environment/defaults/default_clear_color") == Color.BLACK, "clear colour is black")
	_check(ProjectSettings.get_setting("rendering/anti_aliasing/quality/use_debanding") == false, "debanding off")
	_check(ProjectSettings.get_setting("rendering/anti_aliasing/quality/msaa_3d") == 0, "MSAA off")
	_check(ProjectSettings.get_setting("rendering/anti_aliasing/quality/screen_space_aa") == 0, "screen-space AA off")


func _check_autoloads() -> void:
	for autoload_name in AUTOLOADS:
		_check(root.get_node_or_null(autoload_name) != null, "autoload %s is registered" % autoload_name)


func _check_files() -> void:
	for path in DOCS + FONTS:
		_check(FileAccess.file_exists(path), "file exists: %s" % path)
	for texture in TEXTURES:
		_check(FileAccess.file_exists("res://assets/textures/%s.png" % texture), "texture exists: %s.png" % texture)
	for sound in AUDIO:
		_check(FileAccess.file_exists("res://assets/audio/%s.wav" % sound), "audio exists: %s.wav" % sound)
	var credits = JSON.parse_string(FileAccess.get_file_as_string("res://data/credits.json"))
	var lines = credits.get("lines") if credits is Dictionary else null
	_check(lines is Array and lines == ["CARBON"], "credits.json holds exactly one line: CARBON")


func _check_scenes() -> void:
	for path in SCENES:
		_check(ResourceLoader.load(path) is PackedScene, "scene loads: %s" % path)


func _check_export_presets() -> void:
	var cfg := ConfigFile.new()
	_check(cfg.load("res://export_presets.cfg") == OK, "export_presets.cfg parses")
	var preset_names: Array = []
	for section in cfg.get_sections():
		if section.count(".") == 1:
			preset_names.append(cfg.get_value(section, "name", ""))
	for preset_name in PRESETS:
		_check(preset_name in preset_names, "export preset present: %s" % preset_name)
