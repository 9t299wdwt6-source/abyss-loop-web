"""Static regression guards for safe permanent-research respec and save continuity."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
state = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
base = (ROOT / "scripts/systems/base_system.gd").read_text(encoding="utf-8")
save = (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8")
ui = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
project = (ROOT / "project.godot").read_text(encoding="utf-8")

checks = {
    "build version is 0.61.0 without changing stable app identity": 'config/name="Abyss Loop"' in project and 'config/version="0.61.0"' in project,
    "respec preview is blocked while an expedition checkpoint is active": 'func get_research_reset_preview() -> Dictionary:' in state and 'if has_saved_expedition():' in state and 'active_expedition' in state,
    "reset refunds only 80 percent and explicitly calculates retained cost": 'const RESEARCH_RESET_REFUND_PERCENT := 80' in state and '"lost_scrap": spent_scrap - refund_scrap' in state and '"lost_crystals": spent_crystals - refund_crystals' in state,
    "known nodes are reset while unknown stable IDs remain preserved": 'if not ContentRegistry.BASE_RESEARCH.has(research_id):' in state and 'preserved_unknown_ids.append(research_id)' in state and 'if not reset_ids.has(str(node_value)):' in state,
    "purchase ledger records actual research cost and purchase rolls back on save failure": all(token in base for token in ('GameState.research_investments[research_id]', 'old_investments', 'if not GameState.save_now():', 'GameState.unlocked_nodes = old_unlocked_nodes')),
    "respec transaction rolls back unlocks, ledger and both resources on save failure": all(token in state for token in ('old_unlocked_nodes', 'old_investments', 'if not save_now():', 'unlocked_nodes = old_unlocked_nodes', 'research_investments = old_investments', 'scrap = old_scrap', 'crystals = old_crystals')),
    "purchase history is included in persisted data": '"research_investments": research_investments.duplicate(true)' in state,
    "legacy saves remain valid without purchase ledger and investment fields are validated": 'data.get("research_investments", {})' in save and 'investments_value.size() > 256' in save and 'SAVE_VERSION := 3' in save,
    "unknown IDs are preserved and aliases support stable-ID migrations": 'Keep stable IDs even if a content definition is temporarily absent' in state and 'BASE_RESEARCH_ID_ALIASES := {}' in (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8") and 'canonical_research_id(node_id)' in state and 'resolves to unknown/cyclic target' in (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8"),
    "research UI exposes reset, shows costs and requires explicit confirmation": all(token in ui for token in ('ПЕРЕРАСПРЕДЕЛИТЬ ИССЛЕДОВАНИЯ · ВЕРНУТЬ 80%', 'func _request_research_reset()', 'func _confirm_research_reset()', 'Перераспределить дерево исследований?', 'Вернётся (80%%, округление вниз)', '"confirm"')),
}

# Check the documented integer refund policy with representative values, including flooring.
def refund(paid: int) -> int:
    return paid * 80 // 100

checks["refund rounding is deterministic and does not over-refund"] = refund(74) == 59 and refund(7) == 5 and refund(1) == 0 and all(refund(n) <= n for n in range(1000))

failed = [name for name, passed in checks.items() if not passed]
if failed:
    print("RESEARCH RESPEC REGRESSION FAILED")
    for name in failed:
        print("- " + name)
    sys.exit(1)
print(f"RESEARCH RESPEC REGRESSION PASSED: {len(checks)} checks")
for name in checks:
    print("- " + name)
print("UI interaction, GDScript compilation and save-failure injection still require Godot 4.7.2 runtime testing.")
