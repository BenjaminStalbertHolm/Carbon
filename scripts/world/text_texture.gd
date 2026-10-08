extends RefCounted
## Runtime textures for 3D signs (spec 5.5) and the Desk 4 stamp labels (spec 5.4).
## Text textures are SubViewports holding a background and Special Elite labels.
## A ViewportTexture updates in place, so a surface can use it as soon as the
## SubViewport is in the tree. Nothing here is a new asset file.

const FONT := preload("res://assets/fonts/SpecialElite-Regular.ttf")
const TEX_CHALK := preload("res://assets/textures/chalk_board.png")

const COL_PLATE_BODY := Color("#2A2A28")
const COL_PLATE_LETTERS := Color("#C8C2AE")
const COL_FROSTED := Color("#B0B8B0")
const COL_SIGN_TEXT := Color("#2A2A28")
const COL_WALL_UPPER := Color("#B7B39A")
const COL_CHALK := Color("#C9CCC0")
const COL_KEYCAP := Color("#1E1E1C")
const COL_LEGEND := Color("#D8D2BE")
const COL_PAPER := Color("#E6DFC8")

const KEY_LEGENDS := [
	["2", "3", "4", "5", "6", "7", "8", "9", "0", "-"],
	["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
	["A", "S", "D", "F", "G", "H", "J", "K", "L", ";"],
	["Z", "X", "C", "V", "B", "N", "M", ",", ".", "/"],
]
const KEYCAP_CELL := 16
const KEYCAP_ATLAS := Vector2i(160, 64)


## Viewport holding a solid background, an optional texture behind it, and labels.
## labels: Array of entries from label_entry().
static func sheet(host: Node, size: Vector2i, bg: Color, labels: Array, bg_texture: Texture2D = null) -> ViewportTexture:
	var vp := SubViewport.new()
	vp.size = size
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.name = "TextSheet"
	host.add_child(vp)
	var back := ColorRect.new()
	back.color = bg
	back.position = Vector2.ZERO
	back.size = Vector2(size)
	vp.add_child(back)
	if bg_texture != null:
		var pic := TextureRect.new()
		pic.texture = bg_texture
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.position = Vector2.ZERO
		pic.size = Vector2(size)
		vp.add_child(pic)
	for entry in labels:
		var label := Label.new()
		label.text = entry["text"]
		label.position = entry["rect"].position
		label.size = entry["rect"].size
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.add_theme_font_override("font", FONT)
		label.add_theme_font_size_override("font_size", entry["size"])
		label.add_theme_color_override("font_color", entry["colour"])
		vp.add_child(label)
	return vp.get_texture()


static func label_entry(text: String, rect: Rect2, font_size: int, colour: Color) -> Dictionary:
	return {"text": text, "rect": rect, "size": font_size, "colour": colour}


## Largest font size from max_size down to min_size whose text fits in max_w pixels.
static func fit_font_size(text: String, max_w: float, max_size: int, min_size: int = 6) -> int:
	var size := max_size
	while size > min_size and FONT.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > max_w:
		size -= 1
	return size


## Desk nameplate, 64 x 16 px, uppercase, centred (spec 5.5). Empty text gives a blank plate.
static func nameplate(host: Node, text: String) -> ViewportTexture:
	var upper := text.to_upper()
	var size := fit_font_size(upper, 60.0, 10)
	var labels := [label_entry(upper, Rect2(0, 0, 64, 16), size, COL_PLATE_LETTERS)]
	return sheet(host, Vector2i(64, 16), COL_PLATE_BODY, labels)


## "SUPERVISOR" label painted on the frosted glass, 128 x 24 px (spec 5.5).
static func supervisor_label(host: Node) -> ViewportTexture:
	var labels := [label_entry("SUPERVISOR", Rect2(0, 0, 128, 24), 18, COL_SIGN_TEXT)]
	return sheet(host, Vector2i(128, 24), COL_FROSTED, labels)


## "EXIT" sign, 64 x 24 px, #2A2A28 on the wall upper colour (spec 5.5).
static func exit_sign(host: Node) -> ViewportTexture:
	var labels := [label_entry("EXIT", Rect2(0, 0, 64, 24), 16, COL_SIGN_TEXT)]
	return sheet(host, Vector2i(64, 24), COL_WALL_UPPER, labels)


## Quota board chalk text, 256 x 160 px, Special Elite 28 px (spec 8.11).
static func quota_board(host: Node, occupied: int) -> ViewportTexture:
	var labels := [
		label_entry("HALL C", Rect2(0, 22, 256, 36), 28, COL_CHALK),
		label_entry("QUOTA", Rect2(0, 62, 256, 36), 28, COL_CHALK),
		label_entry("%d/12" % occupied, Rect2(0, 102, 256, 36), 28, COL_CHALK),
	]
	return sheet(host, Vector2i(256, 160), COL_KEYCAP, labels, TEX_CHALK)


## One texture for all 40 keycaps: 10 columns by 4 rows of 16 px cells, the legend
## for each key in a cell. The background is the keycap colour, so the sides of a
## keycap can sample a background texel (spec 5.4).
static func keycap_atlas(host: Node) -> ViewportTexture:
	var labels: Array = []
	for r in KEY_LEGENDS.size():
		for c in 10:
			var rect := Rect2(c * KEYCAP_CELL, r * KEYCAP_CELL, KEYCAP_CELL, KEYCAP_CELL)
			labels.append(label_entry(KEY_LEGENDS[r][c], rect, 12, COL_LEGEND))
	return sheet(host, KEYCAP_ATLAS, COL_KEYCAP, labels)


## UV rectangle of one keycap cell in the atlas.
static func keycap_uv(row: int, col: int) -> Rect2:
	return Rect2(
		float(col * KEYCAP_CELL) / float(KEYCAP_ATLAS.x),
		float(row * KEYCAP_CELL) / float(KEYCAP_ATLAS.y),
		float(KEYCAP_CELL) / float(KEYCAP_ATLAS.x),
		float(KEYCAP_CELL) / float(KEYCAP_ATLAS.y))


## A UV point on the keycap background (top-left texel of the first cell's corner).
static func keycap_side_uv() -> Rect2:
	return Rect2(0.5 / float(KEYCAP_ATLAS.x), 0.5 / float(KEYCAP_ATLAS.y), 0.0, 0.0)


## Stamp handle label, 16 x 8 px: paper colour with a coloured band across rows 2-5 (spec 5.4).
static func stamp_label(band: Color) -> ImageTexture:
	var img := Image.create(16, 8, false, Image.FORMAT_RGB8)
	img.fill(COL_PAPER)
	img.fill_rect(Rect2i(0, 2, 16, 4), band)
	return ImageTexture.create_from_image(img)
