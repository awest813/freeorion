class_name MoveOrders
extends RefCounted
## Fleet move orders: why one is refused (FOOrders.move_problem()), and the
## route a fleet would take, previewed on the map.


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
