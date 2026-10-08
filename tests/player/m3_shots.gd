extends Node
## M3 dev screenshot harness (spec 6.2, 6.4, 8.12). Builds the game through main.gd (no front end),
## starts a Day 1 game and saves four PNGs at the window size:
##   m3_a_seated.png     seated at Desk 4, inbox and read stack filled
##   m3_b_standing.png   standing, looking down at the desk
##   m3_c_drawer.png     top drawer open, from standing, looking at the drawer front
##   m3_d_held.png       seated, the top inbox document held at the lower right
## Dev-only and excluded from export (tests/*). Run under a virtual display:
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path /home/user/Carbon res://tests/player/m3_test.tscn -- --out=<dir>

const MainScript := preload("res://scripts/main.gd")

const DESK_LOOK_PITCH := -34.0
const STANDING_LOOK_PITCH := -40.0
const DRAWER_YAW := -64.0
const DRAWER_PITCH := -58.0

var _out := ""
var _main = null
var _dd = null
var _gs = null
var _log := PackedStringArray()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	if _out == "":
		push_error("m3_shots: pass --out=<dir>")
		get_tree().quit(1)
		return
	await get_tree().process_frame
	await _run()
	print("M3 shots written: %s" % ", ".join(_log))
	get_tree().quit(0)


func _run() -> void:
	_dd = get_node("/root/DayDirector")
	_gs = get_node("/root/GameState")
	var ss = get_node("/root/SaveSystem")
	ss.save_path = "user://m3_shots_save.json"
	_main = MainScript.new()
	_main.auto_boot = false
	add_child(_main)
	await get_tree().process_frame
	_main.debug_start_game(4242)
	_fill_desk()
	await get_tree().process_frame

	# (a) seated, looking down at the desk.
	_main.player.set_look(0.0, DESK_LOOK_PITCH)
	await _settle(3)
	await _shot("m3_a_seated.png")

	# Open the top drawer while seated (drawers are desk interactions, spec 6.2).
	_main.interaction.dispatch_click("drawer_top")
	await _wait(0.6)

	# (b) standing, looking down at the desk with the drawer open.
	_main.player.try_space()
	await _wait(0.9)
	_main.player.set_look(0.0, STANDING_LOOK_PITCH)
	await _settle(3)
	await _shot("m3_b_standing.png")

	# (c) the open top drawer and the notebook in it, from standing.
	_main.player.set_look(DRAWER_YAW, DRAWER_PITCH)
	await _settle(3)
	await _shot("m3_c_drawer.png")
	_main.player.sit_down(true)
	await _wait(1.0)
	_main.interaction.dispatch_click("drawer_top")
	await _wait(0.6)

	# (d) a document held at the lower right, seated.
	_main.player.set_look(0.0, DESK_LOOK_PITCH)
	_main.interaction.dispatch_hold("inbox")
	await _settle(3)
	await _shot("m3_d_held.png")
	_main.interaction.dispatch_right_click()
	_main.queue_free()
	await get_tree().process_frame


## A small Day 1 inbox and read stack, so the desk shows paper.
func _fill_desk() -> void:
	for pair in [["M1-WELCOME", "inbox"], ["P-1", "inbox"], ["L-1", "inbox"], ["S-1-COVER", "read_stack"]]:
		var doc: Dictionary = _dd.instantiate(String(pair[0]))
		if not doc.is_empty():
			_gs.add_doc(doc, String(pair[1]))
	_main.desk.refresh()


func _settle(frames: int) -> void:
	for i in frames:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _shot(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s" % [_out, file_name]
	var err := img.save_png(path)
	_log.append("%s (%s)" % [file_name, "ok" if err == OK else "error %d" % err])
