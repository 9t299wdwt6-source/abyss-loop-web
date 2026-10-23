"""Keep the balance screening tool reproducible and tied to the central registry."""
from pathlib import Path
import subprocess
import sys
import tempfile
ROOT = Path(__file__).resolve().parents[1]
tool = ROOT / "tools/balance_campaign.py"
registry = (ROOT / "scripts/core/content_registry.gd").read_text(encoding="utf-8")
assert tool.is_file(), "balance campaign tool is missing"
source = tool.read_text(encoding="utf-8")
for required in ["const_block", "ContentRegistry", "enemy_loop_scaling", "boss_special_multiplier", "sha256", "runtime", "does not execute GDScript"]:
    assert required.casefold() in source.casefold(), f"balance tool misses expected guard: {required}"
assert 'const RUN_MODIFIERS :=' in registry and 'const DIFFICULTY_PRESETS :=' in registry
with tempfile.TemporaryDirectory() as directory:
    report = Path(directory) / "balance.md"
    result = subprocess.run([sys.executable, str(tool), "--runs", "10", "--report", str(report)], cwd=ROOT, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=28)
    assert result.returncode == 0, "balance simulation failed:\n" + result.stdout
    text = report.read_text(encoding="utf-8")
    assert "144" in text and "не исполняет GDScript" in text and "автоматические" in text.lower() and "Уровень героя*" in text and "estimated_level" in source, "balance report is incomplete"
print("BALANCE CAMPAIGN REGRESSION PASSED: parser, seeded scenario matrix, and report generation")
print("Reminder: this is a simplified combat screening model, not a Godot gameplay test.")
