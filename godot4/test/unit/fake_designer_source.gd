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
	{
		"name": "SH_ROBOTIC",
		"icon": "icons/ship_hulls/robotic_hull_small.png",
		"graphic": "hulls_design/robotic_hull.png",
		"description": "SH_ROBOTIC_DESC",
		"structure": 200.0,
		"available": false,
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
	{
		"name": "AR_ZORTRIUM_PLATE",
		"icon": "icons/ship_parts/zortrium_armor_plating.png",
		"class": "PC_ARMOUR",
		"capacity": 32.0,
		"cost": 8.0,
		"available": false,
		"mountable": PackedStringArray(["external"]),
	},
	{
		"name": "SR_WEAPON_0_1",
		"icon": "icons/ship_parts/flak.png",
		"class": "PC_DIRECT_WEAPON",
		"capacity": 3.0,
		"obsolete": true,
		"mountable": PackedStringArray(["external"]),
	},
]
var created: Array = []

var calls: Array = []
var designs := {
	"empire":
	[
		{
			"id": 7,
			"name": "Frigate Ms",
			"hull": "SH_BASIC_MEDIUM",
			"parts": PackedStringArray(["SR_WEAPON_1_1", "AR_STD_PLATE", ""]),
			"producible": true,
			"renamable": true,
		},
	],
	"obsolete":
	[
		{
			"id": 5,
			"name": "Old Scout",
			"hull": "SH_BASIC_SMALL",
			"parts": PackedStringArray([""]),
			"producible": true,
		},
	],
	"premade":
	[
		{
			"id": 30,
			"name": "Comsat",
			"hull": "SH_BASIC_SMALL",
			"parts": PackedStringArray([""]),
			"producible": true,
		},
	],
	"saved":
	[
		{
			"id": -1,
			"uuid": "aaaa-1",
			"name": "Kept Raider",
			"hull": "SH_BASIC_MEDIUM",
			"parts": PackedStringArray(["SR_WEAPON_1_1", "", ""]),
			"producible": true,
			"added": false,
		},
		{
			"id": -1,
			"uuid": "aaaa-2",
			"name": "Kept Scout",
			"hull": "SH_BASIC_SMALL",
			"parts": PackedStringArray([""]),
			"producible": true,
			"added": true,
		},
	],
}


func get_hulls(include_unavailable := false) -> Array:
	return hulls if include_unavailable else hulls.filter(func(h): return h.get("available", true))


func get_parts(include_unavailable := false) -> Array:
	return parts if include_unavailable else parts.filter(func(p): return p.get("available", true))


func evaluate(hull: String, design_parts: PackedStringArray) -> Dictionary:
	var attack := 0.0
	var structure := 30.0
	for part_name in design_parts:
		match part_name:
			"SR_WEAPON_1_1":
				attack += 18.0
			"AR_STD_PLATE":
				structure += 24.0
	var extra := {}
	if hull == "SH_BASIC_MEDIUM" and design_parts == designs["empire"][0]["parts"]:
		extra["duplicate_of"] = "Frigate Ms"
	if "AR_ZORTRIUM_PLATE" in design_parts:
		extra["unavailable"] = PackedStringArray(["AR_ZORTRIUM_PLATE"])
	return (
		extra
		. merged(
			{
				"valid": not hull.is_empty(),
				"attack": attack,
				"structure": structure,
				"speed": 75.0,
				"fuel": 5.0,
				"detection": 25.0,
				"cost": 20.0 + 6.0 * design_parts.size(),
				"turns": 2,
			}
		)
	)


func create(
	design_name: String, hull: String, design_parts: PackedStringArray, description := ""
) -> int:
	created.push_back([design_name, hull, design_parts])
	if not description.is_empty():
		calls.push_back(["describe", description])
	return 42


func update_design(
	design_id: int, design_name: String, hull: String, design_parts: PackedStringArray, _d: String
) -> int:
	calls.push_back(["update_design", design_id, design_name, hull, design_parts])
	return 43


func update_saved(
	uuid: String, design_name: String, hull: String, design_parts: PackedStringArray, _d: String
) -> bool:
	calls.push_back(["update_saved", uuid, design_name, hull, design_parts])
	return true


func set_part_obsolete(part_name: String, obsolete: bool) -> bool:
	calls.push_back(["set_part_obsolete", part_name, obsolete])
	return true


func set_hull_obsolete(hull_name: String, obsolete: bool) -> bool:
	calls.push_back(["set_hull_obsolete", hull_name, obsolete])
	return true


func add_all_saved() -> int:
	calls.push_back(["add_all_saved"])
	return 1


func get_designs(kind: String) -> Array:
	return designs.get(kind, [])


func set_obsolete(design_id: int, obsolete: bool) -> bool:
	calls.push_back(["set_obsolete", design_id, obsolete])
	return true


func delete_design(design_id: int) -> bool:
	calls.push_back(["delete_design", design_id])
	return true


func add_premade(design_id: int) -> int:
	calls.push_back(["add_premade", design_id])
	return 99


func rename_design(design_id: int, new_name: String) -> bool:
	calls.push_back(["rename_design", design_id, new_name])
	return true


func save_design(design_id: int) -> bool:
	calls.push_back(["save_design", design_id])
	return true


func add_saved(uuid: String) -> int:
	calls.push_back(["add_saved", uuid])
	return 99


func delete_saved(uuid: String) -> bool:
	calls.push_back(["delete_saved", uuid])
	return true
