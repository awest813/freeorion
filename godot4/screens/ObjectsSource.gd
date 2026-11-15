class_name ObjectsSource
extends RefCounted
## Object rows via FOObjects; tests use a fake.

const OPTION_COLUMNS := "ui.objects.columns"


func list_objects(kind: String, own_only: bool) -> Array:
	return FOObjects.list_objects(kind, own_only)


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
