extends SceneTree
## Layout checks for the page renderer (spec 6.5) and the Day 1 documents.
## Headless:
##   godot --headless --path . --script res://tests/unit/test_doc_render.gd
## Prints "DOC LAYOUT: N docs, M problems". Exit code 0 means M is 0 and every
## check passed.

const DocRenderer := preload("res://scripts/doc/doc_renderer.gd")
const TextAssist := preload("res://scripts/doc/text_assist.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")
const Content := preload("res://scripts/logic/content.gd")
const PaperQuad := preload("res://scripts/doc/paper_quad.gd")
const NotebookView := preload("res://scripts/doc/notebook_view.gd")
const FONT_TYPED := preload("res://assets/fonts/SpecialElite-Regular.ttf")

const DAY1_IDS := ["M1-WELCOME", "P-1", "T-1-COVER", "L-1", "S-1-COVER", "S-1", "EOS-STANDARD", "NB-1"]
const HELLO_ROW := 3

var _fails := 0
var _checks := 0


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
		print("FAIL: %s" % what)


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.01


func _initialize() -> void:
	# Deferred so that the autoloads are inside the active tree.
	call_deferred("_run")


func _run() -> void:
	_test_cell_maths()
	_test_hand_wrap()
	var problems := _test_day1_docs()
	_test_bars_and_plain_text()
	_test_page_cache()
	_test_paper_quad()
	_test_notebook_pages()
	_test_impressions()
	_test_carbon_passes()
	print("DOC LAYOUT: %d docs, %d problems" % [DAY1_IDS.size(), problems])
	print("doc render checks: %d run, %d failed" % [_checks, _fails])
	quit(0 if (problems == 0 and _fails == 0) else 1)


## Spec 6.5: glyph x = 40 + col x 10.8, line top = 48 + line x 18.6.
func _test_cell_maths() -> void:
	_check(DocRenderer.cell_origin(0, 0).is_equal_approx(Vector2(40.0, 48.0)), "cell (0,0) at (40,48)")
	_check(DocRenderer.cell_origin(2, 10).is_equal_approx(Vector2(148.0, 85.2)), "cell (2,10) at (148, 85.2)")
	_check(DocRenderer.cell_origin(53, 63).is_equal_approx(Vector2(720.4, 1033.8)), "cell (53,63) at (720.4, 1033.8)")
	_check(DocRenderer.cell_at_px(DocRenderer.cell_origin(10, 20) + Vector2(5, 5)) == Vector2i(10, 20), "cell_at_px inverts cell_origin")
	_check(DocRenderer.cell_at_px(DocRenderer.cell_origin(0, 63) + Vector2(10.7, 18.5)) == Vector2i(0, 63), "last cell of line 0 holds its far corner")
	_check(_near(DocRenderer.typed_bar_centre_y(0), 48.0 + 9.3), "bar centre sits at the middle of line 0")
	_check(DocModel.COLS == 64 and DocModel.LINES == 54, "grid is 64 x 54")
	_check(DocModel.PAGE_W == 768 and DocModel.PAGE_H == 1088, "page is 768 x 1088")
	_check(_near(DocRenderer.hand_width("") , 0.0), "empty handwriting has zero width")
	_check(_near(DocModel.HAND_LEFT, 56.0) and _near(DocModel.HAND_LINE_H, 34.0), "handwriting margin 56 and line height 34")


## Spec 6.5: paragraphs wrap at 768 - 2 x 56 = 656 px, using the font's measured width.
func _test_hand_wrap() -> void:
	var text := "Day 1. Desk 4. They told me the last one was reassigned. Nobody here says where to. Nobody here says anything. — H.V."
	var rows: Array = DocRenderer.hand_wrap(text)
	_check(rows.size() >= 3, "a long paragraph wraps to several rows")
	var all_fit := true
	for r in rows:
		if DocRenderer.hand_width(String(r)) > 656.0 + 0.01:
			all_fit = false
	_check(all_fit, "every handwritten row fits 656 px")
	var rejoined := " ".join(PackedStringArray(rows))
	_check(rejoined == text, "wrapping keeps every word in order")
	_check(DocRenderer.hand_wrap("")[0] == "", "empty paragraph gives one empty row")
	var long_word := ""
	for i in range(60):
		long_word += "W"
	var split: Array = DocRenderer.hand_wrap(long_word)
	_check(split.size() >= 2 and DocRenderer.hand_width(String(split[0])) <= 656.0, "a word wider than the page is split")


## Every Day 1 document builds, and every page fits its grid. Returns the number of problems.
func _test_day1_docs() -> int:
	var tt := get_root().get_node_or_null("TextTokens")
	_check(tt != null, "TextTokens autoload is present")
	if tt == null:
		return 1
	var st := Content.strings()
	var app_lines: Array = Content.layouts().app_r2.lines
	var problems := 0
	for id in DAY1_IDS:
		var spec: Dictionary = Content.day(1).documents[id]
		var doc: Dictionary = DocModel.build_doc(id, spec, tt.subst_callable(), st.memo_header, String(st.memo_re_line), app_lines)
		_check(doc.pages.size() >= 1, "%s has at least one page" % id)
		for i in range(doc.pages.size()):
			var page: Dictionary = doc.pages[i]
			for p in DocRenderer.page_problems(page):
				problems += 1
				print("  %s page %d: %s" % [id, i + 1, p])
			_check(page.stamps.is_empty(), "%s page %d has no stamps (none yet)" % [id, i + 1])
		if String(doc.style) == "hand":
			for i in range(doc.pages.size()):
				var rows := DocRenderer.hand_rows(doc.pages[i]).size()
				_check(rows <= DocRenderer.HAND_ROWS_MAX, "%s fits the page in handwriting rows (%d)" % [id, rows])
	return problems


## Bars: a marker bar and a text span both become page rectangles, and text
## assist shows the same cells as block runs.
func _test_bars_and_plain_text() -> void:
	var page := DocModel.new_page()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in range(5):
		DocModel.write_glyph(page, HELLO_ROW, 5 + i, "HELLO".substr(i, 1), rng)
	var row := DocRenderer.row_text(page, HELLO_ROW)
	_check(row.length() == 64 and row.substr(5, 5) == "HELLO", "typed glyphs appear in their cells")
	_check(DocRenderer.row_text(page, HELLO_ROW + 1).strip_edges() == "", "an empty line reads as blanks")

	var doc := DocModel.new_doc("T-TEST", "sheet")
	doc.pages.append(page)

	var marker := DocModel.new_page()
	DocModel.add_bar(marker, HELLO_ROW, DocModel.LEFT + 5 * DocModel.COL_W, DocModel.LEFT + 10 * DocModel.COL_W)
	var mdoc := DocModel.new_doc("M-TEST", "sheet")
	mdoc.pages.append(marker)
	var rects: Array = DocRenderer.bar_rects(mdoc, marker, Callable())
	_check(rects.size() == 1, "one marker bar gives one rectangle")
	if rects.size() == 1:
		var r: Rect2 = rects[0]
		_check(_near(r.position.x, 94.0) and _near(r.size.x, 54.0) and _near(r.size.y, 16.0), "marker bar is 54 x 16 px from x 94")

	var fake := Callable(self, "_fake_bars")
	var spans: Array = DocRenderer.text_bar_spans(doc, page, fake)
	_check(spans.size() == 1 and int(spans[0].start) == 5 and int(spans[0].end) == 10, "text span covers the cells of the matched word")
	var text_rects: Array = DocRenderer.bar_rects(doc, page, fake)
	_check(text_rects.size() == 1 and _near(text_rects[0].size.x, 54.0), "text span becomes a 5-cell bar")

	doc.carbon = true
	_check(DocRenderer.text_bar_spans(doc, page, fake).is_empty(), "carbons get no text bars")
	doc.carbon = false

	var plain: Array = TextAssist.plain_lines(doc, 0, fake)
	_check(plain.size() > HELLO_ROW and String(plain[HELLO_ROW]) == "     █████", "text assist shows the bar as a block run")
	var plain_marker: Array = TextAssist.plain_lines(mdoc, 0, Callable())
	_check(plain_marker.size() > HELLO_ROW and String(plain_marker[HELLO_ROW]) == "     █████", "text assist shows a marker bar as block cells")

	var hand_page := DocModel.new_page()
	DocModel.set_paragraphs(hand_page, ["I told them HELLO today."])
	var hdoc := DocModel.new_doc("H-TEST", "letter", "hand")
	hdoc.pages.append(hand_page)
	var hspans: Array = DocRenderer.text_bar_spans(hdoc, hand_page, fake)
	_check(hspans.size() == 1 and String(hspans[0].style) == "hand", "handwritten rows take text bars")
	var hrect: Rect2 = DocRenderer.bar_rects(hdoc, hand_page, fake)[0]
	var expect_x0 := DocModel.HAND_LEFT + DocRenderer.hand_width("I told them ")
	_check(_near(hrect.position.x, expect_x0), "handwritten bar starts at the measured width of the text before it")


## Stand-in for TextTokens.bar_spans: the word HELLO on any row.
func _fake_bars(line_text: String) -> Array:
	var idx := line_text.find("HELLO")
	if idx < 0:
		return []
	return [[idx, idx + 5]]


## Pages are cached by content: the same content reuses its SubViewport, and a change renders a new one.
func _test_page_cache() -> void:
	var renderer := DocRenderer.new()
	get_root().add_child(renderer)
	var doc := DocModel.new_doc("CACHE-TEST", "sheet")
	doc.pages.append(DocModel.new_page())
	var t1 := renderer.page_texture(doc, 0)
	_check(t1 != null, "page_texture returns a texture")
	var vp1: SubViewport = renderer._cache["CACHE-TEST|0"].vp
	var t2 := renderer.page_texture(doc, 0)
	_check(t2 != null and renderer._cache["CACHE-TEST|0"].vp == vp1, "unchanged page reuses its viewport")
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	DocModel.write_glyph(doc.pages[0], 0, 0, "A", rng)
	renderer.page_texture(doc, 0)
	_check(renderer._cache["CACHE-TEST|0"].vp != vp1, "a changed page renders a new viewport")
	_check(renderer._cache.size() == 1, "one cache entry per page")
	renderer.release_doc("CACHE-TEST")
	_check(not renderer._cache.has("CACHE-TEST|0"), "release_doc drops the document's pages")
	renderer.queue_free()


## The paper quad is 0.21 x 0.297 m and holds the page texture in the PSX shader.
func _test_paper_quad() -> void:
	var mi := PaperQuad.make(null)
	_check(mi is MeshInstance3D, "paper quad is a MeshInstance3D")
	var quad := mi.mesh as QuadMesh
	_check(quad != null and quad.size.is_equal_approx(Vector2(0.21, 0.297)), "paper quad is 0.21 x 0.297 m")
	var mat := mi.material_override as ShaderMaterial
	_check(mat != null and mat.shader != null, "paper quad uses a shader material")
	mi.free()


## The notebook has five pages (spec 14.13, QUESTION-34). Pages 1..day hold their NB
## document, the later pages exist and are blank, and the view opens on page day.
func _test_notebook_pages() -> void:
	var docs: Array = NotebookView.page_docs(3)
	_check(docs.size() == 5, "notebook on day 3 has five pages")
	if docs.size() == 5:
		_check(String(docs[0].id) == "NB-1" and String(docs[2].id) == "NB-3" and String(docs[4].id) == "NB-5", "notebook pages are NB-1..NB-5 in order")
		var page3: Dictionary = docs[2].pages[0]
		_check(not page3.paragraphs.is_empty(), "notebook page 3 (the current day) has its text")
		var blank := true
		for i in [3, 4]:
			var later: Dictionary = docs[i].pages[0]
			blank = blank and later.paragraphs.is_empty() and later.printed.is_empty() and later.cells.is_empty()
		_check(blank, "notebook pages after day 3 are blank")
	_check(NotebookView.open_index(3) == 2, "notebook opens on page 3 on day 3")
	_check(NotebookView.open_index(5) == 4 and NotebookView.open_index(1) == 0, "notebook opens on page day on days 1 and 5")


## Spec 8.1 and 8.4 (QUESTION-31, 32): every impression's words fit its box, RETURNED —
## UNPROCESSED is set on two lines, and NO SUCH ADDRESSEE has a box as wide as its text.
func _test_impressions() -> void:
	var long_lines: Array = DocRenderer.stamp_lines("RETURNED — UNPROCESSED")
	_check(long_lines.size() == 2 and String(long_lines[0]) == "RETURNED —" and String(long_lines[1]) == "UNPROCESSED", "RETURNED — UNPROCESSED is set on two lines")
	_check(DocRenderer.stamp_lines("PROCESSED") == ["PROCESSED"], "a one-line stamp word is set on one line")
	_check(DocRenderer.stamp_font_size("RETURNED — UNPROCESSED") == 24 and DocRenderer.stamp_font_size("APPROVED") == 34, "stamp words at 34 px, the long stamp at 24 px")
	_check(DocRenderer.stamp_font_size("NO SUCH ADDRESSEE") == 30, "NO SUCH ADDRESSEE is set at 30 px")
	var inner_w := DocRenderer.STAMP_W - 2.0 * DocRenderer.STAMP_BORDER
	var inner_h := DocRenderer.STAMP_H - 2.0 * DocRenderer.STAMP_BORDER
	for w in ["APPROVED", "DENIED", "PROCESSED", "RETURNED — UNPROCESSED"]:
		_check(DocRenderer.impression_rect(w).size.is_equal_approx(Vector2(260.0, 70.0)), "%s is in a 260 x 70 box" % w)
		var widest := 0.0
		for line in DocRenderer.stamp_lines(w):
			widest = maxf(widest, DocRenderer.stamp_line_width(String(line), w))
		_check(widest <= inner_w, "%s fits the box width (%.1f px)" % [w, widest])
		_check(DocRenderer.stamp_block_height(w) <= inner_h, "%s fits the box height (%.1f px)" % [w, DocRenderer.stamp_block_height(w)])
	var no_such := "NO SUCH ADDRESSEE"
	var text_w := FONT_TYPED.get_string_size(no_such, HORIZONTAL_ALIGNMENT_LEFT, -1, 30).x
	var margin := DocRenderer.stamp_margin_x()
	var box := DocRenderer.impression_rect(no_such)
	_check(text_w > DocRenderer.STAMP_W, "NO SUCH ADDRESSEE at 30 px is wider than the 260 px stamp box (%.1f px)" % text_w)
	_check(absf(box.size.x - (text_w + 2.0 * margin)) < 0.01, "NO SUCH ADDRESSEE box is its text plus the stamp margin on each side")
	_check(absf(box.size.y - 70.0) < 0.01, "NO SUCH ADDRESSEE box is 70 px tall")
	_check(margin > DocRenderer.STAMP_BORDER, "the stamp margin is wider than the 4 px border")


## Spec 6.5 and QUESTION-36: the two carbon passes composite to 0.85 x the glyph opacity
## where they overlap, so each pass is 1 - sqrt(1 - 0.85 x alpha).
func _test_carbon_passes() -> void:
	var ok := true
	for glyph_alpha in [0.82, 0.9, 1.0]:
		var pass_a := DocRenderer.carbon_pass_alpha(glyph_alpha)
		var overlap := 1.0 - (1.0 - pass_a) * (1.0 - pass_a)
		ok = ok and absf(overlap - 0.85 * glyph_alpha) < 0.0001 and pass_a < glyph_alpha
	_check(ok, "carbon passes composite to 0.85 x glyph opacity where they overlap")
	_check(absf(DocRenderer.carbon_pass_alpha(1.0) - (1.0 - sqrt(0.15))) < 0.0001, "a full-opacity carbon glyph has a pass alpha of about 0.613")
