extends RefCounted
## KeyClack: the non-positional key_clack of black-screen typing (spec 11.4). A
## random variant of assets/audio/key_clack_1..4.wav, at -30 dB additional gain
## (spec 11.1 "playback levels ... are additional gain").
## TODO(M9): AudioDirector has no play method yet. Route this through it when M9
## lands; until then the sound is played here.

const CLACKS := [
	preload("res://assets/audio/key_clack_1.wav"),
	preload("res://assets/audio/key_clack_2.wav"),
	preload("res://assets/audio/key_clack_3.wav"),
	preload("res://assets/audio/key_clack_4.wav"),
]
const VOLUME_DB := -30.0


## Plays one clack under host, which must be in the tree. The player frees itself.
static func play(host: Node) -> void:
	if host == null or not host.is_inside_tree():
		return
	var player := AudioStreamPlayer.new()
	player.stream = CLACKS[randi() % CLACKS.size()]
	player.volume_db = VOLUME_DB
	host.add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
