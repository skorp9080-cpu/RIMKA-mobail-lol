extends Node2D

const GRID_W: int = 80
const GRID_H: int = 56
const TILE_SIZE: float = 32.0
const TEX_SIZE: int = 128
const SAVE_PATH: String = "user://colony_save.json"

var camera: Camera2D
var day_night_modulate: CanvasModulate
var top_status_lbl: Label
var speed_buttons: Dictionary = {}
var colonists: Array = []
var raiders: Array = []
var wildlife: Array = []
var nature_textures: Dictionary = {}
var event_timer: float = 38.0
var _drag_active: bool = false
var _last_drag_pos: Vector2 = Vector2.ZERO

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
	_spawn_wildlife()
	_spawn_initial_colonists()
	_build_top_bar()
	_ensure_mobile_hud()
	_update_temperature()
	_update_lighting()
	_update_top_label()

func focus_on_colonist(pawn: Node2D) -> void:
	if camera != null and pawn != null and is_instance_valid(pawn):
		camera.position = pawn.global_position

func _ensure_mobile_hud() -> void:
	var hud: Node = get_tree().root.get_node_or_null("MobileHUD")
	if hud == null:
		hud = get_node_or_null("MobileHUD")
	if hud == null:
		var hud_script: GDScript = load("res://scripts/mobile_hud_controller.gd") as GDScript
		if hud_script != null:
			hud = hud_script.new() as Node2D
			hud.name = "MobileHUD"
			add_child(hud)
	if hud != null:
		if hud.has_method("rebuild_colonist_bar"):
			hud.call("rebuild_colonist_bar")
		if GameState.is_loading_save and hud.has_method("import_save_state"):
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

func _build_top_bar() -> void:
	var layer: CanvasLayer = CanvasLayer.new()
	layer.layer = 16
	add_child(layer)

	var bar: PanelContainer = PanelContainer.new()
	bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	bar.offset_bottom = 44
	layer.add_child(bar)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	bar.add_child(hbox)

	top_status_lbl = Label.new()
	top_status_lbl.add_theme_font_size_override("font_size", 12)
	top_status_lbl.text = " Д.1 08:00 | +18°C"
	hbox.add_child(top_status_lbl)

	var spacer: Control = Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var speeds: Array = [
		{"val": 0.0, "label": "||"},
		{"val": 1.0, "label": "1x"},
		{"val": 2.0, "label": "2x"},
		{"val": 4.0, "label": "4x"}
	]
	for i: int in range(speeds.size()):
		var s_item: Dictionary = speeds[i]
		var spd_val: float = float(s_item["val"])
		var btn: Button = Button.new()
		btn.text = str(s_item["label"])
		btn.custom_minimum_size = Vector2(40, 32)
		btn.add_theme_font_size_override("font_size", 12)
		btn.pressed.connect(func(): _set_time_speed(spd_val))
		hbox.add_child(btn)
		speed_buttons[spd_val] = btn

	var btn_save: Button = Button.new()
	btn_save.text = "Зберегти"
	btn_save.custom_minimum_size = Vector2(74, 32)
	btn_save.add_theme_font_size_override("font_size", 12)
	btn_save.pressed.connect(func(): _save_current_colony(true))
	hbox.add_child(btn_save)

	var btn_menu: Button = Button.new()
	btn_menu.text = "Меню"
	btn_menu.custom_minimum_size = Vector2(60, 32)
	btn_menu.add_theme_font_size_override("font_size", 12)
	btn_menu.pressed.connect(func():
		if bool(GameState.settings.get("autosave", true)):
			_save_current_colony(false)
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	hbox.add_child(btn_menu)

	_set_time_speed(GameState.time_speed)

func _set_time_speed(spd: float) -> void:
	GameState.time_speed = spd
	for k in speed_buttons.keys():
		var b: Button = speed_buttons[k] as Button
		if b != null:
			b.modulate = Color(1.0, 0.9, 0.4) if is_equal_approx(float(k), spd) else Color.WHITE

func _save_current_colony(notify_user: bool) -> void:
	var col_data: Array = []
	for i: int in range(colonists.size()):
		var p: Node2D = colonists[i] as Node2D
		if p != null and is_instance_valid(p):
			col_data.append({
				"name": p.name,
				"x": p.global_position.x,
				"y": p.global_position.y,
				"trait": str(p.get_meta("trait", "Оптиміст")),
				"hp": float(p.get_meta("hp", 100.0)),
				"mood": float(p.get_meta("mood", 85.0)),
				"hunger": float(p.get_meta("hunger", 100.0)),
				"energy": float(p.get_meta("energy", 100.0)),
				"skill_work": int(p.get_meta("skill_work", 4)),
				"skill_combat": int(p.get_meta("skill_combat", 3)),
				"has_armor": bool(p.get_meta("has_armor", false)),
				"has_rifle": bool(p.get_meta("has_rifle", false))
			})

	var animal_data: Array = []
	for i: int in range(wildlife.size()):
		var a: Node2D = wildlife[i] as Node2D
		if a != null and is_instance_valid(a):
			animal_data.append({
				"kind": str(a.get_meta("kind", "deer")),
				"x": a.global_position.x,
				"y": a.global_position.y,
				"tamed": bool(a.get_meta("tamed", false))
			})

	var hud_state: Dictionary = {}
	var hud: Node = _get_hud()
	if hud != null and hud.has_method("export_save_state"):
		hud_state = hud.call("export_save_state")

	var payload: Dictionary = {
		"planet_seed": GameState.planet_seed,
		"selected_tile": GameState.selected_tile,
		"current_day": GameState.current_day,
		"game_time_hours": GameState.game_time_hours,
		"unlocked_techs": GameState.unlocked_techs,
		"active_research_id": GameState.active_research_id,
		"research_progress": GameState.research_progress,
		"colonists": col_data,
		"wildlife": animal_data,
		"hud_state": hud_state
	}

	var f: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(payload))
		f.close()
		if notify_user and hud != null and hud.has_method("notify_event"):
			hud.call("notify_event", "Колонію збережено (День %d)" % GameState.current_day)

func _unhandled_input(event: InputEvent) -> void:
	if camera == null:
		return
	var cam_spd: float = float(GameState.settings.get("camera_speed", 1.0))
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE or event.button_index == MOUSE_BUTTON_RIGHT:
			_drag_active = event.pressed
			_last_drag_pos = event.position
	elif event is InputEventMouseMotion and _drag_active:
		var delta_pos: Vector2 = event.position - _last_drag_pos
		_last_drag_pos = event.position
		camera.position -= (delta_pos / camera.zoom.x) * cam_spd
	elif event is InputEventScreenDrag:
		camera.position -= (event.relative / camera.zoom.x) * cam_spd

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
			event_timer = randf_range(45.0, 78.0)
			_trigger_storyteller_event()

		_process_wildlife(sim_delta)
		_process_raiders(sim_delta)

	_update_temperature()
	_update_lighting()
	_update_top_label()

func _spawn_wildlife() -> void:
	var saved_animals: Array = GameState.loaded_save_data.get("wildlife", []) if GameState.is_loading_save else []
	if not saved_animals.is_empty():
		for i: int in range(saved_animals.size()):
			if saved_animals[i] is Dictionary:
				var ad: Dictionary = saved_animals[i]
				_create_animal_node(
					str(ad.get("kind", "deer")),
					Vector2(float(ad.get("x", 600.0)), float(ad.get("y", 600.0))),
					bool(ad.get("tamed", false)),
					i
				)
		return

	var center: Vector2 = Vector2(float(GRID_W) * TILE_SIZE * 0.5, float(GRID_H) * TILE_SIZE * 0.5)
	for i: int in range(8):
		var kind: String = "boar" if (i % 2 == 0) else "deer"
		var angle: float = randf() * TAU
		var dist: float = randf_range(260.0, 760.0)
		_create_animal_node(kind, center + Vector2(cos(angle), sin(angle)) * dist, false, i)

func _create_animal_node(kind: String, pos: Vector2, tamed: bool, idx: int) -> void:
	var animal: Node2D = Node2D.new()
	animal.name = "Animal_%s_%d" % [kind, idx]
	animal.add_to_group("wildlife")
	animal.position = pos
	animal.set_meta("kind", kind)
	animal.set_meta("tamed", tamed)
	animal.set_meta("hp", 75.0 if kind == "boar" else 55.0)
	animal.set_meta("move_timer", randf_range(1.0, 3.5))
	animal.set_meta("move_dir", Vector2.ZERO)
	animal.z_index = 4

	var spr: TextureRect = TextureRect.new()
	spr.texture = nature_textures.get(kind) as Texture2D
	spr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	spr.stretch_mode = TextureRect.STRETCH_SCALE
	spr.size = Vector2(28, 28)
	spr.position = Vector2(-14, -14)
	spr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	animal.add_child(spr)

	var lbl: Label = Label.new()
	lbl.name = "AnimalLabel"
	lbl.text = ("[Ручний] " if tamed else "") + ("Кабан" if kind == "boar" else "Олень")
	lbl.position = Vector2(-24, -30)
	lbl.add_theme_font_size_override("font_size", 11)
	animal.add_child(lbl)

	add_child(animal)
	wildlife.append(animal)

func _process_wildlife(sim_delta: float) -> void:
	for i: int in range(wildlife.size()):
		var a: Node2D = wildlife[i] as Node2D
		if a == null or not is_instance_valid(a):
			continue
		var tamed: bool = bool(a.get_meta("tamed", false))
		var kind: String = str(a.get_meta("kind", "deer"))

		if tamed:
			var leader: Node2D = _find_nearest_colonist(a.global_position)
			if leader != null and a.global_position.distance_to(leader.global_position) > 58.0:
				a.global_position += (leader.global_position - a.global_position).normalized() * 95.0 * sim_delta
		else:
			var t_left: float = float(a.get_meta("move_timer", 1.5)) - sim_delta
			var dir: Vector2 = a.get_meta("move_dir", Vector2.ZERO)
			if t_left <= 0.0:
				t_left = randf_range(2.0, 4.5)
				if randf() < 0.65:
					var ang: float = randf() * TAU
					dir = Vector2(cos(ang), sin(ang))
				else:
					dir = Vector2.ZERO
				a.set_meta("move_dir", dir)
			a.set_meta("move_timer", t_left)
			if dir != Vector2.ZERO:
				var next_pos: Vector2 = a.global_position + dir * 32.0 * sim_delta
				next_pos.x = clampf(next_pos.x, TILE_SIZE * 2.0, float(GRID_W - 2) * TILE_SIZE)
				next_pos.y = clampf(next_pos.y, TILE_SIZE * 2.0, float(GRID_H - 2) * TILE_SIZE)
				a.global_position = next_pos

		var lbl: Label = a.get_node_or_null("AnimalLabel") as Label
		if lbl != null:
			var prefix: String = "[Ручний] " if tamed else ""
			lbl.text = "%s%s" % [prefix, ("Кабан" if kind == "boar" else "Олень")]

func _get_base_temp() -> int:
	if GameState.selected_tile is Dictionary:
		return int(GameState.selected_tile.get("temp", 18))
	return int(round(float(GameState.get("selected_temp")))) if "selected_temp" in GameState else 18

func _update_temperature() -> void:
	var base_t: int = _get_base_temp()
	var day_offset: int = -5 if (GameState.game_time_hours >= 22.0 or GameState.game_time_hours < 6.0) else 3
	var weather_offset: int = 0
	if GameState.active_weather_event == "Теплова хвиля":
		weather_offset = 16
	elif GameState.active_weather_event == "Похолодання":
		weather_offset = -18

	var climate_delta: int = 0
	var hud: Node = _get_hud()
	if hud != null and hud.has_method("get_climate_offset"):
		climate_delta = int(hud.call("get_climate_offset"))

	GameState.ambient_temp = base_t + day_offset + weather_offset + climate_delta

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
	var pwr_txt: String = ""
	var hud: Node = _get_hud()
	if hud != null and hud.has_method("get_power_summary"):
		pwr_txt = " | %s" % str(hud.call("get_power_summary"))
	top_status_lbl.text = " Д.%d %02d:%02d | %+d°C%s%s" % [GameState.current_day, h_int, m_int, GameState.ambient_temp, pwr_txt, ev_txt]

func _trigger_storyteller_event() -> void:
	var hud: Node = _get_hud()
	var roll: int = randi() % 7
	match roll:
		0:
			var count: int = clampi(1 + GameState.current_day / 2, 1, 4)
			_spawn_raid(count)
			if hud != null and hud.has_method("notify_event"):
				hud.call("notify_event", "УВАГА: Набіг рейдерів (%d ворогів)!" % count)
		1:
			if hud != null and hud.has_method("grant_drop_pod"):
				hud.call("grant_drop_pod")
		2:
			if colonists.size() < 8:
				var new_name: String = EXTRA_NAMES[randi() % EXTRA_NAMES.size()]
				var center: Vector2 = Vector2(float(GRID_W) * TILE_SIZE * 0.5, float(GRID_H) * TILE_SIZE * 0.5)
				_create_colonist_pawn(new_name, center + Vector2(randf_range(-180, 180), randf_range(-140, 140)), {})
				if hud != null and hud.has_method("notify_event"):
					hud.call("notify_event", "Подія: До колонії приєднався %s!" % new_name)
				if hud != null and hud.has_method("rebuild_colonist_bar"):
					hud.call("rebuild_colonist_bar")
		3:
			var events: PackedStringArray = PackedStringArray(["Теплова хвиля", "Похолодання", "Сонячний спалах", ""])
			GameState.active_weather_event = events[randi() % events.size()]
			if hud != null and hud.has_method("notify_event"):
				var msg: String = "Подія: %s!" % GameState.active_weather_event if GameState.active_weather_event != "" else "Погода стабілізувалася"
				hud.call("notify_event", msg)
		4:
			if hud != null and hud.has_method("enable_trader"):
				hud.call("enable_trader")
		5:
			_trigger_meteor_impact(hud)
		6:
			_trigger_disease_outbreak(hud)

func _trigger_meteor_impact(hud: Node) -> void:
	var cx: int = randi_range(16, GRID_W - 16)
	var cy: int = randi_range(12, GRID_H - 12)
	var crater: ColorRect = ColorRect.new()
	crater.size = Vector2(TILE_SIZE * 2.0, TILE_SIZE * 2.0)
	crater.position = Vector2(float(cx - 1) * TILE_SIZE, float(cy - 1) * TILE_SIZE)
	crater.color = Color(0.18, 0.16, 0.16, 0.88)
	crater.z_index = 1
	crater.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(crater)

	if hud != null and hud.has_method("grant_meteor_loot"):
		hud.call("grant_meteor_loot")
	if hud != null and hud.has_method("notify_event"):
		hud.call("notify_event", "Метеорит упав! У кратері знайдено сталь і компоненти")

func _trigger_disease_outbreak(hud: Node) -> void:
	for i: int in range(colonists.size()):
		var p: Node2D = colonists[i] as Node2D
		if p != null and is_instance_valid(p):
			var hp: float = float(p.get_meta("hp", 100.0))
			p.set_meta("hp", maxf(25.0, hp - 22.0))
	if hud != null and hud.has_method("notify_event"):
		hud.call("notify_event", "Спалах хвороби! Колоністи ослабли — потрібні медикаменти")

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

		var has_rifle: bool = bool(target_pawn.get_meta("has_rifle", false))
		var has_armor: bool = bool(target_pawn.get_meta("has_armor", false))
		var engage_range: float = 150.0 if has_rifle else 44.0

		var dist: float = r.global_position.distance_to(target_pawn.global_position)
		if dist > engage_range:
			r.global_position += (target_pawn.global_position - r.global_position).normalized() * 78.0 * sim_delta
		else:
			var cd: float = float(r.get_meta("attack_cd", 0.0)) - sim_delta
			if cd <= 0.0:
				cd = 1.25
				var dmg_taken: float = 5.0 if has_armor else 12.0
				var p_hp: float = maxf(10.0, float(target_pawn.get_meta("hp", 100.0)) - dmg_taken)
				target_pawn.set_meta("hp", p_hp)

				var combat_skill: int = int(target_pawn.get_meta("skill_combat", 3))
				var weapon_bonus: float = 18.0 if has_rifle else 0.0
				hp -= (14.0 + weapon_bonus + float(combat_skill) * 2.5)
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
	var tx: int = 0
	var ty: int = 0
	var rock_density: float = 0.22
	var tree_density: float = 0.16
	var biome: String = str(GameState.get("selected_biome")) if "selected_biome" in GameState else "Помірний ліс"

	if GameState.selected_tile is Dictionary:
		var tile_info: Dictionary = GameState.selected_tile
		tx = int(tile_info.get("x", 0))
		ty = int(tile_info.get("y", 0))
		rock_density = float(tile_info.get("rock_density", 0.22))
		tree_density = float(tile_info.get("tree_density", 0.16))
		biome = str(tile_info.get))
