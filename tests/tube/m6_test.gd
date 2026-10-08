extends SceneTree
## M6 headless checks for the pneumatic tube (spec 8.4) and the send rules (spec 7.9, 13.3):
## a free sheet is sent and leaves the world through DayDirector; a T-1 original is in the
## removed store with returns_on set; the NO SUCH ADDRESSEE mark is data-only.
## Run: godot --headless --path /home/user/Carbon --script res://tests/tube/m6_test.gd
## Exit 0 only when every check passes. Prints "M6: N checks, M failures".

const DocModel := preload("res://scripts/logic/doc_model.gd")
const TubeView := preload("res://scripts/tube/tube_view.gd")

var _checks := 0
var _fails := 0
var _ran := false
var _hand_kind := ""
var _hand_id := ""


func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run()
		print("M6: %d checks, %d failures" % [_checks, _fails])
		quit(0 if _fails == 0 else 1)
	return false


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


func _get_kind() -> String:
	return _hand_kind


func _get_id() -> String:
	return _hand_id


func _release_hand() -> String:
	var kind := _hand_kind
	_hand_kind = ""
	_hand_id = ""
	return kind


func _hold(doc_id: String) -> void:
	_hand_kind = "document"
	_hand_id = doc_id


func _named(calls: Array, name: String) -> Array:
	var out: Array = []
	for c in calls:
		if String(c[0]) == name:
			out.append(c)
	return out


func _run() -> void:
	var gs = root.get_node("GameState")
	var dd = root.get_node("DayDirector")
	gs.new_game(4321)
	dd.begin_day(1)

	var tube := TubeView.new()
	root.add_child(tube)
	tube.held_kind_fn = _get_kind
	tube.held_id_fn = _get_id
	tube.held_release_fn = _release_hand
	tube.use_fake_clock()
	tube.sounds().silent = true
	tube.sounds().recording = true

	# --- Empty hand and non-document items (spec 8.4) --------------------------------------
	_check(not tube.press_receiver(), "the receiver does nothing with an empty hand")
	_hand_kind = "marker"
	_hand_id = ""
	_check(not tube.press_receiver(), "the receiver does nothing while a marker is held")
	_release_hand()

	# --- A free sheet leaves the world (spec 7.9, 8.4) ---------------------------------------
	var free_id: String = dd.take_blank_sheet()
	_check(free_id.begins_with("FREE-"), "a blank sheet on Day 1 is a free sheet (spec 7.9)")
	_check(gs.location_of(free_id) == "hand", "the free sheet is in the hand")
	_hold(free_id)
	_check(tube.press_receiver(), "clicking the receiver with a document held starts a send (spec 8.4)")
	_check(tube.busy(), "the send sequence is running")
	tube.advance(450)
	_check(gs.location_of(free_id) == "removed", "the free sheet leaves the world through DayDirector")
	_check(gs.free_mail_sent.has(free_id), "DayDirector records the free sheet as sent for the next morning")
	_check(_hand_kind == "", "the hand is empty once the sheet is in the tube")
	tube.advance(1200)
	_check(_named(tube.sounds().calls, "tube_send").size() == 1, "the send plays tube_send once, as the canister leaves")
	_check(not tube.busy() and not tube.canister_visible(), "the canister leaves out of sight and the terminal is free")

	# --- Anything can be sent; misc is counted (spec 8.4) ------------------------------------
	var cover := DocModel.new_doc("COVER-M6", "cover", "typed", "black")
	cover.pages.append(DocModel.new_page())
	gs.add_doc(cover, "hand")
	var misc_before: int = gs.misc_sent
	_hold("COVER-M6")
	_check(tube.press_receiver(), "a cover sheet can be sent")
	tube.advance(450)
	_check(gs.misc_sent == misc_before + 1 and gs.location_of("COVER-M6") == "", "a cover sent through the tube is counted as misc and leaves the world")
	tube.advance(1200)

	# --- A T-1 original is kept in the removed store (spec 13.3, 14.8) -----------------------
	dd.active_task = "T-1"
	var sheet_id: String = dd.take_blank_sheet()
	_check(sheet_id.begins_with("SHEET-") and String(gs.docs[sheet_id].kind) == "sheet", "a transcription sheet is a sheet, not a free sheet (spec 8.5)")
	var carbon_id := String(gs.docs[sheet_id].twin)
	_check(carbon_id != "" and gs.location_of(carbon_id) == "attached", "the carbon of a transcription sheet starts attached to the desk")
	_hold(sheet_id)
	_check(tube.press_receiver(), "the transcription sheet is sent")
	tube.advance(450)
	_check(gs.location_of(sheet_id) == "removed", "the T-1 original is in the removed store")
	_check(int(gs.docs[sheet_id].get("returns_on", 0)) == 2, "the T-1 original has returns_on set to the next day (spec 14.8)")
	_check(gs.location_of(carbon_id) == "attached", "the carbon stays in the world")
	_check(String(dd.active_task) == "" or String(dd.active_task) == "T-1", "the transcription task was completed by the send")
	tube.advance(1200)

	# --- NO SUCH ADDRESSEE is data only (spec 8.4) ------------------------------------------
	dd.call("_return_free_mail", 2)
	var returned: Dictionary = gs.docs[free_id]
	var stamps: Array = returned.pages[0].stamps
	_check(stamps.size() == 1 and String(stamps[0].result) == "NO SUCH ADDRESSEE", "the returned free sheet carries a NO SUCH ADDRESSEE stamp in its page data")
	var st: Dictionary = stamps[0] if stamps.size() > 0 else {}
	_check(not st.is_empty() and float(st.y) < float(DocModel.PAGE_H) / 3.0, "the mark sits in the top third of the page (spec 8.4)")
	_check(not st.is_empty() and absf(float(st.x) - float(DocModel.PAGE_W) * 0.5) < 0.5, "the mark is centred horizontally")
	_check(gs.location_of(free_id) == "inbox", "the returned free sheet arrives in the inbox")
	var src := FileAccess.get_file_as_string("res://scripts/tube/tube_view.gd")
	_check(not src.contains("\"NO SUCH") and not src.contains("stamps.append") and not src.contains("add_stamp"), "tube_view.gd draws or writes no NO SUCH ADDRESSEE mark (the rule is data only)")

	# --- Arrivals (spec 8.4) ------------------------------------------------------------------
	tube.listen()
	tube.sounds().calls.clear()
	var shown: Array = []
	tube.arrival_shown.connect(func(ids): shown.append(ids))
	dd.canister_arrived.emit([free_id])
	_check(tube.busy(), "an arrival starts the canister sequence")
	tube.advance(1000)
	tube.advance(350)
	tube.advance(2000)
	var whoosh := _named(tube.sounds().calls, "tube_arrive_whoosh")
	var thunk := _named(tube.sounds().calls, "tube_thunk")
	var leave := _named(tube.sounds().calls, "tube_send")
	_check(whoosh.size() == 1 and float(whoosh[0][1]) == 0.0, "the arrival starts with tube_arrive_whoosh at its own level")
	_check(thunk.size() == 1 and float(thunk[0][1]) == 0.0, "the canister lands with tube_thunk")
	_check(leave.size() == 1 and float(leave[0][1]) == -12.0, "the canister leaves with tube_send at -30 dBFS peak (file -18 dBFS, gain -12 dB)")
	_check(shown.size() == 1 and (shown[0] as Array).has(free_id), "arrival_shown reports the arrived documents")
	_check(not tube.busy(), "the terminal is free after the arrival")

	var order_ok := tube.sounds().calls.size() >= 3
	if order_ok:
		order_ok = String(tube.sounds().calls[0][0]) == "tube_arrive_whoosh" and String(tube.sounds().calls[1][0]) == "tube_thunk"
	_check(order_ok, "the sounds run whoosh, then thunk, then the departing send")
