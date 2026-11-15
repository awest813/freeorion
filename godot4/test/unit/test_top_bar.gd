extends GutTest
## TopBar driven directly (follow_game = false).

const RESOURCES := {
	"industry": 15.0,
	"industry_spent": 12.0,
	"research": 9.4,
	"research_spent": 9.4,
	"influence": 23.0,
	"influence_change": -1.5,
	"pp_stockpile": 4.0,
	"population": 34.5,
	"ships": 6,
	"detection": 30.0,
}

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
	assert_eq(bar._end_turn.text, tr("MAP_BTN_TURN_UNREADY").replace("%1%", "3"))
	assert_false(bar._end_turn.disabled, "Can be revised while the server waits")
	bar.set_phase("TURN_PROGRESS_PHASE_COMBAT", "Resolving Combat")
	assert_true(bar._end_turn.disabled, "Too late once processing started")
	assert_eq(bar._end_turn.text, tr("TOPBAR_WAITING"))
	assert_string_contains(bar._turn.text, "Resolving Combat")
	bar.set_state("Empire Blue", Color.BLUE, 4, false)
	assert_false(bar._turn.text.contains("Resolving Combat"), "Phase cleared on the new turn")


func test_revise_takes_the_turn_back():
	bar.set_state("Empire Blue", Color.BLUE, 3, false)
	bar._end_turn.pressed.emit()
	bar.set_phase("TURN_PROGRESS_PHASE_WAITING", "Waiting for Other Players")
	assert_true(bar.can_revise())
	bar._end_turn.pressed.emit()
	assert_false(bar.is_waiting())
	assert_eq(bar._end_turn.text, tr("TOPBAR_END_TURN"))


func test_phases_are_ignored_outside_waiting():
	bar.set_state("Empire Blue", Color.BLUE, 3, false)
	bar.set_phase("TURN_PROGRESS_PHASE_COMBAT", "Resolving Combat")
	assert_false(bar._turn.text.contains("Resolving Combat"))


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


func test_resources_are_hidden_without_an_empire():
	bar.set_resources({})
	for chip in bar._resource_chips.values():
		assert_false(chip.visible)


func test_resources_show_values_and_warnings():
	bar.set_resources(RESOURCES)
	var industry: Button = bar._resource_chips["industry"]
	assert_eq(industry.text, "15.0")
	assert_string_contains(industry.tooltip_text, tr("TOPBAR_WASTED").replace("%1%", "3.0"))
	assert_true(industry.has_theme_color_override("font_color"), "Wasted PP stand out")
	var research: Button = bar._resource_chips["research"]
	assert_false(research.has_theme_color_override("font_color"), "All RP spent")
	assert_eq(bar._resource_chips["influence"].text, "23.0 (-1.5)")
	assert_eq(bar._resource_chips["ships"].text, "6")


func test_resource_chips_open_their_screens():
	watch_signals(bar)
	bar.set_resources(RESOURCES)
	bar._resource_chips["influence"].pressed.emit()
	assert_signal_emitted_with_parameters(bar, "screen_requested", ["government"])
