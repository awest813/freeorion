extends RefCounted
## In-memory stand-in for DiplomacySource (tests and screenshots).

var calls: Array = []
var empires: Array = [
	{
		"id": 1,
		"name": "Terran Imperium",
		"player": "Admiral",
		"color": Color("#1193ff"),
		"own": true,
		"eliminated": false,
		"status": "",
		"incoming": "",
		"outgoing": "",
		"actions": [],
	},
	{
		"id": 2,
		"name": "Congregation",
		"player": "AI_1",
		"color": Color("#00ff00"),
		"own": false,
		"eliminated": false,
		"status": "war",
		"incoming": "peace",
		"outgoing": "",
		"actions": ["accept_peace", "reject"],
	},
	{
		"id": 3,
		"name": "Sslith Hegemony",
		"player": "AI_2",
		"color": Color("#ffd23d"),
		"own": false,
		"eliminated": false,
		"status": "peace",
		"incoming": "",
		"outgoing": "allies",
		"actions": ["cancel", "declare_war"],
	},
	{
		"id": 4,
		"name": "Fallen Star",
		"player": "AI_3",
		"color": Color("#ff5a4f"),
		"own": false,
		"eliminated": true,
		"status": "war",
		"incoming": "",
		"outgoing": "",
		"actions": [],
	},
]
var accept := true


func get_empires() -> Array:
	return empires


func act(empire_id: int, action: String) -> bool:
	calls.push_back([empire_id, action])
	return accept
