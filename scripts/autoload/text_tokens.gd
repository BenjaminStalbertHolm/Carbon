extends Node
## TextTokens: runtime token substitution, redaction rendering spans and the
## retired-word rules (spec 14.1, 14.3, 8.3, 8.8). Autoload.

const TextNorm := preload("res://scripts/logic/text_norm.gd")
const Redaction := preload("res://scripts/logic/redaction.gd")
const FondWord := preload("res://scripts/logic/fond_word.gd")

const DEFAULT_PLAYER_NAME := "CLERK 0412"
const DEFAULT_NEXT_OF_KIN := "M. ALDER"


## Spec 14.1 token values for the current game state.
func token_values() -> Dictionary:
	var gs := get_node("/root/GameState")
	var name := TextNorm.sanitize_name(gs.player_name_raw) if gs.player_name_raw != "" else ""
	var player := name if name != "" else DEFAULT_PLAYER_NAME
	var first := TextNorm.first_part(player) if name != "" else "CLERK"
	var kin := TextNorm.sanitize_name(gs.next_of_kin_raw) if gs.next_of_kin_raw != "" else ""
	if kin == "":
		kin = DEFAULT_NEXT_OF_KIN
	return {
		"PLAYER_NAME": player,
		"PLAYER_NAME_TC": TextNorm.title_case(player),
		"PLAYER_FIRST_NAME": first,
		"PLAYER_FIRST_NAME_TC": TextNorm.title_case(first),
		"NEXT_OF_KIN": kin,
		"NEXT_OF_KIN_TC": TextNorm.title_case(kin),
		"FOND_WORD": gs.fond_word if gs.fond_word != "" else "QUIET",
		"P1_Q4": _p1_q4_word(gs.p1_q4),
		"SIGNATURE_MATCHES": "TRUE" if gs.signature_matches else "FALSE",
	}


static func _p1_q4_word(q: String) -> String:
	return q if q == "YES" or q == "NO" else "OTHER"


## Replaces every runtime token in text. Unknown braces are left alone, so form
## markers such as {{F1:24}} pass through unchanged.
func substitute(text: String) -> String:
	var values := token_values()
	var out := text
	for key in ["PLAYER_FIRST_NAME_TC", "PLAYER_FIRST_NAME", "PLAYER_NAME_TC", "PLAYER_NAME", "NEXT_OF_KIN_TC", "NEXT_OF_KIN", "FOND_WORD", "P1_Q4", "SIGNATURE_MATCHES"]:
		out = out.replace("{" + key + "}", String(values[key]))
	return out


## Callable for APIs that need a substitution function (DocModel.build_doc).
func subst_callable() -> Callable:
	return Callable(self, "substitute")


## Spans [start, end) that must render as redaction bars on a non-carbon page
## line (spec 8.3 and 8.8). Entity spans come from redacted_names. The retired
## word applies from Day 3 to whole words, both in game text and in typed or
## ghost text. Carbons are immune (spec 8.7), so callers skip them.
func bar_spans(line_text: String) -> Array:
	var gs := get_node("/root/GameState")
	var spans: Array = []
	if gs.redacted_names.size() > 0:
		spans.append_array(Redaction.find_entity_spans(line_text, gs.redacted_names, subst_callable()))
	if gs.day >= 3 and gs.fond_word != "":
		spans.append_array(Redaction.find_word_spans(line_text, gs.fond_word))
	return spans
