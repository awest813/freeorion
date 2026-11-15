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
	assert_eq(screen._list.get_child(0).text, tr("SAVES_EMPTY"))


func test_format_time():
	assert_eq(SaveLoadScreen.format_time("2026-11-15T10:42:07Z"), "2026-11-15 10:42")
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
