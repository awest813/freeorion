extends GutTest
## Gaps a second parity audit found: production queue moves around items
## removed this turn, items whose location became invalid, turns to the
## next item of a batch, stockpile draw and wasted points.

const FakeProduction := preload("res://test/unit/fake_production_source.gd")


func _production() -> Array:
	var screen := ProductionScreen.new()
	var fake: RefCounted = FakeProduction.new()
	# The second queue item was removed this turn: its place stays (index 1)
	# but it isn't listed, so the listed items are at 0 and 2.
	fake.queue[1]["index"] = 2
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)
	return [screen, fake]


func test_moves_skip_items_removed_this_turn():
	var made := await _production()
	var screen: ProductionScreen = made[0]
	var fake: RefCounted = made[1]
	var last: Dictionary = fake.queue[1]
	assert_eq(screen.item_actions(last, 2), [0, 2, 7], "Listed last: no move down")
	screen.run_item_action(0, last, 2)
	assert_eq(fake.calls[-1], ["move", 2, 0])
	screen.run_item_action(1, fake.queue[0], 2)
	assert_eq(fake.calls[-1], ["move", 0, 2], "To the last listed place, not past it")


func test_invalid_location_and_batch_times():
	var made := await _production()
	var screen: ProductionScreen = made[0]
	var entry: Dictionary = made[1].queue[0].duplicate()
	entry["location_ok"] = false
	assert_string_contains(screen.queue_tooltip(entry), tr("PRODUCTION_LOCATION_INVALID"))
	entry["remaining"] = 3
	entry["turns_left"] = 9
	entry["turns_to_next"] = 3
	assert_eq(
		screen.turns_label(entry),
		tr("PRODUCTION_NEXT_AND_DONE").replace("%1%", ScreenKit.turns_text(3)).replace(
			"%2%", ScreenKit.turns_text(9)
		)
	)
	entry["remaining"] = 1
	assert_eq(screen.turns_label(entry), ScreenKit.turns_text(9))


func test_stockpile_draw_and_waste():
	var note := ProductionScreen.points_note(
		{"available": 15.0, "spent": 9.5, "stockpile_used": 1.25}
	)
	assert_string_contains(note, tr("PRODUCTION_DRAWN").replace("%1%", "1.2"))
	assert_string_contains(note, tr("PRODUCTION_WASTED").replace("%1%", "5.5"))
	assert_eq(ProductionScreen.points_note({"available": 5.0, "spent": 5.0}), "")


func test_player_status_refreshes_the_empires_list():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	var log: MessageLog = shell.get_children().filter(func(n): return n is MessageLog)[0]
	shell.empires_screen.source = preload("res://test/unit/fake_diplomacy_source.gd").new()
	shell.show_screen("empires")
	shell.empires_screen.source.empires[0]["ready"] = false
	log.players_changed()
	await wait_process_frames(1)
	var marks := shell.empires_screen._list.find_children("*", "TextureRect", true, false)
	assert_true(
		marks.any(func(m): return m.tooltip_text == tr("MP_TURN_PLAYING")), "Ready mark updated"
	)
