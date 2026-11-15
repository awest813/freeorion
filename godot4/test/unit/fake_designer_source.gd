extends RefCounted
## In-memory stand-in for DesignerSource (tests and screenshots); slot
## positions and art follow the real SH_BASIC_MEDIUM hull.

var hulls: Array = [
	{
		"name": "SH_BASIC_MEDIUM",
		"icon": "icons/ship_hulls/basic-medium-hull_small.png",
		"graphic": "hulls_design/basic-medium-hull.png",
		"slots":
		[
			{"type": "external", "x": 0.65, "y": 0.25},
			{"type": "external", "x": 0.65, "y": 0.55},
			{"type": "internal", "x": 0.35, "y": 0.35},
		],
	},
	{
		"name": "SH_BASIC_SMALL",
		"icon": "icons/ship_hulls/basic-small-hull_small.png",
		"graphic": "hulls_design/basic-small-hull.png",
		"slots": [{"type": "external", "x": 0.5, "y": 0.5}],
	},
]
var parts: Array = [
	{
		"name": "SR_WEAPON_1_1",
		"icon": "icons/ship_parts/mass-driver.png",
		"class": "PC_DIRECT_WEAPON",
		"capacity": 18.0,
		"mountable": PackedStringArray(["external"]),
	},
	{
		"name": "AR_STD_PLATE",
		"icon": "icons/ship_parts/std_armor_plating.png",
		"class": "PC_ARMOUR",
		"capacity": 24.0,
		"mountable": PackedStringArray(["external"]),
	},
	{
		"name": "DT_DETECTOR_1",
		"icon": "icons/ship_parts/detector-1.png",
		"class": "PC_DETECTION",
		"capacity": 25.0,
		"mountable": PackedStringArray(["internal"]),
	},
]
var created: Array = []


func get_hulls() -> Array:
	return hulls


func get_parts() -> Array:
	return parts


func evaluate(hull: String, design_parts: PackedStringArray) -> Dictionary:
	var attack := 0.0
	var structure := 30.0
	for part_name in design_parts:
		match part_name:
			"SR_WEAPON_1_1":
				attack += 18.0
			"AR_STD_PLATE":
				structure += 24.0
	return {
		"valid": not hull.is_empty(),
		"attack": attack,
		"structure": structure,
		"speed": 75.0,
		"fuel": 5.0,
		"detection": 25.0,
		"cost": 20.0 + 6.0 * design_parts.size(),
		"turns": 2,
	}


func create(design_name: String, hull: String, design_parts: PackedStringArray) -> int:
	created.push_back([design_name, hull, design_parts])
	return 42


func get_designs() -> Array:
	return [
		{
			"id": 7,
			"name": "Frigate Ms",
			"hull": "SH_BASIC_MEDIUM",
			"parts": PackedStringArray(["SR_WEAPON_1_1", "AR_STD_PLATE", ""]),
			"producible": true,
		}
	]
