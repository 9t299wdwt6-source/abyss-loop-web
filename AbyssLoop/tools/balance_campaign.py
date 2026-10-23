#!/usr/bin/env python3
"""Deterministic Monte Carlo screening for Abyss Loop combat values.

This tool does not execute GDScript. It is a *screening approximation*, not a replacement for Godot gameplay. It
reads entity coefficients from ContentRegistry and simulates representative
single encounters, using configured growth, attack cadence, group sizes, boss
phases and telegraphed boss specials. It estimates earlier-loop experience,
choices from the configured perk catalogue, and expected equipment-slot
occupancy. Actual tile placement, event effects, health attrition between fights,
real item rolls and set completion are not simulated; the generated report
spells out these limits so screening is not mistaken for a full playtest.
"""
from __future__ import annotations
import argparse
import hashlib
import math
import random
import re
import statistics
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REGISTRY = ROOT / "scripts/core/content_registry.gd"
DEFAULT_REPORT = ROOT / "tests/reports/BALANCE_CAMPAIGN_REPORT_RU.md"


def const_block(source: str, name: str) -> str:
    marker = f"const {name} :="
    start = source.find(marker)
    if start < 0:
        raise ValueError(f"Missing registry constant {name}")
    brace = source.find("{", start + len(marker))
    if brace < 0:
        raise ValueError(f"Missing dictionary for {name}")
    depth = 0
    quoted = False
    escaped = False
    for i in range(brace, len(source)):
        ch = source[i]
        if quoted:
            if escaped:
                escaped = False
            elif ch == "\\":
                escaped = True
            elif ch == '"':
                quoted = False
            continue
        if ch == '"':
            quoted = True
        elif ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1:i]
    raise ValueError(f"Unbalanced dictionary for {name}")


def top_level_entries(block: str) -> dict[str, str]:
    """Parse top-level GDScript dictionary entries; nested dictionaries stay intact."""
    result: dict[str, str] = {}
    i = 0
    while i < len(block):
        key_match = re.search(r'"([A-Za-z0-9_]+)"\s*:\s*\{', block[i:])
        if not key_match:
            break
        key = key_match.group(1)
        entry_open = i + key_match.end() - 1
        depth = 0
        quoted = False
        escaped = False
        end = entry_open
        for j in range(entry_open, len(block)):
            ch = block[j]
            if quoted:
                if escaped:
                    escaped = False
                elif ch == "\\":
                    escaped = True
                elif ch == '"':
                    quoted = False
                continue
            if ch == '"':
                quoted = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    end = j
                    break
        result[key] = block[entry_open + 1:end]
        i = end + 1
    return result


def field_number(text: str, key: str, default: float = 0.0) -> float:
    match = re.search(r'"' + re.escape(key) + r'"\s*:\s*(-?(?:\d+\.\d+|\d+))', text)
    return float(match.group(1)) if match else default


def field_string(text: str, key: str, default: str = "") -> str:
    match = re.search(r'"' + re.escape(key) + r'"\s*:\s*"([^"]*)"', text)
    return match.group(1) if match else default


def parse_profiles(source: str, name: str) -> dict[str, dict]:
    result: dict[str, dict] = {}
    for key, body in top_level_entries(const_block(source, name)).items():
        d = {
            "name": field_string(body, "name", key),
            "enemy_attack_multiplier": field_number(body, "enemy_attack_multiplier", 1.0),
            "enemy_health_multiplier": field_number(body, "enemy_health_multiplier", 1.0),
            "enemy_defense_multiplier": field_number(body, "enemy_defense_multiplier", 1.0),
            "encounter_chance_delta": field_number(body, "encounter_chance_delta", 0.0),
            "danger_growth_multiplier": field_number(body, "danger_growth_multiplier", 1.0),
            "event_damage_multiplier": field_number(body, "event_damage_multiplier", 1.0),
            "reward_multiplier": field_number(body, "reward_multiplier", 1.0),
            "extra_group_members": int(field_number(body, "extra_group_members", 0)),
            "starting_tile_delta": int(field_number(body, "starting_tile_delta", 0)),
        }
        phase_matches = re.findall(
            r'\{"threshold":\s*([\d.]+),\s*"name":\s*"([^"]+)",\s*"attack_multiplier":\s*([\d.]+),\s*"defense_bonus":\s*(\d+),\s*"attack_interval":\s*([\d.]+),\s*"special_every":\s*(\d+),\s*"telegraph":\s*"([^"]+)"\}',
            body,
        )
        if phase_matches:
            d["phases"] = [
                {"threshold": float(a), "name": b, "attack_multiplier": float(c),
                 "defense_bonus": int(dd), "attack_interval": float(e),
                 "special_every": int(ff), "telegraph": g}
                for a, b, c, dd, e, ff, g in phase_matches
            ]
        d["hp"] = int(field_number(body, "hp", 0))
        d["attack"] = field_number(body, "attack", 0)
        d["defense"] = int(field_number(body, "defense", 0))
        d["attack_interval"] = field_number(body, "attack_interval", 1.0)
        d["role"] = field_string(body, "role", "normal")
        d["xp"] = int(field_number(body, "xp", 0))
        d["scrap"] = int(field_number(body, "scrap", 0))
        d["crystal"] = int(field_number(body, "crystal", 0))
        d["defense_bonus_after_loop"] = int(field_number(body, "defense_bonus_after_loop", 999999))
        result[key] = d
    return result


def damage(atk: float, defense: float, crit: float, rng: random.Random, crit_mult: float) -> int:
    value = max(1.0, atk - defense * 0.48)
    if rng.random() < max(0.0, min(0.75, crit)):
        value *= crit_mult
    return max(1, int(round(value * rng.uniform(0.9, 1.1))))


def make_foe(definition: dict, loop: int, danger: float, difficulty: dict, modifier: dict, balance: dict, rng: random.Random) -> dict:
    scaling = 1.0 + max(0, loop) * balance["enemy_loop_scaling"] + max(0.0, danger - 1.0) * balance["enemy_danger_scaling"]
    hp = max(1, round(definition["hp"] * scaling * difficulty["enemy_health_multiplier"] * modifier["enemy_health_multiplier"]))
    attack = max(1.0, definition["attack"] * (1.0 + max(0.0, scaling - 1.0) * balance["enemy_attack_scaling"]) * difficulty["enemy_attack_multiplier"] * modifier["enemy_attack_multiplier"])
    defense = definition["defense"] + (1 if loop >= definition["defense_bonus_after_loop"] else 0)
    defense = max(0, round(defense * difficulty["enemy_defense_multiplier"] * modifier["enemy_defense_multiplier"]))
    return {"name": definition["name"], "role": definition["role"], "hp": hp, "max_hp": hp,
            "attack": attack, "base_attack": attack, "defense": defense, "base_defense": defense,
            "attack_interval": definition["attack_interval"], "attack_timer": 0.0, "attack_count": 0,
            "is_boss": False, "phases": [], "phase_index": 0, "special_every": 99,
            "telegraph_pending": False, "xp": definition["xp"], "scrap": definition["scrap"]}


def make_boss(definition: dict, loop: int, danger: float, difficulty: dict, modifier: dict, balance: dict) -> dict:
    interval = max(1, int(balance["boss_loop_interval"]))
    cycle_index = max(1, loop // interval)
    scale = 1.0 + max(0, cycle_index - 1) * balance["boss_cycle_scaling"] + max(0.0, danger - 1.0) * balance["boss_danger_scaling"]
    hp = max(1, round(definition["hp"] * scale * difficulty["enemy_health_multiplier"] * modifier["enemy_health_multiplier"]))
    base_attack = max(1.0, definition["attack"] * (1 + max(0.0, scale - 1) * balance["boss_attack_scaling"]) * difficulty["enemy_attack_multiplier"] * modifier["enemy_attack_multiplier"])
    base_defense = max(0, round((definition["defense"] + max(0, cycle_index - 1)) * difficulty["enemy_defense_multiplier"] * modifier["enemy_defense_multiplier"]))
    phases = definition.get("phases", [])
    phase = phases[0] if phases else {"threshold": 1.0, "attack_multiplier": 1.0, "defense_bonus": 0, "attack_interval": definition["attack_interval"], "special_every": 3}
    return {"name": definition["name"], "role": "boss", "hp": hp, "max_hp": hp,
            "attack": base_attack * phase["attack_multiplier"], "base_attack": base_attack,
            "defense": base_defense + phase["defense_bonus"], "base_defense": base_defense,
            "attack_interval": phase["attack_interval"], "attack_timer": 0.0, "attack_count": 0,
            "is_boss": True, "phases": phases, "phase_index": 0, "special_every": phase["special_every"],
            "telegraph_pending": False, "special_name": definition.get("special_name", "Особая атака")}


def _perk_score(perk: dict, build_id: str) -> float:
    attack = field_number(perk.get("raw", ""), "attack", 0.0)
    hp = field_number(perk.get("raw", ""), "hp", 0.0)
    defense = field_number(perk.get("raw", ""), "defense", 0.0)
    speed = field_number(perk.get("raw", ""), "speed", 0.0)
    crit = field_number(perk.get("raw", ""), "crit", 0.0)
    if build_id == "assault":
        return attack * 2.0 + speed * 18.0 + crit * 15.0 + defense * 0.65 + hp * 0.035
    if build_id == "guardian":
        return hp * 0.12 + defense * 2.7 + attack * 0.45 + speed * 7.0 + crit * 5.0
    return attack * 1.35 + hp * 0.085 + defense * 1.5 + speed * 12.0 + crit * 9.0


def estimate_progression(loop: int, difficulty: dict, modifier: dict, enemies: dict,
                         perk_definitions: dict, balance: dict, build_id: str, seed: int) -> dict:
    """Estimate typical levels and equipment collected before entering a loop.

    This is deliberately an expectation model, not a simulation of the whole run:
    it approximates previous-loop encounters and XP, drafts real configured perks,
    and estimates whether loot has populated each equipment slot.
    """
    rng = random.Random(seed ^ 0xA8B155)
    route_cells = max(1, int(balance.get("route_cells", 18)))
    base_chance = float(balance.get("encounter_chance_base", 0.22))
    chance_per_loop = float(balance.get("encounter_chance_per_loop", 0.04))
    min_chance = float(balance.get("encounter_chance_min", 0.08))
    max_chance = float(balance.get("encounter_chance_max", 0.96))
    enemy_xp_mean = sum(max(0.0, float(enemy.get("xp", 0))) for enemy in enemies.values()) / max(1, len(enemies))
    item_chance = max(0.0, min(1.0, float(balance.get("loot_item_chance", 0.18))))
    xp_pool = 0.0
    xp_next = 16
    level = 1
    perk_counts: dict[str, int] = {}
    perk_stats = {key: 0.0 for key in ["attack", "hp", "defense", "speed", "crit"]}
    expected_item_drops = 0.0
    weighted_item_rank = 0.0
    expected_encounters = 0.0
    expected_kills = 0.0
    available_perks = {key: {"raw": raw, "max_stacks": int(field_number(raw, "max_stacks", 1))} for key, raw in perk_definitions.items()}
    for prior_loop in range(max(0, loop)):
        danger = min(6.0, 1.0 + prior_loop * float(balance.get("loop_danger_growth", 0.18)) * float(difficulty.get("danger_growth_multiplier", 1.0)) * float(modifier.get("danger_growth_multiplier", 1.0)))
        chance = max(min_chance, min(max_chance, base_chance + prior_loop * chance_per_loop + float(difficulty.get("encounter_chance_delta", 0.0)) + float(modifier.get("encounter_chance_delta", 0.0))))
        encounters_this_loop = route_cells * chance
        extra_probability = 0.0
        if prior_loop >= 1:
            extra_probability = max(0.10, min(0.48, 0.10 + prior_loop * 0.075 + max(0.0, danger - 1.0) * 0.10))
        if prior_loop >= 4:
            extra_probability = 1.0
        extra_members = max(0, int(difficulty.get("extra_group_members", 0)) + int(modifier.get("extra_group_members", 0)))
        expected_group = min(float(balance.get("max_encounter_enemies", 3)), 1.0 + extra_probability + extra_members)
        kills_this_loop = encounters_this_loop * expected_group
        expected_encounters += encounters_this_loop
        expected_kills += kills_this_loop
        loot_this_loop = kills_this_loop * item_chance
        expected_item_drops += loot_this_loop
        weighted_item_rank += loot_this_loop * (1 + int(prior_loop // 2) + int(level // 3))
        xp_pool += kills_this_loop * enemy_xp_mean
        while xp_pool >= xp_next and level < 30:
            xp_pool -= xp_next
            level += 1
            xp_next = int(math.ceil(xp_next * 1.28 + 3.0))
            choices: list[str] = [key for key, definition in available_perks.items() if perk_counts.get(key, 0) < definition["max_stacks"]]
            if not choices:
                perk_stats["attack"] += 1.0
                continue
            draft = rng.sample(choices, min(3, len(choices)))
            selected = max(draft, key=lambda key: _perk_score(available_perks[key], build_id))
            raw = available_perks[selected]["raw"]
            for stat in perk_stats:
                perk_stats[stat] += field_number(raw, stat, 0.0)
            perk_counts[selected] = perk_counts.get(selected, 0) + 1
    mean_rank = weighted_item_rank / expected_item_drops if expected_item_drops > 0 else 1.0
    slot_chance = 1.0 - math.exp(-expected_item_drops / 3.0)
    # Expected values from InventorySystem.roll_item; the model intentionally avoids
    # pretending to know which random archetype or persistent loadout the player has.
    gear = {key: 0.0 for key in ["attack", "hp", "defense", "speed", "crit"]}
    gear["attack"] += slot_chance * (1.5 + 0.5 * mean_rank + 2.0 / 3.0)  # weapon base plus average assault archetype
    gear["hp"] += slot_chance * (4.0 + 2.0 * mean_rank + 5.0 / 3.0)  # armor base plus average bastion archetype
    gear["defense"] += slot_chance * (1.0 + 0.25 * mean_rank)
    gear["attack"] += slot_chance * (0.3 * mean_rank)  # core's average attack component
    gear["speed"] += slot_chance * (0.04 + min(0.13, mean_rank * 0.015))
    gear["crit"] += slot_chance * (0.025 + min(0.07, mean_rank * 0.008))
    set_probability = slot_chance * slot_chance / 3.0
    gear["hp"] += set_probability * (8.0 / 3.0)
    gear["defense"] += set_probability * (2.0 / 3.0)
    gear["crit"] += set_probability * (0.025 / 3.0)
    return {
        "level": level, "perk_stats": perk_stats, "gear_stats": gear,
        "expected_encounters": expected_encounters, "expected_kills": expected_kills,
        "expected_item_drops": expected_item_drops, "mean_item_rank": mean_rank,
    }


def simulate_fight(seed: int, loop: int, difficulty: dict, modifier: dict, enemies: dict, bosses: dict,
                   balance: dict, build: dict, progression: dict) -> tuple[bool, int, float]:
    rng = random.Random(seed)
    perk_stats = progression["perk_stats"]
    gear_stats = progression["gear_stats"]
    max_hp = max(1, int(round(float(balance["base_hp"]) + build["hp"] + perk_stats["hp"] + gear_stats["hp"])))
    hero = {"hp": max_hp, "max_hp": max_hp,
            "attack": float(balance["base_attack"]) + build["attack"] + perk_stats["attack"] + gear_stats["attack"],
            "defense": max(0, int(round(float(balance["base_defense"]) + build["defense"] + perk_stats["defense"] + gear_stats["defense"]))),
            "crit": min(0.75, max(0.0, build["crit"] + perk_stats["crit"] + gear_stats["crit"])),
            "attack_speed": max(0.35, build["speed"] + perk_stats["speed"] + gear_stats["speed"])}
    boss_fight = loop > 0 and loop % max(1, int(balance["boss_loop_interval"])) == 0
    danger = min(6.0, 1.0 + loop * float(balance["loop_danger_growth"]) * float(difficulty["danger_growth_multiplier"]) * float(modifier["danger_growth_multiplier"]))
    if boss_fight:
        boss_keys = sorted(bosses)
        boss_def = bosses[boss_keys[((loop // max(1, int(balance["boss_loop_interval"]))) - 1) % len(boss_keys)]]
        foes = [make_boss(boss_def, loop, danger, difficulty, modifier, balance)]
    else:
        ids = sorted(enemies)
        first = rng.choice(ids)
        pack_size = 1
        if loop >= 4:
            pack_size = 2
        elif loop >= 1:
            chance = max(0.10, min(0.48, 0.10 + loop * 0.075 + max(0.0, danger - 1.0) * 0.10))
            if rng.random() < chance:
                pack_size = 2
        if loop >= 5 and pack_size >= 2 and rng.random() < float(balance["three_enemy_pack_chance"]):
            pack_size = 3
        pack_size = min(int(balance["max_encounter_enemies"]), pack_size + difficulty["extra_group_members"] + modifier["extra_group_members"])
        chosen = [first] + [rng.choice(ids) for _ in range(pack_size - 1)]
        foes = [make_foe(enemies[enemy_id], loop, danger, difficulty, modifier, balance, rng) for enemy_id in chosen]
        # Support enemies are put behind the front line in the production game.
        foes = [f for f in foes if f["role"] != "support"] + [f for f in foes if f["role"] == "support"]
        for index, foe in enumerate(foes[1:], start=1):
            foe["attack_timer"] = -foe["attack_interval"] * 0.42 * index
    dt = 0.05
    elapsed = 0.0
    hero_timer = 0.0
    debuff_remaining = 0.0
    speed_penalty = 0.0
    while elapsed < 120.0:
        elapsed += dt
        if debuff_remaining > 0:
            debuff_remaining = max(0.0, debuff_remaining - dt)
            if debuff_remaining == 0:
                speed_penalty = 0.0
        hero_timer += dt
        hero_interval = max(0.24, float(balance["hero_attack_interval"]) / max(0.35, hero["attack_speed"] - speed_penalty))
        if hero_timer >= hero_interval:
            hero_timer -= hero_interval
            target = next((foe for foe in foes if foe["hp"] > 0), None)
            if target is None:
                hp_ratio = max(0.0, hero["hp"] / max(1, hero["max_hp"]))
                return True, hero["hp"], elapsed
            dealt = damage(hero["attack"], target["defense"], hero["crit"], rng, float(balance["critical_multiplier"]))
            target["hp"] = max(0, target["hp"] - dealt)
            if target["is_boss"] and target["hp"] > 0:
                phase_next = target["phase_index"] + 1
                if phase_next < len(target["phases"]):
                    phase = target["phases"][phase_next]
                    if target["hp"] / max(1, target["max_hp"]) <= phase["threshold"]:
                        target["phase_index"] = phase_next
                        target["attack"] = target["base_attack"] * phase["attack_multiplier"]
                        target["defense"] = target["base_defense"] + phase["defense_bonus"]
                        target["attack_interval"] = max(0.55, phase["attack_interval"])
                        target["special_every"] = max(2, phase["special_every"])
                        target["telegraph_pending"] = False
        for foe in foes:
            if foe["hp"] <= 0:
                continue
            foe["attack_timer"] += dt
            if foe["attack_timer"] < max(0.35, foe["attack_interval"]):
                continue
            foe["attack_timer"] -= max(0.35, foe["attack_interval"])
            if foe["role"] == "support":
                allies = [ally for ally in foes if ally is not foe and ally["hp"] > 0 and ally["hp"] < ally["max_hp"]]
                if allies:
                    weakest = min(allies, key=lambda ally: ally["hp"] / max(1, ally["max_hp"]))
                    weakest["hp"] = min(weakest["max_hp"], weakest["hp"] + max(3, round(weakest["max_hp"] * 0.12)))
                    continue
            attack_value = foe["attack"]
            if foe["is_boss"]:
                cadence = max(1, int(foe["special_every"]))
                next_count = foe["attack_count"] + 1
                is_special = next_count % cadence == 0
                if is_special and not foe["telegraph_pending"]:
                    foe["telegraph_pending"] = True
                    foe["attack_timer"] = 0.0
                    continue
                foe["attack_count"] = next_count
                if is_special:
                    foe["telegraph_pending"] = False
                    attack_value *= float(balance["boss_special_multiplier"])
            if foe["role"] == "hunter" and hero["hp"] / max(1, hero["max_hp"]) <= 0.35:
                attack_value *= 1.35
            dealt = damage(attack_value, hero["defense"], 0.05, rng, float(balance["critical_multiplier"]))
            hero["hp"] = max(0, hero["hp"] - dealt)
            if foe["role"] == "caster" and foe["attack_count"] > 0 and foe["attack_count"] % 3 == 0:
                speed_penalty = float(balance["enemy_caster_debuff"])
                debuff_remaining = float(balance["enemy_caster_debuff_duration"])
        if hero["hp"] <= 0:
            return False, 0, elapsed
        if not any(foe["hp"] > 0 for foe in foes):
            return True, hero["hp"], elapsed
    return False, 0, elapsed


def run_campaign(repetitions: int, source: str) -> list[dict]:
    balance_body = const_block(source, "BALANCE")
    balance = {k: field_number(balance_body, k, 0) for k in [
        "base_hp", "base_attack", "base_defense", "hero_attack_interval", "enemy_attack_interval",
        "critical_multiplier", "enemy_loop_scaling", "enemy_danger_scaling", "enemy_attack_scaling",
        "boss_loop_interval", "boss_cycle_scaling", "boss_danger_scaling", "boss_attack_scaling",
        "three_enemy_pack_chance", "max_encounter_enemies", "boss_special_multiplier",
        "loop_danger_growth", "enemy_caster_debuff", "enemy_caster_debuff_duration",
        "route_cells", "encounter_chance_base", "encounter_chance_per_loop", "encounter_chance_min",
        "encounter_chance_max", "loot_item_chance"
    ]}
    registry = source
    # Entity parsers need full registry text, not just one block.
    enemies = parse_profiles(registry, "ENEMIES")
    bosses = parse_profiles(registry, "BOSSES")
    difficulties = parse_profiles(registry, "DIFFICULTY_PRESETS")
    modifiers = parse_profiles(registry, "RUN_MODIFIERS")
    perks = top_level_entries(const_block(registry, "PERKS"))
    builds = {
        "balanced": {"attack": 0, "hp": 0, "defense": 0, "speed": 1.0, "crit": 0.05},
        "assault": {"attack": 4, "hp": 0, "defense": 0, "speed": 1.08, "crit": 0.10},
        "guardian": {"attack": 1, "hp": 18, "defense": 2, "speed": 0.94, "crit": 0.05},
    }
    results: list[dict] = []
    for diff_id, diff in difficulties.items():
        for mod_id, mod in modifiers.items():
            for build_id, build in builds.items():
                for tier, loop in [("старт", 0), ("середина", 2), ("босс", 3)]:
                    progression_seed_text = f"progression|{diff_id}|{mod_id}|{build_id}|{tier}"
                    progression_seed = int.from_bytes(hashlib.sha256(progression_seed_text.encode("utf-8")).digest()[:8], "little")
                    progression = estimate_progression(loop, diff, mod, enemies, perks, balance, build_id, progression_seed)
                    wins = 0
                    hp_values: list[int] = []
                    times: list[float] = []
                    for run_idx in range(repetitions):
                        # Stable seed derived from scenario identity avoids dependence on iteration order.
                        seed_text = f"{diff_id}|{mod_id}|{build_id}|{tier}|{run_idx}"
                        seed = int.from_bytes(hashlib.sha256(seed_text.encode("utf-8")).digest()[:8], "little")
                        won, hp_left, duration = simulate_fight(seed, loop, diff, mod, enemies, bosses, balance, build, progression)
                        wins += int(won)
                        if won:
                            hp_values.append(hp_left)
                        times.append(duration)
                    results.append({
                        "difficulty": diff_id, "modifier": mod_id, "build": build_id, "tier": tier,
                        "repetitions": repetitions, "win_rate": wins / repetitions,
                        "median_hp_remaining": statistics.median(hp_values) if hp_values else 0,
                        "median_seconds": statistics.median(times), "wins": wins,
                        "estimated_level": progression["level"],
                        "estimated_attack_bonus": round(progression["perk_stats"]["attack"] + progression["gear_stats"]["attack"], 1),
                        "estimated_hp_bonus": round(progression["perk_stats"]["hp"] + progression["gear_stats"]["hp"], 1),
                        "estimated_defense_bonus": round(progression["perk_stats"]["defense"] + progression["gear_stats"]["defense"], 1),
                        "estimated_previous_encounters": round(progression["expected_encounters"], 1),
                        "estimated_item_drops": round(progression["expected_item_drops"], 1)
                    })
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runs", type=int, default=60, help="Number of seeded trials per scenario (default 60).")
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()
    if args.runs < 10 or args.runs > 1000:
        parser.error("--runs must be between 10 and 1000")
    source = REGISTRY.read_text(encoding="utf-8")
    rows = run_campaign(args.runs, source)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    lines = [
        "# Abyss Loop — балансировочный скрининг",
        "",
        f"Испытаний на сценарий: **{args.runs}**. Сценариев: **{len(rows)}**. Сидирование фиксировано для воспроизводимости.",
        "",
        "> Ограничение: это автоматизированная модель отдельных боёв, считывающая текущие коэффициенты из ContentRegistry. Она включает случайный урон/криты, масштабирование, состав групп, роли поддержки/ослабления, босс-фазы и телеграфированные особые атаки. Оценивает предшествующие циклы, средний опыт, выбор настроенных перков и ожидаемое получение предметов. Это приближённая модель: она не исполняет GDScript и не симулирует здоровье/события/тайлы на протяжении всей экспедиции; реальные броски предметов и завершение наборов также не моделируются. Результат — инструмент выявления очевидных перекосов, а не доказательство баланса.",
        "",
        "*Уровень/бонусы — ожидаемая оценка прогрессии до входа в выбранный цикл; это не реальный симулятор всей экспедиции.*",
        "",
        "## Сводка по уровню угрозы",
        "",
        "| Уровень | Модификатор | Сложность | Сборка | Уровень героя* | Бонус атаки* | Бонус HP* | Бонус защиты* | Победы | Медиана HP после победы | Медиана длительности, с |",
        "|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for row in rows:
        lines.append(f"| {row['tier']} | {row['modifier']} | {row['difficulty']} | {row['build']} | {row['estimated_level']} | +{row['estimated_attack_bonus']} | +{row['estimated_hp_bonus']} | +{row['estimated_defense_bonus']} | {row['win_rate']:.0%} ({row['wins']}/{row['repetitions']}) | {row['median_hp_remaining']} | {row['median_seconds']:.1f} |")
    grouped: dict[tuple[str, str], list[dict]] = {}
    for row in rows:
        grouped.setdefault((row["tier"], row["difficulty"]), []).append(row)
    lines.extend(["", "## Автоматические сигналы для анализа", ""])
    signals = 0
    for (tier, difficulty), group in sorted(grouped.items()):
        worst = min(group, key=lambda row: row["win_rate"])
        best = max(group, key=lambda row: row["win_rate"])
        if worst["win_rate"] < 0.50:
            lines.append(f"- **Высокий риск:** {tier}, {difficulty}: худший профиль {worst['modifier']}/{worst['build']} — победы {worst['win_rate']:.0%}.")
            signals += 1
        if best["win_rate"] > 0.98:
            lines.append(f"- **Потенциально тривиально:** {tier}, {difficulty}: {best['modifier']}/{best['build']} — победы {best['win_rate']:.0%}; проверить ценность получаемого риска/награды.")
            signals += 1
    if signals == 0:
        lines.append("- В этой модели не обнаружены сценарии с победами ниже 50% или выше 98%; это не исключает проблем в полной экспедиции.")
    lines.extend(["", "## Следующие действия", "", "1. Сопоставить результаты с ручными забегами в Godot 4.7.2.", "2. Отдельно прогнать сборки с тайлами, сет-бонусами, событиями и улучшениями убежища.", "3. Менять коэффициенты только при повторяемом перекосе; затем заново выполнять этот скрининг и runtime-проверки.", ""])
    args.report.write_text("\n".join(lines), encoding="utf-8")
    try:
        report_display = str(args.report.relative_to(ROOT))
    except ValueError:
        report_display = str(args.report)
    print(f"Wrote {report_display} with {len(rows)} scenarios × {args.runs} trials")
    for (tier, difficulty), group in sorted(grouped.items()):
        avg = statistics.mean(row["win_rate"] for row in group)
        print(f"{tier:8s} {difficulty:10s}: mean encounter win rate {avg:.1%}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
