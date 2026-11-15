class_name LobbySource
extends RefCounted
## Multiplayer session for ConnectScreen, LobbyScreen and the in-game chat
## via FOMultiplayer: hosting or joining a server, the lobby the server
## sends, ready, chat and passwords. Tests use a fake with the same methods.


## Start a server and host a game on it; "" or a string key saying why not.
func host_game(player_name: String) -> String:
	return FOMultiplayer.host_game(player_name)


## Join the server at \a address as \a client_type ("player", "observer",
## "moderator"); "" or a string key saying why not.
func join_game(address: String, player_name: String, client_type: String) -> String:
	return FOMultiplayer.join_game(address, player_name, client_type)


func leave() -> void:
	FOMultiplayer.leave()


func player_id() -> int:
	return FOMultiplayer.get_player_id()


func is_host() -> bool:
	return FOMultiplayer.is_host()


## Whether the server gave this player \a role ("host", "galaxy_setup",
## "player", "observer", "moderator").
func has_role(role: String) -> bool:
	return FOMultiplayer.has_role(role)


## The lobby as the server last sent it (FOMultiplayer.get_lobby()).
func lobby() -> Dictionary:
	return FOMultiplayer.get_lobby()


## Send the lobby with \a changes (keys of lobby(); players replace the list).
func send_lobby(changes: Dictionary) -> bool:
	return FOMultiplayer.send_lobby(changes)


func set_ready(ready: bool) -> bool:
	return FOMultiplayer.set_ready(ready)


## Say \a text to everyone, or only to players \a recipients.
func send_chat(text: String, recipients := PackedInt32Array()) -> bool:
	return FOMultiplayer.send_chat(text, recipients)


## [{player_name, text, color, time}], oldest first.
func chat() -> Array:
	return FOMultiplayer.get_chat()


func send_password(password: String) -> bool:
	return FOMultiplayer.send_password(password)


## The game's players: [{player_id, name, empire_id, empire_name, color,
## client_type, host, ready, eliminated}].
func players() -> Array:
	return FOMultiplayer.get_players()


func playable_species() -> Array:
	return FOUniverse.get_playable_species()


func empire_colors() -> PackedColorArray:
	return FOUniverse.get_empire_colors()


## Saves a hosted game can load (SavesSource.list_saves()), with "file"
## relative to the save directory as the server wants it.
func list_saves() -> Array:
	var dir := FOSaves.get_save_dir()
	var saves := []
	for save: Dictionary in FOSaves.list_saves():
		var entry := save.duplicate()
		var path: String = save.get("path", "")
		entry["file"] = path.trim_prefix(dir).trim_prefix("/") if path.begins_with(dir) else path
		saves.push_back(entry)
	return saves


## Servers answering on the local network (takes a couple of seconds).
func discover_lan_servers() -> PackedStringArray:
	return FOMultiplayer.discover_lan_servers()
