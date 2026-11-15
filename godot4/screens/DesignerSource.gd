class_name DesignerSource
extends RefCounted
## Hulls, parts, design evaluation and creation via FODesigner; tests use a
## fake with the same methods.


func get_hulls() -> Array:
	return FODesigner.get_hulls()


func get_parts() -> Array:
	return FODesigner.get_parts()


func evaluate(hull: String, parts: PackedStringArray) -> Dictionary:
	return FODesigner.evaluate(hull, parts)


func create(design_name: String, hull: String, parts: PackedStringArray) -> int:
	return FODesigner.create(design_name, hull, parts)


func get_designs() -> Array:
	return FODesigner.get_designs()
