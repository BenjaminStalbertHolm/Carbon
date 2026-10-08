extends RefCounted
## Wall clock (spec 8.10): a 0.22 m disc on the north wall facing south, with
## hour and minute hands as thin boxes pivoting at the centre. Hands are named
## ClockHourHand and ClockMinuteHand and are direct children of the hall root.

const Geo := preload("res://scripts/world/geometry.gd")
const ClockMath := preload("res://scripts/logic/clock_math.gd")

const CENTRE := Vector3(0.0, 2.55, -5.88)
const RADIUS := 0.22
const FACE_SIZE := 128
const COL_FACE := Color("#D8D2BE")
const COL_INK := Color("#1C1B19")


## Builds the face and both hands under parent. Hands are set to time_hhmm ("08:58" at day start).
static func build(parent: Node3D, time_hhmm: String = "08:58") -> Node3D:
	var clock := Geo.group(parent, "Clock", CENTRE)
	var face := Geo.disc(RADIUS, 16, face_texture(), Geo.WHITE, "Face")
	Geo.add(clock, face)
	# Backing body from the wall face (z = -6.0) to just behind the face, so the 0.12 m gap is filled (QUESTION-18).
	Geo.add(clock, Geo.cylinder(RADIUS, 0.114, 8, COL_FACE, "Backing", true, true), Vector3(0, 0, -0.063), Vector3(90, 0, 0))
	var angles := ClockMath.hand_angles(time_hhmm)
	# Degrees clockwise from 12 o'clock; a negative Z rotation turns clockwise as seen from the room.
	var hour := Geo.group(parent, "ClockHourHand", CENTRE, Vector3(0, 0, -float(angles["hour"])))
	Geo.add(hour, Geo.solid(Vector3(0.014, 0.12, 0.006), COL_INK, "Hand"), Vector3(0, 0.06, 0.004))
	var minute := Geo.group(parent, "ClockMinuteHand", CENTRE, Vector3(0, 0, -float(angles["minute"])))
	Geo.add(minute, Geo.solid(Vector3(0.008, 0.18, 0.006), COL_INK, "Hand"), Vector3(0, 0.09, 0.004))
	return clock


## 128 x 128 face: off-white disc and 12 tick marks, generated in code (spec 5.5).
static func face_texture() -> ImageTexture:
	var img := Image.create(FACE_SIZE, FACE_SIZE, false, Image.FORMAT_RGB8)
	img.fill(Color.BLACK)
	var mid := float(FACE_SIZE) * 0.5
	var r := mid - 0.5
	for y in FACE_SIZE:
		for x in FACE_SIZE:
			var d := Vector2(float(x) + 0.5 - mid, float(y) + 0.5 - mid).length()
			if d <= r:
				img.set_pixel(x, y, COL_FACE)
	for k in 12:
		var a := TAU * float(k) / 12.0
		var dir := Vector2(sin(a), -cos(a))
		var s := r * 0.80
		while s <= r * 0.92:
			var p := Vector2(mid, mid) + dir * s
			_ink(img, int(p.x), int(p.y))
			_ink(img, int(p.x) + 1, int(p.y))
			s += 0.5
	return ImageTexture.create_from_image(img)


static func _ink(img: Image, x: int, y: int) -> void:
	if x >= 0 and y >= 0 and x < FACE_SIZE and y < FACE_SIZE:
		img.set_pixel(x, y, COL_INK)
