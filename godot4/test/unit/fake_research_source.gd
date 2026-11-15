extends RefCounted
## In-memory stand-in for ResearchSource (tests and screenshots).

const ICONS := {
	"LRN_ALGO_ELEGANCE": "icons/tech/algorithmic_elegance.png",
	"GRO_PLANET_ECOL": "icons/tech/planetary_ecology.png",
	"SHP_ZORTRIUM_PLATE": "icons/tech/armor_plating.png",
	"PRO_ROBOTIC_PROD": "icons/tech/robotic_production.png",
	"SHP_WEAPON_1_2": "icons/tech/defense.png",
	"LRN_PHYS_BRAIN": "icons/tech/the_physical_brain.png",
}

var queue: Array = [
	{
		"index": 0,
		"name": "LRN_ALGO_ELEGANCE",
		"category": "LEARNING_CATEGORY",
		"icon": "icons/tech/algorithmic_elegance.png",
		"allocated_rp": 4.5,
		"turns_left": 2,
		"progress": 0.6,
		"cost": 10.0,
	},
	{
		"index": 1,
		"name": "GRO_PLANET_ECOL",
		"category": "GROWTH_CATEGORY",
		"icon": "icons/tech/planetary_ecology.png",
		"allocated_rp": 0.0,
		"turns_left": 5,
		"progress": 0.0,
		"cost": 10.0,
	},
]
var techs: Array = [
	_tech("LRN_ALGO_ELEGANCE", "LEARNING_CATEGORY", 10.0, "researchable", true, ["LRN_PHYS_BRAIN"]),
	_tech("GRO_PLANET_ECOL", "GROWTH_CATEGORY", 10.0, "researchable", true),
	_tech("SHP_ZORTRIUM_PLATE", "SHIP_PARTS_CATEGORY", 48.0, "researchable", false),
	_tech("PRO_ROBOTIC_PROD", "PRODUCTION_CATEGORY", 40.0, "researchable", false),
	_tech(
		"SHP_WEAPON_1_2",
		"SHIP_WEAPONS_CATEGORY",
		24.0,
		"partial",
		false,
		["SHP_ZORTRIUM_PLATE", "LRN_ALGO_ELEGANCE"]
	),
	_tech("LRN_PHYS_BRAIN", "LEARNING_CATEGORY", 12.0, "complete", false),
]
var calls: Array = []


static func _tech(
	tech_name: String,
	category: String,
	cost: float,
	status: String,
	queued: bool,
	prerequisites: Array = []
) -> Dictionary:
	return {
		"name": tech_name,
		"category": category,
		"icon": ICONS.get(tech_name, ""),
		"short_description": tech_name + "_SHORT_DESC",
		"cost": cost,
		"turns": 3,
		"status": status,
		"in_queue": queued,
		"progress": 0.0,
		"prerequisites": PackedStringArray(prerequisites),
	}


func get_queue() -> Array:
	return queue


func get_points() -> Dictionary:
	return {"available": 7.5, "spent": 4.5}


func get_techs() -> Array:
	return techs


func get_categories() -> PackedStringArray:
	return PackedStringArray(
		["LEARNING_CATEGORY", "GROWTH_CATEGORY", "PRODUCTION_CATEGORY", "SHIP_PARTS_CATEGORY"]
	)


func enqueue(tech_name: String, position := -1) -> bool:
	if position < 0:
		calls.push_back(["enqueue", tech_name])
	else:
		calls.push_back(["enqueue_at", tech_name, position])
	return true


func remove(tech_name: String) -> bool:
	calls.push_back(["remove", tech_name])
	return true


func move(tech_name: String, position: int) -> bool:
	calls.push_back(["move", tech_name, position])
	return true


func set_paused(tech_name: String, paused: bool) -> bool:
	calls.push_back(["set_paused", tech_name, paused])
	return true
