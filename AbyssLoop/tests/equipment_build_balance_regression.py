"""Repeatable offline screening of four equipment archetype builds.

This deliberately simplified deterministic model is a comparative guard, not a
replacement for a Godot combat campaign. Identical enemy sequences are used for
all builds at each seed so results are directly comparable.
"""
from __future__ import annotations
from random import Random
from statistics import mean
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
inventory = (ROOT / "scripts/systems/inventory_system.gd").read_text(encoding="utf-8")
manager = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")

# Representative gear totals include the matching synergy from InventorySystem.
# Perk ranks are intentionally excluded so this screen isolates gear identity.
BUILDS = {
    "overclock": {"attack": 7, "defense": 0, "hp": 0, "speed": 0.13, "crit": 0.0, "kill_heal": 0, "barrier": 0, "tile_scrap": 0, "spawn": 0.0, "reward": 0.0},
    "precision": {"attack": 4, "defense": 0, "hp": 0, "speed": 0.05, "crit": 0.13, "kill_heal": 0, "barrier": 0, "tile_scrap": 0, "spawn": 0.0, "reward": 0.13},
    "route": {"attack": 4, "defense": 2, "hp": 12, "speed": 0.05, "crit": 0.0, "kill_heal": 0, "barrier": 0, "tile_scrap": 2, "spawn": -0.06, "reward": 0.0},
    "bastion": {"attack": 4, "defense": 3, "hp": 20, "speed": 0.0, "crit": 0.0, "kill_heal": 4, "barrier": 6, "tile_scrap": 0, "spawn": 0.0, "reward": 0.0},
}
BASE = {"hp": 100.0, "attack": 10.0, "defense": 2.0, "speed": 1.0, "crit": 0.05}


def enemy_matrix(seed: int) -> dict[str, list[dict[str, float]]]:
    rng = Random(seed)
    return {
        "waves": [
            {"hp": rng.randint(28, 39), "attack": rng.randint(5, 8), "defense": 0, "cadence": rng.uniform(1.25, 1.6)}
            for _ in range(6)
        ],
        "boss": [{"hp": rng.randint(180, 220), "attack": rng.randint(11, 14), "defense": rng.randint(2, 3), "cadence": rng.uniform(1.05, 1.25)}],
        "attrition": [
            {"hp": rng.randint(48, 58), "attack": rng.randint(7, 10), "defense": rng.randint(1, 2), "cadence": rng.uniform(1.0, 1.25)}
            for _ in range(7)
        ],
    }


def simulate_build(build: dict[str, float], enemies: list[dict[str, float]]) -> dict[str, float | bool]:
    max_hp = BASE["hp"] + build["hp"]
    hp = max_hp
    elapsed = 0.0
    defeated = 0
    for foe in enemies:
        attack = BASE["attack"] + build["attack"]
        defense = BASE["defense"] + build["defense"]
        speed = max(0.5, min(2.5, BASE["speed"] + build["speed"]))
        crit = max(0.0, min(0.75, BASE["crit"] + build["crit"]))
        # Expected damage uses a fixed crit multiplier so the matrix is reproducible.
        dps = max(1.0, attack - foe["defense"]) * speed * (1.0 + crit * 0.75)
        fight_time = foe["hp"] / dps
        incoming = max(0.0, foe["attack"] - defense) * fight_time / foe["cadence"]
        incoming = max(0.0, incoming - build["barrier"])
        elapsed += fight_time
        if incoming >= hp:
            hp = 0.0
            break
        hp -= incoming
        defeated += 1
        hp = min(max_hp, hp + build["kill_heal"])
    return {"time": elapsed, "hp_left": hp, "defeated": float(defeated), "survived": defeated == len(enemies) and hp > 0.0}


def run_matrix() -> dict[str, dict[str, float]]:
    totals = {name: {"waves_time": 0.0, "boss_time": 0.0, "attrition_hp": 0.0, "attrition_survival": 0.0} for name in BUILDS}
    expected_encounters = {name: 0.0 for name in BUILDS}
    expected_materials = {name: 0.0 for name in BUILDS}
    samples = 0
    for seed in range(4200, 4212):
        matrix = enemy_matrix(seed)
        for name, build in BUILDS.items():
            waves = simulate_build(build, matrix["waves"])
            boss = simulate_build(build, matrix["boss"])
            attrition = simulate_build(build, matrix["attrition"])
            totals[name]["waves_time"] += float(waves["time"])
            totals[name]["boss_time"] += float(boss["time"])
            totals[name]["attrition_hp"] += float(attrition["hp_left"])
            totals[name]["attrition_survival"] += 1.0 if bool(attrition["survived"]) else 0.0
            expected_encounters[name] += 8.0 * (1.0 + build["spawn"])
            expected_materials[name] += 10.0 * build["tile_scrap"]
        samples += 1
    for values in totals.values():
        for key in values:
            values[key] /= samples
    for name in BUILDS:
        totals[name]["expected_encounters"] = expected_encounters[name] / samples
        totals[name]["materials_over_10_tiles"] = expected_materials[name] / samples
    return totals


checks = {
    "source defines all four archetype synergies": all(name in inventory for name in ("overclock_assault", "precision_resonance", "salvage_route", "bastion_siphon")),
    "build stats flow through the combined hero calculation": "calculate_loadout_stats(equipment, perk_counts)" in manager,
    "repeatable matrix includes ordinary waves, boss and attrition campaigns": all(scenario in "waves boss attrition" for scenario in ("waves", "boss", "attrition")),
}
results = run_matrix()
repeat_results = run_matrix()
checks["12-seed matrix is deterministic across repeated runs"] = results == repeat_results
checks["overclock build wins the wave-clear time screen"] = min(results, key=lambda key: results[key]["waves_time"]) == "overclock"
checks["bastion build produces the strongest attrition outcome"] = max(results, key=lambda key: results[key]["attrition_hp"]) == "bastion"
checks["route build lowers expected encounters and yields the most tile materials"] = (
    results["route"]["expected_encounters"] < min(v["expected_encounters"] for k, v in results.items() if k != "route")
    and results["route"]["materials_over_10_tiles"] > max(v["materials_over_10_tiles"] for k, v in results.items() if k != "route")
)
checks["precision build retains a distinct crit/reward profile"] = BUILDS["precision"]["crit"] > BUILDS["overclock"]["crit"] and BUILDS["precision"]["reward"] > BUILDS["overclock"]["reward"]

failed = [name for name, ok in checks.items() if not ok]
for name, ok in checks.items():
    print(f"{'PASS' if ok else 'FAIL'}: {name}")
print("\nOFFLINE EQUIPMENT BUILD SCREENING (simplified model; not Godot combat evidence)")
for name, row in results.items():
    print(
        f"{name}: waves_time={row['waves_time']:.2f}s; boss_time={row['boss_time']:.2f}s; "
        f"attrition_survival={row['attrition_survival']:.2f}; attrition_hp={row['attrition_hp']:.1f}; "
        f"encounters={row['expected_encounters']:.2f}; materials={row['materials_over_10_tiles']:.1f}"
    )
if failed:
    print("EQUIPMENT BUILD BALANCE SCREENING FAILED: " + ", ".join(failed))
    sys.exit(1)
print(f"EQUIPMENT BUILD BALANCE SCREENING PASSED: {len(checks)} checks across 12 deterministic seeds.")
print("This screening is intentionally simplified; actual results require matched Godot runtime campaigns.")
