extends Node
## MAIN controller (spec 13.1, 16.2, 12). It creates the PS1 pipeline, builds Hall C into the
## pipeline's world, creates the player and the desk presentation, and wires DayDirector and
## GameState to the views. It also runs the front-end flow: the content note, the title, the day
## title and the fades (through BlackScreen.run_day_title and fade_in). It holds no game rules.
##
## Focus: while a read view, typing view, menu or transition is up, the mouse is visible and the
## player and interaction are disabled. Esc in free view opens the menu folder (open_menu()).
## Tests set auto_boot = false before adding this node, then call debug_start_game().

const PsxPipeline := preload("res://scripts/rendering/psx_pipeline.gd")
const HallC := preload("res://scripts/world/hall_c.gd")
const PlayerController := preload("res://scripts/player/player_controller.gd")
const Interaction := preload("res://scripts/player/interaction.gd")
const Desk4Items := preload("res://scripts/desk/desk4_items.gd")
const HeldItem := preload("res://scripts/desk/held_item.gd")
const Lamp := preload("res://scripts/desk/lamp.gd")
const CarbonStackView := preload("res://scripts/desk/carbon_stack_view.gd")
const TypewriterView := preload("res://scripts/typewriter/typewriter_view.gd")
const TubeView := preload("res://scripts/tube/tube_view.gd")
const StampView := preload("res://scripts/stamps/stamp_view.gd")
const MarkerView := preload("res://scripts/stamps/marker_view.gd")
const TitleScreen := preload("res://scripts/ui/title_screen.gd")
const ContentNote := preload("res://scripts/ui/content_note.gd")
const EndingsController := preload("res://scripts/endings/endings_controller.gd")
const EndingsPresentation := preload("res://scripts/endings/endings_presentation.gd")
const ClerkBehaviour := preload("res://scripts/world/clerk_behaviour.gd")
const ClockBehaviour := preload("res://scripts/world/clock_behaviour.gd")
const GhostTyper := preload("res://scripts/world/ghost_typer.gd")
const READ_VIEW_SCENE := preload("res://scenes/ui/read_view.tscn")
const MENU_SCENE := preload("res://scenes/ui/menu_folder.tscn")
const BLACK_SCENE := preload("res://scenes/ui/black_paper.tscn")

const FADE_IN_S := 2.0

## Emitted when the read view closes, with the id of the document on show (spec 6.4).
signal read_view_closed(doc_id: String)

## The endings presentation, with two announcements for the room. The sequences call silence() and
## restore_record() by name (endings_controller.gd _wire), so these overrides run the base method
## and then emit a signal, which main.gd hands to the clerks and the clock (spec 15.3 steps 4 and 5).
class RoomPresentation extends "res://scripts/endings/endings_presentation.gd":
	signal room_silenced
	signal desks_restored(desks: Array)

	func silence() -> void:
		super.silence()
		room_silenced.emit()

	func restore_record(desks: Array) -> void:
		super.restore_record(desks)
		desks_restored.emit(desks)

var auto_boot := true

var pipeline = null
var hall = null
var player = null
var interaction = null
var desk = null
var held = null
var lamp = null
var carbon_view = null
var typewriter = null
var tube = null
var stamp_view = null
var marker_view = null
var read_view = null
var menu = null
var black = null
var title = null
var note = null
var endings = null  # EndingsController (spec 15): flags for menu, desk, standing and input
var endings_pres = null  # RoomPresentation (an EndingsPresentation): carries out the ending sequences
var clerk_world = null  # ClerkBehaviour: clerk typing, redaction removals and restoration
var clock_world = null  # ClockBehaviour: the clock hands and clock_tick
var ghost_typer = null  # GhostTyper (spec 10.2, 10.3): ghost typing on the typewriter, Days 3 and 4
var typewriter_node: Node3D = null  # Typewriter04: the typewriter that Gaze and the ghost typer watch

var _running := false
var _typing_flag := false
var _transition := false
var _read_doc_id := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	# Debug builds only (spec 21): the debug console goes on the root. Its path is assembled at run
	# time so that no release export carries the file name; release builds never reach this block.
	if OS.is_debug_build():
		var console_path := PackedStringArray(["res://scripts/", "debug/", "debug_", "console.gd"])
		var console = load("".join(console_path)).new()
		console.main = self
		get_tree().root.add_child.call_deferred(console)
	if auto_boot:
		_boot()


func _process(delta: float) -> void:
	if _running and not get_tree().paused:
		var dd = _dd()
		if dd != null:
			dd.tick(delta)
	_sync_focus()


# --- Build -----------------------------------------------------------------------------

func _build() -> void:
	pipeline = PsxPipeline.new()
	pipeline.name = "Pipeline"
	add_child(pipeline)

	hall = HallC.build(pipeline.world, {})

	clerk_world = ClerkBehaviour.new()
	clerk_world.name = "ClerkBehaviour"
	add_child(clerk_world)
	clerk_world.setup(hall)
	clock_world = ClockBehaviour.new()
	clock_world.name = "ClockBehaviour"
	add_child(clock_world)
	clock_world.setup(hall)

	player = PlayerController.new()
	player.name = "Player"
	pipeline.world.add_child(player)

	desk = Desk4Items.new()
	desk.name = "Desk4"
	add_child(desk)
	desk.setup(hall)

	held = HeldItem.new()
	held.name = "HeldItem"
	player.camera().add_child(held)

	lamp = Lamp.new()
	lamp.name = "Lamp"
	add_child(lamp)
	lamp.setup(hall)

	typewriter = TypewriterView.new()
	typewriter.name = "TypewriterView"
	add_child(typewriter)
	typewriter.setup(hall, player.camera(), pipeline)

	tube = TubeView.new()
	tube.name = "TubeView"
	add_child(tube)
	tube.setup(hall)

	carbon_view = CarbonStackView.new()
	carbon_view.name = "CarbonStackView"
	add_child(carbon_view)

	read_view = READ_VIEW_SCENE.instantiate()
	read_view.name = "ReadView"
	add_child(read_view)
	read_view.closed.connect(_on_read_closed)
	read_view.page_changed.connect(_on_read_page)

	stamp_view = StampView.new()
	stamp_view.name = "StampView"
	add_child(stamp_view)
	stamp_view.attach(read_view)

	marker_view = MarkerView.new()
	marker_view.name = "MarkerView"
	add_child(marker_view)
	marker_view.attach(read_view)

	interaction = Interaction.new()
	interaction.name = "Interaction"
	add_child(interaction)
	interaction.setup(self, hall, player, desk, held, typewriter, tube, carbon_view)

	# The hand is owned by interaction.gd. The views get its Callables (spec 6.4).
	var hand_kind := Callable(interaction, "hand_kind")
	var hand_id := Callable(interaction, "hand_id")
	var hand_hold := Callable(interaction, "hand_hold")
	var hand_release := Callable(interaction, "hand_release")
	typewriter.held_kind_fn = hand_kind
	typewriter.held_id_fn = hand_id
	typewriter.held_hold_fn = hand_hold
	typewriter.held_release_fn = hand_release
	typewriter.closed.connect(_on_typing_closed)
	tube.held_kind_fn = hand_kind
	tube.held_id_fn = hand_id
	tube.held_release_fn = hand_release
	stamp_view.held_kind_fn = hand_kind
	stamp_view.held_release_fn = hand_release
	marker_view.held_kind_fn = hand_kind
	marker_view.held_release_fn = hand_release
	carbon_view.held_kind_fn = hand_kind
	carbon_view.held_hold_fn = hand_hold
	carbon_view.lower_drawer_open_fn = Callable(desk, "drawer_open").bind("lower")

	menu = MENU_SCENE.instantiate()
	menu.name = "MenuFolder"
	add_child(menu)
	menu.pause_requested.connect(_on_pause_requested)

	black = BLACK_SCENE.instantiate()
	black.name = "BlackScreen"
	add_child(black)
	black.set_shade(1.0)

	title = TitleScreen.new()
	title.name = "Title"
	add_child(title)
	title.new_game_requested.connect(_on_new_game)
	title.continue_requested.connect(_on_continue)

	var dd = _dd()
	if dd != null and not dd.day_ended.is_connected(_on_day_ended):
		dd.day_ended.connect(_on_day_ended)

	endings = EndingsController.new()
	endings.name = "Endings"
	add_child(endings)
	endings_pres = RoomPresentation.new()
	endings_pres.name = "EndingsPresentation"
	add_child(endings_pres)
	endings_pres.setup(self, hall, player, typewriter, black, pipeline)
	endings_pres.room_silenced.connect(_on_room_silenced)
	endings_pres.desks_restored.connect(_on_desks_restored)
	endings.setup(endings_pres)
	endings.bind_interaction(interaction, player, desk)
	endings.returned_to_title.connect(_on_endings_returned)
	_wire_world_systems()


## Connects the systems that read the world (spec 9.1, 9.2, 10.2, 11.4). Called once from _build, after
## the hall, the player and the views exist. Gaze reads the player's camera; the unseen registry reads
## the hall; positional sound needs its listener inside the pipeline's SubViewport; ghost typing runs on
## the typewriter view's model.
func _wire_world_systems() -> void:
	var gaze = _autoload("Gaze")
	if gaze != null:
		gaze.set_camera(player.camera())
	var un = _autoload("UnseenChanges")
	if un != null:
		un.bind_hall(hall)
	for child in pipeline.get_children():
		if child is SubViewport:
			(child as SubViewport).audio_listener_enable_3d = true
	var ad = _autoload("AudioDirector")
	if ad != null:
		ad.set_spatial_parent(pipeline.world)
	typewriter_node = hall.find_child("Typewriter04", true, false) as Node3D
	ghost_typer = GhostTyper.new()
	ghost_typer.name = "GhostTyper"
	add_child(ghost_typer)
	ghost_typer.setup(typewriter.model, typewriter_node)
	typewriter.opened.connect(_on_typing_opened)
	typewriter.sheet_released.connect(_on_sheet_released)
	var gs = _gs()
	if gs != null:
		gs.state_changed.connect(_sync_typewriter_sheet)


# --- Front-end flow (spec 16.1, 16.2, 13.1) ---------------------------------------------

func _boot() -> void:
	black.set_shade(1.0)
	# The content note draws its own black. The main black would sit over its text, so it is hidden
	# while the note runs and shown again afterwards, as before (smoke run, content note hidden at boot).
	black.visible = false
	note = ContentNote.new()
	note.name = "ContentNote"
	add_child(note)
	await note.run()
	note.queue_free()
	black.visible = true
	title.show_title()


func _on_new_game() -> void:
	if _transition:
		return
	_transition = true
	title.hide_title()
	if endings != null:
		endings.reset()
	_reset_world()
	_dd().start_new_game()
	_reset_built_world()
	_apply_day_world()
	_apply_day_start_changes()
	player.reset_seated()
	await black.run_day_title(1, true)
	await black.fade_in(FADE_IN_S)
	_begin_running()


## Spec 16.4 autosaves at each day start, so a continue restarts the saved day (begin_day).
func _on_continue() -> void:
	if _transition:
		return
	var save = _autoload("SaveSystem")
	if save == null:
		return
	# The view drops its sheet first: the loaded state brings its own copies of the documents, so the
	# view must reload from them (the sync after the load does that). A failed load re-syncs the old state.
	typewriter.unload_sheet()
	if not bool(save.load_game()):
		_sync_typewriter_sheet()
		return
	_transition = true
	title.hide_title()
	if endings != null:
		endings.reset()
	_reset_world()
	player.reset_seated()
	_dd().begin_day(int(_gs().day))
	_apply_day_world()
	# Spec 9.2: the applied changes come back on the world, then the day's own changes the save did not hold.
	var un = _autoload("UnseenChanges")
	if un != null:
		un.restore_visuals()
	_apply_day_start_changes()
	await black.fade_in(FADE_IN_S)
	_begin_running()


## Spec 13.1: after the lamp, the day title runs, the overnight resolution runs (inside
## start_next_day), the day autosaves on day_started, and the day fades in.
func _on_day_ended(day: int) -> void:
	if _transition:
		return
	_running = false
	_transition = true
	await black.run_day_title(day + 1, false)
	# Spec 9.2: changes still pending at the end of the day apply in the black screen, before the overnight step.
	var un = _autoload("UnseenChanges")
	if un != null:
		un.flush_pending()
	_dd().start_next_day()
	_apply_day_world()
	_apply_day_start_changes()
	player.reset_seated()
	await black.fade_in(FADE_IN_S)
	_begin_running()


func _begin_running() -> void:
	_transition = false
	_running = true


## Test and dev hook: starts a new game without the front end. The DayDirector timeline stays
## paused (the tests drive the state themselves) until debug_run() is called.
func debug_start_game(seed_value: int = 4242) -> void:
	if endings != null:
		endings.reset()
	_reset_world()
	_dd().start_new_game(seed_value)
	_apply_day_world()
	_apply_day_start_changes()
	player.reset_seated()
	black.set_shade(0.0)
	_running = false
	_transition = false


func debug_run(on: bool) -> void:
	_running = on


## Test hook: true while the day timeline runs (a day is in play).
func is_running_for_check() -> bool:
	return _running


# --- Focus and menu --------------------------------------------------------------------

## True while a read view, typing view, the menu or a transition holds the screen.
func is_focus_open() -> bool:
	if _typing_flag or _transition:
		return true
	if read_view != null and read_view.is_open():
		return true
	if menu != null and menu.is_open():
		return true
	return title != null and title.visible


func set_typing_focus(on: bool) -> void:
	_typing_flag = on


func open_menu() -> void:
	if not _running or is_focus_open():
		return
	if endings != null and endings.menu_locked():
		return  # spec 15: the menu folder is disabled from RO-5 on
	menu.open()


## The world follows GameState at each day transition, during the black screen (spec 8.9, 8.10):
## redacted desks are removed and every nameplate and refused clerk is synced.
func _apply_day_world() -> void:
	var gs = _gs()
	if gs == null or clerk_world == null:
		return
	clerk_world.apply_day_state(int(gs.day))


## Spec 9.2: the day-start changes of the current day apply during the black screen, after the world
## has followed the day's state. Each change is applied once (UnseenChanges keeps the flags).
func _apply_day_start_changes() -> void:
	var gs = _gs()
	var un = _autoload("UnseenChanges")
	if gs != null and un != null:
		un.apply_day_start(int(gs.day))


## Spec 16.2: a new game starts from the built hall. Only _on_new_game calls this; a continue keeps the saved state.
func _reset_built_world() -> void:
	var un = _autoload("UnseenChanges")
	if un != null:
		un.reset()
	if clerk_world != null:
		clerk_world.reset()


## A new game or a continue after an ending: the clerks type and the clock runs again.
func _reset_world() -> void:
	if clerk_world != null:
		clerk_world.reset_silence()
	if clock_world != null:
		clock_world.reset_silence()


## Ending C step 4 (spec 15.3): all clerk typing and the clock stop.
func _on_room_silenced() -> void:
	if clerk_world != null:
		clerk_world.silence()
	if clock_world != null:
		clock_world.silence()


## Ending C step 5 (spec 15.3): the redacted desks return with their clerks.
func _on_desks_restored(desks: Array) -> void:
	if clerk_world != null:
		clerk_world.restore_desks(desks)


## The endings flags the interaction reads (spec 15.1 step 1, 15.2 step 1): typing view and lamp.
func typing_locked() -> bool:
	return endings != null and endings.typing_locked()


func lamp_locked() -> bool:
	return endings != null and endings.lamp_locked()


func _sync_focus() -> void:
	var focus := is_focus_open() or not _running
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if focus else Input.MOUSE_MODE_CAPTURED
	pipeline.set_focus_view(_typing_flag or (read_view != null and read_view.is_open()))
	var ending_off: bool = endings != null and endings.input_off()
	var desk_off: bool = endings != null and endings.desk_locked()
	player.set_input_enabled(not focus and not ending_off)
	interaction.set_enabled(not focus and not desk_off)
	_sync_gaze_and_ghosts()


## Spec 9.1: while the read view or the typing view is open, Gaze counts the world as out of frustum,
## except the typewriter during typing. Spec 10.3: ghost typing runs only while the day runs.
func _sync_gaze_and_ghosts() -> void:
	var gaze = _autoload("Gaze")
	if gaze != null:
		var reading: bool = read_view != null and read_view.is_open()
		gaze.overlay_open(reading or _typing_flag, typewriter_node if _typing_flag else null)
	if ghost_typer != null:
		ghost_typer.set_active(_running)


func _on_pause_requested(paused: bool) -> void:
	get_tree().paused = paused


## Spec 15.4: the credits are over and the save is gone. Back to the title (spec 16.2).
func _on_endings_returned() -> void:
	_running = false
	_transition = false
	if endings != null:
		endings.reset()
	black.set_shade(1.0)
	title.show_title()


# --- Read view -------------------------------------------------------------------------

## Opens the read view on docs (a list of document dictionaries) at index (spec 6.3).
## mode is "stack" (step through all documents) or "single".
func open_read_view(docs: Array, index: int, mode: String) -> void:
	if docs.is_empty():
		return
	if endings != null and endings.desk_locked():
		return  # spec 15: no desk interaction during an ending (the carbon stack click starts Ending C)
	var at := clampi(index, 0, docs.size() - 1)
	_read_doc_id = String(docs[at].id)
	read_view.open(docs, at, mode)


func _on_read_page(_index: int) -> void:
	var cur: Dictionary = read_view.current_doc()
	if not cur.is_empty():
		_read_doc_id = String(cur.id)


func _on_read_closed() -> void:
	var id := _read_doc_id
	_read_doc_id = ""
	read_view_closed.emit(id)


## The typing view is open (spec 6.3): Gaze looks through the typing camera, so the typewriter is seen while
## the player types on it, and ghost typing stops.
func _on_typing_opened() -> void:
	var gaze = _autoload("Gaze")
	if gaze != null and typewriter != null:
		gaze.set_camera(typewriter.typing_camera())
	if ghost_typer != null:
		ghost_typer.set_typing_view(true)


func _on_typing_closed() -> void:
	_typing_flag = false
	var gaze = _autoload("Gaze")
	if gaze != null and player != null:
		gaze.set_camera(player.camera())
	if ghost_typer != null:
		ghost_typer.set_typing_view(false)


## Spec 10.3: a ghost sheet the player takes off the typewriter ends the ghost typing of that day.
func _on_sheet_released(doc_id: String) -> void:
	var gs = _gs()
	if gs == null or not gs.docs.has(doc_id):
		return
	if String(gs.docs[doc_id].get("kind", "")) == "ghost":
		gs.ghost_sheet_removed_by_player[str(int(gs.day))] = true


## The typewriter view holds one loaded sheet, and GameState.loc.typewriter names the sheet on the typewriter
## (spec 6.4). When the state changes, the view follows it: a ghost sheet placed there (spec 9.3 D3-U3, D4-U3)
## is loaded so that ghost typing (spec 10.2) can run on it, and a sheet that has left is unloaded.
func _sync_typewriter_sheet() -> void:
	var gs = _gs()
	if gs == null or typewriter == null:
		return
	var want := String(gs.loc.typewriter)
	if typewriter.loaded_doc_id() == want:
		return
	typewriter.unload_sheet()
	if want != "":
		typewriter.load_sheet(want)


# --- Services --------------------------------------------------------------------------

func _dd():
	return _autoload("DayDirector")


func _gs():
	return _autoload("GameState")


func _autoload(node_name: String) -> Node:
	var tree := get_tree()
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
