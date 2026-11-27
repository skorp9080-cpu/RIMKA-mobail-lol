extends Control

const MAP_COLS: int = 24
const MAP_ROWS: int = 14

var planet_cells: Array = []
var selected_coords: Vector2i = Vector2i(10, 6)

var menu_panel: VBoxContainer
var planet_panel: Control
var settings_panel: PanelContainer
var btn_load: Button
var info_label: Label
var seed_input: LineEdit
var grid_container: GridContainer
var cell_buttons: Dictionary = {}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_main_menu()
	_build_settings_panel()
	_build_planet_screen()
	_show_screen("menu")

func _build_background() -> void:
	var bg: ColorRect = ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.08, 0.10, 0.13)
	add_child(bg)

func _build_main_menu() -> void:
	menu_panel = VBoxContainer.new()
	menu_panel.set_anchors_preset(Control.PRESET_CENTER)
	menu_panel.offset_left = -220
	menu_panel.offset_right = 220
	menu_panel.offset_top = -180
	menu_panel.offset_bottom = 180
	menu_panel.add_theme_constant_override("separation", 16)
	add_child(menu_panel)

	var title: Label = Label.new()
	title.text = "RIMWORLD COLONY"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 36)
	menu_panel.add_child(title)

	var subtitle: Label = Label.new()
	subtitle.text = "Мобільний симулятор виживання колонії"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.modulate = Color(0.75, 0.82, 0.88)
	menu_panel.add_child(subtitle)

	var btn_new: Button = _make_button("Нова гра", func(): _open_planet_generator())
	btn_load = _make_button("Завантажити збереження", func(): _on_load_pressed())
	var btn_settings: Button = _make_button("Налаштування", func(): _show_screen("settings"))

	menu_panel.add_child(btn_new)
	menu_panel.add_child(btn_load)
	menu_panel.add_child(btn_settings)

func _build_settings_panel() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	settings_panel.offset_left = -240
	settings_panel.offset_right = 240
	settings_panel.offset_top = -170
	settings_panel.offset_bottom = 170
	add_child(settings_panel)

	var box: VBoxContainer = VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	settings_panel.add_child(box)

	var header: Label = Label.new()
	header.text = "НАЛАШТУВАННЯ"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 26)
	box.add_child(header)

	var autosave_chk: CheckButton = CheckButton.new()
	autosave_chk.text = "Автозбереження колонії"
	autosave_chk.button_pressed = bool(GameState.settings.get("autosave", true))
	autosave_chk.add_theme_font_size_override("font_size", 20)
	autosave_chk.toggled.connect(func(val: bool): GameState.settings["autosave"] = val)
	box.add_child(autosave_chk)

	var speed_label: Label = Label.new()
	var init_speed: float = float(GameState.settings.get("camera_speed", 1.0))
	speed_label.text = "Швидкість перетягування камери: %.1fx" % init_speed
	speed_label.add_theme_font_size_override("font_size", 18)
	box.add_child(speed_label)

	var speed_slider: HSlider = HSlider.new()
	speed_slider.min_value = 0.5
	speed_slider.max_value = 2.0
	speed_slider.step = 0.1
	speed_slider.value = init_speed
	speed_slider.value_changed.connect(func(v: float):
		GameState.settings["camera_speed"] = v
		speed_label.text = "Швидкість перетягування камери: %.1fx" % v
	)
	box.add_child(speed_slider)

	var btn_back: Button = _make_button("Назад до меню", func(): _show_screen("menu"))
	box.add_child(btn_back)

func _build_planet_screen() -> void:
	planet_panel = Control.new()
	planet_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(planet_panel)

	var top_bar: HBoxContainer = HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 16
	top_bar.offset_right = -16
	top_bar.offset_top = 12
	top_bar.offset_bottom = 64
	top_bar.add_theme_constant_override("separation", 10)
	planet_panel.add_child(top_bar)

	var btn_back: Button = Button.new()
	btn_back.text = "← Меню"
	btn_back.custom_minimum_size = Vector2(120, 48)
	btn_back.pressed.connect(func(): _show_screen("menu"))
	top_bar.add_child(btn_back)

	seed_input = LineEdit.new()
	seed_input.placeholder_text = "Сід планети..."
	seed_input.text = str(GameState.planet_seed)
	seed_input.custom_minimum_size = Vector2(200, 48)
	top_bar.add_child(seed_input)

	var btn_regen: Button = Button.new()
	btn_regen.text = "Нова планета"
	btn_regen.custom_minimum_size = Vector2(160, 48)
	btn_regen.pressed.connect(func():
		var txt: String = seed_input.text.strip_edges()
		var new_seed: int
		if txt == "":
			new_seed = randi() % 999999
			seed_input.text = str(new_seed)
		elif txt.is_valid_int():
			new_seed = int(txt)
		else:
			new_seed = absi(txt.hash())
		_generate_planet(new_seed)
	)
	top_bar.add_child(btn_regen)

	var btn_rand: Button = Button.new()
	btn_rand.text = "Випадковий сід"
	btn_rand.custom_minimum_size = Vector2(160, 48)
	btn_rand.pressed.connect(func():
		var r: int = randi_range(10000, 999999)
		seed_input.text = str(r)
		_generate_planet(r)
	)
	top_bar.add_child(btn_rand)

	var map_frame: CenterContainer = CenterContainer.new()
	map_frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	map_frame.offset_top = 72
	map_frame.offset_bottom = -96
	planet_panel.add_child(map_frame)

	grid_container = GridContainer.new()
	grid_container.columns = MAP_COLS
	grid_container.add_theme_constant_override("h_separation", 2)
	grid_container.add_theme_constant_override("v_separation", 2)
	map_frame.add_child(grid_container)

	for y in range(MAP_ROWS):
		for x in range(MAP_COLS):
			var c_btn: Button = Button.new()
			c_btn.custom_minimum_size = Vector2(36, 32)
			c_btn.text = ""
			c_btn.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1))
			c_btn.add_theme_font_size_override("font_size", 15)
			var coords: Vector2i = Vector2i(x, y)
			c_btn.pressed.connect(func(): _select_planet_cell(coords))
			grid_container.add_child(c_btn)
			cell_buttons[coords] = c_btn

	var bottom_bar: HBoxContainer = HBoxContainer.new()
	bottom_bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_bar.offset_left = 16
	bottom_bar.offset_right = -16
	bottom_bar.offset_top = -84
	bottom_bar.offset_bottom = -12
	bottom_bar.add_theme_constant_override("separation", 12)
	planet_panel.add_child(bottom_bar)

	info_label = Label.new()
	info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_label.add_theme_font_size_override("font_size", 18)
	info_label.text = "Оберіть клітинку на карті планети"
	bottom_bar.add_child(info_label)

	var btn_land: Button = Button.new()
	btn_land.text = "ВИСАДИТИ КОЛОНІЮ →"
	btn_land.custom_minimum_size = Vector2(240, 62)
	btn_land.add_theme_font_size_override("font_size", 19)
	btn_land.pressed.connect(func(): _start_new_colony())
	bottom_bar.add_child(btn_land)

func _apply_cell_style(btn: Button, bg_color: Color, is_selected: bool) -> void:
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg_color
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	if is_selected:
		sb.border_width_left = 3
		sb.border_width_right = 3
		sb.border_width_top = 3
		sb.border_width_bottom = 3
		sb.border_color = Color(1.0, 0.95, 0.15)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)

func _open_planet_generator() -> void:
	_show_screen("planet")
	_generate_planet(GameState.planet_seed)

func _generate_planet(seed_val: int) -> void:
	GameState.planet_seed = seed_val
	var noise: FastNoiseLite = FastNoiseLite.new()
	noise.seed = seed_val
	noise.frequency = 0.09

	var rock_noise: FastNoiseLite = FastNoiseLite.new()
	rock_noise.seed = seed_val + 777
	rock_noise.frequency = 0.14

	planet_cells.clear()
	for y in range(MAP_ROWS):
		var row: Array = []
		for x in range(MAP_COLS):
			var h: float = noise.get_noise_2d(float(x), float(y))
			var r: float = (rock_noise.get_noise_2d(float(x), float(y)) + 1.0) * 0.5
			var lat: float = absf(float(y) - float(MAP_ROWS) * 0.5) / (float(MAP_ROWS) * 0.5)

			var biome: String = "Помірний ліс"
			var color: Color = Color(0.22, 0.78, 0.30)
			var rock_density: float = 0.15
			var tree_density: float = 0.18
			var temp: int = int(24.0 - lat * 28.0)

			if h < -0.22:
				biome = "Океан (недоступно)"
				color = Color(0.14, 0.48, 0.95)
				rock_density = 0.0
				tree_density = 0.0
			elif r > 0.65 or h > 0.35:
				biome = "Скелясті гори"
				color = Color(0.68, 0.65, 0.62)
				rock_density = 0.38
				tree_density = 0.06
				temp -= 6
			elif lat > 0.72:
				biome = "Холодна тайга"
				color = Color(0.75, 0.90, 0.88)
				rock_density = 0.20
				tree_density = 0.14
			elif lat < 0.25 and h < 0.05:
				biome = "Посушливі скелі"
				color = Color(0.95, 0.78, 0.28)
				rock_density = 0.28
				tree_density = 0.03
				temp += 8

			var cell_data: Dictionary = {
				"x": x,
				"y": y,
				"biome": biome,
				"color": color,
				"rock_density": rock_density,
				"tree_density": tree_density,
				"temp": temp,
				"landable": h >= -0.22
			}
			row.append(cell_data)

			var btn: Button = cell_buttons.get(Vector2i(x, y)) as Button
			if btn != null:
				btn.text = "▲" if biome == "Скелясті гори" else ""
				_apply_cell_style(btn, color, false)
		planet_cells.append(row)

	var safe_coords: Vector2i = Vector2i(
		clampi(selected_coords.x, 0, MAP_COLS - 1),
		clampi(selected_coords.y, 0, MAP_ROWS - 1)
	)
	_select_planet_cell(safe_coords)

func _select_planet_cell(coords: Vector2i) -> void:
	if planet_cells.is_empty():
		return
	var safe_coords: Vector2i = Vector2i(
		clampi(coords.x, 0, MAP_COLS - 1),
		clampi(coords.y, 0, MAP_ROWS - 1)
	)
	selected_coords = safe_coords
	var data: Dictionary = planet_cells[safe_coords.y][safe_coords.x]
	for key in cell_buttons.keys():
		var b: Button = cell_buttons[key] as Button
