extends GutTest
## SaveLoadScreen with an in-memory source.

const FakeSource := preload("res://test/unit/fake_saves_source.gd")

var screen: SaveLoadScreen
var fake: RefCounted


func _make(mode: String) -> void:
	screen = SaveLoadScreen.new()
	fake = FakeSource.new()
	screen.source = fake
	screen.mode = mode
	screen.suggested_name = "Terran_Imperium_turn_43"
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)


func test_load_mode_lists_and_loads():
	await _make("load")
	assert_eq(screen._list.get_child_count(), 2)
	assert_false(screen._name.visible)
	assert_true(screen._action.disabled, "Pick a save first")
	screen._list.get_child(0).pressed.emit()
	assert_false(screen._action.disabled)
	watch_signals(screen)
	screen._action.pressed.emit()
	assert_eq(fake.calls, [["load", "/saves/Terran_Imperium_turn_42.sav"]])
	assert_signal_emitted_with_parameters(
		screen, "load_started", ["/saves/Terran_Imperium_turn_42.sav"]
	)


func test_save_mode_suggests_and_overwrites():
	await _make("save")
	assert_true(screen._name.visible)
	assert_eq(screen._name.text, "Terran_Imperium_turn_43")
	assert_eq(screen._list.get_child_count(), 1, "Autosaves aren't offered for overwriting")
	screen._list.get_child(0).pressed.emit()
	assert_eq(screen._name.text, "Terran_Imperium_turn_42", "Picking a save overwrites it")
	assert_eq(screen._status.text, tr("SAVES_OVERWRITE"))
	screen._action.pressed.emit()
	assert_eq(fake.calls, [], "Replacing a save asks first")
	_dialog().choose(0)
	assert_eq(fake.calls, [["save", "Terran_Imperium_turn_42"]])
	assert_eq(screen._status.text, tr("SAVES_SAVING"))
	screen.on_save_completed("/saves/Terran_Imperium_turn_42.sav")
	assert_eq(screen._status.text, tr("SAVES_SAVED").replace("%1%", "Terran_Imperium_turn_42.sav"))


func test_autosaves_are_marked_in_load_mode():
	await _make("load")
	assert_eq(screen._list.get_child_count(), 2)
	var labels: Array = screen._list.get_child(1).find_children("*", "Label", true, false)
	assert_true(labels.any(func(l): return l.text.begins_with(tr("SAVES_AUTOSAVE"))))


func test_empty_name_cannot_be_saved():
	await _make("save")
	screen._name.text = "  "
	screen._name.text_changed.emit("  ")
	assert_true(screen._action.disabled)


func test_no_saves():
	screen = SaveLoadScreen.new()
	fake = FakeSource.new()
	fake.saves = []
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)
	var empty: Label = screen._list.get_child(0).find_children("*", "Label", true, false)[0]
	assert_eq(empty.text, tr("SAVES_EMPTY"))


func test_format_time():
	assert_eq(SaveLoadScreen.format_time("2026-11-15T10:42:07Z", "2026-11-20"), "2026-11-15 10:42")
	assert_eq(
		SaveLoadScreen.format_time("2026-11-15T10:42:07", "2026-11-15"),
		tr("SAVES_TODAY").replace("%1%", "10:42")
	)
	assert_eq(
		SaveLoadScreen.format_time("2026-02-28T23:05:00", "2026-03-01"),
		tr("SAVES_YESTERDAY").replace("%1%", "23:05"),
		"Across a month's end"
	)
	assert_eq(SaveLoadScreen.format_time("?"), "?")


func test_delete_asks_then_deletes():
	await _make("load")
	assert_true(screen._delete.disabled, "Nothing picked")
	screen._list.get_child(0).pressed.emit()
	screen._delete.pressed.emit()
	var dialogs: Array = screen.get_children().filter(func(c): return c is FODialog)
	assert_eq(dialogs.size(), 1, "Asks first")
	assert_eq(fake.calls, [])
	dialogs[0].choose(0)
	assert_eq(fake.calls, [["delete", "/saves/Terran_Imperium_turn_42.sav"]])
	assert_eq(screen._saves.size(), 1)
	assert_eq(
		screen._status.text, tr("SAVES_DELETED").replace("%1%", "Terran_Imperium_turn_42.sav")
	)


func test_galaxy_details_and_sorting():
	var saves: Array = FakeSource.new().saves.duplicate()
	assert_string_contains(SaveLoadScreen.galaxy_summary(saves[0]), "150")
	assert_eq(SaveLoadScreen.galaxy_summary(saves[1]), "", "Nothing known, nothing shown")
	assert_string_contains(SaveLoadScreen.galaxy_details(saves[0]), "zzX9")
	SaveLoadScreen.sort_saves(saves, "oldest")
	assert_eq(saves[0]["turn"], 40)
	SaveLoadScreen.sort_saves(saves, "turn")
	assert_eq(saves[0]["turn"], 42)
	SaveLoadScreen.sort_saves(saves, "file")
	assert_true(str(saves[0]["file"]).begins_with("FreeOrion"))


func test_disabled_buttons_say_why():
	await _make("load")
	assert_eq(screen._action.tooltip_text, tr("SAVES_PICK_ONE"))
	assert_eq(screen._delete.tooltip_text, tr("SAVES_PICK_ONE"))
	screen._list.get_child(0).pressed.emit()
	assert_eq(screen._action.tooltip_text, "", "no reason once it can be used")


func test_typing_a_saved_name_says_it_will_be_replaced():
	await _make("save")
	screen._name.text = "Terran_Imperium_turn_42.sav"
	screen._name.text_changed.emit(screen._name.text)
	assert_eq(screen._status.text, tr("SAVES_OVERWRITE"), "A typed extension is the same file")
	assert_true(screen._list.get_child(0).button_pressed, "Its card is picked")
	screen._action.pressed.emit()
	assert_not_null(_dialog(), "Asks before replacing")
	_dialog().choose(1)
	assert_eq(fake.calls, [], "Cancel saves nothing")
	screen._name.text = "A new one.SAV"
	screen._name.text_changed.emit(screen._name.text)
	assert_eq(screen._status.text, "")
	screen._action.pressed.emit()
	assert_eq(fake.calls, [["save", "A new one"]], "Saved at once, without the extension")


func test_file_stem_is_the_file_the_server_writes():
	assert_eq(SaveLoadScreen.file_stem("  my game.sav "), "my game")
	assert_eq(SaveLoadScreen.file_stem("../a:b/c"), ".._a_b_c")
	assert_eq(SaveLoadScreen.file_stem(".sav"), "", "Nothing left to save as")


func test_loading_in_a_game_asks_first():
	await _make("load")
	screen.defer_load = true
	screen.empire_name = func() -> String: return "Terran Imperium"
	watch_signals(screen)
	screen._list.get_child(0).pressed.emit()
	screen._action.pressed.emit()
	assert_signal_not_emitted(screen, "load_started", "The running game would be lost")
	var dialog := _dialog()
	assert_string_contains(dialog._message.text, tr("MENU_CONFIRM_LEAVE"))
	assert_string_contains(
		dialog._message.text, GameMenu.saved_note(fake.saves[0]), "Says when it was last saved"
	)
	dialog.choose(0)
	assert_signal_emitted_with_parameters(
		screen, "load_started", ["/saves/Terran_Imperium_turn_42.sav"]
	)
	assert_eq(fake.calls, [], "The game shell loads it once the game has ended")


func test_autosave_cards_leave_the_file_name_to_the_tooltip():
	await _make("load")
	var card: Button = screen._list.get_child(1)
	var texts: Array = card.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_false(texts.any(func(t): return t.contains("FreeOrion_Admiral")))
	assert_string_contains(card.tooltip_text, "FreeOrion_Admiral_Terran_Imperium_0040.sav")


func test_double_click_loads():
	await _make("load")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	screen._list.get_child(0).gui_input.emit(click)
	assert_eq(fake.calls, [["load", "/saves/Terran_Imperium_turn_42.sav"]])


func _dialog() -> FODialog:
	var dialogs := screen.get_children().filter(
		func(c): return c is FODialog and not c.is_queued_for_deletion()
	)
	return dialogs.back() if not dialogs.is_empty() else null


func test_autosaves_can_be_hidden_when_loading():
	await _make("load")
	assert_true(screen._autos.visible)
	screen._autos.button_pressed = false
	await wait_process_frames(1)
	assert_eq(screen._list.get_child_count(), 1, "Only the named save")
	screen._autos.button_pressed = true
	await wait_process_frames(1)
	assert_eq(screen._list.get_child_count(), 2)
	fake.saves = fake.saves.filter(func(s): return not s.get("auto", false))
	screen.refresh()
	assert_false(screen._autos.visible, "Nothing to hide")


func test_saving_offers_no_autosave_toggle():
	await _make("save")
	assert_false(screen._autos.visible)
