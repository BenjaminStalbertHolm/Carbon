extends Node
## StampView: the stamp action in read view (spec 8.1). With a stamp held, a left-click
## on a stampable page calls DayDirector.stamp_document with a random rotation
## (-6 to +6 degrees) and opacity (0.75 to 0.95) from the game RNG. DocRenderer draws
## every impression from page.stamps (spec 8.1 look), so this node draws nothing; it
## refreshes the read view after each stamp.
##
## Right-click in read view while holding a stamp returns it to the rack and keeps the
## read view open. The next right-click closes it (spec 8.1). The read view's
## close_on_right_click flag is kept in step with the hand every frame.
##
## Use: add to the main tree, call attach(read_view) and set the hand hooks:
##   held_kind_fn: () -> String   ("stamp:APPROVED", ..., "" when empty)
##   held_release_fn: () -> String (returns the hand to its home)

const TypewriterSounds := preload("res://scripts/typewriter/typewriter_sounds.gd")

signal stamped(doc_id: String, page_index: int, result: String)

const ROT_DEG := 6.0
const OPACITY_MIN := 0.75
const OPACITY_MAX := 0.95
## Desk 4 centre top (spec 11.4): stamp and marker sounds are positional here.
const DESK_TOP := Vector3(5.25, 0.76, 3.5)

var held_kind_fn := Callable()
var held_release_fn := Callable()
var stamp_position := DESK_TOP

var _read_view = null  # ReadView (untyped: its signals and methods are used directly)
var _sounds := TypewriterSounds.new()


func _ready() -> void:
	_sounds.position = stamp_position


func _process(_delta: float) -> void:
	if _read_view != null:
		_read_view.close_on_right_click = not _holding_any()


## Connects to a ReadView (doc/read_view.gd). Safe to call once.
func attach(read_view) -> void:
	_read_view = read_view
	if read_view == null:
		return
	if not read_view.page_clicked.is_connected(_on_page_clicked):
		read_view.page_clicked.connect(_on_page_clicked)
	if not read_view.right_clicked.is_connected(_on_right_clicked):
		read_view.right_clicked.connect(_on_right_clicked)


func holding_stamp() -> bool:
	return _held_kind().begins_with("stamp:")


## The result of the held stamp ("APPROVED", "DENIED", "PROCESSED", "RETURNED"), or "".
func held_result() -> String:
	var kind := _held_kind()
	return kind.substr(6) if kind.begins_with("stamp:") else ""


## Stamps the current page of the read view at a page point. Returns true when
## DayDirector accepted the stamp. Public so tests can drive it without a click.
func stamp_at(page_index: int, pos: Vector2) -> bool:
	var result := held_result()
	if result == "" or _read_view == null:
		return false
	var doc: Dictionary = _read_view.current_doc()
	if doc.is_empty():
		return false
	var rng := _rng()
	var rot := rng.randf_range(-ROT_DEG, ROT_DEG) if rng != null else 0.0
	var a := rng.randf_range(OPACITY_MIN, OPACITY_MAX) if rng != null else OPACITY_MAX
	var dd = _autoload("DayDirector")
	if dd == null:
		return false
	var doc_id := String(doc.id)
	if not dd.stamp_document(doc_id, page_index, result, pos.x, pos.y, rot, a):
		return false
	_sounds.play("stamp_thud", stamp_position, 0.0, true)
	_read_view.refresh()
	stamped.emit(doc_id, page_index, result)
	return true


func _on_page_clicked(page_index: int, pos: Vector2) -> void:
	if holding_stamp():
		stamp_at(page_index, pos)


func _on_right_clicked() -> void:
	if holding_stamp() and held_release_fn.is_valid():
		held_release_fn.call()


func _holding_any() -> bool:
	return _held_kind().begins_with("stamp:") or _held_kind() == "marker"


func _held_kind() -> String:
	return String(held_kind_fn.call()) if held_kind_fn.is_valid() else ""


func _rng() -> RandomNumberGenerator:
	var gs = _autoload("GameState")
	return gs.rng if gs != null else null


func _autoload(node_name: String) -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(node_name)
