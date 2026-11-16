class_name SavesSource
extends RefCounted
## Save listing and save/load requests via FOSaves; tests use a fake.

## Seconds between asks for the server's saves.
const SERVER_ASK_SECONDS := 2.0

var _asked_at := -1000.0


## The saves to show: in a multiplayer game, the server's (where its saves
## go; asked for again at most every SERVER_ASK_SECONDS, the list arriving
## later), else this computer's.
func list_saves() -> Array:
	if not in_multiplayer_game():
		return FOSaves.list_saves()
	var now := Time.get_ticks_msec() / 1000.0
	if now - _asked_at > SERVER_ASK_SECONDS:
		_asked_at = now
		FOMultiplayer.request_server_saves("")
	return FOMultiplayer.get_server_saves()


func in_multiplayer_game() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	var node: Node = tree.root.get_node_or_null("GlobalFreeOrionNode") if tree else null
	return (
		node != null
		and node.get_current_turn() >= 1
		and not node.get_single_player_game()
		and FOMultiplayer.is_connected_to_server()
	)


func save_game(save_name: String) -> String:
	return FOSaves.save_game(save_name)


func load_game(path: String) -> bool:
	return FOSaves.load_game(path)


func delete_save(path: String) -> bool:
	return FOSaves.delete_save(path)


## The newest of \a saves (list_saves()'s) made by \a empire_name, or {}.
static func newest_for(saves: Array, empire_name: String) -> Dictionary:
	var newest := {}
	for save: Dictionary in saves:
		if save.get("empire", "") != empire_name:
			continue
		if newest.is_empty() or str(save.get("time", "")) > str(newest.get("time", "")):
			newest = save
	return newest
