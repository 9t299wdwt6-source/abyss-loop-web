"""Regression checks for independent shelter specializations and useful previews."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
reg_text = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
base_text = (ROOT / "scripts/systems/base_system.gd").read_text(encoding="utf-8")
ui_text = (ROOT / "scripts/ui/ui_controller.gd").read_text(encoding="utf-8")
smoke_text = (ROOT / "tests/smoke_test.gd").read_text(encoding="utf-8")
manager_text = (ROOT / "scripts/systems/expedition_manager.gd").read_text(encoding="utf-8")
state_text = (ROOT / "scripts/core/game_state.gd").read_text(encoding="utf-8")
project_text = (ROOT / "project.godot").read_text(encoding="utf-8")

def section(text: str, start: str, end: str) -> str:
    return text.split(start, 1)[1].split(end, 1)[0]

branch_section = section(reg_text, "const RESEARCH_BRANCHES := {", "\n}\n\n# Permanent research tree") + "\n}"
research_section = section(reg_text, "const BASE_RESEARCH := {", "\n}\n\nconst PERKS") + "\n}"
branch_blocks = re.findall(r'^\t"([^"]+)": \{(.*?)(?=^\t"[^"]+": \{|^\})', branch_section, re.M | re.S)
node_blocks = re.findall(r'^\t"([^"]+)": \{(.*?)(?=^\t"[^"]+": \{|^\})', research_section, re.M | re.S)
branches = {}
for branch_id, body in branch_blocks:
    nodes_match = re.search(r'"nodes": \[([^\]]*)\]', body)
    entry_match = re.search(r'"entry_node": "([^"]+)"', body)
    assert nodes_match and entry_match, f"branch {branch_id} lacks node list/entry"
    nodes = re.findall(r'"([^"]+)"', nodes_match.group(1))
    branches[branch_id] = {"nodes": nodes, "entry": entry_match.group(1), "body": body}

nodes = {}
for node_id, body in node_blocks:
    branch_match = re.search(r'"branch": "([^"]+)"', body)
    prereq_match = re.search(r'"prerequisites": \[([^\]]*)\]', body)
    cost_match = re.search(r'"scrap_cost": (\d+), "crystal_cost": (\d+)', body)
    assert branch_match and prereq_match and cost_match, f"node {node_id} lacks branch, prerequisites or price"
    nodes[node_id] = {"branch": branch_match.group(1), "prereqs": re.findall(r'"([^"]+)"', prereq_match.group(1)), "cost": tuple(map(int, cost_match.groups())), "body": body}

checks = {
    "version advances to 0.61.0 while application profile stays stable": 'config/name="Abyss Loop"' in project_text and 'config/version="0.61.0"' in project_text,
    "four branches exist with human-readable summaries": len(branches) == 4 and all('"summary"' in value["body"] and '"style"' in value["body"] for value in branches.values()),
    "every research node belongs to exactly one known branch": set(nodes) == {n for b in branches.values() for n in b["nodes"]} and len([n for b in branches.values() for n in b["nodes"]]) == len(set(n for b in branches.values() for n in b["nodes"])),
    "each specialization has an independently unlockable entry node": all(b["entry"] in nodes and nodes[b["entry"]]["branch"] == branch_id and not nodes[b["entry"]]["prereqs"] for branch_id,b in branches.items()),
    "all prerequisites stay inside the same specialization": all(all(nodes.get(prereq, {}).get("branch") == data["branch"] for prereq in data["prereqs"]) for data in nodes.values()),
    "branch dependencies and all targets resolve to registered research": all(all(prereq in nodes for prereq in data["prereqs"]) for data in nodes.values()),
    "starter branches are individually affordable but cannot all be bought with starter scrap": all(cost[0] <= 60 and cost[1] <= 14 for cost in [nodes[b["entry"]]["cost"] for b in branches.values()]) and sum(nodes[b["entry"]]["cost"][0] for b in branches.values()) > 60,
    "branch status centralizes next-node and blocked-node preview": all(token in base_text for token in ("func get_research_branch_status(", '"next_preview"', '"blocked_nodes"', '"entry_available"')),
    "UI visibly groups branches and explains lock reasons": all(token in ui_text for token in ('ContentRegistry.RESEARCH_BRANCHES.keys()', 'get_research_branch_status(branch_id)', 'Следующий открываемый узел:', 'ЗАБЛОКИРОВАНО · не изучено:')),
    "runtime smoke validates branch entries and unique membership": all(token in smoke_text for token in ("RESEARCH_BRANCHES.size() == 4", "independently unlockable", "seen_research_nodes", "branch catalogue")),
    "save schema stays unchanged because no persisted field shape changed": 'const SAVE_VERSION := 3' in (ROOT / "scripts/core/save_system.gd").read_text(encoding="utf-8"),
    "building and research income share one cap for forecast and payout": all(token in state_text for token in ("func get_effective_loop_scrap_bonus()", '"shelter_loop_scrap_bonus_cap"', 'clampi(building_bonus + research_bonus, 0, cap)')) and manager_text.count("GameState.get_effective_loop_scrap_bonus()") == 2,
    "runtime smoke exercises the configured maximum income cap": 'GameState.get_effective_loop_scrap_bonus() == int(ContentRegistry.BALANCE.get("shelter_loop_scrap_bonus_cap", 6))' in smoke_text,
}
failed = [name for name, ok in checks.items() if not ok]
if failed:
    print("SHELTER BRANCH REGRESSION FAILED")
    for name in failed: print("- " + name)
    sys.exit(1)
print(f"SHELTER BRANCH REGRESSION PASSED: {len(checks)} checks")
for name in checks: print("- " + name)
print("Godot compilation and interactive UI still require runtime acceptance in Godot 4.7.2.")
