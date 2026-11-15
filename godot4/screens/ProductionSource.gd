class_name ProductionSource
extends RefCounted
## Data and orders for ProductionScreen. This one talks to the game through
## FOProduction/FOUniverse; tests substitute a fake with the same methods.


func get_queue() -> Array:
	return FOProduction.get_queue()


func get_points() -> Dictionary:
	return FOProduction.get_points()


func get_buildable(location_id: int) -> Array:
	return FOProduction.get_buildable(location_id)


## [{id, name}] of planets where the player can produce, capital first.
func get_locations() -> Array:
	var locations: Array = []
	for planet_id in FOProduction.get_production_locations():
		var planet: FOPlanet = FOUniverse.get_planet(planet_id)
		if planet:
			locations.push_back({"id": planet_id, "name": planet.get_name()})
	return locations


## [{id, name, system_id}] of the locations where \a item can be built now.
func get_item_locations(item: Dictionary) -> Array:
	var locations: Array = []
	for planet_id in FOProduction.get_item_locations(item):
		var planet: FOPlanet = FOUniverse.get_planet(planet_id)
		if planet:
			locations.push_back(
				{"id": planet_id, "name": planet.get_name(), "system_id": planet.get_system_id()}
			)
	return locations


## Add \a item at \a location_id: at the queue's end, or at \a position
## (0: the top).
func enqueue(item: Dictionary, location_id: int, position := -1) -> bool:
	if item.get("build_type") == "building":
		return FOProduction.enqueue_building(item["name"], location_id, position)
	if item.get("build_type") == "stockpile":
		return FOProduction.enqueue_stockpile_project(location_id, position)
	return FOProduction.enqueue_ship(item["design_id"], location_id, 1, position)


func remove(index: int) -> bool:
	return FOProduction.remove(index)


func move(index: int, new_index: int) -> bool:
	return FOProduction.move(index, new_index)


func set_quantity(index: int, quantity: int) -> bool:
	return FOProduction.set_quantity(index, quantity)


func set_paused(index: int, paused: bool) -> bool:
	return FOProduction.set_paused(index, paused)


func set_stockpile_allowed(index: int, allowed: bool) -> bool:
	return FOProduction.set_stockpile_allowed(index, allowed)


func set_blocksize(index: int, blocksize: int) -> bool:
	return FOProduction.set_blocksize(index, blocksize)


func duplicate_item(index: int) -> bool:
	return FOProduction.duplicate(index)


func split_incomplete(index: int) -> bool:
	return FOProduction.split_incomplete(index)


func set_rally_point(index: int, system_id: int) -> bool:
	return FOProduction.set_rally_point(index, system_id)


## Items removed this turn, which can still be restored.
func get_removed() -> Array:
	return FOProduction.get_removed()


func restore(index: int) -> bool:
	return FOProduction.restore(index)
