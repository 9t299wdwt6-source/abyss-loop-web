"""Dependency and basic source-integrity checks that do not require Godot installed."""
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
errors: list[str] = []
for ref in re.findall(r'res://([^"\']+)', "\n".join(p.read_text(encoding="utf-8") for p in ROOT.rglob("*.gd")) + (ROOT / "project.godot").read_text(encoding="utf-8")):
    target = ROOT / ref
    if not target.is_file():
        errors.append(f"Missing resource reference: res://{ref}")

# Lightweight delimiter check ignoring strings/comments; this is not a GDScript compiler.
for source in ROOT.rglob("*.gd"):
    text = source.read_text(encoding="utf-8")
    stack: list[tuple[str, int]] = []
    quote = ""
    escaped = False
    comment = False
    pairs = {")": "(", "]": "[", "}": "{"}
    line = 1
    for char in text:
        if char == "\n":
            if quote:
                errors.append(f"{source.relative_to(ROOT)}:{line}: string literal reaches end of line without closing quote")
                quote = ""
            line += 1
            comment = False
            escaped = False
            continue
        if comment:
            continue
        if quote:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                quote = ""
            continue
        if char == "#":
            comment = True
        elif char in ('"', "'"):
            quote = char
        elif char in "([{":
            stack.append((char, line))
        elif char in ")]}":
            if not stack or stack[-1][0] != pairs[char]:
                errors.append(f"{source.relative_to(ROOT)}:{line}: mismatched delimiter {char}")
                break
            stack.pop()
    if stack:
        errors.append(f"{source.relative_to(ROOT)}:{stack[-1][1]}: unclosed delimiter {stack[-1][0]}")
    if quote:
        errors.append(f"{source.relative_to(ROOT)}:{line}: unclosed string")

if errors:
    print("STATIC PROJECT CHECK FAILED")
    print("\n".join(errors))
    sys.exit(1)
print("STATIC PROJECT CHECK PASSED: resource paths exist and delimiters are balanced.")
print("Note: this is not a Godot/GDScript runtime compilation check.")
