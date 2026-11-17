"""Source-level regression checks for Abyss eight-floor campaign progression.

These checks guard cross-file wiring and content invariants. They do not replace
Godot 4.7.2 import, GDScript smoke, save/reload, or browser gameplay acceptance.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
game_state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
save_system = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
tiles = (ROOT / "scripts/systems/tile_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")

checks: dict[str, bool] = {}

# The catalogue must contain precisely the eight numbered depths.
floor_match = re.search(r"const ABYSS_FLOORS := \{(?P<body>.*?)\n\}", registry, re.S)
floor_ids = (
    [int(value) for value in re.findall(r"^\s*(\d+):\s*\{", floor_match.group("body"), re.M)]
    if floor_match else []
)
checks["catalogue defines exactly floors 1 through 8"] = (
    "const ABYSS_FLOOR_COUNT := 8" in registry and floor_ids == list(range(1, 9))
)
floor_lines = [
    line for line in (floor_match.group("body").splitlines() if floor_match else [])
    if re.match(r"\s*\d+:\s*\{", line)
]
attack = [float(re.search(r'"enemy_attack_multiplier":\s*([0-9.]+)', line).group(1)) for line in floor_lines]
health = [float(re.search(r'"enemy_health_multiplier":\s*([0-9.]+)', line).group(1)) for line in floor_lines]
reward = [float(re.search(r'"reward_multiplier":\s*([0-9.]+)', line).group(1)) for line in floor_lines]
checks["all floor configurations define unique content and monotonic pressure/rewards"] = (
    len(floor_lines) == 8
    and all(re.search(r'"name":\s*"[^"]+"', line) and re.search(r'"biome":\s*"[^"]+"', line) for line in floor_lines)
    and attack == sorted(attack)
    and health == sorted(health)
    and reward == sorted(reward)
)
checks["floor registry validates all eight configs and progression direction"] = (
    "ABYSS_FLOORS.size() != ABYSS_FLOOR_COUNT" in registry
    and "abyss floor pressure/rewards must not decrease" in registry
    and "func get_abyss_floor(floor_id: int) -> Dictionary:" in registry
)

checks["floors have validated biome-specific enemy and mixed card pools"] = (
    'floor_definition.get("enemy_pool", [])' in registry
    and 'floor_definition.get("tile_pool", [])' in registry
    and 'if not ENEMIES.has(str(enemy_id_value))' in registry
    and 'if not TILE_DEFS.has(str(tile_id_value))' in registry
    and '"sporeling"' in registry and '"prism_mite"' in registry
    and '"bone_warden"' in registry and '"echo_wisp"' in registry
)
crystal_bonuses = [
    float(re.search(r'"crystal_chance_bonus":\s*([0-9.]+)', line).group(1))
    for line in floor_lines
]
checks["deep floors have increasing bonus crystal-find probability"] = (
    len(crystal_bonuses) == 8 and crystal_bonuses == sorted(crystal_bonuses)
    and crystal_bonuses[0] == 0.0 and crystal_bonuses[-1] > 0.2
)

# Permanent unlock progression must be loaded, saved, bounded, and rollback on write failure.
checks["profile stores highest unlocked floor, defaults to one, and clamps to eight"] = (
    "var highest_unlocked_floor: int = 1" in game_state
    and 'saved.get("highest_unlocked_floor", 1)' in game_state
    and '"highest_unlocked_floor": highest_unlocked_floor' in game_state
    and "highest_unlocked_floor = 1" in game_state
)
checks["unlock API persists before acknowledging and rolls back on failure"] = (
    "func is_abyss_floor_unlocked(floor_number: int) -> bool:" in game_state
    and "func unlock_abyss_floor(floor_number: int) -> bool:" in game_state
    and "if not save_now():" in game_state
    and "highest_unlocked_floor = previous_floor" in game_state
)

# A checkpoint must preserve the floor decision and any killed boss whose escorts remain.
checks["save validation accepts only floor IDs 1..8 and boolean decision markers"] = (
    "snapshot.has(\"floor_id\")" in save_system
    and "int(floor_id_value) > ContentRegistry.ABYSS_FLOOR_COUNT" in save_system
    and 'snapshot.has("floor_choice_pending")' in save_system
    and 'snapshot.has("boss_defeated_encounter")' in save_system
)
checks["legacy snapshots receive only missing-field defaults, malformed explicit fields stay invalid"] = (
    'if not current.has("floor_id")' in save_system
    and 'if not current.has("floor_choice_pending")' in save_system
    and 'if not current.has("boss_defeated_encounter")' in save_system
    and 'typeof(snapshot.get("boss_defeated_encounter", null)) != TYPE_BOOL' in save_system
)

# Floor config drives live combat/danger/reward calculations; old difficulty presets are no longer runtime input.
checks["new runs require a previously unlocked floor and use that floor's start pressure"] = (
    "requested_floor_id: int = 1" in manager
    and "not GameState.is_abyss_floor_unlocked(requested_floor_id)" in manager
    and "floor_id = clampi(requested_floor_id, 1, ContentRegistry.ABYSS_FLOOR_COUNT)" in manager
    and "danger = maxf(1.0, float(floor_config.get(\"starting_danger\", 1.0)))" in manager
)
checks["live combat, events, healing and defeat retention use floor configuration"] = (
    "func get_floor_config() -> Dictionary:" in manager
    and "var encounter_difficulty: Dictionary = get_floor_config()" in manager
    and "var event_difficulty: Dictionary = get_floor_config()" in manager
    and "var active_difficulty: Dictionary = get_floor_config()" in manager
    and "var floor_definition: Dictionary = get_floor_config()" in manager
    and "DIFFICULTY_PRESETS.get(difficulty_id" not in manager
)

checks["floor draws route cards and selects biome enemy pools"] = (
    "floor_id: int = 1) -> Dictionary:" in tiles
    and 'floor_definition.get("tile_pool", [])' in tiles
    and 'floor_definition.get("enemy_pool", [])' in manager
    and "active_enemy_pool = floor_enemy_pool_value.duplicate(true)" in manager
    and "tile_system.draw_tile(_rng_for_draw(), false, [], floor_id)" in manager
    and "tile_system.draw_tile(run_rng, unlock_rare, [old_tile_id], floor_id)" in manager
)
checks["equipment and boss relic ranks scale with floor depth"] = (
    "abyss_floor: int = 1" in inventory
    and "floor_rank_bonus := int(floor(float(maxi(1, abyss_floor) - 1) / 2.0))" in inventory
    and '"abyss_floor": clampi(abyss_floor, 1, ContentRegistry.ABYSS_FLOOR_COUNT)' in inventory
    and "roll_boss_item(defeated_enemy, drop_rng, loop_count, int(hero.level), floor_id)" in manager
    and "roll_item(drop_rng, loop_count, int(hero.level), boss_rarity_bonus, floor_id)" in manager
)
checks["crystal resources get a floor-specific discovery chance"] = (
    'get_floor_config().get("crystal_chance_bonus", 0.0)' in manager
    and 'reward["crystals"] = maxi(0, int(reward.get("crystals", 0))) + 1' in manager
)
checks["floor, pending decision, and boss escort marker are checkpointed and restored"] = (
    '"floor_id": floor_id' in manager
    and '"floor_choice_pending": pending_floor_choice' in manager
    and '"boss_defeated_encounter": boss_defeated_encounter' in manager
    and 'snapshot.get("floor_choice_pending", false)' in manager
    and 'snapshot.get("boss_defeated_encounter", false)' in manager
)
checks["boss victory unlocks the next floor and delays the decision until encounter escorts clear"] = (
    "boss_defeated_encounter = true" in manager
    and "if boss_defeated_encounter:" in manager
    and "GameState.unlock_abyss_floor(floor_id + 1)" in manager
    and 'pending_floor_choice = true' in manager
)
checks["boss decision supports continuing, descending, and returning"] = (
    'func resolve_floor_choice(choice_id: String) -> Dictionary:' in manager
    and '"continue":' in manager
    and '"descend":' in manager
    and '"return":' in manager
    and '"next_floor_id": next_floor' in manager
)
checks["descending settles the current expedition before creating a new floor run"] = (
    'pending_floor_transition_id = next_floor' in manager
    and '_finish_run("return")' in manager
    and '"level": 1' in manager
    and 'bag.clear()' in manager
)

# UI exposes only unlocked floors, has no difficulty/contract picker, and restores boss modal on reload.
checks["base menu lists only floors already unlocked"] = (
    "floor_option = OptionButton.new()" in ui
    and "range(1, GameState.highest_unlocked_floor + 1)" in ui
    and "ContentRegistry.get_abyss_floor(floor_number)" in ui
)
checks["difficulty and contract selectors are absent from the base UI"] = (
    "DIFFICULTY_PRESETS" not in ui
    and "difficulty_option" not in ui
    and "selected_difficulty_id" not in ui
    and "contract_option" not in ui
    and "selected_contract_id" not in ui
)
checks["boss modal exposes the three intended choices"] = (
    "_try_show_boss_floor_choice()" in ui
    and "Продолжить на этом этаже" in ui
    and "Спуститься на этаж %d" in ui
    and "Вернуться на базу" in ui
)
render_expedition = ui.split("func _render_expedition() -> void:", 1)[1].split("\nfunc ", 1)[0]
checks["restored expedition reopens a saved pending boss decision"] = (
    "_sync_expedition_view(true)" in render_expedition
    and render_expedition.index("_sync_expedition_view(true)") < render_expedition.index("_try_show_boss_floor_choice()")
    and 'modal_kind in ["event", "perk", "floor_choice"' in ui
)
checks["next-floor transition starts a fresh run at level one with an empty backpack"] = (
    'manager.start_run("standard", next_seed, selected_modifier_id, "none", selected_expedition_mode_id, selected_floor_id)' in ui
    and "func _begin_next_floor_after_boss() -> void:" in ui
    and '\"level\": 1' in manager
    and "bag.clear()" in manager
)
checks["Godot smoke test now covers eight-floor progression instead of gameplay difficulty profiles"] = (
    "ContentRegistry.ABYSS_FLOOR_COUNT == 8" in smoke
    and "floor_smoke_manager.floor_id = 8" in smoke
    and "_scale_healing(100) == 72" in smoke
    and "difficulty_smoke_manager" not in smoke
)

failed = [name for name, passed in checks.items() if not passed]
for name, passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
assert not failed, "Abyss floor progression regression failed: " + ", ".join(failed)
print(f"ABYSS FLOOR PROGRESSION SOURCE REGRESSION PASSED: {len(checks)} assertions")
print("Source-level only; run tests/smoke_test.gd in Godot 4.7.2 before runtime acceptance.")
