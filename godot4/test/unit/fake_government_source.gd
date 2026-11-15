extends RefCounted
## In-memory stand-in for GovernmentSource (tests and screenshots).

const ICONS := {
	"PLC_PLANETARY_INFRA": "icons/policies/economic_planetary_infrastructure.png",
	"PLC_PROPAGANDA": "icons/policies/social_propaganda.png",
	"PLC_CENTRALIZATION": "icons/policies/economic_centralization.png",
	"PLC_TECHNOCRACY": "icons/policies/economic_technocracy.png",
	"PLC_ALGORITHMIC_RESEARCH": "icons/policies/social_algorithmic_research.png",
	"PLC_INDUSTRIALISM": "icons/policies/economic_industrialism.png",
}

var slots: Array = [
	{"category": "ECONOMIC_CATEGORY", "policies": ["PLC_PLANETARY_INFRA", ""]},
	{"category": "SOCIAL_CATEGORY", "policies": ["PLC_PROPAGANDA"]},
]
var policies: Array = [
	_policy("PLC_PLANETARY_INFRA", "ECONOMIC_CATEGORY", 4.0, true, true, true),
	_policy("PLC_PROPAGANDA", "SOCIAL_CATEGORY", 5.0, true, true, true),
	_policy("PLC_CENTRALIZATION", "ECONOMIC_CATEGORY", 12.0, false, true, true),
	_policy("PLC_TECHNOCRACY", "ECONOMIC_CATEGORY", 9.0, false, false, true),
	_policy("PLC_ALGORITHMIC_RESEARCH", "SOCIAL_CATEGORY", 6.0, false, true, true),
	_policy("PLC_INDUSTRIALISM", "ECONOMIC_CATEGORY", 8.0, false, true, false),
	_locked("PLC_RACIAL_PURITY", "SOCIAL_CATEGORY", 7.0),
]
var modified := true
var calls: Array = []


static func _policy(
	policy_name: String, category: String, cost: float, adopted: bool, affordable: bool, ok: bool
) -> Dictionary:
	return {
		"name": policy_name,
		"category": category,
		"icon": ICONS.get(policy_name, ""),
		"short_description": policy_name + "_SHORT_DESC",
		"cost": cost,
		"adopted": adopted,
		"affordable": affordable,
		"prerequisites_ok": ok,
		"available": true,
		"description": policy_name + "_DESC",
		"adopted_this_turn": false,
		"current_turns": 3 if adopted else 0,
		"total_turns": 7 if adopted else 0,
		"excluded_by": [] if ok else ["PLC_PLANETARY_INFRA"],
		"prerequisites": [],
	}


static func _locked(policy_name: String, category: String, cost: float) -> Dictionary:
	var policy := _policy(policy_name, category, cost, false, true, true)
	policy["available"] = false
	return policy


func get_slots() -> Array:
	return slots


func get_policies() -> Array:
	return policies


func get_influence() -> Dictionary:
	return {"stockpile": 23.5, "adoption_cost": 9.0}


func adopt(policy_name: String, slot: int) -> bool:
	calls.push_back(["adopt", policy_name, slot])
	return true


func de_adopt(policy_name: String) -> bool:
	calls.push_back(["de_adopt", policy_name])
	return true


func is_modified() -> bool:
	return modified


func revert() -> bool:
	calls.push_back(["revert"])
	return true
