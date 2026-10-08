extends RefCounted
## One-shot player pools (spec 11.1, 11.4). 16 non-positional AudioStreamPlayer and 16
## AudioStreamPlayer3D, reused round-robin. A player is free when its sound has finished
## (playing is false). When all 16 of one kind are busy, the next one in turn is cut off and reused.
## Positional players: attenuation inverse distance, unit size 2.0, max distance 20 m, no doppler.

const POOL_SIZE := 16
const SFX_BUS := &"SFX"

var _flat: Array = []
var _spatial: Array = []
var _flat_next := 0
var _spatial_next := 0


## Creates the pooled players under parent. Call once, while parent is in the tree.
func setup(parent: Node) -> void:
	for i in POOL_SIZE:
		var flat := AudioStreamPlayer.new()
		flat.bus = SFX_BUS
		parent.add_child(flat)
		_flat.append(flat)
		var spatial := AudioStreamPlayer3D.new()
		spatial.bus = SFX_BUS
		configure_spatial(spatial)
		parent.add_child(spatial)
		_spatial.append(spatial)


## Positional settings shared by the pool and the vent bed (spec 11.1).
static func configure_spatial(player: AudioStreamPlayer3D) -> void:
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	player.unit_size = 2.0
	player.max_distance = 20.0
	player.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_DISABLED


## Returns a free player of the requested kind. If none is free, the next in turn is stopped first.
func take(positional: bool) -> Node:
	var players: Array = _spatial if positional else _flat
	var start: int = _spatial_next if positional else _flat_next
	var pick := start
	for i in POOL_SIZE:
		var j := (start + i) % POOL_SIZE
		if not players[j].playing:
			pick = j
			break
	if positional:
		_spatial_next = (pick + 1) % POOL_SIZE
	else:
		_flat_next = (pick + 1) % POOL_SIZE
	var player = players[pick]
	if player.playing:
		player.stop()
	return player


## Number of one-shot players currently playing (both kinds).
func active_count() -> int:
	var n := 0
	for p in _flat + _spatial:
		if p.playing:
			n += 1
	return n


## Moves every pooled player under another node (the 3D viewport that holds the listener).
## Call only while nothing is playing.
func reparent_all(parent: Node) -> void:
	for p in _flat + _spatial:
		p.reparent(parent, true)
