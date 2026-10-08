extends Node
## Credits (spec 15.4): a black screen. Each line of data/credits.json is typed
## centred (Special Elite 32 px, #C8C2AE, 90 ms per character, key_clack at -30 dB),
## held 1.5 s, then cleared. After the last line: hold 3.0 s, delete the save, and
## finish. The caller then returns to the title (spec 16.2).
##
## Coroutine: await credits.run(). There is no skip (none is specified).

const Content := preload("res://scripts/logic/content.gd")
const BlackScreen := preload("res://scripts/ui/black_screen.gd")

const FONT_SIZE := 32
const MS_PER_CHAR := 90
const HOLD_LINE_S := 1.5
const HOLD_END_S := 3.0

signal finished


func run() -> void:
	var screen: Node = BlackScreen.new()
	add_child(screen)
	screen.set_shade(1.0)
	for line in Content.credits().lines:
		await screen.type_lines([String(line)], FONT_SIZE, MS_PER_CHAR, true)
		await screen.hold(HOLD_LINE_S)
		screen.clear_text()
	await screen.hold(HOLD_END_S)
	var save = Engine.get_main_loop().root.get_node_or_null("SaveSystem")
	if save != null:
		save.delete_save()
	screen.queue_free()
	finished.emit()
