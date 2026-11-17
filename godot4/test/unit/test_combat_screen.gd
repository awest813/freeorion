extends GutTest
## CombatScreen with a fake source, plus the shell's badge and links.

const FAKE := preload("res://test/unit/fake_combat_source.gd")

var screen: CombatScreen
var fake: RefCounted


func before_each():
	screen = CombatScreen.new()
	fake = FAKE.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()


func _cards() -> Array:
	return screen._list.get_children().filter(func(c): return c is Button)


func _texts(node: Node) -> String:
	var parts: PackedStringArray = []
	for child in node.find_children("*", "", true, false):
		if child is Label:
			parts.push_back(child.text)
		elif child is RichTextLabel:
			parts.push_back(child.get_parsed_text())
	return "\n".join(parts)


func test_lists_combats_newest_first_and_opens_the_newest():
	var cards := _cards()
	assert_eq(cards.size(), 2)
	assert_eq(cards[0].get_meta("id"), 5)
	assert_true(cards[0].button_pressed)
	assert_eq(fake.requested, [5])


func test_card_shows_losses():
	var text := _texts(_cards()[0])
	assert_string_contains(text, "Iszm α")
	assert_string_contains(text, tr("COMBAT_REPORT_LOSSES").replace("%1%", "1").replace("%2%", "1"))
	assert_string_contains(_cards()[0].tooltip_text, "Iszm α", "Says it whole in the tooltip")


func test_detail_shows_sides_units_and_log():
	var text := _texts(screen._detail)
	assert_string_contains(text, tr("COMBAT_REPORT_AT").replace("%1%", "Iszm α"))
	for side_name in ["Terran Imperium", "Neutral", "Congregation"]:
		assert_string_contains(text, side_name)
	assert_string_contains(text, tr("COMBAT_REPORT_LOST").replace("%1%", "1").replace("%2%", "2"))
	assert_string_contains(text, tr("COMBAT_REPORT_DAMAGE").replace("%1%", "198"))
	assert_string_contains(text, "Tartaro")
	assert_string_contains(text, tr("COMBAT_REPORT_DESTROYED"))
	assert_string_contains(text, "Round 1")
	assert_string_contains(text, "Delany was destroyed")


func test_shots_are_built_on_expand():
	var toggles: Array = screen._detail.find_children("*", "Button", true, false).filter(
		func(b): return b.toggle_mode and b.text == "▸"
	)
	assert_false(_texts(screen._detail).contains("Round 2"), "Empty rounds are left out")
	assert_eq(toggles.size(), 2, "Two attacks have shots")
	assert_false(_texts(screen._detail).contains("attacks"), "Shots stay folded")
	toggles[1].button_pressed = true
	var text := _texts(screen._detail)
	assert_string_contains(text, "Tartaro attacks Delany for 24 damage")
	assert_eq(toggles[1].text, "▾")


func test_selecting_another_combat():
	_cards()[1].pressed.emit()
	assert_eq(fake.requested, [5, 2])
	assert_true(_cards()[1].button_pressed)
	assert_false(_cards()[0].button_pressed)
	assert_string_contains(_texts(screen._detail), tr("COMBAT_REPORT_NO_EVENTS"))


func test_refresh_keeps_the_shown_combat():
	screen.open(2)
	screen.refresh()
	assert_eq(screen._selected_id, 2)


func test_empty_and_fetching_states():
	fake.combats = []
	screen.refresh()
	assert_string_contains(_texts(screen._empty), tr("COMBAT_REPORTS_EMPTY"))
	fake.pending = 3
	screen.refresh()
	assert_string_contains(_texts(screen._empty), tr("COMBAT_REPORTS_FETCHING"))
	assert_eq(screen._info.text, tr("COMBAT_REPORTS_FETCHING"))


func test_links_are_forwarded():
	watch_signals(screen)
	screen._on_meta_clicked("fo://ship/7012")
	assert_signal_emitted_with_parameters(screen, "link_activated", ["ship", "7012"])


func test_losses_and_newest_id():
	assert_eq(CombatScreen.losses(fake.combats[0]), Vector2i(1, 1))
	assert_eq(CombatScreen.newest_id(fake.combats), 5)
	assert_eq(CombatScreen.newest_id([]), -1)


func test_shell_badge_counts_last_turn_combats_until_seen():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	var button: Button = shell.top_bar._screen_buttons["combat"]
	shell.update_combat_badge(fake.combats, 24)
	assert_eq(button.text, "%s (1)" % tr("COMBAT_TAB"), "Only the turn-23 combat is new")
	shell.combat_screen.source = fake
	shell.combat_screen.refresh()
	shell.show_screen("combat")
	assert_eq(button.text, tr("COMBAT_TAB"))
	shell.show_screen("")
	shell.update_combat_badge(fake.combats, 24)
	assert_eq(button.text, tr("COMBAT_TAB"), "Seen combats don't count again")


func test_shell_opens_combat_links():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	shell.combat_screen.source = fake
	shell._on_link_activated("combat", "2")
	assert_eq(shell.active_screen, "combat")
	assert_eq(shell.combat_screen._selected_id, 2)


func test_empty_rounds_are_dropped():
	var events := [
		{"kind": "bout", "text": "Round 1"},
		{"kind": "attack", "text": "a"},
		{"kind": "bout", "text": "Round 2"},
		{"kind": "bout", "text": "Round 3"},
		{"kind": "destroyed", "text": "d"},
		{"kind": "bout", "text": "Round 4"},
	]
	var kept: Array = CombatScreen.without_empty_bouts(events).map(func(e): return e["text"])
	assert_eq(kept, ["Round 1", "a", "Round 3", "d"])


func test_replay_steps_through_the_bouts():
	screen.open(5)
	await wait_process_frames(1)
	assert_eq(screen.bout, 3, "Starts after the combat")
	var charts: Array = screen._detail.find_children("*", "LineChart", true, false)
	assert_eq(charts.size(), 1)
	assert_eq(charts[0].series.size(), 3, "One line per side")
	assert_eq(charts[0].hover_title.call(0), tr("COMBAT_REPLAY_BEFORE"))
	screen.show_bout(0)
	assert_eq(screen._bout_label.text, tr("COMBAT_REPLAY_BEFORE"))
	var bars: Array = screen._replay_bars
	assert_true(
		bars.any(func(e): return e[0].value == 40.0 and e[1][3] == 0.0), "A lost ship whole"
	)
	assert_true(screen._replay_losses.all(func(e): return not e[0].visible), "Nothing lost yet")
	assert_true(screen._log_rows.all(func(e): return e[0].visible == (e[1] == 0)))
	screen.show_bout(1)
	assert_true(screen._replay_losses.all(func(e): return e[0].visible), "Lost in bout 1")
	assert_true(screen._log_rows.any(func(e): return e[0].visible), "Bout 1's log")
	screen.show_bout(9)
	assert_eq(screen.bout, 3, "Kept within the combat")
	assert_eq(screen._whole_log.tooltip_text, "", "No reason while it can be pressed")
	screen.show_whole_combat()
	assert_true(screen._log_rows.all(func(e): return e[0].visible))
	assert_true(screen._whole_log.disabled)
	assert_eq(screen._whole_log.tooltip_text, tr("COMBAT_REPLAY_WHOLE_SHOWN"))


func test_reports_say_what_the_battle_came_to():
	var won := {"sides": [{"own": true, "destroyed": 0}, {"own": false, "destroyed": 2}]}
	assert_eq(CombatScreen.outcome(won)[0], "COMBAT_OUTCOME_VICTORY")
	var lost := {"sides": [{"own": true, "destroyed": 1}, {"own": false, "destroyed": 0}]}
	assert_eq(CombatScreen.outcome(lost)[0], "COMBAT_OUTCOME_DEFEAT")
	var both := {"sides": [{"own": true, "destroyed": 1}, {"own": false, "destroyed": 3}]}
	assert_eq(CombatScreen.outcome(both)[0], "COMBAT_OUTCOME_BOTH")
	assert_eq(CombatScreen.outcome({"sides": []})[0], "COMBAT_OUTCOME_NONE")
