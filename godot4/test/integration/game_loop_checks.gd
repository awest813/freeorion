extends RefCounted
## Checks for the FOUniverse views and FOOrders API, run inside the quickstart
## game of test_quickstart.gd (the bridge supports one game per process).

var _test: GutTest
var _fleet_id := -1
var _dest_id := -1
var _start_position := Vector2.ZERO


func _init(test: GutTest) -> void:
	_test = test


## Call after the game started, before the first turn is ended.
func before_turn() -> void:
	var empire_id: int = FOUniverse.get_empire_id()
	_test.assert_gt(empire_id, -1, "Player controls an empire")

	_check_snapshot()
	await _check_galaxy_map()
	_check_production()
	_check_research()

	_test.assert_null(FOUniverse.get_system(-1), "No view for an invalid system ID")
	_test.assert_null(FOUniverse.get_fleet(-1), "No view for an invalid fleet ID")

	_pick_fleet(empire_id)
	_test.assert_ne(_fleet_id, -1, "Found an own fleet at a system with a known starlane")
	if _fleet_id == -1:
		return

	var fleet: FOFleet = FOUniverse.get_fleet(_fleet_id)
	var home_id: int = fleet.get_system_id()
	_test.assert_has(
		FOUniverse.get_system(home_id).get_fleet_ids(), _fleet_id, "System lists its fleet"
	)

	var orders_before: int = FOOrders.get_order_count()
	_test.assert_gt(FOOrders.issue_fleet_move(_fleet_id, _dest_id), -1, "Move order accepted")
	_test.assert_eq(FOOrders.get_order_count(), orders_before + 1, "Move order recorded")
	_test.assert_eq(fleet.get_final_destination_id(), _dest_id, "View reflects the move at once")

	_test.assert_gt(FOOrders.issue_fleet_move(_fleet_id, home_id), -1, "Stop order accepted")
	_test.assert_ne(fleet.get_final_destination_id(), _dest_id, "Stop order cancels the move")

	_test.assert_eq(FOOrders.issue_fleet_move(-1, _dest_id), -1, "Order for unknown fleet refused")
	_test.assert_false(FOOrders.rescind_order(-12345), "Rescinding an unknown order fails")

	_test.assert_gt(FOOrders.issue_fleet_move(_fleet_id, _dest_id), -1, "Move order re-issued")
	_test.assert_gt(fleet.get_eta(), 0, "Moving fleet has an ETA")


## Call after the first turn update arrived.
func after_turn() -> void:
	if _fleet_id == -1:
		return
	var fleet: FOFleet = FOUniverse.get_fleet(_fleet_id)
	_test.assert_not_null(fleet, "Fleet still known after the turn")
	if fleet:
		_test.assert_ne(fleet.get_position(), _start_position, "Fleet moved during the turn")
	var sitreps: Array = FOUniverse.get_sitreps()
	_test.assert_gt(sitreps.size(), 0, "Turn produced situation reports")
	for entry: Dictionary in sitreps:
		_test.assert_false(entry["text"].is_empty(), "Sitrep has text")
		var bbcode := FORichText.to_bbcode(entry["text"])
		_test.assert_false(bbcode.contains("<"), "Sitrep markup converts: %s" % entry["text"])


func _check_galaxy_map() -> void:
	var view: GalaxyMapView = preload("res://map/GalaxyMapView.tscn").instantiate()
	view.follow_game = false
	_test.add_child_autofree(view)
	await _test.wait_process_frames(2)
	view.refresh()
	_test.assert_eq(
		view.map.system_count(), FOUniverse.get_system_ids().size(), "Map shows known systems"
	)
	_test.assert_true(view.map.bounds.has_area(), "Map has galaxy bounds")
	_check_home_system_panel()
	await _check_fleet_order_from_shell()


# Select the home system and an own fleet in the shell, then right-click a
# neighbouring system: the order is issued and the route is drawn.
func _check_fleet_order_from_shell() -> void:
	var shell := GameShell.new()
	_test.add_child_autofree(shell)
	await _test.wait_process_frames(2)
	shell.map_view.refresh()
	var empire_id: int = FOUniverse.get_empire_id()
	var fleet: FOFleet = null
	for fleet_id in FOUniverse.get_fleet_ids():
		var candidate: FOFleet = FOUniverse.get_fleet(fleet_id)
		if candidate.get_owner_id() == empire_id and candidate.get_speed() > 0.0:
			fleet = candidate
			break
	_test.assert_not_null(fleet, "Own movable fleet")
	if fleet == null:
		return
	var home := fleet.get_system_id()
	var target: int = FOUniverse.get_system(home).get_starlanes()[0]
	shell.map_view.map.select_system(home)
	_test.assert_eq(shell.system_panel.system_id, home, "Panel follows map selection")
	shell.system_panel.select_fleet(fleet.get_id())
	shell.map_view.map.system_context_requested.emit(target)
	_test.assert_eq(fleet.get_final_destination_id(), target, "Right-click ordered the move")
	_test.assert_gt(shell.map_view.map.route_points().size(), 1, "Route drawn")
	_test.assert_eq(
		shell.top_bar._turn.text,
		_test.tr("MAP_BTN_TURN_UPDATE").replace("%1%", str(GlobalFreeOrionNode.get_current_turn())),
		"Top bar shows the turn"
	)
	_test.assert_false(shell.top_bar._empire.text.is_empty(), "Top bar shows the empire")


func _check_home_system_panel() -> void:
	var empire_id: int = FOUniverse.get_empire_id()
	var home_id := -1
	for planet_id in FOUniverse.get_planet_ids():
		var planet: FOPlanet = FOUniverse.get_planet(planet_id)
		if planet.get_owner_id() == empire_id:
			home_id = planet.get_system_id()
			break
	_test.assert_ne(home_id, -1, "Player owns a planet")
	var data := SystemPanel.from_universe(home_id)
	_test.assert_false(data.is_empty(), "Home system data")
	var own_planets: Array = data["planets"].filter(func(p): return p["own"])
	_test.assert_gt(own_planets.size(), 0, "Panel lists an own planet")
	if not own_planets.is_empty():
		_test.assert_gt(own_planets[0]["population"], 0.0, "Own planet has population")
		_test.assert_false(own_planets[0]["species"].is_empty(), "Own planet has species")
		_test.assert_false(own_planets[0]["owner_name"].is_empty(), "Owner empire has a name")


# Production bridge against the real empire: locations, catalog, enqueue,
# quantity, reorder and remove.
func _check_production() -> void:
	var locations := FOProduction.get_production_locations()
	_test.assert_gt(locations.size(), 0, "Empire can produce somewhere")
	if locations.is_empty():
		return
	var buildable := FOProduction.get_buildable(locations[0])
	var ships := buildable.filter(func(item): return item["build_type"] == "ship")
	_test.assert_gt(ships.size(), 0, "Ships can be built at the capital")
	_test.assert_gt(FOProduction.get_points()["available"], 0.0, "Industry available")
	if ships.is_empty():
		return
	var queue_before := FOProduction.get_queue().size()
	_test.assert_true(
		FOProduction.enqueue_ship(ships[0]["design_id"], locations[0], 1), "Enqueue ship"
	)
	_test.assert_true(
		FOProduction.enqueue_ship(ships[0]["design_id"], locations[0], 1), "Enqueue again"
	)
	var queue := FOProduction.get_queue()
	_test.assert_eq(queue.size(), queue_before + 2, "Two items queued")
	var last: int = queue.size() - 1
	_test.assert_true(FOProduction.set_quantity(last, 3), "Set quantity")
	_test.assert_eq(FOProduction.get_queue()[last]["remaining"], 3, "Quantity applied")
	_test.assert_true(FOProduction.move(last, last - 1), "Move up")
	_test.assert_eq(FOProduction.get_queue()[last - 1]["remaining"], 3, "Moved item is earlier")
	_test.assert_true(FOProduction.remove(last - 1), "Remove")
	_test.assert_eq(FOProduction.get_queue().size(), queue_before + 1, "One item left")
	_test.assert_false(FOProduction.enqueue_ship(-1, locations[0], 1), "Unknown design refused")
	var screen := ProductionScreen.new()
	_test.add_child_autofree(screen)
	screen.refresh()
	_test.assert_gt(screen._queue_list.get_child_count(), 0, "Screen lists the real queue")


# Research bridge: techs, enqueue with prerequisites, move and remove.
func _check_research() -> void:
	var techs := FOResearch.get_techs()
	_test.assert_gt(techs.size(), 50, "Tech list loaded")
	_test.assert_gt(FOResearch.get_categories().size(), 3, "Tech categories")
	_test.assert_gt(FOResearch.get_points()["available"], 0.0, "Research available")
	var partial := techs.filter(func(t): return t["status"] == "partial" and not t["in_queue"])
	_test.assert_gt(partial.size(), 0, "Some techs need prerequisites")
	if partial.is_empty():
		return
	var tech_name: String = partial[0]["name"]
	var before := FOResearch.get_queue().size()
	_test.assert_true(FOResearch.enqueue(tech_name), "Enqueue tech with prerequisites")
	var queue := FOResearch.get_queue()
	var names := queue.map(func(e): return e["name"])
	_test.assert_gt(queue.size(), before + 1, "Prerequisites queued too")
	_test.assert_eq(names.back(), tech_name, "Tech queued after its prerequisites")
	_test.assert_true(FOResearch.move(tech_name, 0), "Move to front")
	_test.assert_eq(FOResearch.get_queue()[0]["name"], tech_name)
	_test.assert_true(FOResearch.remove(tech_name), "Remove")
	_test.assert_false(
		FOResearch.get_queue().any(func(e): return e["name"] == tech_name), "Removed from queue"
	)
	_test.assert_false(FOResearch.enqueue("NO_SUCH_TECH"), "Unknown tech refused")
	var screen := ResearchScreen.new()
	_test.add_child_autofree(screen)
	screen.refresh()
	_test.assert_gt(screen._catalog.get_child_count(), 0, "Screen lists real techs")


func _check_snapshot() -> void:
	var snapshot: Dictionary = FOUniverse.get_map_snapshot()
	var system_ids: PackedInt32Array = snapshot["system_ids"]
	var count := system_ids.size()
	_test.assert_gt(count, 0, "Snapshot has known systems")
	_test.assert_eq(FOUniverse.get_system_ids().size(), count, "Snapshot matches system IDs")
	_test.assert_eq(snapshot["system_positions"].size(), count, "One position per system")
	_test.assert_eq(snapshot["system_star_types"].size(), count, "One star type per system")

	var lanes: PackedInt32Array = snapshot["lanes"]
	_test.assert_gt(lanes.size(), 0, "Snapshot has known starlanes")
	_test.assert_eq(lanes.size() % 2, 0, "Lanes are index pairs")
	var lanes_in_range := true
	for index in lanes:
		lanes_in_range = lanes_in_range and index >= 0 and index < count
	_test.assert_true(lanes_in_range, "Lane indices point into the system arrays")

	var fleet_ids: PackedInt32Array = snapshot["fleet_ids"]
	_test.assert_gt(fleet_ids.size(), 0, "Snapshot has known fleets")
	_test.assert_eq(snapshot["fleet_positions"].size(), fleet_ids.size(), "One position per fleet")
	_test.assert_eq(snapshot["fleet_owner_ids"].size(), fleet_ids.size(), "One owner per fleet")


func _pick_fleet(empire_id: int) -> void:
	for fleet_id in FOUniverse.get_fleet_ids():
		var fleet: FOFleet = FOUniverse.get_fleet(fleet_id)
		if fleet.get_owner_id() != empire_id or fleet.get_system_id() == -1:
			continue
		if fleet.get_speed() <= 0.0:
			continue
		var lanes: PackedInt32Array = FOUniverse.get_system(fleet.get_system_id()).get_starlanes()
		if lanes.is_empty():
			continue
		_fleet_id = fleet_id
		_dest_id = lanes[0]
		_start_position = fleet.get_position()
		return
