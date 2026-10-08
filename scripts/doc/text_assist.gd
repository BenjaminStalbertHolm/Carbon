extends Control
## TextAssist: the text assist panel (spec 6.5, 16.3). A plain panel beside the
## document with the same text in Special Elite 28 px on #E6DFC8, ink #1C1B19,
## without jitter. Redaction bars show as runs of the block character.
## Special Elite has no U+2588, so each run is drawn as a solid rectangle of the
## same width. Carbons show no bars (spec 8.7).
##
## plain_lines(doc, page_index, bars_fn) is static, so the typing view can use
## the same text without this node.

const DocRenderer := preload("res://scripts/doc/doc_renderer.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")

const FONT := preload("res://assets/fonts/SpecialElite-Regular.ttf")
const SIZE := 28
const LINE_H := 34.0
const PAD := 14.0
const BLOCK := "█"
const COL_BG := Color("#E6DFC8")
const COL_INK := Color("#1C1B19")

var _rows: Array = []  # plain rows, one per document row, with BLOCK for bars
var _wrapped: Array = []  # rows broken to the panel width
var _wrap_w := -1.0
var _advance := {}
var _block_w := 0.0


func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_block_w = FONT.get_string_size("M", HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x


## Rows of plain text for one page. Typed pages give their 54 lines and
## handwritten pages give their wrapped rows. Trailing blank rows are dropped.
static func plain_lines(doc: Dictionary, page_index: int, bars_fn: Callable) -> Array:
	var page: Dictionary = doc.pages[page_index]
	var hand := not page.paragraphs.is_empty()
	var kind := "hand" if hand else "typed"
	var rows: Array = []
	if hand:
		rows = DocRenderer.hand_rows(page)
	else:
		for line in range(DocModel.LINES):
			rows.append(DocRenderer.row_text(page, line))
	var spans := DocRenderer.text_bar_spans(doc, page, bars_fn)
	var out: Array = []
	for k in range(rows.size()):
		var t := String(rows[k])
		var chars := PackedStringArray()
		for i in range(t.length()):
			chars.append(t.substr(i, 1))
		for sp in spans:
			if int(sp.row) != k or String(sp.style) != kind:
				continue
			for i in range(int(sp.start), mini(int(sp.end), chars.size())):
				chars[i] = BLOCK
		for b in page.bars:
			if int(b.line) != k:
				continue
			for i in range(chars.size()):
				var cx := _char_centre_x(t, i, hand)
				if cx >= float(b.x0) and cx <= float(b.x1):
					chars[i] = BLOCK
		out.append("".join(chars).rstrip(" "))
	while not out.is_empty() and String(out[out.size() - 1]) == "":
		out.pop_back()
	return out


static func _char_centre_x(t: String, i: int, hand: bool) -> float:
	if not hand:
		return DocModel.LEFT + (i + 0.5) * DocModel.COL_W
	var x0 := DocRenderer.hand_width(t.substr(0, i))
	var x1 := DocRenderer.hand_width(t.substr(0, i + 1))
	return DocModel.HAND_LEFT + (x0 + x1) * 0.5


## Shows one page of a document.
func show_page(doc: Dictionary, page_index: int) -> void:
	_rows = plain_lines(doc, page_index, DocRenderer.bars_callable())
	_wrap_w = -1.0
	queue_redraw()


## The plain rows currently shown (for tests).
func rows() -> Array:
	return _rows.duplicate()


func _advance_of(ch: String) -> float:
	if ch == BLOCK:
		return _block_w
	if not _advance.has(ch):
		_advance[ch] = FONT.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE).x
	return float(_advance[ch])


func _width(s: String) -> float:
	var w := 0.0
	for i in range(s.length()):
		w += _advance_of(s.substr(i, 1))
	return w


func _wrap(width: float) -> Array:
	var out: Array = []
	for r in _rows:
		var line := String(r)
		if line == "":
			out.append("")
			continue
		var cur := ""
		for w in line.split(" ", false):
			var cand: String = w if cur == "" else cur + " " + w
			if cur == "" or _width(cand) <= width:
				cur = cand
			else:
				out.append(cur)
				cur = w
		out.append(cur)
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), COL_BG)
	var width := size.x - PAD * 2.0
	if width <= 0.0:
		return
	if _wrap_w != width:
		_wrapped = _wrap(width)
		_wrap_w = width
	var asc := FONT.get_ascent(SIZE)
	var desc := FONT.get_descent(SIZE)
	for i in range(_wrapped.size()):
		var base_y := PAD + i * LINE_H + asc
		if base_y > size.y:
			break
		_draw_row(String(_wrapped[i]), base_y, asc, desc)


func _draw_row(line: String, base_y: float, asc: float, desc: float) -> void:
	var x := PAD
	var run := ""
	var run_block := false
	for j in range(line.length() + 1):
		var ch := line.substr(j, 1) if j < line.length() else ""
		var is_block := ch == BLOCK
		if ch != "" and is_block == run_block:
			run += ch
			continue
		if run != "":
			if run_block:
				var w := _width(run)
				draw_rect(Rect2(x, base_y - asc * 0.8, w, asc * 0.8 + desc * 0.5), DocRenderer.COL_BAR)
				x += w
			else:
				draw_string(FONT, Vector2(x, base_y), run, HORIZONTAL_ALIGNMENT_LEFT, -1, SIZE, COL_INK)
				x += _width(run)
		run = ch
		run_block = is_block
