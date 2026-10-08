extends RefCounted
## Debug-only loudness checker for AudioDirector (spec 11.1, Rules A and B).
## Every playback is judged and counted (playbacks, violations, exempt_playbacks). Only a playback
## that breaks Rule A or B and is not exempt prints a line ("AUDIO VIOLATION") and increments `violations`.
## Passing and exempt playbacks print nothing (QUESTION-69), so the violation lines are not buried.
## Attenuation over distance is not modelled: the check is the file peak plus the playback gain.
## is_active() is false in release builds, so nothing is analysed or logged there.

const LoudnessAnalyser := preload("res://scripts/audio/loudness_analyser.gd")

const RULE_A_PEAK_DB := -24.0
const RULE_A_ATTACK_ABOVE_DB := -30.0
const RULE_A_MIN_ATTACK_MS := 150.0
const RULE_B_PEAK_DB := -10.0
const EPS := 0.01

## Beds start with a volume ramp of BED_RAMP_MS (spec 11.2; the 2.0 s of the spec 13.1 fade-in),
## so their attack is that ramp, not the file onset.
const RAMP_BEDS := ["room_tone", "hum", "vent_shepard"]
const BED_RAMP_MS := 2000.0

## Sounds allowed to break Rule A, with the documented reason. scope "all" exempts every Rule A
## problem (peak and attack). scope "attack" exempts only the attack test; the peak limit still applies.
const EXEMPTIONS := {
	"tube_thunk": {"scope": "all", "reason": "spec 11.1 exception: always preceded by tube_arrive_whoosh"},
	"fixture_off": {"scope": "attack", "reason": "spec 11.3 recipe: attack 150 ms (Rule A); 90% proxy measure differs"},
	"fixture_on": {"scope": "attack", "reason": "spec 11.3 recipe: attack 150 ms (Rule A); 90% proxy measure differs"},
	"door_unlock": {"scope": "attack", "reason": "spec 11.3 recipe: attack 150 ms (Rule A); 90% proxy measure differs"},
}

var enabled := true
var playbacks := 0
var violations := 0
var exempt_playbacks := 0
var _analysis: Dictionary = {}


func is_active() -> bool:
	return enabled and OS.is_debug_build()


## Pure rule check, shared with tests. Returns "" when the playback obeys the rules, else the reason.
## The attack problem message begins with "Rule A attack", so is_exempt() can tell it from a peak problem.
static func judge(peak_db: float, attack_ms: float, player_caused: bool) -> String:
	if player_caused:
		if peak_db > RULE_B_PEAK_DB + EPS:
			return "Rule B: player-caused peak %.2f dBFS is above -10" % peak_db
		return ""
	if peak_db > RULE_A_PEAK_DB + EPS:
		return "Rule A: peak %.2f dBFS is above -24" % peak_db
	if peak_db > RULE_A_ATTACK_ABOVE_DB + EPS and attack_ms < RULE_A_MIN_ATTACK_MS - EPS:
		return "Rule A attack: peak %.2f dBFS is above -30 with attack %.1f ms (needs 150 ms)" % [peak_db, attack_ms]
	return ""


## True when the problem is covered by the documented exemption of this sound.
static func is_exempt(sound: String, problem: String) -> bool:
	if not EXEMPTIONS.has(sound) or not problem.begins_with("Rule A"):
		return false
	if EXEMPTIONS[sound]["scope"] == "attack":
		return problem.begins_with("Rule A attack")
	return true


## The attack a playback is judged on: a bed's applied start ramp, else the file's onset.
static func applied_attack_ms(sound: String, file_attack_ms: float) -> float:
	return BED_RAMP_MS if RAMP_BEDS.has(sound) else file_attack_ms


## File-level measurements, read once per file and cached.
func analysis(sound: String, stream: AudioStreamWAV) -> Dictionary:
	if not _analysis.has(sound):
		_analysis[sound] = LoudnessAnalyser.analyse(stream)
	return _analysis[sound]


## Logs and judges one playback. Call only when is_active(). ramp_ms, when at least 0, is the attack
## the caller applied (a bed's start ramp); it replaces the file's onset.
func record(sound: String, source: String, stream: AudioStreamWAV, gain_db: float, player_caused: bool, ramp_ms := -1.0) -> void:
	var info := analysis(sound, stream)
	var file_peak: float = info["peak_db"]
	var attack: float = info["attack_ms"] if ramp_ms < 0.0 else ramp_ms
	var at_listener := file_peak + gain_db
	var problem := judge(at_listener, attack, player_caused)
	var kind := "PLAYER" if player_caused else "AMBIENT"
	playbacks += 1
	var detail := "%s [%s] %s file_peak=%.2f dBFS gain=%.2f dB peak=%.2f dBFS attack=%.1f ms" % [
		sound, source, kind, file_peak, gain_db, at_listener, attack]
	if problem == "":
		return
	if is_exempt(sound, problem):
		exempt_playbacks += 1
		return
	violations += 1
	print("AUDIO VIOLATION: %s -- %s" % [detail, problem])


func reset() -> void:
	playbacks = 0
	violations = 0
	exempt_playbacks = 0
