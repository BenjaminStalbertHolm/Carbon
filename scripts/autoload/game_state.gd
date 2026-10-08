extends Node
## GameState: all persistent variables (spec 14.2). Single source of truth.
## Autoload. Plain data plus helpers. Rules live in DayDirector and the logic
## modules. Serialises to a JSON-safe Dictionary for SaveSystem.

const Content := preload("res://scripts/logic/content.gd")

const SAVE_VERSION := 1
const LOCATIONS := ["inbox", "read_stack", "carbon_spot", "drawer", "removed", "attached"]

signal state_changed

var day := 1
var rng := RandomNumberGenerator.new()
var rng_seed := 0

# P-1 answers and derived tokens (spec 14.1).
var tokens_set := false
var player_name_raw := ""
var next_of_kin_raw := ""
var fond_word := ""
var p1_q4 := ""  # "YES", "NO" or "OTHER", as classified on the form.
var signature_matches := false

# Results (spec 14.2).
var accuracy := {}  # "T-1".."T-4" -> float
var stamp_results := {}  # "S-1", "S-2", "S-4" -> Array of per-page "APPROVED"/"DENIED"/"NONE"
var s4_choice := "NONE"  # "A", "B", "C", "NONE" or "MULTIPLE"
var ro_results := {}  # "RO-2".."RO-5" -> {"entries": {key: bool}, "first_stamp": String}
var first_stamp := {}  # "RO-2".."RO-5" -> "PROCESSED", "RETURNED", "OTHER" or "NONE"
var carried_forward := []  # RO-2 entries not redacted: [{key, name, reg, address}]
var f3_answers := {}  # "Q1".."Q4" -> normalised answer
var f3_had_carbons := false
var carbons_unfiled_flag := false
var contradictory_stamps := 0  # per day
var fluid_uses := 12
var misc_sent := 0
var free_mail_sent := []  # document ids sent on the current day
var ghost_lines_done := {"3": 0, "4": 0}
var ghost_sheet_removed_by_player := {"3": false, "4": false}
var redacted_names := []  # entity ids with effect from the next day
var redacted_desks := []  # desk numbers (ints) whose clerk was redacted
var refused_desks := []  # desk numbers (ints) of clerks who now face Desk 4
var carbons_kept_at_final := 0
var ending := "none"  # "A", "B", "C" or "none"

# Physical state (spec 8 and 13). Documents are stored by id.
var docs := {}  # id -> document Dictionary (logic/doc_model.gd)
var loc := {"inbox": [], "read_stack": [], "carbon_spot": [], "drawer": [], "removed": [], "attached": [], "copyholder": "", "typewriter": "", "hand": ""}
var tray_count := 10
var desk_removed := {}  # "1".."12" -> bool
var clerk_present := {}  # "1".."12" -> bool
var clerk_faces_player := {}  # "1".."12" -> bool
var nameplate := {}  # "1".."12" -> text
var clock_time := "08:58"
var clock_frozen := false
var lamp_on := true
var fixture_lit := {}  # "1".."6" -> bool
var fixture_pattern := {}  # "1".."6" -> String, the flicker pattern in use
var hum_pitch := 1.0
var vent_on := false
var notebook_pages_seen := 0
var morning_done := false
var end_of_shift_arrived := false
var last_task_done := ""
var sheet_seq := 0  # counter for sheet and carbon ids
var flags := {}  # misc booleans and counts: ghost4_deleted, tray_line, quota_occupied


func _ready() -> void:
	new_game(int(Time.get_unix_time_from_system()) ^ 0x5CA1E)


## Spec 3.6: one RNG per save, seeded at new game from the system time.
func new_game(seed_value: int = -1) -> void:
	rng_seed = seed_value if seed_value >= 0 else int(Time.get_unix_time_from_system() * 1000.0) & 0x7FFFFFFF
	rng.seed = rng_seed
	day = 1
	tokens_set = false
	player_name_raw = ""
	next_of_kin_raw = ""
	fond_word = ""
	p1_q4 = ""
	signature_matches = false
	accuracy = {}
	stamp_results = {"S-1": [], "S-2": [], "S-4": []}
	s4_choice = "NONE"
	ro_results = {}
	first_stamp = {}
	carried_forward = []
	f3_answers = {}
	f3_had_carbons = false
	carbons_unfiled_flag = false
	contradictory_stamps = 0
	fluid_uses = 12
	misc_sent = 0
	free_mail_sent = []
	ghost_lines_done = {"3": 0, "4": 0}
	ghost_sheet_removed_by_player = {"3": false, "4": false}
	redacted_names = []
	redacted_desks = []
	refused_desks = []
	carbons_kept_at_final = 0
	ending = "none"
	docs = {}
	loc = {"inbox": [], "read_stack": [], "carbon_spot": [], "drawer": [], "removed": [], "attached": [], "copyholder": "", "typewriter": "", "hand": ""}
	tray_count = 10
	desk_removed = {}
	clerk_present = {}
	clerk_faces_player = {}
	nameplate = {}
	# Spec 8.9: the nameplates show the names exactly. The names live in data/strings.json (spec 3.4).
	var plates: Dictionary = Content.strings().nameplates
	for n in range(1, 13):
		clerk_present[str(n)] = n != 4 and n != 12
		clerk_faces_player[str(n)] = false
		desk_removed[str(n)] = false
		nameplate[str(n)] = String(plates.get(str(n), ""))
	nameplate["4"] = "0412"
	clock_time = "08:58"
	clock_frozen = false
	lamp_on = true
	fixture_lit = {}
	fixture_pattern = {}
	for f in range(1, 7):
		fixture_lit[str(f)] = true
		fixture_pattern[str(f)] = "m"
	hum_pitch = 1.0
	vent_on = false
	notebook_pages_seen = 0
	morning_done = false
	end_of_shift_arrived = false
	last_task_done = ""
	sheet_seq = 0
	flags = {}
	state_changed.emit()


# --- Document store and locations -------------------------------------------

func add_doc(doc: Dictionary, location: String) -> void:
	docs[String(doc.id)] = doc
	place(String(doc.id), location)


## Puts an existing document id at the end of a location (spec 6.4). Hand and
## copyholder hold one item, so they take the id directly.
func place(doc_id: String, location: String) -> void:
	unplace(doc_id)
	match location:
		"copyholder":
			loc.copyholder = doc_id
		"typewriter":
			loc.typewriter = doc_id
		"hand":
			loc.hand = doc_id
		_:
			loc[location].append(doc_id)
	state_changed.emit()


func unplace(doc_id: String) -> void:
	for key in LOCATIONS:
		loc[key].erase(doc_id)
	if loc.copyholder == doc_id:
		loc.copyholder = ""
	if loc.typewriter == doc_id:
		loc.typewriter = ""
	if loc.hand == doc_id:
		loc.hand = ""


func location_of(doc_id: String) -> String:
	for key in LOCATIONS:
		if loc[key].has(doc_id):
			return key
	for key in ["copyholder", "typewriter", "hand"]:
		if loc[key] == doc_id:
			return key
	return ""


func remove_doc(doc_id: String) -> void:
	unplace(doc_id)
	docs.erase(doc_id)
	state_changed.emit()


# --- Serialisation -------------------------------------------------------------

func to_dict() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"day": day,
		"rng_seed": rng_seed,
		"rng_state": str(rng.state),
		"tokens_set": tokens_set,
		"player_name_raw": player_name_raw,
		"next_of_kin_raw": next_of_kin_raw,
		"fond_word": fond_word,
		"p1_q4": p1_q4,
		"signature_matches": signature_matches,
		"accuracy": accuracy,
		"stamp_results": stamp_results,
		"s4_choice": s4_choice,
		"ro_results": ro_results,
		"first_stamp": first_stamp,
		"carried_forward": carried_forward,
		"f3_answers": f3_answers,
		"f3_had_carbons": f3_had_carbons,
		"carbons_unfiled_flag": carbons_unfiled_flag,
		"contradictory_stamps": contradictory_stamps,
		"fluid_uses": fluid_uses,
		"misc_sent": misc_sent,
		"free_mail_sent": free_mail_sent,
		"ghost_lines_done": ghost_lines_done,
		"ghost_sheet_removed_by_player": ghost_sheet_removed_by_player,
		"redacted_names": redacted_names,
		"redacted_desks": redacted_desks,
		"refused_desks": refused_desks,
		"carbons_kept_at_final": carbons_kept_at_final,
		"ending": ending,
		"docs": docs,
		"loc": loc,
		"tray_count": tray_count,
		"desk_removed": desk_removed,
		"clerk_present": clerk_present,
		"clerk_faces_player": clerk_faces_player,
		"nameplate": nameplate,
		"clock_time": clock_time,
		"clock_frozen": clock_frozen,
		"lamp_on": lamp_on,
		"fixture_lit": fixture_lit,
		"fixture_pattern": fixture_pattern,
		"hum_pitch": hum_pitch,
		"vent_on": vent_on,
		"notebook_pages_seen": notebook_pages_seen,
		"morning_done": morning_done,
		"end_of_shift_arrived": end_of_shift_arrived,
		"last_task_done": last_task_done,
		"sheet_seq": sheet_seq,
		"flags": flags,
	}


## Loads a dictionary made by to_dict(). Returns false when the version differs
## or a required key is missing (spec 16.4: treat as no save).
func from_dict(d: Dictionary) -> bool:
	if int(d.get("version", -1)) != SAVE_VERSION:
		return false
	for key in ["day", "rng_seed", "rng_state", "docs", "loc"]:
		if not d.has(key):
			return false
	new_game(int(d.rng_seed))
	rng.state = int(d.rng_state)
	day = int(d.day)
	tokens_set = bool(d.tokens_set)
	player_name_raw = String(d.player_name_raw)
	next_of_kin_raw = String(d.next_of_kin_raw)
	fond_word = String(d.fond_word)
	p1_q4 = String(d.p1_q4)
	signature_matches = bool(d.signature_matches)
	accuracy = d.accuracy
	stamp_results = d.stamp_results
	s4_choice = String(d.s4_choice)
	ro_results = d.ro_results
	first_stamp = d.first_stamp
	carried_forward = d.carried_forward
	f3_answers = d.f3_answers
	f3_had_carbons = bool(d.f3_had_carbons)
	carbons_unfiled_flag = bool(d.carbons_unfiled_flag)
	contradictory_stamps = int(d.contradictory_stamps)
	fluid_uses = int(d.fluid_uses)
	misc_sent = int(d.misc_sent)
	free_mail_sent = d.free_mail_sent
	ghost_lines_done = d.ghost_lines_done
	ghost_sheet_removed_by_player = d.ghost_sheet_removed_by_player
	redacted_names = d.redacted_names
	redacted_desks = _ints(d.redacted_desks)
	refused_desks = _ints(d.refused_desks)
	carbons_kept_at_final = int(d.carbons_kept_at_final)
	ending = String(d.ending)
	docs = d.docs
	loc = d.loc
	tray_count = int(d.tray_count)
	desk_removed = d.desk_removed
	clerk_present = d.clerk_present
	clerk_faces_player = d.clerk_faces_player
	nameplate = d.nameplate
	clock_time = String(d.clock_time)
	clock_frozen = bool(d.clock_frozen)
	lamp_on = bool(d.lamp_on)
	fixture_lit = d.fixture_lit
	fixture_pattern = d.fixture_pattern
	hum_pitch = float(d.hum_pitch)
	vent_on = bool(d.vent_on)
	notebook_pages_seen = int(d.notebook_pages_seen)
	morning_done = bool(d.morning_done)
	end_of_shift_arrived = bool(d.end_of_shift_arrived)
	last_task_done = String(d.last_task_done)
	sheet_seq = int(d.get("sheet_seq", 0))
	flags = d.get("flags", {})
	state_changed.emit()
	return true


static func _ints(values: Array) -> Array:
	var out: Array = []
	for v in values:
		out.append(int(v))
	return out
