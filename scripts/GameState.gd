extends Node

const SAVE_PATH: String = "user://colony_save.json"

var planet_seed: int = 1337
var selected_tile: Vector2i = Vector2i(20, 12)
var selected_biome: String = "Помірний ліс"
var selected_temp: float = 18.5
var selected_rainfall: float = 1100.0
var selected_hills: String = "Пагорби"
var storyteller: String = "Ренді Рандом"

var is_loading_save: bool = false
var loaded_save_data: Dictionary = {}

var current_day: int = 1
var game_time_hours: float = 8.0
var time_speed: float = 1.0
var active_weather_event: String = ""
var ambient_temp: int = 18

var unlocked_techs: Array = ["basic_survival"]
var active_research_id: String = "electricity"
var research_progress: float = 0.0

var settings: Dictionary = {
	"autosave": true,
	"camera_speed": 1.0
}

var starting_colonists: Array = [
	{
		"name": "Олекса",
		"trait": "Оптиміст",
		"hair_color": Color(0.22, 0.15, 0.10),
		"shirt_color": Color(0.26, 0.48, 0.72),
		"priorities": {"fire": 1, "doctor": 2, "cook": 3, "construct": 1, "mine": 2, "grow": 2, "haul": 3}
	},
	{
		"name": "Соломія",
		"trait": "Трудоголік",
		"hair_color": Color(0.68, 0.34, 0.16),
		"shirt_color": Color(0.74, 0.32, 0.38),
		"priorities": {"fire": 1, "doctor": 1, "cook": 1, "construct": 3, "mine": 4, "grow": 2, "haul": 2}
	},
	{
		"name": "Богдан",
		"trait": "Залізна воля",
		"hair_color": Color(0.12, 0.12, 0.14),
		"shirt_color": Color(0.32, 0.62, 0.38),
		"priorities": {"fire": 1, "doctor": 3, "cook": 4, "construct": 2, "mine": 1, "grow": 1, "haul": 2}
	}
]

func _ready() -> void:
	randomize()
	planet_seed = randi() % 99999

func reset_for_new_colony() -> void:
	is_loading_save = false
	loaded_save_data = {}
	current_day = 1
	game_time_hours = 8.0
	time_speed = 1.0
	active_weather_event = ""
	ambient_temp = int(round(selected_temp))
	unlocked_techs = ["basic_survival"]
	active_research_id = "electricity"
	research_progress = 0.0

func has_tech(tech_id: String) -> bool:
	return unlocked_techs.has(tech_id)

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)

func save_game(extra_data: Dictionary = {}) -> bool:
	var hud: Node = get_tree().root.get_node_or_null("MobileHUD")
	if hud == null and get_tree().current_scene != null:
		hud = get_tree().current_scene.get_node_or_null("MobileHUD")

	var hud_state: Dictionary = {}
	if hud != null and hud.has_method("export_save_state"):
		var exported: Variant = hud.call("export_save_state")
		if exported is Dictionary:
			hud_state = exported

	var payload: Dictionary = {
		"planet_seed": planet_seed,
		"selected_tile": {"x": selected_tile.x, "y": selected_tile.y},
		"selected_biome": selected_biome,
		"selected_temp": selected_temp,
		"selected_rainfall": selected_rainfall,
		"selected_hills": selected_hills,
		"storyteller": storyteller,
		"current_day": current_day,
		"game_time_hours": game_time_hours,
		"unlocked_techs": unlocked_techs.duplicate(),
		"active_research_id": active_research_id,
		"research_progress": research_progress,
		"hud_state": hud_state
	}

	for k in extra_data.keys():
		payload[k] = extra_data[k]

	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	return true

func load_game() -> bool:
	if not has_save():
		return false
	var file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return false

	var data: Dictionary = parsed
	loaded_save_data = data
	is_loading_save = true

	planet_seed = int(data.get("planet_seed", planet_seed))
	if data.get("selected_tile") is Dictionary:
		var st: Dictionary = data["selected_tile"]
		selected_tile = Vector2i(int(st.get("x", selected_tile.x)), int(st.get("y", selected_tile.y)))
	selected_biome = str(data.get("selected_biome", selected_biome))
	selected_temp = float(data.get("selected_temp", selected_temp))
	selected_rainfall = float(data.get("selected_rainfall", selected_rainfall))
	selected_hills = str(data.get("selected_hills", selected_hills))
	storyteller = str(data.get("storyteller", storyteller))
	current_day = int(data.get("current_day", 1))
	game_time_hours = float(data.get("game_time_hours", 8.0))
	if data.get("unlocked_techs") is Array:
		unlocked_techs = data["unlocked_techs"]
	active_research_id = str(data.get("active_research_id", ""))
	research_progress = float(data.get("research_progress", 0.0))
	return true

func get_biome_at(x: int, y: int, seed_val: int) -> Dictionary:
	var n_temp: float = sin(float(y) * 0.14 + float(seed_val % 100) * 0.1) * 0.5 + 0.5
	var n_elev: float = sin(float(x) * 0.22 + float(y) * 0.18 + float(seed_val % 50)) * 0.5 + 0.5
	var n_rain: float = cos(float(x) * 0.15 - float(y) * 0.12 + float(seed_val % 77)) * 0.5 + 0.5

	var temp: float = lerpf(-22.0, 38.0, n_temp)
	var rain: float = lerpf(150.0, 2200.0, n_rain)
	var biome: String = "Помірний ліс"
	var color: Color = Color(0.26, 0.58, 0.25)

	if n_elev < 0.26:
		biome = "Океан"
		color = Color(0.14, 0.34, 0.58)
	elif temp < -4.0:
		biome = "Тундра / Льодовик"
		color = Color(0.84, 0.90, 0.96)
	elif temp > 26.0 and rain < 800.0:
		biome = "Пустеля"
		color = Color(0.82, 0.72, 0.42)
	elif n_elev > 0.78:
		biome = "Гори"
		color = Color(0.46, 0.46, 0.50)

	var hills: String = "Рівнина"
	if n_elev > 0.75:
		hills = "Гірський хребет"
	elif n_elev > 0.58:
		hills = "Пагорби"

	return {
		"biome": biome,
		"color": color,
		"temp": snappedf(temp, 0.1),
		"rain": snappedf(rain, 10.0),
		"hills": hills,
		"is_water": n_elev < 0.26
	}
