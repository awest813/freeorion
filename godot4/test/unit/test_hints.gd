extends GutTest
## First-time hints.

var coach: HintCoach


func before_each():
	coach = HintCoach.new()
	coach.persist = false
	add_child_autofree(coach)
	# A fixed area instead of the (headless) window.
	coach.set_anchors_preset(Control.PRESET_TOP_LEFT)
	coach.position = Vector2.ZERO
	coach.size = Vector2(1280, 800)


func test_one_at_a_time_and_once():
	coach.offer("map")
	coach.offer("end_turn")
	coach.offer("map")
	assert_eq(coach.current, "map")
	assert_true(coach._card.visible)
	assert_eq(coach._text.text, tr("HINT_MAP"))
	coach.dismiss()
	assert_eq(coach.current, "end_turn", "The waiting hint comes next")
	coach.dismiss()
	assert_eq(coach.current, "")
	assert_false(coach._card.visible)
	coach.offer("map")
	assert_eq(coach.current, "", "Seen hints don't come back")


func test_turn_off_and_reset():
	coach.offer("production")
	coach.offer("research")
	coach.turn_off()
	assert_false(coach._card.visible)
	coach.offer("design")
	assert_eq(coach.current, "", "Off")
	coach.reset()
	coach.screen_shown("production")
	assert_eq(coach.current, "production")


func test_placed_next_to_the_anchor_inside_the_screen():
	var anchor := Button.new()
	anchor.position = Vector2(1200, 10)
	anchor.size = Vector2(60, 30)
	coach.add_child(anchor)
	coach.offer("end_turn", anchor)
	await wait_process_frames(2)
	var card: Rect2 = coach._card.get_rect()
	assert_gt(card.position.y, 40.0, "Below the button")
	assert_lte(card.end.x, 1280.0, "Kept on screen")


func test_game_shell_offers_screen_hints():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(2)
	assert_false(shell.hints.enabled, "No hints outside a real game")
	shell.hints.enabled = true
	shell.show_screen("production")
	assert_eq(shell.hints.current, "production")


func test_options_can_show_hints_again():
	var screen := OptionsScreen.new()
	var fake: RefCounted = preload("res://test/unit/fake_options_source.gd").new()
	fake.options[HintCoach.OPTION_SEEN] = {
		"value": "map end_turn", "default": "", "description": ""
	}
	fake.options[HintCoach.OPTION_ENABLED] = {"value": false, "default": true, "description": ""}
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	screen.reset_hints()
	assert_eq(fake.get_value(HintCoach.OPTION_SEEN), "")
	assert_eq(fake.get_value(HintCoach.OPTION_ENABLED), true)


func test_hints_name_the_current_key():
	coach.offer("end_turn")
	assert_string_contains(coach._text.text, FOHotkeys.binding("end_turn"))
	assert_false(coach._text.text.contains("%1%"))


func test_map_hints_wait_while_a_screen_is_open():
	coach.offer("end_turn")
	assert_eq(coach.current, "end_turn")
	coach.screen_shown("research")
	assert_eq(coach.current, "research", "The screen's own hint, not one about the map")
	coach.dismiss()
	assert_eq(coach.current, "", "The map hint waits for the map")
	coach.screen_shown("")
	assert_eq(coach.current, "end_turn", "Back on the map: it comes back")


func test_screen_hints_sit_in_the_bottom_right():
	coach.size = Vector2(1280, 800)
	coach.screen_shown("production")
	await wait_seconds(FOUi.tokens.motion + HintCoach.SETTLE_SECONDS + 0.1)
	var card: Rect2 = coach._card.get_rect()
	assert_gt(card.position.y, 400.0, "Clear of the screen's top rows")
	assert_gt(card.position.x, 640.0)


func test_screen_hint_takes_the_quietest_corner():
	var area := Rect2(0, 0, 1000, 800)
	var card := Vector2(300, 150)
	assert_eq(
		HintCoach.quiet_corner(area, card, []),
		Vector2(700, 650),
		"Bottom right when nothing is in the way"
	)
	# Add buttons down the right side: the bottom left is clear.
	var buttons := [Rect2(900, 100, 80, 700)]
	assert_eq(HintCoach.quiet_corner(area, card, buttons), Vector2(0, 650))
	# Everything along the bottom: a top corner.
	assert_eq(HintCoach.quiet_corner(area, card, [Rect2(0, 600, 1000, 200)]), Vector2(700, 0))


func test_screen_hint_keeps_clear_of_the_screen_controls():
	var screen := Control.new()
	coach.add_child(screen)
	screen.position = Vector2.ZERO
	screen.size = coach.size
	var add := Button.new()
	add.text = "Add"
	screen.add_child(add)
	add.position = Vector2(1100, 700)
	add.size = Vector2(120, 60)
	# Scrolled out of its list: no longer in the way.
	var scroll := ScrollContainer.new()
	screen.add_child(scroll)
	scroll.position = Vector2(0, 0)
	scroll.size = Vector2(200, 100)
	var hidden := Button.new()
	scroll.add_child(hidden)
	hidden.custom_minimum_size = Vector2(200, 600)
	var rects := HintCoach.busy_rects(screen, Rect2(Vector2.ZERO, coach.size))
	assert_eq(rects.size(), 2)
	assert_true(rects.all(func(r): return r.end.y <= 100.0 or r.position.x >= 1100.0), str(rects))
	coach.screen_shown("production", screen)
	await wait_seconds(FOUi.tokens.motion + HintCoach.SETTLE_SECONDS + 0.1)
	assert_eq(coach.current, "production")
	var card: Rect2 = coach._card.get_global_rect()
	assert_false(
		card.intersects(add.get_global_rect()), "The hint leaves the Add button free: %s" % card
	)
	assert_gt(card.end.y, 600.0, "Still along the bottom")
