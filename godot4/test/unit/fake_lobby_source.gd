extends RefCounted
## In-memory stand-in for LobbySource (tests and screenshots): a lobby with
## the host, a second human and an AI, and what was sent to the server.

var my_id := 1
var roles := ["host", "galaxy_setup", "player"]
var host_error := ""
var join_error := ""
var hosted := []
var joined := []
var left := 0
var sent: Array = []
var ready_sent: Array = []
var chat_sent: Array = []
var passwords: Array = []
var lan_servers := PackedStringArray(["192.168.1.20"])
var chat_lines: Array = [
	{
		"player_name": "Alice",
		"text": "Hello [b]all[/b]",
		"color": Color("#58a8ff"),
		"time": "12:03:45"
	},
	{
		"player_name": "Bob",
		"text": "Ready when you are",
		"color": Color("#f07171"),
		"time": "12:04:10"
	},
]
var lobby_data := {
	"new_game": true,
	"any_can_edit": false,
	"start_locked": false,
	"start_lock_cause": "",
	"save_game": "",
	"in_game": false,
	"galaxy":
	{
		"seed": "abc",
		"size": 150,
		"shape": "SPIRAL_3",
		"age": "GALAXY_SETUP_MEDIUM",
		"starlane_freq": "GALAXY_SETUP_MEDIUM",
		"planet_density": "GALAXY_SETUP_MEDIUM",
		"specials_freq": "GALAXY_SETUP_MEDIUM",
		"monster_freq": "MONSTER_SETUP_LOW",
		"native_freq": "GALAXY_SETUP_MEDIUM",
		"ai_aggression": "TYPICAL",
	},
	"players":
	[
		{
			"player_id": 1,
			"player_name": "Alice",
			"empire_name": "Alice Empire",
			"species": "SP_HUMAN",
			"color": Color("#58a8ff"),
			"client_type": "player",
			"ready": false,
			"team": -1,
			"save_empire_id": -1,
		},
		{
			"player_id": 2,
			"player_name": "Bob",
			"empire_name": "Bob Empire",
			"species": "SP_LAENFA",
			"color": Color("#f07171"),
			"client_type": "player",
			"ready": true,
			"team": -1,
			"save_empire_id": -1,
		},
		{
			"player_id": 3,
			"player_name": "AI_1",
			"empire_name": "Machine Hegemony",
			"species": "SP_HUMAN",
			"color": Color("#4cc38a"),
			"client_type": "ai",
			"ready": false,
			"team": -1,
			"save_empire_id": -1,
		},
	],
	"save_empires": [],
}
var game_players: Array = [
	{"player_id": 1, "name": "Alice", "client_type": "player", "empire_id": 1},
	{"player_id": 2, "name": "Bob", "client_type": "player", "empire_id": 2},
	{"player_id": 3, "name": "AI_1", "client_type": "ai", "empire_id": 3},
]


func host_game(player_name: String) -> String:
	hosted.push_back(player_name)
	return host_error


func join_game(address: String, player_name: String, client_type: String) -> String:
	joined.push_back([address, player_name, client_type])
	return join_error


func leave() -> void:
	left += 1


func player_id() -> int:
	return my_id


func is_host() -> bool:
	return "host" in roles


func has_role(role: String) -> bool:
	return role in roles


func lobby() -> Dictionary:
	return lobby_data


func send_lobby(changes: Dictionary) -> bool:
	sent.push_back(changes)
	return true


func set_ready(ready: bool) -> bool:
	ready_sent.push_back(ready)
	return true


func send_chat(text: String, recipients := PackedInt32Array()) -> bool:
	chat_sent.push_back([text, recipients])
	return true


func chat() -> Array:
	return chat_lines


func send_password(password: String) -> bool:
	passwords.push_back(password)
	return true


func players() -> Array:
	return game_players


func playable_species() -> Array:
	return [{"name": "SP_HUMAN"}, {"name": "SP_LAENFA"}]


func empire_colors() -> PackedColorArray:
	return PackedColorArray(
		[Color("#58a8ff"), Color("#f07171"), Color("#4cc38a"), Color("#f2b84b")]
	)


func list_saves() -> Array:
	return [{"file": "game1.mps", "turn": 12}, {"file": "auto/autosave.mps", "turn": 30}]


func request_saves() -> bool:
	sent.push_back({"request_saves": true})
	return true


func discover_lan_servers() -> PackedStringArray:
	return lan_servers
