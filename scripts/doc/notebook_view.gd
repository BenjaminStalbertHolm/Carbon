extends RefCounted
## NotebookView: the notebook (spec 14.13), shown through the read view. Pages
## 1..GameState.day are shown and the view opens on page `day`, the newest.
## Each page is the handwritten document NB-n from data/dayN.json, built with
## DocModel.build_doc and TextTokens. NB-4 gets its extra paragraph when
## GameState.p1_q4 is NO (spec 14.10). Redaction bars on the signatures come from
## DocRenderer, which applies TextTokens.bar_spans to handwritten rows.
##
## Use: NotebookView.open(read_view, GameState.day). Connect the read view's
## page_changed signal to the page_turn sound (spec 14.13).

const Content := preload("res://scripts/logic/content.gd")
const DocModel := preload("res://scripts/logic/doc_model.gd")
const DocRenderer := preload("res://scripts/doc/doc_renderer.gd")


## Notebook pages 1..day as documents, oldest first.
static func page_docs(day: int) -> Array:
	var docs: Array = []
	var subst := _subst()
	var gs := DocRenderer._game_state()
	for n in range(1, clampi(day, 0, 5) + 1):
		var day_docs: Dictionary = Content.day(n).get("documents", {})
		var doc_id := "NB-%d" % n
		if not day_docs.has(doc_id):
			push_error("NotebookView: no document %s" % doc_id)
			continue
		var spec: Dictionary = (day_docs[doc_id] as Dictionary).duplicate(true)
		if spec.has("append_if") and gs != null:
			var cond: Dictionary = spec.append_if
			if str(gs.get(String(cond.state))) == String(cond.value):
				spec.pages[0].paragraphs.append_array(cond.paragraphs)
		docs.append(DocModel.build_doc(doc_id, spec, subst, [], "", []))
	return docs


## Opens the read view on the notebook at the newest page.
static func open(read_view: Node, day: int) -> void:
	var docs := page_docs(day)
	if docs.is_empty():
		return
	read_view.open(docs, docs.size() - 1, "stack")


static func _subst() -> Callable:
	var tt := DocRenderer.text_tokens_node()
	if tt != null:
		return tt.subst_callable()
	return func(s: String) -> String: return s
