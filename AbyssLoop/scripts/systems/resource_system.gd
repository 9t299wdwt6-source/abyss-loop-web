extends RefCounted
class_name ResourceSystem

func add(ledger: Dictionary, resource_id: String, amount: int) -> void:
	if not ledger.has(resource_id):
		ledger[resource_id] = 0
	ledger[resource_id] = maxi(0, int(ledger[resource_id]) + amount)

func settle(ledger: Dictionary, ratio: float) -> Dictionary:
	var safe_ratio := clampf(ratio, 0.0, 1.0)
	return {
		"scrap": maxi(0, int(floor(float(ledger.get("scrap", 0)) * safe_ratio))),
		"crystals": maxi(0, int(floor(float(ledger.get("crystals", 0)) * safe_ratio))),
		"victories": maxi(0, int(ledger.get("victories", 0)))
	}
