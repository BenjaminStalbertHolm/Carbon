extends RefCounted
## Maps TypewriterModel events to AudioDirector calls (spec 7.3, 7.4, 7.6, 8.8, 11.1,
## 11.3, 11.4). TypewriterView passes each batch of model events to play_events()
## and calls tick() every frame, so the platen clicks of a long line feed are spread
## over their time.
##
## Ghost gain (spec 11.1): ghost keys, returns and bells get -20 dB here.
## Rule A and B (spec 11.1, QUESTION-47): a sound that is not player-caused (a ghost-typing jam)
## gets the same -20 dB as the other ghost sounds. key_jam peaks at -14 dBFS in its file, so
## -20 dB puts it at -34 dBFS, below Rule A's -24 dBFS at the listener.
##
## Tests set silent = true and read calls, so no audio plays.

const GHOST_GAIN_DB := -20.0
const NON_PLAYER_JAM_DB := -20.0
const RATCHET_DEFAULT_MS := 400.0
## tube_send is -18 dBFS in its file. Spec 8.4 says the departing canister is at -30 dBFS.
const TUBE_SEND_LEAVE_DB := -12.0

var position := Vector3(5.25, 0.9, 3.45)  # Desk 4 typewriter (spec 11.4); the view sets it
var silent := false
var recording := false
var calls: Array = []  # [sound, gain_db, player_caused] while recording (tests)
var _due: Array = []  # [at_ms, sound, gain_db, player_caused]


## Plays the sounds for a batch of model events (spec 7 and 8.8).
## ghost_active is true while ghost typing has keys still queued.
func play_events(events: Array, now_ms: float, ghost_active: bool = false) -> void:
	for raw in events:
		var ev: Dictionary = raw
		match String(ev.get("t", "")):
			"key":
				var ghost := bool(ev.get("ghost", false))
				play("key_clack", position, GHOST_GAIN_DB if ghost else 0.0, not ghost)
			"jam":
				var jam_player := not ghost_active
				play("key_jam", position, 0.0 if jam_player else NON_PLAYER_JAM_DB, jam_player)
			"bell":
				var bell_ghost := bool(ev.get("ghost", false))
				play("bell", position, GHOST_GAIN_DB if bell_ghost else 0.0, not bell_ghost)
			"return":
				var ret_ghost := bool(ev.get("ghost", false))
				play("carriage_return", position, GHOST_GAIN_DB if ret_ghost else 0.0, not ret_ghost)
			"ratchet":
				_schedule_ratchets(int(ev.get("count", 1)), float(ev.get("ms", 0.0)), now_ms)
			"backspace":
				play("backspace_click", position, 0.0, true)
			"fluid":
				play("fluid_brush", position, 0.0, true)
	tick(now_ms)


## Plays every scheduled click that is due (platen_ratchet, spread over a line feed).
func tick(now_ms: float) -> void:
	if _due.is_empty():
		return
	_due.sort_custom(func(a, b): return float(a[0]) < float(b[0]))
	while not _due.is_empty() and float(_due[0][0]) <= now_ms:
		var item: Array = _due.pop_front()
		play(String(item[1]), position, float(item[2]), bool(item[3]))


func pending_clicks() -> int:
	return _due.size()


## One-shot at a world position. Used by the view for paper and tube sounds.
func play(sound: String, at: Vector3, gain_db: float, player_caused: bool) -> void:
	if recording:
		calls.append([sound, gain_db, player_caused])
	if silent:
		return
	var audio := _audio()
	if audio != null and audio.has_method("play"):
		audio.call("play", sound, at, true, gain_db, player_caused)


## The departing canister of spec 8.4 (-30 dBFS at the listener).
func play_tube_leave(at: Vector3) -> void:
	play("tube_send", at, TUBE_SEND_LEAVE_DB, false)


func _schedule_ratchets(count: int, ms: float, now_ms: float) -> void:
	# No cap on the clicks (QUESTION-50). A 53-line move at the default span keeps about ten
	# 70 ms platen_ratchet files overlapping, which the 16-voice pool holds.
	var n := maxi(count, 0)
	if n <= 0:
		return
	if n == 1:
		_due.append([now_ms, "platen_ratchet", 0.0, true])
		return
	var span := ms if ms > 0.0 else RATCHET_DEFAULT_MS
	for i in range(n):
		_due.append([now_ms + span * float(i) / float(n), "platen_ratchet", 0.0, true])


func _audio() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null("AudioDirector")
