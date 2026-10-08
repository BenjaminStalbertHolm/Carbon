extends Node3D
## HeldItem: the one item the player holds (spec 6.4). It is a presentation node attached to the
## player's camera, so the item stays at the lower right of the view. A document is a small paper
## quad with its page texture; a stamp, the marker and the correction bottle are small props.
## Ownership: interaction.gd decides what is held (its hand_* functions). This node only shows it.
##
## hold(kind, id, texture) builds the visual. release() removes it at once; release_home(pos)
## first slides it to the home position on the desk over 0.25 s, then removes it.

const Geo := preload("res://scripts/world/geometry.gd")
const PaperQuad := preload("res://scripts/doc/paper_quad.gd")
const TextTex := preload("res://scripts/world/text_texture.gd")

const HOME_S := 0.25
const DOC_POS := Vector3(0.13, -0.12, -0.36)
const DOC_SCALE := 0.4
const DOC_TILT := Vector3(-14.0, -14.0, 6.0)
const PROP_POS := Vector3(0.14, -0.14, -0.34)
const PROP_TILT := Vector3(-50.0, 0.0, 0.0)
const COL_MARKER := Color("#0E0E0E")
const COL_CORRECTION := Color("#F2EEE2")
const COL_CAP := Color("#2A2A2A")
const BAND := {
	"APPROVED": Color("#2F3B5C"),
	"PROCESSED": Color("#2F3B5C"),
	"DENIED": Color("#8E2A22"),
	"RETURNED": Color("#8E2A22"),
}

var _kind := ""
var _id := ""
var _visual: Node3D = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE


func kind() -> String:
	return _kind


func doc_id() -> String:
	return _id


func is_holding() -> bool:
	return _kind != ""


## Shows the held item. texture is the page texture for a document (null uses blank paper).
func hold(item_kind: String, id: String = "", texture: Texture2D = null) -> void:
	release()
	_kind = item_kind
	_id = id
	_visual = _make_visual(item_kind, texture)
	add_child(_visual)


## Removes the visual at once. Returns the kind that was held ("" when empty).
func release() -> String:
	var k := _kind
	if _visual != null:
		_visual.queue_free()
		_visual = null
	_kind = ""
	_id = ""
	return k


## Slides the visual to home_world (a global position) and then removes it. Returns the kind.
func release_home(home_world: Vector3) -> String:
	if _visual == null or not home_world.is_finite():
		return release()
	var k := _kind
	var v := _visual
	_visual = null
	_kind = ""
	_id = ""
	if v.is_inside_tree():
		var tw := create_tween()
		tw.tween_property(v, "global_position", home_world, HOME_S)
		tw.tween_callback(v.queue_free)
	else:
		v.queue_free()
	return k


func _make_visual(item_kind: String, texture: Texture2D) -> Node3D:
	if item_kind == "document":
		var tex: Texture2D = texture if texture != null else Geo.TEX_PAPER
		var quad := PaperQuad.make(tex, PaperQuad.SIZE)
		quad.position = DOC_POS
		quad.rotation_degrees = DOC_TILT
		quad.scale = Vector3(DOC_SCALE, DOC_SCALE, 1.0)
		return quad
	var prop := Node3D.new()
	prop.position = PROP_POS
	prop.rotation_degrees = PROP_TILT
	if item_kind.begins_with("stamp:"):
		var result := item_kind.substr(6)
		var label: Texture2D = TextTex.stamp_label(BAND.get(result, Color("#2F3B5C")))
		prop.add_child(Geo.cylinder(0.015, 0.07, 8, Geo.WHITE, "Handle", true, true, label))
		prop.add_child(Geo.solid(Vector3(0.05, 0.02, 0.03), COL_CAP, "Base"))
		prop.get_child(1).position = Vector3(0.0, -0.045, 0.0)
	elif item_kind == "marker":
		prop.add_child(Geo.cylinder(0.008, 0.13, 8, COL_MARKER, "Marker"))
	elif item_kind == "fluid":
		prop.add_child(Geo.cylinder(0.015, 0.05, 8, COL_CORRECTION, "Bottle"))
		var cap := Geo.cylinder(0.008, 0.02, 8, COL_CAP, "Cap")
		cap.position = Vector3(0.0, 0.035, 0.0)
		prop.add_child(cap)
	return prop
