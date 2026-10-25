extends Node

const ExpeditionManagerScript = preload("res://scripts/systems/expedition_manager.gd")
const InventorySystemScript = preload("res://scripts/systems/inventory_system.gd")

var _check_count: int = 0
var _failures: Array[String] = []

func _ready() -> void:
	call_deferred("_run_acceptance")

func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if condition:
		print("PASS: ", description)
	else:
		_failures.append(description)
		printerr("FAIL: ", description)

func _make_item(item_id: String, slot: String, rarity: String = "Обычный") -> Dictionary:
	return {
		"id": item_id,
		"name": "QA · " + item_id,
		"slot": slot,
		"rarity": rarity,
		"rank": 1,
		"upgrade_level": 0,
		"power": 10.0,
		"attack": 3,
		"defense": 1,
		"hp": 2
	}

func _item_is_equipped(manager, item_id: String) -> bool:
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var item_value: Variant = manager.equipment.get(str(slot_value), {})
		if typeof(item_value) == TYPE_DICTIONARY and str(item_value.get("id", "")) == item_id:
			return true
	return false

func _run_acceptance() -> void:
	print("Abyss Loop Stage 83 — end-to-end inventory and settlement runtime acceptance")
	if OS.get_environment("ABYSS_LOOP_RUNTIME_QA") != "1":
		printerr("REFUSED: this destructive integration test is only allowed inside the isolated ABYSS_LOOP_RUNTIME_QA profile.")
		get_tree().quit(2)
		return

	if GameState.has_saved_expedition():
		_check(GameState.clear_saved_expedition(), "isolated QA profile clears any leftover run checkpoint before starting")
	else:
		_check(true, "isolated QA profile starts without a previous run checkpoint")

	var manager = ExpeditionManagerScript.new()
	add_child(manager)
	_check(bool(manager.start_run("standard", 83008301)), "a real expedition starts through ExpeditionManager.start_run")
	if not bool(manager.active):
		_finish()
		return

	# Fill the real FIFO backpack with unique equipment instances.
	var slots: Array[String] = ["weapon", "helmet", "armor", "shield", "amulet", "core"]
	var return_prefix: String = "stage83_%d_return" % int(Time.get_ticks_usec())
	var initial_ids: Array[String] = []
	for index in range(1, InventorySystemScript.BACKPACK_CAPACITY + 1):
		var item_id := "%s_%02d" % [return_prefix, index]
		var slot := slots[(index - 1) % slots.size()]
		var rarity := "Редкий" if index == 1 else "Обычный"
		var item := _make_item(item_id, slot, rarity)
		var accepted := bool(manager.call("_store_run_item", item))
		_check(accepted, "backpack accepts the unique equipment instance %02d" % index)
		if accepted:
			initial_ids.append(item_id)
	_check(manager.bag.size() == InventorySystemScript.BACKPACK_CAPACITY, "backpack reaches its configured 12-item capacity")

	var ejections_before_duplicate := int(manager.run_ledger.get("inventory_ejections_count", 0))
	var dust_before_duplicate := int(manager.run_ledger.get("inventory_ejections_dust", 0))
	var bag_before_duplicate: Array = manager.bag.duplicate(true)
	_check(not bool(manager.call("_store_run_item", _make_item("%s_12" % return_prefix, "core"))), "duplicate item IDs are rejected before modifying the bag")
	_check(manager.bag == bag_before_duplicate and int(manager.run_ledger.get("inventory_ejections_count", 0)) == ejections_before_duplicate and int(manager.run_ledger.get("inventory_ejections_dust", 0)) == dust_before_duplicate, "a rejected duplicate neither evicts an item nor grants ejection dust")

	var oldest_item_id := str(initial_ids[0]) if not initial_ids.is_empty() else ""
	var oldest_item := _make_item(oldest_item_id, "weapon", "Редкий")
	var expected_dust := int(manager.inventory_system.get_ejection_echo_dust(oldest_item))
	var return_overflow_id := "%s_13" % return_prefix
	var overflow_item := _make_item(return_overflow_id, "weapon", "Обычный")
	_check(bool(manager.call("_store_run_item", overflow_item)), "a new unique item can enter a full backpack")
	_check(str(manager.last_inventory_evicted_item.get("id", "")) == oldest_item_id, "the FIFO rule ejects the oldest item from the tail")
	_check(int(manager.run_ledger.get("inventory_ejections_count", 0)) == 1, "one valid overflow increments the cumulative ejection count once")
	_check(int(manager.run_ledger.get("inventory_ejections_dust", 0)) == expected_dust and expected_dust > 0, "the overflow contributes the correct non-zero dust value")
	_check(manager.bag.size() == InventorySystemScript.BACKPACK_CAPACITY and manager.find_run_item(oldest_item_id).is_empty(), "overflow keeps capacity fixed and removes the ejected item from the run bag")

	var equip_result: Dictionary = manager.equip_bag_item(return_overflow_id)
	_check(bool(equip_result.get("ok", false)), "the newly acquired weapon can be manually equipped through the production API")
	_check(_item_is_equipped(manager, return_overflow_id) and manager.find_run_item(return_overflow_id).is_empty(), "equip moves the same instance from bag to slot without cloning it")
	_check(manager.save_run_snapshot(), "the inventory/equipment state is checkpointed through the production save path")
	var expected_bag_after_save: Array = manager.bag.duplicate(true)
	var expected_equipment_after_save: Dictionary = manager.equipment.duplicate(true)
	var expected_run_seed: int = int(manager.run_seed)
	manager.set_process(false)
	manager.active = false
	manager.queue_free()
	await get_tree().process_frame

	var restored = ExpeditionManagerScript.new()
	add_child(restored)
	_check(bool(restored.restore_saved_run()), "a second manager restores the saved run through the production restore path")
	if not bool(restored.active):
		_finish()
		return
	_check(bool(restored.paused), "a restored expedition resumes safely paused")
	_check(int(restored.run_seed) == expected_run_seed, "restoration preserves the run seed")
	_check(restored.bag == expected_bag_after_save and restored.equipment == expected_equipment_after_save, "restoration preserves exact bag order and all equipped instances")
	_check(int(restored.run_ledger.get("inventory_ejections_count", 0)) == 1 and int(restored.run_ledger.get("inventory_ejections_dust", 0)) == expected_dust, "restoration preserves cumulative ejection count and dust rather than only the bounded log")
	_check(restored.find_run_item(oldest_item_id).is_empty() and not _item_is_equipped(restored, oldest_item_id), "an ejected item cannot reappear after restore")
	_check(_item_is_equipped(restored, return_overflow_id) and restored.find_run_item(return_overflow_id).is_empty(), "an equipped item remains in exactly one location after restore")

	var all_ids: Dictionary = {}
	for item_value in restored.bag:
		if typeof(item_value) == TYPE_DICTIONARY:
			var item_id := str(item_value.get("id", ""))
			all_ids[item_id] = int(all_ids.get(item_id, 0)) + 1
	for slot_value in InventorySystemScript.EQUIPMENT_SLOTS:
		var item_value: Variant = restored.equipment.get(str(slot_value), {})
		if typeof(item_value) == TYPE_DICTIONARY and not item_value.is_empty():
			var item_id := str(item_value.get("id", ""))
			all_ids[item_id] = int(all_ids.get(item_id, 0)) + 1
	var duplicate_ids: Array[String] = []
	for item_id_value in all_ids.keys():
		if str(item_id_value).is_empty() or int(all_ids[item_id_value]) > 1:
			duplicate_ids.append(str(item_id_value))
	_check(duplicate_ids.is_empty(), "all live bag and equipment instance IDs are unique after restore")

	var dust_before_return := int(GameState.echo_dust)
	var summary_run_id := "%d-%d-%s" % [int(GameState.runs_started), expected_run_seed, str(restored.difficulty_id)]
	restored.run_ledger["scrap"] = 30
	restored.run_ledger["crystals"] = 4
	restored.end_run("return")
	var return_summary: Dictionary = GameState.last_summary.duplicate(true)
	_check(not bool(restored.active) and not GameState.has_saved_expedition(), "safe return completes settlement and clears the saved checkpoint")
	_check(str(return_summary.get("outcome", "")) == "return" and str(return_summary.get("run_id", "")) == summary_run_id, "the debrief summary records the completed run identity")
	_check(int(return_summary.get("earned_echo_dust", 0)) == expected_dust and int(return_summary.get("kept_echo_dust", 0)) == expected_dust, "safe return banks the full cumulative overflow dust")
	_check(int(GameState.echo_dust) - dust_before_return == int(return_summary.get("kept_echo_dust", -1)), "persistent dust changes by exactly the amount committed to the summary")
	_check(GameState.get_armory_item(oldest_item_id).is_empty(), "the ejected item is not restored to the permanent armory")
	_check(not GameState.get_armory_item(return_overflow_id).is_empty(), "equipped loot survives a safe return into the permanent armory")
	_check(not GameState.get_armory_item("%s_12" % return_prefix).is_empty(), "carried backpack loot survives a safe return into the permanent armory")

	var dust_after_settlement := int(GameState.echo_dust)
	var scrap_after_settlement := int(GameState.scrap)
	var crystals_after_settlement := int(GameState.crystals)
	var completed_after_settlement := int(GameState.runs_completed)
	var armory_after_settlement: int = GameState.armory.size()
	var duplicate_summary: Dictionary = GameState.settle_expedition(restored.run_ledger, "return", restored.loop_count, int(restored.hero.get("level", 1)), 0.4, {"run_id": summary_run_id}, "standard", 0, 0, 0, restored.equipment, [])
	_check(bool(duplicate_summary.get("_already_settled", false)), "a duplicate settlement request is explicitly recognized as already committed")
	_check(int(GameState.echo_dust) == dust_after_settlement and int(GameState.scrap) == scrap_after_settlement and int(GameState.crystals) == crystals_after_settlement, "retries cannot double-pay dust or expedition resources")
	_check(int(GameState.runs_completed) == completed_after_settlement and GameState.armory.size() == armory_after_settlement, "retries cannot duplicate campaign completion or armory entries")

	# Second production run exercises defeat policy: equipment is retained but loose bag loot is lost.
	_check(bool(restored.start_run("standard", 83008302)), "a second real expedition starts after a successful settlement")
	if bool(restored.active):
		var defeat_prefix: String = "stage83_%d_defeat" % int(Time.get_ticks_usec())
		for index in range(1, InventorySystemScript.BACKPACK_CAPACITY + 2):
			var item_id := "%s_%02d" % [defeat_prefix, index]
			var slot := slots[(index - 1) % slots.size()]
			var rarity := "Редкий" if index == 1 else "Обычный"
			_check(bool(restored.call("_store_run_item", _make_item(item_id, slot, rarity))), "defeat-path loot acquisition accepts unique item %02d" % index)
		var defeat_raw_dust := int(restored.run_ledger.get("inventory_ejections_dust", 0))
		_check(int(restored.run_ledger.get("inventory_ejections_count", 0)) == 1 and defeat_raw_dust > 0, "defeat-path overflow uses the same cumulative dust ledger")
		var defeat_ejected_id := str(restored.last_inventory_evicted_item.get("id", ""))
		var defeat_equipped_id := "%s_13" % defeat_prefix
		var defeat_equip: Dictionary = restored.equip_bag_item(defeat_equipped_id)
		_check(bool(defeat_equip.get("ok", false)), "defeat-path item can be equipped before ending the run")
		var dust_before_defeat := int(GameState.echo_dust)
		restored.end_run("defeat")
		var defeat_summary: Dictionary = GameState.last_summary.duplicate(true)
		_check(str(defeat_summary.get("outcome", "")) == "defeat" and not GameState.has_saved_expedition(), "defeat settles and removes the checkpoint")
		_check(int(defeat_summary.get("earned_echo_dust", 0)) == defeat_raw_dust, "defeat summary preserves the full raw ejection value for transparency")
		_check(int(defeat_summary.get("kept_echo_dust", 0)) >= 1 and int(defeat_summary.get("kept_echo_dust", 0)) <= defeat_raw_dust, "defeat retains only the configured fraction of overflow dust")
		_check(int(GameState.echo_dust) - dust_before_defeat == int(defeat_summary.get("kept_echo_dust", -1)), "defeat dust payment matches the committed summary exactly")
		_check(not GameState.get_armory_item(defeat_equipped_id).is_empty(), "equipped loot survives defeat into the permanent armory")
		_check(GameState.get_armory_item("%s_12" % defeat_prefix).is_empty(), "unequipped bag loot is lost on defeat rather than banked")
		_check(GameState.get_armory_item(defeat_ejected_id).is_empty(), "ejected loot is neither banked nor duplicated on defeat")
	else:
		_check(false, "the defeat path requires a started second expedition")

	_finish()

func _finish() -> void:
	if _failures.is_empty():
		print("INVENTORY-TO-SETTLEMENT RUNTIME ACCEPTANCE PASSED: %d checks" % _check_count)
		get_tree().quit(0)
	else:
		printerr("INVENTORY-TO-SETTLEMENT RUNTIME ACCEPTANCE FAILED: %d/%d checks failed" % [_failures.size(), _check_count])
		for failure in _failures:
			printerr(" - ", failure)
		get_tree().quit(1)
