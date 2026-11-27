extends Node2D

const TILE_SIZE: float = 32.0
const SELECT_RADIUS: float = 36.0

enum BuildMode { NONE, WALL, BED, STORAGE }

var current_build_mode: BuildMode = BuildMode.NONE
var selected_colonist: Node2D = null
var colonist_targets: Dictionary = {}
var placed_cells: Dictionary = {}

var wood: int = 200
var steel: int = 140

var hud_layer: CanvasLayer
var selection_ring: Line2D
var status_label: Label
var btn_wall: Button
var btn_bed: Button
var btn_storage: Button
var btn_cancel: Button

func _ready() -> void:
	_create_selection_ring()
	_build_mobile_hud()
	_refresh_buttons()

func _is_colony_scene() -> bool:
	var scene: Node = get_tree().current_scene
	return scene != null and scene.name == "Main"

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

	if current_build_mode != BuildMode.NONE:
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

func _try_place_building(world_pos: Vector2) -> void:
	var cell: Vector2i = Vector2i(floori(world_pos.x / TILE_SIZE), floori(world_pos.y / TILE_SIZE))
	if placed_cells.has(cell):
		status_label.text = "Ця клітинка вже зайнята"
		return

	var cost_wood: int = 0
	var cost_steel: int = 0
	var color: Color = Color.WHITE
	var title: String = ""

	match current_build_mode:
		BuildMode.WALL:
			cost_wood = 10
			color = Color(0.55, 0.36, 0.20)
			title = "Стіна"
		BuildMode.BED:
			cost_wood = 25
			color = Color(0.25, 0.52, 0.85)
			title = "Ліжко"
		BuildMode.STORAGE:
			cost_wood = 15
			cost_steel = 10
			color = Color(0.85, 0.72, 0.22)
			title = "Склад"

	if wood < cost_wood or steel < cost_steel:
		status_label.text = "Не вистачає ресурсів (%d дер., %d сталі)" % [cost_wood, cost_steel]
		return

	wood -= cost_wood
	steel -= cost_steel

	var building: ColorRect = ColorRect.new()
	building.size = Vector2(TILE_SIZE - 2.0, TILE_SIZE - 2.0)
	building.position = Vector2(cell.x * TILE_SIZE + 1.0, cell.y * TILE_SIZE + 1.0)
	building.color = color
	building.mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().current_scene.add_child(building)

	placed_cells[cell] = building
	status_label.text = "Побудовано: %s (Дерево: %d | Сталь: %d)" % [title, wood, steel]

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
	root_box.offset_top = -126
	root_box.offset_left = 12
	root_box.offset_right = -12
	root_box.offset_bottom = -10
	root_box.add_theme_constant_override("separation", 6)
	hud_layer.add_child(root_box)

	status_label = Label.new()
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.text = "Тапніть по колоністу або виберіть будівлю знизу"
	status_label.add_theme_font_size_override("font_size", 18)
	root_box.add_child(status_label)

	var panel: PanelContainer = PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 74)
	root_box.add_child(panel)

	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10)
	panel.add_child(hbox)

	btn_wall = _make_hud_button("Стіна (10 дер.)", func(): _set_build_mode(BuildMode.WALL))
	btn_bed = _make_hud_button("Ліжко (25 дер.)", func(): _set_build_mode(BuildMode.BED))
	btn_storage = _make_hud_button("Склад (15д/10с)", func(): _set_build_mode(BuildMode.STORAGE))
	btn_cancel = _make_hud_button("Скасувати", func(): _set_build_mode(BuildMode.NONE))

	hbox.add_child(btn_wall)
	hbox.add_child(btn_bed)
	hbox.add_child(btn_storage)
	hbox.add_child(btn_cancel)

func _make_hud_button(caption: String, on_click: Callable) -> Button:
	var btn: Button = Button.new()
	btn.text = caption
	btn.custom_minimum_size = Vector2(155, 62)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", 17)
	btn.pressed.connect(on_click)
	return btn

func _set_build_mode(mode: BuildMode) -> void:
	current_build_mode = mode
	_refresh_buttons()
	match mode:
		BuildMode.NONE:
			status_label.text = "Режим наказів: тапніть по колоністу"
		BuildMode.WALL:
			status_label.text = "Тапніть по клітинці, щоб поставити Стіну"
		BuildMode.BED:
			status_label.text = "Тапніть по клітинці, щоб поставити Ліжко"
		BuildMode.STORAGE:
			status_label.text = "Тапніть по клітинці, щоб поставити Склад"

func _refresh_buttons() -> void:
	btn_wall.disabled = (current_build_mode == BuildMode.WALL)
	btn_bed.disabled = (current_build_mode == BuildMode.BED)
	btn_storage.disabled = (current_build_mode == BuildMode.STORAGE)
	btn_cancel.visible = (current_build_mode != BuildMode.NONE)
