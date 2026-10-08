extends Node
## Presentation for the endings (spec 8.12, 8.13, 11.4, 15): carries out every signal the sequences
## emit, on the real hall, typewriter, player, black screen and audio. The rules stay in the
## sequences and GameState. Each method has the name and arguments of the sequence signal it serves,
## and the controller connects them by name (endings_controller.gd _wire).
##
## Also answers the queries the sequences make: has_paper, ghost_idle, key_delay_ms, player_crossed,
## figure_distance.

const ExitDoor := preload("res://scripts/endings/exit_door.gd")
const ClerkFigure := preload("res://scripts/world/clerk_figure.gd")
const TypewriterView := preload("res://scripts/typewriter/typewriter_view.gd")
const Doc := preload("res://scripts/logic/doc_model.gd")
const Content := preload("res://scripts/logic/content.gd")

## Gains (QUESTION-24, QUESTION-58, QUESTION-68). The scripted sounds are not player-caused, so Rule A
## applies, and each gain is set by the sound's attack. Ending A's paper_in (Hann rise, about 240 ms
## to 90%) takes -6 dB. Its paper_out (50 ms rise) takes -10 dB. The scripted lamp click (about 1 ms
## attack) takes -10 dB. Ending C's eject and paper_in follow the player's click, so they are
## player-caused and play at 0 dB (Rule B).
const SCRIPTED_GAIN_DB := -6.0
const PAPER_OUT_SCRIPTED_DB := -10.0
const LAMP_CLICK_GAIN_DB := -10.0
const PLAYER_GAIN_DB := 0.0
## Paper timing (QUESTION-62): the slide out of the typewriter is the 0.6 s animation of
## typewriter_view.gd (EJECT_MS), then the sheet travels to the read stack in the same 0.6 s as paper_in.
const PAPER_OUT_S := 0.6
const PAPER_TRAVEL_S := 0.6
const PAPER_IN_S := 0.6
## Row spacing of the flat sheets on a desk stack (desk4_items.gd SHEET_SPACING).
const STACK_SPACING := 0.0008
const FINAL_CAM_POS := Vector3(5.25, 1.55, 5.60)
const FINAL_PITCH_DEG := -12.0
const FINAL_NAMEPLATE := "0413"
const DUPLICATE_POS := Vector3(0.0, 0.0, -5.30)
const DUPLICATE_YAW_DEG := 180.0
const DESK4_CLERK_POS := Vector3(5.25, 0.0, 4.05)
const CHAIR4 := "Chair04"
const CLOCK_WALL_Z := 6.1
const RISE_WAIT_S := 0.7

var main = null
var hall: Node = null
var player: Node = null
var typewriter: Node = null
var black: Node = null
var pipeline: Node = null
var exit_door = null
var _clerk4: Node3D = null


## main_ctl: the main controller (set_typing_focus). hall: HallC root. player: PlayerController.
## typewriter: TypewriterView. black: BlackScreen. pipeline: PsxPipeline (internal resolution).
func setup(main_ctl, hall_root: Node, player_node: Node, typewriter_node: Node, black_node: Node, pipeline_node: Node) -> void:
	main = main_ctl
	hall = hall_root
	player = player_node
	typewriter = typewriter_node
	black = black_node
	pipeline = pipeline_node
	exit_door = ExitDoor.new()
	exit_door.setup(hall)


# --- Queries ---------------------------------------------------------------------------------

func has_paper() -> bool:
	return typewriter != null and bool(typewriter.is_loaded())


func ghost_idle() -> bool:
	if typewriter == null or not bool(typewriter.is_loaded()):
		return true
	return not typewriter.model.ghost_pending()


func key_delay_ms(prev: String, ch: String) -> float:
	var cad = _autoload("Cadence")
	if cad == null:
		return 180.0
	return float(cad.delay_for(prev, ch))


func player_crossed() -> bool:
	if player == null:
		return false
	var cam: Camera3D = player.camera()
	return cam != null and cam.global_position.z > CLOCK_WALL_Z


## Floor-plane distance (x and z) in metres from the player to the Desk 4 figure's root (QUESTION-67).
func figure_distance() -> float:
	if player == null or _clerk4 == null:
		return INF
	var a: Vector3 = player.global_position
	var b: Vector3 = _clerk4.global_position
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))


# --- Fixtures (spec 8.12) ---------------------------------------------------------------------

func fixture_off(index: int) -> void:
	_set_fixture(index, false)
	_play("fixture_off", _node_pos("Fixture%d" % index), true, 0.0, false)
	_refresh_hum()


func fixture_on(index: int) -> void:
	_set_fixture(index, true)
	_play("fixture_on", _node_pos("Fixture%d" % index), true, 0.0, false)
	_refresh_hum()


# --- Paper (spec 7.5, 7.7, 8.5) ---------------------------------------------------------------

## The loaded paper leaves the typewriter for the read stack. No typing view opens. The sheet itself
## slides out over 0.6 s with paper_out, then travels to the read stack over 0.6 s, and joins the stack
## on arrival, so it never jumps (QUESTION-62). A transcription carbon moves to the carbon spot at once
## (DayDirector.paper_removed), because Ending C loads it next. Ending A's eject is scripted (paper_out at
## -10 dB); Ending C's follows the player's click (0 dB, player-caused).
func paper_ejected(player_caused: bool) -> void:
	if not has_paper():
		return
	var paper := _typewriter_paper()
	var sheet := _sheet_copy(paper)
	var id: String = typewriter.loaded_doc_id()
	typewriter.unload_sheet()
	var dd = _autoload("DayDirector")
	if dd != null:
		dd.paper_removed(id)
	var gain := PLAYER_GAIN_DB if player_caused else PAPER_OUT_SCRIPTED_DB
	_play("paper_out", _node_pos("Typewriter04"), true, gain, player_caused)
	_travel_to_read_stack(sheet, paper, id)


func blank_sheet_loaded() -> void:
	var dd = _autoload("DayDirector")
	if dd == null or typewriter == null:
		return
	var id: String = dd.take_blank_sheet()
	if id != "" and bool(typewriter.load_sheet(id)):
		_slide_in(_typewriter_paper())
		_play("paper_in", _node_pos("Typewriter04"), true, SCRIPTED_GAIN_DB, false)


## The carbon stack's top carbon, loaded into the typewriter. The 0.8 s travel of the whole stack
## is not drawn here (carbon_stack_moved): the carbon stack view has no travel hook yet.
func carbon_stack_moved() -> void:
	pass


## Ending C step 1: the top carbon slides in after the player's click, so paper_in is player-caused at 0 dB.
func carbon_loaded() -> void:
	var id := _top_carbon()
	if id == "" or typewriter == null:
		return
	if bool(typewriter.load_sheet(id)):
		_slide_in(_typewriter_paper())
		_play("paper_in", _node_pos("Typewriter04"), true, PLAYER_GAIN_DB, true)


# --- Ghost typing (spec 10.2) -------------------------------------------------------------------

## Hands the line to the typewriter's own ghost queue. It types whether or not the typing view is open.
func ghost_typed(text: String) -> void:
	if typewriter == null or not bool(typewriter.is_loaded()):
		return
	typewriter.model.enqueue_ghost_text(text)
	typewriter.model.ghost_set_running(true, float(Time.get_ticks_msec()))


## The clerk's keys during the final shot: sound only, with ghost gain (spec 11.1).
func clerk_key(_letter: String, _delay_ms: float) -> void:
	var ad = _autoload("AudioDirector")
	if ad != null:
		ad.play_ghost("key_clack", _node_pos("Typewriter04"), true, 0.0)


# --- Lamp, lights and sound --------------------------------------------------------------------

func lamp_off() -> void:
	var gs = _autoload("GameState")
	if gs != null:
		gs.lamp_on = false
	_play("lamp_click", _node_pos("Lamp04"), false, LAMP_CLICK_GAIN_DB, false)


func silence() -> void:
	var ad = _autoload("AudioDirector")
	if ad == null:
		return
	for bed in ["hum", "room_tone", "vent_shepard"]:
		ad.stop_bed(bed)
	# Clerk typing and the clock stop too, but not here. main.gd's RoomPresentation overrides silence(),
	# calls this method, then emits room_silenced, and main.gd hands that signal to ClerkBehaviour.silence()
	# and ClockBehaviour.silence() (spec 15.3 step 4).


# --- Black screen (spec 13.1, 15) --------------------------------------------------------------

func faded_to_black(seconds: float) -> void:
	if black != null:
		black.fade_to(1.0, seconds)


func faded_in(seconds: float) -> void:
	if black != null:
		black.fade_to(0.0, seconds)


func cut_to_black() -> void:
	if black != null:
		black.set_shade(1.0)


func title_typed(text: String, ms_per_char: float) -> void:
	if black == null:
		return
	black.clear_text()
	black.type_lines([text], 40, int(ms_per_char), true)


func title_cleared() -> void:
	if black != null:
		black.clear_text()


# --- Camera and typing view ----------------------------------------------------------------------

func camera_to_typing(_seconds: float) -> void:
	if typewriter == null:
		return
	if bool(typewriter.open_typing_view()) and main != null and main.has_method("set_typing_focus"):
		main.set_typing_focus(true)
	typewriter.set_process_input(false)


func camera_to_free(_seconds: float) -> void:
	if typewriter == null:
		return
	typewriter.close_typing_view()
	if main != null and main.has_method("set_typing_focus"):
		main.set_typing_focus(false)


## Final shot (spec 15.1 step 6): camera, F2 lit with no flicker, lamp on, Desk 4 nameplate 0413,
## and the clerk at Desk 4. The screen is black when this runs and stays black: the faded_in signal
## (1.5 s, QUESTION-59) brings the shot in, so it is not cut to.
func final_shot() -> void:
	_set_fixture(2, true)
	_refresh_hum()
	var gs = _autoload("GameState")
	if gs != null:
		gs.lamp_on = true
	_set_nameplate(4, FINAL_NAMEPLATE)
	_ensure_clerk4()
	_place_camera(FINAL_CAM_POS, FINAL_PITCH_DEG)
	if pipeline != null:
		pipeline.set_high_resolution(false)


# --- Restoration and the refusal (spec 15.2, 15.3) -----------------------------------------------

## Ending C step 5: the desks removed by redaction return, with their clerks and nameplates. Clerks
## face Desk 4 and no redaction bar remains. Visible restoration goes through the unseen rule.
func restore_record(desks: Array) -> void:
	var gs = _autoload("GameState")
	if gs == null:
		return
	var names: Dictionary = Content.strings()["nameplates"]
	for d in desks:
		var key := str(int(d))
		gs.desk_removed[key] = false
		gs.clerk_present[key] = true
		gs.nameplate[key] = String(names.get(key, ""))
	if String(gs.nameplate.get("12", "")) == "":
		gs.nameplate["12"] = "0411"
	for n in range(1, 13):
		if bool(gs.clerk_present.get(str(n), false)):
			gs.clerk_faces_player[str(n)] = true
	gs.redacted_names = []
	gs.redacted_desks = []
	var un = _autoload("UnseenChanges")
	if un != null:
		un.restore_visuals()


## Step 1 of the refusal: a black memo on the inbox, arriving on the tube canister.
func refusal_memo() -> void:
	var gs = _autoload("GameState")
	var dd = _autoload("DayDirector")
	if gs == null or dd == null:
		return
	var b: Dictionary = Content.endings()["B"]["refusal_memo"]
	var doc := Doc.new_doc("MEMO-RO5-REFUSAL", "memo", "typed", "black")
	var page := Doc.new_page()
	var lines: Array = [String(Content.strings()["memo_re_line"]).replace("{RE}", String(b["re"])), ""]
	for l in b["lines"]:
		lines.append(String(l))
	Doc.add_printed_lines(page, lines, 0, "black")
	doc.pages.append(page)
	gs.add_doc(doc, "inbox")
	dd.canister_arrived.emit([String(doc.id)])


func exit_unlocked() -> void:
	if exit_door != null:
		exit_door.unlock()
	_play("door_unlock", _node_pos("ExitDoor"), true, 0.0, false)


func door_rattle() -> void:
	_play("door_rattle", _node_pos("ExitDoor"), true, 0.0, true)


func door_swing(seconds: float) -> void:
	if exit_door != null:
		exit_door.swing_open(seconds)
	_play("door_open", _node_pos("ExitDoor"), true, 0.0, true)


## Duplicate hall (spec 15.2 step 4): the door shut and locked, all fixtures lit with no flicker, the
## clerk at Desk 4, the nameplate, the lamp, and the player standing at (0, 1.62, -5.30) facing south.
func duplicate_hall_set() -> void:
	if exit_door != null:
		exit_door.reset_closed_locked()
	for f in range(1, 7):
		_set_fixture(f, true)
	_refresh_hum()
	var gs = _autoload("GameState")
	if gs != null:
		gs.lamp_on = true
	_set_nameplate(4, _player_name())
	_ensure_clerk4()
	_place_player()


# --- Paper travel (spec 7.7, 15.1 step 3, 15.3 step 1) -------------------------------------------

func _typewriter_paper() -> MeshInstance3D:
	var tw := _node_3d("Typewriter04")
	if tw == null:
		return null
	return tw.find_child("Paper", true, false) as MeshInstance3D


## A copy of the typewriter's paper quad at its current pose. The ejected sheet travels on the copy,
## because the typewriter's own paper is hidden at once (unload_sheet) and loads the blank sheet next.
## The copy has its own shader material, so the blank sheet does not change the copy's page.
func _sheet_copy(paper: MeshInstance3D) -> MeshInstance3D:
	if paper == null or hall == null:
		return null
	var sheet := paper.duplicate() as MeshInstance3D
	sheet.name = "EjectedSheet"
	var mat := paper.material_override as ShaderMaterial
	if mat != null:
		sheet.material_override = mat.duplicate()
	sheet.visible = true
	hall.add_child(sheet)
	sheet.global_transform = paper.global_transform
	return sheet


## Slides the copy out of the typewriter (paper_out, 0.6 s), then over to the read stack (0.6 s). On
## arrival the sheet joins the read stack and the copy is freed, so the stack never shows it early.
## Without a copy, the sheet joins the read stack at once.
func _travel_to_read_stack(sheet: MeshInstance3D, paper: MeshInstance3D, id: String) -> void:
	if sheet == null or paper == null:
		_join_read_stack(id)
		return
	var from := sheet.global_transform
	var parent := paper.get_parent() as Node3D
	var out := from
	if parent != null:
		out = Transform3D(from.basis, parent.global_transform * (paper.position + TypewriterView.EJECT_OFFSET))
	var land := _read_stack_pose(out)
	var tween := sheet.create_tween()
	tween.tween_method(_set_sheet.bind(sheet, from, out), 0.0, 1.0, PAPER_OUT_S)
	tween.tween_method(_set_sheet.bind(sheet, out, land), 0.0, 1.0, PAPER_TRAVEL_S)
	tween.tween_callback(_land_on_read_stack.bind(sheet, id))


func _land_on_read_stack(sheet: MeshInstance3D, id: String) -> void:
	_join_read_stack(id)
	sheet.queue_free()


func _join_read_stack(id: String) -> void:
	var gs = _autoload("GameState")
	if gs != null:
		gs.place(id, "read_stack")


func _set_sheet(k: float, sheet: Node3D, a: Transform3D, b: Transform3D) -> void:
	sheet.global_transform = a.interpolate_with(b, k)


## The pose of the top sheet on the read stack (desk4_items.gd lays each sheet flat, with its row at
## (index + 0.5) x STACK_SPACING). The fallback is used when the desk has no read stack.
func _read_stack_pose(fallback: Transform3D) -> Transform3D:
	var stack := _node_3d("Desk04/ReadStack")
	if stack == null:
		return fallback
	var gs = _autoload("GameState")
	var count := 1 if gs == null else maxi(1, int(gs.loc.read_stack.size()))
	var lay := Transform3D(Basis.from_euler(Vector3(deg_to_rad(-90.0), 0.0, 0.0)), Vector3(0.0, STACK_SPACING * (float(count) - 0.5), 0.0))
	return stack.global_transform * lay


## An incoming sheet slides into the typewriter from the tray: the same offset and 0.6 s as a sheet
## loaded in the typing view (typewriter_view.gd LOAD_OFFSET). It visibly travels; it does not appear.
func _slide_in(paper: MeshInstance3D) -> void:
	if paper == null:
		return
	var rest := paper.position
	paper.position = rest + TypewriterView.LOAD_OFFSET
	var tween := paper.create_tween()
	tween.tween_property(paper, "position", rest, PAPER_IN_S)


func _node_3d(path: String) -> Node3D:
	if hall == null:
		return null
	return hall.get_node_or_null(path) as Node3D


# --- Helpers -------------------------------------------------------------------------------------

func _set_fixture(index: int, on: bool) -> void:
	var gs = _autoload("GameState")
	if gs != null:
		gs.fixture_lit[str(index)] = on
	if hall == null:
		return
	var light := hall.get_node_or_null("Fixture%d" % index) as OmniLight3D
	if light == null:
		return
	light.visible = on
	light.light_energy = 1.2 if on else 0.0
	var tube := light.get_node_or_null("Tube") as MeshInstance3D
	if tube != null and tube.material_override is ShaderMaterial:
		(tube.material_override as ShaderMaterial).set_shader_parameter("emission_strength", 1.0 if on else 0.0)


func _refresh_hum() -> void:
	var gs = _autoload("GameState")
	var ad = _autoload("AudioDirector")
	if gs == null or ad == null:
		return
	var lit := 0
	for f in range(1, 7):
		if bool(gs.fixture_lit.get(str(f), false)):
			lit += 1
	ad.set_fixtures_lit(lit)


func _set_nameplate(desk: int, text: String) -> void:
	var gs = _autoload("GameState")
	if gs != null:
		gs.nameplate[str(desk)] = text
	var un = _autoload("UnseenChanges")
	if un != null:
		un.set_nameplate_visual(desk, text)


func _ensure_clerk4() -> void:
	if hall == null:
		return
	_clerk4 = hall.get_node_or_null("Clerk04") as Node3D
	if _clerk4 == null:
		var chair := hall.get_node_or_null(CHAIR4) as Node3D
		_clerk4 = ClerkFigure.build(hall, "Clerk04", DESK4_CLERK_POS, chair)
	_clerk4.visible = true


func _place_player() -> void:
	if player == null:
		return
	if bool(player.is_seated()):
		player.try_space()
		await get_tree().create_timer(RISE_WAIT_S).timeout
	player.position = DUPLICATE_POS
	player.set_look(DUPLICATE_YAW_DEG, 0.0)


func _place_camera(pos: Vector3, pitch_deg: float) -> void:
	if player == null:
		return
	var cam: Camera3D = player.camera()
	if cam == null:
		return
	cam.global_transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(pitch_deg), 0.0, 0.0)), pos)


func _top_carbon() -> String:
	var gs = _autoload("GameState")
	if gs == null:
		return ""
	for stack in ["carbon_spot", "attached"]:
		var best := ""
		for id in gs.loc[stack]:
			var d: Dictionary = gs.docs.get(String(id), {})
			if bool(d.get("carbon", false)):
				best = String(id)
		if best != "":
			return best
	return ""


func _player_name() -> String:
	var tt = _autoload("TextTokens")
	if tt == null:
		return "CLERK 0412"
	return String(tt.token_values().PLAYER_NAME)


func _node_pos(node_name: String) -> Vector3:
	if hall == null:
		return Vector3.ZERO
	var n := hall.get_node_or_null(node_name) as Node3D
	if n == null or not n.is_inside_tree():
		return Vector3.ZERO
	return n.global_position


func _play(sound: String, pos: Vector3, positional: bool, gain_db: float, player_caused: bool) -> void:
	var ad = _autoload("AudioDirector")
	if ad != null:
		ad.play(sound, pos, positional, gain_db, player_caused)


func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
