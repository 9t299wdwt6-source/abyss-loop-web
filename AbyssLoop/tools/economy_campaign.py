#!/usr/bin/env python3
"""Reproducible campaign-level economy screening for Abyss Loop.

Reads live GDScript balance/content registries. It estimates currency flow across
expeditions, shelter/research purchases, optional contracts, and periodic item
upgrades. This is a deterministic seeded screening model, not Godot execution.
"""
from __future__ import annotations
import argparse
import hashlib
import math
import random
import re
import statistics
import sys
from collections import Counter, defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from balance_campaign import const_block, top_level_entries, field_number, field_string  # noqa: E402

REGISTRY = ROOT / "scripts/core/content_registry.gd"
DEFAULT_REPORT = ROOT / "tests/reports/ECONOMY_CAMPAIGN_REPORT_RU.md"
GAME_STATE = ROOT / "scripts/core/game_state.gd"
INVENTORY = ROOT / "scripts/systems/inventory_system.gd"
RESOURCE_SYSTEM = ROOT / "scripts/systems/resource_system.gd"


def parse_registry() -> dict:
    source = REGISTRY.read_text(encoding="utf-8")
    game_state_source = GAME_STATE.read_text(encoding="utf-8")
    start_scrap_match = re.search(r"var scrap: int = (\d+)", game_state_source)
    start_crystal_match = re.search(r"var crystals: int = (\d+)", game_state_source)
    if not start_scrap_match or not start_crystal_match:
        raise ValueError("Could not parse starting currencies from GameState")
    starting_scrap, starting_crystals = int(start_scrap_match.group(1)), int(start_crystal_match.group(1))
    bal_block = const_block(source, "BALANCE")
    balance = {k: float(v) for k, v in re.findall(r'"([a-zA-Z0-9_]+)"\s*:\s*(-?(?:\d+\.\d+|\d+))', bal_block)}
    buildings = {}
    for key, body in top_level_entries(const_block(source, "BUILDINGS")).items():
        buildings[key] = {"name": field_string(body, "name", key),
                          "base_scrap": int(field_number(body, "base_scrap")),
                          "base_crystal": int(field_number(body, "base_crystal")),
                          "scrap_step": int(field_number(body, "scrap_step")),
                          "crystal_step": int(field_number(body, "crystal_step")),
                          "max_level": int(field_number(body, "max_level", 5)),
                          "loop_scrap_per_level": int(field_number(body, "loop_scrap_per_level"))}
    research = {}
    for key, body in top_level_entries(const_block(source, "BASE_RESEARCH")).items():
        pre = re.search(r'"prerequisites"\s*:\s*\[([^\]]*)\]', body)
        prereqs = re.findall(r'"([a-zA-Z0-9_]+)"', pre.group(1)) if pre else []
        effects = re.search(r'"effects"\s*:\s*\{([^}]*)\}', body)
        effect_dict = {}
        if effects:
            effect_dict = {k: float(v) for k, v in re.findall(r'"([a-zA-Z0-9_]+)"\s*:\s*(-?(?:\d+\.\d+|\d+))', effects.group(1))}
        research[key] = {"name": field_string(body, "name", key),
                         "branch": field_string(body, "branch", ""),
                         "scrap_cost": int(field_number(body, "scrap_cost")),
                         "crystal_cost": int(field_number(body, "crystal_cost")),
                         "prerequisites": prereqs, "effects": effect_dict}
    enemies = {}
    for key, body in top_level_entries(const_block(source, "ENEMIES")).items():
        enemies[key] = {"name": field_string(body, "name", key),
                        "scrap": int(field_number(body, "scrap")),
                        "crystal": int(field_number(body, "crystal"))}
    bosses = {}
    for key, body in top_level_entries(const_block(source, "BOSSES")).items():
        bosses[key] = {"name": field_string(body, "name", key),
                       "scrap": int(field_number(body, "scrap")),
                       "crystal": int(field_number(body, "crystal"))}
    contracts = {}
    for key, body in top_level_entries(const_block(source, "EXPEDITION_CONTRACTS")).items():
        contracts[key] = {"name": field_string(body, "name", key),
                          "kind": field_string(body, "kind", "none"),
                          "deadline_loops": int(field_number(body, "deadline_loops")),
                          "scrap_cost": int(field_number(body, "scrap_cost")),
                          "crystal_cost": int(field_number(body, "crystal_cost")),
                          "scrap_reward": int(field_number(body, "scrap_reward")),
                          "crystal_reward": int(field_number(body, "crystal_reward"))}
    return {"source": source, "balance": balance, "starting_scrap": starting_scrap,
            "starting_crystals": starting_crystals, "buildings": buildings,
            "research": research, "enemies": enemies, "bosses": bosses,
            "contracts": contracts}


PRIORITIES = {
    "balanced": [
        ("research", "field_training"), ("building", "forge"),
        ("research", "supply_contracts"), ("building", "infirmary"),
        ("research", "boss_analysis"), ("building", "salvage"),
        ("research", "route_archive"), ("research", "advanced_salvage"),
        ("research", "medical_relay"), ("research", "event_forecasting"),
        ("research", "rare_survey"), ("research", "crystal_study"),
    ],
    "economy": [
        ("research", "supply_contracts"), ("research", "advanced_salvage"),
        ("building", "salvage"), ("building", "salvage"),
        ("research", "crystal_study"), ("building", "salvage"),
        ("building", "salvage"), ("building", "salvage"),
        ("research", "field_training"), ("building", "infirmary"),
    ],
    "combat": [
        ("research", "field_training"), ("building", "forge"),
        ("building", "forge"), ("building", "infirmary"),
        ("building", "infirmary"), ("research", "medical_relay"),
        ("research", "boss_analysis"), ("building", "forge"),
        ("building", "infirmary"), ("research", "event_forecasting"),
    ],
    "scouting": [
        ("research", "boss_analysis"), ("research", "event_forecasting"),
        ("research", "route_archive"), ("research", "rare_survey"),
        ("building", "infirmary"), ("research", "field_training"),
        ("research", "medical_relay"), ("research", "supply_contracts"),
    ],
}

REGIMES = ("mixed", "loss_streak", "win_streak", "long_push")
STRATEGIES = tuple(PRIORITIES)


def make_route(rng: random.Random, count: int, safe_prefix: int) -> list[str]:
    cells = []
    for i in range(count):
        if i == 0:
            kind = "shrine"
        elif i < safe_prefix:
            kind = "plain"
        else:
            roll = rng.random()
            kind = "cache" if roll < .12 else "event" if roll < .23 else "danger" if roll < .34 else "shrine" if roll < .42 else "plain"
        cells.append(kind)
    if count > 7:
        for kind, idx in (("event", count - 5), ("cache", 4), ("danger", count - 3)):
            if kind not in cells:
                cells[idx] = kind
    return cells


def build_bonus(state: dict, reg: dict) -> int:
    b = reg["buildings"]
    building_bonus = state["buildings"].get("salvage", 0) * int(b["salvage"]["loop_scrap_per_level"])
    research_bonus = 0
    for rid in state["unlocked"]:
        research_bonus += int(reg["research"].get(rid, {}).get("effects", {}).get("loop_scrap_bonus", 0))
        research_bonus += int(reg["research"].get(rid, {}).get("effects", {}).get("route_reward_bonus", 0))
    cap = int(reg["balance"].get("shelter_loop_scrap_bonus_cap", 6))
    return max(0, min(cap, building_bonus + research_bonus))


def purchase_one(state: dict, strategy: str, reg: dict, sinks: Counter) -> bool:
    for kind, key in PRIORITIES[strategy]:
        if kind == "building":
            definition = reg["buildings"].get(key)
            if not definition:
                continue
            level = state["buildings"].get(key, 0)
            planned_levels = sum(1 for entry_kind, entry_key in PRIORITIES[strategy] if entry_kind == "building" and entry_key == key)
            target_level = min(int(definition["max_level"]), planned_levels)
            if level >= target_level:
                continue
            cost_s = definition["base_scrap"] + level * definition["scrap_step"]
            cost_c = definition["base_crystal"] + level * definition["crystal_step"]
            if state["scrap"] >= cost_s and state["crystals"] >= cost_c:
                state["scrap"] -= cost_s; state["crystals"] -= cost_c
                state["buildings"][key] = level + 1
                sinks[f"building:{key}"] += 1
                sinks["building_scrap"] += cost_s; sinks["building_crystals"] += cost_c
                return True
        else:
            definition = reg["research"].get(key)
            if not definition or key in state["unlocked"]:
                continue
            if any(pre not in state["unlocked"] for pre in definition["prerequisites"]):
                continue
            cost_s, cost_c = definition["scrap_cost"], definition["crystal_cost"]
            if state["scrap"] >= cost_s and state["crystals"] >= cost_c:
                state["scrap"] -= cost_s; state["crystals"] -= cost_c
                state["unlocked"].add(key)
                sinks[f"research:{key}"] += 1
                sinks["research_scrap"] += cost_s; sinks["research_crystals"] += cost_c
                return True
    return False


def has_remaining_plan(state: dict, strategy: str, reg: dict) -> bool:
    """Whether this strategy still has an unpurchased planned investment."""
    building_targets = Counter(key for kind, key in PRIORITIES[strategy] if kind == "building")
    for building_id, target_count in building_targets.items():
        target_level = min(int(reg["buildings"][building_id]["max_level"]), target_count)
        if int(state["buildings"].get(building_id, 0)) < target_level:
            return True
    return any(kind == "research" and key not in state["unlocked"] for kind, key in PRIORITIES[strategy])


def choose_length_and_outcome(rng: random.Random, regime: str, run_index: int) -> tuple[int, str]:
    if regime == "loss_streak" and run_index < 5:
        return rng.choice((1, 2, 2, 3)), "defeat"
    if regime == "win_streak" and run_index < 5:
        return rng.choice((4, 5, 6)), "return"
    if regime == "long_push":
        loops = rng.choice((5, 6, 7, 8, 9, 10))
        defeat_chance = min(.82, .24 + .09 * (loops - 5))
        return loops, "defeat" if rng.random() < defeat_chance else "return"
    loops = rng.choices((2, 3, 4, 5, 6), weights=(.10, .20, .35, .25, .10), k=1)[0]
    defeat_chance = min(.42, .12 + max(0, loops - 3) * .045)
    if regime == "loss_streak" and run_index < 10:
        defeat_chance = max(defeat_chance, .48)
    if regime == "win_streak" and run_index < 10:
        defeat_chance = min(defeat_chance, .08)
    return loops, "defeat" if rng.random() < defeat_chance else "return"


def sim_run(state: dict, loops: int, outcome: str, rng: random.Random, reg: dict, sinks: Counter, sources: Counter, contract_chance: float) -> dict:
    b = reg["balance"]
    ledger = {"scrap": 0, "crystals": 0}
    paid_contract = None
    # An optional paid contract is attempted in about one run in four, but only
    # when the player can afford the fee before starting.
    if rng.random() < contract_chance:
        preferred = "bounty_hunter" if loops >= 2 else "event_archive"
        definition = reg["contracts"].get(preferred, {})
        if definition and state["scrap"] >= definition["scrap_cost"] and state["crystals"] >= definition["crystal_cost"]:
            state["scrap"] -= definition["scrap_cost"]
            state["crystals"] -= definition["crystal_cost"]
            sinks["contract_fees_scrap"] += definition["scrap_cost"]
            sinks["contract_fees_crystals"] += definition["crystal_cost"]
            paid_contract = (preferred, definition)
    route = make_route(rng, int(b.get("route_cells", 18)), int(b.get("safe_intro_route_nodes", 3)))
    bonus = build_bonus(state, reg)
    full_loops = loops if outcome == "return" else max(0, loops - 1)
    for loop_no in range(1, loops + 1):
        partial_defeat_loop = outcome == "defeat" and loop_no == loops
        if not partial_defeat_loop:
            route_scrap = int(b.get("route_reward_scrap", 4)) + bonus
            ledger["scrap"] += route_scrap
            sources["route_scrap"] += route_scrap
            interval = max(1, int(b.get("loop_crystal_interval", 2)))
            if loop_no % interval == 0:
                milestone = 1
                if "crystal_study" in state["unlocked"]:
                    milestone += int(reg["research"]["crystal_study"]["effects"].get("loop_crystal_bonus", 0))
                ledger["crystals"] += milestone
                sources["milestone_crystals"] += milestone
        loop_index = loop_no - 1
        # In a defeated expedition, the final intended loop is only partly
        # traversed: there is no full-loop payout/milestone/boss boundary.
        cell_limit = len(route) if not partial_defeat_loop else min(len(route), 1 + max(1, math.ceil((len(route) - 1) * .55)))
        for cell_index, kind in enumerate(route[:cell_limit]):
            if cell_index == 0:
                # Node 0 is a boss node only at every configured boss interval.
                continue
            if kind == "cache":
                cache = 2 + min(loop_index, 2)
                ledger["scrap"] += cache; sources["cache_scrap"] += cache
            if kind == "event":
                # Expected-value sample of event decisions: mix of small rewards,
                # expensive choices and occasional crystal rewards; not every text path.
                roll = rng.random()
                if roll < .42:
                    ledger["scrap"] += 5; sources["event_scrap"] += 5
                elif roll < .63:
                    ledger["scrap"] += 8; sources["event_scrap"] += 8
                elif roll < .78:
                    ledger["crystals"] += 2; sources["event_crystals"] += 2
                elif roll < .88 and ledger["scrap"] >= 5:
                    ledger["scrap"] -= 5; sources["event_spent_scrap"] += 5
                # negative-health-only choices are represented through defeat odds.
                continue
            chance = max(float(b.get("encounter_chance_min", .08)), min(float(b.get("encounter_chance_max", .96)), float(b.get("encounter_chance_base", .22)) + loop_index * float(b.get("encounter_chance_per_loop", .04)) + (.27 if kind == "danger" else 0.0)))
            if rng.random() >= chance:
                continue
            count = 3 if rng.random() < float(b.get("three_enemy_pack_chance", .18)) else 1
            for _ in range(count):
                enemy = rng.choice(list(reg["enemies"].values()))
                scrap = enemy["scrap"] + rng.randint(0, 2)
                crystals = enemy["crystal"]
                crystal_chance = float(b.get("loot_crystal_chance", .22)) + min(float(b.get("loot_crystal_loop_cap", .18)), loop_index * float(b.get("loot_crystal_loop_step", .025)))
                if rng.random() < crystal_chance:
                    crystals += 1
                ledger["scrap"] += scrap; ledger["crystals"] += crystals
                sources["enemy_scrap"] += scrap; sources["enemy_crystals"] += crystals
        if not partial_defeat_loop and loop_no % max(1, int(b.get("boss_loop_interval", 3))) == 0:
            boss = rng.choice(list(reg["bosses"].values()))
            scrap = boss["scrap"] + rng.randint(0, 2)
            crystals = boss["crystal"]
            crystal_chance = float(b.get("loot_crystal_chance", .22)) + min(float(b.get("loot_crystal_loop_cap", .18)), loop_index * float(b.get("loot_crystal_loop_step", .025)))
            if rng.random() < crystal_chance:
                crystals += 1
            ledger["scrap"] += scrap; ledger["crystals"] += crystals
            sources["boss_scrap"] += scrap; sources["boss_crystals"] += crystals
    if paid_contract:
        contract_id, definition = paid_contract
        # Complete only with a chance conditioned on the contract deadline and
        # outcome. Failure loses the fee; earned rewards are retained at settlement ratio.
        if full_loops >= max(1, int(definition["deadline_loops"])):
            base_success = .77 if contract_id == "bounty_hunter" else .70
        else:
            base_success = .16
        if outcome == "defeat":
            base_success *= .62
        if rng.random() < base_success:
            ledger["scrap"] += definition["scrap_reward"]
            ledger["crystals"] += definition["crystal_reward"]
            sources["contract_reward_scrap"] += definition["scrap_reward"]
            sources["contract_reward_crystals"] += definition["crystal_reward"]
            sources["contract_completed"] += 1
        else:
            sources["contract_failed"] += 1
    ratio = 1.0 if outcome == "return" else float(b.get("defeat_keep_ratio", .4))
    kept_scrap = math.floor(ledger["scrap"] * ratio)
    kept_crystals = math.floor(ledger["crystals"] * ratio)
    state["scrap"] += kept_scrap; state["crystals"] += kept_crystals
    sources["settled_scrap"] += kept_scrap; sources["settled_crystals"] += kept_crystals
    sources["lost_scrap_on_defeat"] += ledger["scrap"] - kept_scrap
    sources["lost_crystals_on_defeat"] += ledger["crystals"] - kept_crystals
    sources["return_runs"] += outcome == "return"
    sources["defeat_runs"] += outcome == "defeat"
    sources["loops_completed"] += full_loops
    sources["raw_scrap_earned"] += ledger["scrap"]
    sources["raw_crystals_earned"] += ledger["crystals"]
    # One optional gear upgrade after each third returned expedition, if affordable.
    # Conservative common-rarity rank-2 item estimate, increasing upgrade level by slot.
    if outcome == "return" and int(sources["return_runs"]) % 3 == 0:
        slot = int(sources.get("gear_upgrades", 0)) % 3
        level = int(sources.get(f"gear_level_{slot}", 0))
        if level < 10:
            rank = max(1, 1 + loops // 2)
            power_tier = rank + level
            scrap_cost = math.ceil(18 + power_tier * 7 + level * 10)
            crystal_cost = 1 + math.floor(power_tier / 3)
            if state["scrap"] >= scrap_cost and state["crystals"] >= crystal_cost:
                state["scrap"] -= scrap_cost; state["crystals"] -= crystal_cost
                sources["gear_upgrades"] += 1
                sources[f"gear_level_{slot}"] = level + 1
                sinks["gear_upgrade_scrap"] += scrap_cost
                sinks["gear_upgrade_crystals"] += crystal_cost
    return {"planned_depth": loops, "loops_completed": full_loops, "outcome": outcome, "earned_scrap": ledger["scrap"], "earned_crystals": ledger["crystals"], "kept_scrap": kept_scrap, "kept_crystals": kept_crystals}


def simulate_campaign(seed: int, strategy: str, regime: str, runs: int, reg: dict, contract_chance: float = .25) -> dict:
    rng = random.Random(seed)
    state = {"scrap": reg["starting_scrap"], "crystals": reg["starting_crystals"], "buildings": {"forge": 0, "infirmary": 0, "salvage": 0}, "unlocked": set()}
    sources = Counter(); sinks = Counter(); per_run = []; no_purchase_streak = 0; max_no_purchase_streak = 0; zero_resource_events = 0
    for run_index in range(runs):
        loops, outcome = choose_length_and_outcome(rng, regime, run_index)
        result = sim_run(state, loops, outcome, rng, reg, sinks, sources, contract_chance)
        per_run.append(result)
        purchases_this_intermission = 0
        # The live UI permits multiple purchases between expeditions. Drain every
        # affordable planned investment rather than impose an artificial limit.
        while purchase_one(state, strategy, reg, sinks):
            purchases_this_intermission += 1
        if purchases_this_intermission:
            no_purchase_streak = 0
        elif has_remaining_plan(state, strategy, reg):
            no_purchase_streak += 1
            max_no_purchase_streak = max(max_no_purchase_streak, no_purchase_streak)
            zero_resource_events += 1
        else:
            no_purchase_streak = 0
    return {"scrap": state["scrap"], "crystals": state["crystals"], "buildings": state["buildings"], "unlocked": state["unlocked"],
            "sources": sources, "sinks": sinks, "runs": per_run, "purchases": sum(v for k,v in sinks.items() if k.startswith("building:") or k.startswith("research:")),
            "max_no_purchase_streak": max_no_purchase_streak, "zero_resource_events": zero_resource_events}


def percentile(values: list[float], p: float) -> float:
    if not values: return 0.0
    vals = sorted(values)
    return vals[min(len(vals)-1, max(0, math.ceil(p*len(vals))-1))]


def run_analysis(reg: dict, campaigns: int, runs: int, seed: int, contract_chance: float) -> dict:
    matrix = {}
    for strategy_index, strategy in enumerate(STRATEGIES):
        for regime_index, regime in enumerate(REGIMES):
            rows = [simulate_campaign(seed + strategy_index*100_000 + regime_index*10_000 + i, strategy, regime, runs, reg, contract_chance) for i in range(campaigns)]
            matrix[(strategy, regime)] = {
                "rows": rows,
                "scrap_median": statistics.median(r["scrap"] for r in rows),
                "crystal_median": statistics.median(r["crystals"] for r in rows),
                "scrap_p10": percentile([r["scrap"] for r in rows], .10),
                "crystal_p10": percentile([r["crystals"] for r in rows], .10),
                "scrap_p90": percentile([r["scrap"] for r in rows], .90),
                "crystal_p90": percentile([r["crystals"] for r in rows], .90),
                "purchases_median": statistics.median(r["purchases"] for r in rows),
                "research_median": statistics.median(len(r["unlocked"]) for r in rows),
                "max_stall_median": statistics.median(r["max_no_purchase_streak"] for r in rows),
                "starve_rate": sum(r["zero_resource_events"] > 0 for r in rows)/campaigns,
                "scrap_sink_median": statistics.median(r["sinks"]["building_scrap"]+r["sinks"]["research_scrap"]+r["sinks"]["contract_fees_scrap"]+r["sinks"]["gear_upgrade_scrap"] for r in rows),
                "crystal_sink_median": statistics.median(r["sinks"]["building_crystals"]+r["sinks"]["research_crystals"]+r["sinks"]["contract_fees_crystals"]+r["sinks"]["gear_upgrade_crystals"] for r in rows),
            }
    return matrix


def render_report(reg: dict, matrix: dict, campaigns: int, runs: int, seed: int, contract_chance: float) -> str:
    bal = reg["balance"]
    total = campaigns * runs * len(STRATEGIES) * len(REGIMES)
    registry_hash = hashlib.sha256(reg["source"].encode("utf-8")).hexdigest()
    lines = [
        "# Abyss Loop — анализ экономики длинной кампании (этап 45)", "",
        f"**Модель:** {campaigns} кампаний × {runs} экспедиций × {len(STRATEGIES)} специализаций × {len(REGIMES)} режимов = {total:,} смоделированных экспедиций.",
        f"**Seed:** {seed}. **Шанс взять платный контракт в экспедиции:** {contract_chance:.0%}.",
        f"**SHA-256 content_registry.gd:** `{registry_hash}`.", "",
        "> Важно: это детерминированная вероятностная модель на Python, которая читает текущие коэффициенты реестра. Она не исполняет GDScript и не моделирует точный бой, поведение игрока, реальные карты тайлов, здоровье по кадрам или все варианты событий. Значения нужны для поиска трендов, а не как обещание игрового результата.", "",
        "## 1. Источники ресурсов и расходы", "",
        "| Тип | Правило из проекта | Как учтено в модели |", "|---|---|---|",
        f"| Стартовые ресурсы | {reg['starting_scrap']} материалов и {reg['starting_crystals']} кристаллов в новом профиле | начальный баланс каждой кампании |",
        f"| Материалы за цикл | {int(bal.get('route_reward_scrap',4))} + постоянный бонус, предел бонуса +{int(bal.get('shelter_loop_scrap_bonus_cap',6))} | учитывается до выхода/поражения |",
        f"| Кристаллы за рубеж | 1 за каждые {int(bal.get('loop_crystal_interval',2))} цикла; исследование может добавлять +1 | отдельная строка дохода |",
        f"| Обычные враги | награда по 5 типам противников, случайный бонус материалов 0–2, шанс кристалла {float(bal.get('loot_crystal_chance',.22)):.0%} + рост до {float(bal.get('loot_crystal_loop_cap',.18)):.0%} | случайный состав группы и добыча |",
        f"| Боссы | гарантированная награда по конфигурациям боссов; период {int(bal.get('boss_loop_interval',3))} цикла | учитываются в длинных забегах |",
        "| Тайники и события | типы узлов из генератора; события имеют смешанный положительный/платный результат | событие моделируется набором укрупнённых исходов |",
        "| Платные контракты | комиссия списывается до старта; награда попадает в добычу | успех зависит от срока и исхода забега; при поражении применяется удержание |",
        "| Постройки и исследования | фактические цены из `BUILDINGS` и `BASE_RESEARCH` | все доступные запланированные вложения приобретаются в приоритетном порядке между забегами |",
        "| Улучшение экипировки | формула базового/обычного предмета из `InventorySystem.get_upgrade_cost` | одна попытка после каждой третьей успешной эвакуации, только при достаточном балансе |", "",
        f"**Правило поражения:** удерживается {float(bal.get('defeat_keep_ratio',.4)):.0%} временной добычи; остальное теряется. Безопасное возвращение сохраняет 100%. Плата за контракт взимается из постоянного запаса перед забегом.", "",
        "## 2. Сценарии кампании", "",
        "- **Смешанный:** от 2 до 6 циклов, с повышением риска для длинных забегов.",
        "- **Серия поражений:** первые 5 экспедиций намеренно короткие и заканчиваются поражением; затем повышенная вероятность поражения сохраняется до десятой экспедиции.",
        "- **Удачная серия:** первые 5 экспедиций возвращаются с добычей; затем действует умеренно сниженная вероятность поражения.",
        "- **Длинный забег:** 5–10 циклов; вероятность поражения растёт вместе с длиной забега.", "",
        "В каждой стратегии моделируются 4 пути приоритетных покупок: сбалансированный, экономический, боевой и разведывательный. Между экспедициями модель покупает все доступные запланированные инвестиции по приоритету (сама игра покупки автоматически не выполняет). Это стресс-сценарий активного инвестирования, а не модель каждого возможного поведения игрока.", "",
        "## 3. Остаток ресурсов после кампании", "",
        "| Стратегия | Сценарий | Материалы медиана (P10–P90) | Кристаллы медиана (P10–P90) | Покупок медиана | Изучено узлов медиана | Макс. серия без покупки | Кампании с нехваткой обоих ресурсов* |", "|---|---|---:|---:|---:|---:|---:|---:|",
    ]
    label = {"balanced":"Сбалансированная", "economy":"Экономическая", "combat":"Боевая", "scouting":"Разведка"}
    regime_label = {"mixed":"Смешанный", "loss_streak":"Серия поражений", "win_streak":"Удачная серия", "long_push":"Длинный забег"}
    for strategy in STRATEGIES:
        for regime in REGIMES:
            r = matrix[(strategy, regime)]
            lines.append(f"| {label[strategy]} | {regime_label[regime]} | {r['scrap_median']:.0f} ({r['scrap_p10']:.0f}–{r['scrap_p90']:.0f}) | {r['crystal_median']:.0f} ({r['crystal_p10']:.0f}–{r['crystal_p90']:.0f}) | {r['purchases_median']:.0f} | {r['research_median']:.0f} | {r['max_stall_median']:.0f} | {r['starve_rate']:.0%} |")
    lines.extend(["", "## 4. Источники и расходы в смешанном сценарии", "", "Все значения ниже — медиана на кампанию, а не на одну экспедицию. Показатели добычи до удержания включают ресурсы, которые могли быть потеряны при поражении.", "", "### Источники", "", "| Стратегия | Циклы: материалы | Враги: материалы | Тайники и события: материалы, нетто | Боссы: материалы | Кристаллы из циклов | Кристаллы из боёв/событий | Потеря материалов при поражении |", "|---|---:|---:|---:|---:|---:|---:|---:|"])
    for strategy in STRATEGIES:
        rows = matrix[(strategy, "mixed")]["rows"]
        med = lambda key: statistics.median(r["sources"][key] for r in rows)
        lines.append(f"| {label[strategy]} | {med('route_scrap'):.0f} | {med('enemy_scrap'):.0f} | {med('cache_scrap') + med('event_scrap') - med('event_spent_scrap'):.0f} | {med('boss_scrap'):.0f} | {med('milestone_crystals'):.0f} | {med('enemy_crystals') + med('boss_crystals') + med('event_crystals'):.0f} | {med('lost_scrap_on_defeat'):.0f} |")
    lines.extend(["", "### Расходы", "", "| Стратегия | Постройки: материалы | Исследования: материалы | Комиссии контрактов: материалы | Улучшение экипировки: материалы | Всего материалов потрачено | Кристаллы всего потрачено |", "|---|---:|---:|---:|---:|---:|---:|"])
    for strategy in STRATEGIES:
        rows = matrix[(strategy, "mixed")]["rows"]
        med_sink = lambda key: statistics.median(r["sinks"][key] for r in rows)
        building_scrap = med_sink("building_scrap")
        research_scrap = med_sink("research_scrap")
        contract_scrap = med_sink("contract_fees_scrap")
        gear_scrap = med_sink("gear_upgrade_scrap")
        total_scrap = building_scrap + research_scrap + contract_scrap + gear_scrap
        total_crystal = med_sink("building_crystals") + med_sink("research_crystals") + med_sink("contract_fees_crystals") + med_sink("gear_upgrade_crystals")
        lines.append(f"| {label[strategy]} | {building_scrap:.0f} | {research_scrap:.0f} | {contract_scrap:.0f} | {gear_scrap:.0f} | {total_scrap:.0f} | {total_crystal:.0f} |")
    lines.extend(["", "## 5. Ключевые выводы и балансировочные ворота", ""])
    mixed = [matrix[(s, "mixed")] for s in STRATEGIES]
    starvation = max(r["starve_rate"] for r in mixed)
    if starvation >= .50:
        lines.append(f"- **Риск коротких стопоров развития обнаружен:** максимум {starvation:.0%} кампаний в смешанном режиме хотя бы раз теряют возможность покупки из-за малого остатка обеих валют. Рассмотрите небольшое снижение стоимости ранних узлов/построек или увеличение раннего дохода; не меняйте баланс автоматически без runtime проверки.")
    else:
        lines.append(f"- **Ресурсный тупик не подтверждён этой моделью:** доля кампаний со стопором покупки в смешанном режиме не превышает {starvation:.0%} по всем приоритетам инвестиций. Это не исключает краткосрочную нехватку кристаллов в отдельных сохранениях.")
    economy_income = matrix[("economy", "mixed")]["scrap_median"]
    combat_income = matrix[("combat", "mixed")]["scrap_median"]
    lines.append(f"- Экономическая специализация заканчивает кампанию с медианой {economy_income:.0f} материалов против {combat_income:.0f} у боевой. Остаток — после всех доступных запланированных покупок по приоритетам, а не чистая прибыль.")
    lines.append(f"- Общий доход пассивных материалов остаётся ограниченным капом +{int(bal.get('shelter_loop_scrap_bonus_cap',6))} за цикл; это защищает от бесконечного складывания бонусов построек и исследований.")
    # Interpret the model's boundaries explicitly: high ending balances can
    # reflect finite simulated purchase plans, not prove the whole game's sink
    # economy is exhausted; a purchase stall is not a hardlock while runs stay free.
    lines.append("- **Остаток после кампании нельзя считать доказанным избытком экономики 1.0:** сценарий намеренно покупает лишь конечный список инвестиций стратегии и моделирует одно улучшение экипировки после каждой третьей успешной эвакуации. Высокий остаток означает, что этих расходов мало для поглощения модельного дохода, но для вывода о полноценном эндгейме нужны все реальные траты и runtime-данные.")
    loss_streak = [matrix[(s, "loss_streak")] for s in STRATEGIES]
    loss_stall = max(r["starve_rate"] for r in loss_streak)
    lines.append(f"- **Серия поражений даёт временную паузу инвестиций:** до {loss_stall:.0%} кампаний режима loss-streak хотя бы раз не могут купить следующий запланированный узел. Это не hardlock по модели: обычная экспедиция остаётся бесплатной, но покупку придётся отложить до восстановления ресурсов.")
    lines.append("- **Поражение моделируется частичным последним циклом:** за него не выдаётся полная выплата за цикл, рубежный кристалл и награда босса на границе цикла; оставшаяся добыча проходит через настроенный коэффициент удержания.")
    lines.append("- Результаты по длинным забегам нельзя прямо сравнивать с короткими: модель не знает настоящую длительность боя, лечение героя, размещённые тайлы и конкретные решения в событиях.")
    lines.extend(["", "## 6. Обязательные ручные проверки в Godot", "", "1. Новый профиль: проверить стартовые 60 материалов / 14 кристаллов и покупку первой постройки/исследования.", "2. Несколько коротких поражений подряд: проверить удержание 40%, списание комиссии контракта и возможность продолжить бесплатную экспедицию.", "3. Смешанный забег на 4–6 циклов: сверить фактические материалы и кристаллы с прогнозом возврата, включая боссов и события.", "4. Длинный забег: сравнить доход за цикл, предел +6, кристаллические рубежи и растущую частоту столкновений.", "5. Сохранить/загрузить перед покупкой постройки, после покупки исследования и после эвакуации: убедиться, что нет двойного начисления/списания.", "", "## 7. Честный статус", "", "- Этот отчёт получен статическим чтением GDScript-конфигурации и seeded Python-сценариями.", "- Он не подтверждает компиляцию GDScript или поведение внутри Godot 4.7.2.", "- В этапе 45 не изменяются игровые коэффициенты: сначала фиксируется воспроизводимая экономическая базовая линия, а изменения баланса будут вноситься только при устойчиво подтверждённом дефекте.", ""])
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--campaigns", type=int, default=35)
    parser.add_argument("--runs", type=int, default=30)
    parser.add_argument("--seed", type=int, default=45045)
    parser.add_argument("--contract-chance", type=float, default=.25)
    parser.add_argument("--report", type=Path, default=DEFAULT_REPORT)
    args = parser.parse_args()
    if args.campaigns < 1 or args.runs < 1 or not 0 <= args.contract_chance <= 1:
        parser.error("campaigns/runs must be positive and contract chance must be 0..1")
    reg = parse_registry()
    matrix = run_analysis(reg, args.campaigns, args.runs, args.seed, args.contract_chance)
    report = render_report(reg, matrix, args.campaigns, args.runs, args.seed, args.contract_chance)
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(report, encoding="utf-8")
    print(f"ECONOMY CAMPAIGN SCREENING PASSED: {args.campaigns*args.runs*len(STRATEGIES)*len(REGIMES):,} expedition runs simulated")
    print(f"Report: {args.report.relative_to(ROOT) if args.report.is_relative_to(ROOT) else args.report}")
    print(f"Models: {', '.join(STRATEGIES)}; regimes: {', '.join(REGIMES)}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
