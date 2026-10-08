extends RefCounted
## One-shot player pools (spec 11.1, 11.4). 16 non-positional AudioStreamPlayer and 16
## AudioStreamPlayer3D, reused round-robin. A player is free when its sound has finished
## (playing is false). When all 16 of one kind are busy, the next player in turn is cut off and
## reused, skipping any player that holds a loop unless every player holds one.
## Loops (start_loop, the marker drag of spec 8.2) hold their player until stop_loop().
## Positional players: attenuation inverse distance, unit size 2.0, max distance 20 m, no doppler.

const POOL_SIZE := 16
const SFX_BUS := &"SFX"

var _flat: Array = []
var _spatial: Array = []
var _flat_next := 0
var _spatial_next := 0
var _loops: Dictionary = {}  # loop id -> the player holding that loop
var _loop_serial := 0


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


## Returns a free player of the requested kind. If none is free, the next one in turn that holds no
## loop is stopped first (or the next in turn when every player holds a loop).
func take(positional: bool) -> Node:
	var players: Array = _spatial if positional else _flat
	var start: int = _spatial_next if positional else _flat_next
	var pick := -1
	for i in POOL_SIZE:
		var j := (start + i) % POOL_SIZE
		if not players[j].playing:
			pick = j
			break
	if pick == -1:
		for i in POOL_SIZE:
			var j := (start + i) % POOL_SIZE
			if not _holds_loop(players[j]):
				pick = j
				break
	if pick == -1:
		pick = start
	if positional:
		_spatial_next = (pick + 1) % POOL_SIZE
	else:
		_flat_next = (pick + 1) % POOL_SIZE
	var player = players[pick]
	if player.playing:
		player.stop()
	_release_loop(player)
	return player


## Plays stream on a pooled player until stop_loop() is called on the returned id (above 0).
## The stream's loop mode is the caller's to set.
func start_loop(stream: AudioStream, positional: bool, volume_db: float, pos: Vector3) -> int:
	var player = take(positional)
	player.stream = stream
	player.pitch_scale = 1.0
	player.volume_db = volume_db
	if positional:
		player.global_position = pos
	player.play()
	_loop_serial += 1
	_loops[_loop_serial] = player
	return _loop_serial


## Stops a loop and frees its player. Unknown or already ended ids do nothing.
func stop_loop(id: int) -> void:
	if not _loops.has(id):
		return
	var player = _loops[id]
	_loops.erase(id)
	if is_instance_valid(player) and player.playing:
		player.stop()


func is_loop_playing(id: int) -> bool:
	return _loops.has(id) and is_instance_valid(_loops[id]) and _loops[id].playing


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


func _holds_loop(player: Node) -> bool:
	return _loops.values().has(player)


func _release_loop(player: Node) -> void:
	for id in _loops.keys():
		if _loops[id] == player:
			_loops.erase(id)
