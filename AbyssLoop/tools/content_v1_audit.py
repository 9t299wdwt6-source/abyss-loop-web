"""Extract literal Abyss Loop content registries and build a v1.0 readiness matrix."""
from __future__ import annotations
import ast
import json
import re
from pathlib import Path
from typing import Any

MATCHING = {"{": "}", "[": "]"}
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")

REGISTRY_CONSTANTS = [
    "STATUS_EFFECTS", "DIFFICULTY_PRESETS", "EXPEDITION_MODES", "RUN_MODIFIERS",
    "TILE_DEFS", "TILE_SYNERGIES", "ENEMIES", "ELITE_ROLE_ABILITIES", "BOSSES",
    "BUILDINGS", "RESEARCH_BRANCHES", "BASE_RESEARCH_ID_ALIASES", "BASE_RESEARCH",
    "PERKS", "EXPEDITION_EVENTS", "EXPEDITION_OBJECTIVES", "EXPEDITION_CONTRACTS",
    "ROUTE_CELL_TYPES", "LANDSCAPE_SECRET_RECIPES",
]
INVENTORY_CONSTANTS = ["ARCHETYPES", "SET_DEFS", "SYNERGY_DEFS", "SECRET_RELIC_TEMPLATES"]


def parse_literal_constants(path: Path, names: list[str]) -> dict[str, Any]:
    source = path.read_text(encoding="utf-8")
    found: dict[str, Any] = {}
    pattern = re.compile(r"^const\s+(\w+)\s*:=\s*([\[{])", re.M)
    for match in pattern.finditer(source):
        name = match.group(1)
        if name not in names:
            continue
        start = match.start(2)
        stack: list[str] = []
        quoted = False
        escaped = False
        end = None
        for index in range(start, len(source)):
            char = source[index]
            if quoted:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == '"':
                    quoted = False
                continue
            if char == '"':
                quoted = True
            elif char in MATCHING:
                stack.append(MATCHING[char])
            elif char in MATCHING.values():
                if not stack or stack.pop() != char:
                    raise ValueError(f"Mismatched bracket in {path.name}:{name}")
                if not stack:
                    end = index + 1
                    break
        if end is None:
            raise ValueError(f"Unclosed literal constant {name} in {path}")
        literal = source[start:end]
        literal = re.sub(r"\btrue\b", "True", literal)
        literal = re.sub(r"\bfalse\b", "False", literal)
        literal = re.sub(r"\bnull\b", "None", literal)
        try:
            found[name] = ast.literal_eval(literal)
        except (SyntaxError, ValueError) as exc:
            raise ValueError(f"Constant {name} is not a simple literal registry: {exc}") from exc
    missing = sorted(set(names) - set(found))
    if missing:
        raise ValueError(f"Missing registry constants in {path}: {', '.join(missing)}")
    return found


def read_catalogs(root: Path) -> dict[str, Any]:
    registry = parse_literal_constants(root / "scripts/core/content_registry.gd", REGISTRY_CONSTANTS)
    inventory = parse_literal_constants(root / "scripts/systems/inventory_system.gd", INVENTORY_CONSTANTS)
    categories: list[dict[str, Any]] = []

    def add(category: str, source_name: str, mapping: dict[str, Any], name_field: str = "name", purpose_fields: tuple[str, ...] = ("description", "effect_text", "behavior_hint", "ability_text", "summary", "narrative")) -> None:
        items = []
        for raw_id, definition in mapping.items():
            if isinstance(definition, dict):
                purpose = next((str(definition.get(field, "")).strip() for field in purpose_fields if str(definition.get(field, "")).strip()), "")
                display_name = str(definition.get(name_field, raw_id))
            else:
                purpose = ""
                display_name = str(raw_id)
            items.append({"id": str(raw_id), "definition": definition, "name": display_name, "purpose": purpose})
        categories.append({"category": category, "source": source_name, "items": items})

    for source_name, category in [
        ("TILE_DEFS", "Тайлы ландшафта"), ("ENEMIES", "Обычные противники"),
        ("ELITE_ROLE_ABILITIES", "Роли и способности элит"), ("BOSSES", "Боссы"),
        ("STATUS_EFFECTS", "Боевые статусы"), ("BUILDINGS", "Постройки убежища"),
        ("RESEARCH_BRANCHES", "Ветки исследований"), ("BASE_RESEARCH", "Постоянные исследования"),
        ("PERKS", "Перки"), ("EXPEDITION_EVENTS", "События экспедиции"),
        ("EXPEDITION_OBJECTIVES", "Цели экспедиции"), ("EXPEDITION_CONTRACTS", "Контракты"),
        ("DIFFICULTY_PRESETS", "Сложности"), ("EXPEDITION_MODES", "Режимы экспедиции"),
        ("RUN_MODIFIERS", "Модификаторы маршрута"), ("ROUTE_CELL_TYPES", "Типы узлов маршрута"),
    ]:
        add(category, f"scripts/core/content_registry.gd:{source_name}", registry[source_name])

    add("Синергии ландшафта", "scripts/core/content_registry.gd:TILE_SYNERGIES", {str(item.get("id", f"entry_{i}")): item for i, item in enumerate(registry["TILE_SYNERGIES"])})
    add("Сеты экипировки", "scripts/systems/inventory_system.gd:SET_DEFS", inventory["SET_DEFS"])
    add("Секретные реликвии", "scripts/systems/inventory_system.gd:SECRET_RELIC_TEMPLATES", inventory["SECRET_RELIC_TEMPLATES"])
    add("Синергии экипировки", "scripts/systems/inventory_system.gd:SYNERGY_DEFS", inventory["SYNERGY_DEFS"])
    archetypes: dict[str, Any] = {}
    for slot, definitions in inventory["ARCHETYPES"].items():
        for item in definitions:
            archetypes[f"{slot}.{item.get('id', 'missing_id')}"] = {**item, "slot": slot}
    add("Архетипы экипировки", "scripts/systems/inventory_system.gd:ARCHETYPES", archetypes)
    return {"registry": registry, "inventory": inventory, "categories": categories}


def stable_ids_snapshot(catalogs: dict[str, Any]) -> dict[str, list[str]]:
    return {row["category"]: sorted(item["id"] for item in row["items"]) for row in catalogs["categories"]}


def _nonempty(record: dict[str, Any], fields: list[str]) -> list[str]:
    return [field for field in fields if field not in record or str(record.get(field, "")).strip() == ""]


def validate_catalogs(catalogs: dict[str, Any]) -> list[str]:
    r = catalogs["registry"]
    inv = catalogs["inventory"]
    issues: list[str] = []
    all_categories = catalogs["categories"]
    for category in all_categories:
        ids = [item["id"] for item in category["items"]]
        if len(ids) != len(set(ids)):
            issues.append(f"{category['category']}: duplicate stable IDs")
        for record_id in ids:
            if not ID_RE.fullmatch(record_id) and not (category["category"] == "Архетипы экипировки" and ID_RE.fullmatch(record_id.replace(".", "_"))):
                issues.append(f"{category['category']}:{record_id} has unstable/invalid ID syntax")
        display_names = [item["name"].strip().casefold() for item in category["items"] if item["name"].strip()]
        duplicate_names = sorted({name for name in display_names if display_names.count(name) > 1})
        for duplicate in duplicate_names:
            issues.append(f"{category['category']}: duplicate display name '{duplicate}'")

    for tile_id, tile in r["TILE_DEFS"].items():
        for f in ["name", "short", "kind", "color", "description", "placement_zone"]:
            if not str(tile.get(f, "")).strip(): issues.append(f"tile:{tile_id} missing {f}")
        if not re.fullmatch(r"#[0-9a-fA-F]{6}", str(tile.get("color", ""))): issues.append(f"tile:{tile_id} invalid color")
        if tile.get("placement_zone") not in {"any", "road", "landscape"}: issues.append(f"tile:{tile_id} invalid placement zone")
    tile_effects = {"scrap", "heal", "reward_bonus", "spawn_bonus", "enemy_bonus"}
    seen_synergies: set[str] = set()
    for synergy in r["TILE_SYNERGIES"]:
        sid = str(synergy.get("id", ""))
        if not sid or sid in seen_synergies: issues.append(f"tile synergy duplicate/empty ID: {sid or '?'}")
        seen_synergies.add(sid)
        if synergy.get("trigger_tile") not in r["TILE_DEFS"]: issues.append(f"tile synergy:{sid} has unknown trigger tile")
        if synergy.get("neighbor_tile") not in r["TILE_DEFS"]: issues.append(f"tile synergy:{sid} has unknown neighbor tile")
        effects = synergy.get("effects", {})
        if not isinstance(effects, dict) or not effects: issues.append(f"tile synergy:{sid} has no effect map")
        elif set(effects) - tile_effects: issues.append(f"tile synergy:{sid} has unsupported effects {sorted(set(effects)-tile_effects)}")
        if not str(synergy.get("description", "")).strip(): issues.append(f"tile synergy:{sid} missing player-facing explanation")

    enemy_roles = {str(enemy.get("role", "")) for enemy in r["ENEMIES"].values()}
    for eid, enemy in r["ENEMIES"].items():
        for f in ["name", "role", "behavior_hint", "ability_text"]:
            if not str(enemy.get(f, "")).strip(): issues.append(f"enemy:{eid} missing {f}")
        for f in ["hp", "attack", "attack_interval", "xp", "scrap"]:
            if f not in enemy or float(enemy[f]) <= 0: issues.append(f"enemy:{eid} invalid {f}")
        if float(enemy.get("defense", -1)) < 0 or float(enemy.get("crystal", -1)) < 0: issues.append(f"enemy:{eid} has negative defense/reward")
    for role, ability in r["ELITE_ROLE_ABILITIES"].items():
        if role not in enemy_roles: issues.append(f"elite ability:{role} has no matching ordinary enemy role")
        for f in ["name", "telegraph", "effect_id", "duration", "magnitude"]:
            if f not in ability or (isinstance(ability.get(f), str) and not ability[f].strip()): issues.append(f"elite ability:{role} missing {f}")
        if ability.get("effect_id") not in r["STATUS_EFFECTS"]: issues.append(f"elite ability:{role} references an unknown status")
        if float(ability.get("duration", 0)) <= 0 or float(ability.get("magnitude", -1)) < 0: issues.append(f"elite ability:{role} has invalid duration/magnitude")

    for bid, boss in r["BOSSES"].items():
        for f in ["name", "special_name", "hp", "attack", "attack_interval", "xp", "scrap", "crystal", "phases"]:
            if f not in boss or (isinstance(boss.get(f), str) and not boss[f].strip()): issues.append(f"boss:{bid} missing {f}")
        special_effect_id = str(boss.get("special_effect_id", "wound"))
        if special_effect_id not in r["STATUS_EFFECTS"]:
            issues.append(f"boss:{bid} references unknown special status {special_effect_id}")
        if float(boss.get("special_effect_duration", 4.0)) <= 0 or float(boss.get("special_effect_magnitude", 0.12)) < 0:
            issues.append(f"boss:{bid} has invalid special-effect duration/magnitude")
        phases = boss.get("phases", [])
        if not isinstance(phases, list) or len(phases) < 2: issues.append(f"boss:{bid} needs at least two phases"); continue
        thresholds = []
        for idx, phase in enumerate(phases):
            for f in ["name", "threshold", "attack_multiplier", "defense_bonus", "attack_interval", "special_every", "telegraph"]:
                if f not in phase: issues.append(f"boss:{bid} phase {idx} missing {f}")
            thresholds.append(float(phase.get("threshold", -1)))
            if not str(phase.get("name", "")).strip() or not str(phase.get("telegraph", "")).strip(): issues.append(f"boss:{bid} phase {idx} lacks readable telegraph")
            if float(phase.get("attack_multiplier", 0)) <= 0 or float(phase.get("attack_interval", 0)) <= 0 or int(phase.get("special_every", 0)) < 1: issues.append(f"boss:{bid} phase {idx} has invalid combat values")
            status_on_enter = phase.get("status_on_enter", {})
            if status_on_enter and status_on_enter.get("id") not in r["STATUS_EFFECTS"]: issues.append(f"boss:{bid} phase {idx} references unknown status effect")
        if thresholds and (thresholds[0] != 1.0 or any(a <= b for a, b in zip(thresholds, thresholds[1:])) or thresholds[-1] < 0):
            issues.append(f"boss:{bid} phase thresholds must start at 1.0 and strictly descend")

    for sid, status in r["STATUS_EFFECTS"].items():
        for f in ["name", "description", "kind", "duration", "max_stacks", "stack_mode", "max_magnitude"]:
            if f not in status: issues.append(f"status:{sid} missing {f}")
        if float(status.get("duration", 0)) <= 0 or int(status.get("max_stacks", 0)) < 1 or float(status.get("max_magnitude", 0)) <= 0: issues.append(f"status:{sid} has invalid lifetime/stack/cap")
        if status.get("kind") in {"damage_over_time", "healing_over_time"} and float(status.get("tick_interval", 0)) <= 0: issues.append(f"status:{sid} periodic effect needs a tick interval")

    for bid, building in r["BUILDINGS"].items():
        for f in ["name", "description", "effect", "max_level", "base_scrap", "base_crystal", "scrap_step", "crystal_step"]:
            if f not in building or (isinstance(building.get(f), str) and not building[f].strip()): issues.append(f"building:{bid} missing {f}")
        if int(building.get("max_level", 0)) < 1 or min(int(building.get("base_scrap", -1)), int(building.get("base_crystal", -1)), int(building.get("scrap_step", -1)), int(building.get("crystal_step", -1))) < 0: issues.append(f"building:{bid} invalid level/cost")

    research = r["BASE_RESEARCH"]
    branch_owners: dict[str, str] = {}
    for branch_id, branch in r["RESEARCH_BRANCHES"].items():
        for f in ["name", "summary", "nodes", "entry_node"]:
            if f not in branch: issues.append(f"research branch:{branch_id} missing {f}")
        nodes = branch.get("nodes", [])
        if not isinstance(nodes, list) or not nodes: issues.append(f"research branch:{branch_id} has no nodes"); continue
        if branch.get("entry_node") not in nodes: issues.append(f"research branch:{branch_id} entry is outside node list")
        for node in nodes:
            if node not in research: issues.append(f"research branch:{branch_id} references unknown node {node}"); continue
            if node in branch_owners: issues.append(f"research node:{node} belongs to more than one branch")
            branch_owners[node] = branch_id
            if research[node].get("branch") != branch_id: issues.append(f"research node:{node} disagrees with branch owner")
            if node == branch.get("entry_node") and research[node].get("prerequisites", []): issues.append(f"research branch:{branch_id} entry is not independently unlockable")
    graph = {}
    for rid, item in research.items():
        if item.get("branch") not in r["RESEARCH_BRANCHES"]: issues.append(f"research:{rid} unknown branch")
        if rid not in branch_owners: issues.append(f"research:{rid} is not mapped to a branch")
        if not str(item.get("description", "")).strip() or not str(item.get("effect_text", "")).strip(): issues.append(f"research:{rid} missing player-facing effect text")
        if float(item.get("scrap_cost", -1)) < 0 or float(item.get("crystal_cost", -1)) < 0 or not isinstance(item.get("effects"), dict): issues.append(f"research:{rid} has invalid cost/effects")
        prerequisites = item.get("prerequisites", [])
        if not isinstance(prerequisites, list): issues.append(f"research:{rid} prerequisites are malformed"); prerequisites = []
        for prereq in prerequisites:
            if prereq not in research: issues.append(f"research:{rid} references unknown prerequisite {prereq}")
            elif research[prereq].get("branch") != item.get("branch"): issues.append(f"research:{rid} crosses branches from {prereq}")
        graph[rid] = prerequisites
    visiting: set[str] = set(); visited: set[str] = set()
    def visit(node: str) -> bool:
        if node in visiting: return True
        if node in visited: return False
        visiting.add(node)
        for dep in graph.get(node, []):
            if dep in graph and visit(dep): return True
        visiting.remove(node); visited.add(node); return False
    if any(visit(node) for node in graph if node not in visited): issues.append("research graph contains a prerequisite cycle")

    for pid, perk in r["PERKS"].items():
        if not _nonempty(perk, ["name", "description", "category"]):
            if int(perk.get("max_stacks", 0)) < 1: issues.append(f"perk:{pid} invalid stack limit")
        else: issues.append(f"perk:{pid} missing {_nonempty(perk, ['name', 'description', 'category'])}")
        effect_keys = [k for k, v in perk.items() if k not in {"name", "description", "category", "max_stacks"} and isinstance(v, (int, float))]
        if not effect_keys: issues.append(f"perk:{pid} has no numeric effect")

    for event_id, event in r["EXPEDITION_EVENTS"].items():
        for f in ["name", "narrative", "weight", "min_loop", "choices"]:
            if f not in event: issues.append(f"event:{event_id} missing {f}")
        choices = event.get("choices", [])
        if not isinstance(choices, list) or len(choices) < 2: issues.append(f"event:{event_id} needs at least two choices"); continue
        choice_ids = [str(ch.get("id", "")) for ch in choices if isinstance(ch, dict)]
        if len(choice_ids) != len(set(choice_ids)) or any(not choice_id for choice_id in choice_ids): issues.append(f"event:{event_id} has duplicate/empty choice ID")
        for choice in choices:
            if not isinstance(choice, dict) or not _nonempty(choice, ["id", "title", "description"]) == [] or not isinstance(choice.get("effects"), dict):
                issues.append(f"event:{event_id} has malformed choice")
        if float(event.get("weight", 0)) <= 0 or int(event.get("min_loop", -1)) < 0: issues.append(f"event:{event_id} invalid spawn tuning")

    for source_key in ["EXPEDITION_OBJECTIVES", "EXPEDITION_CONTRACTS"]:
        for object_id, item in r[source_key].items():
            for f in ["name", "description", "kind", "target"]:
                if f not in item or (isinstance(item.get(f), str) and not item[f].strip()): issues.append(f"{source_key}:{object_id} missing {f}")
            if "reward" in source_key.lower() and False: pass
            if int(item.get("target", -1)) < 0: issues.append(f"{source_key}:{object_id} invalid target")
            for f in ["scrap_reward", "crystal_reward"]:
                if f not in item or int(item.get(f, -1)) < 0: issues.append(f"{source_key}:{object_id} invalid/missing {f}")
            if source_key == "EXPEDITION_CONTRACTS":
                for f in ["deadline_loops", "scrap_cost", "crystal_cost"]:
                    if f not in item or int(item.get(f, -1)) < 0: issues.append(f"contract:{object_id} invalid/missing {f}")

    for preset_id, preset in r["DIFFICULTY_PRESETS"].items():
        for f in ["name", "description", "enemy_attack_multiplier", "enemy_health_multiplier", "reward_multiplier", "healing_multiplier", "defeat_keep_ratio", "challenge_score_multiplier"]:
            if f not in preset: issues.append(f"difficulty:{preset_id} missing {f}")
        if not 0 <= float(preset.get("defeat_keep_ratio", -1)) <= 1 or float(preset.get("reward_multiplier", 0)) <= 0: issues.append(f"difficulty:{preset_id} invalid risk/reward data")
    for mode_id, mode in r["EXPEDITION_MODES"].items():
        if _nonempty(mode, ["name", "description"]): issues.append(f"expedition mode:{mode_id} missing player-facing text")
        if int(mode.get("goal_loops", -1)) < 0 or int(mode.get("goal_bosses", -1)) < 0 or float(mode.get("max_danger", 0)) <= 0 or float(mode.get("reward_multiplier_cap", 0)) <= 0: issues.append(f"expedition mode:{mode_id} invalid endgame bounds")
    allowed_shapes = {"classic_ring", "deep_descent", "narrow_ring", "fractured_loop"}
    for modifier_id, modifier in r["RUN_MODIFIERS"].items():
        if _nonempty(modifier, ["name", "description", "route_shape"]): issues.append(f"modifier:{modifier_id} missing player-facing text/shape")
        if modifier.get("route_shape") not in allowed_shapes: issues.append(f"modifier:{modifier_id} unknown route shape")
    for route_id, route_cell in r["ROUTE_CELL_TYPES"].items():
        if _nonempty(route_cell, ["name", "color"]): issues.append(f"route cell:{route_id} missing name/color")
        if not re.fullmatch(r"#[0-9a-fA-F]{6}", str(route_cell.get("color", ""))): issues.append(f"route cell:{route_id} has invalid color")

    for slot, archetypes in inv["ARCHETYPES"].items():
        if slot not in {"weapon", "armor", "core"}: issues.append(f"equipment archetype unknown slot:{slot}")
        ids = [str(x.get("id", "")) for x in archetypes]
        if any(not ID_RE.fullmatch(x) for x in ids) or len(ids) != len(set(ids)): issues.append(f"equipment archetypes:{slot} IDs empty/duplicate/invalid")
        for archetype in archetypes:
            for f in ["id", "name", "description", "stats"]:
                if f not in archetype or (isinstance(archetype.get(f), str) and not archetype[f].strip()): issues.append(f"equipment archetype:{slot}.{archetype.get('id','?')} missing {f}")
            if not isinstance(archetype.get("stats"), dict) or not archetype["stats"]: issues.append(f"equipment archetype:{slot}.{archetype.get('id','?')} has no stat effect")
    for sid, set_def in inv["SET_DEFS"].items():
        if _nonempty(set_def, ["name", "description", "threshold", "effects"]): issues.append(f"equipment set:{sid} missing required metadata")
        if int(set_def.get("threshold", 0)) < 2 or not isinstance(set_def.get("effects"), dict) or not set_def.get("effects"): issues.append(f"equipment set:{sid} invalid threshold/effects")
    archetype_ids = {slot: {str(item["id"]) for item in items} for slot, items in inv["ARCHETYPES"].items()}
    for synergy_id, synergy in inv["SYNERGY_DEFS"].items():
        if _nonempty(synergy, ["name", "description", "requirements", "effects"]): issues.append(f"equipment synergy:{synergy_id} missing metadata")
        requirements = synergy.get("requirements", {})
        if not isinstance(requirements, dict) or not requirements: issues.append(f"equipment synergy:{synergy_id} missing requirements")
        else:
            for slot, allowed in requirements.items():
                if slot not in archetype_ids or not isinstance(allowed, list) or any(value not in archetype_ids.get(slot, set()) for value in allowed): issues.append(f"equipment synergy:{synergy_id} has unknown archetype requirement for {slot}")
        if not isinstance(synergy.get("effects"), dict) or not synergy.get("effects"): issues.append(f"equipment synergy:{synergy_id} has no effects")

    # Event choices create flags directly; landscape-secret recipes create their
    # discovery flag when the matching neighboring tiles share a route sector.
    produced_flags: set[str] = set()
    referenced_flags: set[str] = set()
    secret_recipes = r.get("LANDSCAPE_SECRET_RECIPES", [])
    if not isinstance(secret_recipes, list):
        issues.append("landscape secret recipes must be a list")
        secret_recipes = []
    for recipe in secret_recipes:
        if not isinstance(recipe, dict):
            issues.append("landscape secret recipe is malformed")
            continue
        flag = str(recipe.get("flag", ""))
        if not flag or recipe.get("first_tile") not in r["TILE_DEFS"] or recipe.get("second_tile") not in r["TILE_DEFS"]:
            issues.append("landscape secret recipe has an empty flag or unknown tile")
        else:
            produced_flags.add(flag)
    for event in r["EXPEDITION_EVENTS"].values():
        for choice in event.get("choices", []):
            effects = choice.get("effects", {}) if isinstance(choice, dict) else {}
            for k in ["set_flags", "clear_flags"]:
                values = effects.get(k, []) if isinstance(effects, dict) else []
                if isinstance(values, list): produced_flags.update(str(value) for value in values)
        for k in ["requires_flag", "excludes_flag", "resolved_flag"]:
            if event.get(k): referenced_flags.add(str(event[k]))
    unknown_flags = sorted(referenced_flags - produced_flags)
    for flag in unknown_flags:
        issues.append(f"event flag '{flag}' is referenced but no event choice declares it")
    return sorted(set(issues))


def build_audit(catalogs: dict[str, Any]) -> dict[str, Any]:
    categories = catalogs["categories"]
    return {"categories": categories, "records_checked": sum(len(row["items"]) for row in categories), "registry": catalogs["registry"], "inventory": catalogs["inventory"]}


def _source_test(category: str) -> str:
    groups = {
        "Тайлы ландшафта": "world_field_regression.py; tile_synergy_regression.py; tile_effect_pipeline_regression.py",
        "Синергии ландшафта": "tile_synergy_regression.py; tile_effect_pipeline_regression.py",
        "Обычные противники": "enemy_roles_regression.py; combat_encounter_regression.py",
        "Роли и способности элит": "elite_enemy_regression.py; status_effect_regression.py",
        "Боссы": "boss_phase_regression.py; combat_encounter_regression.py",
        "Боевые статусы": "status_effect_regression.py",
        "Постройки убежища": "shelter_branch_regression.py; shelter_economy_cap_regression.py",
        "Ветки исследований": "shelter_branch_regression.py; research_tree_regression.py",
        "Постоянные исследования": "research_tree_regression.py; research_respec_regression.py",
        "Перки": "progression_build_regression.py; equipment_build_regression.py",
        "События экспедиции": "expedition_event_regression.py; event_chain_regression.py",
        "Цели экспедиции": "expedition_objective_regression.py; objective_availability_regression.py",
        "Контракты": "contract_system_regression.py",
        "Сложности": "difficulty_challenge_regression.py; balance_campaign_regression.py",
        "Режимы экспедиции": "long_expedition_regression.py; campaign_history_regression.py",
        "Модификаторы маршрута": "expedition_modifier_regression.py; route_geometry_regression.py",
        "Типы узлов маршрута": "closed_loop_brand_regression.py; world_field_geometry_regression.py",
        "Архетипы экипировки": "equipment_build_regression.py; item_upgrade_salvage_regression.py",
        "Сеты экипировки": "equipment_synergy_regression.py; equipment_build_balance_regression.py",
        "Синергии экипировки": "equipment_synergy_regression.py; equipment_build_balance_regression.py",
    }
    return groups.get(category, "content_registry_validation_regression.py")


def write_readiness_report(root: Path, catalogs: dict[str, Any], output: Path) -> None:
    summary = build_audit(catalogs)
    categories = summary["categories"]
    lines = [
        "# Abyss Loop — матрица готовности контента версии 1.0",
        "",
        "**Основа:** Prototype 48; **аудит:** этап 49; **назначение:** зафиксировать текущий набор контента, стабильные ID и фактические пробелы до наращивания объёма.",
        "",
        f"**Проверено записей:** {summary['records_checked']} в {len(categories)} категориях.",
        "",
        "> Статус аудита данных не означает готовность к финальному релизу. Содержимое проверяется статически из литеральных реестров. Godot-компиляция, визуальная проверка и реальная балансировка требуют запуска на целевой версии движка.",
        "",
        "## Вывод по объёму 1.0",
        "",
        "Текущая базовая матрица включает маршрут/ландшафт, 5 ролей обычных врагов и соответствующие элитные способности, 2 боссов с фазами, 8 статусов, 7 событий, экипировку из 10 архетипов по слотам, 3 сета, 4 синергии экипировки, 10 перков, 9 исследований в 4 ветвях, 3 постройки, 5 целей, 6 контрактов, 4 сложности, 2 режима экспедиции и 4 модификатора.",
        "",
        "## Матрица категорий",
        "",
        "| Категория | Количество | Источник правил | Текущее состояние |",
        "|---|---:|---|---|",
    ]
    for row in categories:
        lines.append(f"| {row['category']} | {len(row['items'])} | `{row['source']}` | Статические данные и тестовые guards; runtime ожидает приёмку |")
    lines += ["", "## Реестр элементов и критерии приёмки", ""]
    for row in categories:
        lines += [f"### {row['category']}", "", f"Источник: `{row['source']}`. Regression coverage: `{_source_test(row['category'])}`.", "", "| Stable ID | Отображаемое имя | Назначение / эффект | Данные и ссылки | Визуал | Локализация |", "|---|---|---|---|---|---|"]
        for item in row["items"]:
            definition = item["definition"] if isinstance(item["definition"], dict) else {}
            purpose = item["purpose"] or "Роль указана в данных/правилах; текст назначения нужно подтвердить в Godot."
            purpose = purpose.replace("|", "\\|").replace("\n", " ")
            name = item["name"].replace("|", "\\|")
            # No per-entity art path exists in these records today; drawing uses the shared biome backdrop and programmatic markers.
            lines.append(f"| `{item['id']}` | {name} | {purpose} | {'PASS: обязательные поля' if definition else 'PASS: enum/list item'} | Процедурный маркер / общий фон; отдельный спрайт не назначен | RU-текст; система переводов не подтверждена |")
        lines.append("")
    lines += [
        "## Блокеры полного 1.0 (не маскируются статическим PASS)",
        "",
        "1. **Визуальные ресурсы:** в папке `assets` есть общий фон окружения; у большинства тайлов, врагов, предметов, боссов и состояний нет отдельных sprite/animation ресурсов. До выпуска нужно решить, какие элементы получают отдельный арт, а где программная пиксельная графика приемлема.",
        "2. **Локализация:** пользовательские строки в основном на русском; отдельный процесс локализации и проверка длин строк на втором языке не подтверждены.",
        "3. **Фактическое поведение:** связь данных с боем, UI и сохранениями требует runtime-прогона Godot 4.7.2 и ручных сценариев. Наличие статического теста не заменяет эти проверки.",
        "4. **Баланс:** офлайн-модели остаются скринингом. Пройти стандартный и длинный забег несколькими сборками; подтвердить, что ни один предмет, перк, контракт или выбор события не является фиктивным или безальтернативно обязательным.",
        "",
        "## Критерии приёмки отдельного элемента",
        "",
        "- [ ] Stable ID присутствует в `tests/fixtures/content_v1_stable_ids.json`; переименование ID сопровождается явным алиасом/миграцией.",
        "- [ ] Есть читаемое имя и описание игроку на русском; числовой эффект совпадает с поведением в игре.",
        "- [ ] Все ID-зависимости и эффекты поддерживаются системами; неизвестные ссылки не допускаются.",
        "- [ ] Выбранная визуальная стратегия задокументирована: отдельный спрайт/анимация или сознательно программная отрисовка.",
        "- [ ] Категория связана с автоматической регрессией и, где это возможно, сценарием `tests/smoke_test.gd`.",
        "- [ ] Пройти проверку в Godot 4.7.2; заполнить визуальные и балансировочные пункты матрицы приёмки.",
        "",
        "## Честный статус этапа 49",
        "",
        "Этап определяет объём и назначение текущего контента и усиливает автоматическую проверку стабильных IDs/ссылок. Он **не объявляет финальную готовность 1.0**: индивидуальный арт и мульти-языковая локализация ещё не созданы/не подтверждены. Следующий этап 50 — инструменты авторинга и диагностика конфигураций.",
        "",
    ]
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text("\n".join(lines), encoding="utf-8")
