class_name ObjectsSource
extends RefCounted
## Object rows via FOObjects; tests use a fake.

const OPTION_COLUMNS := "ui.objects.columns"


func list_objects(kind: String, own_only: bool, include_destroyed := false) -> Array:
	return FOObjects.list_objects(kind, own_only, include_destroyed)


## The foci planet \a planet_id can take.
func focus_options(planet_id: int) -> PackedStringArray:
	var focus: Dictionary = FOPlanetActions.get_actions(planet_id).get("focus", {})
	return focus.get("options", PackedStringArray())


func set_focus(planet_id: int, focus: String) -> bool:
	return FOPlanetActions.set_focus(planet_id, focus)


## What can be built at planet \a planet_id (ProductionSource.get_buildable()).
func buildable(planet_id: int) -> Array:
	return FOProduction.get_buildable(planet_id)


func enqueue(item: Dictionary, planet_id: int) -> bool:
	return ProductionSource.new().enqueue(item, planet_id)


func empire_id() -> int:
	return FOUniverse.get_empire_id()


## Column choices kept in option ui.objects.columns ("planets:type=1 ...").
func load_columns() -> String:
	var options := Engine.get_singleton("FOOptions")
	options.add_option(OPTION_COLUMNS, "OPTIONS_DB_UI_OBJECTS_COLUMNS", "")
	return str(options.get_value(OPTION_COLUMNS))


func save_columns(text: String) -> void:
	var options := Engine.get_singleton("FOOptions")
	options.set_value(OPTION_COLUMNS, text)
	options.commit()
