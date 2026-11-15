class_name MapModeData
extends RefCounted
## The per-system values the map modes show (GalaxyMap.mode_values), worked
## out from rows such as FOObjects.list_objects() gives, so tests can feed
## them directly.


## Per-system values for \a mode from the running game.
static func from_game(mode: String) -> Dictionary:
	match mode:
		"political":
			return political_values(FOObjects.list_objects("planets", false))
		"resources":
			return resource_values(FOObjects.list_objects("planets", true))
		"threat":
			var hostile := {-1: true}  # monsters
			for empire: Dictionary in FODiplomacy.get_empires():
				if empire.get("status", "") == "war":
					hostile[empire["id"]] = true
			return threat_values(FOObjects.list_objects("fleets", false), hostile)
	return {}


## Each system's owner colour: the empire owning most of its planets.
static func political_values(planets: Array) -> Dictionary:
	var counts := {}
	for planet: Dictionary in planets:
		var owner: int = planet.get("owner_id", -1)
		var system_id: int = planet.get("system_id", -1)
		if owner < 0 or system_id < 0:
			continue
		if not counts.has(system_id):
			counts[system_id] = {}
		var by_owner: Dictionary = counts[system_id]
		if not by_owner.has(owner):
			by_owner[owner] = [0, planet.get("owner_color", Color.WHITE)]
		by_owner[owner][0] += 1
	var result := {}
	for system_id in counts:
		var best: Array = []
		for owner in counts[system_id]:
			var entry: Array = counts[system_id][owner]
			if best.is_empty() or entry[0] > best[0]:
				best = entry
		result[system_id] = {"color": best[1]}
	return result


## Industry and research of the player's planets, summed per system.
static func resource_values(own_planets: Array) -> Dictionary:
	var result := {}
	for planet: Dictionary in own_planets:
		var system_id: int = planet.get("system_id", -1)
		if system_id < 0:
			continue
		var entry: Dictionary = result.get(system_id, {"industry": 0.0, "research": 0.0})
		entry["industry"] += planet.get("industry", 0.0)
		entry["research"] += planet.get("research", 0.0)
		result[system_id] = entry
	return result


## Structure of the fleets of \a hostile owners (owner id -> true) in each
## system: monsters' and those of empires at war with the player.
static func threat_values(fleets: Array, hostile: Dictionary) -> Dictionary:
	var result := {}
	for fleet: Dictionary in fleets:
		var system_id: int = fleet.get("system_id", -1)
		if system_id < 0 or not hostile.has(fleet.get("owner_id", -1)):
			continue
		var entry: Dictionary = result.get(system_id, {"threat": 0.0})
		entry["threat"] += fleet.get("structure", 0.0)
		result[system_id] = entry
	return result
