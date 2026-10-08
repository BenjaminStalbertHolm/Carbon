extends RefCounted
## Management corrections on returned originals (spec 8.6). Pure page edits.
## Each correction is {find, replace}. Matching is fuzzy on whole-page text.

const DocModel := preload("res://scripts/logic/doc_model.gd")
const TextNorm := preload("res://scripts/logic/text_norm.gd")
const Lev := preload("res://scripts/logic/levenshtein.gd")
const Content := preload("res://scripts/logic/content.gd")

const MIN_SIMILARITY := 0.6


static func apply_all(page: Dictionary, corrections: Array, rng: RandomNumberGenerator) -> void:
	for c in corrections:
		apply_one(page, String(c.find), String(c.replace), rng)


## Spec 8.6 step 1: the page as one normalised string, with a map from each
## string index back to its cell index (line * COLS + col).
static func typed_map(page: Dictionary) -> Dictionary:
	var norm := ""
	var map := PackedInt32Array()
	var last_space := true
	for line in range(DocModel.LINES):
		for col in range(DocModel.COLS):
			var ch := DocModel.cell_char(page, line, col).to_upper()
			var idx := line * DocModel.COLS + col
			if ch == " ":
				if not last_space:
					norm += " "
					map.append(idx)
					last_space = true
			else:
				norm += ch
				map.append(idx)
				last_space = false
		# A line break counts as a space (spec 7.8).
		if not last_space:
			norm += " "
			map.append(line * DocModel.COLS + DocModel.COLS - 1)
			last_space = true
	if last_space and norm.length() > 0:
		norm = norm.substr(0, norm.length() - 1)
		map.resize(map.size() - 1)
	return {"norm": norm, "map": map}


static func apply_one(page: Dictionary, find_raw: String, replace_text: String, rng: RandomNumberGenerator) -> void:
	var m := typed_map(page)
	var norm: String = m.norm
	var map: PackedInt32Array = m.map
	var find := TextNorm.normalise(find_raw)
	var flen := find.length()
	var best_i := -1
	var best_sim := -1.0
	if flen > 0 and norm.length() >= flen:
		for i in range(0, norm.length() - flen + 1):
			var d := Lev.distance(norm.substr(i, flen), find)
			var sim := 1.0 - float(d) / float(flen)
			if sim > best_sim:
				best_sim = sim
				best_i = i
	if best_i >= 0 and best_sim >= MIN_SIMILARITY:
		_strike_window(page, map, best_i, flen)
		var first := map[best_i]
		_write_insert(page, replace_text, first / DocModel.COLS, first % DocModel.COLS, rng)
	else:
		_write_add(page, replace_text, rng)


## Red strike line through every cell of the window, split per line.
static func _strike_window(page: Dictionary, map: PackedInt32Array, start: int, length: int) -> void:
	var run_line := -1
	var run_c0 := 0
	var run_c1 := 0
	for k in range(start, start + length):
		var idx := map[k]
		var line := idx / DocModel.COLS
		var col := idx % DocModel.COLS
		if line == run_line and col == run_c1 + 1:
			run_c1 = col
		else:
			if run_line >= 0:
				page.strikes.append({"line": run_line, "c0": run_c0, "c1": run_c1})
			run_line = line
			run_c0 = col
			run_c1 = col
	if run_line >= 0:
		page.strikes.append({"line": run_line, "c0": run_c0, "c1": run_c1})


## Spec 8.6 step 4: red glyphs on the half-line above the window's first cell,
## continuing right. After column 63 they continue on the next half-line at 0.
static func _write_insert(page: Dictionary, text: String, line: int, col: int, rng: RandomNumberGenerator) -> void:
	var y := float(line) - 0.5
	var c := col
	for ch in text:
		if c >= DocModel.COLS:
			c = 0
			y += 1.0
		var g := DocModel.make_glyph(ch, rng, "red")
		g["line"] = y
		g["col"] = c
		page.inserts.append(g)
		c += 1


## Spec 8.6 step 5: the ADD prefix (data/strings.json) plus the replacement, in red typed glyphs, on the
## first empty line below the last typed line.
static func _write_add(page: Dictionary, text: String, rng: RandomNumberGenerator) -> void:
	var last := -1
	for line in range(DocModel.LINES):
		for col in range(DocModel.COLS):
			if DocModel.has_glyph(page, line, col):
				last = line
				break
	var line_i := mini(last + 1, DocModel.LINES - 1)
	var col_i := 0
	for ch in String(Content.strings().correction_add_prefix) + text:
		if col_i >= DocModel.COLS:
			col_i = 0
			line_i = mini(line_i + 1, DocModel.LINES - 1)
		DocModel.write_glyph(page, line_i, col_i, ch, rng, "red")
		col_i += 1
