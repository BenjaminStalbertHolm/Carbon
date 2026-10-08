extends RefCounted
## Debug-only loudness checker for AudioDirector (spec 11.1, Rules A and B).
## Every playback is logged with the file's normalised peak, the playback gain and the verdict.
## A playback that breaks Rule A or B prints "AUDIO VIOLATION" and increments `violations`.
## Attenuation over distance is not modelled: the check is the file peak plus the playback gain.
## is_active() is false in release builds, so nothing is analysed or logged there.

const LoudnessAnalyser := preload("res://scripts/audio/loudness_analyser.gd")

const RULE_A_PEAK_DB := -24.0
const RULE_A_ATTACK_ABOVE_DB := -30.0
const RULE_A_MIN_ATTACK_MS := 150.0
const RULE_B_PEAK_DB := -10.0
const EPS := 0.01

## Sounds allowed to break Rule A, with the documented reason. Only Rule A problems are exempted.
const EXEMPTIONS := {
	"tube_thunk": "spec 11.1 exception: always preceded by tube_arrive_whoosh",
}

var enabled := true
var playbacks := 0
var violations := 0
var exempt_playbacks := 0
var _analysis: Dictionary = {}


func is_active() -> bool:
	return enabled and OS.is_debug_build()


## Pure rule check, shared with tests. Returns "" when the playback obeys the rules, else the reason.
static func judge(peak_db: float, attack_ms: float, player_caused: bool) -> String:
	if player_caused:
		if peak_db > RULE_B_PEAK_DB + EPS:
			return "Rule B: player-caused peak %.2f dBFS is above -10" % peak_db
		return ""
	if peak_db > RULE_A_PEAK_DB + EPS:
		return "Rule A: peak %.2f dBFS is above -24" % peak_db
	if peak_db > RULE_A_ATTACK_ABOVE_DB + EPS and attack_ms < RULE_A_MIN_ATTACK_MS - EPS:
		return "Rule A: peak %.2f dBFS is above -30 with attack %.1f ms (needs 150 ms)" % [peak_db, attack_ms]
	return ""


static func is_exempt(sound: String, problem: String) -> bool:
	return EXEMPTIONS.has(sound) and problem.begins_with("Rule A")


## File-level measurements, read once per file and cached.
func analysis(sound: String, stream: AudioStreamWAV) -> Dictionary:
	if not _analysis.has(sound):
		_analysis[sound] = LoudnessAnalyser.analyse(stream)
	return _analysis[sound]


## Logs and judges one playback. Call only when is_active().
func record(sound: String, source: String, stream: AudioStreamWAV, gain_db: float, player_caused: bool) -> void:
	var info := analysis(sound, stream)
	var file_peak: float = info["peak_db"]
	var at_listener := file_peak + gain_db
	var problem := judge(at_listener, info["attack_ms"], player_caused)
	var kind := "PLAYER" if player_caused else "AMBIENT"
	playbacks += 1
	var detail := "%s [%s] %s file_peak=%.2f dBFS gain=%.2f dB peak=%.2f dBFS attack=%.1f ms" % [
		sound, source, kind, file_peak, gain_db, at_listener, info["attack_ms"]]
	if problem == "":
		print("AUDIO CHECK ok: " + detail)
	elif is_exempt(sound, problem):
		exempt_playbacks += 1
		print("AUDIO CHECK exempt: %s (%s)" % [detail, EXEMPTIONS[sound]])
	else:
		violations += 1
		print("AUDIO VIOLATION: %s -- %s" % [detail, problem])


func reset() -> void:
	playbacks = 0
	violations = 0
	exempt_playbacks = 0
