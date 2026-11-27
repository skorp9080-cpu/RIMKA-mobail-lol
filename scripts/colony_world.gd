extends Node2D

const GRID_W: int = 80
const GRID_H: int = 56
const TILE_SIZE: float = 32.0
const TEX_SIZE: int = 128

var camera: Camera2D
var day_night_modulate: CanvasModulate
var top_status_lbl: Label
var speed_buttons: Dictionary = {}
var colonists: Array = []
var raiders: Array = []
var nature_textures: Dictionary = {}
var event_timer: float = 42.0

const TRAITS_POOL: PackedStringArray = PackedStringArray(["Оптиміст", "Працьовитий", "Стрілець", "Нічна сова", "Песиміст"])
const EXTRA_NAMES: PackedStringArray = PackedStringArray(["Тарас", "Дарина", "Мирослав", "Зоряна", "Іван", "Квітка"])

func _ready() -> void:
	if not GameState.is_loading_save:
		GameState.current_day = 1
		GameState.game_time_hours = 8.0
		GameState.unlocked_techs = ["basic_survival"]
		GameState.active_research_id = "electricity"
		GameState.research_progress = 0.0
	GameState.time_speed = 1.0
	GameState.active_weather_event = ""

	_generate_nature_textures()
	_setup_camera()
	_setup_day_night()
	_generate_local_map()
	_spawn_initial_colonists()
	_build_top_bar()
	_ensure_mobile_hud()

func _ensure_mobile_hud() -> void:
	var hud: Node = get_tree().root.get_node_or_null("MobileHUD")
	if hud == null:
		var hud_script: GDScript = load("res://scripts/mobile_hud_controller.gd") as GDScript
		if hud_script != null:
			hud = hud_script.new() as Node2D
			hud.name = "MobileHUD"
			add_child(hud)
	if hud != null and GameState.is_loading_save and hud.has_method("import_save_state"):
		var hud_state: Dictionary = GameState.loaded_save_data.get("hud_state", {})
		hud.call("import_save_state", hud_state)

func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.position = Vector2(float(GRID_W) * TILE_SIZE * 0.5, float(GRID_H) * TILE_SIZE * 0.5)
	camera.zoom = Vector2(1.05, 1.05)
	add_child(camera)
	camera.make_current()

func _setup_day_night() -> void:
	day_night_modulate = CanvasModulate.new()
	day_night_modulate.color = Color.WHITE
	add_child(day_night_modulate)

func _process(delta: float) -> void:
	var sim_delta: float = delta * GameState.time_speed
	if sim_delta > 0.0:
		GameState.game_time_hours += sim_delta * 0.125
		if GameState.game_time_hours >= 24.0:
			GameState.game_time_hours -= 24.0
			GameState.current_day += 1
			if bool(GameState.settings.get("autosave", true)):
				_save_current_colony(false)

		event_timer -= sim_delta
		if event_timer <= 0.0:
			event_timer = randf_range(55.0, 95.0)
			_trigger_storyteller_event()

		_process_raiders(sim_delta)

	_update_temperature()
	_update_lighting()
	_update_top_label()

func _update_temperature() -> void:
	var base_t: int = int(GameState.selected_tile.get("temp", 18))
	var day_offset: int = -5 if (GameState.game_time_hours >= 22.0 or GameState.game_time_hours < 6.0) else 3
	var weather_offset: int = 0
	if GameState.active_weather_event == "Теплова хвиля":
		weather_offset = 16
	elif GameState.active_weather_event == "Похолодання":
		weather_offset = -18
	GameState.ambient_temp = base_t + day_offset + weather_offset

func _update_lighting() -> void:
	if day_night_modulate == null:
		return
	var h: float = GameState.game_time_hours
	var target_col: Color = Color.WHITE
	if h >= 21.0 or h < 5.0:
		target_col = Color(0.42, 0.48, 0.68)
	elif h >= 18.0 and h < 21.0:
		var t: float = (h - 18.0) / 3.0
		target_col = Color.WHITE.lerp(Color(0.42, 0.48, 0.68), t)
	elif h >= 5.0 and h < 8.0:
		var t2: float = (h - 5.0) / 3.0
		target_col = Color(0.42, 0.48, 0.68).lerp(Color.WHITE, t2)

	if GameState.active_weather_event == "Сонячний спалах":
		target_col = target_col.lerp(Color(1.0, 0.78, 0.55), 0.35)
	day_night_modulate.color = target_col

func _update_top_label() -> void:
	if top_status_lbl == null:
		return
	var h_int: int = int(floor(GameState.game_time_hours))
	var m_int: int = int(floor((GameState.game_time_hours - float(h_int)) * 60.0))
	var ev_txt: String = " | %s" % GameState.active_weather_event if GameState.active_weather_event != "" else ""
	top_status_lbl.text = " Д.%d %02d:%02d | %+d°C%s" % [GameState.current_day, h_int, m_int, GameState.ambient_temp, ev_txt]

func _trigger_storyteller_event() -> void:
	var hud: Node = _get_hud()
	var roll: int = randi() % 5
	match roll:
		0:
			# Набіг рейдерів
			var count: int = clampi(1 + GameState.current_day / 2, 1, 4)
			_spawn_raid(count)
			if hud != null and hud.has_method("notify_event"):
				hud.call("notify_event", "УВАГА: Набіг рейдерів (%d ворогів)!" % count)
		1:
			# Скидання вантажних капсул
			if hud != null and hud.has_method("grant_drop_pod"):
				hud.call("grant_drop_pod")
		2:
			# Новий колоніст просить притулку
			if colonists.size() < 8:
				var new_name: String = EXTRA_NAMES[randi() % EXTRA_NAMES.size()]
				var center: Vector2 = Vector2(float(GRID_W) * TILE_SIZE * 0.5, float(GRID_H) * TILE_SIZE * 0.5)
				_create_colonist_pawn(new_name, center + Vector2(randf_range(-180, 180), randf_range(-140, 140)), {})
				if hud != null and hud.has_method("notify_event"):
					hud.call("notify_event", "Подія: До колонії приєднався %s!" % new_name)
		3:
			# Зміна погоди / Сонячний спалах
			var events: PackedStringArray = PackedStringArray(["Теплова хвиля", "Похолодання", "Сонячний спалах", ""])
			GameState.active_weather_event = events[randi() % events.size()]
			if hud != null and hud.has_method("notify_event"):
				var msg: String = "Подія: %s!" % GameState.active_weather_event if GameState.active_weather_event != "" else "Погода стабілізувалася"
				hud.call("notify_event", msg)
		4:
			# Торговий караван
			if hud != null and hud.has_method("enable_trader"):
				hud.call("enable_trader")

func _spawn_raid(count: int) -> void:
	var edge_x: float = 64.0 if (randi() % 2 == 0) else (float(GRID_W) * TILE_SIZE - 64.0)
	for i: int in range(count):
		var r: Node2D = Node2D.new()
		r.name = "Raider_%d" % i
		r.add_to_group("raiders")
		r.position = Vector2(edge_x, float(GRID_H) * TILE_SIZE * 0.5 + float(i - 1) * 42.0)
		r.set_meta("hp", 100.0)
		r.set_meta("attack_cd", 0.0)
		r.z_index = 6

		var body: ColorRect = ColorRect.new()
		body.size = Vector2(18, 22)
		body.position = Vector2(-9, -6)
		body.color = Color(0.85, 0.16, 0.16)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_child(body)

		var head: ColorRect = ColorRect.new()
		head.size = Vector2(14, 14)
		head.position = Vector2(-7, -18)
		head.color = Color(0.30, 0.25, 0.25)
		head.mouse_filter = Control.MOUSE_FILTER_IGNORE
		r.add_child(head)

		var lbl: Label = Label.new()
		lbl.name = "RaiderLabel"
		lbl.text = "Рейдер 100%"
		lbl.position = Vector2(-34, -38)
		lbl.modulate = Color(1.0, 0.4, 0.4)
		lbl.add_theme_font_size_override("font_size", 12)
		r.add_child(lbl)

		add_child(r)
		raiders.append(r)

func _process_raiders(sim_delta: float) -> void:
	var dead_raiders: Array = []
	for i: int in range(raiders.size()):
		var r: Node2D = raiders[i] as Node2D
		if r == null or not is_instance_valid(r):
			dead_raiders.append(r)
			continue
		var hp: float = float(r.get_meta("hp", 100.0))
		if hp <= 0.0:
			dead_raiders.append(r)
			continue

		var target_pawn: Node2D = _find_nearest_colonist(r.global_position)
		if target_pawn == null:
			continue

		var dist: float = r.global_position.distance_to(target_pawn.global_position)
		if dist > 42.0:
			r.global_position += (target_pawn.global_position - r.global_position).normalized() * 78.0 * sim_delta
		else:
			var cd: float = float(r.get_meta("attack_cd", 0.0)) - sim_delta
			if cd <= 0.0:
				cd = 1.4
				var p_hp: float = maxf(10.0, float(target_pawn.get_meta("hp", 100.0)) - 12.0)
				target_pawn.set_meta("hp", p_hp)
				# Колоніст відповідає ударом/пострілом
				var combat_skill: int = int(target_pawn.get_meta("skill_combat", 3))
				hp -= (14.0 + float(combat_skill) * 2.5)
				r.set_meta("hp", hp)
				target_pawn.set_meta("skill_combat", mini(20, combat_skill + 1))
			r.set_meta("attack_cd", cd)

		var lbl: Label = r.get_node_or_null("RaiderLabel") as Label
		if lbl != null:
			lbl.text = "Рейдер %d%%" % int(maxf(0.0, hp))

	for i: int in range(dead_raiders.size()):
		var dr: Node2D = dead_raiders[i] as Node2D
		raiders.erase(dr)
		if dr != null and is_instance_valid(dr):
			dr.queue_free()
			var hud: Node = _get_hud()
			if hud != null and hud.has_method("reward_raid_victory"):
				hud.call("reward_raid_victory")

func _find_nearest_colonist(pos: Vector2) -> Node2D:
	var best: Node2D = null
	var best_d: float = 999999.0
	for i: int in range(colonists.size()):
		var p: Node2D = colonists[i] as Node2D
		if p != null and is_instance_valid(p):
			var d: float = p.global_position.distance_to(pos)
			if d < best_d:
				best_d = d
				best = p
	return best

func _get_hud() -> Node:
	var hud: Node = get_tree().root.get_node_or_null("MobileHUD")
	if hud == null:
		hud = get_node_or_null("MobileHUD")
	return hud

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
	rock_noise.frequency = 0.085

	var base_ground: Color = Color(0.20, 0.44, 0.18)
	if biome == "Посушливі скелі":
		base_ground = Color(0.62, 0.52, 0.30)
	elif biome == "Холодна тайга":
		base_ground = Color(0.36, 0.48, 0.44)
	elif biome == "Скелясті гори":
		base_ground = Color(0.28, 0.36, 0.24)

	var center_x: int = GRID_W / 2
	var center_y: int = GRID_H / 2

	for y: int in range(GRID_H):
		for x: int in range(GRID_W):
			var rect: ColorRect = ColorRect.new()
			rect.size = Vector2(TILE_SIZE, TILE_SIZE)
			rect.position = Vector2(float(x) * TILE_SIZE, float(y) * TILE_SIZE)
			rect.mouse_filter = Control.MOUSE_FILTER_IGNORE

			var dist_center: float = Vector2(x - center_x, y - center_y).length()
			var n_val: float = (rock_noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5

			if dist_center < 6.5:
				rect.color = base_ground.lightened(0.14)
				add_child(rect)
				continue

			if n_val > (1.0 - rock_density):
				rect.color = Color(0.36, 0.35, 0.34)
				rect.name = "Rock_%d_%d" % [x, y]
				add_child(rect)

				var ridge: ColorRect = ColorRect.new()
				ridge.size = Vector2(TILE_SIZE - 6.0, TILE_SIZE - 8.0)
				ridge.position = Vector2(float(x) * TILE_SIZE + 3.0, float(y) * TILE_SIZE + 2.0)
				ridge.color = Color(0.50, 0.49, 0.47)
				ridge.mouse_filter = Control.MOUSE_FILTER_IGNORE
				add_child(ridge)
			elif n_val < 0.13:
				rect.color = Color(0.14, 0.38, 0.72)
				add_child(rect)
			else:
				rect.color = base_ground
				add_child(rect)

				var roll: float = rng.randf()
				if roll < tree_density:
					_spawn_nature_sprite("Tree_%d_%d" % [x, y], "tree", x, y)
				elif roll < tree_density + 0.032:
					_spawn_nature_sprite("Berry_%d_%d" % [x, y], "berry", x, y)
				elif roll < tree_density + 0.056:
					_spawn_nature_sprite("Mushroom_%d_%d" % [x, y], "mushroom", x, y)

func _spawn_nature_sprite(node_name: String, tex_key: String, gx: int, gy: int) -> void:
	var spr: TextureRect = TextureRect.new()
	spr.name = node_name
	spr.texture = nature_textures.get(tex_key) as Texture2D
	spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spr.stretch_mode = TextureRect.STRETCH_SCALE
	spr.size = Vector2(TILE_SIZE, TILE_SIZE)
	spr.position = Vector2(float(gx) * TILE_SIZE, float(gy) * TILE_SIZE)
	spr.z_index = 1
	spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(spr)

func _spawn_initial_colonists() -> void:
	var center: Vector2 = Vector2(float(GRID_W) * TILE_SIZE * 0.5, float(GRID_H) * TILE_SIZE * 0.5)
	var saved_pawns: Array = GameState.loaded_save_data.get("colonists", []) if GameState.is_loading_save else []

	if not saved_pawns.is_empty():
		for i: int in range(saved_pawns.size()):
			if saved_pawns[i] is Dictionary:
				var p_dict: Dictionary = saved_pawns[i]
				_create_colonist_pawn(str(p_dict.get("name", "Колоніст")), Vector2(float(p_dict["x"]), float(p_dict["y"])), p_dict)
		return

	var names: PackedStringArray = PackedStringArray(["Олекса", "Соломія", "Богдан"])
	for i: int in range(names.size()):
		_create_colonist_pawn(names[i], center + Vector2(float(i - 1) * 56.0, 0.0), {})

func _create_colonist_pawn(p_name: String, pos: Vector2, saved_dict: Dictionary) -> void:
	var pawn: Node2D = Node2D.new()
	pawn.name = p_name
	pawn.add_to_group("colonists")
	pawn.position = pos
	pawn.z_index = 5

	var trait_str: String = str(saved_dict.get("trait", TRAITS_POOL[randi() % TRAITS_POOL.size()]))
	pawn.set_meta("trait", trait_str)
	pawn.set_meta("hp", float(saved_dict.get("hp", 100.0)))
	pawn.set_meta("mood", float(saved_dict.get("mood", 85.0)))
	pawn.set_meta("hunger", float(saved_dict.get("hunger", 100.0)))
	pawn.set_meta("energy", float(saved_dict.get("energy", 100.0)))
	pawn.set_meta("skill_work", int(saved_dict.get("skill_work", randi_range(3, 7))))
	pawn.set_meta("skill_combat", int(saved_dict.get("skill_combat", randi_range(2, 6))))

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
	lbl.name = "NameLabel"
	lbl.text = p_name
	lbl.position = Vector2(-42, -52)
	lbl.add_theme_font_size_override("font_size", 12)
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
	hbox.add_theme_constant_override("separation", 4)
	bar.add_child(hbox)

	top_status_lbl = Label.new()
	top_status_lbl.text = " Д.1 08:00 | +18°C"
	top_status_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_status_lbl.add_theme_font_size_override("font_size", 14)
	hbox.add_child(top_status_lbl)

	var btn_zoom_out: Button = Button.new()
	btn_zoom_out.text = "-"
	btn_zoom_out.custom_minimum_size = Vector2(36, 38)
	btn_zoom_out.pressed.connect(func(): _change_zoom(-0.2))
	hbox.add_child(btn_zoom_out)

	var btn_zoom_in: Button = Button.new()
	btn_zoom_in.text = "+"
	btn_zoom_in.custom_minimum_size = Vector2(36, 38)
	btn_zoom_in.pressed.connect(func(): _change_zoom(0.2))
	hbox.add_child(btn_zoom_in)

	var speeds: Array = [
		{"val": 0.0, "txt": "||"},
		{"val": 1.0, "txt": "1x"},
		{"val": 2.0, "txt": "2x"},
		{"val": 3.0, "txt": "3x"}
	]
	for i: int in range(speeds.size()):
		var sp: Dictionary = speeds[i]
		var s_val: float = float(sp["val"])
		var btn_s: Button = Button.new()
		btn_s.text = str(sp["txt"])
		btn_s.custom_minimum_size = Vector2(38, 38)
		btn_s.pressed.connect(func(): _set_speed(s_val))
		hbox.add_child(btn_s)
		speed_buttons[s_val] = btn_s

	_set_speed(1.0)

	var btn_save: Button = Button.new()
	btn_save.text = "Зберегти"
	btn_save.custom_minimum_size = Vector2(88, 38)
	btn_save.pressed.connect(func(): _save_current_colony(true))
	hbox.add_child(btn_save)

	var btn_menu: Button = Button.new()
	btn_menu.text = "Меню"
	btn_menu.custom_minimum_size = Vector2(72, 38)
	btn_menu.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	hbox.add_child(btn_menu)

func _change_zoom(delta_z: float) -> void:
	if camera == null:
		return
	var next_z: float = clampf(camera.zoom.x + delta_z, 0.55, 2.2)
	camera.zoom = Vector2(next_z, next_z)

func _set_speed(val: float) -> void:
	GameState.time_speed = val
	for key in speed_buttons.keys():
		var b: Button = speed_buttons[key] as Button
		b.disabled = is_equal_approx(float(key), val)

func _save_current_colony(show_msg: bool) -> void:
	var pawn_list: Array = []
	for i: int in range(colonists.size()):
		var p: Node2D = colonists[i] as Node2D
		if p != null and is_instance_valid(p):
			pawn_list.append({
				"name": p.name,
				"x": p.position.x,
				"y": p.position.y,
				"trait": str(p.get_meta("trait", "Оптиміст")),
				"hp": float(p.get_meta("hp", 100.0)),
				"mood": float(p.get_meta("mood", 85.0)),
				"hunger": float(p.get_meta("hunger", 100.0)),
				"energy": float(p.get_meta("energy", 100.0)),
				"skill_work": int(p.get_meta("skill_work", 4)),
				"skill_combat": int(p.get_meta("skill_combat", 3))
			})
	var ok: bool = GameState.save_game({"colonists": pawn_list})
	if show_msg and top_status_lbl != null:
		top_status_lbl.text = " Гру збережено!" if ok else " Помилка збереження"

func _input(event: InputEvent) -> void:
	if event is InputEventScreenDrag:
		var spd: float = float(GameState.settings.get("camera_speed", 1.0))
		camera.position -= event.relative * spd / camera.zoom.x

func _fill_px(img: Image, x0: int, y0: int, w: int, h: int, col: Color) -> void:
	var x_end: int = mini(TEX_SIZE, x0 + w)
	var y_end: int = mini(TEX_SIZE, y0 + h)
	var x_start: int = maxi(0, x0)
	var y_start: int = maxi(0, y0)
	for y: int in range(y_start, y_end):
		for x: int in range(x_start, x_end):
			img.set_pixel(x, y, col)

func _fill_circle_px(img: Image, cx: int, cy: int, r: int, col: Color) -> void:
	var r2: int = r * r
	for y: int in range(maxi(0, cy - r), mini(TEX_SIZE, cy + r + 1)):
		for x: int in range(maxi(0, cx - r), mini(TEX_SIZE, cx + r + 1)):
			var dx: int = x - cx
			var dy: int = y - cy
			if dx * dx + dy * dy <= r2:
				img.set_pixel(x, y, col)

func _generate_nature_textures() -> void:
	var t_img: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	t_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	_fill_circle_px(t_img, 66, 108, 26, Color(0.05, 0.12, 0.05, 0.45))
	_fill_px(t_img, 54, 72, 20, 42, Color(0.38, 0.22, 0.10))
	_fill_px(t_img, 58, 72, 8, 42, Color(0.50, 0.30, 0.14))
	_fill_circle_px(t_img, 64, 52, 42, Color(0.08, 0.28, 0.10))
	_fill_circle_px(t_img, 46, 56, 26, Color(0.11, 0.34, 0.13))
	_fill_circle_px(t_img, 82, 56, 26, Color(0.07, 0.24, 0.09))
	_fill_circle_px(t_img, 56, 38, 24, Color(0.18, 0.48, 0.18))
	nature_textures["tree"] = ImageTexture.create_from_image(t_img)

	var b_img: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	b_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	_fill_circle_px(b_img, 64, 74, 38, Color(0.10, 0.32, 0.12))
	_fill_circle_px(b_img, 46, 78, 24, Color(0.14, 0.40, 0.16))
	_fill_circle_px(b_img, 82, 78, 24, Color(0.12, 0.36, 0.14))
	_fill_circle_px(b_img, 64, 62, 26, Color(0.18, 0.48, 0.20))
	var berry_coords: Array = [
		Vector2i(46, 66), Vector2i(52, 72), Vector2i(76, 62),
		Vector2i(82, 70), Vector2i(62, 82), Vector2i(68, 88),
		Vector2i(58, 54), Vector2i(74, 82)
	]
	for i: int in range(berry_coords.size()):
		var pt: Vector2i = berry_coords[i]
		_fill_circle_px(b_img, pt.x, pt.y, 6, Color(0.88, 0.12, 0.18))
		_fill_px(b_img, pt.x - 2, pt.y - 2, 2, 2, Color(1.0, 0.75, 0.78))
	nature_textures["berry"] = ImageTexture.create_from_image(b_img)

	var m_img: Image = Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
	m_img.fill(Color(0.0, 0.0, 0.0, 0.0))
	_fill_px(m_img, 48, 66, 18, 38, Color(0.92, 0.88, 0.80))
	_fill_circle_px(m_img, 57, 62, 28, Color(0.76, 0.24, 0.16))
	_fill_px(m_img, 30, 64, 54, 10, Color(0.62, 0.18, 0.12))
	_fill_circle_px(m_img, 46, 50, 4, Color(0.98, 0.96, 0.92))
	_fill_circle_px(m_img, 66, 48, 4, Color(0.98, 0.96, 0.92))
	_fill_circle_px(m_img, 56, 40, 3, Color(0.98, 0.96, 0.92))
	_fill_px(m_img, 82, 82, 12, 24, Color(0.90, 0.86, 0.78))
	_fill_circle_px(m_img, 88, 78, 18, Color(0.82, 0.46, 0.18))
	_fill_px(m_img, 70, 80, 36, 6, Color(0.68, 0.36, 0.12))
	nature_textures["mushroom"] = ImageTexture.cr
