extends Node
## M5 and M6 dev screenshot harness (spec 6.3, 6.5, 7, 8.1, 8.2, 8.5). Builds Hall C under the
## PS1 pipeline, then saves PNGs:
##   m5_1_typing_p1.png   typing view on the Day 1 P-1 form: fields filled, one overstruck cell
##   m5_2_stamp_s1.png    read view on S-1 page 1 with an APPROVED impression (StampView)
##   m5_3_marker_ro2.png  read view on RO-2 with four entries barred (MarkerView)
##   m5_4_carbon.png      read view on the T-1 carbon (filed to the lower drawer in the game)
## Dev-only and excluded from export (tests/*). Run under a virtual display:
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path /home/user/Carbon res://tests/typewriter/m5_shots.tscn -- --out=<dir>

const PsxPipeline := preload("res://scripts/rendering/psx_pipeline.gd")
const HallC := preload("res://scripts/world/hall_c.gd")
const TypewriterView := preload("res://scripts/typewriter/typewriter_view.gd")
const ReadView := preload("res://scripts/doc/read_view.gd")
const StampView := preload("res://scripts/stamps/stamp_view.gd")
const MarkerView := preload("res://scripts/stamps/marker_view.gd")
const DocRenderer := preload("res://scripts/doc/doc_renderer.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")
const Redaction := preload("res://scripts/logic/redaction.gd")

const EYE := Vector3(5.25, 1.15, 4.10)
const SAMPLE_FIELDS := ["MARTA ADLER", "3301447", "2 GLASSWORKS ROW", "YES"]

var _out := "/tmp"
var _pipeline = null
var _hall = null
var _cam: Camera3D = null
var _view = null
var _gs = null
var _dd = null
var _log := PackedStringArray()


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			_out = a.substr(6)
	await get_tree().process_frame
	await _run()
	print("M5 shots written: %s" % ", ".join(_log))
	get_tree().quit(0)


func _run() -> void:
	_gs = get_node("/root/GameState")
	_dd = get_node("/root/DayDirector")
	_gs.new_game(4242)
	_dd.begin_day(1)
	var p1: Dictionary = _dd.instantiate("P-1")
	_gs.add_doc(p1, "inbox")
	var s1: Dictionary = _dd.instantiate("S-1")
	_gs.add_doc(s1, "inbox")
	_dd.active_task = "T-1"
	var sheet_id: String = _dd.take_blank_sheet()
	var carbon_id := String(_gs.docs[sheet_id].twin)
	_gs.place(carbon_id, "drawer")
	_dd.begin_day(2)
	var ro2: Dictionary = _dd.instantiate("RO-2")
	_gs.add_doc(ro2, "inbox")

	_pipeline = PsxPipeline.new()
	add_child(_pipeline)
	_hall = HallC.build(_pipeline.world, {})
	_cam = Camera3D.new()
	_cam.fov = 60.0
	_cam.near = 0.05
	_cam.far = 30.0
	_pipeline.world.add_child(_cam)
	_cam.global_transform = Transform3D(Basis.looking_at(Vector3(0.0, -0.2, -1.0), Vector3.UP), EYE)
	_cam.current = true

	_view = TypewriterView.new()
	add_child(_view)
	_view.setup(_hall, _cam, _pipeline)
	await _frames(3)

	# --- 1. Typing view on P-1 ---------------------------------------------------------
	_view.open_typing_view("P-1")
	await _wait(1.4)
	var fields: Array = _gs.docs["P-1"].pages[0].fields
	for i in range(mini(fields.size(), SAMPLE_FIELDS.size())):
		var f: Dictionary = fields[i]
		_view.click_cell(int(f.line), int(f.col))
		for ch in String(SAMPLE_FIELDS[i]):
			_view.type_char(ch)
	# Overstrike in field 3 (YES): type O, Backspace, then 0, so the cell holds two glyphs.
	var f3: Dictionary = fields[mini(3, fields.size() - 1)]
	_view.click_cell(int(f3.line), int(f3.col))
	_view.type_char("O")
	_view.type_backspace()
	_view.type_char("0")
	await _frames(4)
	await _capture("m5_1_typing_p1.png")
	_view.close_typing_view()
	await _wait(0.7)
	# Full-resolution page of the same P-1 (768 x 1088), for reading the typed values.
	var rr := DocRenderer.new()
	add_child(rr)
	await _frames(2)
	_view.unload_sheet()
	await _frames(2)
	await _capture_texture(rr.page_texture(_gs.docs["P-1"], 0), "m5_1b_p1_page_full.png")

	# A transcription sheet with its carbon: type a line, so the carbon mirrors it (spec 8.5).
	_view.load_sheet(sheet_id)
	for ch in String("THE QUICK BROWN FOX"):
		_view.type_char(ch)
	_view.type_enter()
	for ch in String("JUMPS OVER 13 LAZY DOGS"):
		_view.type_char(ch)
	_view.type_char("X")
	_view.type_backspace()
	_view.type_char("Q")
	await _frames(4)
	_view.unload_sheet()
	await _frames(2)

	# --- 2. Stamp on S-1 page 1 ----------------------------------------------------------
	var rv := ReadView.new()
	add_child(rv)
	var sv := StampView.new()
	add_child(sv)
	sv.attach(rv)
	sv.held_kind_fn = func(): return "stamp:APPROVED"
	rv.open([_gs.docs["S-1"]], 0, "single")
	await _frames(2)
	sv.stamp_at(0, Vector2(DocModel.PAGE_W * 0.5, DocModel.PAGE_H * 0.28))
	await _frames(4)
	await _capture("m5_2_stamp_s1.png")
	rv.close()

	# --- 3. Marker bars on RO-2 (the four entries 03, 05, 09, 10) -------------------------
	var mv := MarkerView.new()
	add_child(mv)
	mv.attach(rv)
	mv.held_kind_fn = func(): return "marker"
	rv.open([_gs.docs["RO-2"]], 0, "single")
	await _frames(2)
	var ro_page: Dictionary = _gs.docs["RO-2"].pages[0]
	for entry in _gs.docs["RO-2"].register:
		if String(entry.key) in ["03", "05", "09", "10"]:
			var ext: Array = Redaction.name_extent(ro_page, String(entry.name))
			if ext.is_empty():
				continue
			var y := DocRenderer.typed_bar_centre_y(int(ext[0]))
			mv.draw_bar(0, Vector2(float(ext[1]) - 2.0, y), Vector2(float(ext[2]) + 2.0, y))
	await _frames(4)
	await _capture("m5_3_marker_ro2.png")
	rv.close()

	# --- 4. Carbon (the T-1 carbon, filed to the lower drawer in the game) ---------------
	rv.open([_gs.docs[carbon_id]], 0, "single")
	await _frames(4)
	await _capture("m5_4_carbon.png")
	rv.close()


func _frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _capture_texture(tex: Texture2D, file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var path := _out.path_join(file_name)
	var err := tex.get_image().save_png(path)
	if err == OK:
		_log.append(path)
	else:
		push_error("m5_shots: could not save %s (%d)" % [path, err])


func _capture(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img: Image = get_viewport().get_texture().get_image()
	var path := _out.path_join(file_name)
	var err := img.save_png(path)
	if err == OK:
		_log.append(path)
	else:
		push_error("m5_shots: could not save %s (%d)" % [path, err])
