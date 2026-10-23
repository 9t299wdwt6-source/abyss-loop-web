"""Guard campaign-level economy screening and its seeded reproducibility."""
from __future__ import annotations
import hashlib
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TOOL = ROOT / "tools/economy_campaign.py"
REGISTRY = ROOT / "scripts/core/content_registry.gd"
GAME_STATE = ROOT / "scripts/core/game_state.gd"
INVENTORY = ROOT / "scripts/systems/inventory_system.gd"
PACKAGE = ROOT / "tools/package_release.py"

assert TOOL.is_file(), "campaign economy simulator missing"
assert 'config/version="0.61.0"' in (ROOT / "project.godot").read_text(encoding="utf-8")
assert 'config/version="0.61.0"' in PACKAGE.read_text(encoding="utf-8"), "release packager version gate is stale"
reg = REGISTRY.read_text(encoding="utf-8")
state = GAME_STATE.read_text(encoding="utf-8")
inventory = INVENTORY.read_text(encoding="utf-8")
tool_text = TOOL.read_text(encoding="utf-8")
for token in ('"route_reward_scrap": 4', '"shelter_loop_scrap_bonus_cap": 6', '"loop_crystal_interval": 2', '"defeat_keep_ratio": 0.40'):
    assert token in reg, f"economy simulation anchor missing: {token}"
for token in ('func get_effective_loop_scrap_bonus()', 'clampi(building_bonus + research_bonus, 0, cap)', 'func settle_expedition'):
    assert token in state, f"source/sink implementation anchor missing: {token}"
for token in ('func get_upgrade_cost(item: Dictionary)', '"scrap": scrap_cost, "crystals": crystal_cost'):
    assert token in inventory, f"gear upgrade sink anchor missing: {token}"
for token in ('loss_streak', 'win_streak', 'long_push', 'seed', 'P10', 'P90', 'has_remaining_plan', 'purchase_one', 'not Godot execution'):
    assert token.casefold() in tool_text.casefold(), f"campaign model coverage missing: {token}"

# Plan priorities are targets, not a loophole that allows repeated identical
# entries to keep upgrading the same building to level 5.
sys.path.insert(0, str(ROOT / "tools"))
import economy_campaign as economy  # noqa: E402
reg_data = economy.parse_registry()
for strategy, building_targets in {"balanced": {"forge": 1, "infirmary": 1, "salvage": 1},
                                   "economy": {"salvage": 5, "infirmary": 1},
                                   "combat": {"forge": 3, "infirmary": 3}}.items():
    state_data = {"scrap": 100_000, "crystals": 100_000,
                  "buildings": {"forge": 0, "infirmary": 0, "salvage": 0}, "unlocked": set()}
    sinks = Counter()
    while economy.purchase_one(state_data, strategy, reg_data, sinks):
        pass
    for building_id, expected_level in building_targets.items():
        assert state_data["buildings"][building_id] == expected_level, (strategy, building_id, state_data["buildings"][building_id], expected_level)
    assert not economy.has_remaining_plan(state_data, strategy, reg_data), f"investment plan not fully applied for {strategy}"

with tempfile.TemporaryDirectory() as directory:
    report_a = Path(directory) / "economy_a.md"
    report_b = Path(directory) / "economy_b.md"
    base = [sys.executable, str(TOOL), "--campaigns", "3", "--runs", "8", "--seed", "45045", "--contract-chance", ".25"]
    proc_a = subprocess.run(base + ["--report", str(report_a)], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=25)
    assert proc_a.returncode == 0, "first seeded economy simulation failed:\n" + proc_a.stdout
    proc_b = subprocess.run(base + ["--report", str(report_b)], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=25)
    assert proc_b.returncode == 0, "second seeded economy simulation failed:\n" + proc_b.stdout
    text_a = report_a.read_text(encoding="utf-8")
    text_b = report_b.read_text(encoding="utf-8")
    assert hashlib.sha256(text_a.encode()).hexdigest() == hashlib.sha256(text_b.encode()).hexdigest(), "same seed generated different reports"
    for token in ("384 смоделированных экспедиций", "Источники", "Расходы", "Серия поражений", "Удачная серия", "Длинный забег", "Постройки: материалы", "Улучшение экипировки", "Godot 4.7.2", "не исполняет GDScript", "остаток после кампании нельзя считать доказанным избытком", "обычная экспедиция остаётся бесплатной", "частичным последним циклом"):
        assert token.casefold() in text_a.casefold(), f"economy report is missing: {token}"
    # Currency balances and costs must remain non-negative for every seeded run.
    for strategy in economy.STRATEGIES:
        for regime in economy.REGIMES:
            result = economy.simulate_campaign(45045, strategy, regime, 12, reg_data)
            assert result["scrap"] >= 0 and result["crystals"] >= 0
            assert result["sources"]["lost_scrap_on_defeat"] >= 0 and result["sources"]["lost_crystals_on_defeat"] >= 0
            assert result["sources"]["return_runs"] + result["sources"]["defeat_runs"] == 12

print("ECONOMY CAMPAIGN REGRESSION PASSED")
print("- parsed resource sources/sinks are anchored to current GDScript registries")
print("- strategy purchase priorities respect their intended target levels")
print("- 384-run report is deterministic for a fixed seed and covers success/failure regimes")
print("- all sampled balances stay non-negative; model limitations distinguish investment stalls from hardlocks")
print("- end-balance interpretation is bounded by finite purchase plans and partial-defeat rules")
print("- Godot runtime is not inferred")
