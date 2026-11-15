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


func test_top_bar_tips_sit_below_the_whole_bar():
	var shell := GameShell.new()
	shell.follow_game = false
	shell.size = Vector2(1280, 800)
	add_child_autofree(shell)
	await wait_process_frames(2)
	shell.hints.turn_off()
	shell.hints.reset()
	for id in HintCoach.HINTS:
		shell.hints.seen[id] = id != "end_turn"
	shell.hints.seen.erase("end_turn")
	shell.hints.offer("end_turn", shell.top_bar._end_turn)
	await wait_process_frames(3)
	shell.hints._place()  # once laid out, as in the running game
	var card: Control = shell.hints._card
	assert_true(card.visible)
	var bar_bottom := shell.top_bar.get_global_rect().end.y
	assert_gte(card.get_global_rect().position.y, bar_bottom, "Not over the bar's second row")


func test_continue_names_the_game():
	var title := TitleScreen.new()
	add_child_autofree(title)
	title.set_can_continue(true, "Terran Imperium  ·  Turn 15")
	assert_true(title._continue_detail.visible)
	assert_eq(title._continue_detail.text, "Terran Imperium  ·  Turn 15")
	title.set_can_continue(false)
	assert_false(title._continue_detail.visible)


func test_lobby_warns_when_alone():
	var alone := {"players": [{"client_type": "player"}, {"client_type": "observer"}]}
	assert_eq(LobbyScreen.empire_count(alone), 1)
	alone["players"].push_back({"client_type": "ai"})
	assert_eq(LobbyScreen.empire_count(alone), 2)


func test_end_turn_and_menu_stay_on_screen_while_a_turn_is_processed():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	shell.size = Vector2(1280, 800)
	await wait_process_frames(2)
	var bar := shell.top_bar
	bar.set_state("Terran Imperium", Color.BLUE, 12, true)
	bar.set_phase(
		"TURN_PROGRESS_PHASE_ORDERS", "Processing orders sent by all the players this turn"
	)
	await wait_process_frames(3)
	assert_lte(bar._end_turn.get_global_rect().end.x, 1280.0, "End turn stays on screen")
	var menu: Button = null
	for b: Button in bar.find_children("*", "Button", true, false):
		if b.text == tr("MAP_BTN_MENU") or b.text == "Menu":
			menu = b
	assert_not_null(menu)
	assert_lte(menu.get_global_rect().end.x, 1280.0, "Menu stays on screen")


func test_screen_buttons_become_icons_when_their_names_dont_fit():
	var holder := Control.new()
	holder.size = Vector2(1600, 100)
	add_child_autofree(holder)
	var bar := TopBar.new()
	bar.follow_game = false
	holder.add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	await wait_process_frames(3)
	bar.fit_screen_buttons()
	assert_false(bar.is_compact(), "Room for the names")
	holder.size = Vector2(700, 100)
	await wait_process_frames(3)
	bar.fit_screen_buttons()
	assert_true(bar.is_compact(), "Too narrow: icons")
	var production: Button = bar._screen_buttons["production"]
	assert_not_null(production.icon)
	assert_eq(production.text, "")
	bar.set_badge("production", 2)
	assert_eq(production.text, "2", "Badges still show")
