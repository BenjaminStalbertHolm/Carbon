extends Node
## Dev-only screenshot harness for the document renderer (spec 6.5, 6.3). Renders
## every Day 1 document page to PNG at 768 x 1088, plus a carbon, a page with a
## marker bar, a text bar from a redacted name, a stamp demo (on a copy), and
## read views at 1280 x 960. Run under a virtual display:
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . res://tests/doc/doc_render_shots.tscn -- --out=/abs/dir
## --out sets the output folder (default user://doc_shots). Excluded from exports.

const DocRenderer := preload("res://scripts/doc/doc_renderer.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")
const Content := preload("res://scripts/logic/content.gd")
const NotebookView := preload("res://scripts/doc/notebook_view.gd")
const ReadViewScene := preload("res://scenes/ui/read_view.tscn")

const DAY1 := ["M1-WELCOME", "P-1", "T-1-COVER", "L-1", "S-1-COVER", "S-1", "EOS-STANDARD", "NB-1"]

var _out := "user://doc_shots"
var _abs := ""
var _renderer: Node
var _tt  # TextTokens autoload
var _gs  # GameState autoload
var _log := PackedStringArray()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out = arg.substr(6)
	_abs = ProjectSettings.globalize_path(_out) if _out.begins_with("user://") else _out
	DirAccess.make_dir_recursive_absolute(_abs)
	_tt = get_node("/root/TextTokens")
	_gs = get_node("/root/GameState")
	_renderer = DocRenderer.new()
	add_child(_renderer)
	await get_tree().process_frame
	await _run()
	print("SHOTS written to %s" % _abs)
	for line in _log:
		print(line)
	get_tree().quit(0)


func _build(id: String, n: int = 1) -> Dictionary:
	var st := Content.strings()
	var spec: Dictionary = Content.day(n).documents[id]
	return DocModel.build_doc(id, spec, _tt.subst_callable(), st.memo_header, String(st.memo_re_line), Content.layouts().app_r2.lines)


## Waits until the viewports have drawn, then saves each texture as a PNG.
func _save_textures(items: Array) -> void:
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	for item in items:
		var img: Image = (item[1] as Texture2D).get_image()
		var path := "%s/%s.png" % [_abs, String(item[0])]
		var err := img.save_png(path)
		_log.append("%s %dx%d err=%d" % [path, img.get_width(), img.get_height(), err])


func _run() -> void:
	# 1. Every Day 1 page as its own texture.
	var items: Array = []
	for id in DAY1:
		var doc := _build(id)
		for i in range(doc.pages.size()):
			items.append(["day1_%s_p%d" % [id, i + 1], _renderer.page_texture(doc, i)])
	await _save_textures(items)

	# 2. A typed sheet with glyphs, overstrike, whiteout, a red insert, and its carbon.
	var rng := RandomNumberGenerator.new()
	rng.seed = 412
	var sheet := DocModel.new_doc("SHEET-SHOT", "sheet")
	var page := DocModel.new_page()
	var lines := [
		"ATTACHED: CORRESPONDENCE RECEIVED, WARD VII.",
		"TYPE A CLEAN COPY FOR THE ARCHIVE.",
		"DO NOT CORRECT THE CITIZEN'S GRAMMAR.",
	]
	for l in range(lines.size()):
		for c in range(lines[l].length()):
			DocModel.write_glyph(page, l, c, String(lines[l]).substr(c, 1), rng)
	DocModel.write_glyph(page, 3, 0, "E", rng)
	DocModel.write_glyph(page, 3, 0, "A", rng)  # overstrike: two glyphs in one cell
	for c in range(10):
		DocModel.write_glyph(page, 5, c, "XXXXXXXXXX".substr(c, 1), rng)
	DocModel.whiteout(page, 5, 3, rng)
	DocModel.write_glyph(page, 5, 3, "Q", rng)
	for c in range(12):
		DocModel.write_glyph(page, 7, c, "ADD: TRIAL".substr(c, 1), rng, "red")
	sheet.pages.append(page)
	var carbon := DocModel.make_carbon(sheet, "CARBON-SHOT")
	await _save_textures([
		["typed_sheet_p1", _renderer.page_texture(sheet, 0)],
		["carbon_p1", _renderer.page_texture(carbon, 0)],
	])

	# 3. A marker bar on a page, and a page with a text bar from a redacted name.
	DocModel.add_bar(page, 1, DocModel.LEFT + 8 * DocModel.COL_W, DocModel.LEFT + 30 * DocModel.COL_W)
	var bar_items := [["typed_sheet_marker_bar_p1", _renderer.page_texture(sheet, 0)]]
	await _save_textures(bar_items)

	var saved_names: Array = _gs.redacted_names.duplicate()
	_gs.redacted_names = ["aurel", "vance"]
	var s1 := _build("S-1")
	var nb1 := _build("NB-1")
	await _save_textures([
		["redacted_S-1_p3", _renderer.page_texture(s1, 2)],
		["redacted_NB-1", _renderer.page_texture(nb1, 0)],
	])
	_gs.redacted_names = saved_names

	# 4. Stamp demo on a copy of S-1 page 1 (the real page has no stamps).
	var demo := _build("S-1")
	var dp: Dictionary = demo.pages[0]
	DocModel.add_stamp(dp, "APPROVED", "APPROVED", "#2F3B5C", 300.0, 420.0, -4.0, 0.85, 1201)
	DocModel.add_stamp(dp, "DENIED", "DENIED", "#8E2A22", 430.0, 640.0, 5.0, 0.8, 1202)
	DocModel.add_stamp(dp, "RETURNED — UNPROCESSED", "RETURNED", "#8E2A22", 300.0, 820.0, -2.0, 0.9, 1203)
	DocModel.add_stamp(dp, "NO SUCH ADDRESSEE", "NO SUCH ADDRESSEE", "red", 384.0, 181.3, 0.0, 0.9, 1204)
	demo.id = "S-1-DEMO"
	await _save_textures([["stamp_demo_S-1_p1", _renderer.page_texture(demo, 0)]])

	# 5. Read views at 1280 x 960.
	var rv = ReadViewScene.instantiate()
	add_child(rv)
	rv.text_assist_override = 0
	await _capture_view(rv, [_build("P-1")], 0, "single", "read_P-1")
	await _capture_view(rv, [_build("L-1")], 0, "single", "read_L-1_letter")
	rv.text_assist_override = 1
	await _capture_view(rv, [_build("P-1")], 0, "single", "read_P-1_text_assist")
	rv.text_assist_override = 0
	await _capture_view(rv, [demo], 0, "single", "read_S-1_stamp_demo")
	_gs.redacted_names = ["aurel", "vance"]
	await _capture_view(rv, [_build("NB-1")], 0, "single", "read_NB-1_vance_bar")
	rv.text_assist_override = 1
	rv.open([_build("S-1")], 0, "single")
	rv.step(2)
	await _capture_view(rv, [], 0, "single", "read_S-1_p3_text_assist_bar", false)
	rv.text_assist_override = 0
	_gs.redacted_names = saved_names
	NotebookView.open(rv, 1)
	await _capture_view(rv, [], 0, "single", "notebook_day1", false)
	rv.close()


func _capture_view(rv, docs: Array, start: int, mode: String, name: String, open_docs: bool = true) -> void:
	if open_docs:
		rv.open(docs, start, mode)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s.png" % [_abs, name]
	var err := img.save_png(path)
	_log.append("%s %dx%d err=%d" % [path, img.get_width(), img.get_height(), err])
	rv.close()
