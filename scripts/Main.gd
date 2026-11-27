extends Control

enum ScreenState { MAIN_MENU, STORYTELLER, WORLD_MAP, COLONY }
var state: ScreenState = ScreenState.MAIN_MENU

const WORLD_W := 42
const WORLD_H := 24
var world_tiles: Array = []

const MAP_W := 64
const MAP_H := 64
const TILE_SIZE := 64

var terrain_grid: Array = []
var object_grid: Array = []
var stockpile_grid: Array = []
var designation_grid: Array = []
var claimed_grid: Array = []

var resources := {"wood": 200, "steel": 140, "food": 50, "medicine": 10}
var pawns: Array = []
var active_tool: String = "select"
var selected_pawn_idx: int = -1
var show_alt_labels: bool = true

var randy_timer: float = 20.0
var randy_chaos_level: int = 45

var cam_pos := Vector2(2048, 2048)
var cam_zoom: float = 1.0
var is_dragging: bool = false
var drag_moved: bool = false
var touch_start_pos := Vector2.ZERO
var last_drag_pos := Vector2.ZERO

var game_speed: float = 1.0
var game_hours: float = 8.0
var day_count: int = 1

var tex_map: Dictionary = {}

var ui_root: Control
var world_canvas: Control
var colony_canvas: Control
var top_res_label: Label
var time_label: Label
var randy_label: Label
var inspector_label: Label
var pawn_card_panel: PanelContainer
var pawn_card_label: Label
var work_panel: PanelContainer
var work_vbox: VBoxContainer
var letter_box: VBoxContainer
var tool_buttons: Dictionary = {}

func _ready() -> void:
	_generate_procedural_textures()
	ui_root = Control.new()
	ui_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(ui_root)
	_switch_screen(ScreenState.MAIN_MENU)

func _generate_procedural_textures() -> void:
	var s := TILE_SIZE

	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.23, 0.38, 0.19, 1.0))
	for y in range(0, s, 8):
		for x in range(0, s, 8):
			if (x + y) % 16 == 0:
				img.fill_rect(Rect2i(x, y, 3, 3), Color(0.27, 0.43, 0.22, 1.0))
			else:
				img.set_pixel((x + 2) % s, (y + 5) % s, Color(0.19, 0.33, 0.16, 1.0))
	tex_map["grass"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.36, 0.27, 0.18, 1.0))
	for i in range(45):
		img.fill_rect(Rect2i((i * 17) % (s - 2), (i * 29) % (s - 2), 2, 2), Color(0.29, 0.21, 0.14, 1.0))
	tex_map["soil"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.76, 0.68, 0.46, 1.0))
	for i in range(35):
		img.set_pixel((i * 19) % s, (i * 23) % s, Color(0.66, 0.58, 0.38, 1.0))
	tex_map["sand"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.88, 0.92, 0.96, 1.0))
	for i in range(25):
		img.fill_rect(Rect2i((i * 13) % (s - 4), (i * 31) % (s - 2), 4, 2), Color(0.78, 0.85, 0.92, 1.0))
	tex_map["snow"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.15, 0.34, 0.54, 1.0))
	for wy in range(10, s, 16):
		for wx in range(8, s - 8):
			var wave_y := wy + int(sin(float(wx) * 0.25) * 2.0)
			img.set_pixel(wx, wave_y, Color(0.26, 0.50, 0.74, 1.0))
	tex_map["water"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.35, 0.35, 0.38, 1.0))
	_draw_border(img, Color(0.20, 0.20, 0.23, 1.0), 3)
	img.fill_rect(Rect2i(10, 12, 20, 16), Color(0.44, 0.44, 0.48, 1.0))
	img.fill_rect(Rect2i(32, 32, 20, 18), Color(0.28, 0.28, 0.31, 1.0))
	tex_map["rock"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.35, 0.35, 0.38, 1.0))
	_draw_border(img, Color(0.20, 0.20, 0.23, 1.0), 3)
	img.fill_rect(Rect2i(12, 14, 18, 16), Color(0.66, 0.52, 0.42, 1.0))
	img.fill_rect(Rect2i(34, 34, 18, 16), Color(0.75, 0.60, 0.48, 1.0))
	tex_map["steel_ore"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.52, 0.36, 0.21, 1.0))
	_draw_border(img, Color(0.30, 0.19, 0.10, 1.0), 4)
	for py in range(16, s, 16):
		img.fill_rect(Rect2i(4, py, s - 8, 2), Color(0.38, 0.25, 0.13, 1.0))
	tex_map["wall_wood"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(8, 16, 48, 32), Color(0.62, 0.44, 0.26, 1.0))
	_draw_rect_outline(img, Rect2i(8, 16, 48, 32), Color(0.28, 0.18, 0.09, 1.0), 2)
	img.fill_rect(Rect2i(44, 29, 6, 6), Color(0.85, 0.72, 0.25, 1.0))
	tex_map["door"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_ellipse(img, 32, 48, 18, 8, Color(0.08, 0.14, 0.07, 0.45))
	img.fill_rect(Rect2i(28, 30, 8, 20), Color(0.38, 0.25, 0.14, 1.0))
	_draw_ellipse(img, 32, 24, 22, 16, Color(0.16, 0.38, 0.15, 1.0))
	_draw_ellipse(img, 32, 21, 16, 12, Color(0.23, 0.48, 0.20, 1.0))
	tex_map["tree"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_ellipse(img, 32, 36, 18, 14, Color(0.18, 0.41, 0.16, 1.0))
	for bp in [Vector2i(22, 32), Vector2i(34, 28), Vector2i(40, 38), Vector2i(28, 42), Vector2i(20, 40)]:
		_draw_ellipse(img, bp.x, bp.y, 3, 3, Color(0.85, 0.16, 0.22, 1.0))
	tex_map["berry_bush"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	img.fill_rect(Rect2i(12, 6, 40, 52), Color(0.47, 0.31, 0.18, 1.0))
	_draw_rect_outline(img, Rect2i(12, 6, 40, 52), Color(0.27, 0.17, 0.08, 1.0), 2)
	img.fill_rect(Rect2i(16, 10, 32, 12), Color(0.92, 0.92, 0.95, 1.0))
	img.fill_rect(Rect2i(16, 24, 32, 30), Color(0.25, 0.44, 0.66, 1.0))
	tex_map["bed"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_ellipse(img, 32, 42, 18, 12, Color(0.32, 0.32, 0.35, 1.0))
	img.fill_rect(Rect2i(20, 36, 24, 6), Color(0.42, 0.26, 0.12, 1.0))
	_draw_ellipse(img, 32, 30, 10, 14, Color(0.96, 0.55, 0.12, 1.0))
	_draw_ellipse(img, 32, 32, 5, 8, Color(1.0, 0.90, 0.35, 1.0))
	tex_map["campfire"] = ImageTexture.create_from_image(img)

	img = Image.create(s, s, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	_draw_ellipse(img, 32, 53, 14, 5, Color(0.0, 0.0, 0.0, 0.38))
	img.fill_rect(Rect2i(20, 28, 24, 24), Color(0.82, 0.84, 0.88, 1.0))
	_draw_rect_outline(img, Rect2i(20, 28, 24, 24), Color(0.14, 0.16, 0.20, 1.0), 2)
	_draw_ellipse(img, 32, 20, 11, 11, Color(0.93, 0.78, 0.66, 1.0))
	img.fill_rect(Rect2i(27, 19, 2, 3), Color(0.12, 0.12, 0.14, 1.0))
	img.fill_rect(Rect2i(35, 19, 2, 3), Color(0.12, 0.12, 0.14, 1.0))
	tex_map["pawn"] = ImageTexture.create_from_image(img)

func _draw_border(img: Image, col: Color, thickness: int) -> void:
	var w := img.get_width()
	var h := img.get_height()
	img.fill_rect(Rect2i(0, 0, w, thickness), col)
	img.fill_rect(Rect2i(0, h - thickness, w, thickness), col)
	img.fill_rect(Rect2i(0, 0, thickness, h), col)
	img.fill_rect(Rect2i(w - thickness, 0, thickness, h), col)

func _draw_rect_outline(img: Image, rect: Rect2i, col: Color, t: int) -> void:
	img.fill_rect(Rect2i(rect.position.x, rect.position.y, rect.size.x, t), col)
	img.fill_rect(Rect2i(rect.position.x, rect.end.y - t, rect.size.x, t), col)
	img.fill_rect(Rect2i(rect.position.x, rect.position.y, t, rect.size.y), col)
	img.fill_rect(Rect2i(rect.end.x - t, rect.position.y, t, rect.size.y), col)

func _draw_ellipse(img: Image, cx: int, cy: int, rx: int, ry: int, col: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	for y in range(maxi(0, cy - ry), mini(h, cy + ry + 1)):
		for x in range(maxi(0, cx - rx), mini(w, cx + rx + 1)):
			var dx := float(x - cx) / float(maxi(1, rx))
			var dy := float(y - cy) / float(maxi(1, ry))
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, col)

func _clear_ui() -> void:
	for child in ui_root.get_children():
		child.queue_free()
	tool_buttons.clear()

func _switch_screen(new_state: ScreenState) -> void:
	state = new_state
	_clear_ui()
	match state:
		ScreenState.MAIN_MENU:
			_build_main_menu()
		ScreenState.STORYTELLER:
			_build_storyteller_menu()
		ScreenState.WORLD_MAP:
			_generate_planet()
			_build_world_map_ui()
		ScreenState.COLONY:
			_generate_colony_map()
			_build_colony_ui()

func _build_main_menu() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(center)

	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(440, 340)
	vbox.add_theme_constant_override("separation", 14)
	center.add_child(vbox)

	var title := Label.new()
	title.text = "РІМВОРЛД"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.92, 0.86, 0.72))
	vbox.add_child(title)

	var sub := Label.new()
	sub.text = "СИМУЛЯТОР КОЛОНІЇ • ЕТАП 1"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 16)
	sub.add_theme_color_override("font_color", Color(0.65, 0.70, 0.75))
	vbox.add_child(sub)

	var btn_new := Button.new()
	btn_new.text = "НОВА КОЛОНІЯ"
	btn_new.custom_minimum_size = Vector2(0, 56)
	btn_new.pressed.connect(func(): _switch_screen(ScreenState.STORYTELLER))
	vbox.add_child(btn_new)

	var btn_quick := Button.new()
	btn_quick.text = "ШВИДКИЙ СТАРТ (РЕНДІ РАНДОМ)"
	btn_quick.custom_minimum_size = Vector2(0, 52)
	btn_quick.pressed.connect(func():
		GameState.planet_seed = randi() % 99999
		GameState.storyteller = "Ренді Рандом"
		GameState.selected_biome = "Помірний ліс"
		GameState.selected_temp = 19.5
		GameState.selected_hills = "Пагорби"
		_switch_screen(ScreenState.COLONY)
	)
	vbox.add_child(btn_quick)

	var btn_exit := Button.new()
	btn_exit.text = "ВИХІД"
	btn_exit.custom_minimum_size = Vector2(0, 48)
	btn_exit.pressed.connect(func(): get_tree().quit())
	vbox.add_child(btn_exit)

func _build_storyteller_menu() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.09, 0.10, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 440)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	var header := Label.new()
	header.text = "ОБЕРІТЬ ОПОВІДАЧА ШІ"
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_theme_font_size_override("font_size", 28)
	vbox.add_child(header)

	var hbox := HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(hbox)

	var storytellers := [
		{"name": "Кассандра Класик", "desc": "Поступове зростання напруги та викликів."},
		{"name": "Фібі Тихоня", "desc": "Довгі періоди спокою для розбудови бази."},
		{"name": "Ренді Рандом", "desc": "Повний рандом: капсули, 42 дерев'яні ноги, їжа без столу або бонуси."}
	]

	var selected_lbl := Label.new()
	selected_lbl.text = "Обрано: " + GameState.storyteller
	selected_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	selected_lbl.add_theme_color_override("font_color", Color(0.95, 0.78, 0.35))

	for st in storytellers:
		var card := Button.new()
		card.custom_minimum_size = Vector2(210, 190)
		card.text = st["name"] + "\n\n" + st["desc"]
		card.autowrap_mode = TextServer.AUTOWRAP_WORD
		card.pressed.connect(func():
			GameState.storyteller = st["name"]
			selected_lbl.text = "Обрано: " + GameState.storyteller
		)
		hbox.add_child(card)

	vbox.add_child(selected_lbl)

	var nav := HBoxContainer.new()
	nav.alignment = BoxContainer.ALIGNMENT_CENTER
	nav.add_theme_constant_override("separation", 24)
	vbox.add_child(nav)

	var back_btn := Button.new()
	back_btn.text = "← НАЗАД"
	back_btn.custom_minimum_size = Vector2(180, 52)
	back_btn.pressed.connect(func(): _switch_screen(ScreenState.MAIN_MENU))
	nav.add_child(back_btn)

	var next_btn := Button.new()
	next_btn.text = "ГЕНЕРАЦІЯ ПЛАНЕТИ →"
	next_btn.custom_minimum_size = Vector2(240, 52)
	next_btn.pressed.connect(func(): _switch_screen(ScreenState.WORLD_MAP))
	nav.add_child(next_btn)

func _generate_planet() -> void:
	world_tiles.clear()
	for y in range(WORLD_H):
		var row := []
		for x in range(WORLD_W):
			row.append(GameState.get_biome_at(x, y, GameState.planet_seed))
		world_tiles.append(row)
	if world_tiles[GameState.selected_tile.y][GameState.selected_tile.x]["is_water"]:
		_pick_random_land_tile()

func _pick_random_land_tile() -> void:
	for attempt in range(120):
		var rx := randi() % WORLD_W
		var ry := randi() % WORLD_H
		if not world_tiles[ry][rx]["is_water"]:
			GameState.selected_tile = Vector2i(rx, ry)
			return

func _build_world_map_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(bg)

	var hbox := HBoxContainer.new()
	hbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	ui_root.add_child(hbox)

	world_canvas = Control.new()
	world_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	world_canvas.draw.connect(_draw_planet_map)
	world_canvas.gui_input.connect(_on_planet_input)
	hbox.add_child(world_canvas)

	var side := PanelContainer.new()
	side.custom_minimum_size = Vector2(360, 0)
	hbox.add_child(side)

	var svbox := VBoxContainer.new()
	svbox.add_theme_constant_override("separation", 12)
	side.add_child(svbox)

	var title := Label.new()
	title.text = "КАРТА ПЛАНЕТИ"
	title.add_theme_font_size_override("font_size", 24)
	svbox.add_child(title)

	var seed_btn := Button.new()
	seed_btn.text = "🎲 Новий сід (" + str(GameState.planet_seed) + ")"
	seed_btn.custom_minimum_size = Vector2(0, 48)
	seed_btn.pressed.connect(func():
		GameState.planet_seed = randi() % 99999
		seed_btn.text = "🎲 Новий сід (" + str(GameState.planet_seed) + ")"
		_generate_planet()
		_update_planet_inspector()
		world_canvas.queue_redraw()
	)
	svbox.add_child(seed_btn)

	inspector_label = Label.new()
	inspector_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	inspector_label.add_theme_font_size_override("font_size", 16)
	svbox.add_child(inspector_label)

	var rand_site_btn := Button.new()
	rand_site_btn.text = "Випадкове місце висадки"
	rand_site_btn.custom_minimum_size = Vector2(0, 48)
	rand_site_btn.pressed.connect(func():
		_pick_random_land_tile()
		_update_planet_inspector()
