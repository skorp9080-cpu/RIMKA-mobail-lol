extends Node2D

const GRID_W: int = 48
const GRID_H: int = 32
const TILE_SIZE: float = 32.0

var camera: Camera2D
var drag_active: bool = false
var drag_start_pos: Vector2 = Vector2.ZERO
var colonists: Array = []

func _ready() -> void:
	_setup_camera()
	_generate_local_map()
	_spawn_colonists()
	_build_top_bar()

func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.position = Vector2(GRID_W * TILE_SIZE * 0.5, GRID_H * TILE_SIZE * 0.5)
	camera.zoom = Vector2(1.15, 1.15)
	add_child(camera)
	camera.make_current()

func _generate_local_map() -> void:
	var tile_info: Dictionary = GameState.selected_tile
	var local_seed: int = GameState.planet_seed + int(tile_info.get("x", 0)) * 131 + int(tile_info.get("y", 0)) * 977
	var rock_density: float = float(tile_info.get("rock_density", 0.22))
	var tree_density: float = float(tile_info.get("tree_density", 0.16))
	var biome: String = str(tile_info.get("biome", "Помірний ліс"))

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = local_seed

	var rock_noise: FastNoiseLite = FastNoiseLite.new()
	rock_noise.seed = local_seed + 55
	rock_noise.frequency = 0.12

	var base_ground: Color = Color(0.20, 0.44, 0.18)
	if biome == "Посушливі скелі":
		base_ground = Color(0.62, 0.52, 0.30)
	elif biome == "Холодна тайга":
		base_ground = Color(0.36, 0.48, 0.44)
	elif biome == "Скелясті гори":
		base_ground = Color(0.28, 0.36, 0.24)

	var center_x: int = GRID_W / 2
	var center_y: int = GRID_H / 2

	for y in range(GRID_H):
		for x in range(GRID_W):
			var rect: ColorRect = ColorRect.new()
			rect.size = Vector2(TILE_SIZE, TILE_SIZE)
			rect.position = Vector2(x * TILE_SIZE, y * TILE_SIZE)
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var dist_center: float = Vector2(x - center_x, y - center_y).length()
			var n_val: float = (rock_noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5

			# Центральна стартова галявина без скель і води
			if dist_center < 5.5:
				rect.color = base_ground.lightened(0.14)
				add_child(rect)
				continue

			# Скелі (гірські породи)
			if n_val > (1.0 - rock_density):
				rect.color = Color(0.36, 0.35, 0.34)
				rect.name = "Rock_%d_%d" % [x, y]
				add_child(rect)

				# Додаємо об'ємну верхівку скелі
				var ridge: ColorRect = ColorRect.new()
				ridge.size = Vector2(TILE_SIZE - 6.0, TILE_SIZE - 8.0)
				ridge.position = Vector2(x * TILE_SIZE + 3.0, y * TILE_SIZE + 2.0)
				ridge.color = Color(0.50, 0.49, 0.47)
				ridge.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(ridge)
			elif n_val < 0.14:
				# Вода
				rect.color = Color(0.14, 0.38, 0.72)
				add_child(rect)
			else:
				rect.color = base_ground
				add_child(rect)

				# Дерева на вільній землі
				if rng.randf() < tree_density:
					var tree: ColorRect = ColorRect.new()
					tree.size = Vector2(18, 18)
					tree.position = Vector2(x * TILE_SIZE + 7.0, y * TILE_SIZE + 7.0)
					tree.color = Color(0.10, 0.28, 0.10)
					tree.mouse_filter = Control.MOUSE_FILTER_IGNORE
					add_child(tree)

func _spawn_colonists() -> void:
	var names: Array = ["Олекса", "Соломія", "Богдан"]
	var center: Vector2 = Vector2(GRID_W * TILE_SIZE * 0.5, GRID_H * TILE_SIZE * 0.5)
	var saved_pawns: Array = GameState.loaded_save_data.get("colonists", []) if GameState.is_loading_save else []

	for i in range(names.size()):
		var pawn: Node2D = Node2D.new()
		pawn.name = str(names[i])
		pawn.add_to_group("colonists")

		if i < saved_pawns.size() and saved_pawns[i] is Dictionary:
			pawn.position = Vector2(float(saved_pawns[i]["x"]), float(saved_pawns[i]["y"]))
		else:
			pawn.position = center + Vector2((i - 1) * 56.0, 0.0)

		var body: ColorRect = ColorRect.new()
		body.size = Vector2(18, 22)
		body.position = Vector2(-9, -6)
		body.color = Color(0.82, 0.86, 0.92)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pawn.add_child(body)

		var head: ColorRect = ColorRect.new()
		head.size = Vector2(14, 14)
		head.position = Vector2(-7, -18)
		head.color = Color(0.95, 0.78, 0.65)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pawn.add_child(head)

		var lbl: Label = Label.new()
		lbl.text = pawn.name
		lbl.position = Vector2(-28, -40)
		lbl.add_theme_font_size_override("font_size", 14)
		pawn.add_child(lbl)

		add_child(pawn)
		colonists.append(pawn)

func _build_top_bar() -> void:
	var hud: CanvasLayer = CanvasLayer.new()
	hud.layer = 12
	add_child(hud)

	var bar: PanelContainer = PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.custom_minimum_size = Vector2(0, 48)
	hud.add_child(bar)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	bar.add_child(hbox)

	var biome_lbl: Label = Label.new()
	biome_lbl.text = "  Локація: %s | День 1" % str(GameState.selected_tile.get("biome", "Помірний ліс"))
	biome_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	biome_lbl.add_theme_font_size_override("font_size", 17)
	hbox.add_child(biome_lbl)

	var btn_save: Button = Button.new()
	btn_save.text = "Зберегти"
	btn_save.custom_minimum_size = Vector2(120, 40)
	btn_save.pressed.connect(func(): _save_current_colony(biome_lbl))
	hbox.add_child(btn_save)

	var btn_menu: Button = Button.new()
	btn_menu.text = "Меню"
	btn_menu.custom_minimum_size = Vector2(100, 40)
	btn_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	hbox.add_child(btn_menu)

func _save_current_colony(status_lbl: Label) -> void:
	var pawn_list: Array = []
	for p in colonists:
		if is_instance_valid(p):
			pawn_list.append({"name": p.name, "x": p.position.x, "y": p.position.y})
	var ok: bool = GameState.save_game({"colonists": pawn_list})
	status_lbl.text = "  Гру збережено!" if ok else "  Помилка збереження"

func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		var spd: float = float(GameState.settings.get("camera_speed", 1.0))
		camera.position -= event.relative * spd / camera.zoom.x
