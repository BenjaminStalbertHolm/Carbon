extends Node
## EndingsController (spec 15). Listens to DayDirector.ro5_sent and decides Ending A, or the
## refusal (which leads to Ending B by the exit, or Ending C by the carbon stack). It owns the
## endings' input flags, which main.gd reads, runs the sequences (ending_a/b/c.gd), and forwards
## their signals to the presentation (endings_presentation.gd). Every signal with the same name as
## a presentation method is connected to it, so the sequences never reference the scene.
##
## main.gd reads: menu_locked() (Esc, spec 15), desk_locked() (no desk interaction, read view
## included), standing_locked(), typing_locked(), input_off() (no walking or looking),
## walk_look() and lamp_locked(). reset() runs at a new game and at a continue.
##
## Wiring (main.gd): setup(presentation) once; bind_interaction(interaction, player, desk) once.

const EndingClock := preload("res://scripts/endings/ending_clock.gd")
const EndingA := preload("res://scripts/endings/ending_a.gd")
const EndingB := preload("res://scripts/endings/ending_b.gd")
const EndingC := preload("res://scripts/endings/ending_c.gd")
const StandingGuard := preload("res://scripts/endings/standing_guard.gd")
const EndingsLogic := preload("res://scripts/logic/endings.gd")
const Content := preload("res://scripts/logic/content.gd")
const Doc := preload("res://scripts/logic/doc_model.gd")
const CreditsScene := preload("res://scripts/ui/credits.gd")

## Emitted after the credits, when the game returns to the title (spec 15.4, 16.2).
signal returned_to_title

## Signals the controller handles itself. Every other sequence signal goes to the presentation.
const CONTROLLER_SIGNALS := ["set_input_mode", "ending_set", "credits_requested"]

var presentation = null
var clock = null

var ro5_sent := false
var refused := false
var exit_unlocked := false
var ending_id := "none"
var lamp_locked_flag := false
var _mode := "open"  # "open", "walk_look", "look_only" or "off" (set by the sequences)
var _standing_forced := false  # Ending A from RO-5 (spec 15.1 step 1)
var _typing_forced := false  # Ending A from RO-5 (spec 15.1 step 1)
var _exit_started := false
var _ending_running := false
var _a = null
var _b = null
var _c = null
var _player = null
var _desk = null
var _credits_enabled := true
var _ro5_connected := false


## presentation: the object that carries out every visible or audible action (see endings_presentation.gd).
## clock_ref: an EndingClock, or null for real time.
func setup(presentation_ref, clock_ref = null) -> void:
	presentation = presentation_ref
	clock = clock_ref if clock_ref != null else EndingClock.new(false, get_tree())
	var dd = _autoload("DayDirector")
	if dd != null and not _ro5_connected:
		dd.ro5_sent.connect(_on_ro5_sent)
		_ro5_connected = true


## Connects the interaction's action signal, and gives the player the standing guard (spec 15.1).
func bind_interaction(interaction: Node, player: Node, desk: Node) -> void:
	_player = player
	_desk = desk
	if interaction != null and not interaction.action_pressed.is_connected(_on_action):
		interaction.action_pressed.connect(_on_action)
	if player != null and player.get_node_or_null("StandingGuard") == null:
		var guard := StandingGuard.new()
		guard.name = "StandingGuard"
		guard.controller = self
		player.add_child(guard)


## Credits can be turned off for a test. Off, the controller returns to the title at once.
func set_credits_enabled(on: bool) -> void:
	_credits_enabled = on


## A new game or a continue: no ending has run and the flags are back to normal.
func reset() -> void:
	ro5_sent = false
	refused = false
	exit_unlocked = false
	ending_id = "none"
	lamp_locked_flag = false
	_mode = "open"
	_standing_forced = false
	_typing_forced = false
	_exit_started = false
	_ending_running = false
	_a = null
	_b = null
	_c = null


# --- Flags read by main.gd ----------------------------------------------------------------

func menu_locked() -> bool:
	return ro5_sent


func desk_locked() -> bool:
	return _mode != "open"


func standing_locked() -> bool:
	return _standing_forced or _mode == "off" or _mode == "look_only"


func typing_locked() -> bool:
	return _typing_forced or _mode != "open"


func input_off() -> bool:
	return _mode == "off"


func walk_look() -> bool:
	return _mode == "walk_look"


func lamp_locked() -> bool:
	return lamp_locked_flag


func ending_running() -> bool:
	return _ending_running


# --- RO-5 -----------------------------------------------------------------------------------

func _on_ro5_sent(desk4_redacted: bool) -> void:
	if ro5_sent:
		return
	ro5_sent = true
	if desk4_redacted:
		# Spec 15.1: Ending A regardless of the stamp. Standing and typing are disabled from now on.
		_standing_forced = true
		_typing_forced = true
		_ending_running = true
		_a = EndingA.new()
		var lit := _lit_state()
		var ids := _texts()
		_a.setup(clock, lit, String(ids.a_ghost), String(ids.a_title), Callable(presentation, "has_paper"),
			Callable(presentation, "ghost_idle"), Callable(presentation, "key_delay_ms"), _rng())
		_wire(_a)
		_a.ending_set.connect(_on_ending_set)
		_a.credits_requested.connect(_on_credits_requested)
		_a.set_input_mode.connect(_on_input_mode)
		_a.run()
	else:
		# Spec 15.2 step 1: the refusal. The exit unlocks 5.0 s after RO-5, with the memo.
		refused = true
		lamp_locked_flag = true
		var ids := _texts()
		_b = EndingB.new()
		_b.setup(clock, String(ids.b_end), Callable(presentation, "player_crossed"),
			Callable(presentation, "figure_distance"))
		_wire(_b)
		_b.exit_unlocked.connect(_on_exit_unlocked)
		_b.ending_set.connect(_on_ending_set)
		_b.credits_requested.connect(_on_credits_requested)
		_b.set_input_mode.connect(_on_input_mode)
		_b.run_refusal()


func _on_exit_unlocked() -> void:
	exit_unlocked = true


# --- Actions from the interaction (spec 8.13, 15.2, 15.3) ---------------------------------

func _on_action(action: String, _node: Variant, _pos: Variant) -> void:
	if action == "door_exit":
		_on_exit_handle()
	elif action == "carbon_spot":
		_on_carbon_stack()


func _on_exit_handle() -> void:
	if _ending_running and not refused:
		return
	if not exit_unlocked:
		if presentation != null and presentation.has_method("door_rattle"):
			presentation.door_rattle()
		return
	if _exit_started or _b == null:
		return
	_exit_started = true
	_ending_running = true
	_b.run_exit()


## Spec 15.3: a click on the carbon stack while seated, with the lower drawer closed, starts Ending C
## when at least three transcription carbons are kept. A hold is a pick-up, not a click.
func _on_carbon_stack() -> void:
	if not refused or _ending_running or _c != null:
		return
	if _player == null or not bool(_player.is_seated()):
		return
	if _desk != null and bool(_desk.drawer_open("lower")):
		return
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	var gs = _gs()
	if gs == null or not EndingsLogic.ending_c_available(int(gs.carbons_kept_at_final)):
		return
	_start_ending_c()


func _start_ending_c() -> void:
	var gs = _gs()
	var dd = _autoload("DayDirector")
	var tt = _autoload("TextTokens")
	var ids := _texts()
	var registers := {}
	for order_id in ["RO-2", "RO-3", "RO-4"]:
		registers[order_id] = dd._register_of(order_id) if dd != null else []
	var player_name := String(tt.token_values().PLAYER_NAME) if tt != null else ""
	var lines: Array = EndingsLogic.ending_c_lines(gs.ro_results, registers, player_name, tt.subst_callable(), ids.c_record)
	var restore: Array = EndingsLogic.desks_to_restore(gs.ro_results, registers)
	_ending_running = true
	_c = EndingC.new()
	_c.setup(clock, lines, restore, _lit_state(), bool(presentation.has_paper()),
		Callable(presentation, "ghost_idle"), ids.c_title)
	_wire(_c)
	_c.ending_set.connect(_on_ending_set)
	_c.credits_requested.connect(_on_credits_requested)
	_c.set_input_mode.connect(_on_input_mode)
	_c.run()


# --- Shared sequence handling ---------------------------------------------------------------

## Connects every sequence signal to the presentation method of the same name (when it has one).
func _wire(seq: Object) -> void:
	for info in seq.get_signal_list():
		var sig := String(info.name)
		if CONTROLLER_SIGNALS.has(sig):
			continue
		if presentation != null and presentation.has_method(sig):
			seq.connect(sig, Callable(presentation, sig))


func _on_input_mode(mode: String) -> void:
	_mode = mode


func _on_ending_set(id: String) -> void:
	ending_id = id
	var gs = _gs()
	if gs != null:
		gs.ending = id


func _on_credits_requested() -> void:
	if not _credits_enabled:
		_finish_to_title()
		return
	var credits = CreditsScene.new()
	add_child(credits)
	await credits.run()
	credits.queue_free()
	_finish_to_title()


func _finish_to_title() -> void:
	_ending_running = false
	_mode = "off"
	returned_to_title.emit()


# --- Data --------------------------------------------------------------------------------

## The text of the endings, copied from data/endings.json and data/strings.json (never retyped).
func _texts() -> Dictionary:
	var e: Dictionary = Content.endings()
	var a: Dictionary = e["A"]
	var b: Dictionary = e["B"]
	var c: Dictionary = e["C"]
	return {
		"a_ghost": String(a["ghost_lines"][0]),
		"a_title": String(a["title_lines"][0]),
		"b_end": String(b["end_lines"][0]),
		"c_record": String(c["carbon_ghost_lines_fixed"][0]),
		"c_title": String(c["title_lines"][0]),
	}


func _lit_state() -> Dictionary:
	var gs = _gs()
	var out := {}
	if gs == null:
		return out
	for f in range(1, 7):
		out[str(f)] = bool(gs.fixture_lit.get(str(f), false))
	return out


func _rng() -> RandomNumberGenerator:
	var gs = _gs()
	if gs != null:
		return gs.rng
	return RandomNumberGenerator.new()


func _gs():
	return _autoload("GameState")


func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
