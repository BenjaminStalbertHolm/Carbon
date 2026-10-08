extends RefCounted
## Levenshtein edit distance (spec 7.8 and 8.6). Two-row dynamic programme.
## Pure static functions; no state.


static func distance(a: String, b: String) -> int:
	var n := a.length()
	var m := b.length()
	if n == 0:
		return m
	if m == 0:
		return n
	var prev := PackedInt32Array()
	prev.resize(m + 1)
	var cur := PackedInt32Array()
	cur.resize(m + 1)
	for j in range(m + 1):
		prev[j] = j
	for i in range(1, n + 1):
		cur[0] = i
		var ca := a.unicode_at(i - 1)
		for j in range(1, m + 1):
			var cost := 0 if ca == b.unicode_at(j - 1) else 1
			cur[j] = mini(mini(prev[j] + 1, cur[j - 1] + 1), prev[j - 1] + cost)
		var tmp := prev
		prev = cur
		cur = tmp
	return prev[m]
