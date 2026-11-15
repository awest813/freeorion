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


func enqueue(item: Dictionary, location_id: int) -> bool:
	if item.get("build_type") == "building":
		return FOProduction.enqueue_building(item["name"], location_id)
	if item.get("build_type") == "stockpile":
		return FOProduction.enqueue_stockpile_project(location_id)
	return FOProduction.enqueue_ship(item["design_id"], location_id, 1)


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
