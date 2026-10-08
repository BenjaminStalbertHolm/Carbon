extends RefCounted
## Clock arithmetic (spec 8.10). Pure functions.
## Times are minutes after midnight, read as HH:MM on the clock face.

const DAY_START := "08:58"
const SHIFT_START_MIN := 540  # 09:00
const SHIFT_LENGTH_MIN := 480  # 8 hours
const END_OF_SHIFT := "16:58"


## Spec 8.10: after the k-th task of n is sent, time = 09:00 + 8 h × k / n,
## rounded down to the minute. k = n gives 17:00. Spec 8.10 then sets 16:58 when the
## End of Shift memo arrives (QUESTION-5, decided literal).
static func time_after_task(k: int, n: int) -> String:
	var minutes := SHIFT_START_MIN + int(floor(float(SHIFT_LENGTH_MIN * k) / float(n)))
	return format_minutes(minutes)


static func format_minutes(total: int) -> String:
	return "%02d:%02d" % [total / 60, total % 60]


static func parse_hhmm(s: String) -> int:
	var parts := s.split(":")
	return int(parts[0]) * 60 + int(parts[1])


## Hand angles in degrees, clockwise from 12 o'clock (spec 5.4 and 8.10).
## Returns {hour, minute}.
static func hand_angles(hhmm: String) -> Dictionary:
	var total := parse_hhmm(hhmm)
	var h := total / 60
	var m := total % 60
	return {
		"hour": fmod(float(h % 12) + float(m) / 60.0, 12.0) * 30.0,
		"minute": float(m) * 6.0,
	}
