extends Node
## Dev-only screenshot harness for the front end (spec 16.1 to 16.3). Excluded from
## export (tests/*). Run under a virtual display, with the shot directory as an
## argument after "--":
##   xvfb-run -a -s "-screen 0 1280x1024x24" godot --path . res://tests/ui/ui_shots.tscn -- --shot=<dir>
## Writes PNGs into <dir>: content_note, title_nosave, title_save, title_erase,
## settings, folder, folder_quit. Uses its own save and settings files.

const ContentNote := preload("res://scripts/ui/content_note.gd")
const TitleScreen := preload("res://scripts/ui/title_screen.gd")
const MENU_FOLDER := preload("res://scenes/ui/menu_folder.tscn")

const TEST_SAVE := "user://ui_shots_save.json"
const TEST_SETTINGS := "user://ui_shots_settings.cfg"

var _dir := ""


func _ready() -> void:
	_dir = _shot_dir()
	DirAccess.make_dir_recursive_absolute(_dir)
	_run()


func _run() -> void:
	var save = get_node("/root/SaveSystem")
	var gs = get_node("/root/GameState")
	save.save_path = TEST_SAVE
	save.settings_path = TEST_SETTINGS
	save.load_settings()

	# Content note: typed in full, before the press that proceeds.
	var note = ContentNote.new()
	add_child(note)
	note.run()
	await note.typed
	await _shot("content_note")
	note.queue_free()
	await get_tree().process_frame

	# Title without a save: no CONTINUE line.
	save.delete_save()
	var title = TitleScreen.new()
	add_child(title)
	title.show_title()
	await _shot("title_nosave")

	# Title with a save on Wednesday: CONTINUE — WEDNESDAY.
	gs.new_game(412)
	gs.day = 3
	save.save_game()
	title.show_title()
	await _shot("title_save")

	# BEGIN with a save: erase prompt with YES / NO, then NO goes back.
	title.choose(0)
	await _shot("title_erase")
	title.choose(1)

	# SETTINGS from the title.
	title.show_title()
	title.choose(2)
	await _shot("settings")
	title.hide_title()

	# Menu folder over the scene (the screen behind is black here).
	var folder = MENU_FOLDER.instantiate()
	add_child(folder)
	folder.open()
	await _shot("folder")
	folder.choose(2)
	await _shot("folder_quit")
	folder.close()

	print("SHOTS DONE in %s" % _dir)
	get_tree().quit(0)


func _shot(shot_name: String) -> void:
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var path := _dir.path_join(shot_name + ".png")
	image.save_png(path)
	print("SHOT %s %dx%d" % [path, image.get_width(), image.get_height()])


func _shot_dir() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			return arg.substr(7)
	return OS.get_user_data_dir().path_join("ui_shots")
