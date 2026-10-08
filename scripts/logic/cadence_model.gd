extends RefCounted
## Keystroke timing capture and ghost-typing delays (spec 10.1 and 10.2). Pure
## object: the Cadence autoload owns one instance and persists it.
##
## Newline is stored as ENTER (spec 10.1 uses the return sign for Enter).

const ENTER := "⏎"
const RING_SIZE := 2000
const MAX_GAP_MS := 1500.0
const MIN_INTERVAL_MS := 40.0
const FALLBACK_MS := 180.0
const ENTER_FALLBACK_MS := 600.0

var intervals: Array = []  # ring of the last RING_SIZE intervals, clamped to 40..1500 ms
var bigram := {}  # "previous current" -> {"mean": float, "n": int}
var return_mean := 0.0
var return_n := 0
var _prev_ms := -1.0
var _prev_char := ""


## Records one accepted keypress (spec 10.1). ch is the typed character, or ENTER.
func record(ch: String, now_ms: float) -> void:
	if _prev_ms >= 0.0:
		var gap := now_ms - _prev_ms
		if gap <= MAX_GAP_MS:
			var interval := clampf(gap, MIN_INTERVAL_MS, MAX_GAP_MS)
			intervals.append(interval)
			if intervals.size() > RING_SIZE:
				intervals.pop_front()
			var key := _prev_char + ch
			var entry: Dictionary = bigram.get(key, {"mean": 0.0, "n": 0})
			entry.n = int(entry.n) + 1
			entry.mean = float(entry.mean) + (interval - float(entry.mean)) / float(entry.n)
			bigram[key] = entry
			if ch == ENTER:
				return_n += 1
				return_mean += (interval - return_mean) / float(return_n)
	_prev_ms = now_ms
	_prev_char = ch


## Delay before typing ch after prev, in ms (spec 10.2). Uses the bigram mean when
## it has at least two samples, else a random interval, else 180 ms. Enter uses
## the return mean, else 600 ms.
func delay_for(prev: String, ch: String, rng: RandomNumberGenerator) -> float:
	if ch == ENTER:
		return return_mean if return_n > 0 else ENTER_FALLBACK_MS
	var entry: Dictionary = bigram.get(prev + ch, {"mean": 0.0, "n": 0})
	if int(entry.n) >= 2:
		return float(entry.mean)
	if intervals.is_empty():
		return FALLBACK_MS
	return float(intervals[rng.randi_range(0, intervals.size() - 1)])


func to_dict() -> Dictionary:
	return {
		"intervals": intervals,
		"bigram": bigram,
		"return_mean": return_mean,
		"return_n": return_n,
	}


func from_dict(d: Dictionary) -> void:
	intervals = []
	for v in d.get("intervals", []):
		intervals.append(float(v))
	bigram = d.get("bigram", {})
	return_mean = float(d.get("return_mean", 0.0))
	return_n = int(d.get("return_n", 0))
	_prev_ms = -1.0
	_prev_char = ""
