extends Node
## M10 dev-only screenshot harness for the endings (spec 15.2 step 4, 15.3). Builds the real main
## controller without the front end, then saves two PNGs:
##   endings_c_carbon_stack.png  seated at Desk 4, the carbon stack on the carbon spot (three transcription
##                               carbons kept, RO-5 refused): the stack Ending C is clicked on
##   endings_b_duplicate_hall.png  the duplicate hall: standing at (0, 1.62, -5.30) facing south, the clerk
##                               at Desk 4, the nameplate with the player's name, the exit door shut
##   endings_exit_door_open.png  the exit door swung open (1.2 s), the unlit box beyond it
##   endings_a_fade_mid.png      Ending A's final shot, half-way through its 1.5 s fade in from black
##   endings_a_final_shot.png    Ending A's final shot, faded in
## Dev-only and excluded from export (tests/*).
## Run: xvfb-run -a -s "-screen 0 1280x1024x24" godot --path /home/user/Carbon res://tests/endings/endings_shots.tscn -- --out=<dir>

const MainScript := preload("res://scripts/main.gd")
const Doc := preload("res://scripts/logic/doc_model.gd")

var _out_dir := "/tmp"
var _main = null
var _gs = null
var _stage := 0
var _wait_frames := 0
var _pending_wait := 0.0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out_dir = a.substr(6)
	call_deferred("_setup_main")


## Deferred: the root is still setting up its children while this node is ready.
func _setup_main() -> void:
	_gs = get_node("/root/GameState")
	_main = MainScript.new()
	_main.auto_boot = false
	get_tree().root.add_child(_main)
	_main.debug_start_game(4242)
	_stage = 0
	_wait_frames = 3


func _process(delta: float) -> void:
	if _wait_frames > 0:
		_wait_frames -= 1
		return
	if _pending_wait > 0.0:
		_pending_wait -= delta
		return
	match _stage:
		0:
			_make_carbons(3)
			_gs.carbons_kept_at_final = 3
			_main.desk.refresh()
			_stage = 1
			_wait_frames = 6
		1:
			# Look straight at the carbon spot from the seated eye (Desk 4, spec 6.4).
			var spot: Vector3 = _main.desk.home_world("carbon_spot")
			_main.player.camera().look_at(spot, Vector3.UP)
			_stage = 2
			_wait_frames = 4
		2:
			_shot("endings_c_carbon_stack.png")
			_main.endings_pres.duplicate_hall_set()
			_main.black.set_shade(0.0)
			_stage = 3
			_pending_wait = 1.6
		3:
			# Standing at (0, 1.62, -5.30) facing south, looking across to the Desk 4 clerk and nameplate.
			_main.player.camera().look_at(Vector3(5.25, 1.0, 3.9), Vector3.UP)
			_stage = 4
			_wait_frames = 4
		4:
			_shot("endings_b_duplicate_hall.png")
			_stage = 5
			_wait_frames = 2
		5:
			# The exit door swung open (spec 15.2 step 2): the leaf's hinge is on the east edge, so the free
			# edge swings south into the unlit box. The player stands at (-6, 0, 3), facing the door.
			_main.endings_pres.door_swing(1.2)
			_main.player.position = Vector3(-6.0, 0.0, 3.0)
			_main.player.set_look(180.0, 0.0)
			_main.player.camera().look_at(Vector3(-6.0, 1.0, 6.5), Vector3.UP)
			_stage = 6
			_pending_wait = 1.6
		6:
			_shot("endings_exit_door_open.png")
			_stage = 7
			_wait_frames = 2
		7:
			# Ending A's final shot comes in from black over 1.5 s (QUESTION-59): the shot is set while black.
			_main.black.set_shade(1.0)
			_main.endings_pres.final_shot()
			_main.endings_pres.faded_in(1.5)
			_stage = 8
			_pending_wait = 0.75
		8:
			_shot("endings_a_fade_mid.png")
			_stage = 9
			_pending_wait = 1.2
		9:
			_shot("endings_a_final_shot.png")
			_stage = 10
			_wait_frames = 2
		10:
			get_tree().quit(0)


## Three transcription carbons (spec 8.5), filed on the carbon spot, with a line of typing each.
func _make_carbons(count: int) -> void:
	for i in range(count):
		var sheet_id := "SHEET-%d" % (100 + i)
		var sheet := Doc.new_doc(sheet_id, "sheet", "typed", "black")
		sheet.task = "T-2"
		sheet.pages.append(Doc.new_page())
		var text := "THE RECORD OF CLERK 0412 %d" % (i + 1)
		for c in range(text.length()):
			Doc.write_glyph(sheet.pages[0], 2, c, text.substr(c, 1), _gs.rng)
		var carbon := Doc.make_carbon(sheet, "CARBON-%d" % (100 + i))
		_gs.add_doc(carbon, "carbon_spot")


func _shot(file_name: String) -> void:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(_out_dir.path_join(file_name))
	print("SHOT ", file_name, " ", "ok" if err == OK else "error %d" % err)
