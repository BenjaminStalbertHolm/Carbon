extends RefCounted
## Text normalisation, name sanitising and accuracy (spec 7.8 and 14.1).
## Pure static functions; no state.

const Lev := preload("res://scripts/logic/levenshtein.gd")


## Spec 7.8: uppercase, one space for each run of whitespace, trimmed.
static func normalise(s: String) -> String:
	var t := s.to_upper().replace("\n", " ").replace("\t", " ")
	return " ".join(t.split(" ", false))


## Spec 14.1 name sanitising: uppercase, keep only A-Z, space, "-", "'" and ".",
## collapse spaces, trim, then keep the first 24 characters.
static func sanitize_name(raw: String) -> String:
	var kept := ""
	for ch in raw.to_upper():
		var c := ch.unicode_at(0)
		if (c >= 65 and c <= 90) or c == 32 or c == 45 or c == 39 or c == 46:
			kept += ch
	var s := " ".join(kept.split(" ", false))
	if s.length() > 24:
		s = s.substr(0, 24)
	return s


## Spec 14.1 "_TC" variants: each space-separated part gets an upper-case first
## letter and lower-case rest.
static func title_case(s: String) -> String:
	var parts := PackedStringArray()
	for part in s.split(" ", false):
		parts.append(part.substr(0, 1).to_upper() + part.substr(1).to_lower())
	return " ".join(parts)


## First space-separated part, or "" when there is none.
static func first_part(s: String) -> String:
	var parts := s.split(" ", false)
	return parts[0] if parts.size() > 0 else ""


## Spec 7.8: accuracy = max(0, 1 - levenshtein(typed, source) / len(source)).
## Both strings are normalised first. An empty source scores 1.0 only when the
## typed text is also empty.
static func accuracy(typed: String, source: String) -> float:
	var t := normalise(typed)
	var s := normalise(source)
	if s.length() == 0:
		return 1.0 if t.length() == 0 else 0.0
	return maxf(0.0, 1.0 - float(Lev.distance(t, s)) / float(s.length()))
