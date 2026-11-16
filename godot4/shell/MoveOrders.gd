class_name MoveOrders
extends RefCounted
## Fleet move orders: why one is refused (FOOrders.move_problem()), the
## route a fleet would take, previewed on the map, and scouts sent exploring
## on their own (option ui.fleet.explore.scouts).

## Option: the starting scouts, and scouts as they're built, explore.
const OPTION_EXPLORE_SCOUTS := "ui.fleet.explore.scouts"
## Age of the starting fleets, made before the first turn (and of nothing
## else).
const STARTING_FLEET_AGE := 1 << 29


## What to tell the player when a move order to a system is refused, for
## \a problem (FOOrders.move_problem()).
static func move_refusal_text(problem: String) -> String:
	return TranslationServer.translate(
		problem if problem.begins_with("MOVE_PROBLEM_") else "SYSTEM_PANEL_ORDER_REFUSED"
	)


## In \a shell: the route the fleet picked (or the box-selected fleets) would take to
## \a system_id, with its ETA, drawn on the map; in the warning colour, with
## the reason, when it can't get there (no known route: a straight line).
static func preview_route(shell: GameShell, system_id: int) -> void:
	var fleets: FleetLayer = shell.map_view.map.fleets
	var preview := {}
	var problem := ""
	var fleet_id := shell.active_fleet()
	if shell.follow_game and system_id >= 0 and shell.map_modes.has_fleet_selection():
		preview = shell.map_modes.group_preview(system_id)
	elif shell.follow_game and system_id >= 0 and fleet_id >= 0:
		var fleet: FOFleet = FOUniverse.get_fleet(fleet_id)
		if fleet and system_id != fleet.get_system_id():
			var append := Input.is_key_pressed(KEY_SHIFT)
			preview = fleet.preview_route(system_id, append)
			problem = FOOrders.move_problem(fleet_id, system_id, append)
			problem = "" if problem == "MOVE_PROBLEM_UNKNOWN" else problem
			var target: FOSystem = FOUniverse.get_system(system_id)
			if preview.is_empty() and problem != "" and target:
				var line := PackedVector2Array([fleet.get_position(), target.get_position()])
				preview = {"points": line, "eta": -1}
	if preview.is_empty():
		fleets.set_preview(PackedVector2Array(), PackedVector2Array())
		return
	fleets.set_preview(
		preview.get("points", PackedVector2Array()),
		preview.get("turn_ends", PackedVector2Array()),
		(
			TranslationServer.translate(problem + "_SHORT")
			if problem != ""
			else GameShell.eta_text(preview.get("eta", -1))
		),
		preview.get("turn_etas", PackedInt32Array()),
		preview.get("turn_flags", PackedInt32Array()),
		problem != ""
	)


## Ids of the scouts in \a fleets (FOObjects.list_objects("fleets", true))
## to send exploring on turn \a turn: each fleet whose \a heads entry
## (FOUniverse.get_map_snapshot() fleet_heads by id) is "scout", that is
## new (built this turn, or one of the starting fleets in the first turns),
## idle, and not exploring yet.
static func scouts_to_explore(fleets: Array, heads: Dictionary, turn: int) -> Array:
	var ids := []
	for fleet: Dictionary in fleets:
		var id: int = fleet.get("id", -1)
		var age: int = fleet.get("age", 1)
		if (
			heads.get(id, "") == "scout"
			and (age == 0 or (turn <= 2 and age >= STARTING_FLEET_AGE))
			and not fleet.get("moving", false)
			and str(fleet.get("destination", "")) == ""
			and not fleet.get("exploring", false)
		):
			ids.push_back(id)
	return ids


## At the start of a turn: new scouts explore, if the player wants that.
static func explore_new_scouts() -> void:
	if not Engine.has_singleton("FOOptions"):
		return
	if not Engine.get_singleton("FOOptions").get_value(OPTION_EXPLORE_SCOUTS):
		return
	var snapshot: Dictionary = FOUniverse.get_map_snapshot()
	var heads := {}
	var ids: PackedInt32Array = snapshot.get("fleet_ids", PackedInt32Array())
	var names: Array = Array(snapshot.get("fleet_heads", []))
	for k in mini(ids.size(), names.size()):
		heads[ids[k]] = names[k]
	var fleets: Array = FOObjects.list_objects("fleets", true)
	for fleet: Dictionary in fleets:
		fleet["exploring"] = FOExplore.is_exploring(fleet["id"])
	var turn: int = GlobalFreeOrionNode.get_current_turn()
	for id: int in scouts_to_explore(fleets, heads, turn):
		FOExplore.set_exploring(id, true)
