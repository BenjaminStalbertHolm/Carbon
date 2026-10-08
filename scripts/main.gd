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
const READ_VIEW_SCENE := preload("res://scenes/ui/read_view.tscn")
const MENU_SCENE := preload("res://scenes/ui/menu_folder.tscn")
const BLACK_SCENE := preload("res://scenes/ui/black_paper.tscn")

const FADE_IN_S := 2.0

## Emitted when the read view closes, with the id of the document on show (spec 6.4).
signal read_view_closed(doc_id: String)

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
var endings_pres = null  # EndingsPresentation: carries out the ending sequences

var _running := false
var _typing_flag := false
var _transition := false
var _read_doc_id := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
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
	endings_pres = EndingsPresentation.new()
	endings_pres.name = "EndingsPresentation"
	add_child(endings_pres)
	endings_pres.setup(self, hall, player, typewriter, black, pipeline)
	endings.setup(endings_pres)
	endings.bind_interaction(interaction, player, desk)
	endings.returned_to_title.connect(_on_endings_returned)


# --- Front-end flow (spec 16.1, 16.2, 13.1) ---------------------------------------------

func _boot() -> void:
	black.set_shade(1.0)
	note = ContentNote.new()
	note.name = "ContentNote"
	add_child(note)
	await note.run()
	note.queue_free()
	title.show_title()


func _on_new_game() -> void:
	if _transition:
		return
	_transition = true
	title.hide_title()
	if endings != null:
		endings.reset()
	_dd().start_new_game()
	player.reset_seated()
	await black.run_day_title(1, true)
	await black.fade_in(FADE_IN_S)
	_begin_running()


## Spec 16.4 autosaves at each day start, so a continue restarts the saved day (begin_day).
func _on_continue() -> void:
	if _transition:
		return
	var save = _autoload("SaveSystem")
	if save == null or not bool(save.load_game()):
		return
	_transition = true
	title.hide_title()
	if endings != null:
		endings.reset()
	player.reset_seated()
	_dd().begin_day(int(_gs().day))
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
	_dd().start_next_day()
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
	_dd().start_new_game(seed_value)
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


func _sync_focus() -> void:
	var focus := is_focus_open() or not _running
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if focus else Input.MOUSE_MODE_CAPTURED
	pipeline.set_focus_view(_typing_flag or (read_view != null and read_view.is_open()))
	var ending_off: bool = endings != null and endings.input_off()
	var desk_off: bool = endings != null and endings.desk_locked()
	player.set_input_enabled(not focus and not ending_off)
	interaction.set_enabled(not focus and not desk_off)


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


func _on_typing_closed() -> void:
	_typing_flag = false


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
