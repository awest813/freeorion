extends RefCounted
## In-memory stand-in for OptionsSource (tests and screenshots).

var options := {
	"ui.scale": {"value": "auto", "default": "auto", "description": "OPTIONS_DB_UI_SCALE"},
	"ui.theme": {"value": "default", "default": "default", "description": "OPTIONS_DB_UI_THEME"},
	"ui.reduce-motion":
	{"value": false, "default": false, "description": "OPTIONS_DB_UI_REDUCE_MOTION"},
	"setup.star.count":
	{
		"value": 150,
		"default": 150,
		"description": "OPTIONS_DB_GAMESETUP_STARS",
		"min": 10,
		"max": 5000,
	},
	"audio.music.enabled":
	{"value": true, "default": true, "description": "OPTIONS_DB_MUSIC_ON"},
	"save.format.binary":
	{"value": false, "default": true, "description": "OPTIONS_DB_BINARY_SERIALIZATION"},
}
var committed := false


func exists(option: String) -> bool:
	return options.has(option)


func get_value(option: String) -> Variant:
	return options[option]["value"]


func set_value(option: String, value: Variant) -> bool:
	var entry: Dictionary = options.get(option, {})
	if entry.is_empty():
		return false
	if entry.has("min") and (value < entry["min"] or value > entry["max"]):
		return false
	entry["value"] = value
	return true


func get_default(option: String) -> Variant:
	return options[option]["default"]


func is_default(option: String) -> bool:
	return options[option]["value"] == options[option]["default"]


func reset_to_default(option: String) -> bool:
	options[option]["value"] = options[option]["default"]
	return true


func get_description(option: String) -> String:
	return options[option]["description"]


func find(_prefix: String) -> PackedStringArray:
	return PackedStringArray(options.keys())


func commit() -> bool:
	committed = true
	return true
