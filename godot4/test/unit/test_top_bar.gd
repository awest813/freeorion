extends GutTest
## TopBar driven directly (follow_game = false).

var bar: TopBar


func before_each():
	bar = TopBar.new()
	bar.follow_game = false
	add_child_autofree(bar)


func test_shows_empire_and_turn():
	bar.set_state("Empire Blue", Color("#3d9bff"), 12, false)
	assert_eq(bar._empire.text, "Empire Blue")
	assert_eq(bar._swatch.color, Color("#3d9bff"))
	assert_eq(bar._turn.text, tr("MAP_BTN_TURN_UPDATE").replace("%1%", "12"))
	assert_false(bar._end_turn.disabled)
	assert_eq(bar._end_turn.text, tr("TOPBAR_END_TURN"))


func test_no_game_disables_end_turn():
	bar.set_state("", Color.WHITE, 0, false)
	assert_true(bar._end_turn.disabled)
	assert_false(bar._swatch.visible, "No swatch without an empire")


func test_end_turn_waits_until_next_turn():
	bar.set_state("Empire Blue", Color.BLUE, 3, false)
	bar._end_turn.pressed.emit()
	assert_true(bar.is_waiting())
	assert_true(bar._end_turn.disabled, "Can't end the turn twice")
	assert_eq(bar._end_turn.text, tr("TOPBAR_WAITING"))


func test_ctrl_enter_is_the_shortcut():
	var event: InputEventKey = bar._end_turn.shortcut.events[0]
	assert_eq(event.keycode, KEY_ENTER)
	assert_true(event.ctrl_pressed)


func test_shell_disables_inherited_auto_translation():
	# Upstream MapWnd sets ALWAYS; names inside the shell must not be translated.
	var upstream := Control.new()
	upstream.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_ALWAYS
	add_child_autofree(upstream)
	var shell := GameShell.new()
	shell.follow_game = false
	upstream.add_child(shell)
	await wait_process_frames(1)
	shell.top_bar.set_state("Terran Imperium", Color.BLUE, 1, false)
	assert_eq(shell.top_bar._empire.atr("Terran Imperium"), "Terran Imperium")


func test_screen_buttons_request_screens():
	watch_signals(bar)
	var research: Button = bar._screen_buttons["research"]
	research.button_pressed = true
	assert_signal_emitted_with_parameters(bar, "screen_requested", ["research"])
	research.button_pressed = false
	assert_signal_emitted_with_parameters(bar, "screen_requested", [""])
	bar.set_active_screen("production")
	assert_true(bar._screen_buttons["production"].button_pressed)
	assert_false(bar._screen_buttons["research"].button_pressed)


func test_shell_shows_one_screen_at_a_time():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	shell.show_screen("production")
	assert_true(shell.production_screen.visible)
	shell.show_screen("research")
	assert_false(shell.production_screen.visible, "Exclusive")
	assert_true(shell.research_screen.visible)
	assert_true(shell.top_bar._screen_buttons["research"].button_pressed)
	shell.research_screen.close_requested.emit()
	assert_eq(shell.active_screen, "")
	assert_false(shell.research_screen.visible)
