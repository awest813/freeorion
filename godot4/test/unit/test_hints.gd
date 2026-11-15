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
	coach.offer("production")
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
