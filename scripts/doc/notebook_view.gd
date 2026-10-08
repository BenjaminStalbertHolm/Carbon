extends RefCounted
## NotebookView: the notebook (spec 14.13), shown through the read view. The notebook has
## five pages. Pages 1..GameState.day are shown with their handwritten document NB-n from
## data/dayN.json, built with DocModel.build_doc and TextTokens. The pages after the current
## day exist and are blank. The view opens on page `day`, the newest. NB-4 gets its extra
## paragraph when GameState.p1_q4 is NO (spec 14.10). Redaction bars on the signatures come
## from DocRenderer, which applies TextTokens.bar_spans to handwritten rows.
##
## Use: NotebookView.open(read_view, GameState.day). Connect the read view's
## page_changed signal to the page_turn sound (spec 14.13).

const Content := preload("res://scripts/logic/content.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")
const DocRenderer := preload("res://scripts/doc/doc_renderer.gd")

const PAGE_COUNT := 5


## The five notebook pages as documents, oldest first. Pages 1..day are the NB-n documents;
## the later pages are blank.
static func page_docs(day: int) -> Array:
	var docs: Array = []
	var subst := _subst()
	var gs := DocRenderer._game_state()
	for n in range(1, PAGE_COUNT + 1):
		if n > day:
			docs.append(_blank_page(n))
			continue
		var day_docs: Dictionary = Content.day(n).get("documents", {})
		var doc_id := "NB-%d" % n
		if not day_docs.has(doc_id):
			push_error("NotebookView: no document %s" % doc_id)
			docs.append(_blank_page(n))
			continue
		var spec: Dictionary = (day_docs[doc_id] as Dictionary).duplicate(true)
		if spec.has("append_if") and gs != null:
			var cond: Dictionary = spec.append_if
			if str(gs.get(String(cond.state))) == String(cond.value):
				spec.pages[0].paragraphs.append_array(cond.paragraphs)
		docs.append(DocModel.build_doc(doc_id, spec, subst, [], "", []))
	return docs


## Index of the page the notebook opens on: the newest page, `day` (spec 14.13).
static func open_index(day: int) -> int:
	return clampi(day, 1, PAGE_COUNT) - 1


## Opens the read view on the notebook at the newest page.
static func open(read_view: Node, day: int) -> void:
	read_view.open(page_docs(day), open_index(day), "stack")


## An empty handwritten page for a notebook page that is not written yet.
static func _blank_page(n: int) -> Dictionary:
	var doc := DocModel.new_doc("NB-%d" % n, "notebook", "hand", "black")
	doc.pages.append(DocModel.new_page())
	return doc


static func _subst() -> Callable:
	var tt := DocRenderer.text_tokens_node()
	if tt != null:
		return tt.subst_callable()
	return func(s: String) -> String: return s
