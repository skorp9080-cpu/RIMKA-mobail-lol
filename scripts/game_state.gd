extends Node

const SAVE_PATH: String = "user://rimka_save.json"

var planet_seed: int = 12345
var selected_tile: Dictionary = {
	"x": 12,
	"y": 8,
	"biome": "Помірний ліс",
	"rock_density": 0.22,
	"tree_density": 0.18,
	"fertility": 1.0,
	"temp": 18
}

var settings: Dictionary = {
	"camera_speed": 1.0,
	"ui_scale": 1.0,
	"autosave": true
}

var loaded_save_data: Dictionary = {}
var is_loading_save: bool = false

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game(data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	data["planet_seed"] = planet_seed
	data["selected_tile"] = selected_tile
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

func load_game() -> bool:
	if not has_save():
		return false
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var raw: String = file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(raw)
	if parsed is Dictionary:
		loaded_save_data = parsed
		if parsed.has("planet_seed"):
			planet_seed = int(parsed["planet_seed"])
		if parsed.has("selected_tile"):
			selected_tile = parsed["selected_tile"]
		is_loading_save = true
		return true
	return false
