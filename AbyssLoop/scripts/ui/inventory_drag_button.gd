extends Button

# Lightweight inventory control used only by the expedition equipment modal.
# Left click is handled by the normal Button.pressed callback; right click equips,
# and drag payloads can be dropped onto compatible slots or another bag cell.
var inventory_controller: Node = null
var inventory_item_id: String = ""
var equipment_slot_target: String = ""
var inventory_cell_target: int = -1
var inventory_item_draggable: bool = false

func configure_inventory_control(controller: Node, item_id: String = "", target_slot: String = "", target_cell: int = -1, draggable: bool = false) -> void:
	inventory_controller = controller
	inventory_item_id = item_id
	equipment_slot_target = target_slot
	inventory_cell_target = target_cell
	inventory_item_draggable = draggable
	if not gui_input.is_connected(_on_inventory_gui_input):
		gui_input.connect(_on_inventory_gui_input)

func _on_inventory_gui_input(event: InputEvent) -> void:
	if disabled or not inventory_item_draggable or inventory_item_id.is_empty():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if inventory_controller != null and inventory_controller.has_method("on_inventory_quick_equip"):
			inventory_controller.call("on_inventory_quick_equip", inventory_item_id)
			accept_event()

func _get_drag_data(_at_position: Vector2) -> Variant:
	if disabled or not inventory_item_draggable or inventory_item_id.is_empty():
		return null
	var preview := Label.new()
	preview.text = text
	preview.add_theme_font_size_override("font_size", 12)
	preview.add_theme_color_override("font_color", Color("#f0ecd7"))
	preview.add_theme_color_override("font_shadow_color", Color("#081318"))
	preview.add_theme_constant_override("shadow_offset_x", 1)
	preview.add_theme_constant_override("shadow_offset_y", 1)
	set_drag_preview(preview)
	return {"kind": "abyss_equipment_item", "item_id": inventory_item_id}

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if disabled or typeof(data) != TYPE_DICTIONARY or str(data.get("kind", "")) != "abyss_equipment_item":
		return false
	var source_item_id := str(data.get("item_id", ""))
	if source_item_id.is_empty() or inventory_controller == null:
		return false
	if not equipment_slot_target.is_empty():
		return inventory_controller.has_method("can_inventory_item_equip") and bool(inventory_controller.call("can_inventory_item_equip", source_item_id, equipment_slot_target))
	if inventory_cell_target >= 0:
		return inventory_controller.has_method("can_reorder_inventory_item") and bool(inventory_controller.call("can_reorder_inventory_item", source_item_id, inventory_cell_target))
	return false

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY or inventory_controller == null:
		return
	var source_item_id := str(data.get("item_id", ""))
	if source_item_id.is_empty():
		return
	if not equipment_slot_target.is_empty():
		if inventory_controller.has_method("on_inventory_drag_drop"):
			inventory_controller.call("on_inventory_drag_drop", source_item_id, equipment_slot_target, -1)
	elif inventory_cell_target >= 0 and inventory_controller.has_method("on_inventory_drag_drop"):
		inventory_controller.call("on_inventory_drag_drop", source_item_id, "", inventory_cell_target)
