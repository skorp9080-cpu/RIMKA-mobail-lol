extends Node

var planet_seed: int = 1337
var selected_tile: Vector2i = Vector2i(20, 12)
var selected_biome: String = "Помірний ліс"
var selected_temp: float = 18.5
var selected_rainfall: float = 1100.0
var selected_hills: String = "Пагорби"
var storyteller: String = "Ренді Рандом"

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
