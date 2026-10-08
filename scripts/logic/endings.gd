extends RefCounted
## Ending rules (spec 15) as pure functions. The sequences themselves (timing,
## camera, lights, sound) belong to the endings presentation. This file decides
## which ending applies and which lines Ending C types.
##
## Inputs are plain data taken from GameState:
##   ro_results: {"RO-2": {"entries": {key: bool}, "listed": [key...]}, ...}
##   registers:  {"RO-2": [{key, name, entity, listed}], ...} (RO-4 includes carried)
##   player_name: the substituted {PLAYER_NAME} text

## Spec 15: Ending A when the Desk 4 entry is redacted on RO-5, regardless of stamp.
static func desk4_redacted(ro5_entries: Dictionary) -> bool:
	return bool(ro5_entries.get("04", false))


## Spec 15: after the refusal, Ending C is available only with 3 or more
## transcription carbons outside the lower drawer.
static func ending_c_available(carbons_kept_at_final: int) -> bool:
	return carbons_kept_at_final >= 3


## Spec 15.3 step 3: the ghost-typed lines of Ending C, in order.
## Lines: RECORD RESTORED, then one line per entity redacted on RO-2, RO-3 or RO-4
## in that order (each in list order, using the string as it appears on the order),
## then the player's name. Name text containing a token is resolved with subst.
static func ending_c_lines(ro_results: Dictionary, registers: Dictionary, player_name: String, subst: Callable, record_line: String) -> Array:
	var lines: Array = [record_line]
	for order_id in ["RO-2", "RO-3", "RO-4"]:
		var record: Dictionary = ro_results.get(order_id, {})
		var entries: Dictionary = record.get("entries", {})
		var listed: Array = record.get("listed", [])
		var register: Array = registers.get(order_id, [])
		for key in listed:
			if not bool(entries.get(String(key), false)):
				continue
			for entry in register:
				if String(entry.key) == String(key):
					lines.append(String(subst.call(String(entry.name))))
	lines.append(player_name)
	return lines


## Spec 15.3 step 5: a desk removed by redaction comes back when Ending C restores
## the record. Returns the desk numbers (as strings) to restore, in order.
static func desks_to_restore(ro_results: Dictionary, registers: Dictionary) -> Array:
	var out: Array = []
	for order_id in ["RO-3", "RO-4"]:
		var record: Dictionary = ro_results.get(order_id, {})
		var entries: Dictionary = record.get("entries", {})
		for entry in registers.get(order_id, []):
			if entry.get("clerk_desk") == null:
				continue
			if bool(entries.get(String(entry.key), false)):
				out.append(str(int(entry.clerk_desk)))
	return out
