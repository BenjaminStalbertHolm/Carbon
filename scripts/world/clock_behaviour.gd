extends Node
## Clock behaviour (spec 8.10, 9.3 D2-U2 and D5-U2). Drives the hands of the Clock
## built by hall_c.gd: animates to GameState.clock_time on DayDirector.clock_set (2.0 s
## moves, smooth at 60 fps), plays clock_tick once per second unless the clock is frozen,
## and shows the UnseenChanges override (flags.clock_override) while it is set.
##
## Usage (the lead): var cb := ClockBehaviour.new(); add_child(cb); cb.setup(hall_root).

const ClockMath := preload("res://scripts/logic/clock_math.gd")

const MOVE_S := 2.0
const TICK_DB := -38.0

var _hall: Node3D = null
var _hour: Node3D = null
var _minute: Node3D = null
var _clock: Node3D = null
var _hour_deg := 0.0
var _minute_deg := 0.0
var _anim := false
var _from_h := 0.0
var _from_m := 0.0
var _to_h := 0.0
var _to_m := 0.0
var _elapsed := 0.0
var _dur := MOVE_S
var _shown_override := ""
var _tick_acc := 0.0


func setup(hall_root: Node3D) -> void:
	_hall = hall_root
	_hour = hall_root.get_node_or_null("ClockHourHand")
	_minute = hall_root.get_node_or_null("ClockMinuteHand")
	_clock = hall_root.get_node_or_null("Clock")
	var dd = get_node_or_null("/root/DayDirector")
	if dd != null:
		dd.connect("clock_set", Callable(self, "_on_clock_set"))
		dd.connect("day_started", Callable(self, "_on_day_started"))
	var gaze = get_node_or_null("/root/Gaze")
	if gaze != null and _clock != null:
		gaze.track(_clock)
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		_snap(String(gs.clock_time))
	_apply_hands()


func _process(delta: float) -> void:
	if _hour == null or _minute == null:
		return
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		return
	var override := String(gs.flags.get("clock_override", ""))
	if override != _shown_override:
		_shown_override = override
		_anim = false
		_snap(override if override != "" else String(gs.clock_time))
	var frozen: bool = bool(gs.clock_frozen)
	if frozen:
		_anim = false
	elif _anim:
		_elapsed += delta
		var t := clampf(_elapsed / _dur, 0.0, 1.0)
		var e := t * t * (3.0 - 2.0 * t)
		_hour_deg = lerpf(_from_h, _to_h, e)
		_minute_deg = lerpf(_from_m, _to_m, e)
		if t >= 1.0:
			_anim = false
	_apply_hands()
	if not frozen and _clock != null:
		_tick_acc += delta
		if _tick_acc >= 1.0:
			_tick_acc -= 1.0
			_play("clock_tick", _clock.global_position, TICK_DB)


## Animates the hands to time over anim_s seconds (spec 8.10). Ignored while frozen or
## while an override is showing; the correct time is then read from GameState.
func _on_clock_set(time: String, anim_s: float) -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null or bool(gs.clock_frozen) or _shown_override != "":
		return
	var target := ClockMath.hand_angles(time)
	_from_h = _hour_deg
	_from_m = _minute_deg
	_to_h = _from_h + wrapf(float(target["hour"]) - _from_h, -180.0, 180.0)
	_to_m = _from_m + wrapf(float(target["minute"]) - _from_m, -180.0, 180.0)
	_elapsed = 0.0
	_dur = maxf(anim_s, 0.001)
	_anim = true


func _on_day_started(_day: int) -> void:
	_anim = false
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		_snap(String(gs.clock_time))


func _snap(time: String) -> void:
	if time == "":
		return
	var a := ClockMath.hand_angles(time)
	_hour_deg = float(a["hour"])
	_minute_deg = float(a["minute"])


func _apply_hands() -> void:
	if _hour != null:
		_hour.rotation_degrees = Vector3(0.0, 0.0, -_hour_deg)
	if _minute != null:
		_minute.rotation_degrees = Vector3(0.0, 0.0, -_minute_deg)


func _play(sfx: String, pos: Vector3, gain_db: float) -> void:
	var ad = get_node_or_null("/root/AudioDirector")
	if ad != null and ad.has_method("play"):
		ad.call("play", sfx, pos, true, gain_db, false)
