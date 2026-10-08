extends Node
## DocRenderer: draws document pages into SubViewport textures (spec 6.5, 7.6,
## 8.1, 8.2, 8.5, 8.6, 14.13). Every page is 768 x 1088 px.
##
## Add this node to the scene tree before use. The SubViewports it creates are
## its children, and they only render while inside the tree.
##
##   page_texture(doc, page_index) -> ViewportTexture   cached per page content
##   release_doc(doc_id)                                 frees that doc's viewports
##
## Static helpers, usable without a node (read view, text assist, marker, tests):
##   cell_origin(line, col), cell_at_px(px), typed_bar_centre_y(line),
##   hand_rows(page), row_text(page, line), hand_wrap(text), hand_width(text),
##   text_bar_spans(doc, page, bars_fn), bar_rects(doc, page, bars_fn),
##   bars_callable()
##
## Redaction bars for text come from TextTokens.bar_spans, which is skipped on
## carbons (spec 8.7). The page cache key includes the redaction context, so a
## change to redacted names or the retired word redraws the page.

const DocModel := preload("res://scripts/logic/doc_model.gd")

const PAGE_SIZE := Vector2i(768, 1088)
const FONT_TYPED := preload("res://assets/fonts/SpecialElite-Regular.ttf")
const FONT_HAND := preload("res://assets/fonts/HomemadeApple-Regular.ttf")
const TEX_PAPER := preload("res://assets/textures/paper.png")
const TEX_ONION := preload("res://assets/textures/onionskin.png")

const TYPED_SIZE := 22
const HAND_SIZE := 26
const HAND_OPACITY := 0.9
const HAND_WIDTH := 656.0  # 768 - 2 x 56 (spec 6.5)
const HAND_ROWS_MAX := 30  # (1088 - 48) / 34, rounded down
const NO_SUCH_SIZE := 30
const STAMP_SIZE := 34
const STAMP_SIZE_LONG := 24
const STAMP_W := 260.0
const STAMP_H := 70.0
const STAMP_BORDER := 4.0
const STAMP_KNOCK := 0.2
const BAR_H := 16.0
const STRIKE_H := 2.0
const BLOB_HALF_W := 6.0
const BLOB_HALF_H := 10.0
const CARBON_BLUR := 0.6
const CARBON_OPACITY := 0.85

# Style keys that match data/strings.json (stamp_words, no_such_addressee).
const NO_SUCH_WORD := "NO SUCH ADDRESSEE"
const STAMP_LONG_WORD := "RETURNED — UNPROCESSED"

const COL_INK := Color("#1C1B19")
const COL_RED := Color("#8E2A22")
const COL_CARBON := Color("#2B2F45")
const COL_BAR := Color("#0E0E0E")
const COL_FLUID := Color("#F2EEE2")
const COL_PAPER := Color("#E6DFC8")
const COL_STAMP_BLUE := Color("#2F3B5C")

var _cache := {}  # "doc_id|page_index" -> {"hash": int, "vp": SubViewport}


## One page's drawing surface. Lives inside a SubViewport.
class PageDraw extends Node2D:
	var doc: Dictionary = {}
	var page_index := 0
	var bars_fn: Callable

	func _draw() -> void:
		paint_page(self, doc, page_index, bars_fn)


# --- Cached textures ---------------------------------------------------------------

## Texture of one page (spec 6.5). Rendered once, then reused until the page's
## content or its redaction context changes. The old viewport is freed then, so
## callers that hold a texture must ask again after a change (ReadView.refresh()).
func page_texture(doc: Dictionary, page_index: int) -> ViewportTexture:
	if page_index < 0 or page_index >= doc.pages.size():
		push_error("DocRenderer: page %d out of range for %s" % [page_index, String(doc.id)])
		return null
	var key := "%s|%d" % [String(doc.id), page_index]
	var h := _page_hash(doc, page_index)
	if _cache.has(key):
		var entry: Dictionary = _cache[key]
		if int(entry.hash) == h and is_instance_valid(entry.vp):
			return entry.vp.get_texture()
		_free_entry(key)
	var vp := SubViewport.new()
	vp.size = PAGE_SIZE
	vp.disable_3d = true
	vp.transparent_bg = false
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.name = "Page"
	var draw := PageDraw.new()
	draw.doc = doc.duplicate(true)
	draw.page_index = page_index
	draw.bars_fn = bars_callable()
	vp.add_child(draw)
	add_child(vp)
	_cache[key] = {"hash": h, "vp": vp}
	return vp.get_texture()


## Frees every cached page of one document.
func release_doc(doc_id: String) -> void:
	for key in _cache.keys():
		if String(key).begins_with(doc_id + "|"):
			_free_entry(key)


func _free_entry(key: String) -> void:
	var entry: Dictionary = _cache[key]
	if is_instance_valid(entry.vp):
		entry.vp.queue_free()
	_cache.erase(key)


func _page_hash(doc: Dictionary, page_index: int) -> int:
	var ctx: Array = [doc.get("carbon", false), doc.get("style", ""), doc.get("ink", ""), doc.pages[page_index]]
	var gs := _game_state()
	if gs != null:
		ctx.append([gs.day, gs.redacted_names, gs.fond_word])
	return JSON.stringify(ctx).hash()


static func _game_state() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("GameState")


## Callable for TextTokens.bar_spans, or an invalid Callable when the autoload
## is missing (then no text bars are drawn).
static func bars_callable() -> Callable:
	var tt := text_tokens_node()
	if tt == null:
		return Callable()
	return Callable(tt, "bar_spans")


# --- Geometry (spec 6.5) -------------------------------------------------------------

## Top-left of a typed cell in page pixels (the top of its line box).
static func cell_origin(line: int, col: int) -> Vector2:
	return Vector2(DocModel.LEFT + col * DocModel.COL_W, DocModel.TOP + line * DocModel.LINE_H)


## Inverse of cell_origin: the (line, col) cell holding a page pixel, as Vector2i(line, col).
static func cell_at_px(px: Vector2) -> Vector2i:
	var col := int(floor((px.x - DocModel.LEFT) / DocModel.COL_W))
	var line := int(floor((px.y - DocModel.TOP) / DocModel.LINE_H))
	return Vector2i(line, col)


static func typed_baseline(line: int) -> float:
	return DocModel.TOP + line * DocModel.LINE_H + FONT_TYPED.get_ascent(TYPED_SIZE)


static func typed_bar_centre_y(line: int) -> float:
	return DocModel.TOP + (line + 0.5) * DocModel.LINE_H


static func hand_row_top(row: int) -> float:
	return DocModel.HAND_TOP + row * DocModel.HAND_LINE_H


static func hand_baseline(row: int) -> float:
	return hand_row_top(row) + FONT_HAND.get_ascent(HAND_SIZE)


static func hand_bar_centre_y(row: int) -> float:
	return hand_row_top(row) + DocModel.HAND_LINE_H * 0.5


static func hand_width(text: String) -> float:
	if text == "":
		return 0.0
	return FONT_HAND.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, HAND_SIZE).x


## Greedy word wrap at spaces, measured with the handwriting font. Words wider
## than the line are split. Empty text gives one empty row.
static func hand_wrap(text: String, width: float = HAND_WIDTH) -> Array:
	var out: Array = []
	var cur := ""
	for w in text.split(" ", false):
		var cand: String = w if cur == "" else cur + " " + w
		if hand_width(cand) <= width:
			cur = cand
			continue
		if cur != "":
			out.append(cur)
		cur = w
		while hand_width(cur) > width and cur.length() > 1:
			var k := cur.length() - 1
			while k > 1 and hand_width(cur.substr(0, k)) > width:
				k -= 1
			out.append(cur.substr(0, k))
			cur = cur.substr(k)
	out.append(cur)
	return out


## Rows of a handwritten page: each paragraph wrapped, with one blank row
## between paragraphs. The spacing between paragraphs is not in the spec (see
## the report to the lead).
static func hand_rows(page: Dictionary) -> Array:
	var rows: Array = []
	for p in page.paragraphs:
		if not rows.is_empty():
			rows.append("")
		rows.append_array(hand_wrap(String(p)))
	return rows


## Text of one typed line as 64 characters. Printed text is uppercase. A typed
## glyph replaces the printed character. A whited-out cell with no glyph reads
## as a space, because its correction fluid covers the printed character.
static func row_text(page: Dictionary, line: int) -> String:
	var cells := PackedStringArray()
	cells.resize(DocModel.COLS)
	for c in range(DocModel.COLS):
		cells[c] = " "
	for entry in page.printed:
		if int(entry.line) != line:
			continue
		var t := String(entry.text).to_upper()
		for i in range(t.length()):
			var col := int(entry.col) + i
			if col >= 0 and col < DocModel.COLS:
				cells[col] = t.substr(i, 1)
	for c in range(DocModel.COLS):
		var key := DocModel.cell_key(line, c)
		if not page.cells.has(key):
			continue
		var cell: Dictionary = page.cells[key]
		if cell.g.is_empty():
			if bool(cell.w):
				cells[c] = " "
			continue
		cells[c] = String(cell.g[cell.g.size() - 1].c)
	return "".join(cells)


static func _is_hand(page: Dictionary) -> bool:
	return not page.paragraphs.is_empty()


# --- Redaction bars (spec 8.2, 8.3, 8.8) -----------------------------------------------

## Text spans to draw as bars: {row, style, start, end, text}. Rows are typed
## lines or handwritten rows. Carbons and a missing bars_fn give none.
static func text_bar_spans(doc: Dictionary, page: Dictionary, bars_fn: Callable) -> Array:
	var out: Array = []
	if bool(doc.get("carbon", false)) or not bars_fn.is_valid():
		return out
	if _is_hand(page):
		var rows := hand_rows(page)
		for k in range(rows.size()):
			var t := String(rows[k])
			if t.strip_edges() == "":
				continue
			for sp in bars_fn.call(t):
				out.append({"row": k, "style": "hand", "start": int(sp[0]), "end": int(sp[1]), "text": t})
	for line in range(DocModel.LINES):
		var t := row_text(page, line)
		if t.strip_edges() == "":
			continue
		for sp in bars_fn.call(t):
			out.append({"row": line, "style": "typed", "start": int(sp[0]), "end": int(sp[1]), "text": t})
	return out


## Bar rectangles in page pixels: text spans, then marker bars (page.bars).
static func bar_rects(doc: Dictionary, page: Dictionary, bars_fn: Callable) -> Array:
	var rects: Array = []
	for sp in text_bar_spans(doc, page, bars_fn):
		var y := 0.0
		var x0 := 0.0
		var x1 := 0.0
		if String(sp.style) == "hand":
			y = hand_bar_centre_y(int(sp.row))
			var t := String(sp.text)
			x0 = DocModel.HAND_LEFT + hand_width(t.substr(0, int(sp.start)))
			x1 = DocModel.HAND_LEFT + hand_width(t.substr(0, int(sp.end)))
		else:
			y = typed_bar_centre_y(int(sp.row))
			x0 = DocModel.LEFT + int(sp.start) * DocModel.COL_W
			x1 = DocModel.LEFT + int(sp.end) * DocModel.COL_W
		rects.append(Rect2(x0, y - BAR_H * 0.5, x1 - x0, BAR_H))
	var hand := _is_hand(page)
	for b in page.bars:
		var y := hand_bar_centre_y(int(b.line)) if hand else typed_bar_centre_y(int(b.line))
		rects.append(Rect2(float(b.x0), y - BAR_H * 0.5, float(b.x1) - float(b.x0), BAR_H))
	return rects


# --- Painting ------------------------------------------------------------------------

## Draws one page onto ci (a CanvasItem inside _draw). Layer order: paper, printed
## text, correction fluid, typed glyphs, handwriting, inserts, strikes, bars, stamps.
static func paint_page(ci: CanvasItem, doc: Dictionary, page_index: int, bars_fn: Callable) -> void:
	var page: Dictionary = doc.pages[page_index]
	var carbon := bool(doc.get("carbon", false))
	ci.draw_texture_rect(TEX_ONION if carbon else TEX_PAPER, Rect2(Vector2.ZERO, Vector2(PAGE_SIZE)), true)
	_paint_printed(ci, page, carbon)
	_paint_typed_cells(ci, page, carbon)
	_paint_hand(ci, page, carbon)
	_paint_inserts(ci, page, carbon)
	_paint_strikes(ci, page)
	for r in bar_rects(doc, page, bars_fn):
		ci.draw_rect(r, COL_BAR)
	_paint_stamps(ci, page)


static func _ink_colour(ink: String, carbon: bool) -> Color:
	if carbon:
		return COL_CARBON
	if ink == "red":
		return COL_RED
	return COL_INK


static func _draw_glyph(ci: CanvasItem, ch: String, pos: Vector2, colour: Color, alpha: float, carbon: bool) -> void:
	if ch == "" or ch == " ":
		return
	if carbon:
		# Carbon ink: the glyph drawn twice, 0.6 px apart, at reduced opacity (spec 6.5).
		var a := alpha * CARBON_OPACITY * 0.5
		ci.draw_string(FONT_TYPED, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, TYPED_SIZE, Color(colour, a))
		ci.draw_string(FONT_TYPED, pos + Vector2(CARBON_BLUR, 0.0), ch, HORIZONTAL_ALIGNMENT_LEFT, -1, TYPED_SIZE, Color(colour, a))
		return
	ci.draw_string(FONT_TYPED, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, TYPED_SIZE, Color(colour, alpha))


## Pre-printed text: no jitter (spec 6.5).
static func _paint_printed(ci: CanvasItem, page: Dictionary, carbon: bool) -> void:
	for entry in page.printed:
		var colour := _ink_colour(String(entry.ink), carbon)
		var line := int(entry.line)
		var t := String(entry.text).to_upper()
		for i in range(t.length()):
			var col := int(entry.col) + i
			if col < 0 or col >= DocModel.COLS:
				continue
			_draw_glyph(ci, t.substr(i, 1), Vector2(DocModel.LEFT + col * DocModel.COL_W, typed_baseline(line)), colour, 1.0, carbon)


## Correction fluid blobs (spec 7.6), then typed glyphs with their jitter (spec 6.5).
static func _paint_typed_cells(ci: CanvasItem, page: Dictionary, carbon: bool) -> void:
	for key in page.cells.keys():
		var cell: Dictionary = page.cells[key]
		if not bool(cell.w):
			continue
		var pos := _cell_key_pos(String(key))
		var centre := Vector2(DocModel.LEFT + pos.y * DocModel.COL_W + DocModel.COL_W * 0.5, DocModel.TOP + pos.x * DocModel.LINE_H + DocModel.LINE_H * 0.5)
		ci.draw_colored_polygon(_fluid_points(centre, int(cell.ws)), COL_FLUID)
	for key in page.cells.keys():
		var cell: Dictionary = page.cells[key]
		var pos := _cell_key_pos(String(key))
		for g in cell.g:
			var colour := _ink_colour(String(g.ink), carbon)
			var x := DocModel.LEFT + pos.y * DocModel.COL_W + float(g.x)
			var y := typed_baseline(int(pos.x)) + float(g.y)
			_draw_glyph(ci, String(g.c), Vector2(x, y), colour, float(g.a), carbon)


## Vector2(line, col) from a "line:col" cell key.
static func _cell_key_pos(key: String) -> Vector2:
	var parts := key.split(":")
	return Vector2(float(parts[0]), float(parts[1]))


## Irregular rounded blob about 12 x 20 px with edges wobbling by up to 1.5 px (spec 7.6).
static func _fluid_points(centre: Vector2, ws: int) -> PackedVector2Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = ws
	var corners := [
		Vector2(-BLOB_HALF_W, -BLOB_HALF_H), Vector2(BLOB_HALF_W, -BLOB_HALF_H),
		Vector2(BLOB_HALF_W, BLOB_HALF_H), Vector2(-BLOB_HALF_W, BLOB_HALF_H),
	]
	var pts := PackedVector2Array()
	for i in range(4):
		var a: Vector2 = corners[i]
		var b: Vector2 = corners[(i + 1) % 4]
		for s in range(3):
			var p := a.lerp(b, float(s) / 3.0)
			var jitter := Vector2(rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
			pts.append(centre + p + jitter)
	return pts


## Handwritten paragraphs (spec 6.5): Homemade Apple 26 px, left margin 56, line
## height 34, ink #1C1B19 at opacity 0.9. Case is kept.
static func _paint_hand(ci: CanvasItem, page: Dictionary, carbon: bool) -> void:
	if not _is_hand(page) or carbon:
		return
	var rows := hand_rows(page)
	for k in range(rows.size()):
		var t := String(rows[k])
		if t == "":
			continue
		ci.draw_string(FONT_HAND, Vector2(DocModel.HAND_LEFT, hand_baseline(k)), t, HORIZONTAL_ALIGNMENT_LEFT, -1, HAND_SIZE, Color(COL_INK, HAND_OPACITY))


## Management insert glyphs (spec 8.6): red, at float lines, same jitter rule.
static func _paint_inserts(ci: CanvasItem, page: Dictionary, carbon: bool) -> void:
	for g in page.inserts:
		var x := DocModel.LEFT + int(g.get("col", 0)) * DocModel.COL_W + float(g.x)
		var y := DocModel.TOP + float(g.line) * DocModel.LINE_H + FONT_TYPED.get_ascent(TYPED_SIZE) + float(g.y)
		_draw_glyph(ci, String(g.c), Vector2(x, y), COL_RED, float(g.a), carbon)


## Red 2 px strike lines through cells c0..c1 (both inclusive, spec 8.6).
static func _paint_strikes(ci: CanvasItem, page: Dictionary) -> void:
	for s in page.strikes:
		var x0 := DocModel.LEFT + int(s.c0) * DocModel.COL_W
		var x1 := DocModel.LEFT + (int(s.c1) + 1) * DocModel.COL_W
		var y := typed_bar_centre_y(int(s.line))
		ci.draw_rect(Rect2(x0, y - STRIKE_H * 0.5, x1 - x0, STRIKE_H), COL_RED)


## Stamp impressions (spec 8.1, 8.4). x and y are the centre, rot is in degrees.
## The first 20% of the impression's pixels are knocked out to opacity 0.3 by
## paper-coloured squares at alpha 0.7, seeded by stamp.seed.
static func _paint_stamps(ci: CanvasItem, page: Dictionary) -> void:
	for st in page.stamps:
		var word := String(st.word)
		var a := float(st.a)
		var colour := _stamp_colour(String(st.ink))
		var rng := RandomNumberGenerator.new()
		rng.seed = int(st.seed)
		ci.draw_set_transform(Vector2(float(st.x), float(st.y)), deg_to_rad(float(st.rot)), Vector2.ONE)
		if word == NO_SUCH_WORD:
			var size_n := NO_SUCH_SIZE
			var tsz := FONT_TYPED.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_n)
			var asc := FONT_TYPED.get_ascent(size_n)
			var desc := FONT_TYPED.get_descent(size_n)
			var base_y := (asc - desc) * 0.5
			ci.draw_string(FONT_TYPED, Vector2(-tsz.x * 0.5, base_y), word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_n, Color(colour, a))
			_knock_out(ci, rng, Rect2(-tsz.x * 0.5, -(asc + desc) * 0.5, tsz.x, asc + desc))
		else:
			var size_s := STAMP_SIZE_LONG if word == STAMP_LONG_WORD else STAMP_SIZE
			var rect := Rect2(-STAMP_W * 0.5, -STAMP_H * 0.5, STAMP_W, STAMP_H)
			ci.draw_rect(rect, Color(colour, a), false, STAMP_BORDER)
			var tw := FONT_TYPED.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_s).x
			var asc2 := FONT_TYPED.get_ascent(size_s)
			var desc2 := FONT_TYPED.get_descent(size_s)
			ci.draw_string(FONT_TYPED, Vector2(-tw * 0.5, (asc2 - desc2) * 0.5), word, HORIZONTAL_ALIGNMENT_LEFT, -1, size_s, Color(colour, a))
			_knock_out(ci, rng, rect)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One pixel square per chosen pixel: STAMP_KNOCK of the area in rect.
static func _knock_out(ci: CanvasItem, rng: RandomNumberGenerator, rect: Rect2) -> void:
	var paper := Color(COL_PAPER, 0.7)
	var x_end := int(ceil(rect.end.x))
	var y_end := int(ceil(rect.end.y))
	for py in range(int(floor(rect.position.y)), y_end):
		for px in range(int(floor(rect.position.x)), x_end):
			if rng.randf() < STAMP_KNOCK:
				ci.draw_rect(Rect2(px, py, 1, 1), paper)


static func _stamp_colour(ink: String) -> Color:
	if ink.begins_with("#"):
		return Color(ink)
	if ink == "red":
		return COL_RED
	return COL_STAMP_BLUE


# --- Fitting checks (used by the unit test and by the layout report) ---------------

## Problems with one page's layout: typed text past 64 columns or 54 lines, and
## handwriting past the page. Empty when the page fits.
static func page_problems(page: Dictionary) -> Array:
	var problems: Array = []
	for entry in page.printed:
		var line := int(entry.line)
		var col := int(entry.col)
		if line < 0 or line >= DocModel.LINES:
			problems.append("printed line %d outside 0..%d" % [line, DocModel.LINES - 1])
		if col < 0 or col + String(entry.text).length() > DocModel.COLS:
			problems.append("printed line %d runs past column %d" % [line, DocModel.COLS - 1])
	if _is_hand(page):
		var rows := hand_rows(page).size()
		if rows > HAND_ROWS_MAX:
			problems.append("handwriting has %d rows, page holds %d" % [rows, HAND_ROWS_MAX])
	return problems


# --- Autoload access ----------------------------------------------------------------

## The TextTokens autoload, or null when it is missing.
static func text_tokens_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("TextTokens")
