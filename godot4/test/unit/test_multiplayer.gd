extends GutTest
## Multiplayer: the lobby screen (galaxy, ready, chat) and the in-game
## parts (messages window, turn timeout, concede), on a fake LobbySource.

const FakeLobby := preload("res://test/unit/fake_lobby_source.gd")

var source: Variant


func before_each():
	source = FakeLobby.new()


func _lobby_screen() -> LobbyScreen:
	var screen := LobbyScreen.new()
	screen.source = source
	add_child_autofree(screen)
	screen.refresh()
	return screen


# Lobby screen ----------------------------------------------------------


func test_ready_button_starts_when_everyone_else_is_ready():
	var screen := _lobby_screen()
	assert_eq(screen.ready_text(), tr("START_GAME_BN"), "Bob is ready, the AI doesn't count")
	source.lobby_data["players"][1]["ready"] = false
	screen.refresh()
	assert_eq(screen.ready_text(), tr("READY_BN"))
	source.lobby_data["players"][0]["ready"] = true
	screen.refresh()
	assert_eq(screen.ready_text(), tr("NOT_READY_BN"))
	screen.ready_button.pressed.emit()
	assert_eq(source.ready_sent, [false])


func test_start_lock_disables_ready_and_says_why():
	source.lobby_data["start_locked"] = true
	source.lobby_data["start_lock_cause"] = "ERROR_NOT_ENOUGH_AI_PLAYERS"
	var screen := _lobby_screen()
	assert_true(screen.ready_button.disabled)
	assert_eq(screen.conditions_text(), tr("ERROR_NOT_ENOUGH_AI_PLAYERS"))


func test_galaxy_settings_shown_and_sent():
	var screen := _lobby_screen()
	assert_eq(screen.seed_edit.text, "abc")
	assert_eq(screen.stars.value, 150.0)
	var shape: OptionButton = screen._choices["shape"]
	assert_eq(shape.get_item_metadata(shape.selected), "SPIRAL_3")
	shape.select(0)
	shape.item_selected.emit(0)
	assert_eq(source.sent[-1], {"galaxy": {"shape": "SPIRAL_2"}})
	screen.stars.value = 300
	assert_eq(source.sent[-1], {"galaxy": {"size": 300}})


func test_only_galaxy_setup_edits_settings():
	source.roles = ["player"]
	source.my_id = 2
	var screen := _lobby_screen()
	assert_false(screen.seed_edit.editable)
	assert_true(screen._choices["age"].disabled)
	assert_true(screen.new_game_button.disabled)
	assert_true(screen.any_can_edit.disabled)
	assert_eq(screen._info.text, tr("MP_SETTINGS_LOCKED"))


func test_loading_a_save_in_the_lobby():
	source.lobby_data["new_game"] = false
	var screen := _lobby_screen()
	assert_false(screen._galaxy_grid.visible)
	assert_true(screen.save_picker.visible)
	assert_eq(screen.save_picker.item_count, 3)
	screen.save_picker.select(2)
	screen.save_picker.item_selected.emit(2)
	assert_eq(source.sent[-1], {"save_game": "auto/autosave.sav"})


func test_lobby_chat_shows_and_sends():
	var screen := _lobby_screen()
	screen.refresh_chat()
	var text := screen.chat.log_view.get_parsed_text()
	assert_string_contains(text, "Alice")
	assert_string_contains(text, "Hello [b]all[/b]", "chat text is not BBCode")
	screen.chat.input.text = "gl hf"
	screen.chat.input.text_submitted.emit("gl hf")
	assert_eq(source.chat_sent, [["gl hf", PackedInt32Array()]])
	assert_eq(screen.chat.input.text, "")


func test_chat_line_format():
	var line := ChatPanel.format_line({"player_name": "A[x]", "text": "[i]hi", "time": "09:15:00"})
	assert_string_contains(line, "09:15")
	assert_false(line.contains("09:15:00"))
	assert_string_contains(line, "A[lb]x]")
	assert_string_contains(line, "[lb]i]hi")


func test_server_notices_are_translated():
	assert_eq(
		ChatPanel.substitute("[[PLAYER_LEFT_GAME,Bob]]"),
		tr("PLAYER_LEFT_GAME").replace("%1%", "Bob")
	)
	assert_eq(ChatPanel.substitute("a [[NO_SUCH_KEY_X]] b"), "a NO_SUCH_KEY_X b")
	assert_eq(ChatPanel.substitute("plain [text]"), "plain [text]")


# In game ---------------------------------------------------------------


func test_messages_window_counts_unread_and_whispers():
	var window := ChatWindow.new()
	window.source = source
	add_child_autofree(window)
	watch_signals(window)
	window.refresh()
	assert_eq(window.unread, 2)
	window.open()
	assert_eq(window.unread, 0)
	# Everyone, then Bob; not yourself or the AI.
	assert_eq(window.recipient.item_count, 2)
	window.recipient.select(1)
	window.chat.input.text_submitted.emit("psst")
	assert_eq(source.chat_sent[-1], ["psst", PackedInt32Array([2])])
	window.close()
	source.chat_lines.push_back({"player_name": "Bob", "text": "?"})
	window.refresh()
	assert_eq(window.unread, 1)
	assert_signal_emitted_with_parameters(window, "unread_changed", [1])


func test_turn_timeout_counts_down_in_top_bar():
	var bar := TopBar.new()
	bar.follow_game = false
	add_child_autofree(bar)
	bar.set_state("Alice Empire", Color.BLUE, 5, false)
	assert_eq(bar.turn_seconds_left(), -1)
	bar.set_turn_timeout(90)
	assert_between(bar.turn_seconds_left(), 89, 90)
	assert_string_contains(bar._turn.text, "1:30")
	bar.set_turn_timeout(0)
	assert_eq(bar.turn_seconds_left(), -1)
	assert_eq(TopBar.timeout_text(65), "1:05")
	assert_eq(TopBar.timeout_text(3725), "1:02:05")
	bar.set_unread_messages(3)
	assert_eq(bar._messages.text, "3")


func test_concede_replaces_load_in_multiplayer():
	var menu := GameMenu.new()
	add_child_autofree(menu)
	menu.open("", true, true, true)
	assert_false(menu._load.visible)
	assert_true(menu._concede.visible)
	watch_signals(menu)
	menu._concede.pressed.emit()
	assert_eq(menu._warning.text, tr("GAME_MENU_REALLY_CONCEDE"))
	menu._confirm_button.pressed.emit()
	assert_signal_emitted(menu, "concede_requested")
	assert_signal_not_emitted(menu, "leave_requested")
	menu.open("", true, true, false)
	assert_true(menu._concede.disabled)
	menu.open("")
	assert_true(menu._load.visible)
	assert_false(menu._concede.visible)


func test_messages_log_game_events_and_commands():
	var window := ChatWindow.new()
	window.source = source
	add_child_autofree(window)
	window.add_event("Begin Turn 5")
	var lines := window.merged(source.chat_lines)
	assert_eq(lines.size(), source.chat_lines.size() + 1)
	assert_true(lines[-1].get("event", false), "Events come after the chat so far")
	assert_string_contains(ChatPanel.format_line(lines[-1]), "[i]Begin Turn 5")
	watch_signals(window)
	window.chat.input.text_submitted.emit("/pedia Robotic Hull")
	assert_signal_emitted_with_parameters(window, "pedia_requested", ["Robotic Hull"])
	assert_eq(source.chat_sent, [], "Commands aren't sent")
	window.chat.input.text_submitted.emit("/pm Bob hello there")
	assert_eq(source.chat_sent[-1], ["hello there", PackedInt32Array([2])])
	window.chat.input.text_submitted.emit("/pm Nobody hi")
	assert_eq(window.events[-1]["text"], tr("MESSAGES_INVALID"))
	window.chat.input.text_submitted.emit("/help")
	assert_eq(window.events[-1]["text"], tr("MESSAGES_HELP_COMMAND"))


func test_diplomacy_changes_are_logged():
	var known := {}
	var empires := [
		{"id": 1, "name": "Us", "own": true, "color": Color.BLUE},
		{"id": 2, "name": "Them", "status": "war", "color": Color.RED},
	]
	assert_eq(MessageLog.diplomacy_changes(known, empires).size(), 0, "First look: no change")
	empires[1]["status"] = "peace"
	var messages := MessageLog.diplomacy_changes(known, empires)
	assert_eq(messages.size(), 1)
	assert_string_contains(messages[0], "Them")
	assert_string_contains(messages[0], "<rgba 0 0 255 255>Us</rgba>")
	assert_eq(MessageLog.diplomacy_changes(known, empires).size(), 0, "Only changes")
