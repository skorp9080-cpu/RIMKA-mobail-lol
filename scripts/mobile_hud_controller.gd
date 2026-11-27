extends Node2D

const TILE_SIZE: float = 32.0
const SELECT_RADIUS: float = 36.0

var current_category: String = "walls"
var selected_build_id: String = ""
var selected_colonist: Node2D = null
var colonist_targets: Dictionary = {}
var placed_cells: Dictionary = {}
var placed_floors: Dictionary = {}
var item_textures: Dictionary = {}

var wood: int = 200
var steel: int = 140
var stone: int = 120

var hud_layer: CanvasLayer
var selection_ring: Line2D
var status_label: Label
var category_buttons: Dictionary = {}
var items_hbox: HBoxContainer
var btn_cancel: Button

var categories_order: Array = ["walls", "floors", "furniture", "workbenches", "power"]
var category_titles: Dictionary = {
	"walls": "Стіни",
	"floors": "Підлога",
	"furniture": "Меблі",
	"workbenches": "Верстаки",
	"power": "Енергетика"
}

var build_catalog: Dictionary = {
	"walls": [
		{"id": "wall_wood", "name": "Дер. стіна", "wood": 10, "steel": 0, "stone": 0, "is_floor": false},
		{"id": "wall_stone", "name": "Кам. стіна", "wood": 0, "steel": 0, "stone": 15, "is_floor": false},
		{"id": "wall_steel", "name": "Стал. стіна", "wood": 0, "steel": 15, "stone": 0, "is_floor": false}
	],
	"floors": [
		{"id": "floor_wood", "name": "Дер. підлога", "wood": 5, "steel": 0, "stone": 0, "is_floor": true},
		{"id": "floor_stone", "name": "Кам. плитка", "wood": 0, "steel": 0, "stone": 5, "is_floor": true},
		{"id": "floor_steel", "name": "Метал. підлога", "wood": 0, "steel": 5, "stone": 0, "is_floor": true}
	],
	"furniture": [
		{"id": "bed", "name": "Ліжко", "wood": 25, "steel": 0, "stone": 0, "is_floor": false},
		{"id": "table", "name": "Стіл", "wood": 15, "steel": 0, "stone": 0, "is_floor": false},
		{"id": "storage", "name": "Склад", "wood": 15, "steel": 10, "stone": 0, "is_floor": false}
	],
	"workbenches": [
		{"id": "bench_wood", "name": "Верстак", "wood": 30, "steel": 0, "stone": 0, "is_floor": false},
		{"id": "bench_forge", "name": "Кузня", "wood": 10, "steel": 25, "stone": 15, "is_floor": false},
		{"id": "bench_stove", "name": "Плита", "wood": 15, "steel": 20, "stone": 0, "is_floor": false}
	],
	"power": [
		{"id": "solar", "name": "Сон. панель", "wood": 0, "steel": 25, "stone": 0, "is_floor": false},
		{"id": "wind", "name": "Вітряк", "wood": 15, "steel": 30, "stone": 0, "is_floor": false},
		{"id": "battery", "name": "Акумулятор", "wood": 0, "steel": 20, "stone": 0, "is_floor": false}
	]
}

func _ready() -> void:
	_generate_all_textures()
	_create_selection_ring()
	_build_mobile_hud()
	_select_category("walls")

func _is_colony_scene() -> bool:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return false
	return scene.name != "MainMenu" and not scene.scene_file_path.ends_with("MainMenu.tscn")

func _physics_process(delta: float) -> void:
	var in_colony: bool = _is_colony_scene()
	if hud_layer != null:
		hud_layer.visible = in_colony

	if not in_colony:
		if selection_ring != null:
			selection_ring.visible = false
		return

	for pawn in colonist_targets.keys():
		if not is_instance_valid(pawn):
			colonist_targets.erase(pawn)
			continue
		var pawn_node: Node2D = pawn as Node2D
		var target: Vector2 = colonist_targets[pawn]
		var to_target: Vector2 = target - pawn_node.global_position
		if to_target.length() <= 4.0:
			pawn_node.global_position = target
			colonist_targets.erase(pawn)
		else:
			pawn_node.global_position += to_target.normalized() * 110.0 * delta

	if is_instance_valid(selected_colonist):
		selection_ring.visible = true
		selection_ring.global_position = selected_colonist.global_position
	else:
		selected_colonist = null
		selection_ring.visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not _is_colony_scene():
		return

	var tapped: bool = false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		tapped = true
	elif event is InputEventScreenTouch and event.pressed:
		tapped = true

	if not tapped:
		return

	var world_pos: Vector2 = get_global_mouse_position()

	if selected_build_id != "":
		_try_place_building(world_pos)
		return

	var clicked_pawn: Node2D = _find_colonist_near(world_pos)
	if clicked_pawn != null:
		selected_colonist = clicked_pawn
		status_label.text = "Вибрано: %s — тапніть по землі для руху" % clicked_pawn.name
		return

	if is_instance_valid(selected_colonist):
		colonist_targets[selected_colonist] = world_pos
		status_label.text = "%s прямує до точки..." % selected_colonist.name

func _find_colonist_near(pos: Vector2) -> Node2D:
	var best_pawn: Node2D = null
	var best_dist: float = SELECT_RADIUS

	var candidates: Array = get_tree().get_nodes_in_group("colonists")
	if candidates.is_empty():
		candidates = _collect_scene_pawns(get_tree().current_scene)

	for item in candidates:
		if item is Node2D and item != self:
			var pawn_node: Node2D = item as Node2D
			var d: float = pawn_node.global_position.distance_to(pos)
			if d <= best_dist:
				best_dist = d
				best_pawn = pawn_node
	return best_pawn

func _collect_scene_pawns(root: Node) -> Array:
	var result: Array = []
	if root == null:
		return result
	for child in root.get_children():
		if child is Node2D and (child.name in ["Олекса", "Соломія", "Богдан"] or child.has_node("Label")):
			result.append(child)
		result.append_array(_collect_scene_pawns(child))
	return result

func _find_item_def(item_id: String) -> Dictionary:
	for cat in build_catalog.keys():
		var list: Array = build_catalog[cat]
		for entry in list:
			if str(entry["id"]) == item_id:
				return entry
	return {}

func _try_place_building(world_pos: Vector2) -> void:
	var item_def: Dictionary = _find_item_def(selected_build_id)
	if item_def.is_empty():
		return

	var cell: Vector2i = Vector2i(floori(world_pos.x / TILE_SIZE), floori(world_pos.y / TILE_SIZE))
	var is_floor: bool = bool(item_def.get("is_floor", false))

	if is_floor and placed_floors.has(cell):
		status_label.text = "Тут уже є підлога"
		return
	if not is_floor and placed_cells.has(cell):
		status_label.text = "Ця клітинка вже зайнята"
		return

	var c_wood: int = int(item_def["wood"])
	var c_steel: int = int(item_def["steel"])
	var c_stone: int = int(item_def["stone"])

	if wood < c_wood or steel < c_steel or stone < c_stone:
		status_label.text = "Не вистачає ресурсів! (Д:%d С:%d К:%d)" % [wood, steel, stone]
		return

	wood -= c_wood
	steel -= c_steel
	stone -= c_stone

	var block: TextureRect = TextureRect.new()
	block.texture = item_textures.get(selected_build_id)
	block.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	block.stretch_mode = TextureRect.STRETCH_SCALE
	block.size = Vector2(TILE_SIZE, TILE_SIZE)
	block.position = Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if is_floor:
		block.z_index = -1
		placed_floors[cell] = block
	else:
		block.z_index = 2
		placed_cells[cell] = block

	get_tree().current_scene.add_child(block)
	status_label.text = "Збудовано: %s | Залишок — Дер: %d, Сталь: %d, Кам: %d" % [
		str(item_def["name"]), wood, steel, stone
	]

func _create_selection_ring() -> void:
	selection_ring = Line2D.new()
	selection_ring.width = 2.5
	selection_ring.default_color = Color(0.2, 1.0, 0.35)
	selection_ring.closed = true
	selection_ring.points = PackedVector2Array([
		Vector2(-18, -22),
		Vector2(18, -22),
		Vector2(18, 22),
		Vector2(-18, 22)
	])
	selection_ring.visible = false
	selection_ring.z_index = 50
	add_child(selection_ring)

func _build_mobile_hud() -> void:
	hud_layer = CanvasLayer.new()
	hud_layer.layer = 10
	hud_layer.visible = false
	add_child(hud_layer)

	var root_box: VBoxContainer = VBoxContainer.new()
	root_box.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	root_box.offset_top = -172
	root_box.offset_left = 10
	root_box.offset_right = -10
	root_box.offset_bottom = -8
	root_box.add_theme_constant_override("separation", 4)
	hud_layer.add_child(root_box)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = "Оберіть вкладку будівництва або тапніть по колоністу"
	status_label.add_theme_font_size_override("font_size", 16)
	root_box.add_child(status_label)

	# Рядок вкладок категорій
	var tabs_hbox: HBoxContainer = HBoxContainer.new()
	tabs_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs_hbox.add_theme_constant_override("separation", 6)
	root_box.add_child(tabs_hbox)

	for cat_id in categories_order:
		var cid: String = str(cat_id)
		var tab_btn: Button = Button.new()
		tab_btn.text = str(category_titles[cid])
		tab_btn.custom_minimum_size = Vector2(110, 42)
		tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn.add_theme_font_size_override("font_size", 15)
		tab_btn.pressed.connect(func(): _select_category(cid))
		tabs_hbox.add_child(tab_btn)
		category_buttons[cid] = tab_btn

	btn_cancel = Button.new()
	btn_cancel.text = "✕ Скасувати"
	btn_cancel.custom_minimum_size = Vector2(120, 42)
	btn_cancel.add_theme_font_size_override("font_size", 15)
	btn_cancel.pressed.connect(func(): _select_build_item(""))
	tabs_hbox.add_child(btn_cancel)

	# Панель карток будівель обраної вкладки
	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 82)
	root_box.add_child(panel)

	items_hbox = HBoxContainer.new()
	items_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	items_hbox.add_theme_constant_override("separation", 10)
	panel.add_child(items_hbox)

func _select_category(cat_id: String) -> void:
	current_category = cat_id
	for key in category_buttons.keys():
		var b: Button = category_buttons[key]
		b.disabled = (str(key) == cat_id)
	_rebuild_item_buttons()

func _rebuild_item_buttons() -> void:
	for child in items_hbox.get_children():
		child.queue_free()

	var list: Array = build_catalog.get(current_category, [])
	for entry in list:
		var item_id: String = str(entry["id"])
		var cost_parts: Array = []
		if int(entry["wood"]) > 0:
			cost_parts.append("%d дер." % int(entry["wood"]))
		if int(entry["stone"]) > 0:
			cost_parts.append("%d кам." % int(entry["stone"]))
		if int(entry["steel"]) > 0:
			cost_parts.append("%d сталі" % int(entry["steel"]))

		var btn: Button = Button.new()
		btn.text = "%s\n(%s)" % [str(entry["name"]), ", ".join(cost_parts)]
		btn.icon = item_textures.get(item_id)
		btn.expand_icon = true
		btn.custom_minimum_size = Vector2(180, 72)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 15)
		btn.disabled = (selected_build_id == item_id)
		btn.pressed.connect(func(): _select_build_item(item_id))
		items_hbox.add_child(btn)

	btn_cancel.visible = (selected_build_id != "")

func _select_build_item(item_id: String) -> void:
	selected_build_id = item_id
	_rebuild_item_buttons()
	if item_id == "":
		status_label.text = "Режим наказів: тапніть по колоністу"
	else:
		var def: Dictionary = _find_item_def(item_id)
		status_label.text = "Обрано: %s — тапніть по карті для побудови" % str(def.get("name", ""))

# Генерація процедурних текстур 32x32 для кожного блоку
func _generate_all_textures() -> void:
	item_textures["wall_wood"] = _make_tex(Color(0.56, 0.36, 0.18), "planks")
	item_textures["wall_stone"] = _make_tex(Color(0.52, 0.52, 0.54), "bricks")
	item_textures["wall_steel"] = _make_tex(Color(0.45, 0.54, 0.64), "metal")

	item_textures["floor_wood"] = _make_tex(Color(0.72, 0.52, 0.30), "planks")
	item_textures["floor_stone"] = _make_tex(Color(0.68, 0.68, 0.70), "tiles")
	item_textures["floor_steel"] = _make_tex(Color(0.60, 0.66, 0.72), "tiles")

	item_textures["bed"] = _make_tex(Color(0.24, 0.50, 0.86), "bed")
	item_textures["table"] = _make_tex(Color(0.66, 0.44, 0.22), "table")
	item_textures["storage"] = _make_tex(Color(0.86, 0.68, 0.20), "crate")

	item_textures["bench_wood"] = _make_tex(Color(0.62, 0.40, 0.20), "bench")
	item_textures["bench_forge"] = _make_tex(Color(0.32, 0.32, 0.36), "forge")
	item_textures["bench_stove"] = _make_tex(Color(0.78, 0.80, 0.84), "stove")

	item_textures["solar"] = _make_tex(Color(0.12, 0.28, 0.68), "solar")
	item_textures["wind"] = _make_tex(Color(0.84, 0.88, 0.92), "wind")
	item_textures["battery"] = _make_tex(Color(0.22, 0.64, 0.34), "battery")

func _make_tex(base_col: Color, pattern: String) -> ImageTexture:
	var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(base_col)
	var dark: Color = base_col.darkened(0.32)
	var light: Color = base_col.lightened(0.28)

	# Рамка по периметру
	for i in range(32):
		img.set_pixel(i, 0, dark)
		img.set_pixel(i, 31, dark)
		img.set_pixel(0, i, dark)
		img.set_pixel(31, i, dark)

	match pattern:
		"planks":
			for y in [8, 16, 24]:
				for x in range(1, 31):
					img.set_pixel(x, y, dark)
					img.set_pixel(x, y + 1, light)
		"bricks":
			for y in [8, 16, 24]:
				for x in range(1, 31):
					img.set_pixel(x, y, dark)
			for x in [10, 22]:
				for y in range(1, 8):
					img.set_pixel(x, y, dark)
				for y in range(17, 24):
					img.set_pixel(x, y, dark)
			for x in [6, 18]:
				for y in range(9, 16):
					img.set_pixel(x, y, dark)
				for y in range(25, 31):
					img.set_pixel(x, y, dark)
		"metal":
			for p in [4, 27]:
				for q in [4, 27]:
					img.set_pixel(p, q, light)
					img.set_pixel(p + 1, q, dark)
			for i in range(4, 28):
				img.set_pixel(i, i, light)
		"tiles":
			for i in range(1, 31):
				img.set_pixel(i, 16, dark)
				img.set_pixel(16, i, dark)
		"bed":
			for y in range(4, 12):
				for x in range(5, 27):
					img.set_pixel(x, y, Color(0.94, 0.94, 0.96))
			for y in range(12, 28):
				for x in range(4, 28):
					img.set_pixel(x, y, light)
		"table":
			for y in range(6, 26):
				for x in range(6, 26):
					img.set_pixel(x, y, light)
		"crate":
			for i in range(3, 29):
				img.set_pixel(i, i, dark)
				img.set_pixel(31 - i, i, dark)
		"bench":
			for y in range(10, 22):
				for x in range(3, 29):
					img.set_pixel(x, y, light)
		"forge":
			for y in range(10, 22):
				for x in range(10, 22):
					img.set_pixel(x, y, Color(0.95, 0.38, 0.12))
		"stove":
			for cx in [10, 22]:
				for cy in [10, 22]:
					for dx in range(-2, 3):
						for dy in range(-2, 3):
							img.set_pixel(cx + dx, cy + dy, Color(0.15, 0.15, 0.18))
		"solar":
			for g in [8, 16, 24]:
				for i in range(2, 30):
					img.set_pixel(i, g, Color(0.55, 0.78, 1.0))
					img.set_pixel(g, i, Color(0.55, 0.78, 1.0))
		"wind":
			for i in range(6, 26):
				img.set_pixel(16, i, Color(0.2, 0.25, 0.3))
				img.set_pixel(i, 16, Color(0.2, 0.25, 0.3))
		"battery":
			for y in range(8, 24):
				for x in range(8, 24):
					img.set_pixel(x, y, Color(0.95, 0.85, 0.15))

	return ImageTexture.create_from_image(img)
