extends RefCounted
## In-memory stand-in for ObjectsSource (tests and screenshots).

const BLUE := Color("#1193ff")
const GREEN := Color("#00ff00")

var calls: Array = []
var rows := {
	"planets":
	[
		_planet(
			704, "Hegira β I", 1, "Terran Imperium", "SP_HUMAN", "FOCUS_INDUSTRY", 17.4, 15.0, 3.2
		),
		_planet(1608, "Iszm α I", -1, "", "SP_SSLITH", "", 9.0, 0.0, 0.0),
		_planet(
			812, "Mu Arae II", 1, "Terran Imperium", "SP_HUMAN", "FOCUS_RESEARCH", 5.1, 1.0, 6.5
		),
		_planet(
			2210, "Vega IV", 2, "Congregation", "SP_EGASSEM", "FOCUS_INDUSTRY", 22.0, 18.0, 1.0
		),
	],
	"fleets":
	[
		{
			"id": 2712,
			"name": "Battle Fleet",
			"owner_id": 1,
			"owner_name": "Terran Imperium",
			"owner_color": BLUE,
			"system_id": -1,
			"system_name": "Mu Arae",
			"moving": true,
			"ships": 3,
			"structure": 150.0,
			"max_structure": 168.0,
			"destination": "Vega",
			"eta": 3,
			"aggression": "aggressive",
		},
		{
			"id": 2720,
			"name": "Scout Fleet",
			"owner_id": 1,
			"owner_name": "Terran Imperium",
			"owner_color": BLUE,
			"system_id": 704,
			"system_name": "Hegira β",
			"moving": false,
			"ships": 1,
			"structure": 16.0,
			"max_structure": 16.0,
			"destination": "",
			"eta": 0,
			"aggression": "passive",
		},
	],
	"buildings":
	[
		{
			"id": 900,
			"name": "Imperial Palace",
			"owner_id": 1,
			"owner_name": "Terran Imperium",
			"owner_color": BLUE,
			"system_id": 704,
			"system_name": "Hegira β",
			"building_type": "BLD_IMPERIAL_PALACE",
			"planet_id": 705,
			"planet_name": "Hegira β I",
		},
	],
}


func list_objects(kind: String, own_only: bool) -> Array:
	calls.push_back([kind, own_only])
	var result: Array = rows.get(kind, [])
	if own_only:
		result = result.filter(func(r): return r["owner_id"] == 1)
	return result


static func _planet(
	id: int,
	planet_name: String,
	owner: int,
	owner_name: String,
	species: String,
	focus: String,
	population: float,
	industry: float,
	research: float
) -> Dictionary:
	return {
		"id": id,
		"name": planet_name,
		"owner_id": owner,
		"owner_name": owner_name,
		"owner_color": BLUE if owner == 1 else GREEN,
		"system_id": id - 4,
		"system_name": planet_name.get_slice(" ", 0) + " " + planet_name.get_slice(" ", 1),
		"type": "PT_OCEAN" if owner == 1 else "PT_TUNDRA",
		"size": "SZ_MEDIUM",
		"species": species,
		"focus": focus,
		"population": population,
		"industry": industry,
		"research": research,
		"influence": 0.5,
		"stability": 8.0,
		"supply": 2.0,
		"defense": 15.0,
		"shield": 10.0,
		"troops": 6.0,
	}
