extends GutTest
## Game flow found by playtesting: the readiness check's items look like
## links, the menu's Save waits for the AI players and comes back on its
## own, and saving from the save screen returns to the game.

const FakeSaves := preload("res://test/unit/fake_saves_source.gd")
const FakeProduction := preload("res://test/unit/fake_production_source.gd")


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


func test_buildings_that_empty_a_planet_ask_first():
	var screen := ProductionScreen.new()
	var fake: RefCounted = FakeProduction.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	assert_null(screen.add_item({"label": "Shipyard", "name": "BLD_SHIPYARD_BASE"}))
	assert_eq(fake.calls.size(), 1, "an ordinary building is queued at once")
	var dialog := screen.add_item({"label": "Evacuation", "name": "BLD_EVACUATION"})
	assert_not_null(dialog)
	assert_eq(fake.calls.size(), 1, "nothing is queued before the answer")
	dialog.choose(1)
	assert_eq(fake.calls.size(), 1, "Cancel queues nothing")
	dialog = screen.add_item({"label": "Evacuation", "name": "BLD_EVACUATION"})
	dialog.choose(0)
	assert_eq(fake.calls.size(), 2)
	assert_eq(fake.calls[1], ["enqueue", "Evacuation", 101])


func test_auto_end_turn_stops_in_danger():
	var guard := AutoTurnGuard.new()
	assert_eq(guard.check({"planets": 3}, []), "", "first turn: nothing to compare")
	assert_eq(guard.check({"planets": 4}, [{"label": "SITREP_TECH_RESEARCHED_LABEL"}]), "")
	assert_eq(guard.check({"planets": 3}, []), "AUTO_TURN_STOP_PLANET_LOST")
	assert_eq(
		guard.check({"planets": 3}, [{"label": "SITREP_COMBAT_SYSTEM_LABEL"}]),
		"AUTO_TURN_STOP_COMBAT"
	)
	assert_eq(
		guard.check({"planets": 3}, [{"label": "SITREP_OWN_SHIP_DESTROYED_AT_SYSTEM_LABEL"}]),
		"AUTO_TURN_STOP_SHIP_LOST"
	)
	assert_eq(guard.check({"planets": 3}, []), "", "calm again")
	assert_eq(guard.check({"planets": 3}, [], [41]), "AUTO_TURN_STOP_ENEMY_SIGHTED")
	assert_eq(guard.check({"planets": 3}, [], [41]), "", "seen already")
	var fleets := [
		{"id": 1, "owner_id": 2, "armed": true, "visibility": "visible", "system_id": 5},
		{"id": 2, "owner_id": 3, "armed": true, "visibility": "visible", "system_id": 5},
		{"id": 3, "owner_id": -1, "armed": true, "visibility": "visible", "system_id": 5},
		{"id": 4, "owner_id": 2, "armed": false, "visibility": "visible", "system_id": 5},
		{"id": 5, "owner_id": 2, "armed": true, "visibility": "seen", "system_id": 5},
		{"id": 6, "owner_id": 2, "armed": true, "visibility": "visible", "system_id": 8},
	]
	assert_eq(AutoTurnGuard.hostile_in_supply(fleets, {5: true}, {2: true}), [1, 3])


func test_refused_moves_say_why():
	assert_eq(MoveOrders.move_refusal_text("MOVE_PROBLEM_NO_ROUTE"), tr("MOVE_PROBLEM_NO_ROUTE"))
	assert_eq(MoveOrders.move_refusal_text(""), tr("SYSTEM_PANEL_ORDER_REFUSED"))
	assert_ne(tr("MOVE_PROBLEM_FUEL"), "MOVE_PROBLEM_FUEL", "has a text")


func test_colony_fleets_list_places_to_settle():
	var targets := SettleTargets.new()
	add_child_autofree(targets)
	var places := [
		{
			"planet_name": "Vega II",
			"system_id": 9,
			"system_name": "Vega",
			"eta": 3,
			"target_population": 8.0,
		},
		{"planet_name": "Rock", "planet_id": 12, "system_id": 4, "eta": 0, "outpost": true},
	]
	targets.provider = func(_id, _count): return places
	var colony := {"id": 5, "ships": [{"colony": true}]}
	targets.show_fleet({"id": 5, "ships": [{"colony": false}]}, true)
	assert_false(targets.visible, "no settlers, no list")
	targets.show_fleet(colony.merged({"destination": "Sol"}), true)
	assert_false(targets.visible, "already on its way")
	targets.show_fleet(colony, false)
	assert_false(targets.visible, "not our fleet")
	targets.show_fleet(colony, true)
	assert_true(targets.visible)
	var buttons := targets.find_children("*", "Button", true, false)
	assert_eq(buttons.size(), 2)
	assert_string_contains(buttons[0].text, "Vega II")
	assert_string_contains(buttons[1].text, tr("SETTLE_TARGETS_HERE"))
	watch_signals(targets)
	targets.show_fleet(colony, true)
	assert_signal_emitted_with_parameters(targets, "targets_changed", [places])
	targets.show_fleet({}, false)
	assert_signal_emitted_with_parameters(targets, "targets_changed", [[]], 1)
	targets.show_fleet(colony, true)
	await get_tree().process_frame
	buttons = targets.find_children("*", "Button", true, false)
	buttons[0].mouse_entered.emit()
	assert_signal_emitted_with_parameters(targets, "target_hovered", [9])
	assert_eq(
		SettleTargets.mark_text([places[1], places[1]]),
		"%s ×2 · %s" % [tr("SETTLE_TARGETS_OUTPOST"), tr("SETTLE_TARGETS_HERE")]
	)
	buttons[0].pressed.emit()
	assert_signal_emitted_with_parameters(targets, "send_requested", [5, 9])
	buttons[1].pressed.emit()
	assert_signal_emitted_with_parameters(targets, "settle_requested", [12])
	places.clear()
	targets.show_fleet(colony, true)
	await get_tree().process_frame
	assert_eq(targets.find_children("*", "Button", true, false).size(), 0)
	var texts := targets.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_has(texts, tr("SETTLE_TARGETS_NONE"))


func test_ships_need_a_shipyard_location():
	var screen := ProductionScreen.new()
	screen.source = FakeProduction.new()
	add_child_autofree(screen)
	screen.refresh()
	screen.select_location_among([102])
	assert_eq(screen.selected_location_id(), 102)
	var note := screen._nothing_here("ship", 102)
	add_child_autofree(note)
	var go: Button = note.find_children("*", "Button", true, false)[0]
	assert_eq(go.text, tr("PRODUCTION_BUILD_AT").replace("%1%", "Hegira β I"))
	go.pressed.emit()
	assert_eq(screen.selected_location_id(), 101, "back at the capital")
	var plain := screen._nothing_here("building", 101)
	add_child_autofree(plain)
	assert_eq(plain.find_children("*", "Button", true, false).size(), 0)


func test_autosaves_stay_out_of_the_log():
	assert_true(MessageLog.is_autosave("/home/a/.local/share/freeorion/save/auto/x_0014.sav"))
	assert_true(MessageLog.is_autosave("C:\\Users\\a\\save\\auto\\x.sav"))
	assert_false(MessageLog.is_autosave("/home/a/.local/share/freeorion/save/mine.sav"))
	assert_true(MessageLog.is_autosave("/s/de6fbad8-86fd-41b2-9498-09fd97f4790f/g_0003.mps"))


func test_new_scouts_explore_on_their_own():
	var fleets := [
		{"id": 1, "age": 0},
		{"id": 2, "age": 1073741825},
		{"id": 3, "age": 0, "exploring": true},
		{"id": 4, "age": 0, "destination": "Vega"},
		{"id": 5, "age": 0},
	]
	var heads := {1: "scout", 2: "scout", 3: "scout", 4: "scout", 5: "colony"}
	assert_eq(MoveOrders.scouts_to_explore(fleets, heads, 7), [1], "new idle scouts only")
	assert_eq(MoveOrders.scouts_to_explore(fleets, heads, 2), [1, 2], "the starting ones too")


func test_new_turns_are_announced_and_numbers_count_up():
	var banner := TurnBanner.new()
	add_child_autofree(banner)
	var was := FOUi.reduce_motion
	FOUi.reduce_motion = false
	banner.announce(12, null)
	assert_true(banner.visible)
	assert_string_contains(banner._title.text, "12")
	var bar := TopBar.new()
	bar.follow_game = false
	add_child_autofree(bar)
	bar.set_state("Empire", Color.WHITE, 3, false)
	bar.set_resources({"industry": 10.0, "industry_spent": 10.0})
	bar.set_resources({"industry": 20.0, "industry_spent": 20.0})
	var chip: Button = bar._resource_chips["industry"]
	assert_ne(chip.text, "20.0", "still counting")
	await wait_seconds(FOUi.tokens.motion * 4.0 + 0.2)
	assert_eq(chip.text, "20.0")
	bar.end_turn()
	assert_true(bar._busy.visible, "busy while the turn is processed")
	FOUi.reduce_motion = was


func test_screens_open_with_motion_but_keep_their_size():
	var holder := Control.new()
	holder.size = Vector2(1280, 800)
	add_child_autofree(holder)
	var shell := GameShell.new()
	shell.follow_game = false
	holder.add_child(shell)
	await wait_process_frames(1)
	var was := FOUi.reduce_motion
	FOUi.reduce_motion = false
	shell.show_screen("design")
	await wait_seconds(FOUi.tokens.motion + 0.2)
	var screen := shell.designer_screen
	assert_lte(screen.size.y, holder.size.y, "fits the window")
	assert_eq(screen.scale, Vector2.ONE, "settled")
	assert_eq(screen.modulate.a, 1.0)
	FOUi.reduce_motion = was
