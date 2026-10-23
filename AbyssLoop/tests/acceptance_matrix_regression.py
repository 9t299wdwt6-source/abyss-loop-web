from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
MATRIX = ROOT / "tests" / "acceptance_matrix.md"
REGISTER = ROOT / "tests" / "reports" / "REGRESSION_REGISTER_RU.md"

required_scenarios = [
    "Начать экспедицию", "Группового боя", "босса", "каждого варианта события",
    "Разместить каждый доступный тип тайла", "надевание и снятие предмета",
    "повышение уровня", "Вернуться добровольно", "Закрыть игру",
    "дерево исследований", "Повторно открыть",
    "последнего узла к первому", "башен/турелей", "топологию старого маршрута",
    "стабильным названием", "runtime-tested ZIP", "source fingerprint"
]

assert MATRIX.is_file(), "Acceptance matrix is missing"
assert REGISTER.is_file(), "Regression register is missing"
content = MATRIX.read_text(encoding="utf-8")
for scenario in required_scenarios:
    assert scenario.casefold() in content.casefold(), f"Missing acceptance scenario: {scenario}"
assert "требует ручной проверки" in content.casefold(), "Runtime limitations must be disclosed"
assert "Открыт — требуется Godot" in REGISTER.read_text(encoding="utf-8"), "Unverified runtime cases must remain open"
assert "RUN_RELEASE_GATE_WINDOWS.bat" in content and "Prototype 37" in content and "Синергии ландшафта" in content and "Синергии экипировки" in content, "release-gate acceptance steps are missing"
scenario_count = len(re.findall(r"^\d+\.", content, flags=re.MULTILINE))
assert scenario_count >= 31, f"Acceptance matrix unexpectedly short: {scenario_count} scenarios"
print(f"ACCEPTANCE MATRIX CHECK PASSED: {scenario_count} acceptance scenarios and explicit runtime status are documented.")
