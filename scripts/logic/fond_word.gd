extends RefCounted
## The P-1 "word you are fond of" rules (spec 14.1 and 8.8). Pure functions.

const Redaction := preload("res://scripts/logic/redaction.gd")


## Spec 14.1: letters only, uppercase, first 12 letters. Replaced by QUIET if it
## has fewer than 4 letters, or if it equals any whole word in the reserved set.
## reserved_words is the set built by reserved_words_from() from the content.
static func compute(raw: String, reserved_words: Array) -> String:
	var letters := ""
	for ch in raw.to_upper():
		var c := ch.unicode_at(0)
		if c >= 65 and c <= 90:
			letters += ch
	letters = letters.substr(0, 12)
	if letters.length() < 4:
		return "QUIET"
	if reserved_words.has(letters):
		return "QUIET"
	return letters


## Whole words of the token-free texts named in spec 14.1: the source texts of
## T-3 and T-4, and the printed text of RO-3, RO-4, F-3, S-4 and P-1D. lines is
## an Array of raw strings. Tokens in braces are removed before splitting, so
## token names do not count as words.
static func reserved_words_from(lines: Array) -> Array:
	var words := {}
	var token := RegEx.create_from_string("\\{[^}]*\\}")
	for raw in lines:
		var cleaned := token.sub(String(raw).to_upper(), " ", true)
		var word := ""
		for ch in cleaned:
			var c := ch.unicode_at(0)
			if c >= 65 and c <= 90:
				word += ch
			else:
				if word != "":
					words[word] = true
				word = ""
		if word != "":
			words[word] = true
	return words.keys()
