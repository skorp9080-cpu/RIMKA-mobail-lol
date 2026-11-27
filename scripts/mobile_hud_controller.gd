extends Node2D

const TILE_SIZE: float = 32.0
const SELECT_RADIUS: float = 36.0
const WORK_DISTANCE: float = 38.0

var current_category: String = "orders"
var selected_build_id: String = ""
var selected_colonist: Node2D = null
var colonist_targets: Dictionary = {}
var placed_cells: Dictionary = {}
var placed_floors: Dictionary = {}
var item_textures: Dictionary = {}

# Черга наказів: масив словників { "type": String, "cell": Vector2i, "world_pos": Vector2, "target_node": Node, "marker": Control, "worker": Node2D, "progress": float }
var work_orders: Array = []

var wood: int = 200
var steel: int = 140
var stone: int = 120

var hud_layer: CanvasLayer
var selection_ring: Line2D
var status_label: Label
var category_buttons: Dictionary = {}
var items_hbox: HBoxContainer
var btn_cancel: Button

var categories_order: Array = ["orders", "walls", "floors", "furniture", "workbenches", "power"]
var category_titles: Dictionary = {
	"orders": "Накази",
	"walls": "Стіни",
	"floors": "Підлога",
	"furniture": "Меблі",
	"workbenches": "Верстаки",
	"power": "Енергетика"
}

var build_catalog: Dictionary = {
	"orders": [
		{"id": "order_chop", "name": "Рубати дерево", "wood": 0, "steel": 0, "stone": 0, "is_order": true},
		{"id": "order_mine", "name": "Копати скелю", "wood": 0, "steel": 0, "stone": 0, "is_order": true},
		{"id": "order_deconstruct", "name": "Розібрати", "wood": 0, "steel": 0, "stone": 0, "is_order": true}
	],
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
	_select_category("orders")

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
		if not work_orders.is_empty():
			work_orders.clear()
		return

	# 1. Рух за прямими ручними наказами
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
			pawn_node.global_position += to_target.normalized() * 115.0 * delta

	# 2. Автоматичне виконання черги наказів колоністами
	_process_work_orders(delta)

	# 3. Оновлення рамки виділення
	if is_instance_valid(selected_colonist):
		selection_ring.visible = true
		selection_ring.global_position = selected_colonist.global_position
	else:
		selected_colonist = null
		selection_ring.visible = false

func _process_work_orders(delta: float) -> void:
	if work_orders.is_empty():
		return

	var all_pawns: Array = _get_all_colonists()
	var busy_pawns: Array = []

	for order in work_orders:
		var w: Variant = order.get("worker", null)
		if w != null and is_instance_valid(w) and not colonist_targets.has(w):
			busy_pawns.append(w)
		else:
			order["worker"] = null

	# Призначаємо вільних колоністів на найближчі вільні накази
	for order in work_orders:
		if order.get("worker", null) != null:
			continue
		var target_pos: Vector2 = order["world_pos"]
		var best_pawn: Node2D = null
		var best_dist: float = 999999.0
		for p in all_pawns:
			if p is Node2D and not busy_pawns.has(p) and not colonist_targets.has(p):
				var d: float = (p as Node2D).global_position.distance_to(target_pos)
				if d < best_dist:
					best_dist = d
					best_pawn = p as Node2D
		if best_pawn != null:
			order["worker"] = best_pawn
			busy_pawns.append(best_pawn)

	# Рухаємо призначених колоністів і рахуємо прогрес роботи
	var completed: Array = []
	for order in work_orders:
		var worker: Node2D = order.get("worker", null)
		if worker == null or not is_instance_valid(worker):
			continue
		var target_pos: Vector2 = order["world_pos"]
		var diff: Vector2 = target_pos - worker.global_position
		if diff.length() > WORK_DISTANCE:
			worker.global_position += diff.normalized() * 105.0 * delta
		else:
			var speed: float = 0.55 if str(order["type"]) == "order_chop" else (0.38 if str(order["type"]) == "order_mine" else 0.70)
			order["progress"] = float(order.get("progress", 0.0)) + delta * speed
			if float(order["progress"]) >= 1.0:
				completed.append(order)

	for done_order in completed:
		_finish_work_order(done_order)
		work_orders.erase(done_order)

func _finish_work_order(order: Dictionary) -> void:
	var order_type: String = str(order["type"])
	var cell: Vector2i = order["cell"]
	var marker: Variant = order.get("marker", null)
	if marker != null and is_instance_valid(marker):
		(marker as Node).queue_free()

	var target_node: Variant = order.get("target_node", null)

	match order_type:
		"order_chop":
			if target_node != null and is_instance_valid(target_node):
				(target_node as Node).queue_free()
			wood += 25
			status_label.text = "Дерево зрубано (+25 дер.) | Дер: %d, Сталь: %d, Кам: %d" % [wood, steel, stone]
		"order_mine":
			if target_node != null and is_instance_valid(target_node):
				(target_node as Node).queue_free()
			var ridge: Variant = order.get("extra_node", null)
			if ridge != null and is_instance_valid(ridge):
				(ridge as Node).queue_free()
			stone += 20
			steel += 15
			status_label.text = "Скелю видобуто (+20 кам., +15 сталі) | Дер: %d, Сталь: %d, Кам: %d" % [wood, steel, stone]
		"order_deconstruct":
			if placed_cells.has(cell):
				var b_node: Node = placed_cells[cell]
				var b_id: String = str(b_node.get_meta("build_id", ""))
				_refund_resources(b_id)
				b_node.queue_free()
				placed_cells.erase(cell)
			elif placed_floors.has(cell):
				var f_node: Node = placed_floors[cell]
				var f_id: String = str(f_node.get_meta("build_id", ""))
				_refund_resources(f_id)
				f_node.queue_free()
				placed_floors.erase(cell)
			status_label.text = "Розібрано! | Дер: %d, Сталь: %d, Кам: %d" % [wood, steel, stone]

func _refund_resources(item_id: String) -> void:
	var def: Dictionary = _find_item_def(item_id)
	if def.is_empty():
		return
	wood += int(int(def["wood"]) * 0.5)
	steel += int(int(def["steel"]) * 0.5)
	stone += int(int(def["stone"]) * 0.5)

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
		if selected_build_id.begins_with("order_"):
			_try_assign_order(world_pos)
		else:
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

func _try_assign_order(world_pos: Vector2) -> void:
	var cell: Vector2i = Vector2i(floori(world_pos.x / TILE_SIZE), floori(world_pos.y / TILE_SIZE))
	var cell_center: Vector2 = Vector2((cell.x + 0.5) * TILE_SIZE, (cell.y + 0.5) * TILE_SIZE)

	for existing in work_orders:
		if existing["cell"] == cell:
			status_label.text = "На цю клітинку вже призначено наказ"
			return

	var scene: Node = get_tree().current_scene
	if scene == null:
		return

	if selected_build_id == "order_chop":
		var tree_node: Control = _find_map_object_at_cell(scene, cell, "tree")
		if tree_node == null:
			status_label.text = "Тут немає дерева! Тапніть по зеленому дереву"
			return
		var marker: TextureRect = _create_order_marker(cell, "order_chop")
		work_orders.append({
			"type": "order_chop",
			"cell": cell,
			"world_pos": cell_center,
			"target_node": tree_node,
			"marker": marker,
			"worker": null,
			"progress": 0.0
		})
		status_label.text = "Наказ: зрубати дерево (у черзі: %d)" % work_orders.size()

	elif selected_build_id == "order_mine":
		var rock_node: Control = _find_map_object_at_cell(scene, cell, "rock")
		if rock_node == null:
			status_label.text = "Тут немає скелі! Тапніть по сірій скелі"
			return
		var ridge_node: Control = _find_map_object_at_cell(scene, cell, "ridge")
		var marker: TextureRect = _create_order_marker(cell, "order_mine")
		work_orders.append({
			"type": "order_mine",
			"cell": cell,
			"world_pos": cell_center,
			"target_node": rock_node,
			"extra_node": ridge_node,
			"marker": marker,
			"worker": null,
			"progress": 0.0
		})
		status_label.text = "Наказ: копати скелю (у черзі: %d)" % work_orders.size()

	elif selected_build_id == "order_deconstruct":
		if not placed_cells.has(cell) and not placed_floors.has(cell):
			status_label.text = "Тут немає збудованого об'єкта для розбору"
			return
		var marker: TextureRect = _create_order_marker(cell, "order_deconstruct")
		work_orders.append({
			"type": "order_deconstruct",
			"cell": cell,
			"world_pos": cell_center,
			"target_node": null,
			"marker": marker,
			"worker": null,
			"progress": 0.0
		})
		status_label.text = "Наказ: розібрати будівлю (у черзі: %d)" % work_orders.size()

func _find_map_object_at_cell(root: Node, cell: Vector2i, kind: String) -> Control:
	var cell_rect: Rect2 = Rect2(cell.x * TILE_SIZE, cell.y * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	for child in root.get_children():
		if child is ColorRect:
			var cr: ColorRect = child as ColorRect
			if not cell_rect.has_point(cr.position + cr.size * 0.5):
				continue
			if kind == "tree" and cr.size.x < 24.0:
				return cr
			elif kind == "rock" and cr.name.begins_with("Rock_"):
				return cr
			elif kind == "ridge" and cr.size.x == TILE_SIZE - 6.0 and cr.size.y == TILE_SIZE - 8.0:
				return cr
	return null

func _create_order_marker(cell: Vector2i, tex_id: String) -> TextureRect:
	var marker: TextureRect = TextureRect.new()
	marker.texture = item_textures.get(tex_id)
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.stretch_mode = TextureRect.STRETCH_SCALE
	marker.size = Vector2(TILE_SIZE, TILE_SIZE)
	marker.position = Vector2(cell.x * TILE_SIZE, cell.y * TILE_SIZE)
	marker.modulate = Color(1.0, 1.0, 1.0, 0.85)
	marker.z_index = 20
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().current_scene.add_child(marker)
	return marker

func _get_all_colonists() -> Array:
	var candidates: Array = get_tree().get_nodes_in_group("colonists")
	if candidates.is_empty():
		candidates = _collect_scene_pawns(get_tree().current_scene)
	return candidates

func _find_colonist_near(pos: Vector2) -> Node2D:
	var best_pawn: Node2D = null
	var best_dist: float = SELECT_RADIUS

	for item in _get_all_colonists():
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
	block.set_meta("build_id", selected_build_id)
	if is_floor:
		block.z_index = -1
		placed_floors[cell] = block
	else:
		block.z_index = 2
		placed_cells[cell] = block

	get_tree().current_scene.add_child(block)
	status_label.text = "Збудовано: %s | Дер: %d, Сталь: %d, Кам: %d" % [
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
	status_label.text = "Оберіть наказ або вкладку будівництва знизу"
	status_label.add_theme_font_size_override("font_size", 16)
	root_box.add_child(status_label)

	var tabs_hbox: HBoxContainer = HBoxContainer.new()
	tabs_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs_hbox.add_theme_constant_override("separation", 5)
	root_box.add_child(tabs_hbox)

	for cat_id in categories_order:
		var cid: String = str(cat_id)
		var tab_btn: Button = Button.new()
		tab_btn.text = str(category_titles[cid])
		tab_btn.custom_minimum_size = Vector2(95, 42)
		tab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab_btn.add_theme_font_size_override("font_size", 14)
		tab_btn.pressed.connect(func(): _select_category(cid))
		tabs_hbox.add_child(tab_btn)
		category_buttons[cid] = tab_btn

	btn_cancel = Button.new()
	btn_cancel.text = "✕ Скасувати"
	btn_cancel.custom_minimum_size = Vector2(115, 42)
	btn_cancel.add_theme_font_size_override("font_size", 14)
	btn_cancel.pressed.connect(func(): _select_build_item(""))
	tabs_hbox.add_child(btn_cancel)

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
		var btn: Button = Button.new()

		if bool(entry.get("is_order", false)):
			btn.text = str(entry["name"])
		else:
			var cost_parts: Array = []
			if int(entry["wood"]) > 0:
				cost_parts.append("%d дер." % int(entry["wood"]))
			if int(entry["stone"]) > 0:
				cost_parts.append("%d кам." % int(entry["stone"]))
			if int(entry["steel"]) > 0:
				cost_parts.append("%d сталі" % int(entry["steel"]))
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
		status_label.text = "Режим керування: тапніть по колоністу"
	elif item_id == "order_chop":
		status_label.text = "Тапніть по дереву на карті, щоб призначити рубку"
	elif item_id == "order_mine":
		status_label.text = "Тапніть по скелі на карті, щоб добути камінь і сталь"
	elif item_id == "order_deconstruct":
		status_label.text = "Тапніть по збудованому блоку, щоб розібрати його"
	else:
		var def: Dictionary = _find_item_def(item_id)
		status_label.text = "Обрано: %s — тапніть по карті для побудови" % str(def.get("name", ""))

func _generate_all_textures() -> void:
	item_textures["order_chop"] = _make_order_tex(Color(0.95, 0.55, 0.15), "axe")
	item_textures["order_mine"] = _make_order_tex(Color(0.35, 0.78, 0.95), "pickaxe")
	item_textures["order_deconstruct"] = _make_order_tex(Color(0.92, 0.25, 0.25), "cross")

	item_textures["wall_wood"] = _make_tex(Color(0.56, 0.36, 0.18), "planks")
	item_textures["wall_stone"] = _make_tex(Color(0.52, 0.52, 0.54), "bricks")
	item_textures["wall_steel"] = _make_tex(Color(0.45, 0.54, 0.64), "metal")

	item_textures["floor_wood"] = _make_tex(Color(0.72, 0.52, 0.30), "planks")
	item_textures["floor_stone"] = _make_tex(Color(0.68, 0.68, 0.70), "tiles")
	item_textures["floor_steel"] = _make_tex(Color(0.60, 0.66, 0.72), "tiles")

	item_textures["bed"] = _make_tex(Color(0.24, 0.50, 0.86), "bed")
	item_textures["table"] = _make_tex(Color(0.66, 0.44, 0.22), "table")
	item_t
