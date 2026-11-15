extends RefCounted
## In-memory stand-in for SavesSource (tests and screenshots).

var saves: Array = [
	{
		"path": "/saves/Terran_Imperium_turn_42.sav",
		"file": "Terran_Imperium_turn_42.sav",
		"player": "Admiral",
		"empire": "Terran Imperium",
		"color": Color("#3d9bff"),
		"turn": 42,
		"time": "2026-11-15T10:42:07Z",
		"systems": 150,
		"shape": "Spiral, 3 arms",
		"empires": 5,
		"humans": 1,
		"seed": "zzX9",
		"age": "Mature",
	},
	{
		"path": "/saves/auto/FreeOrion_Admiral_Terran_Imperium_0040.sav",
		"file": "FreeOrion_Admiral_Terran_Imperium_0040.sav",
		"auto": true,
		"player": "Admiral",
		"empire": "Terran Imperium",
		"color": Color("#3d9bff"),
		"turn": 40,
		"time": "2026-11-14T21:03:55Z",
	},
]
var calls: Array = []


func list_saves() -> Array:
	return saves


func save_game(save_name: String) -> String:
	calls.push_back(["save", save_name])
	return "/saves/%s.sav" % save_name


func load_game(path: String) -> bool:
	calls.push_back(["load", path])
	return true


func delete_save(path: String) -> bool:
	calls.push_back(["delete", path])
	saves = saves.filter(func(s): return s["path"] != path)
	return true
