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

var game_time_hours: float = 8.0
var current_day: int = 1
var time_speed: float = 1.0
var ambient_temp: int = 19
var active_weather_event: String = ""

var unlocked_techs: Array = ["basic_survival"]
var active_research_id: String = "electricity"
var research_progress: float = 0.0

var loaded_save_data: Dictionary = {}
var is_loading_save: bool = false

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func has_tech(tech_id: String) -> bool:
	return unlocked_techs.has(tech_id)

func save_game(extra_data: Dictionary) -> bool:
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	var payload: Dictionary = extra_data.duplicate(true)
	payload["planet_seed"] = planet_seed
	payload["selected_tile"] = selected_tile
	payload["current_day"] = current_day
	payload["game_time_hours"] = game_time_hours
	payload["unlocked_techs"] = unlocked_techs
	payload["active_research_id"] = active_research_id
	payload["research_progress"] = research_progress

	var hud: Node = get_tree().root.get_node_or_null("MobileHUD")
	if hud == null and get_tree().current_scene != null:
		hud = get_tree().current_scene.get_node_or_null("MobileHUD")
	if hud != null and hud.has_method("export_save_state"):
		payload["hud_state"] = hud.call("export_save_state")

	file.store_string(JSON.stringify(payload, "\t"))
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
		var dict_data: Dictionary = parsed as Dictionary
		loaded_save_data = dict_data
		if dict_data.has("planet_seed"):
			planet_seed = int(dict_data["planet_seed"])
		if dict_data.has("selected_tile"):
			selected_tile = dict_data["selected_tile"]
		current_day = int(dict_data.get("current_day", 1))
		game_time_hours = float(dict_data.get("game_time_hours", 8.0))
		if dict_data.has("unlocked_techs") and dict_data["unlocked_techs"] is Array:
			unlocked_techs = dict_data["unlocked_techs"]
		active_research_id = str(dict_data.get("active_research_id", "electricity"))
		research_progress = float(dict_data.get("research_progress", 0.0))
		is_loading_save = true
		return true
	return false
