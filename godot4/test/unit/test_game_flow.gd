extends GutTest
## Game flow found by playtesting: the readiness check's items look like
## links, the menu's Save waits for the AI players and comes back on its
## own, and saving from the save screen returns to the game.

const FakeSaves := preload("res://test/unit/fake_saves_source.gd")


func test_readiness_items_look_clickable():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	var dialog := shell.show_readiness(
		[{"text": "The research queue is empty.", "screen": "research"}]
	)
	var links := dialog.find_children("*", "LinkButton", true, false)
	assert_eq(links.size(), 1)
	assert_eq(links[0].underline, LinkButton.UNDERLINE_MODE_ALWAYS)


func test_menu_save_waits_and_comes_back():
	var menu := GameMenu.new()
	add_child_autofree(menu)
	var ready := [false]
	menu.save_check = func() -> bool: return ready[0]
	menu.open("Empire · Turn 4", false)
	assert_true(menu._save.disabled)
	assert_eq(menu._save.tooltip_text, tr("GAME_MENU_SAVE_WAIT"), "Says what it waits for")
	ready[0] = true
	await wait_process_frames(2)
	assert_false(menu._save.disabled, "Enabled once the AI players are done")


func test_saving_from_the_screen_reports_once():
	var screen := SaveLoadScreen.new()
	screen.mode = "save"
	screen.source = FakeSaves.new()
	add_child_autofree(screen)
	screen.refresh()
	watch_signals(screen)
	screen.on_save_completed("/x/auto/turn_5.sav")
	assert_signal_not_emitted(screen, "saved", "An autosave isn't ours")
	screen._name.text = "mine"
	screen._name.text_changed.emit("mine")
	screen._on_action()
	screen.on_save_completed("/x/mine.sav")
	assert_signal_emitted_with_parameters(screen, "saved", ["/x/mine.sav"])
