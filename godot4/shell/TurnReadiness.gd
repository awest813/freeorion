class_name TurnReadiness
extends RefCounted
## What may be forgotten before ending a turn: unspent production or research
## points, colony ships without orders, newly built fleets without orders,
## unarmed fleets (scouts) idle and not exploring, a free policy slot
## while a policy could be adopted into it, planets too unhappy to grow
## (stability 5 or less: their industry and research stop increasing), and
## influence about to run out (then every planet's stability falls).
## An issue the player ended a turn anyway on isn't raised again for
## REMIND_TURNS turns or until it is resolved (unacknowledged()), so the same
## reminder doesn't come every turn, nor never again.
## check() works on plain data (gather() reads it from the game), so tests
## can feed it directly.

## Option that turns the check on and off.
const OPTION := "ui.turn.readiness.check"
## Unspent PP or RP above this is worth a warning.
const EPSILON := 0.05
## Stability at or below which a populated planet's output stops growing
## (the game's own planet status, OPTIONS_DB_UI_PLANET_STATUS_UNHAPPY).
const UNHAPPY_STABILITY := 5.0
## Influence running out within this many turns is worth a warning.
const INFLUENCE_WARN_TURNS := 10
## Unhappy planets named in the warning; the rest are counted.
const UNHAPPY_NAMED := 3
## Turns after which an issue ended anyway on is raised again.
const REMIND_TURNS := 5


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
			(
				issues
				. push_back(
					{
						"text": tr_s(key).replace("%1%", "%.1f" % unspent),
						"screen": entry[1],
						"key": key,
					}
				)
			)
	for fleet: Dictionary in data.get("fleets", []):
		if fleet.get("moving", false) or fleet.get("destination", "") != "":
			continue
		var key := ""
		if fleet.get("colony_ships", 0) > 0:
			key = "READINESS_COLONY_SHIPS"
		elif fleet.get("age", 1) == 0:
			key = "READINESS_NEW_FLEET"
		elif not fleet.get("armed", true) and not fleet.get("exploring", false):
			key = "READINESS_IDLE_SCOUT"
		if key != "":
			(
				issues
				. push_back(
					{
						"text":
						tr_s(key).replace("%1%", fleet["name"]).replace(
							"%2%", fleet["system_name"]
						),
						"key": "%s:%d" % [key, fleet["id"]],
						"target":
						{
							"system_id": fleet["system_id"],
							"fleet_id": fleet["id"],
							"position": fleet.get("position", Vector2.ZERO),
						},
					}
				)
			)
	for category: String in data.get("free_policy_slots", []):
		var text := tr_s("READINESS_POLICY_SLOT").replace("%1%", tr_s(category))
		issues.push_back({"text": text, "screen": "government", "key": "policy:" + category})
	var unhappy := unhappy_issue(data.get("planets", []))
	if not unhappy.is_empty():
		issues.push_back(unhappy)
	var influence := influence_issue(resources)
	if not influence.is_empty():
		issues.push_back(influence)
	return issues


## The warning for own \a planets (FOObjects' planet rows) too unhappy to
## grow, naming the first few; it opens the first one's system. {} if none.
static func unhappy_issue(planets: Array) -> Dictionary:
	var unhappy := planets.filter(
		func(p: Dictionary):
			return (
				p.get("population", 0.0) > 0.0
				and p.get("stability", UNHAPPY_STABILITY + 1.0) <= UNHAPPY_STABILITY
			)
	)
	if unhappy.is_empty():
		return {}
	var names: Array = unhappy.slice(0, UNHAPPY_NAMED).map(func(p): return str(p.get("name", "")))
	var text := (
		tr_s("READINESS_UNHAPPY_ONE").replace("%1%", names[0])
		if unhappy.size() == 1
		else (tr_s("READINESS_UNHAPPY_MANY").replace("%1%", str(unhappy.size())).replace(
			"%2%", ", ".join(names)
		))
	)
	return {
		"text": text,
		"key": "unhappy",
		"target": {"system_id": unhappy[0].get("system_id", -1)},
	}


## The warning when influence (\a resources: influence, influence_change)
## falls fast enough to run out within INFLUENCE_WARN_TURNS. {} if not.
static func influence_issue(resources: Dictionary) -> Dictionary:
	var change: float = resources.get("influence_change", 0.0)
	var stock: float = resources.get("influence", 0.0)
	if change >= -EPSILON or stock + change * INFLUENCE_WARN_TURNS > 0.0:
		return {}
	var turns := maxi(int(floor(maxf(stock, 0.0) / -change)), 0)
	return {
		"text":
		tr_s("READINESS_INFLUENCE").replace("%1%", "%.1f" % -change).replace("%2%", str(turns)),
		"screen": "government",
		"key": "influence",
	}


## \a issues (check()) without those whose key is in \a acknowledged (the
## player ended a turn anyway while they stood: key -> the turn they did).
## Acknowledged keys no longer among \a issues are dropped from it: once
## resolved, an issue counts again when it comes back. One still standing
## REMIND_TURNS after it was acknowledged (on \a turn) is raised again: an
## empty research queue ignored once shouldn't go unmentioned all game.
static func unacknowledged(issues: Array, acknowledged: Dictionary, turn := -1) -> Array:
	var keys := {}
	for issue: Dictionary in issues:
		keys[issue.get("key", "")] = true
	for key in acknowledged.keys():
		var since: int = acknowledged[key] if acknowledged[key] is int else -1
		if not keys.has(key) or (turn >= 0 and since >= 0 and turn - since >= REMIND_TURNS):
			acknowledged.erase(key)
	return issues.filter(func(i): return not acknowledged.has(i.get("key", "")))


## The data check() needs, from the running game.
static func gather() -> Dictionary:
	var fleets := []
	for fleet: Dictionary in FOObjects.list_objects("fleets", true):
		var view: FOFleet = FOUniverse.get_fleet(fleet["id"])
		if view:
			fleet["position"] = view.get_position()
		fleet["exploring"] = FOExplore.is_exploring(fleet["id"])
		fleets.push_back(fleet)
	return {
		"resources": FOUniverse.get_empire_resources(),
		"production_queue": FOProduction.get_queue().size(),
		"research_queue": FOResearch.get_queue().size(),
		"fleets": fleets,
		"free_policy_slots":
		free_policy_slots(FOGovernment.get_slots(), FOGovernment.get_policies()),
		"planets": FOObjects.list_objects("planets", true),
	}


## Categories of \a slots (FOGovernment.get_slots()) with an empty slot that
## one of \a policies (get_policies()) could be adopted into now.
static func free_policy_slots(slots: Array, policies: Array) -> Array:
	var categories := []
	for slot: Dictionary in slots:
		var category: String = slot.get("category", "")
		if not slot.get("policies", []).has(""):
			continue
		for policy: Dictionary in policies:
			if (
				policy.get("category") == category
				and not policy.get("adopted", false)
				and policy.get("available", false)
				and policy.get("affordable", false)
				and policy.get("prerequisites_ok", true)
			):
				categories.push_back(category)
				break
	return categories


## Whether the player wants the check (on unless turned off in Options).
static func enabled() -> bool:
	if not Engine.has_singleton("FOOptions"):
		return true
	var options := Engine.get_singleton("FOOptions")
	return not options.exists(OPTION) or options.get_value(OPTION)


## tr() for static functions.
static func tr_s(key: String) -> String:
	return TranslationServer.translate(key)
