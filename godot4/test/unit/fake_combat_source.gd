extends RefCounted
## In-memory stand-in for CombatSource (tests and screenshots): two combats,
## the newer one with a full log.

const BLUE := Color("#1193ff")
const GREEN := Color("#00ff00")
const GREY := Color("#999999")

var pending := 0
var combats: Array = [
	{
		"id": 5,
		"turn": 23,
		"system_id": 1600,
		"system_name": "Iszm α",
		"sides":
		[
			_side(1, "Terran Imperium", BLUE, true, 2, 1, 70.0, 110.0, 54.0),
			_side(-1, "Neutral", GREY, false, 2, 0, 290.0, 344.0, 198.0),
			_side(2, "Congregation", GREEN, false, 1, 1, 0.0, 40.0, 0.0),
		],
	},
	{
		"id": 2,
		"turn": 14,
		"system_id": 704,
		"system_name": "Hegira β",
		"sides":
		[
			_side(1, "Terran Imperium", BLUE, true, 3, 0, 260.0, 280.0, 96.0),
			_side(-1, "Neutral", GREY, false, 1, 1, 0.0, 120.0, 20.0),
		],
	},
]
var units := {
	1:
	[
		_unit(
			2720, "Delany", "ship", "icons/ship_hulls/basic-small-hull_small.png", 0.0, 40.0, true
		),
		_unit(
			2731,
			"Defender I",
			"ship",
			"icons/ship_hulls/basic-medium-hull_small.png",
			70,
			70,
			false
		),
	],
	-1:
	[
		_unit(1608, "Iszm α I", "planet", "", 80.0, 80.0, false, "PT_OCEAN"),
		_unit(7012, "Tartaro", "ship", "", 210.0, 264.0, false),
	],
	2:
	[_unit(2800, "Scout", "ship", "icons/ship_hulls/basic-small-hull_small.png", 0.0, 40.0, true)],
}
var events: Array = [
	_event("bout", "Round 1"),
	_event(
		"attack",
		"<planet 1608>Iszm α I</planet> damages <ship 2800>Scout</ship> for 30 damage.",
		[
			_event(
				"attack",
				"<planet 1608>Iszm α I</planet> attacks <ship 2800>Scout</ship> for 30 damage",
				[],
				"Weapon: <shippart DEF_DEFENSE>Planetary Defense</shippart>  Damage: 30"
			)
		]
	),
	_event(
		"attack",
		(
			"<ship 7012>Tartaro</ship> damages 2 targets: <ship 2720>Delany</ship> for 72 damage"
			+ " and <ship 2800>Scout</ship> for 96 damage."
		),
		[
			_event(
				"attack", "<ship 7012>Tartaro</ship> attacks <ship 2720>Delany</ship> for 24 damage"
			),
			_event(
				"attack", "<ship 7012>Tartaro</ship> attacks <ship 2800>Scout</ship> for 72 damage"
			),
		]
	),
	_event(
		"attack",
		"<ship 2731>Defender I</ship> damages <ship 7012>Tartaro</ship> for 54 damage.",
	),
	_event(
		"destroyed",
		(
			"The <rgba 17 147 255 255><empire 1>Terran Imperium</empire></rgba> ship"
			+ " <ship 2720>Delany</ship> was destroyed"
		)
	),
	_event(
		"destroyed",
		(
			"The <rgba 0 255 0 255><empire 2>Congregation</empire></rgba> ship"
			+ " <ship 2800>Scout</ship> was destroyed"
		)
	),
	_event("bout", "Round 2"),
	_event("bout", "Round 3"),
]
var requested: Array = []


func list_combats() -> Array:
	return combats


func get_combat(log_id: int) -> Dictionary:
	requested.push_back(log_id)
	for combat: Dictionary in combats:
		if combat["id"] == log_id:
			var detail := combat.duplicate(true)
			for side: Dictionary in detail["sides"]:
				side["unit_list"] = units.get(side["empire_id"], []) if log_id == 5 else []
			detail["events"] = events if log_id == 5 else []
			if log_id == 5:
				_add_bouts(detail)
			return detail
	return {}


# Health before the combat and after each of its 3 bouts: everything
# happened in the first.
func _add_bouts(detail: Dictionary) -> void:
	detail["bouts"] = 3
	for side: Dictionary in detail["sides"]:
		var start := 0.0
		for unit: Dictionary in side["unit_list"]:
			var before: float = 40.0 if unit["destroyed"] else unit["max_health"]
			var after: float = unit["health"]
			unit["health_by_bout"] = PackedFloat32Array([before, after, after, after])
			start += before
		var final: float = side["health"]
		side["health_by_bout"] = PackedFloat32Array([start, final, final, final])
		side["dealt_by_bout"] = PackedFloat32Array([side["damage_dealt"], 0.0, 0.0])


func get_pending_count() -> int:
	return pending


static func _side(
	empire_id: int,
	side_name: String,
	color: Color,
	own: bool,
	count: int,
	destroyed: int,
	health: float,
	max_health: float,
	damage: float
) -> Dictionary:
	return {
		"empire_id": empire_id,
		"name": side_name,
		"color": color,
		"own": own,
		"units": count,
		"destroyed": destroyed,
		"health": health,
		"max_health": max_health,
		"damage_dealt": damage,
	}


static func _unit(
	id: int,
	unit_name: String,
	type: String,
	icon: String,
	health: float,
	max_health: float,
	destroyed: bool,
	planet_type := ""
) -> Dictionary:
	return {
		"id": id,
		"name": unit_name,
		"type": type,
		"icon": icon,
		"planet_type": planet_type,
		"health": health,
		"max_health": max_health,
		"destroyed": destroyed,
	}


static func _event(kind: String, text: String, children := [], details := "") -> Dictionary:
	return {"kind": kind, "text": text, "details": details, "children": children}
