extends RefCounted
## Loads the JSON content under res://data (spec 3.4). Files are parsed once and
## cached. Callers must treat the returned Dictionaries as read-only.

static var _cache := {}


static func load_json(path: String) -> Variant:
	if _cache.has(path):
		return _cache[path]
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if data == null:
		push_error("content: could not parse %s" % path)
		data = {}
	_cache[path] = data
	return data


static func strings() -> Dictionary:
	return load_json("res://data/strings.json")


static func day(n: int) -> Dictionary:
	return load_json("res://data/day%d.json" % n)


static func layouts() -> Dictionary:
	return load_json("res://data/layouts.json")


static func endings() -> Dictionary:
	return load_json("res://data/endings.json")


static func credits() -> Dictionary:
	return load_json("res://data/credits.json")
