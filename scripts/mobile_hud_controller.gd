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
var crop_plots: Array = []
var item_textures: Dictionary = {}

var work_orders: Array = []

var wood: int = 200
var steel: int = 140
var stone: int = 120
var food: int = 80

var hud_layer: CanvasLayer
var selection_ring: Line2D
var status_label: Label
var resources_label: Label
var category_buttons: Dictionary = {}
var items_hbox: HBoxContainer
var btn_cancel: Button

var categories_order: PackedStringArray = PackedStringArray(["orders", "farm", "walls", "floors", "furniture", "workbenches", "power"])
var category_titles: Dictionary = {
	"orders": "Накази",
	"farm": "Ферма",
	"walls": "Стіни",
	"floors": "Підлога",
	"furniture": "Меблі",
	"workbenches": "Верстаки",
	"power": "Енергія"
}

var build_catalog: Dictionary = {
	"orders": [
		{"id": "order_chop", "name": "Рубати дерево", "wood": 0, "steel": 0, "stone": 0, "is_order": true},
		{"id": "order_mine", "name": "Копати скелю", "wood": 0, "steel": 0, "stone": 0, "is_order": true},
		{"id": "order_deconstruct", "name": "Розібрати", "wood": 0, "steel": 0, "stone": 0, "is_order": true}
	],
	"farm": [
		{"id": "farm_potato", "name": "Грядка картоплі", "wood": 5, "steel": 0, "stone": 0, "is_floor": false},
		{"id": "campfire", "name": "Багаття", "wood": 20, "steel": 0, "stone": 5, "is_floor": false}
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
	_refresh_resource_bar()

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

	var sim_delta: float = delta * GameState.time_speed
	if sim_delta > 0.0:
		_update_colonist_needs(sim_delta)
		_update_crops(sim_delta)

		for pawn_key in colonist_targets.keys():
			var pawn_node: Node2D = pawn_key as Node2D
			if pawn_node == null or not is_instance_valid(pawn_node):
				colonist_targets.erase(pawn_key)
				continue
			var target: Vector2 = colonist_targets[pawn_key]
			var to_target: Vector2 = target - pawn_node.global_position
			if to_target.length() <= 4.0:
				pawn_node.global_position = target
				colonist_targets.erase(pawn_key)
			else:
				pawn_node.global_position += to_target.normalized() * 115.0 * sim_delta

		_process_work_orders(sim_delta)

	if is_instance_valid(selected_colonist):
		selection_ring.visible = true
		selection_ring.global_position = selected_colonist.global_position
	else:
		selected_colonist = null
		selection_ring.visible = false

func _update_colonist_needs(sim_delta: float) -> void:
	var all_pawns: Array = _get_all_colonists()
	for i: int in range(all_pawns.size()):
		var pawn: Node2D = all_pawns[i] as Node2D
		if pawn == null or not is_instance_valid(pawn):
			continue
		var hunger: float = maxf(0.0, float(pawn.get_meta("hunger", 100.0)) - sim_delta * 0.65)
		var energy: float = float(pawn.get_meta("energy", 100.0))

		var bed_pos: Vector2 = _find_nearest_bed(pawn.global_position)
		var is_night: bool = GameState.game_time_hours >= 22.0 or GameState.game_time_hours < 6.0
		if (energy < 25.0 or (is_night and energy < 75.0)) and bed_pos != Vector2.ZERO and not colonist_targets.has(pawn):
			if pawn.global_position.distance_to(bed_pos) > 12.0:
				pawn.global_position += (bed_pos - pawn.global_position).normalized() * 90.0 * sim_delta
			else:
				energy = minf(100.0, energy + sim_delta * 8.5)
		else:
			energy = maxf(0.0, energy - sim_delta * 0.50)

		if hunger < 25.0 and food >= 10:
			food -= 10
			hunger = minf(100.0, hunger + 65.0)
			_refresh_resource_bar()

		pawn.set_meta("hunger", hunger)
		pawn.set_meta("energy", energy)

		var lbl: Label = pawn.get_node_or_null("NameLabel") as Label
		if lbl != null:
			lbl.text = "%s\nЇжа:%d%% Сон:%d%%" % [pawn.name, int(hunger), int(energy)]

func _find_nearest_bed(from_pos: Vector2) -> Vector2:
	var best_pos: Vector2 = Vector2.ZERO
	var best_dist: float = 999999.0
	for cell_key in placed_cells.keys():
		var node: Control = placed_cells[cell_key] as Control
		if node != null and is_instance_valid(node) and str(node.get_meta("build_id", "")) == "bed":
			var center: Vector2 = node.position + node.size * 0.5
			var d: float = from_pos.distance_to(center)
			if d < best_dist:
				best_dist = d
				best_pos = center
	return best_pos

func _update_crops(sim_delta: float) -> void:
	for i: int in range(crop_plots.size()):
		var plot: Dictionary = crop_plots[i]
		var block: TextureRect = plot.get("node", null) as TextureRect
		if block == null or not is_instance_valid(block):
			continue
		var growth: float = float(plot.get("growth", 0.0)) + sim_delta * 0.045
		if growth >= 1.0:
			growth = 0.0
			food += 30
			_refresh_resource_bar()
			status_label.text = "Зібрано врожай картоплі (+30 їжі)!"
		plot["growth"] = growth
		block.modulate = Color(0.65, 0.55, 0.45).lerp(Color(0.35, 0.95, 0.35), growth)

func _process_work_orders(sim_delta: float) -> void:
	if work_orders.is_empty():
		return

	var all_pawns: Array = _get_all_colonists()
	var busy_pawns: Array = []

	for i: int in range(work_orders.size()):
		var order: Dictionary = work_orders[i]
		var w: Variant = order.get("worker", null)
		if w != null and is_instance_valid(w) and not colonist_targets.has(w):
			busy_pawns.append(w)
		else:
			order["worker"] = null

	for i: int in range(work_orders.size()):
		var order: Dictionary = work_orders[i]
		if order.get("worker", null) != null:
			continue
		var target_pos: Vector2 = order["world_pos"]
		var best_pawn: Node2D = null
		var best_dist: float = 999999.0
		for j: int in range(all_pawns.size()):
			var p_node: Node2D = all_pawns[j] as Node2D
			if p_node != null and not busy_pawns.has(p_node) and not colonist_targets.has(p_node):
				var d: float = p_node.global_position.distance_to(target_pos)
				if d < best_dist:
					best_dist = d
					best_pawn = p_node
		if best_pawn != null:
			order["worker"] = best_pawn
			busy_pawns.append(best_pawn)

	var completed: Array = []
	for i: int in range(work_orders.size()):
		var order: Dictionary = work_orders[i]
		var worker: Node2D = order.get("worker", null) as Node2D
		if worker == null or not is_instance_valid(worker):
			continue
		var target_pos: Vector2 = order["world_pos"]
		var diff: Vector2 = target_pos - worker.global_position
		if diff.length() > WORK_DISTANCE:
			worker.global_position += diff.normalized() * 105.0 * sim_delta
		else:
			var o_type: String = str(order["type"])
			var speed: float = 0.55 if o_type == "order_chop" else (0.38 if o_type == "order_mine" else 0.70)
			var prog: float = float(order.get("progress", 0.0)) + sim_delta * speed
			order["progress"] = prog
			var bar_fill: ColorRect = order.get("bar_fill", null) as ColorRect
			if bar_fill != null and is_instance_valid(bar_fill):
				bar_fill.size.x = clampf(prog, 0.0, 1.0) * (TILE_SIZE - 4.0)
			if prog >= 1.0:
				completed.append(order)

	for i: int in range(completed.size()):
		var done_order: Dictionary = completed[i]
		_finish_work_order(done_order)
		work_orders.erase(done_order)

func _finish_work_order(order: Dictionary) -> void:
	var order_type: String = str(order["type"])
	var cell: Vector2i = order["cell"]
	var marker: Node = order.get("marker", null) as Node
	if marker != null and is_instance_valid(marker):
		marker.queue_free()

	var target_node: Node = order.get("target_node", null) as Node

	match order_type:
		"order_chop":
			if target_node != null and is_instance_valid(target_node):
				target_node.queue_free()
			wood += 25
			status_label.text = "Дерево зрубано (+25 дер.)"
		"order_mine":
			if target_node != null and is_instance_valid(target_node):
				target_node.queue_free()
			var ridge: Node = order.get("extra_node", null) as Node
			if ridge != null and is_instance_valid(ridge):
				ridge.queue_free()
			stone += 20
			steel += 15
			status_label.text = "Скелю видобуто (+20 кам., +15 сталі)"
		"order_deconstruct":
			if placed_cells.has(cell):
				var b_node: Node = placed_cells[cell] as Node
				var b_id: String = str(b_node.get_meta("build_id", ""))
				_refund_resources(b_id)
				b_node.queue_free()
				placed_cells.erase(cell)
			elif placed_floors.has(cell):
				var f_node: Node = placed_floors[cell] as Node
				var f_id: String = str(f_node.get_meta("build_id", ""))
				_refund_resources(f_id)
				f_node.queue_free()
				placed_floors.erase(cell)
			status_label.text = "Об'єкт розібрано!"
	_refresh_resource_bar()

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
	var cell_center: Vector2 = Vector2((float(cell.x) + 0.5) * TILE_SIZE, (float(cell.y) + 0.5) * TILE_SIZE)

	for i: int in range(work_orders.size()):
		var existing: Dictionary = work_orders[i]
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
		var marker_data: Dictionary = _create_order_marker(cell, "order_chop")
		work_orders.append({
			"type": "order_chop",
			"cell": cell,
			"world_pos": cell_center,
			"target_node": tree_node,
			"marker": marker_data["root"],
			"bar_fill": marker_data["fill"],
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
		var marker_data: Dictionary = _create_order_marker(cell, "order_mine")
		work_orders.append({
			"type": "order_mine",
			"cell": cell,
			"world_pos": cell_center,
			"target_node": rock_node,
			"extra_node": ridge_node,
			"marker": marker_data["root"],
			"bar_fill": marker_data["fill"],
			"worker": null,
			"progress": 0.0
		})
		status_label.text = "Наказ: копати скелю (у черзі: %d)" % work_orders.size()

	elif selected_build_id == "order_deconstruct":
		if not placed_cells.has(cell) and not placed_floors.has(cell):
			status_label.text = "Тут немає збудованого об'єкта"
			return
		var marker_data: Dictionary = _create_order_marker(cell, "order_deconstruct")
		work_orders.append({
			"type": "order_deconstruct",
			"cell": cell,
			"world_pos": cell_center,
			"target_node": null,
			"marker": marker_data["root"],
			"bar_fill": marker_data["fill"],
			"worker": null,
			"progress": 0.0
		})
		status_label.text = "Наказ: розібрати будівлю (у черзі: %d)" % work_orders.size()

func _find_map_object_at_cell(root: Node, cell: Vector2i, kind: String) -> Control:
	var cell_rect: Rect2 = Rect2(float(cell.x) * TILE_SIZE, float(cell.y) * TILE_SIZE, TILE_SIZE, TILE_SIZE)
	var children: Array = root.get_children()
	for i: int in range(children.size()):
		var child: Node = children[i]
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

func _create_order_marker(cell: Vector2i, tex_id: String) -> Dictionary:
	var marker: TextureRect = TextureRect.new()
	marker.texture = item_textures.get(tex_id) as Texture2D
	marker.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	marker.stretch_mode = TextureRect.STRETCH_SCALE
	marker.size = Vector2(TILE_SIZE, TILE_SIZE)
	marker.position = Vector2(float(cell.x) * TILE_SIZE, float(cell.y) * TILE_SIZE)
	marker.z_index = 20
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var bar_bg: ColorRect = ColorRect.new()
	bar_bg.size = Vector2(TILE_SIZE - 4.0, 5.0)
	bar_bg.position = Vector2(2.0, -7.0)
	bar_bg.color = Color(0.1, 0.1, 0.1, 0.85)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(bar_bg)

	var bar_fill: ColorRect = ColorRect.new()
	bar_fill.size = Vector2(0.0, 5.0)
	bar_fill.position = Vector2(2.0, -7.0)
	bar_fill.color = Color(0.25, 0.95, 0.35)
	bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marker.add_child(bar_fill)

	get_tree().current_scene.add_child(marker)
	return {"root": marker, "fill": bar_fill}

func _get_all_colonists() -> Array:
	var candidates: Array = get_tree().get_nodes_in_group("colonists")
	if candidates.is_empty():
		candidates = _collect_scene_pawns(get_tree().current_scene)
	return candidates

func _find_colonist_near(pos: Vector2) -> Node2D:
	var best_pawn: Node2D = null
	var best_dist: float = SELECT_RADIUS
	var all_pawns: Array = _get_all_colonists()

	for i: int in range(all_pawns.size()):
		var pawn_node: Node2D = all_pawns[i] as Node2D
		if pawn_node != null and pawn_node != self:
			var d: float = pawn_node.global_position.distance_to(pos)
			if d <= best_dist:
				best_dist = d
				best_pawn = pawn_node
	return best_pawn

func _collect_scene_pawns(root: Node) -> Array:
	var result: Array = []
	if root == null:
		return result
	var children: Array = root.get_children()
	for i: int in range(children.size()):
		var child: Node = children[i]
		if child is Node2D and (child.name == "Олекса" or child.name == "Соломія" or child.name == "Богдан" or child.has_node("NameLabel")):
			result.append(child)
		result.append_array(_collect_scene_pawns(child))
	return result

func _find_item_def(item_id: String) -> Dictionary:
	for cat in build_catalog.keys():
		var list: Array = build_catalog[cat]
		for i: int in range(list.size()):
			var entry: Dictionary = list[i]
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
		status_label.text = "Не вистачає ресурсів!"
		return

	wood -= c_wood
	steel -= c_steel
	stone -= c_stone
	_refresh_resource_bar()

	_spawn_building_block(cell, selected_build_id, is_floor)
	status_label.text = "Збудовано: %s" % str(item_def["name"])

func _spawn_building_block(cell: Vector2i, build_id: String, is_floor: bool) -> void:
	var block: TextureRect = TextureRect.new()
	block.texture = item_textures.get(build_id) as Texture2D
	block.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	block.stretch_mode = TextureRect.STRETCH_SCALE
	block.size = Vector2(TILE_SIZE, TILE_SIZE)
	block.position = Vector2(float(cell.x) * TILE_SIZE, float(cell.y) * TILE_SIZE)
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.set_meta("build_id", build_id)
	if is_floor:
		block.z_index = -1
		placed_floors[cell] = block
	else:
		block.z_index = 2
		placed_cells[cell] = block
		if build_id == "farm_potato":
			crop_plots.append({"cell": cell, "node": block, "growth": 0.0})

	get_tree().current_scene.add_child(block)

func export_save_state() -> Dictionary:
	var saved_buildings: Array = []
	for cell_key in placed_cells.keys():
		var c: Vector2i = cell_key as Vector2i
		var node: Control = placed_cells[cell_key] as Control
		if node != null and is_instance_valid(node):
			saved_buildings.append({"x": c.x, "y": c.y, "id": str(node.get_meta("build_id", "")), "floor": false})
	for floor_key in placed_floors.keys():
		var fc: Vector2i = floor_key as Vector2i
		var fnode: Control = placed_floors[floor_key] as Control
		if fnode != null and is_instance_valid(fnode):
			saved_buildings.append({"x": fc.x, "y": fc.y, "id": str(fnode.get_meta("build_id", "")), "floor": true})
	return {
		"wood": wood,
		"steel": steel,
		"stone": stone,
		"food": food,
		"buildings": saved_buildings
	}

func import_save_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	wood = int(state.get("wood", 200))
	steel = int(state.get("steel", 140))
	stone = int(state.get("stone", 120))
	food = int(state.get("food", 80))
	_refresh_resource_bar
