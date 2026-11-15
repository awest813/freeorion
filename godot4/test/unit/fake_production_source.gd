extends RefCounted
## In-memory stand-in for ProductionSource (tests and screenshots).

var queue: Array = [
	{
		"index": 0,
		"build_type": "building",
		"name": "BLD_MILITARY_COMMAND",
		"design_id": -1,
		"label": "BLD_MILITARY_COMMAND",
		"icon": "icons/building/palace.png",
		"location_name": "Hegira β I",
		"remaining": 1,
		"progress": 0.35,
		"allocated_pp": 6.0,
		"turns_left": 4,
	},
	{
		"index": 1,
		"build_type": "ship",
		"name": "",
		"design_id": 3,
		"label": "Outpost Ship",
		"icon": "icons/ship_hulls/basic-medium-hull_small.png",
		"location_name": "Hegira β I",
		"remaining": 2,
		"progress": 0.0,
		"allocated_pp": 3.5,
		"turns_left": -1,
		"paused": true,
		"stockpile_allowed": true,
	},
]
var buildable: Array = [
	{
		"build_type": "building",
		"name": "BLD_SHIPYARD_BASE",
		"design_id": -1,
		"label": "BLD_SHIPYARD_BASE",
		"icon": "icons/building/shipyard-1.png",
		"cost": 10.0,
		"turns": 4,
	},
	{
		"build_type": "ship",
		"name": "",
		"design_id": 3,
		"label": "Outpost Ship",
		"icon": "icons/ship_hulls/basic-medium-hull_small.png",
		"cost": 56.0,
		"turns": 5,
	},
	{
		"build_type": "ship",
		"name": "",
		"design_id": 4,
		"label": "Scout",
		"icon": "icons/ship_hulls/basic-small-hull_small.png",
		"cost": 12.0,
		"turns": 2,
	},
	{
		"build_type": "stockpile",
		"name": "PROJECT_BT_STOCKPILE",
		"design_id": -1,
		"label": "PROJECT_BT_STOCKPILE",
		"icon": "icons/meter/stockpile.png",
		"cost": 1.0,
		"turns": 1,
	},
]
var calls: Array = []


func get_queue() -> Array:
	return queue


func get_points() -> Dictionary:
	return {"available": 15.0, "spent": 9.5, "stockpile": 0.0}


func get_buildable(location_id: int) -> Array:
	return buildable if location_id == 101 else []


func get_locations() -> Array:
	return [{"id": 101, "name": "Hegira β I"}, {"id": 102, "name": "Mu Arae II"}]


func enqueue(item: Dictionary, location_id: int) -> bool:
	calls.push_back(["enqueue", item.get("label"), location_id])
	return true


func remove(index: int) -> bool:
	calls.push_back(["remove", index])
	return true


func move(index: int, new_index: int) -> bool:
	calls.push_back(["move", index, new_index])
	return true


func set_quantity(index: int, quantity: int) -> bool:
	calls.push_back(["set_quantity", index, quantity])
	return true


func set_paused(index: int, paused: bool) -> bool:
	calls.push_back(["set_paused", index, paused])
	return true


func set_stockpile_allowed(index: int, allowed: bool) -> bool:
	calls.push_back(["set_stockpile_allowed", index, allowed])
	return true
