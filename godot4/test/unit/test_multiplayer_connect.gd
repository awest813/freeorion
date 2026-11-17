extends GutTest
## Multiplayer: the connect screen and the lobby's player list, on a fake
## LobbySource.

const FakeLobby := preload("res://test/unit/fake_lobby_source.gd")
const FakeOptions := preload("res://test/unit/fake_options_source.gd")

var source: Variant


func before_each():
	source = FakeLobby.new()


func _connect_screen() -> ConnectScreen:
	var screen := ConnectScreen.new()
	var options = FakeOptions.new()
	options.options["setup.multiplayer.player.name"] = {"value": "Alice", "default": ""}
	options.options["setup.multiplayer.host.address"] = {"value": "localhost", "default": ""}
	screen.options = options
	screen.lobby_source = source
	add_child_autofree(screen)
	screen.refresh()
	return screen


# Connect screen --------------------------------------------------------


func test_connect_fills_remembered_name_and_address():
	var screen := _connect_screen()
	assert_eq(screen.name_edit.text, "Alice")
	assert_eq(screen.address_edit.text, "localhost")
	assert_false(screen.host_button.disabled)


func test_connect_needs_a_name():
	var screen := _connect_screen()
	screen.name_edit.text = "  "
	screen.name_edit.text_changed.emit("  ")
	assert_true(screen.host_button.disabled)
	assert_true(screen.join_button.disabled)


func test_join_as_observer_emits_and_remembers():
	var screen := _connect_screen()
	watch_signals(screen)
	screen.address_edit.text = "10.0.0.5"
	screen.join_as.select(1)
	screen.join_button.pressed.emit()
	assert_signal_emitted_with_parameters(
		screen, "join_requested", ["10.0.0.5", "Alice", "observer"]
	)
	assert_eq(screen.options.get_value("setup.multiplayer.host.address"), "10.0.0.5")
	assert_string_contains(screen.status_text(), "10.0.0.5")


func test_host_emits_name():
	var screen := _connect_screen()
	watch_signals(screen)
	screen.host_button.pressed.emit()
	assert_signal_emitted_with_parameters(screen, "host_requested", ["Alice"])


func test_lan_servers_listed_and_picked():
	var screen := _connect_screen()
	assert_eq(screen._lan_empty.text, tr("MP_LAN_LOOK"), "the empty list says how to look")
	screen.find_lan_servers()
	assert_true(screen.join_button.disabled, "No joining while searching")
	assert_eq(screen._lan_empty.text, tr("MP_SEARCHING_LAN"))
	await wait_for_signal(screen.lan_search_done, 5)
	assert_eq(screen.lan_list.item_count, 1)
	assert_false(screen._lan_empty.visible, "a found game hides the note")
	screen.lan_list.select(0)
	screen.lan_list.item_selected.emit(0)
	assert_eq(screen.address_edit.text, "192.168.1.20")
	source.lan_servers = PackedStringArray()
	screen.find_lan_servers()
	await wait_for_signal(screen.lan_search_done, 5)
	assert_eq(screen.status_text(), tr("MP_NO_LAN_SERVERS"))
	assert_true(screen._lan_empty.visible)
	assert_eq(screen._lan_empty.text, tr("MP_NO_LAN_SERVERS"))


# Players ---------------------------------------------------------------


func test_host_edits_every_row_others_only_their_own():
	var list := LobbyPlayerList.new()
	add_child_autofree(list)
	var players: Array = source.lobby_data["players"]
	list.show_lobby(source.lobby_data, 1, true, true)
	assert_true(list.can_edit(players[1]))
	list.show_lobby(source.lobby_data, 2, false, false)
	assert_false(list.can_edit(players[0]))
	assert_true(list.can_edit(players[1]))
	assert_false(list.can_edit(players[2]), "AI rows need galaxy setup")
	list.show_lobby(source.lobby_data, 2, false, true)
	assert_true(list.can_edit(players[2]))


func test_add_ai_takes_a_free_colour():
	var list := LobbyPlayerList.new()
	list.colors = source.empire_colors()
	list.species = source.playable_species()
	add_child_autofree(list)
	list.show_lobby(source.lobby_data, 1, true, true)
	watch_signals(list)
	list.add_ai_player()
	var players: Array = get_signal_parameters(list, "players_edited")[0]
	assert_eq(players.size(), 4)
	assert_eq(players[3]["client_type"], "ai")
	assert_eq(players[3]["player_id"], -1)
	assert_eq(players[3]["color"], Color("#f2b84b"))


func test_dropping_and_retyping_players():
	var list := LobbyPlayerList.new()
	add_child_autofree(list)
	list.show_lobby(source.lobby_data, 1, true, true)
	watch_signals(list)
	list._drop(3)
	var players: Array = get_signal_parameters(list, "players_edited")[0]
	assert_eq(players.size(), 2)
	list._edit(2, {"client_type": "observer"})
	players = get_signal_parameters(list, "players_edited")[0]
	assert_eq(players[1]["client_type"], "observer")
	assert_eq(
		source.lobby_data["players"][1]["client_type"], "player", "the lobby itself is unchanged"
	)


func test_start_needs_unique_names_and_colours():
	assert_true(LobbyPlayerList.player_data_acceptable(source.lobby_data))
	var lobby: Dictionary = source.lobby_data.duplicate(true)
	lobby["players"][1]["color"] = lobby["players"][0]["color"]
	assert_false(LobbyPlayerList.player_data_acceptable(lobby))
	lobby = source.lobby_data.duplicate(true)
	lobby["players"][2]["empire_name"] = ""
	assert_false(LobbyPlayerList.player_data_acceptable(lobby))
	# Observers don't need an empire.
	lobby = source.lobby_data.duplicate(true)
	lobby["players"][1]["client_type"] = "observer"
	lobby["players"][1]["empire_name"] = ""
	assert_true(LobbyPlayerList.player_data_acceptable(lobby))


func test_loaded_game_lists_free_empires():
	var lobby: Dictionary = source.lobby_data.duplicate(true)
	lobby["new_game"] = false
	lobby["players"] = [lobby["players"][0]]
	lobby["players"][0]["save_empire_id"] = 7
	lobby["save_empires"] = [
		{"empire_id": 7, "empire_name": "Old Alice", "player_name": "Alice", "color": Color.BLUE},
		{"empire_id": 8, "empire_name": "Old Bob", "player_name": "Bob", "color": Color.RED},
	]
	var free := LobbyPlayerList.unassigned_empires(lobby)
	assert_eq(free.size(), 1)
	assert_eq(free[0]["empire_id"], 8)
	var list := LobbyPlayerList.new()
	add_child_autofree(list)
	list.show_lobby(lobby, 1, true, true)
	assert_eq(list.row_count(), 2, "Alice and the free empire")
	watch_signals(list)
	list._add_ai_for(free[0])
	var players: Array = get_signal_parameters(list, "players_edited")[0]
	assert_eq(players[1]["save_empire_id"], 8)
	assert_eq(players[1]["empire_name"], "Old Bob")


func test_quick_edits_build_on_each_other_until_the_server_answers():
	var list := LobbyPlayerList.new()
	list.colors = source.empire_colors()
	list.species = source.playable_species()
	add_child_autofree(list)
	list.show_lobby(source.lobby_data, 1, true, true)
	watch_signals(list)
	list.add_ai_player()
	list.add_ai_player()
	var players: Array = get_signal_parameters(list, "players_edited", 1)[0]
	assert_eq(players.size(), 5, "Both new AIs, not just the second")
	assert_ne(players[3]["color"], players[4]["color"], "Each its own free colour")
	list.show_lobby(source.lobby_data, 1, true, true)
	list.add_ai_player()
	players = get_signal_parameters(list, "players_edited", 2)[0]
	assert_eq(players.size(), 4, "Once the server answers, its lobby counts")


func test_start_conditions_name_the_problem():
	assert_eq(LobbyPlayerList.data_problem(source.lobby_data), "")
	var lobby: Dictionary = source.lobby_data.duplicate(true)
	lobby["players"][1]["color"] = lobby["players"][0]["color"]
	assert_eq(
		LobbyPlayerList.data_problem(lobby),
		tr("MP_EMPIRE_COLOR_TWICE").replace("%1%", "Alice Empire").replace("%2%", "Bob Empire")
	)
	lobby = source.lobby_data.duplicate(true)
	lobby["players"][2]["empire_name"] = "Alice Empire"
	assert_eq(
		LobbyPlayerList.data_problem(lobby),
		tr("MP_EMPIRE_NAME_TWICE").replace("%1%", "Alice Empire")
	)
	lobby = source.lobby_data.duplicate(true)
	lobby["players"][1]["empire_name"] = " "
	assert_eq(LobbyPlayerList.data_problem(lobby), tr("MP_EMPIRE_UNNAMED").replace("%1%", "Bob"))


func test_lobby_fits_the_smallest_window():
	var screen := LobbyScreen.new()
	screen.source = source
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)
	assert_lte(screen.get_combined_minimum_size().x, float(FOWindow.MIN_SIZE.x))
	source.lobby_data["new_game"] = false
	source.lobby_data["save_game"] = "auto/FreeOrion_Human_Player_Aristocracy_0002_20261115_234335.mps"
	screen.refresh()
	await wait_process_frames(1)
	assert_lte(
		screen.get_combined_minimum_size().x,
		float(FOWindow.MIN_SIZE.x),
		"A long save name is cut short"
	)
