extends SceneTree
## Headless checks for Ending C steps 4 and 5 (spec 15.3) as wired in main.gd: the presentation's
## silence() stops clerk typing and the clock, and restore_record() rebuilds the desks removed by
## redaction, with their clerks, facing Desk 4. Run: godot --headless --path /home/user/Carbon
## --script res://tests/world/room_test.gd. Exit 0 only when every check passes.
## Prints "ROOM: N checks, M failures".
const MainScript := preload("res://scripts/main.gd")

var _checks := 0
var _fails := 0
var _started := false
var _main = null
var _gs = null
var _hall: Node = null


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _check(ok: bool, label: String) -> void:
	_checks += 1
	if not ok:
		_fails += 1
	print("%s  %s" % ["PASS" if ok else "FAIL", label])


func _run() -> void:
	_gs = root.get_node("GameState")
	_main = MainScript.new()
	_main.auto_boot = false
	root.add_child(_main)
	await process_frame
	_main.debug_start_game(4242)
	await process_frame
	_hall = _main.hall
	_checks_wiring()
	_checks_silence()
	_checks_restore()
	_teardown()
	print("ROOM: %d checks, %d failures" % [_checks, _fails])
	quit(0 if _fails == 0 else 1)


func _checks_wiring() -> void:
	var pres = _main.endings_pres
	_check(pres.room_silenced.is_connected(_main._on_room_silenced), "the presentation's silence is connected to main")
	_check(pres.desks_restored.is_connected(_main._on_desks_restored), "the presentation's restore_record is connected to main")
	_check(_main.clerk_world != null and _main.clock_world != null, "main owns the clerk and clock behaviours")


# --- Step 4: silence (spec 15.3) ---------------------------------------------------------------

func _checks_silence() -> void:
	var cw = _main.clerk_world
	var kw = _main.clock_world
	_check(not cw._silenced and not kw._silenced, "before the silence, clerks and clock run")
	var ad = root.get_node("AudioDirector")
	ad.set_checker_enabled(true)
	_main.endings_pres.silence()
	_check(cw._silenced and kw._silenced, "the silence stops clerk typing and the clock")
	var before: int = ad.get_checker_playbacks()
	cw._process(2.0)
	kw._process(2.0)
	_check(int(ad.get_checker_playbacks()) == before, "after the silence no clerk key, carriage or clock tick plays")
	kw._on_clock_set("10:00", 2.0)
	_check(not kw._anim, "after the silence the clock hands do not move")
	ad.set_checker_enabled(false)


# --- Step 5: restoration (spec 15.3) -----------------------------------------------------------

func _checks_restore() -> void:
	var cw = _main.clerk_world
	# Desk 7 is removed by redaction (spec 8.9): the world drops its desk and clerk.
	_gs.desk_removed["7"] = true
	_gs.clerk_present["7"] = false
	_gs.clerk_faces_player["7"] = false
	cw.apply_day_state(4)
	_check(_hall.get_node_or_null("Desk07") == null and _hall.get_node_or_null("Clerk07") == null, "a redacted desk and its clerk are removed from the world")
	_check(_hall.get_node_or_null("Chair07") == null and _hall.get_node_or_null("Typewriter07") == null and _hall.get_node_or_null("Tube07") == null, "its chair, typewriter and tube terminal are removed too")
	# The ending's state: Desk 12 cleared, bars on, Desk 7 to come back.
	_gs.nameplate["12"] = ""
	_gs.redacted_names = ["DOBRA, KASIMIR", "FELL, ODETTE"]
	_gs.redacted_desks = [7]
	_main.endings_pres.restore_record([7])
	_check(_gs.redacted_names.is_empty(), "the redaction bars are cleared (GameState.redacted_names is empty)")
	_check(not bool(_gs.desk_removed.get("7", true)) and bool(_gs.clerk_present.get("7", false)), "Desk 7 is back in the state")
	_check(String(_gs.nameplate.get("12", "")) == "0411", "Desk 12's nameplate returns to 0411 when cleared")
	var desk := _hall.get_node_or_null("Desk07")
	_check(desk != null and desk.get_node_or_null("Nameplate") != null, "Desk 7 is rebuilt with its nameplate")
	_check(_hall.get_node_or_null("Chair07") != null and _hall.get_node_or_null("Typewriter07") != null and _hall.get_node_or_null("Tube07") != null, "Desk 7 comes back with its chair, typewriter and tube terminal")
	var fig := _hall.get_node_or_null("Clerk07") as Node3D
	_check(fig != null, "Desk 7's seated clerk figure is back")
	if fig != null:
		_check(absf(fig.rotation.y) > 0.5, "the restored clerk faces Desk 4, not north (yaw %.1f deg)" % rad_to_deg(fig.rotation.y))
	var other := _hall.get_node_or_null("Clerk01") as Node3D
	_check(other != null and absf(other.rotation.y) > 0.01, "a clerk still in the room faces Desk 4 after the restoration")
	_check(cw._silenced, "the restored clerks do not type (the silence still holds)")


func _teardown() -> void:
	_gs.desk_removed["7"] = false
	_gs.clerk_present["7"] = true
	_gs.clerk_faces_player["7"] = false
	if _main != null:
		_main.queue_free()
