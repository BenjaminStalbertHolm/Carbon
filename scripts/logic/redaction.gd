extends RefCounted
## Redaction rules (spec 8.2, 8.3, 14.3) and the retired word (8.8). Pure
## functions. Matching is case-insensitive and on whole words. An alias must be
## bounded by non-letters or by the text edges, and longer aliases win overlaps.

const DocModel := preload("res://scripts/logic/doc_model.gd")

const COVER_THRESHOLD := 0.8

## Spec 14.3. Aliases are unsubstituted. The "nok" entity uses the {NEXT_OF_KIN}
## token, which callers resolve through aliases_for(..., subst).
const ALIASES := {
	"aurel": ["MORAVEC, AUREL", "MORAVEC, A.", "AUREL MORAVEC"],
	"ilse": ["MORAVEC, ILSE", "DR. ILSE MORAVEC", "ILSE MORAVEC"],
	"dobra": ["DOBRA, KASIMIR"],
	"fell": ["FELL, ODETTE"],
	"abel": ["J. ABEL", "ABEL"],
	"ferrand": ["N. FERRAND", "FERRAND"],
	"vance": ["H. VANCE", "VANCE, H.", "VANCE", "H.V."],
	"nok": ["{NEXT_OF_KIN}"],
	"halvorsen": ["HALVORSEN, PETRA"],
	"weiss": ["WEISS, CORA", "C. WEISS", "WEISS"],
}


static func aliases_for(entity: String, subst: Callable) -> Array:
	var out: Array = []
	for a in ALIASES.get(entity, []):
		out.append(subst.call(String(a)))
	return out


## Spans [start, end) of every whole-word match of any alias of the given
## entities. subst resolves tokens inside aliases.
static func find_entity_spans(text: String, entities: Array, subst: Callable) -> Array:
	var words: Array = []
	for e in entities:
		for a in aliases_for(String(e), subst):
			words.append(String(a).to_upper())
	words.sort_custom(func(x, y): return x.length() > y.length())
	return _spans_for_words(text.to_upper(), words)


## Spans of a retired word (spec 8.8). Whole words only.
static func find_word_spans(text: String, word: String) -> Array:
	return _spans_for_words(text.to_upper(), [word.to_upper()])


static func _spans_for_words(upper_text: String, words: Array) -> Array:
	var used := PackedByteArray()
	used.resize(upper_text.length())
	var spans: Array = []
	for w in words:
		var needle := String(w)
		if needle == "":
			continue
		var from := 0
		while true:
			var idx := upper_text.find(needle, from)
			if idx < 0:
				break
			var end := idx + needle.length()
			if _word_bounded(upper_text, idx, end) and not _any_used(used, idx, end):
				spans.append([idx, end])
				for i in range(idx, end):
					used[i] = 1
			from = idx + 1
	spans.sort_custom(func(a, b): return a[0] < b[0])
	return spans


static func _is_letter(c: int) -> bool:
	return c >= 65 and c <= 90


static func _word_bounded(t: String, s: int, e: int) -> bool:
	var before_ok := s == 0 or not _is_letter(t.unicode_at(s - 1))
	var after_ok := e >= t.length() or not _is_letter(t.unicode_at(e))
	return before_ok and after_ok


static func _any_used(used: PackedByteArray, s: int, e: int) -> bool:
	for i in range(s, e):
		if used[i] == 1:
			return true
	return false


## Fraction of [x0, x1] covered by the union of bars (spec 8.2). Bars are dicts
## with x0 and x1 in page pixels.
static func coverage(bars: Array, x0: float, x1: float) -> float:
	if x1 <= x0:
		return 0.0
	var segs: Array = []
	for b in bars:
		var a := maxf(float(b.x0), x0)
		var c := minf(float(b.x1), x1)
		if c > a:
			segs.append([a, c])
	segs.sort_custom(func(p, q): return p[0] < q[0])
	var covered := 0.0
	var has_cur := false
	var cur_a := 0.0
	var cur_b := 0.0
	for seg in segs:
		if not has_cur:
			cur_a = seg[0]
			cur_b = seg[1]
			has_cur = true
		elif seg[0] > cur_b:
			covered += cur_b - cur_a
			cur_a = seg[0]
			cur_b = seg[1]
		else:
			cur_b = maxf(cur_b, seg[1])
	if has_cur:
		covered += cur_b - cur_a
	return covered / (x1 - x0)


## Spec 8.2: an entry is redacted when the bars on its line cover at least 80%
## of the horizontal extent of its name text. name must already be substituted.
## Returns false when the name is not printed on the page.
static func entry_redacted(page: Dictionary, name: String) -> bool:
	var needle := name.to_upper()
	for entry in page.printed:
		var text := String(entry.text).to_upper()
		var idx := text.find(needle)
		if idx < 0:
			continue
		var line := int(entry.line)
		var col0 := int(entry.col) + idx
		var x0 := DocModel.LEFT + float(col0) * DocModel.COL_W
		var x1 := x0 + float(needle.length()) * DocModel.COL_W
		var line_bars: Array = []
		for b in page.bars:
			if int(b.line) == line:
				line_bars.append(b)
		return coverage(line_bars, x0, x1) >= COVER_THRESHOLD
	return false


## Printed extent in page pixels of a name on a page, or [] if absent.
static func name_extent(page: Dictionary, name: String) -> Array:
	var needle := name.to_upper()
	for entry in page.printed:
		var idx := String(entry.text).to_upper().find(needle)
		if idx >= 0:
			var x0 := DocModel.LEFT + float(int(entry.col) + idx) * DocModel.COL_W
			return [int(entry.line), x0, x0 + float(needle.length()) * DocModel.COL_W]
	return []
