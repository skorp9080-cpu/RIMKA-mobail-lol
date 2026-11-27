extends Node2D

const TILE_SIZE: float = 32.0
const TEX_SIZE: int = 128
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

var wood: int = 240
var steel: int = 160
var stone: int = 140
var food: int = 90
var meds: int = 12
var components: int = 8
var stored_power_wh: float = 400.0
var trader_available: bool = false
var turret_cooldown: float = 0.0

var hud_layer: CanvasLayer
var selection_ring: Line2D
var status_label: Label
var resources_label: Label
var category_buttons: Dictionary = {}
var items_hbox: HBoxContainer
var btn_cancel: Button

var categories_order: PackedStringArray = PackedStringArray(["orders", "farm", "walls", "floors", "furniture", "workbenches", "power", "gear", "research", "trade"])
var category_titles: Dictionary = {
	"orders": "Накази",
	"farm": "Ферма",
	"walls": "Стіни",
	"floors": "Підлога",
	"furniture": "Меблі",
	"workbenches": "Верстаки",
	"power": "Енергія",
	"gear": "Зброя",
	"research": "Наука",
	"trade": "Торгівля"
}

var tech_catalog: Array = [
	{"id": "electricity", "name": "Електрика", "cost": 100.0},
	{"id": "turrets", "name": "Авто-турелі", "cost": 160.0},
	{"id": "hydroponics", "name": "Гідропоніка", "cost": 220.0},
	{"id": "armory", "name": "Зброярня", "cost": 180.0}
]

var build_catalog: Dictionary = {
	"orders": [
		{"id": "order_chop", "name": "Рубати дерево", "wood": 0, "steel": 0, "stone": 0, "is_order": true},
		{"id": "order_mine", "name": "Копати скелю", "wood": 0, "steel": 0, "stone": 0, "is_order": true},
		{"id": "order_harvest", "name": "Збирати їжу", "wood": 0, "steel": 0, "stone": 0, "is_order": true},
		{"id": "order_deconstruct", "name": "Розібрати", "wood": 0, "steel": 0, "stone": 0, "is_order": true}
	],
	"farm": [
		{"id": "farm_potato", "name": "Грядка картоплі", "wood": 5, "steel": 0, "stone": 0, "is_floor": false},
		{"id": "hydro_basin", "name": "Гідропоніка", "wood": 0, "steel": 30, "stone": 0, "is_floor": false, "req_tech": "hydroponics"},
		{"id": "campfire", "name": "Багаття", "wood": 20, "steel": 0, "stone": 5, "is_floor": false}
	],
	"walls": [
		{"id": "door_wood", "name": "Дер. двері", "wood": 12, "steel": 0, "stone": 0, "is_floor": false},
		{"id": "door_steel", "name": "Стал. двері", "wood": 0, "steel": 20, "stone": 0, "is_floor": false},
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
		{"id": "med_bed", "name": "Мед. ліжко", "wood": 10, "steel": 25, "stone": 0, "is_floor": false},
		{"id": "table", "name": "Стіл", "wood": 15, "steel": 0, "stone": 0, "is_floor": false},
		{"id": "storage", "name": "Склад", "wood": 15, "steel": 10, "stone": 0, "is_floor": false}
	],
	"workbenches": [
		{"id": "bench_research", "name": "Стіл науки", "wood": 25, "steel": 10, "stone": 0, "is_floor": false},
		{"id": "bench_wood", "name": "Верстак", "wood": 30, "steel": 0, "stone": 0, "is_floor": false},
		{"id": "bench_forge", "name": "Кузня", "wood": 10, "steel": 25, "stone": 15, "is_floor": false},
		{"id": "bench_stove", "name": "Плита", "wood": 15, "steel": 20, "stone": 0, "is_floor": false}
	],
	"power": [
		{"id": "solar", "name": "Сон. панель", "wood": 0, "steel": 25, "stone": 0, "is_floor": false, "req_tech": "electricity"},
		{"id": "wind", "name": "Вітряк", "wood": 15, "steel": 30, "stone": 0, "is_floor": false, "req_tech": "electricity"},
		{"id": "battery", "name": "Акумулятор", "wood": 0, "steel": 20, "stone": 0, "is_floor": false, "req_tech": "electricity"},
		{"id": "heater", "name": "Обігрівач", "wood": 0, "steel": 20, "stone": 0, "is_floor": false, "req_tech": "electricity"},
		{"id": "cooler", "name": "Кондиціонер", "wood": 0, "steel": 30, "stone": 0, "is_floor": false, "req_tech": "electricity"},
		{"id": "turret", "name": "Авто-турель", "wood": 0, "steel": 45, "stone": 0, "is_floor": false, "req_tech": "turrets"}
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

func get_climate_offset() -> int:
	if GameState.active_weather_event == "Сонячний спалах" or stored_power_wh <= 5.0:
		return 0
	var offset: int = 0
	for cell_key in placed_cells.keys():
		var node: Control = placed_cells[cell_key] as Control
		if node == null or not is_instance_valid(node):
			continue
		var bid: String = str(node.get_meta("build_id", ""))
		if bid == "heater":
			offset += 5
		elif bid == "cooler":
			offset -= 5
	return clampi(offset, -15, 15)

func get_power_summary() -> String:
	if GameState.active_weather_event == "Сонячний спалах":
		return "0Wh (Спалах)"
	return "%dWh" % int(stored_power_wh)

func notify_event(text_msg: String) -> void:
	if status_label != null:
		status_label.text = text_msg

func grant_drop_pod() -> void:
	wood += 60
	steel += 45
	food += 35
	meds += 4
	components += 2
	_refresh_resource_bar()
	notify_event("Подія: Вантажні капсули! (+60 дер, +45 сталі, +35 їжі, +4 мед, +2 комп)")

func enable_trader() -> void:
	trader_available = true
	notify_event("Подія: Прибув торговий караван! Відкрийте вкладку «Торгівля»")
	if current_category == "trade":
		_rebuild_item_buttons()

func reward_raid_victory() -> void:
	steel += 25
	meds += 2
	components += 1
	_refresh_resource_bar()
	notify_event("Рейдера переможено! Трофеї: +25 сталі, +2 мед., +1 комп.")

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
		_update_power_and_turrets(sim_delta)
		_update_research(sim_delta)
		_update_colonist_simulation(sim_delta)
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

func _update_power_and_turrets(sim_delta: float) -> void:
	if GameState.active_weather_event == "Сонячний спалах":
		stored_power_wh = 0.0
		return

	var net_gen: float = 0.0
	var turret_nodes: Array = []
	var is_day: bool = GameState.game_time_hours >= 6.0 and GameState.game_time_hours < 20.0

	for cell_key in placed_cells.keys():
		var node: Control = placed_cells[cell_key] as Control
		if node == null or not is_instance_valid(node):
			continue
		var b_id: String = str(node.get_meta("build_id", ""))
		if b_id == "solar" and is_day:
			net_gen += 35.0
		elif b_id == "wind":
			net_gen += 28.0
		elif b_id == "turret":
			net_gen -= 15.0
			turret_nodes.append(node)
		elif b_id == "hydro_basin" or b_id == "heater" or b_id == "cooler":
			net_gen -= 10.0

	stored_power_wh = clampf(stored_power_wh + net_gen * sim_delta, 0.0, 2000.0)

	if stored_power_wh > 10.0 and not turret_nodes.is_empty():
		turret_cooldown -= sim_delta
		if turret_cooldown <= 0.0:
			var enemies: Array = get_tree().get_nodes_in_group("raiders")
			if not enemies.is_empty():
				turret_cooldown = 1.2
				for t_i: int in range(turret_nodes.size()):
					var t_ctrl: Control = turret_nodes[t_i] as Control
					var t_pos: Vector2 = t_ctrl.position + t_ctrl.size * 0.5
					for e_i: int in range(enemies.size()):
						var enemy: Node2D = enemies[e_i] as Node2D
						if enemy != null and is_instance_valid(enemy) and t_pos.distance_to(enemy.global_position) <= 260.0:
							var e_hp: float = float(enemy.get_meta("hp", 100.0)) - 22.0
							enemy.set_meta("hp", e_hp)
							break

func _update_research(sim_delta: float) -> void:
	if GameState.active_research_id == "":
		return
	var benches: int = 0
	for cell_key in placed_cells.keys():
		var node: Control = placed_cells[cell_key] as Control
		if node != null and is_instance_valid(node) and str(node.get_meta("build_id", "")) == "bench_research":
			benches += 1
	var rate: float = 1.2 + float(benches) * 3.5
	GameState.research_progress += sim_delta * rate

	for i: int in range(tech_catalog.size()):
		var tech: Dictionary = tech_catalog[i]
		if str(tech["id"]) == GameState.active_research_id:
			var req_cost: float = float(tech["cost"])
			if GameState.research_progress >= req_cost:
				GameState.research_progress = 0.0
				if not GameState.unlocked_techs.has(GameState.active_research_id):
					GameState.unlocked_techs.append(GameState.active_research_id)
				notify_event("Дослідження завершено: %s!" % str(tech["name"]))
				GameState.active_research_id = ""
				if current_category == "research" or current_category == "gear" or current_category == "power" or current_category == "farm":
					_rebuild_item_buttons()
			break

func _update_colonist_simulation(sim_delta: float) -> void:
	var all_pawns: Array = _get_all_colonists()
	for i: int in range(all_pawns.size()):
		var pawn: Node2D = all_pawns[i] as Node2D
		if pawn == null or not is_instance_valid(pawn):
			continue

		var trait_name: String = str(pawn.get_meta("trait", "Оптиміст"))
		var hp: float = float(pawn.get_meta("hp", 100.0))
		var hunger: float = maxf(0.0, float(pawn.get_meta("hunger", 100.0)) - sim_delta * 0.60)
		var energy: float = float(pawn.get_meta("energy", 100.0))
		var mood: float = float(pawn.get_meta("mood", 85.0))

		if hp < 75.0 and meds > 0:
			meds -= 1
			hp = minf(100.0, hp + 40.0)
			_refresh_resource_bar()
			notify_event("%s перев'язав рани (-1 медикамент)" % pawn.name)

		var bed_pos: Vector2 = _find_nearest_bed(pawn.global_position)
		var is_night: bool = GameState.game_time_hours >= 22.0 or GameState.game_time_hours < 6.0
		if trait_name == "Нічна сова":
			is_night = GameState.game_time_hours >= 4.0 and GameState.game_time_hours < 11.0

		if (energy < 25.0 or (is_night and energy < 75.0)) and bed_pos != Vector2.ZERO and not colonist_targets.has(pawn):
			if pawn.global_position.distance_to(bed_pos) > 12.0:
				pawn.global_position += (bed_pos - pawn.global_position).normalized() * 90.0 * sim_delta
			else:
				energy = minf(100.0, energy + sim_delta * 9.0)
				hp = minf(100.0, hp + sim_delta * 1.5)
		else:
			energy = maxf(0.0, energy - sim_delta * 0.48)

		if hunger < 25.0 and food >= 10:
			food -= 10
			hunger = minf(100.0, hunger + 65.0)
			_refresh_resource_bar()

		var target_mood: float = 75.0
		if trait_name == "Оптиміст":
			target_mood += 12.0
		elif trait_name == "Песиміст":
			target_mood -= 12.0
		if hunger < 20.0:
			target_mood -= 25.0
		if energy < 20.0:
			target_mood -= 20.0
		if GameState.ambient_temp < 5 or GameState.ambient_temp > 34:
			target_mood -= 12.0
		mood = move_toward(mood, clampf(target_mood, 5.0, 100.0), sim_delta * 2.5)

		if mood < 18.0 and randf() < sim_delta * 0.08:
			colonist_targets[pawn] = pawn.global_position + Vector2(randf_range(-160, 160), randf_range(-160, 160))
			mood = 45.0
			notify_event("Психічний зрив: %s блукає в істериці!" % pawn.name)

		pawn.set_meta("hp", hp)
		pawn.set_meta("hunger", hunger)
		pawn.set_meta("energy", energy)
		pawn.set_meta("mood", mood)

		var gear_marks: String = ""
		if bool(pawn.get_meta("has_armor", false)):
			gear_marks += "[Бр]"
		if bool(pawn.get_meta("has_rifle", false)):
			gear_marks += "[Гв]"

		var lbl: Label = pawn.get_node_or_null("NameLabel") as Label
		if lbl != null:
			lbl.text = "%s %s\nХП:%d%% Настрій:%d%%\nЇжа:%d%% Сон:%d%%" % [pawn.name, gear_marks, int(hp), int(mood), int(hunger), int(energy)]

func _find_nearest_bed(from_pos: Vector2) -> Vector2:
	var best_pos: Vector2 = Vector2.ZERO
	var best_dist: float = 999999.0
	for cell_key in placed_cells.keys():
		var node: Control = placed_cells[cell_key] as Control
		if node != null and is_instance_valid(node):
			var bid: String = str(node.get_meta("build_id", ""))
			if bid == "bed" or bid == "med_bed":
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
		var is_hydro: bool = str(block.get_meta("build_id", "")) == "hydro_basin"
		if is_hydro and stored_power_wh <= 5.0:
			continue
		var growth_rate: float = 0.095 if is_hydro else 0.045
		var growth: float = float(plot.get("growth", 0.0)) + sim_delta * growth_rate
		if growth >= 1.0:
			growth = 0.0
			var yield_food: int = 45 if is_hydro else 30
			food += yield_food
			_refresh_resource_bar()
			notify_event("Зібрано врожай (+%d їжі)!" % yield_food)
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
			var w_skill: float = float(worker.get_meta("skill_work", 4))
			var trait_mult: float = 1.25 if str(worker.get_meta("trait", "")) == "Працьовитий" else 1.0
			var base_spd: float = 0.50 if o_type == "order_chop" else (0.35 if o_type == "order_mine" else 0.72)
			var speed: float = base_spd * (1.0 + w_skill * 0.06) * trait_mult
			var prog: float = float(order.get("progress", 0.0)) + sim_delta * speed
			order["progress"] = prog
			var bar_fill: ColorRect = order.get("bar_fill", null) as ColorRect
			if bar_fill != null and is_instance_valid(bar_fill):
				bar_fill.size.x = clampf(prog, 0.0, 1.0) * (TILE_SIZE - 4.0)
			if prog >= 1.0:
				worker.set_meta("skill_work", mini(20, int(w_skill) + 1))
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
			notify_event("Дерево зрубано (+25 дер.)")
		"order_mine":
			if target_node != null and is_instance_valid(target_node):
				target_node.queue_free()
			var ridge: Node = order.get("extra_node", null) as Node
			if ridge != null and is_instance_valid(ridge):
				ridge.queue_free()
			stone += 20
			steel += 15
			if randf() < 0.25:
				components += 1
			notify_event("Скелю видобуто (+20 кам., +15 сталі)")
		"order_harvest":
			var gain: int = 12
			if target_node != null and is_instance_valid(target_node):
				if target_node.name.begins_with("Berry_"):
					gain = 16
				target_node.queue_free()
			food += gain
			notify_event("Зібрано лісовий врожай (+%d їжі)" % gain)
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
			notify_event("Об'єкт розібрано!")
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
		var tr_str: String = str(clicked_pawn.get_meta("trait", ""))
		var sk_w: int = int(clicked_pawn.get_meta("skill_work", 4))
		var sk_c: int = int(clicked_pawn.get_meta("skill_combat", 3))
		notify_event("%s [%s] | Праця:%d Бій:%d — тапніть по землі для руху" % [clicked_pawn.name, tr_str, sk_w, sk_c])
		return

	if is_instance_valid(selected_colonist):
		colonist_targets[selected_colonist] = world_pos
		notify_event("%s прямує до точки..." % selected_colonist.name)

func _try_assign_order(world_pos: Vector2) -> voi
