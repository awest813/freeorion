class_name DesignerSource
extends RefCounted
## Hulls, parts, design evaluation and creation via FODesigner; tests use a
## fake with the same methods.


func get_hulls(include_unavailable := false) -> Array:
	return FODesigner.get_hulls(include_unavailable)


func get_parts(include_unavailable := false) -> Array:
	return FODesigner.get_parts(include_unavailable)


func evaluate(hull: String, parts: PackedStringArray) -> Dictionary:
	return FODesigner.evaluate(hull, parts)


func create(design_name: String, hull: String, parts: PackedStringArray, description := "") -> int:
	return FODesigner.create(design_name, hull, parts, description)


func update_design(
	design_id: int, design_name: String, hull: String, parts: PackedStringArray, description: String
) -> int:
	return FODesigner.update_design(design_id, design_name, hull, parts, description)


func update_saved(
	uuid: String, design_name: String, hull: String, parts: PackedStringArray, description: String
) -> bool:
	return FODesigner.update_saved(uuid, design_name, hull, parts, description)


func set_part_obsolete(part_name: String, obsolete: bool) -> bool:
	return FODesigner.set_part_obsolete(part_name, obsolete)


func set_hull_obsolete(hull_name: String, obsolete: bool) -> bool:
	return FODesigner.set_hull_obsolete(hull_name, obsolete)


func get_designs(kind: String) -> Array:
	return FODesigner.get_designs(kind)


func set_obsolete(design_id: int, obsolete: bool) -> bool:
	return FODesigner.set_obsolete(design_id, obsolete)


func move_design(design_id: int, before_id: int) -> bool:
	return FODesigner.move_design(design_id, before_id)


func delete_design(design_id: int) -> bool:
	return FODesigner.delete_design(design_id)


func add_premade(design_id: int) -> int:
	return FODesigner.add_premade(design_id)


func rename_design(design_id: int, new_name: String) -> bool:
	return FODesigner.rename_design(design_id, new_name)


## Keep own design \a design_id between games (<user data>/shipdesigns).
func save_design(design_id: int) -> bool:
	return FODesigner.save_design(design_id)


func add_saved(uuid: String) -> int:
	return FODesigner.add_saved(uuid)


func delete_saved(uuid: String) -> bool:
	return FODesigner.delete_saved(uuid)


func add_all_saved() -> int:
	return FODesigner.add_all_saved()
