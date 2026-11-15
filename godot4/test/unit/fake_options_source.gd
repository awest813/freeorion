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
	"audio.music.enabled": {"value": true, "default": true, "description": "OPTIONS_DB_MUSIC_ON"},
	"save.format.binary":
	{"value": false, "default": true, "description": "OPTIONS_DB_BINARY_SERIALIZATION"},
}
var committed := false
var rules: Array = [
	{
		"name": "RULE_NUM_COMBAT_ROUNDS",
		"category": "",
		"type": "int",
		"value": 4,
		"default": 4,
		"description": "RULE_NUM_COMBAT_ROUNDS_DESC",
		"min": 2,
		"max": 20,
	},
	{
		"name": "RULE_AGGRESSIVE_SHIPS_COMBAT_VISIBLE",
		"category": "",
		"type": "toggle",
		"value": false,
		"default": false,
		"description": "",
	},
	{
		"name": "RULE_SHIP_SPEED_FACTOR",
		"category": "BALANCE",
		"type": "double",
		"value": 1.0,
		"default": 1.0,
		"description": "",
		"min": 0.1,
		"max": 10.0,
	},
	{
		"name": "RULE_TEST_STRING",
		"category": "TEST",
		"type": "string",
		"value": "PLAYER",
		"default": "PLAYER",
		"description": "",
		"choices": ["MODERATOR", "OBSERVER", "PLAYER", "AI_PLAYER"],
	},
]
var rules_set := {}
var refuse_rules := false


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


func playable_species() -> Array:
	return [
		{"name": "SP_HUMAN", "icon": "icons/species/human.png"},
		{"name": "SP_EGASSEM", "icon": "icons/species/egassem.png"},
	]


func empire_colors() -> PackedColorArray:
	return PackedColorArray([Color("#ff0000"), Color("#00ff00"), Color("#3d9bff")])


func game_rules() -> Array:
	return rules


func set_game_rules(values: Dictionary) -> bool:
	if refuse_rules:
		return false
	rules_set = values
	return true
