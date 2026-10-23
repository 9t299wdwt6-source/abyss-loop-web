extends RefCounted

## Read-only presentation helper for status effects shown in the expedition HUD.
## It formats already-computed status data; it never applies or ticks effects.

func format_line(status_effect_system: Variant, entity: Dictionary, heading: String, max_visible: int = 3, show_symbols: bool = true) -> String:
	var active_statuses: Array[Dictionary] = status_effect_system.describe_active(entity)
	if active_statuses.is_empty():
		return "%s: нет активных эффектов" % heading
	var status_parts: Array[String] = []
	var visible_count := mini(max_visible, active_statuses.size())
	for index in range(visible_count):
		var status_value: Dictionary = active_statuses[index]
		var stacks := maxi(1, int(status_value.get("stacks", 1)))
		var stacks_suffix := " ×%d" % stacks if stacks > 1 else ""
		var status_id := str(status_value.get("id", ""))
		var status_prefix := accessibility_prefix(status_id) if show_symbols else ""
		status_parts.append("%s%s%s · %.1fс" % [status_prefix, str(status_value.get("name", "Эффект")), stacks_suffix, float(status_value.get("duration", 0.0))])
	if active_statuses.size() > visible_count:
		status_parts.append("+%d" % (active_statuses.size() - visible_count))
	return "%s: %s" % [heading, " · ".join(status_parts)]

func accessibility_prefix(status_id: String) -> String:
	# Stable ASCII markers are intentionally distinct per effect and remain readable
	# in fonts without decorative Unicode glyph coverage.
	match status_id:
		"poison":
			return "[P] "
		"bleed":
			return "[B] "
		"wound":
			return "[W] "
		"barrier":
			return "[#] "
		"regeneration":
			return "[+] "
		"distortion":
			return "[~] "
		"weakness":
			return "[-] "
		"exposed":
			return "[!] "
		_:
			return "[*] "
