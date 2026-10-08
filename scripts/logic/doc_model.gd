extends RefCounted
## Document model: pages, cells, glyphs, printed text and form fields
## (spec 6.5, 7.1, 7.5, 8.1, 8.5). Pure data and helpers, no nodes. Documents are
## plain Dictionaries of JSON-safe values, so they save directly.
##
## Document: {id, kind, style ("typed"|"hand"), ink ("black"|"red"), carbon (bool),
##            origin (carbon: id of the original), twin (original: id of its carbon),
##            task (task tag for transcription sheets), stampable, redactable,
##            register (orders: [{key, name, entity, listed, clerk_desk}]),
##            listed (orders: [keys]), pages: [page...]}
## Page:     {printed: [{line, col, text, ink}], paragraphs: [String],
##            fields: [{id, line, col, len}], cells: {"line:col": cell},
##            bars: [{line, x0, x1}], stamps: [{word, result, ink, x, y, rot, a, seed}],
##            strikes: [{line, c0, c1}], inserts: [glyph with float "line"]}
## Cell:     {g: [glyph...], w: bool, ws: int}   g holds overstrike glyphs (max 3).
##           w marks correction fluid. ws is the blob seed (spec 7.6).
## Glyph:    {c, x, y, a, ink ("black"|"red"|"carbon")}; x, y and a are jitter (6.5).
##
## Field value and typed-text rules are in spec 7.5 and 7.8. Cell character rule:
## the last glyph, or a space when there is none. A whited-out cell with no glyph
## therefore reads as a space. Glyphs typed after whiteout are read as normal.

const TextNorm := preload("res://scripts/logic/text_norm.gd")

const COLS := 64
const LINES := 54
const PAGE_W := 768
const PAGE_H := 1088
const LEFT := 40.0
const TOP := 48.0
const COL_W := 10.8
const LINE_H := 18.6
const HAND_LEFT := 56.0
const HAND_TOP := 48.0
const HAND_LINE_H := 34.0
const MAX_GLYPHS := 3

static var _field_regex: RegEx = null


static func new_doc(id: String, kind: String, style: String = "typed", ink: String = "black") -> Dictionary:
	return {
		"id": id, "kind": kind, "style": style, "ink": ink,
		"carbon": false, "origin": "", "twin": "", "task": "",
		"stampable": false, "redactable": false,
		"register": [], "listed": [],
		"pages": [],
	}


static func new_page() -> Dictionary:
	return {
		"printed": [], "paragraphs": [], "fields": [], "cells": {},
		"bars": [], "stamps": [], "strikes": [], "inserts": [],
	}


static func cell_key(line: int, col: int) -> String:
	return "%d:%d" % [line, col]


static func cell(page: Dictionary, line: int, col: int) -> Dictionary:
	var k := cell_key(line, col)
	if not page.cells.has(k):
		page.cells[k] = {"g": [], "w": false, "ws": 0}
	return page.cells[k]


## A typed glyph with its jitter (spec 6.5). Opacity 0.82 to 1.00, x ±0.3 px,
## y ±0.6 px. Glyphs are stored per cell, so re-rendering gives the same result.
static func make_glyph(ch: String, rng: RandomNumberGenerator, ink: String = "black") -> Dictionary:
	return {
		"c": ch,
		"x": rng.randf_range(-0.3, 0.3),
		"y": rng.randf_range(-0.6, 0.6),
		"a": rng.randf_range(0.82, 1.0),
		"ink": ink,
	}


## Writes one typed glyph into a cell (overstrike, spec 6.5). Returns false when
## the cell already holds MAX_GLYPHS glyphs. The extra glyph is then ignored.
static func write_glyph(page: Dictionary, line: int, col: int, ch: String, rng: RandomNumberGenerator, ink: String = "black") -> bool:
	var c := cell(page, line, col)
	if c.g.size() >= MAX_GLYPHS:
		return false
	c.g.append(make_glyph(ch, rng, ink))
	return true


## Removes every glyph in a cell, and marks it with correction fluid (spec 7.6).
static func whiteout(page: Dictionary, line: int, col: int, rng: RandomNumberGenerator) -> void:
	var c := cell(page, line, col)
	c.g = []
	c.w = true
	c.ws = rng.randi_range(1, 2147483646)


static func cell_char(page: Dictionary, line: int, col: int) -> String:
	var k := cell_key(line, col)
	if not page.cells.has(k):
		return " "
	var g: Array = page.cells[k].g
	if g.is_empty():
		return " "
	return String(g[g.size() - 1].c)


static func has_glyph(page: Dictionary, line: int, col: int) -> bool:
	var k := cell_key(line, col)
	return page.cells.has(k) and not page.cells[k].g.is_empty()


static func line_text(page: Dictionary, line: int) -> String:
	var s := ""
	for col in range(COLS):
		s += cell_char(page, line, col)
	return s


## Spec 7.8: every cell read line by line, lines joined with single spaces, then
## normalised. Used for accuracy and for corrections (8.6 step 1).
static func typed_text(page: Dictionary) -> String:
	var parts := PackedStringArray()
	for line in range(LINES):
		parts.append(line_text(page, line))
	return TextNorm.normalise(" ".join(parts))


## Spec 7.5: cells left to right, last glyph per cell, whiteout as space,
## trimmed, internal runs of spaces collapsed.
static func field_value(page: Dictionary, field: Dictionary) -> String:
	var s := ""
	for col in range(int(field.col), int(field.col) + int(field.len)):
		s += cell_char(page, int(field.line), col)
	return TextNorm.normalise(s)


static func field_by_id(page: Dictionary, field_id: String) -> Dictionary:
	for f in page.fields:
		if String(f.id) == field_id:
			return f
	return {}


static func field_values(page: Dictionary) -> Dictionary:
	var out := {}
	for f in page.fields:
		out[String(f.id)] = field_value(page, f)
	return out


## Splits {{Fn:len}} markers out of a line. Returns {"text": clean text,
## "fields": [{id, col, len}]} where col is the column in the clean text.
static func extract_fields(text: String) -> Dictionary:
	if _field_regex == null:
		_field_regex = RegEx.create_from_string("\\{\\{(F[0-9]+):([0-9]+)\\}\\}")
	var clean := ""
	var fields: Array = []
	var last := 0
	for m in _field_regex.search_all(text):
		clean += text.substr(last, m.get_start() - last)
		fields.append({"id": m.get_string(1), "col": clean.length(), "len": int(m.get_string(2))})
		last = m.get_end()
	clean += text.substr(last)
	return {"text": clean, "fields": fields}


## Greedy word wrap at spaces. Words longer than the width are split.
static func wrap_text(text: String, width: int = COLS) -> Array:
	var out: Array = []
	if text.length() <= width:
		out.append(text)
		return out
	var cur := ""
	for w in text.split(" "):
		var cand: String = w if cur == "" else cur + " " + w
		if cand.length() <= width:
			cur = cand
			continue
		if cur != "":
			out.append(cur)
		cur = w
		while cur.length() > width:
			out.append(cur.substr(0, width))
			cur = cur.substr(width)
	out.append(cur)
	return out


## Adds pre-printed typed lines (spec 6.5 and 14.4). Lines must already have
## their runtime tokens substituted. Lines longer than 64 columns wrap. Form
## markers are removed, and the field is recorded at the marker's column. Returns
## the next free line index. Printed text takes no jitter.
static func add_printed_lines(page: Dictionary, lines: Array, start: int = 0, ink: String = "black") -> int:
	var line := start
	for raw in lines:
		var parsed := extract_fields(String(raw))
		var pieces := wrap_text(String(parsed.text), COLS)
		if line + pieces.size() > LINES:
			push_error("add_printed_lines: page overflow at line %d" % line)
			return LINES
		if parsed.text == "" and parsed.fields.is_empty():
			line += 1
			continue
		var first_line := line
		for piece in pieces:
			if piece != "":
				page.printed.append({"line": line, "col": 0, "text": piece, "ink": ink})
			line += 1
		for f in parsed.fields:
			f["line"] = first_line
			page.fields.append(f)
	return line


## Adds a list of handwritten paragraphs. The renderer lays them out with its
## font metrics (spec 6.5, 14.4).
static func set_paragraphs(page: Dictionary, paragraphs: Array) -> void:
	page.paragraphs = []
	for p in paragraphs:
		page.paragraphs.append(String(p))


static func add_bar(page: Dictionary, line: int, x0: float, x1: float) -> void:
	page.bars.append({"line": line, "x0": minf(x0, x1), "x1": maxf(x0, x1)})


static func add_stamp(page: Dictionary, word: String, result: String, ink: String, x: float, y: float, rot: float, a: float, seed_value: int) -> void:
	page.stamps.append({"word": word, "result": result, "ink": ink, "x": x, "y": y, "rot": rot, "a": a, "seed": seed_value})


## Result of the first impression on a page (spec 8.1). "" when unstamped.
static func first_stamp_result(page: Dictionary) -> String:
	if page.stamps.is_empty():
		return ""
	return String(page.stamps[0].result)


## Builds a document from its content spec (data/dayN.json and layouts.json).
## subst: Callable(String) -> String applies runtime tokens (spec 14.1).
## header_lines: the memo header (strings.json memo_header). re_template: memo
## RE line with {RE} (strings.json memo_re_line). app_layout: layouts.json
## app_r2.lines, used for batch pages.
static func build_doc(id: String, spec: Dictionary, subst: Callable, header_lines: Array, re_template: String, app_layout: Array) -> Dictionary:
	var doc := new_doc(id, String(spec.get("kind", "printed")), String(spec.get("style", "typed")), String(spec.get("ink", "black")))
	doc.stampable = bool(spec.get("stampable", false))
	doc.redactable = bool(spec.get("redactable", false))
	for raw_page in spec.get("pages", []):
		var page := new_page()
		var first: bool = doc.pages.is_empty()
		if raw_page.has("app"):
			var app: Dictionary = raw_page.app
			var lines: Array = []
			for l in app_layout:
				lines.append(_fill(String(l), app, subst))
			add_printed_lines(page, _subst_all(lines, subst), 0, String(doc.ink))
		elif raw_page.has("paragraphs"):
			var paras: Array = []
			for p in raw_page.paragraphs:
				paras.append(subst.call(String(p)))
			set_paragraphs(page, paras)
		else:
			var body: Array = []
			if first and bool(spec.get("header", false)):
				for h in header_lines:
					body.append(String(h))
				body.append(re_template.replace("{RE}", String(spec.get("re", ""))))
				body.append("")
			for l in raw_page.get("lines", []):
				body.append(String(l))
			add_printed_lines(page, _subst_all(body, subst), 0, String(doc.ink))
		doc.pages.append(page)
	if spec.has("register"):
		var reg: Array = []
		for e in spec.register:
			var entry: Dictionary = e.duplicate()
			entry["name"] = subst.call(String(e.name))
			reg.append(entry)
		doc.register = reg
	if spec.has("listed"):
		doc.listed = spec.listed.duplicate()
	return doc


static func _fill(template: String, values: Dictionary, subst: Callable) -> String:
	var s := template
	for key in values.keys():
		s = s.replace("{" + String(key) + "}", String(values[key]))
	return subst.call(s)


static func _subst_all(lines: Array, subst: Callable) -> Array:
	var out: Array = []
	for l in lines:
		out.append(subst.call(String(l)))
	return out


## Document copy for a carbon of a typed original (spec 8.5). Carbons take the
## same cells, printed text and fields, and no bars or stamps.
static func make_carbon(original: Dictionary, carbon_id: String) -> Dictionary:
	var c := original.duplicate(true)
	c.id = carbon_id
	c.carbon = true
	c.origin = String(original.id)
	c.twin = ""
	c.task = String(original.task)
	c.stampable = false
	c.redactable = false
	c.ink = "carbon"
	for page in c.pages:
		page.bars = []
		page.stamps = []
		page.strikes = []
		page.inserts = []
	return c
