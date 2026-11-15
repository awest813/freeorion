class_name ResearchSource
extends RefCounted
## Data and orders for ResearchScreen via FOResearch; tests use a fake with
## the same methods.


func get_queue() -> Array:
	return FOResearch.get_queue()


func get_points() -> Dictionary:
	return FOResearch.get_points()


func get_techs() -> Array:
	return FOResearch.get_techs()


func get_categories() -> PackedStringArray:
	return FOResearch.get_categories()


func enqueue(tech_name: String) -> bool:
	return FOResearch.enqueue(tech_name)


func remove(tech_name: String) -> bool:
	return FOResearch.remove(tech_name)


func move(tech_name: String, position: int) -> bool:
	return FOResearch.move(tech_name, position)
