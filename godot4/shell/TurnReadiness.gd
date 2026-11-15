class_name TurnReadiness
extends RefCounted
## What may be forgotten before ending a turn: unspent production or research
## points, colony ships without orders and newly built fleets without orders.
## check() works on plain data (gather() reads it from the game), so tests
## can feed it directly.

## Option that turns the check on and off.
const OPTION := "ui.turn.readiness.check"
## Unspent PP or RP above this is worth a warning.
const EPSILON := 0.05


## Warnings for \a data ({resources, production_queue, research_queue,
## fleets}): each {text, screen} or {text, target} (a map target, as for
## GameShell.go_to()).
static func check(data: Dictionary) -> Array:
	var issues := []
	var resources: Dictionary = data.get("resources", {})
	for entry in [
		["industry", "production", "production_queue", "READINESS_PP", "READINESS_PP_EMPTY"],
		["research", "research", "research_queue", "READINESS_RP", "READINESS_RP_EMPTY"],
	]:
		var unspent: float = resources.get(entry[0], 0.0) - resources.get(entry[0] + "_spent", 0.0)
		if unspent > EPSILON:
			var key: String = entry[4] if data.get(entry[2], 0) == 0 else entry[3]
			issues.push_back(
				{"text": tr_s(key).replace("%1%", "%.1f" % unspent), "screen": entry[1]}
			)
	for fleet: Dictionary in data.get("fleets", []):
		if fleet.get("moving", false) or fleet.get("destination", "") != "":
			continue
		var key := ""
		if fleet.get("colony_ships", 0) > 0:
			key = "READINESS_COLONY_SHIPS"
		elif fleet.get("age", 1) == 0:
			key = "READINESS_NEW_FLEET"
		if key != "":
			(
				issues
				. push_back(
					{
						"text":
						tr_s(key).replace("%1%", fleet["name"]).replace(
							"%2%", fleet["system_name"]
						),
						"target":
						{
							"system_id": fleet["system_id"],
							"fleet_id": fleet["id"],
							"position": fleet.get("position", Vector2.ZERO),
						},
					}
				)
			)
	return issues


## The data check() needs, from the running game.
static func gather() -> Dictionary:
	var fleets := []
	for fleet: Dictionary in FOObjects.list_objects("fleets", true):
		var view: FOFleet = FOUniverse.get_fleet(fleet["id"])
		if view:
			fleet["position"] = view.get_position()
		fleets.push_back(fleet)
	return {
		"resources": FOUniverse.get_empire_resources(),
		"production_queue": FOProduction.get_queue().size(),
		"research_queue": FOResearch.get_queue().size(),
		"fleets": fleets,
	}


## Whether the player wants the check (on unless turned off in Options).
static func enabled() -> bool:
	if not Engine.has_singleton("FOOptions"):
		return true
	var options := Engine.get_singleton("FOOptions")
	return not options.exists(OPTION) or options.get_value(OPTION)


## tr() for static functions.
static func tr_s(key: String) -> String:
	return TranslationServer.translate(key)
