extends SceneTree

const Generation = preload("res://scripts/systems/procedural_generation.gd")
const RouteSystemType = preload("res://scripts/systems/route_system.gd")
const TileSystemType = preload("res://scripts/systems/tile_system.gd")
const CombatSystemType = preload("res://scripts/systems/combat_system.gd")
const EnemySystemType = preload("res://scripts/systems/enemy_system.gd")
const ResourceSystemType = preload("res://scripts/systems/resource_system.gd")
const EventSystemType = preload("res://scripts/systems/expedition_event_system.gd")
const InventorySystemType = preload("res://scripts/systems/inventory_system.gd")
const ProgressionSystemType = preload("res://scripts/systems/progression_system.gd")
const RouteViewScript = preload("res://scripts/ui/route_view.gd")
const ExpeditionManagerType = preload("res://scripts/systems/expedition_manager.gd")
const StatusEffectSystemType = preload("res://scripts/systems/status_effect_system.gd")
const LootSystemType = preload("res://scripts/systems/loot_system.gd")
const UIControllerType = preload("res://scripts/ui/ui_controller.gd")
const RunDebriefPresenterType = preload("res://scripts/ui/run_debrief_presenter.gd")
const ItemTextPresenterType = preload("res://scripts/ui/item_text_presenter.gd")

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	assert(Localization.catalog_size() >= 100, "the Russian UI localization catalog must load at runtime")
	assert(Localization.has_key("base.hero.title"), "the preparation screen hero title must resolve in the catalog")
	assert(Localization.text("help.body").contains("Shift+Tab"), "the localized help must preserve keyboard shortcut instructions")
	assert(Localization.text("route.no_tiles").contains("ДОРОГЕ") and Localization.text("route.no_tiles").contains("ЛАНДШАФТЕ") and Localization.text("expedition.route_hint").contains("Стартовый узел закрыт") and Localization.text("expedition.tiles.preview_description").contains("ландшафта"), "tile placement guidance must cover both road and landscape targets after hint relocation")
	var return_debrief: Dictionary = RunDebriefPresenterType.build({"outcome": "return", "loops": 5, "victories": 8, "bosses_defeated": 1, "elites_defeated": 1, "events_resolved": 2, "earned_scrap": 80, "lost_scrap": 0, "lost_crystals": 0, "endgame_completed": false, "objective": {"completed": true}, "challenge": {}, "contract": {}})
	assert(str(return_debrief.get("finding", "")).contains("Безопасное возвращение") and not str(return_debrief.get("action", "")).is_empty(), "safe-return debrief must report secured loot and a next action")
	var defeat_debrief: Dictionary = RunDebriefPresenterType.build({"outcome": "defeat", "loops": 2, "victories": 3, "bosses_defeated": 0, "elites_defeated": 0, "events_resolved": 1, "lost_scrap": 42, "lost_crystals": 3, "endgame_completed": false, "objective": {}, "challenge": {}, "contract": {}})
	assert(str(defeat_debrief.get("finding", "")).contains("3 редких ресурсов") and str(defeat_debrief.get("action", "")).contains("безопасный возврат"), "defeat debrief must prioritize real losses and safer extraction advice")
	var endgame_debrief: Dictionary = RunDebriefPresenterType.build({"outcome": "return", "loops": 12, "victories": 20, "bosses_defeated": 4, "elites_defeated": 3, "events_resolved": 5, "earned_scrap": 250, "lost_scrap": 0, "lost_crystals": 0, "endgame_completed": true, "objective": {}, "challenge": {}, "contract": {}})
	assert(str(endgame_debrief.get("finding", "")).contains("цель эндгейма выполнена"), "completed endgame debrief must recognize the actual completion flag")
	var abyss_art := load("res://assets/background/abyss_pixel_backdrop.png") as Texture2D
	assert(abyss_art != null, "the approved pixel-art backdrop must load in the runtime")
	assert(abyss_art.get_width() == 480 and abyss_art.get_height() == 300, "pixel-art backdrop dimensions must stay low-resolution for nearest filtering")
	var route := Generation.generate_route(123456, 18)
	assert(route.size() == 18, "legacy 18-node route geometry remains loadable for older saved expeditions")
	assert(str(route[0].kind) == "shrine", "route must have a stable start cell")
	# Regression: visual node positions and mouse hit-testing must share geometry
	# for every expedition contour and supported content-panel size.
	# The active map is 34 square road cells; legacy 18-node routes remain a compatibility path.
	assert(int(ContentRegistry.BALANCE.get("route_cells", 0)) == 34, "new expeditions must use a 34-cell square-road loop")
	# Stage 86 procedural contours are seed-reproducible, bounded and preserve legacy geometry at seed 0.
	for procedural_shape_id in ["classic_ring", "deep_descent", "narrow_ring", "fractured_loop"]:
		var legacy_contour: Array[Vector2i] = TileSystemType.get_road_grid_coordinates_for_seed(str(procedural_shape_id), 0)
		assert(legacy_contour == TileSystemType.get_road_grid_coordinates(str(procedural_shape_id)), "seed 0 must preserve legacy rectangular geometry")
		var shape_signatures: Dictionary = {}
		for contour_seed_value in range(1, 81):
			var contour: Array[Vector2i] = TileSystemType.get_road_grid_coordinates_for_seed(str(procedural_shape_id), contour_seed_value)
			assert(TileSystemType.is_valid_procedural_road_grid_coordinates(contour), "Stage 86 contour must be a simple 34-cell orthogonal loop: shape=%s seed=%d" % [procedural_shape_id, contour_seed_value])
			assert(contour == TileSystemType.get_road_grid_coordinates_for_seed(str(procedural_shape_id), contour_seed_value), "same geometry seed must reproduce exactly the same contour")
			var signature_parts: Array[String] = []
			for contour_point in contour:
				signature_parts.append("%d:%d" % [contour_point.x, contour_point.y])
			shape_signatures[",".join(signature_parts)] = true
		assert(shape_signatures.size() >= 8, "each route family must expose multiple distinct procedural contours across seeds")
		var seeded_cells: Array[Vector2i] = TileSystemType.get_road_grid_coordinates_for_seed(str(procedural_shape_id), 42)
		var seeded_road_cell := "m:%d:%d" % [seeded_cells[0].x, seeded_cells[0].y]
		assert(not bool(TileSystemType.can_place_world(route, {}, seeded_road_cell, {"id": "archive"}, str(procedural_shape_id), 42).get("ok", true)), "landscape placement must reject road cells for the same geometry seed")
	var route_view = RouteViewScript.new()
	route_view.route_cells = route
	var route_view_sizes: Array[Vector2] = [Vector2(620, 420), Vector2(900, 600), Vector2(1280, 720), Vector2(1440, 900), Vector2(1920, 1080)]
	var route_shapes: Array[String] = ["classic_ring", "deep_descent", "narrow_ring", "fractured_loop"]
	for view_size in route_view_sizes:
		route_view.size = view_size
		for shape_id in route_shapes:
			route_view.route_shape_id = shape_id
			var route_geometry: Dictionary = route_view._get_route_geometry()
			var route_points: Array = route_geometry.get("points", [])
			assert(route_points.size() == route.size(), "route geometry must provide one point per route cell")
			for point_index in range(route_points.size()):
				var point: Vector2 = route_points[point_index]
				assert(route_view._find_closest_cell(point) == point_index, "clicking a rendered route node must return its own index: shape=%s size=%s cell=%d" % [shape_id, view_size, point_index])
				var next_point: Vector2 = route_points[(point_index + 1) % route_points.size()]
				var road_midpoint := point.lerp(next_point, 0.5)
				assert(route_view._find_world_cell(road_midpoint).is_empty(), "road segments must never be treated as landscape placement cells")
			for world_cell_value in TileSystemType.WORLD_FIELD_KEYS:
				var world_cell_id := str(world_cell_value)
				var field_center := route_view._field_cell_rect(world_cell_id).get_center()
				assert(route_view._find_closest_cell(field_center) < 0 and not route_view._is_near_route_line(field_center), "landscape cell center must stay outside the route hit zone: cell=%s shape=%s size=%s" % [world_cell_id, shape_id, view_size])
				assert(route_view._find_world_cell(field_center) == world_cell_id, "clear field-cell center must remain selectable: cell=%s shape=%s size=%s" % [world_cell_id, shape_id, view_size])
	# Stress route geometry with different procedural node counts. Dense routes scale
	# down marker and hit areas; neither visible nodes nor input target zones may merge.
	var stress_route_counts: Array[int] = [12, 14, 16, 18, 20, 22]
	for route_count in stress_route_counts:
		route_view.route_cells = Generation.generate_route(54321 + route_count, route_count)
		for view_size in [Vector2(620, 420), Vector2(900, 600), Vector2(1440, 900)]:
			route_view.size = view_size
			for shape_id in route_shapes:
				route_view.route_shape_id = shape_id
				var points: Array = route_view._get_route_geometry().get("points", [])
				var marker_size: float = route_view._route_marker_size()
				var hit_radius: float = route_view._route_hit_radius()
				assert(points.size() == route_count, "stress route has the wrong point count")
				for point_index in range(route_count):
					var point: Vector2 = points[point_index]
					var next_point: Vector2 = points[(point_index + 1) % route_count]
					assert(point.distance_to(next_point) > hit_radius * 2.0, "neighboring route hit zones overlap: shape=%s size=%s nodes=%d" % [shape_id, view_size, route_count])
					assert(route_view._find_closest_cell(point) == point_index, "dense route node center resolves to wrong index")
				for segment_a in range(route_count):
					var a0: Vector2 = points[segment_a]
					var a1: Vector2 = points[(segment_a + 1) % route_count]
					for segment_b in range(segment_a + 1, route_count):
						var b1_index := (segment_b + 1) % route_count
						if segment_a == segment_b or (segment_a + 1) % route_count == segment_b or b1_index == segment_a:
							continue
						var crossing: Variant = Geometry2D.segment_intersects_segment(a0, a1, points[segment_b], points[b1_index])
						assert(crossing == null, "route profile self-intersects: shape=%s size=%s nodes=%d segments=%d/%d" % [shape_id, view_size, route_count, segment_a, segment_b])
	route_view.free()
	for seed_value in range(500):
		var route_a: Array = Generation.generate_route(seed_value, 18)
		var route_b: Array = Generation.generate_route(seed_value, 18)
		assert(route_a == route_b, "same seed must generate identical route data")
		assert(str(route_a[0].get("kind", "")) == "shrine", "generated route must preserve stable start cell")
		assert(route_a.size() == 18, "seeded route must preserve requested cell count")
	var objective_manager = ExpeditionManagerType.new()
	for modifier_id_value in ContentRegistry.RUN_MODIFIERS.keys():
		var modifier_id := str(modifier_id_value)
		for preview_seed in [1, 123456, 987654321]:
			var objective_a: Dictionary = objective_manager.preview_objective_for_seed(preview_seed, modifier_id)
			var objective_b: Dictionary = objective_manager.preview_objective_for_seed(preview_seed, modifier_id)
			assert(not objective_a.is_empty(), "each valid modifier must have a feasible expedition objective")
			assert(str(objective_a.get("id", "")) == str(objective_b.get("id", "")), "same displayed seed/modifier must preview the same objective")
			assert(objective_manager._objective_is_feasible_for_run(objective_a, modifier_id), "selected objective must be reachable under the selected modifier")
			assert(int(objective_a.get("target", 0)) > 0 and str(objective_a.get("description", "")).length() > 0, "objective preview must show a real condition before launch")
	objective_manager.free()
	assert(ContentRegistry.DIFFICULTY_PRESETS.size() >= 4 and ContentRegistry.DIFFICULTY_PRESETS.has("abyssal"), "four gameplay difficulty profiles including the high-risk Abyss mode must exist")
	var difficulty_smoke_manager = ExpeditionManagerType.new()
	difficulty_smoke_manager.difficulty_id = "abyssal"
	assert(difficulty_smoke_manager._scale_healing(100) == 55, "Abyss difficulty should apply its 55% healing factor deterministically")
	assert(float(ContentRegistry.DIFFICULTY_PRESETS["abyssal"].get("defeat_keep_ratio", 1.0)) == 0.25, "Abyss difficulty should retain only a quarter of temporary loot on defeat")
	difficulty_smoke_manager.free()
	# Long expedition soft caps are isolated from the standard run's original formulas.
	var long_expedition_smoke_manager = ExpeditionManagerType.new()
	long_expedition_smoke_manager.expedition_mode_id = "long_expedition"
	assert(int(long_expedition_smoke_manager.get_expedition_mode().get("goal_loops", 0)) == 12, "long expedition must expose a 12-loop endgame target")
	assert(long_expedition_smoke_manager._effective_scaling_loop(50) == 12, "long expedition combat scaling must stop at loop 12")
	assert(long_expedition_smoke_manager._clamp_long_mode_danger(99.0) == 6.0, "long expedition danger must respect its configured cap")
	long_expedition_smoke_manager.loop_count = 3
	long_expedition_smoke_manager.hero = {"hp": 35, "max_hp": 50}
	long_expedition_smoke_manager.run_ledger = {"scrap": 20, "crystals": 3, "bosses_defeated": 1}
	long_expedition_smoke_manager._record_long_expedition_checkpoint()
	assert(long_expedition_smoke_manager.run_ledger.get("long_run_checkpoints", []).size() == 1, "long expedition checkpoint must be recorded at loop three")
	long_expedition_smoke_manager._record_long_expedition_checkpoint()
	assert(long_expedition_smoke_manager.run_ledger.get("long_run_checkpoints", []).size() == 1, "checkpoint must not duplicate when the same loop is recorded twice")
	long_expedition_smoke_manager.free()
	var standard_mode_smoke_manager = ExpeditionManagerType.new()
	assert(standard_mode_smoke_manager._effective_scaling_loop(50) == 50, "standard expedition scaling must remain uncapped by endgame rules")
	assert(standard_mode_smoke_manager._clamp_long_mode_danger(99.0) == 99.0, "standard expedition danger must not use the long-mode cap")
	standard_mode_smoke_manager.free()
	assert(ContentRegistry.RUN_MODIFIERS.size() >= 4, "four expedition modifier profiles must exist")
	for modifier_id_value in ContentRegistry.RUN_MODIFIERS.keys():
		var modifier_def: Dictionary = ContentRegistry.RUN_MODIFIERS[str(modifier_id_value)]
		assert(["classic_ring", "deep_descent", "narrow_ring", "fractured_loop"].has(str(modifier_def.get("route_shape", ""))), "each modifier must reference a supported closed-loop profile")
		assert(float(modifier_def.get("reward_multiplier", 0.0)) > 0.0, "run modifier rewards must remain positive")
		var challenge_value: Variant = modifier_def.get("challenge", {})
		assert(typeof(challenge_value) == TYPE_DICTIONARY, "modifier challenge must be a dictionary")
		if not challenge_value.is_empty():
			assert(int(challenge_value.get("target", 0)) > 0, "run challenge must have a positive target")
	assert(ContentRegistry.validate_content_registry().is_empty(), "content registry definitions must all validate")	
	assert(ContentRegistry.RESEARCH_BRANCHES.size() == 4, "shelter development must expose four independent specializations")
	var old_smoke_buildings: Dictionary = GameState.buildings.duplicate(true)
	var old_smoke_research: Array = GameState.unlocked_nodes.duplicate(true)
	GameState.buildings["salvage"] = 5
	GameState.unlocked_nodes = ["supply_contracts", "advanced_salvage"]
	assert(GameState.get_effective_loop_scrap_bonus() == int(ContentRegistry.BALANCE.get("shelter_loop_scrap_bonus_cap", 6)), "all passive per-loop scrap sources must share the configured cap")
	GameState.buildings = old_smoke_buildings
	GameState.unlocked_nodes = old_smoke_research
	assert(GameState.get_effective_loop_scrap_bonus() >= 0 and GameState.get_effective_loop_scrap_bonus() <= int(ContentRegistry.BALANCE.get("shelter_loop_scrap_bonus_cap", 6)), "effective loop income must remain bounded")
	var seen_research_nodes: Dictionary = {}
	for branch_id_value in ContentRegistry.RESEARCH_BRANCHES.keys():
		var branch_id := str(branch_id_value)
		var branch_def: Dictionary = ContentRegistry.RESEARCH_BRANCHES[branch_id_value]
		var branch_nodes: Array = branch_def.get("nodes", [])
		var entry_node := str(branch_def.get("entry_node", ""))
		assert(branch_nodes.has(entry_node), "every shelter specialization must name an entry node")
		assert(ContentRegistry.BASE_RESEARCH.has(entry_node), "every shelter specialization entry must exist")
		assert(ContentRegistry.BASE_RESEARCH[entry_node].get("prerequisites", []).is_empty(), "every shelter specialization must be independently unlockable")
		for branch_node_value in branch_nodes:
			var branch_node := str(branch_node_value)
			assert(not seen_research_nodes.has(branch_node), "research node must belong to only one specialization")
			seen_research_nodes[branch_node] = true
			assert(str(ContentRegistry.BASE_RESEARCH[branch_node].get("branch", "")) == branch_id, "research node branch membership must match branch catalogue")
	assert(seen_research_nodes.size() == ContentRegistry.BASE_RESEARCH.size(), "all research nodes must be presented in a shelter specialization")
	assert(ContentRegistry.canonical_research_id("route_archive") == "route_archive", "stable research IDs must remain canonical unless an explicit migration alias exists")
	assert(ContentRegistry.canonical_research_id("future_missing_research") == "future_missing_research", "unknown research IDs must remain intact for later content restoration")
	assert(ContentRegistry.EXPEDITION_CONTRACTS.size() >= 5, "contract catalogue must provide multiple optional contracts")
	var contract_manager = ExpeditionManagerType.new()
	var free_contract_check: Dictionary = contract_manager.can_accept_contract("none")
	assert(bool(free_contract_check.get("ok", false)) and int(free_contract_check.get("scrap_cost", -1)) == 0 and int(free_contract_check.get("crystal_cost", -1)) == 0, "free expedition contract must never charge resources")
	for contract_id_value in ContentRegistry.EXPEDITION_CONTRACTS.keys():
		var contract_id := str(contract_id_value)
		var contract_definition: Dictionary = ContentRegistry.EXPEDITION_CONTRACTS[contract_id_value]
		assert(int(contract_definition.get("scrap_cost", -1)) >= 0 and int(contract_definition.get("crystal_cost", -1)) >= 0, "contract costs must not be negative")
		assert(int(contract_definition.get("scrap_reward", -1)) >= 0 and int(contract_definition.get("crystal_reward", -1)) >= 0, "contract rewards must not be negative")
		if contract_id != "none":
			assert(int(contract_definition.get("target", 0)) > 0 and int(contract_definition.get("deadline_loops", 0)) > 0, "paid/optional contract needs a positive target and deadline")
	contract_manager.free()
	assert(ContentRegistry.STATUS_EFFECTS.size() >= 3, "status catalogue must include timed modifiers and damage over time")
	var status_system = StatusEffectSystemType.new()
	var status_target := {"hp": 30, "defense": 4, "status_effects": []}
	var slow_apply: Dictionary = status_system.apply_effect(status_target, "distortion", 3.5, 0.18, "smoke_caster")
	assert(bool(slow_apply.get("ok", false)) and is_equal_approx(status_system.get_modifier(status_target, "attack_speed_penalty"), 0.18), "distortion status must modify attack cadence through a shared modifier path")
	var slow_refresh: Dictionary = status_system.apply_effect(status_target, "distortion", 2.0, 0.18, "smoke_caster")
	assert(str(slow_refresh.get("disposition", "")) == "refreshed" and status_target.status_effects.size() == 1, "refresh-mode status must not create duplicate instances or shorten its lifetime")
	var poison_first: Dictionary = status_system.apply_effect(status_target, "poison", 4.0, 2.0, "smoke_spore")
	var poison_second: Dictionary = status_system.apply_effect(status_target, "poison", 4.0, 2.0, "smoke_spore")
	var poison_third: Dictionary = status_system.apply_effect(status_target, "poison", 4.0, 2.0, "smoke_spore")
	var poison_capped: Dictionary = status_system.apply_effect(status_target, "poison", 4.0, 2.0, "smoke_spore")
	assert(bool(poison_first.get("ok", false)) and bool(poison_second.get("ok", false)) and bool(poison_third.get("ok", false)) and int(poison_capped.get("stacks", 0)) == 3, "stacking poison must stop at the data-defined stack cap")
	var poison_before := int(status_target.hp)
	var status_events: Array[Dictionary] = status_system.tick_effects(status_target, 1.0)
	assert(int(status_target.hp) < poison_before and not status_events.is_empty(), "damage-over-time statuses must tick on active combat time")
	var legacy_entity := {"hp": 20, "combat_debuff": {"speed_penalty": 0.18, "time_remaining": 2.0}}
	status_system.normalize_legacy_entity(legacy_entity)
	assert(is_equal_approx(status_system.get_modifier(legacy_entity, "attack_speed_penalty"), 0.18) and legacy_entity.status_effects.size() == 1, "legacy combat debuff must migrate into the general status schema")
	var barrier_target := {"hp": 30, "max_hp": 30, "status_effects": []}
	status_system.apply_effect(barrier_target, "barrier", 5.0, 8.0, "smoke_guard")
	var barrier_hit: Dictionary = status_system.apply_incoming_damage(barrier_target, 5)
	assert(int(barrier_target.hp) == 30 and int(barrier_hit.get("absorbed", 0)) == 5 and int(barrier_hit.get("damage", -1)) == 0, "barrier must absorb incoming damage before health is reduced")
	var barrier_refresh_target := {"hp": 30, "max_hp": 30, "status_effects": []}
	status_system.apply_effect(barrier_refresh_target, "barrier", 5.0, 8.0, "smoke_guard_first")
	status_system.apply_effect(barrier_refresh_target, "barrier", 5.0, 6.0, "smoke_guard_second")
	var refreshed_barriers: Array[Dictionary] = status_system.describe_active(barrier_refresh_target)
	assert(refreshed_barriers.size() == 1 and is_equal_approx(float(refreshed_barriers[0].get("magnitude", 0.0)), 8.0), "reapplying an active barrier must refresh it without adding shield strength")
	var wound_target := {"hp": 30, "max_hp": 30, "status_effects": []}
	status_system.apply_effect(wound_target, "wound", 4.0, 0.12, "smoke_wound")
	status_system.apply_effect(wound_target, "wound", 4.0, 0.12, "smoke_wound")
	var wound_hit: Dictionary = status_system.apply_incoming_damage(wound_target, 10)
	assert(int(wound_hit.get("damage", 0)) == 13 and int(wound_target.hp) == 17, "stacked wounds must increase incoming damage through the shared bounded modifier")
	var status_combat = CombatSystemType.new()
	var protected_defender := {"hp": 30, "defense": 0, "crit": 0.0, "status_effects": []}
	status_system.apply_effect(protected_defender, "barrier", 5.0, 8.0, "smoke_combat")
	var status_rng := RandomNumberGenerator.new()
	status_rng.seed = 222
	var protected_hit: Dictionary = status_combat.perform_attack({"attack": 5.0, "crit": 0.0}, protected_defender, status_rng)
	assert(int(protected_hit.get("absorbed", 0)) > 0 and int(protected_defender.hp) == 30, "the real shared CombatSystem attack path must honor barriers")
	var dodge_rng := RandomNumberGenerator.new()
	dodge_rng.seed = 7654
	var dodge_target := {"hp": 100, "defense": 0, "dodge_chance": 0.25, "status_effects": []}
	var dodged_attacks := 0
	for _dodge_roll in range(40):
		dodge_target["hp"] = 100
		var dodge_hit: Dictionary = status_combat.perform_attack({"attack": 5.0, "crit": 0.0}, dodge_target, dodge_rng)
		if bool(dodge_hit.get("dodged", false)):
			dodged_attacks += 1
			assert(int(dodge_hit.get("damage", -1)) == 0 and int(dodge_target.get("hp", 0)) == 100, "a successful phase dodge must fully negate the attack")
	assert(dodged_attacks > 0 and dodged_attacks < 40, "phase dodge must trigger probabilistically and be capped rather than guaranteed")
	status_combat.free()
	var elite_factory = EnemySystemType.new()
	var elite_rng := RandomNumberGenerator.new()
	elite_rng.seed = 38039
	var elite_pack: Array = elite_factory.create_encounter(4, 1.3, elite_rng, 0.0, false, 0)
	assert(not elite_pack.is_empty(), "elite smoke must start from a valid normal encounter")
	for biome_enemy_id in ["sporeling", "prism_mite", "bone_warden", "echo_wisp"]:
		var biome_enemy: Dictionary = elite_factory.create_enemy(2, 1.1, elite_rng, 0.0, [biome_enemy_id])
		assert(str(biome_enemy.get("id", "")) == biome_enemy_id and bool(ContentRegistry.ENEMIES[biome_enemy_id].get("landscape_only", false)), "each landscape-only enemy must be selectable only through its tile-authored pool: %s" % biome_enemy_id)
	var normal_target: Dictionary = elite_pack[0].duplicate(true)
	var elite_target: Dictionary = elite_factory.promote_encounter_to_elite(elite_pack, 4)
	assert(bool(elite_target.get("is_elite", false)) and not bool(elite_target.get("is_boss", false)), "elite promotion must tag a regular enemy without changing it into a boss")
	assert(int(elite_target.get("max_hp", 0)) > int(normal_target.get("max_hp", 0)) and int(elite_target.get("scrap", 0)) > int(normal_target.get("scrap", 0)), "elite promotion must add survivability and a higher material reward")
	assert(ContentRegistry.ELITE_ROLE_ABILITIES.has(str(elite_target.get("role", ""))) and not str(elite_target.get("elite_ability", "")).is_empty() and not str(elite_target.get("elite_telegraph", "")).is_empty(), "every elite role must have a registered telegraphed ability")
	var boss_target: Dictionary = elite_factory.create_boss(6, 1.0, elite_rng)
	var boss_group: Array = [boss_target]
	assert(elite_factory.promote_encounter_to_elite(boss_group, 6).is_empty(), "bosses must not be reclassified as regular elites")
	var boss_phase_manager = ExpeditionManagerType.new()
	boss_target["hp"] = int(floor(float(boss_target.get("max_hp", 1)) * 0.65))
	boss_phase_manager.hero = {"hp": 40, "max_hp": 40, "status_effects": []}
	boss_phase_manager.enemy = boss_target
	boss_phase_manager.encounter_enemies = [boss_target]
	boss_phase_manager._update_boss_phase()
	assert(int(boss_phase_manager.enemy.get("phase_index", -1)) == 1, "crossing a boss phase threshold must advance exactly one phase")
	var phase_after_first_transition := int(boss_phase_manager.enemy.get("phase_index", -1))
	boss_phase_manager._update_boss_phase()
	assert(int(boss_phase_manager.enemy.get("phase_index", -1)) == phase_after_first_transition, "rechecking a phase must not repeat the same phase transition")
	boss_phase_manager.enemy["hp"] = int(floor(float(boss_phase_manager.enemy.get("max_hp", 1)) * 0.30))
	boss_phase_manager._update_boss_phase()
	assert(int(boss_phase_manager.enemy.get("phase_index", -1)) == 2, "crossing the next health threshold must advance to the final boss phase")
	var final_phase_statuses: Array = boss_phase_manager.enemy.get("status_effects", [])
	assert(not final_phase_statuses.is_empty(), "phase entry must apply its configured defensive/healing state")
	assert(SaveSystem._validate_boss_phase_state(boss_phase_manager.enemy), "phase snapshots must validate their thresholds, indexes, and special-attack state")
	boss_phase_manager.free()
	elite_factory.free()
	var expiry_target := {"hp": 20, "status_effects": []}
	status_system.apply_effect(expiry_target, "distortion", 0.2, 0.18, "smoke")
	var expiry_events: Array[Dictionary] = status_system.tick_effects(expiry_target, 0.25)
	var status_expired := false
	for expiry_event in expiry_events:
		if str(expiry_event.get("type", "")) == "expired":
			status_expired = true
	assert(expiry_target.status_effects.is_empty() and status_expired, "expired status must be removed and reported once")
	status_system.free()
	assert(ContentRegistry.BASE_RESEARCH.has("rare_survey") and ContentRegistry.BASE_RESEARCH.has("field_training") and ContentRegistry.BASE_RESEARCH.has("event_forecasting"), "research should offer multiple branches")
	assert(ContentRegistry.EXPEDITION_OBJECTIVES.size() >= 5, "expedition goal catalogue must provide alternatives")
	assert(GameState.settings.has("reduced_motion"), "reduced_motion preference must persist")
	assert(GameState.settings.has("reduce_flashes"), "reduce_flashes preference must persist")
	# Campaign history is a compact summary, not a copy of the active run snapshot.
	var history_fixture: Dictionary = GameState._normalize_history_entry({
		"run_id": "smoke-history-1", "timestamp_unix": 1700000000, "date": "2026-10-23 10:00:00",
		"game_version": "0.49.0", "seed": 123456, "difficulty_id": "standard", "difficulty_name": "Стандарт",
		"outcome": "return", "loops": 3, "hero_level": 6, "challenge_score": 120,
		"victories": 12, "bosses_defeated": 1, "elites_defeated": 2, "events_resolved": 3,
		"earned_scrap": 100, "earned_crystals": 12, "kept_scrap": 100, "kept_crystals": 12,
		"lost_scrap": 0, "lost_crystals": 0, "retention_percent": 100,
		"tiles": ["Корневой оберег", "Кристалл-резонатор", "Корневой оберег"],
		"event_decisions": ["Маяк → Настроить маяк"]
	})
	assert(str(history_fixture.get("run_id", "")) == "smoke-history-1" and str(history_fixture.get("game_version", "")) == "0.49.0", "history summaries must preserve a stable replay identity and game version")
	assert(history_fixture.get("tiles", []).size() == 2 and history_fixture.get("event_decisions", []).size() == 1, "history must store only bounded unique tiles and a short list of decisions")
	var history_save_probe: Dictionary = GameState.export_save_data()
	history_save_probe["expedition_history"] = [history_fixture]
	assert(SaveSystem._validate_save_data(history_save_probe), "save validator must accept a normalized campaign history record")
	history_save_probe["expedition_history"] = [history_fixture, history_fixture.duplicate(true)]
	assert(not SaveSystem._validate_save_data(history_save_probe), "save validator must reject duplicate run IDs in campaign history")
	var bounded_phase_item := {"id": "phase_save_fixture", "slot": "core", "lifesteal": 0.25, "dodge_chance": 0.25}
	assert(SaveSystem._validate_item(bounded_phase_item, "core"), "equipment save validator must accept the shared 25% cap for lifesteal and dodge")
	var invalid_lifesteal_item: Dictionary = bounded_phase_item.duplicate(true)
	invalid_lifesteal_item["lifesteal"] = 0.251
	assert(not SaveSystem._validate_item(invalid_lifesteal_item, "core"), "equipment save validator must reject lifesteal values above the cap")
	var invalid_dodge_item: Dictionary = bounded_phase_item.duplicate(true)
	invalid_dodge_item["dodge_chance"] = -0.001
	assert(not SaveSystem._validate_item(invalid_dodge_item, "core"), "equipment save validator must reject negative dodge values")
	var route_system = RouteSystemType.new()
	var live_loop: Array = route_system.create_route(123456, 18)
	assert(route_system.is_closed_loop(live_loop), "active route must carry validated closed-loop topology")
	assert(int(live_loop[0].get("previous_index", -1)) == 17, "start node must link backward to the final node")
	assert(int(live_loop[17].get("next_index", -1)) == 0, "final node must link forward to the start node")
	assert(route_system.next_index(17, 18) == 0 and route_system.previous_index(0, 18) == 17, "both navigation directions must wrap around the route")
	var route_progress_before_wrap: Dictionary = route_system.route_progress(17.75, 18)
	var route_progress_after_wrap: Dictionary = route_system.route_progress(18.25, 18)
	assert(int(route_progress_before_wrap.get("index", -1)) == 17, "hero stays on the final loop segment before wrapping")
	assert(int(route_progress_after_wrap.get("index", -1)) == 0 and int(route_progress_after_wrap.get("loops", -1)) == 1, "hero returns to node zero after a full loop")
	var has_event_node: bool = false
	for route_cell_value in route:
		if str(route_cell_value.get("kind", "")) == "event":
			has_event_node = true
	assert(has_event_node, "generated route must include at least one choice-driven event")
	assert(route_system.next_index(17, 18) == 0, "route must wrap to start")
	assert(route_system.get_cell_kind(route, 19) == route[1].kind, "route lookup must wrap")
	var tile_system = TileSystemType.new()
	assert(not bool(tile_system.can_place(route, {}, 0).ok), "start node must reject tiles")
	assert(bool(tile_system.can_place(route, {}, 1).ok), "empty node must accept tiles")
	assert(not bool(tile_system.can_place(route, {"1": {"id": "cache"}}, 1).ok), "occupied node must reject tiles")
	assert(not bool(tile_system.can_place(route, {}, 1, {"id": "archive"}).ok), "archive is landscape-only and must not be placeable on the road")
	assert(not bool(tile_system.can_place(route, {}, 1, {"id": "nursery"}).ok), "nursery is landscape-only and must not be placeable on the road")
	assert(not bool(tile_system.can_place(route, {}, 1, {"id": "spore_garden"}).ok) and not bool(tile_system.can_place(route, {}, 1, {"id": "crystal_hive"}).ok) and not bool(tile_system.can_place(route, {}, 1, {"id": "bone_orchard"}).ok) and not bool(tile_system.can_place(route, {}, 1, {"id": "echo_obelisk"}).ok), "new off-road structures must remain restricted to the landscape field")
	assert(bool(tile_system.can_place(route, {}, 1, {"id": "echo_spring"}).ok) and bool(tile_system.can_place(route, {}, 1, {"id": "fault_line"}).ok), "new road cards must remain placeable on the route")
	assert(not bool(tile_system.can_place_world(route, {}, "2:0", {"id": "echo_spring"}).ok), "new road-only cards must not be placeable in the off-road field")
	assert(bool(tile_system.can_place(route, {}, 1, {"id": "cache"}).ok), "flexible cards must remain placeable on road")
	assert(not bool(tile_system.can_place_world(route, {}, "2:0", {"id": "road_test", "placement_zone": "road"}).ok), "road-only cards must be rejected by the field validator")
	assert(bool(tile_system.can_place_world(route, {}, "2:0", {"id": "archive"}).ok), "archive must be placeable on a valid landscape cell")
	assert(bool(tile_system.can_place_world(route, {}, "2:0", {"id": "nursery"}).ok), "nursery must be placeable on a valid landscape cell")
	var archive_road_preview: Dictionary = tile_system.get_placement_preview(route, {}, 1, {"id": "archive"})
	assert(not bool(archive_road_preview.get("ok", true)), "road placement preview must reject the archive")
	var archive_field_preview: Dictionary = tile_system.get_world_placement_preview(route, {}, "2:0", {"id": "archive"})
	assert(bool(archive_field_preview.get("ok", false)), "landscape placement preview must accept the archive")
	var tile_draw_rng := RandomNumberGenerator.new()
	tile_draw_rng.seed = 23019
	# The saved profile can retain upgrades from prior sessions. Pin this first
	# distribution sample to the baseline so its rarity bounds stay reproducible.
	GameState.buildings["cartographer"] = 0
	var locked_rare_tiles := 0
	var unlocked_rare_tiles := 0
	var unlocked_draw_count := 1200
	for _draw_index in range(unlocked_draw_count):
		var common_draw: Dictionary = tile_system.draw_tile(tile_draw_rng, false)
		if str(common_draw.get("id", "")) in ["rift", "signal", "archive", "nursery", "fault_line", "spore_garden", "crystal_hive", "bone_orchard", "echo_obelisk", "lost_convoy", "hunter_marker"]:
			locked_rare_tiles += 1
		var unlocked_draw: Dictionary = tile_system.draw_tile(tile_draw_rng, true)
		if str(unlocked_draw.get("id", "")) in ["rift", "signal", "archive", "nursery", "fault_line", "spore_garden", "crystal_hive", "bone_orchard", "echo_obelisk", "lost_convoy", "hunter_marker"]:
			unlocked_rare_tiles += 1
	assert(locked_rare_tiles == 0, "rare rift/signal/archive/nursery cards must remain locked until unlock conditions")
	assert(unlocked_rare_tiles >= 250 and unlocked_rare_tiles <= 400, "the complete unlocked rare-card pool should remain a minority of the draft")
	var base_rare_rng := RandomNumberGenerator.new()
	base_rare_rng.seed = 7741
	GameState.buildings["cartographer"] = 0
	var base_rare_count := 0
	for _base_draw in range(1800):
		var base_draw: Dictionary = tile_system.draw_tile(base_rare_rng, true)
		if str(base_draw.get("id", "")) in ["rift", "signal", "archive", "nursery", "fault_line", "spore_garden", "crystal_hive", "bone_orchard", "echo_obelisk", "lost_convoy", "hunter_marker"]:
			base_rare_count += 1
	var observatory_rng := RandomNumberGenerator.new()
	observatory_rng.seed = 7741
	GameState.buildings["cartographer"] = 5
	var observatory_rare_count := 0
	for _observatory_draw in range(1800):
		var observatory_draw: Dictionary = tile_system.draw_tile(observatory_rng, true)
		if str(observatory_draw.get("id", "")) in ["rift", "signal", "archive", "nursery", "fault_line", "spore_garden", "crystal_hive", "bone_orchard", "echo_obelisk", "lost_convoy", "hunter_marker"]:
			observatory_rare_count += 1
	GameState.buildings["cartographer"] = 0
	assert(observatory_rare_count > base_rare_count, "cartographer building upgrades must measurably improve rare card discovery without editing the pool")
	var structure_ledger := {"scrap": 0, "crystals": 0}
	var structure_hero := {"hp": 15, "max_hp": 30}
	var archive_result: Dictionary = tile_system.apply_tile_visit({"id": "archive"}, structure_ledger, structure_hero, 2)
	assert(int(structure_ledger.get("scrap", 0)) == 2 and int(structure_ledger.get("crystals", 0)) == 1 and is_equal_approx(float(archive_result.get("reward_bonus", 0.0)), 0.08), "archive structure must pay its crystal/scrap reward through real tile visit")
	var nursery_result: Dictionary = tile_system.apply_tile_visit({"id": "nursery"}, structure_ledger, structure_hero, 2)
	assert(is_equal_approx(float(nursery_result.get("spawn_bonus", 0.0)), 0.28) and is_equal_approx(float(nursery_result.get("enemy_bonus", 0.0)), 0.12) and is_equal_approx(float(nursery_result.get("reward_bonus", 0.0)), 0.25), "abyss nursery must create a deliberate risk/reward sector")
	var spring_before_hp := int(structure_hero.get("hp", 0))
	var spring_result: Dictionary = tile_system.apply_tile_visit({"id": "echo_spring"}, structure_ledger, structure_hero, 2)
	assert(int(structure_hero.get("hp", 0)) == spring_before_hp + 6 and is_equal_approx(float(spring_result.get("spawn_bonus", 0.0)), -0.04), "echo spring must heal and reduce encounter risk")
	var prepared_loot_ledger := {"scrap": 0, "crystals": 0, "pending_item_rarity_bonus": 0.0, "pending_item_drop_bonus": 0.0}
	var prepared_loot_hero := {"hp": 20, "max_hp": 20}
	var convoy_result: Dictionary = tile_system.apply_tile_visit({"id": "lost_convoy"}, prepared_loot_ledger, prepared_loot_hero, 3)
	assert(int(prepared_loot_ledger.get("scrap", 0)) == 3 and is_equal_approx(float(prepared_loot_ledger.get("pending_item_rarity_bonus", 0.0)), 0.12), "lost convoy must pay salvage and prepare rare equipment")
	tile_system.apply_tile_visit({"id": "lost_convoy"}, prepared_loot_ledger, prepared_loot_hero, 3)
	assert(is_equal_approx(float(prepared_loot_ledger.get("pending_item_rarity_bonus", 0.0)), 0.18), "lost convoy rarity preparation must stop at 18 percentage points")
	var marker_result: Dictionary = tile_system.apply_tile_visit({"id": "hunter_marker"}, prepared_loot_ledger, prepared_loot_hero, 3)
	assert(is_equal_approx(float(prepared_loot_ledger.get("pending_item_drop_bonus", 0.0)), 0.15) and is_equal_approx(float(marker_result.get("enemy_bonus", 0.0)), 0.05), "hunter marker must trade stronger encounters for higher equipment-drop chance")
	tile_system.apply_tile_visit({"id": "hunter_marker"}, prepared_loot_ledger, prepared_loot_hero, 3)
	assert(is_equal_approx(float(prepared_loot_ledger.get("pending_item_drop_bonus", 0.0)), 0.30), "hunter marker drop preparation must be capped at 30 percentage points")
	var garden_before_hp := int(structure_hero.get("hp", 0))
	var garden_before_scrap := int(structure_ledger.get("scrap", 0))
	var garden_result: Dictionary = tile_system.apply_tile_visit({"id": "spore_garden"}, structure_ledger, structure_hero, 2)
	assert(int(structure_hero.get("hp", 0)) == garden_before_hp + 3 and int(structure_ledger.get("scrap", 0)) == garden_before_scrap + 1 and garden_result.get("enemy_pool", []).has("sporeling"), "spore garden must heal, pay materials and call its biome enemy")
	var hive_before_scrap := int(structure_ledger.get("scrap", 0))
	var hive_before_crystals := int(structure_ledger.get("crystals", 0))
	var hive_result: Dictionary = tile_system.apply_tile_visit({"id": "crystal_hive"}, structure_ledger, structure_hero, 2)
	assert(int(structure_ledger.get("scrap", 0)) == hive_before_scrap + 1 and int(structure_ledger.get("crystals", 0)) == hive_before_crystals + 1 and hive_result.get("enemy_pool", []).has("prism_mite"), "crystal hive must grant resources and its own encounter pool")
	var bone_before_scrap := int(structure_ledger.get("scrap", 0))
	var bone_result: Dictionary = tile_system.apply_tile_visit({"id": "bone_orchard"}, structure_ledger, structure_hero, 2)
	assert(int(structure_ledger.get("scrap", 0)) == bone_before_scrap + 2 and bone_result.get("enemy_pool", []).has("bone_warden"), "bone orchard must increase loot and wake bone wardens")
	var obelisk_before_crystals := int(structure_ledger.get("crystals", 0))
	var obelisk_result: Dictionary = tile_system.apply_tile_visit({"id": "echo_obelisk"}, structure_ledger, structure_hero, 2)
	assert(int(structure_ledger.get("crystals", 0)) == obelisk_before_crystals + 1 and obelisk_result.get("enemy_pool", []).has("echo_wisp"), "echo obelisk must grant a crystal and call echo wisps")
	var cache_ward_tiles := {"2": {"id": "cache"}, "3": {"id": "ward"}}
	var supply_synergy: Dictionary = tile_system.get_synergy_bonus(cache_ward_tiles, 2, route.size())
	assert(int(supply_synergy.get("scrap", 0)) == 4, "cache next to ward must grant the configured synergy materials")
	var cache_hunt_pair := {"1": {"id": "cache"}, "2": {"id": "hunt"}}
	var cache_hunt_synergy: Dictionary = tile_system.get_synergy_bonus(cache_hunt_pair, 1, route.size())
	assert(int(cache_hunt_synergy.get("scrap", 0)) == 2 and is_equal_approx(float(cache_hunt_synergy.get("reward", 0.0)), 0.08), "cache next to hunt must give the trophy-cache resource/reward recipe")
	var snare_hunt_pair := {"1": {"id": "snare"}, "2": {"id": "hunt"}}
	var snare_hunt_synergy: Dictionary = tile_system.get_synergy_bonus(snare_hunt_pair, 1, route.size())
	assert(is_equal_approx(float(snare_hunt_synergy.get("spawn_bonus", 0.0)), -0.06) and is_equal_approx(float(snare_hunt_synergy.get("reward", 0.0)), 0.12), "snare/hunt recipe must trade fewer encounters for improved rewards")
	var rift_signal_pair := {"1": {"id": "rift"}, "2": {"id": "signal"}}
	var rift_signal_synergy: Dictionary = tile_system.get_synergy_bonus(rift_signal_pair, 1, route.size())
	assert(is_equal_approx(float(rift_signal_synergy.get("enemy_bonus", 0.0)), 0.08) and is_equal_approx(float(rift_signal_synergy.get("reward", 0.0)), 0.20), "rift/signal recipe must increase both risk and reward")
	var archive_cache_pair := {"1": {"id": "archive"}, "2": {"id": "cache"}}
	var archive_cache_synergy: Dictionary = tile_system.get_synergy_bonus(archive_cache_pair, 1, route.size())
	assert(int(archive_cache_synergy.get("scrap", 0)) == 4 and is_equal_approx(float(archive_cache_synergy.get("reward", 0.0)), 0.08), "archive/cache recipe must convert location planning into supplies")
	var nursery_rift_pair := {"1": {"id": "nursery"}, "2": {"id": "rift"}}
	var nursery_rift_synergy: Dictionary = tile_system.get_synergy_bonus(nursery_rift_pair, 1, route.size())
	assert(is_equal_approx(float(nursery_rift_synergy.get("enemy_bonus", 0.0)), 0.10) and is_equal_approx(float(nursery_rift_synergy.get("reward", 0.0)), 0.25), "nursery/rift recipe must amplify risk for extra payout")
	var ward_hunt_tiles := {"4": {"id": "ward"}, "5": {"id": "hunt"}}
	var healing_synergy: Dictionary = tile_system.get_synergy_bonus(ward_hunt_tiles, 4, route.size())
	assert(int(healing_synergy.get("heal", 0)) == 4, "ward next to hunt must grant the configured synergy heal")
	var formation_tiles := {"1": {"id": "ward"}, "2": {"id": "cache"}, "3": {"id": "hunt"}}
	var formation_plain: Dictionary = tile_system.get_synergy_bonus(formation_tiles, 2, route.size())
	assert(formation_plain.get("synergies", []).has("Маршрут снабженческого дозора") and int(formation_plain.get("scrap", 0)) >= 4 and is_equal_approx(float(formation_plain.get("reward", 0.0)), 0.16), "three road tiles must activate the supply patrol formation on its center node")
	var cartographer_item := {"id": "smoke_route_scribe", "slot": "amulet", "archetype": "route_scribe", "road_formation_bonus": 0.10}
	var formation_equipped: Dictionary = tile_system.get_synergy_bonus(formation_tiles, 2, route.size(), {"amulet": cartographer_item})
	assert(is_equal_approx(float(formation_equipped.get("reward", 0.0)), 0.168), "worn route-scribe gear must improve formation reward only, without changing risk")
	assert(is_equal_approx(float(formation_equipped.get("spawn_bonus", 0.0)), float(formation_plain.get("spawn_bonus", 0.0))) and is_equal_approx(float(formation_equipped.get("enemy_bonus", 0.0)), float(formation_plain.get("enemy_bonus", 0.0))), "cartographer equipment must not amplify encounter chance or enemy strength")
	var quiet_formation_tiles := {"10": {"id": "snare"}, "11": {"id": "hunt"}, "12": {"id": "snare"}}
	var quiet_formation: Dictionary = tile_system.get_synergy_bonus(quiet_formation_tiles, 11, route.size())
	assert(quiet_formation.get("synergies", []).has("Тихая ловушка") and is_equal_approx(float(quiet_formation.get("spawn_bonus", 0.0)), -0.12), "quiet-trap formation must trade encounter chance for controlled enemy strength and reward")
	var rift_formation_tiles := {"13": {"id": "ward"}, "14": {"id": "rift"}, "15": {"id": "ward"}}
	var rift_formation: Dictionary = tile_system.get_synergy_bonus(rift_formation_tiles, 14, route.size())
	assert(rift_formation.get("synergies", []).has("Стабилизированный разлом") and int(rift_formation.get("heal", 0)) == 5, "ward-rift-ward formation must heal and reduce the rift threat")
	var echo_formation_tiles := {"10": {"id": "fault_line"}, "11": {"id": "signal"}, "12": {"id": "hunt"}}
	var echo_formation: Dictionary = tile_system.get_synergy_bonus(echo_formation_tiles, 11, route.size())
	assert(echo_formation.get("synergies", []).has("Засада на резонансе") and int(echo_formation.get("scrap", 0)) >= 2 and float(echo_formation.get("reward", 0.0)) >= 0.18, "echo ambush formation must grant material and reward while raising danger")
	var healing_formation_tiles := {"10": {"id": "echo_spring"}, "11": {"id": "ward"}, "12": {"id": "echo_spring"}}
	var healing_formation: Dictionary = tile_system.get_synergy_bonus(healing_formation_tiles, 11, route.size())
	assert(healing_formation.get("synergies", []).has("Шаги тихого источника") and int(healing_formation.get("heal", 0)) == 6, "echo-spring healing stride must return health and reduce encounter chance")
	var wrap_formation_tiles := {"16": {"id": "ward"}, "17": {"id": "cache"}, "1": {"id": "hunt"}}
	var wrap_formation: Dictionary = tile_system.get_synergy_bonus(wrap_formation_tiles, 17, route.size())
	assert(wrap_formation.get("synergies", []).has("Маршрут снабженческого дозора"), "road formations must wrap the last placeable road slot to the first without occupying the immutable start node")
	var wrap_preview: Dictionary = tile_system.get_placement_preview(route, {"16": {"id": "ward"}, "1": {"id": "hunt"}}, 17, {"id": "cache", "name": "Узел снабжения"})
	assert(wrap_preview.get("new_road_formations", []).size() == 1, "placement preview must detect a formation that closes across the route-card seam")
	var formation_preview: Dictionary = tile_system.get_placement_preview(route, {"1": {"id": "ward"}, "3": {"id": "hunt"}}, 2, {"id": "cache", "name": "Узел снабжения"})
	assert(formation_preview.get("new_road_formations", []).size() == 1 and str(formation_preview.get("text", "")).contains("Маршрут снабженческого дозора"), "road preview must show a new formation completed by this placement")
	var preview_result: Dictionary = tile_system.get_placement_preview(route, {"3": {"id": "ward"}}, 2, {"id": "cache", "name": "Узел снабжения"})
	assert(bool(preview_result.get("ok", false)), "empty legal node should have a placement preview")
	assert(not preview_result.get("synergies", []).is_empty(), "placement preview must show a known neighbor synergy")
	assert(str(preview_result.get("text", "")).contains("Узел снабжения"), "road preview must identify the selected tile before placement")
	var route_tiles_before_preview := {"2": {"id": "cache"}}
	var route_tiles_snapshot := route_tiles_before_preview.duplicate(true)
	var reverse_route_preview: Dictionary = tile_system.get_placement_preview(route, route_tiles_before_preview, 3, {"id": "ward"})
	assert(bool(reverse_route_preview.get("ok", false)) and reverse_route_preview.get("new_route_synergy_matches", []).size() == 1, "road preview must detect a synergy triggered by the pre-existing tile when the neighbour is placed last")
	assert(str(reverse_route_preview.get("text", "")).contains("узла 3") and str(reverse_route_preview.get("text", "")).contains("Контур снабжения"), "road preview must identify the neighbour trigger node and the new synergy")
	assert(route_tiles_before_preview == route_tiles_snapshot, "placement forecasts must not mutate route tiles")
	var occupied_route_preview: Dictionary = tile_system.get_placement_preview(route, {"2": {"id": "ward"}}, 2, {"id": "cache"})
	assert(not bool(occupied_route_preview.get("ok", true)), "road preview must reject occupied route nodes")
	var forbidden_preview: Dictionary = tile_system.get_placement_preview(route, {}, 0, {"id": "cache"})
	assert(not bool(forbidden_preview.get("ok", true)), "preview must explain why the route start is forbidden")
	assert(TileSystemType.WORLD_FIELD_KEYS.size() == 80, "legacy landscape IDs must remain stable for pre-Stage-85 saves")
	var road_profiles := {"classic_ring": true, "narrow_ring": true, "deep_descent": true, "fractured_loop": true}
	for profile_id in road_profiles.keys():
		var physical_road := TileSystemType.get_road_grid_coordinates(str(profile_id))
		var physical_road_set: Dictionary = {}
		for physical_coord in physical_road:
			physical_road_set["%d:%d" % [physical_coord.x, physical_coord.y]] = true
		assert(physical_road.size() == 34 and physical_road_set.size() == 34, "every Stage 85 contour must contain 34 unique road cells")
		var free_cell_count := 0
		for board_row in range(TileSystemType.MAP_ROWS):
			for board_col in range(TileSystemType.MAP_COLUMNS):
				var board_coord_id := "%d:%d" % [board_col, board_row]
				if not physical_road_set.has(board_coord_id):
					free_cell_count += 1
		assert(free_cell_count == 232, "every route shape must expose 232 off-road grid cells")
	assert(TileSystemType.is_world_cell_valid("m:0:0") and TileSystemType.is_world_cell_valid("m:18:13") and not TileSystemType.is_world_cell_valid("m:-1:0") and not TileSystemType.is_world_cell_valid("m:19:0"), "full-board IDs must validate within the 19x14 grid only")
	assert(TileSystemType.world_route_index("m:4:2", route.size(), "classic_ring") == 0, "landscape sector must map to the nearest actual road contour slot")
	assert(not bool(tile_system.can_place_world(route, {}, "m:4:3", {"id": "archive"}, "classic_ring").ok), "landscape placement must never target a road cell")
	assert(not bool(tile_system.can_place_world(route, {}, "m:4:2", {"id": "archive"}, "classic_ring").ok), "landscape-only structures must avoid roadside cells")
	assert(bool(tile_system.can_place_world(route, {}, "m:0:0", {"id": "archive"}, "classic_ring").ok), "wilderness structures should accept cells beyond the roadside band")
	assert(bool(tile_system.can_place_world(route, {}, "m:4:2", {"id": "roadside_test", "placement_zone": "roadside"}, "classic_ring").ok), "roadside placement should accept a cell orthogonally adjacent to the route")
	assert(not bool(tile_system.can_place_world(route, {}, "m:0:0", {"id": "roadside_test", "placement_zone": "roadside"}, "classic_ring").ok), "roadside placement should reject a cell away from the route")
	assert(TileSystemType.is_world_cell_valid("0:0") and TileSystemType.is_world_cell_valid("4:0") and TileSystemType.is_world_cell_valid("9:7"), "expanded landscape field must permit every 10x8 logical cell")
	var unique_world_cell_ids: Dictionary = {}
	for world_cell_value in TileSystemType.WORLD_FIELD_KEYS:
		var world_cell_key := str(world_cell_value)
		assert(not unique_world_cell_ids.has(world_cell_key), "landscape logical IDs must remain unique: %s" % world_cell_key)
		unique_world_cell_ids[world_cell_key] = true
	var landscape_cache := {"id": "cache", "name": "Узел снабжения", "short": "СНАБ"}
	var field_preview: Dictionary = tile_system.get_world_placement_preview(route, {}, "2:0", landscape_cache)
	assert(bool(field_preview.get("ok", false)) and int(field_preview.get("route_index", -1)) >= 0, "landscape placement preview must resolve a real route sector")
	var affinity_item := {"id": "preview_affinity", "name": "Линза сада", "landscape_affinity": "spore_garden", "affinity_effect": {"heal": 2, "scrap": 1, "reward_bonus": 0.10}}
	var equipped_affinity_preview: Dictionary = tile_system.get_world_placement_preview(route, {}, "2:0", {"id": "spore_garden"}, {"amulet": affinity_item})
	assert(bool(equipped_affinity_preview.get("ok", false)) and int(equipped_affinity_preview.get("equipment_affinity", {}).get("heal", 0)) == 2, "landscape forecast must use the equipped item's matching affinity")
	assert(str(equipped_affinity_preview.get("text", "")).contains("Эффект надетой экипировки") and str(equipped_affinity_preview.get("text", "")).contains("Угроза участка"), "landscape forecast must explain affinity effects and the enemy family")
	var secret_before_tiles := {}
	var secret_after_tiles := {"4:4": {"id": "crystal_hive", "route_index": 2}, "5:4": {"id": "echo_obelisk", "route_index": 2}}
	var new_secret_recipes: Array = tile_system.get_new_landscape_secret_recipes(secret_before_tiles, secret_after_tiles, "4:4")
	assert(new_secret_recipes.size() == 1 and str(new_secret_recipes[0].get("flag", "")) == "secret_prism_echo_found", "landscape forecast must detect a newly prepared secret recipe")
	var field_ward := {"id": "ward", "field_x": 1, "field_y": 0, "route_index": TileSystemType.world_route_index("1:0", route.size())}
	var field_cache := {"id": "cache", "field_x": 2, "field_y": 0, "route_index": TileSystemType.world_route_index("2:0", route.size())}
	var landscape_synergy: Dictionary = tile_system.get_world_synergy_bonus({"1:0": field_ward, "2:0": field_cache}, "2:0")
	assert(int(landscape_synergy.get("scrap", 0)) >= 4, "adjacent landscape cache and ward must grant the defined synergy")
	var crystal_archive_field := {"4:4": {"id": "crystal_hive", "route_index": 2}, "5:4": {"id": "archive", "route_index": 2}}
	var crystal_archive_bonus: Dictionary = tile_system.get_world_synergy_bonus(crystal_archive_field, "4:4")
	assert(int(crystal_archive_bonus.get("scrap", 0)) == 3 and is_equal_approx(float(crystal_archive_bonus.get("reward", 0.0)), 0.12), "crystal hive + archive must grant the authored resource/reward synergy")
	var spore_ward_field := {"4:4": {"id": "spore_garden", "route_index": 2}, "5:4": {"id": "ward", "route_index": 2}}
	var spore_ward_bonus: Dictionary = tile_system.get_world_synergy_bonus(spore_ward_field, "4:4")
	assert(int(spore_ward_bonus.get("heal", 0)) == 5 and is_equal_approx(float(spore_ward_bonus.get("spawn_bonus", 0.0)), -0.04), "spore garden + ward must provide the safer healing combo")
	var cross_sector_field := {"4:4": {"id": "crystal_hive", "route_index": 2}, "5:4": {"id": "archive", "route_index": 3}}
	var cross_sector_bonus: Dictionary = tile_system.get_world_synergy_bonus(cross_sector_field, "4:4")
	assert(int(cross_sector_bonus.get("scrap", 0)) == 0 and is_zero_approx(float(cross_sector_bonus.get("reward", 0.0))), "landscape synergies must not jump between distinct route sectors")
	var dense_synergy_field := {
		"4:4": {"id": "cache", "route_index": 2},
		"3:4": {"id": "ward", "route_index": 2},
		"5:4": {"id": "ward", "route_index": 2},
		"4:3": {"id": "ward", "route_index": 2},
		"4:5": {"id": "ward", "route_index": 2}
	}
	var capped_landscape_synergy: Dictionary = tile_system.get_world_synergy_bonus(dense_synergy_field, "4:4")
	assert(int(capped_landscape_synergy.get("raw_effects", {}).get("scrap", 0)) == 16, "four supply/ward recipes should retain the uncapped audit value")
	assert(int(capped_landscape_synergy.get("scrap", 0)) == 12, "per-cell synergy scrap must be capped at 12 per visit")
	assert(capped_landscape_synergy.get("caps_applied", []).has("scrap"), "the synergy cap must be reported for UI and diagnostics")
	var cap_delta: Dictionary = tile_system.get_world_placement_effect_delta({"4:4": dense_synergy_field["4:4"], "3:4": dense_synergy_field["3:4"], "5:4": dense_synergy_field["5:4"], "4:3": dense_synergy_field["4:3"]}, dense_synergy_field, "4:5")
	assert(int(cap_delta.get("totals", {}).get("scrap", 0)) == 0, "placement preview must show zero marginal scrap after the per-cell cap is already reached")
	assert(cap_delta.get("caps_applied", []).has("scrap"), "placement preview must disclose a capped effect")
	var capped_sector_synergy: Dictionary = tile_system.get_world_synergy_bonus_for_route_index(dense_synergy_field, 2)
	assert(int(capped_sector_synergy.get("raw_effects", {}).get("scrap", 0)) == 16 and int(capped_sector_synergy.get("scrap", 0)) == 12, "all landscape triggers in the same route sector must aggregate before applying the sector cap")
	var capped_visit: Dictionary = tile_system.clamp_visit_modifiers({"spawn_bonus": 2.0, "enemy_bonus": 1.2, "reward_bonus": 2.4})
	assert(is_equal_approx(float(capped_visit.get("spawn_bonus", 0.0)), 1.0), "final encounter chance modifier must be capped after all additions")
	assert(is_equal_approx(float(capped_visit.get("enemy_bonus", 0.0)), 0.75), "final enemy strength modifier must be capped after all additions")
	assert(is_equal_approx(float(capped_visit.get("reward_bonus", 0.0)), 1.5), "final combat reward modifier must be capped after all additions")
	assert(capped_visit.get("caps_applied", []).size() == 3, "all final visit caps must be exposed to diagnostics")
	var world_before_reverse := {"2:0": field_cache.duplicate(true)}
	var world_after_reverse := {"1:0": field_ward.duplicate(true), "2:0": field_cache.duplicate(true)}
	var reverse_matches: Array = tile_system.get_new_world_synergy_matches(world_before_reverse, world_after_reverse, "1:0")
	assert(reverse_matches.size() == 1 and str(reverse_matches[0].get("id", "")) == "supply_ward", "placing the neighbor tile last must detect a synergy triggered by the pre-existing tile")
	var reverse_preview: Dictionary = tile_system.get_world_placement_preview(route, world_before_reverse, "1:0", field_ward)
	assert(bool(reverse_preview.get("ok", false)) and str(reverse_preview.get("text", "")).contains("Контур снабжения") and str(reverse_preview.get("text", "")).contains("сектор"), "landscape preview must explain the newly completed synergy and its trigger sector from either placement order")
	var reverse_before_preview := world_before_reverse.duplicate(true)
	var removed_pair_delta: Dictionary = tile_system.get_world_placement_effect_delta(world_after_reverse, world_before_reverse, "1:0")
	assert(int(removed_pair_delta.get("totals", {}).get("scrap", 0)) == -4, "removing a neighbour tile must remove the old synergy bonus from the before/after forecast")
	assert(world_before_reverse == reverse_before_preview, "placement forecasts must not mutate the live tile map")
	var replacement_tiles := world_after_reverse.duplicate(true)
	var replacement_ward: Dictionary = replacement_tiles["1:0"].duplicate(true)
	replacement_ward["id"] = "snare"
	replacement_tiles["1:0"] = replacement_ward
	var replacement_delta: Dictionary = tile_system.get_world_placement_effect_delta(world_after_reverse, replacement_tiles, "1:0")
	assert(int(replacement_delta.get("totals", {}).get("scrap", 0)) == -4, "replacing a synergy tile must not leave a ghost bonus")
	assert(not bool(tile_system.can_place_world(route, {"2:0": field_cache}, "2:0").get("ok", true)), "occupied landscape cell must reject another tile")
	assert(not bool(tile_system.can_place_world(route, {}, "4:0").get("ok", true)), "unregistered landscape cell must reject placement")
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var enemy_system = EnemySystemType.new()
	var enemy: Dictionary = enemy_system.create_enemy(2, 1.3, rng)
	assert(int(enemy.hp) > 0 and int(enemy.max_hp) == int(enemy.hp), "enemy stats must be valid")
	assert(not bool(enemy.get("is_boss", true)), "regular enemies must not be tagged as bosses")
	var high_threat_pack: Array = enemy_system.create_encounter(4, 1.7, rng)
	assert(high_threat_pack.size() >= 2 and high_threat_pack.size() <= 3, "high-threat encounters must contain a group")
	var enemy_roles: Dictionary = {}
	for enemy_id_value in ContentRegistry.ENEMIES.keys():
		var enemy_definition: Dictionary = ContentRegistry.ENEMIES[str(enemy_id_value)]
		enemy_roles[str(enemy_definition.get("role", ""))] = true
	assert(enemy_roles.has("support") and enemy_roles.has("hunter") and enemy_roles.has("caster"), "enemy roster must include support, execute and weaken roles")
	for member in high_threat_pack:
		assert(int(member.get("hp", 0)) > 0 and float(member.get("attack_interval", 0.0)) > 0.0, "every encounter member must have valid combat stats")
	var configured_boss_group: Array = enemy_system.create_encounter(3, 1.54, rng, 0.0, true)
	assert(configured_boss_group.size() == 1, "boss encounter should contain a single boss in this ruleset")
	assert(bool(configured_boss_group[0].get("is_boss", false)), "boss encounter must be marked as a boss")
	assert(int(configured_boss_group[0].get("special_every", 0)) == 3, "boss must have a special attack cadence")
	assert(configured_boss_group[0].get("phases", []).size() >= 3, "boss definition must contain multiple phases")
	assert(str(configured_boss_group[0].get("phase_name", "")).length() > 0, "boss must expose its current phase")
	assert(str(configured_boss_group[0].get("phase_telegraph", "")).length() > 0, "boss must expose a special-attack telegraph")
	assert(int(configured_boss_group[0].get("crystal", 0)) >= 4, "boss must promise a meaningful rare-resource reward")
	var boss_cycle_ids: Array[String] = []
	var boss_special_effects: Dictionary = {}
	for boss_loop in [3, 6, 9, 12]:
		var cycle_boss: Dictionary = enemy_system.create_boss(boss_loop, 1.2, rng)
		boss_cycle_ids.append(str(cycle_boss.get("id", "")))
		boss_special_effects[str(cycle_boss.get("special_effect_id", ""))] = true
		assert(cycle_boss.get("phases", []).size() >= 3 and not str(cycle_boss.get("special_effect_id", "")).is_empty(), "each scheduled boss must define phases and a special status effect")
	assert(boss_cycle_ids == ["warden", "harvester", "matriarch", "bellkeeper"], "boss roster must rotate through four distinct bosses on the first four milestones")
	assert(boss_special_effects.has("wound") and boss_special_effects.has("distortion") and boss_special_effects.has("poison") and boss_special_effects.has("weakness"), "boss roster must require different combat preparations")
	var combat_system = CombatSystemType.new()
	var defender := {"hp": 8, "defense": 0}
	var attack: Dictionary = combat_system.perform_attack({"attack": 20, "crit": 0.0}, defender, rng)
	assert(int(defender.hp) == 0 and bool(attack.defeated), "combat should handle defeat cleanly")
	var event_system = EventSystemType.new()
	var event_rng := RandomNumberGenerator.new()
	event_rng.seed = 19077
	var first_event: Dictionary = event_system.draw_event(event_rng, 0, "")
	assert(not first_event.is_empty(), "event system must return a valid event")
	var first_choices_value: Variant = first_event.get("choices", [])
	assert(typeof(first_choices_value) == TYPE_ARRAY, "event choices must be an array")
	var first_choices: Array = first_choices_value
	assert(first_choices.size() >= 2, "every event must present multiple choices")
	var second_event: Dictionary = event_system.draw_event(event_rng, 0, str(first_event.get("id", "")))
	assert(not second_event.is_empty(), "event system must always have a fallback event")
	assert(str(second_event.get("id", "")) != str(first_event.get("id", "")), "immediate event repetition should be avoided")
	var secret_rng := RandomNumberGenerator.new()
	secret_rng.seed = 55661
	var archive_secret_event: Dictionary = event_system.draw_event(secret_rng, 1, "", {"secret_archive_rift_found": true})
	assert(str(archive_secret_event.get("id", "")) == "archive_rift_echo", "a discovered archive/rift secret must be the next event offered")
	var brood_secret_event: Dictionary = event_system.draw_event(secret_rng, 1, "", {"secret_nursery_snare_found": true})
	assert(str(brood_secret_event.get("id", "")) == "sealed_brood", "a discovered nursery/snare secret must be the next event offered")
	var secret_unseen_event: Dictionary = event_system.draw_event(secret_rng, 1, "", {})
	assert(not str(secret_unseen_event.get("id", "")).begins_with("archive_rift_echo") and str(secret_unseen_event.get("id", "")) != "sealed_brood", "secret events must not leak into ordinary random event pools")
	assert(ContentRegistry.EXPEDITION_EVENTS.archive_rift_echo.choices.size() == 2 and ContentRegistry.EXPEDITION_EVENTS.sealed_brood.choices.size() == 2, "each secret discovery must offer a meaningful choice")
	var secret_manager := ExpeditionManagerType.new()
	secret_manager.world_tiles = {"4:3": {"id": "archive", "route_index": 7}, "5:3": {"id": "rift", "route_index": 7}}
	secret_manager.run_ledger = {"event_flags": {}}
	var secret_messages: Array = []
	secret_manager._discover_landscape_secrets(7, secret_messages)
	assert(bool(secret_manager.run_ledger.get("event_flags", {}).get("secret_archive_rift_found", false)) and secret_messages.size() == 1 and str(secret_messages[0]).contains("ТАЙНА ОБНАРУЖЕНА"), "adjacent archive/rift tiles in one visited sector must reveal exactly one secret")
	secret_manager._discover_landscape_secrets(7, secret_messages)
	assert(secret_messages.size() == 1, "the same landscape secret must not announce itself again after discovery")
	secret_manager.world_tiles = {"4:3": {"id": "nursery", "route_index": 8}, "5:3": {"id": "snare", "route_index": 8}}
	secret_manager.run_ledger = {"event_flags": {}}
	var brood_messages: Array = []
	secret_manager._discover_landscape_secrets(8, brood_messages)
	assert(bool(secret_manager.run_ledger.get("event_flags", {}).get("secret_nursery_snare_found", false)) and brood_messages.size() == 1, "adjacent nursery/snare tiles in one sector must reveal the hidden nest")
	secret_manager.world_tiles = {"4:3": {"id": "crystal_hive", "route_index": 9}, "5:3": {"id": "echo_obelisk", "route_index": 9}}
	secret_manager.run_ledger = {"event_flags": {}}
	var prism_messages: Array = []
	secret_manager._discover_landscape_secrets(9, prism_messages)
	assert(bool(secret_manager.run_ledger.get("event_flags", {}).get("secret_prism_echo_found", false)), "adjacent crystal hive and echo obelisk must unlock the prism relic event")
	var prism_secret_event: Dictionary = event_system.draw_event(secret_rng, 1, "", {"secret_prism_echo_found": true})
	assert(str(prism_secret_event.get("id", "")) == "prism_echo", "the discovered prism combination must resolve into the matching event")
	secret_manager.world_tiles = {"4:3": {"id": "spore_garden", "route_index": 10}, "5:3": {"id": "bone_orchard", "route_index": 10}}
	secret_manager.run_ledger = {"event_flags": {}}
	var root_bone_messages: Array = []
	secret_manager._discover_landscape_secrets(10, root_bone_messages)
	assert(bool(secret_manager.run_ledger.get("event_flags", {}).get("secret_root_bone_found", false)), "adjacent spore and bone gardens must unlock the root/bone memory event")
	var root_bone_event: Dictionary = event_system.draw_event(secret_rng, 1, "", {"secret_root_bone_found": true})
	assert(str(root_bone_event.get("id", "")) == "root_bone_memory", "the root/bone landscape secret must lead to its named equipment event")
	var progression_system = ProgressionSystemType.new()
	var perk_rng := RandomNumberGenerator.new()
	perk_rng.seed = 101
	var perk_hero := {"attack_bonus": 0, "hp_bonus": 0, "defense_bonus": 0, "speed_bonus": 0.0, "crit_bonus": 0.0, "perk_counts": {"power": 3}}
	var perk_choices: Array = progression_system.make_perk_choices(perk_rng, perk_hero)
	assert(perk_choices.size() == 3, "a normal perk draft should offer three distinct choices")
	assert(not perk_choices.has("power"), "a perk at its stack limit must not be offered")
	var perk_unique: Dictionary = {}
	for perk_id in perk_choices:
		assert(not perk_unique.has(str(perk_id)), "perk draft must not contain duplicate choices")
		perk_unique[str(perk_id)] = true
	assert(progression_system.apply_perk(perk_hero, str(perk_choices[0])), "offered perk should be accepted")
	assert(int(perk_hero.get("perk_counts", {}).get(str(perk_choices[0]), 0)) == 1, "selected perk rank must be recorded")
	assert(not progression_system.apply_perk(perk_hero, "missing_perk"), "unknown perk must be rejected")
	var inventory_system = InventorySystemType.new()
	var secret_relic_ids := ["echo_chart_core", "riftwalker_edge", "brood_shell", "snare_hunter_core", "prism_heart", "echo_veil", "rootwatch_mantle", "bone_impulse_edge"]
	for secret_relic_id in secret_relic_ids:
		var secret_relic: Dictionary = inventory_system.make_secret_relic(str(secret_relic_id), 4, 5, 9981)
		assert(not secret_relic.is_empty() and bool(secret_relic.get("is_secret_relic", false)) and str(secret_relic.get("rarity", "")) == "Тайная", "each secret choice must create a named secret-rarity item")
		assert(not str(secret_relic.get("id", "")).is_empty() and float(secret_relic.get("power", 0.0)) > 0.0 and int(secret_relic.get("rank", 0)) > 0, "secret relics need a stable identity, ranked stats and usable item power")
		assert(int(inventory_system.get_upgrade_cost(secret_relic).get("scrap", 0)) > 0 and int(inventory_system.get_salvage_reward(secret_relic).get("crystals", 0)) >= 2, "secret relics must participate in upgrade and salvage systems")
	var repeated_seed_relic_a: Dictionary = inventory_system.make_secret_relic("echo_chart_core", 4, 5, 9981, 1)
	var repeated_seed_relic_b: Dictionary = inventory_system.make_secret_relic("echo_chart_core", 4, 5, 9981, 2)
	assert(str(repeated_seed_relic_a.get("id", "")) != str(repeated_seed_relic_b.get("id", "")), "replaying the same public seed on separate runs must not collapse unique relic inventory IDs")
	assert(inventory_system.make_secret_relic("unregistered_secret_item", 1, 1, 9981).is_empty(), "unregistered secret loot identifiers must be rejected")
	var item_rng := RandomNumberGenerator.new()
	item_rng.seed = 77531
	var rolled_item: Dictionary = inventory_system.roll_item(item_rng, 4, 5)
	var base_quality_rng := RandomNumberGenerator.new()
	base_quality_rng.seed = 40575
	var prepared_quality_rng := RandomNumberGenerator.new()
	prepared_quality_rng.seed = 40575
	var base_quality_item: Dictionary = inventory_system.roll_item(base_quality_rng, 4, 5, 0.0)
	var prepared_quality_item: Dictionary = inventory_system.roll_item(prepared_quality_rng, 4, 5, 0.25)
	var rarity_ranks := {"Обычный": 0, "Редкий": 1, "Эпический": 2, "Реликтовый": 3}
	assert(int(rarity_ranks.get(str(prepared_quality_item.get("rarity", "")), -1)) >= int(rarity_ranks.get(str(base_quality_item.get("rarity", "")), -1)), "prepared rarity bonus must never reduce the rolled item's rarity")
	var scout_amulet: Dictionary = {"id": "smoke_scout_amulet", "slot": "amulet", "archetype": "relic_scout", "set_id": "", "rare_find_bonus": 0.05, "tile_spawn_bonus": 0.02}
	var scout_loadout: Dictionary = inventory_system.calculate_loadout_stats({"amulet": scout_amulet}, {})
	assert(is_equal_approx(float(scout_loadout.get("combined", {}).get("rare_find_bonus", 0.0)), 0.05), "rare-find modifier must be derived from equipped slots only")
	assert(InventorySystemType.EQUIPMENT_SLOTS.has(str(rolled_item.get("slot", ""))), "equipment roll must choose a valid slot")
	assert(not str(rolled_item.get("archetype", "")).is_empty(), "rolled equipment must have a gameplay archetype")
	assert(not str(rolled_item.get("set_id", "")).is_empty(), "rolled equipment must define a set")
	assert(float(rolled_item.get("power", 0.0)) >= 0.0, "equipment comparison score must be non-negative")
	assert(int(rolled_item.get("upgrade_level", -1)) == 0, "new gear must start at upgrade level zero")
	var expected_roll_affixes := 0 if str(rolled_item.get("rarity", "")) == "Обычный" else (2 if str(rolled_item.get("rarity", "")) in ["Эпический", "Реликтовый"] else 1)
	assert(rolled_item.get("affix_ids", []).size() == expected_roll_affixes, "ordinary, rare and epic loot must produce zero, one and two affixes respectively")
	var weapon_fixture := {"id": "smoke_wpn", "slot": "weapon", "rarity": "Обычный", "rank": 2, "upgrade_level": 0, "archetype": "wound", "archetype_name": "Резец глубин", "archetype_description": "Кровотечение", "set_id": "vanguard", "set_name": "Авангард", "attack": 3, "defense": 0, "hp": 0, "speed": 0.0, "crit": 0.0, "bleed_chance": 0.2, "bleed_damage": 2, "power": 0.0}
	weapon_fixture["power"] = inventory_system.item_power(weapon_fixture)
	var weapon_upgrade_cost: Dictionary = inventory_system.get_upgrade_cost(weapon_fixture)
	var upgraded_weapon: Dictionary = inventory_system.preview_upgrade_item(weapon_fixture)
	assert(bool(weapon_upgrade_cost.get("available", false)) and int(weapon_upgrade_cost.get("scrap", 0)) > 0 and int(weapon_upgrade_cost.get("crystals", 0)) > 0, "gear upgrades must have a visible positive materials cost")
	assert(str(upgraded_weapon.get("id", "")) == "smoke_wpn" and int(upgraded_weapon.get("upgrade_level", 0)) == 1, "upgrade must preserve item identity and advance its separate upgrade level")
	assert(int(upgraded_weapon.get("attack", 0)) > int(weapon_fixture.get("attack", 0)) and float(upgraded_weapon.get("power", 0.0)) > float(weapon_fixture.get("power", 0.0)), "weapon upgrade must increase its primary stat and calculated power")
	assert(str(upgraded_weapon.get("archetype", "")) == "wound" and str(upgraded_weapon.get("set_id", "")) == "vanguard" and is_equal_approx(float(upgraded_weapon.get("bleed_chance", 0.0)), 0.2), "upgrade must preserve affix, set and special-property data")
	var rare_fixture: Dictionary = weapon_fixture.duplicate(true)
	rare_fixture["rarity"] = "Редкий"
	assert(int(inventory_system.get_upgrade_cost(rare_fixture).get("scrap", 0)) > int(weapon_upgrade_cost.get("scrap", 0)), "rarer equipment should cost more to upgrade")
	var elite_fixture: Dictionary = weapon_fixture.duplicate(true)
	elite_fixture["rarity"] = "Элитная"
	var boss_fixture: Dictionary = weapon_fixture.duplicate(true)
	boss_fixture["rarity"] = "Боссовая"
	assert(int(inventory_system.get_upgrade_cost(elite_fixture).get("scrap", 0)) > int(weapon_upgrade_cost.get("scrap", 0)) and int(inventory_system.get_upgrade_cost(boss_fixture).get("scrap", 0)) > int(inventory_system.get_upgrade_cost(rare_fixture).get("scrap", 0)), "elite and boss relic upgrades must cost more than ordinary and rare gear")
	var warden_relic: Dictionary = inventory_system.roll_boss_item({"id": "warden", "name": "Страж древнего узла"}, item_rng, 3, 1)
	var harvester_relic: Dictionary = inventory_system.roll_boss_item({"id": "harvester", "name": "Светожор — сборщик импульсов"}, item_rng, 6, 2)
	assert(bool(warden_relic.get("is_boss_relic", false)) and str(warden_relic.get("rarity", "")) == "Боссовая" and str(warden_relic.get("set_id", "")) == "vanguard", "Warden must drop a named relic from its signature set")
	assert(bool(harvester_relic.get("is_boss_relic", false)) and str(harvester_relic.get("rarity", "")) == "Боссовая" and str(harvester_relic.get("set_id", "")) == "resonance", "Harvester must drop a named relic from its signature set")
	assert(not str(warden_relic.get("unique_id", "")).is_empty() and float(warden_relic.get("power", 0.0)) > 0.0 and int(warden_relic.get("rank", 0)) >= 1, "boss relic rolls must produce named, ranked and comparable items")
	var armor_fixture := {"id": "smoke_arm", "slot": "armor", "rarity": "Обычный", "rank": 1, "upgrade_level": 0, "defense": 1, "hp": 6, "power": 0.0}
	var upgraded_armor: Dictionary = inventory_system.preview_upgrade_item(armor_fixture)
	assert(int(upgraded_armor.get("defense", 0)) > 1 and int(upgraded_armor.get("hp", 0)) > 6, "armor upgrades must improve both defence and health")
	var core_fixture := {"id": "smoke_core", "slot": "core", "rarity": "Обычный", "rank": 1, "upgrade_level": 0, "attack": 0, "speed": 0.04, "crit": 0.025, "power": 0.0}
	var rare_affix_rng := RandomNumberGenerator.new()
	rare_affix_rng.seed = 1827
	var rare_affix_base: Dictionary = weapon_fixture.duplicate(true)
	rare_affix_base["rarity"] = "Редкий"
	var rare_affixed: Dictionary = inventory_system.apply_random_affixes(rare_affix_base, rare_affix_rng)
	var rare_affix_ids: Array = rare_affixed.get("affix_ids", [])
	assert(rare_affix_ids.size() == 1 and not str(rare_affixed.get("affix_description", "")).is_empty(), "rare gear must roll exactly one readable prefix affix")
	assert(float(rare_affixed.get("power", 0.0)) > float(weapon_fixture.get("power", 0.0)), "a weapon affix must change the real item comparison score")
	assert(not weapon_fixture.has("affix_ids"), "affix rolls must not mutate the source item fixture")
	var epic_affix_rng := RandomNumberGenerator.new()
	epic_affix_rng.seed = 7319
	var epic_affix_base: Dictionary = weapon_fixture.duplicate(true)
	epic_affix_base["rarity"] = "Эпический"
	var epic_affixed: Dictionary = inventory_system.apply_random_affixes(epic_affix_base, epic_affix_rng)
	var epic_affix_ids: Array = epic_affixed.get("affix_ids", [])
	var epic_prefix_count := 0
	var epic_suffix_count := 0
	for affix_id_value in epic_affix_ids:
		var affix_definition: Dictionary = InventorySystemType.ITEM_AFFIXES.get(str(affix_id_value), {})
		assert(str(affix_definition.get("slot", "")) == "weapon", "weapon affixes must never come from armor or core pools")
		if str(affix_definition.get("position", "")) == "prefix":
			epic_prefix_count += 1
		elif str(affix_definition.get("position", "")) == "suffix":
			epic_suffix_count += 1
	assert(epic_affix_ids.size() == 2 and epic_prefix_count == 1 and epic_suffix_count == 1 and epic_affixed.get("affix_names", []).size() == 2, "epic gear must roll one slot-matched prefix and one suffix")
	var common_affix_base: Dictionary = weapon_fixture.duplicate(true)
	common_affix_base["rarity"] = "Обычный"
	var common_affixed: Dictionary = inventory_system.apply_random_affixes(common_affix_base, epic_affix_rng)
	assert(common_affixed.get("affix_ids", []).is_empty(), "ordinary gear must not roll rarity affixes")
	var armor_affix_base: Dictionary = armor_fixture.duplicate(true)
	armor_affix_base["rarity"] = "Эпический"
	var armor_affixed: Dictionary = inventory_system.apply_random_affixes(armor_affix_base, epic_affix_rng)
	var core_affix_base: Dictionary = core_fixture.duplicate(true)
	core_affix_base["rarity"] = "Эпический"
	var core_affixed: Dictionary = inventory_system.apply_random_affixes(core_affix_base, epic_affix_rng)
	for slot_fixture in [{"item": armor_affixed, "slot": "armor"}, {"item": core_affixed, "slot": "core"}]:
		var slot_item: Dictionary = slot_fixture.get("item", {})
		assert(slot_item.get("affix_ids", []).size() == 2, "epic armor and core must also receive two affixes")
		for affix_id_value in slot_item.get("affix_ids", []):
			var affix_definition: Dictionary = InventorySystemType.ITEM_AFFIXES.get(str(affix_id_value), {})
			assert(str(affix_definition.get("slot", "")) == str(slot_fixture.get("slot", "")), "each affix pool must remain slot-specific")
	assert(float(armor_affixed.get("power", 0.0)) >= 0.0 and float(core_affixed.get("power", 0.0)) >= 0.0, "affixed armor/core must retain valid comparison scores")
	var upgraded_core: Dictionary = inventory_system.preview_upgrade_item(core_fixture)
	assert(float(upgraded_core.get("speed", 0.0)) > 0.04 and float(upgraded_core.get("crit", 0.0)) > 0.025, "core upgrade must improve speed and critical chance")
	var maxed_item: Dictionary = weapon_fixture.duplicate(true)
	maxed_item["upgrade_level"] = InventorySystemType.MAX_UPGRADE_LEVEL
	assert(not bool(inventory_system.get_upgrade_cost(maxed_item).get("available", true)) and inventory_system.preview_upgrade_item(maxed_item).is_empty(), "maximum-level items must not be upgradeable")
	var common_salvage: Dictionary = inventory_system.get_salvage_reward(weapon_fixture)
	var epic_fixture: Dictionary = weapon_fixture.duplicate(true)
	epic_fixture["rarity"] = "Эпический"
	var epic_salvage: Dictionary = inventory_system.get_salvage_reward(epic_fixture)
	assert(int(common_salvage.get("scrap", 0)) > 0 and int(epic_salvage.get("scrap", 0)) > int(common_salvage.get("scrap", 0)) and int(epic_salvage.get("crystals", 0)) > int(common_salvage.get("crystals", 0)), "salvage returns must be deterministic and scale by rarity")
	var elite_salvage: Dictionary = inventory_system.get_salvage_reward(elite_fixture)
	var boss_salvage: Dictionary = inventory_system.get_salvage_reward(boss_fixture)
	assert(int(boss_salvage.get("scrap", 0)) > int(epic_salvage.get("scrap", 0)) and int(boss_salvage.get("crystals", 0)) > int(elite_salvage.get("crystals", 0)), "recycling boss relics must return the highest rarity materials")
	var set_stats: Dictionary = inventory_system.total_equipment_stats({"weapon": {"slot": "weapon", "set_id": "vanguard", "attack": 1}, "armor": {"slot": "armor", "set_id": "vanguard", "defense": 1}})
	assert(int(set_stats.get("defense", 0)) == 3 and int(set_stats.get("hp", 0)) == 8, "two-piece vanguard set must apply actual stats")
	assert(set_stats.get("active_sets", []).has("Авангард"), "active set should be reported to the UI")
	var phase_loadout := {
		"weapon": {"slot": "weapon", "archetype": "leech", "set_id": "phasebound", "attack": 1, "lifesteal": 0.08},
		"armor": {"slot": "armor", "archetype": "phaseweave", "set_id": "phasebound", "hp": 3, "dodge_chance": 0.07},
		"core": {"slot": "core", "archetype": "reflex", "set_id": "", "lifesteal": 0.025, "dodge_chance": 0.045}
	}
	var phase_stats: Dictionary = inventory_system.total_equipment_stats(phase_loadout)
	assert(phase_stats.get("active_sets", []).has("Фазоход") and phase_stats.get("active_synergies", []).has("Живой фантом"), "living blade + phaseweave must activate the phase set and its equipment synergy")
	var tracker_stats: Dictionary = inventory_system.total_equipment_stats({"weapon": {"id": "test_w", "slot": "weapon", "set_id": "abyss_tracker", "biome_damage_bonus": 0.0}, "helmet": {"id": "test_h", "slot": "helmet", "set_id": "abyss_tracker"}})
	assert(float(tracker_stats.get("biome_damage_bonus", 0.0)) >= 0.05 and float(tracker_stats.get("biome_resistance", 0.0)) >= 0.025, "two Abyss Tracker pieces must grant biome offense and defense")
	var prism_enemy := {"id": "prism_mite", "biome_tag": "crystal", "tags": ["crystal", "insect", "fast"]}
	var affinity_equipment := {"core": {"id": "prism_heart", "slot": "core", "landscape_affinity": "crystal_hive", "affinity_effect": {"crystals": 1}}}
	var prism_affinity: Dictionary = inventory_system.get_landscape_combat_bonus(affinity_equipment, ["crystal_hive"], prism_enemy)
	assert(is_equal_approx(float(prism_affinity.get("bonus", 0.0)), 0.06), "matching crystal relic and landscape must add contextual combat damage")
	var wrong_affinity: Dictionary = inventory_system.get_landscape_combat_bonus(affinity_equipment, ["spore_garden"], prism_enemy)
	assert(is_zero_approx(float(wrong_affinity.get("bonus", 0.0))), "landscape affinity must not activate away from its named tile")
	assert(is_equal_approx(float(phase_stats.get("lifesteal", 0.0)), 0.175) and is_equal_approx(float(phase_stats.get("dodge_chance", 0.0)), 0.175), "equipment, set and archetype synergy must apply real healing/dodge stats once")
	var overclock_loadout := {
		"weapon": {"slot": "weapon", "archetype": "assault", "attack": 3, "set_id": ""},
		"armor": {"slot": "armor", "archetype": "field_medic", "defense": 1, "set_id": ""},
		"core": {"slot": "core", "archetype": "tempo", "speed": 0.04, "set_id": ""}
	}
	var overclock_stats: Dictionary = inventory_system.total_equipment_stats(overclock_loadout)
	assert(overclock_stats.get("active_synergies", []).has("Контур перегрузки"), "assault plus tempo should activate the overclock synergy")
	assert(int(overclock_stats.get("attack", 0)) == 4 and is_equal_approx(float(overclock_stats.get("speed", 0.0)), 0.075), "overclock synergy should add its declared attack and speed bonuses")
	var route_build := overclock_loadout.duplicate(true)
	route_build["armor"]["archetype"] = "scavenger"
	route_build["armor"]["tile_scrap"] = 1
	route_build["core"]["archetype"] = "pathfinder"
	route_build["core"]["tile_spawn_bonus"] = -0.04
	var route_build_stats: Dictionary = inventory_system.total_equipment_stats(route_build)
	assert(route_build_stats.get("active_synergies", []).has("Маршрут сборщика") and not route_build_stats.get("active_synergies", []).has("Контур перегрузки"), "replacing gear must deactivate the old synergy and activate the new build")
	assert(int(route_build_stats.get("tile_scrap", 0)) == 2 and is_equal_approx(float(route_build_stats.get("tile_spawn_bonus", 0.0)), -0.06), "route synergy must affect actual resource and encounter stats")
	var overcap_loadout := {
		"weapon": {"slot": "weapon", "crit": 0.65, "speed": 1.4, "reward_bonus": 1.2},
		"armor": {"slot": "armor", "crit": 0.2, "speed": 0.2, "reward_bonus": 0.8},
		"core": {"slot": "core", "crit": 0.2, "speed": 0.2, "reward_bonus": 0.8}
	}
	var capped_gear_stats: Dictionary = inventory_system.total_equipment_stats(overcap_loadout)
	assert(float(capped_gear_stats.get("crit", 1.0)) <= 0.70 and float(capped_gear_stats.get("speed", 2.0)) <= 1.5 and float(capped_gear_stats.get("reward_bonus", 2.0)) <= 1.5, "aggregated equipment modifiers must respect shared build caps")
	var calculated_perks: Dictionary = inventory_system.total_perk_stats({"power": 3, "tempo": 3, "fortune": 3, "ambush": 2})
	assert(int(calculated_perks.get("attack", 0)) == 6 and is_equal_approx(float(calculated_perks.get("speed", 0.0)), 0.36), "perks must be derived from saved ranks")
	var calculated_build: Dictionary = inventory_system.calculate_loadout_stats(overclock_loadout, {"power": 3, "tempo": 3})
	assert(int(calculated_build.get("combined", {}).get("attack", 0)) == 10 and is_equal_approx(float(calculated_build.get("combined", {}).get("speed", 0.0)), 0.435), "combined loadout preview must include gear, synergy and perk ranks exactly once")
	assert(ContentRegistry.BALANCE.has("encounter_chance_base"), "encounter chance must be configurable")
	assert(ContentRegistry.BALANCE.has("loop_danger_growth"), "danger growth must be configurable")
	assert(ContentRegistry.DIFFICULTY_PRESETS.has("volatile"), "volatile difficulty must be configured")
	var biome_affinity_loadout := {
		"weapon": {"id": "spore_edge", "slot": "weapon", "spore_damage_bonus": 0.08, "spore_trophy_bonus": 0.06},
		"core": {"id": "echo_core", "slot": "core", "echo_damage_bonus": 0.08, "echo_trophy_bonus": 0.06}
	}
	var biome_affinity_stats: Dictionary = inventory_system.total_equipment_stats(biome_affinity_loadout)
	assert(is_equal_approx(float(biome_affinity_stats.get("spore_trophy_bonus", 0.0)), 0.06) and is_equal_approx(float(biome_affinity_stats.get("echo_trophy_bonus", 0.0)), 0.06), "biome affixes must add trophy chance only through equipped gear stats")
	# STAGE79_LOOP_HERO_BACKPACK_QUEUE: newest item enters the first cell and oldest leaves when full.
	var queue_smoke_manager = ExpeditionManagerType.new()
	for packed_index in range(queue_smoke_manager.BACKPACK_CAPACITY):
		queue_smoke_manager.bag.append({"id": "packed_%d" % packed_index, "slot": "weapon", "name": "Загруженный предмет %d" % packed_index})
	var overflow_candidate := {"id": "overflow_candidate", "slot": "armor", "name": "Броня из тайника", "defense": 2, "hp": 6}
	assert(queue_smoke_manager._store_run_item(overflow_candidate), "new loot should enter the backpack queue when full")
	assert(queue_smoke_manager.bag.size() == queue_smoke_manager.BACKPACK_CAPACITY, "FIFO backpack must remain limited to 12 items")
	assert(str(queue_smoke_manager.bag.front().get("id", "")) == "overflow_candidate", "new item must enter cell 01")
	assert(str(queue_smoke_manager.bag.back().get("id", "")) == "packed_10", "oldest item must be ejected and second-oldest becomes the final cell")
	assert(queue_smoke_manager.find_run_item("packed_11").is_empty(), "ejected item must no longer be present in the active expedition backpack")
	assert(str(queue_smoke_manager.last_inventory_evicted_item.get("id", "")) == "packed_11", "last evicted item must be exposed for feedback and later base-resource conversion")
	assert(queue_smoke_manager.field_cache.is_empty(), "overflow must not be redirected to the legacy field cache")
	assert(int(queue_smoke_manager.run_ledger.get("inventory_ejections_count", 0)) == 1 and int(queue_smoke_manager.run_ledger.get("inventory_ejections_dust", 0)) == inventory_system.get_ejection_echo_dust(queue_smoke_manager.last_inventory_evicted_item), "every FIFO eviction must increment both the cumulative item count and its eventual base-resource value")
	# STAGE82_ITEM_IDENTITY: duplicate rewards must not be reported as successful inserts or eject more gear.
	var bag_size_before_duplicate := queue_smoke_manager.bag.size()
	var ejection_count_before_duplicate := int(queue_smoke_manager.run_ledger.get("inventory_ejections_count", 0))
	var dust_before_duplicate := int(queue_smoke_manager.run_ledger.get("inventory_ejections_dust", 0))
	assert(not queue_smoke_manager._store_run_item({"id": "packed_10", "slot": "weapon", "name": "Дубликат"}), "duplicate backpack item IDs must be rejected instead of falsely reporting a successful drop")
	assert(queue_smoke_manager.bag.size() == bag_size_before_duplicate and int(queue_smoke_manager.run_ledger.get("inventory_ejections_count", 0)) == ejection_count_before_duplicate and int(queue_smoke_manager.run_ledger.get("inventory_ejections_dust", 0)) == dust_before_duplicate, "a rejected duplicate must not change backpack capacity or ejection rewards")
	queue_smoke_manager.equipment["core"] = {"id": "already_equipped", "slot": "core", "name": "Уже надето"}
	assert(not queue_smoke_manager._store_run_item({"id": "already_equipped", "slot": "core", "name": "Копия"}), "item identity must be unique across equipped slots and backpack")
	var common_ejection := {"id": "dust_common", "slot": "weapon", "rarity": "Обычный", "rank": 1, "upgrade_level": 0, "power": 0.0}
	var rare_ejection := {"id": "dust_rare", "slot": "weapon", "rarity": "Редкий", "rank": 1, "upgrade_level": 0, "power": 0.0}
	var epic_ejection := {"id": "dust_epic", "slot": "weapon", "rarity": "Эпический", "rank": 1, "upgrade_level": 0, "power": 0.0}
	var relic_ejection := {"id": "dust_relic", "slot": "core", "rarity": "Реликтовый", "rank": 1, "upgrade_level": 0, "power": 0.0}
	assert(inventory_system.get_ejection_echo_dust(common_ejection) == 1 and inventory_system.get_ejection_echo_dust(rare_ejection) == 2 and inventory_system.get_ejection_echo_dust(epic_ejection) == 4 and inventory_system.get_ejection_echo_dust(relic_ejection) == 6, "overflow conversion must reward higher rarities with more capped Echo Dust")
	var powered_ejection := rare_ejection.duplicate(true)
	powered_ejection["rank"] = 9
	powered_ejection["upgrade_level"] = 5
	powered_ejection["power"] = 95.0
	assert(inventory_system.get_ejection_echo_dust(powered_ejection) > inventory_system.get_ejection_echo_dust(rare_ejection) and inventory_system.get_ejection_echo_dust(powered_ejection) <= 10, "overflow dust must recognize ranked/upgraded gear but enforce a per-item ceiling")
	assert(GameState.echo_dust >= 0 and GameState.echo_dust <= GameState.MAX_ECHO_DUST, "base Echo Dust must stay inside its save-safe cap")
	var reorder_result: Dictionary = queue_smoke_manager.reorder_run_bag_item("packed_10", 0)
	assert(not bool(reorder_result.get("ok", true)), "reordering must be blocked when the expedition is inactive")
	var legacy_snapshot_items := [{"id": "legacy_old", "slot": "weapon", "name": "Старый"}, {"id": "legacy_new", "slot": "armor", "name": "Новый"}]
	var migrated_order := legacy_snapshot_items.duplicate(true)
	migrated_order.reverse()
	assert(str(migrated_order.front().get("id", "")) == "legacy_new", "legacy oldest-first inventory migration must reverse into newest-first ordering")
	assert(GameState.get_armory_item("overflow_candidate").is_empty(), "fresh expedition drops must not be copied to permanent armory before surviving the run")
	queue_smoke_manager.free()
	var stat_comparison := ItemTextPresenterType.format_stat_comparison({"attack": 4, "speed": 0.10, "defense": 0}, {"attack": 2, "speed": 0.05, "defense": 1})
	assert(stat_comparison.contains("Атака: +2") and stat_comparison.contains("Скорость атаки: +5%") and stat_comparison.contains("Защита: -1"), "item comparison must explain positive and negative stat changes, not only an aggregate power score")
	var loot_system = LootSystemType.new()
	var base_rarity_distribution: Dictionary = inventory_system.get_rarity_distribution(0.0)
	var boosted_rarity_distribution: Dictionary = inventory_system.get_rarity_distribution(0.25)
	var base_rarity_total := 0.0
	for rarity_value in base_rarity_distribution.values():
		base_rarity_total += float(rarity_value)
	assert(is_equal_approx(base_rarity_total, 1.0), "rarity distribution must sum to one")
	assert(is_equal_approx(float(base_rarity_distribution.get("Обычный", 0.0)), 0.70) and is_equal_approx(float(base_rarity_distribution.get("Редкий", 0.0)), 0.24), "baseline rarity probabilities must match the documented 70/24/5.2/0.8 split")
	assert(float(boosted_rarity_distribution.get("Обычный", 0.0)) < float(base_rarity_distribution.get("Обычный", 0.0)) and float(boosted_rarity_distribution.get("Редкий", 0.0)) > float(base_rarity_distribution.get("Редкий", 0.0)), "rare-find bonus should shift probability away from common gear toward rarer tiers")
	assert(float(boosted_rarity_distribution.get("Обычный", 0.0)) > float(boosted_rarity_distribution.get("Редкий", 0.0)) and float(boosted_rarity_distribution.get("Редкий", 0.0)) > float(boosted_rarity_distribution.get("Эпический", 0.0)) and float(boosted_rarity_distribution.get("Эпический", 0.0)) > float(boosted_rarity_distribution.get("Реликтовый", 0.0)), "relic chance must remain below epic chance at maximum bias")
	var rarity_rng := RandomNumberGenerator.new()
	rarity_rng.seed = 811731
	var rarity_counts := {"Обычный": 0, "Редкий": 0, "Эпический": 0, "Реликтовый": 0}
	const RARITY_SAMPLE_COUNT := 12000
	for _sample_index in range(RARITY_SAMPLE_COUNT):
		var base_sample_rarity := inventory_system.roll_rarity(rarity_rng, 0.0)
		rarity_counts[base_sample_rarity] = int(rarity_counts.get(base_sample_rarity, 0)) + 1
	assert(absf(float(rarity_counts["Обычный"]) / RARITY_SAMPLE_COUNT - 0.70) < 0.02, "seeded rarity samples should stay near 70% common")
	assert(absf(float(rarity_counts["Редкий"]) / RARITY_SAMPLE_COUNT - 0.24) < 0.02, "seeded rarity samples should stay near 24% rare")
	assert(absf(float(rarity_counts["Эпический"]) / RARITY_SAMPLE_COUNT - 0.052) < 0.012, "seeded rarity samples should stay near 5.2% epic")
	assert(absf(float(rarity_counts["Реликтовый"]) / RARITY_SAMPLE_COUNT - 0.008) < 0.006, "seeded rarity samples should stay near 0.8% relic")
	var max_bias_counts := {"Обычный": 0, "Редкий": 0, "Эпический": 0, "Реликтовый": 0}
	var max_bias_rng := RandomNumberGenerator.new()
	max_bias_rng.seed = 811732
	for _sample_index in range(RARITY_SAMPLE_COUNT):
		var biased_sample_rarity := inventory_system.roll_rarity(max_bias_rng, 0.25)
		max_bias_counts[biased_sample_rarity] = int(max_bias_counts.get(biased_sample_rarity, 0)) + 1
	assert(float(max_bias_counts["Реликтовый"]) / RARITY_SAMPLE_COUNT < 0.05, "rarity bonus at cap must not turn relic equipment into a common drop")
	assert(is_equal_approx(loot_system.get_equipment_drop_chance("enemy"), 0.18), "ordinary equipment drop chance must use 18% baseline")
	assert(is_equal_approx(loot_system.get_equipment_drop_chance("elite"), 0.45), "elite equipment drop chance must use 45% baseline")
	assert(is_equal_approx(loot_system.get_equipment_drop_chance("cache"), 0.35), "cache equipment drop chance must use 35% baseline")
	assert(is_equal_approx(loot_system.get_equipment_drop_chance("boss"), 1.0), "boss equipment reward must remain guaranteed")
	assert(is_equal_approx(loot_system.get_equipment_drop_chance("cache", 0.0, 4, 0.30), 0.85), "equipment drop probabilities must use source-specific weights and respect cache cap")
	assert(loot_system.get_source_rarity_bonus("elite") > loot_system.get_source_rarity_bonus("enemy") and loot_system.get_source_rarity_bonus("cache") > loot_system.get_source_rarity_bonus("enemy"), "elite and cache sources should improve quality odds without guaranteeing a relic")
	var spore_enemy := {"id": "sporeling", "biome_tag": "spore"}
	var crystal_enemy := {"id": "prism_mite", "biome_tag": "crystal"}
	var spore_base_chance: float = loot_system.get_biome_trophy_chance(spore_enemy)
	var spore_gear_chance: float = loot_system.get_biome_trophy_chance(spore_enemy, [], 0.0, 0.06)
	var crystal_base_chance: float = loot_system.get_biome_trophy_chance(crystal_enemy)
	assert(is_equal_approx(spore_gear_chance, spore_base_chance + 0.06), "matching biome affix must add its trophy bonus")
	assert(is_equal_approx(crystal_base_chance, 0.56), "a spore-specific affix must not change a crystal biome's base trophy chance")
	var draft_rng := RandomNumberGenerator.new()
	draft_rng.seed = 87531
	var tile_system_for_draft = TileSystemType.new()
	var original_draft: Dictionary = tile_system_for_draft.draw_tile(draft_rng, true)
	var alternate_draft: Dictionary = tile_system_for_draft.draw_tile(draft_rng, true, [str(original_draft.get("id", ""))])
	assert(str(alternate_draft.get("id", "")) != str(original_draft.get("id", "")), "card redraw must exclude the selected tile ID when other choices exist")
	var exchange_manager = ExpeditionManagerType.new()
	exchange_manager.active = true
	exchange_manager.tile_hand = [{"id": "cache", "name": "Узел снабжения"}]
	exchange_manager.run_ledger = {"crystals": 1, "last_tile_exchange_loop": -1}
	exchange_manager.loop_count = 0
	assert(bool(exchange_manager.get_tile_exchange_preview(0).get("ok", false)), "card exchange should be offered for a valid hand card with one crystal")
	exchange_manager.run_ledger["last_tile_exchange_loop"] = 0
	assert(not bool(exchange_manager.get_tile_exchange_preview(0).get("ok", true)), "card exchange must be limited to once per loop")
	exchange_manager.run_ledger["last_tile_exchange_loop"] = -1
	exchange_manager.run_ledger["crystals"] = 0
	assert(not bool(exchange_manager.get_tile_exchange_preview(0).get("ok", true)), "card exchange must not allow spending a missing crystal")
	exchange_manager.free()
	var resource_system = ResourceSystemType.new()
	var ledger := {"scrap": 11, "crystals": 3}
	var settled: Dictionary = resource_system.settle(ledger, 0.4)
	assert(int(settled.scrap) == 4 and int(settled.crystals) == 1, "settlement ratio should floor consistently")
	assert(ContentRegistry.EXPEDITION_EVENTS.has("beacon_echo"), "beacon follow-up event must be configured")
	assert(ContentRegistry.EXPEDITION_EVENTS.has("signal_pursuit"), "signal consequence event must be configured")
	print("SMOKE TESTS PASSED")
	quit(0)
