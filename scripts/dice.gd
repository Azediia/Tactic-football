class_name Dice
extends RefCounted
## Jets de d100 centralisés. Un seul générateur : on peut le graîner pour rejouer un match,
## et imposer des résultats dans les tests.

static var rng := RandomNumberGenerator.new()
static var _forced: Array = []


static func seed_with(value: int) -> void:
	rng.seed = value


## Impose les prochains résultats ("crit_success", "success", "fail", "crit_fail"). Pour les tests.
static func force(tiers: Array) -> void:
	_forced = tiers.duplicate()


static func clear_forced() -> void:
	_forced.clear()


static func d100() -> int:
	return rng.randi_range(1, 100)


## Lance un d100 contre `chance` (en %). Résultat :
## {"roll", "chance", "tier", "margin"} avec tier parmi crit_success, success, fail, crit_fail.
## Réussite critique : jet <= chance / 10. Échec critique : jet dépasse la chance de plus de 50.
static func resolve(chance: float) -> Dictionary:
	chance = clampf(chance, 1.0, 99.0)
	if not _forced.is_empty():
		return _forced_result(String(_forced.pop_front()), chance)
	var roll := d100()
	var tier := "fail"
	if roll <= chance / 10.0:
		tier = "crit_success"
	elif roll <= chance:
		tier = "success"
	elif roll - chance > 50.0:
		tier = "crit_fail"
	return {"roll": roll, "chance": chance, "tier": tier, "margin": maxf(0.0, roll - chance)}


static func is_success(result: Dictionary) -> bool:
	return result["tier"] == "success" or result["tier"] == "crit_success"


static func label(result: Dictionary) -> String:
	match result["tier"]:
		"crit_success":
			return "réussite critique"
		"success":
			return "réussie"
		"fail":
			return "ratée"
	return "échec critique"


static func _forced_result(tier: String, chance: float) -> Dictionary:
	match tier:
		"crit_success":
			return {"roll": 1, "chance": chance, "tier": tier, "margin": 0.0}
		"success":
			return {"roll": maxi(1, int(chance * 0.5)), "chance": chance, "tier": tier, "margin": 0.0}
		"fail":
			return {"roll": mini(100, int(chance) + 15), "chance": chance, "tier": tier, "margin": 15.0}
	return {"roll": 100, "chance": chance, "tier": "crit_fail", "margin": 70.0}
