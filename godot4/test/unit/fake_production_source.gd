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
## Items removed this turn (get_removed()).
var removed: Array = []


func get_queue() -> Array:
	return queue


func get_points() -> Dictionary:
	return {"available": 15.0, "spent": 9.5, "stockpile": 0.0}


func get_buildable(location_id: int, include_unavailable := false) -> Array:
	if location_id != 101:
		return []
	if not include_unavailable:
		return buildable
	return (
		buildable
		+ [
			{
				"build_type": "building",
				"name": "BLD_GAS_GIANT_GEN",
				"label": "BLD_GAS_GIANT_GEN",
				"cost": 40.0,
				"turns": 5,
				"available": false,
				"reason": "Needs a gas giant",
			}
		]
	)


func get_group_points(_location_id: int) -> Dictionary:
	return {"output": 15.0, "allocated": 9.5}


func get_locations() -> Array:
	return [{"id": 101, "name": "Hegira β I"}, {"id": 102, "name": "Mu Arae II"}]


func get_item_locations(item: Dictionary) -> Array:
	if item.get("build_type") == "ship":
		return [
			{"id": 101, "name": "Hegira β I", "system_id": 11},
			{"id": 102, "name": "Mu Arae II", "system_id": 12},
			{"id": 103, "name": "Vega III", "system_id": 13}
		]
	return [{"id": 101, "name": "Hegira β I", "system_id": 11}]


func enqueue(item: Dictionary, location_id: int, position := -1, force := false) -> bool:
	if force:
		calls.push_back(["enqueue_forced", item.get("label"), location_id])
	elif position < 0:
		calls.push_back(["enqueue", item.get("label"), location_id])
	else:
		calls.push_back(["enqueue_at", item.get("label"), location_id, position])
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


func set_blocksize(index: int, blocksize: int) -> bool:
	calls.push_back(["set_blocksize", index, blocksize])
	return true


func duplicate_item(index: int) -> bool:
	calls.push_back(["duplicate", index])
	return true


func split_incomplete(index: int) -> bool:
	calls.push_back(["split_incomplete", index])
	return true


func set_rally_point(index: int, system_id: int) -> bool:
	calls.push_back(["set_rally_point", index, system_id])
	return true


func get_removed() -> Array:
	return removed


func restore(index: int) -> bool:
	calls.push_back(["restore", index])
	return true
