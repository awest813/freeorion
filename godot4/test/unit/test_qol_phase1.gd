extends GutTest
## Quality of life, phase 1: actions that don't happen say why, buttons that
## can't work are disabled (or hidden) with a reason, screens catch up after
## orders, and the lobby explains its ready state.

const FakeLobby := preload("res://test/unit/fake_lobby_source.gd")
const FakeProduction := preload("res://test/unit/fake_production_source.gd")


func _fleet(in_system: bool) -> Dictionary:
	return {
		"id": 9,
		"name": "Home Fleet",
		"own": true,
		"in_system": in_system,
		"ships": [{"id": 90, "name": "Scout", "scrapping": false}],
	}


func test_scrap_disabled_in_transit_with_a_reason():
	var panel := FleetPanel.new()
	add_child_autofree(panel)
	panel.show_data(_fleet(false))
	panel._on_ship_toggled(true, 90)
	assert_true(panel._scrap.disabled)
	assert_eq(panel._scrap.tooltip_text, tr("FLEET_SCRAP_NEEDS_SYSTEM"))
	panel.show_data(_fleet(true))
	panel._on_ship_toggled(true, 90)
	assert_false(panel._scrap.disabled)


func test_fleet_notice_until_another_fleet_is_shown():
	var panel := FleetPanel.new()
	add_child_autofree(panel)
	panel.show_data(_fleet(true))
	panel.show_notice(tr("ORDER_REFUSED_MERGE"))
	assert_true(panel._notice.visible)
	panel.show_data(_fleet(true))
	assert_true(panel._notice.visible, "Same fleet: still says why")
	var other := _fleet(true)
	other["id"] = 10
	panel.show_data(other)
	assert_false(panel._notice.visible)


func test_refused_fleet_orders_say_why():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	shell.fleet_panel.show_data(_fleet(true))
	shell.panel_orders.refused("ORDER_REFUSED_SCRAP")
	assert_eq(shell.fleet_panel._notice.text, tr("ORDER_REFUSED_SCRAP"))


func test_planet_menu_only_with_someone_to_give_to():
	var panel := PlanetPanel.new()
	add_child_autofree(panel)
	panel.give_targets_provider = func(_id) -> Dictionary: return {"targets": [], "giving_to": -1}
	panel.show_data({"id": 5, "name": "Home", "own": true})
	assert_false(panel._give.visible, "No disabled 'no gift' menu any more")


func test_annex_tooltip_says_why_first():
	var tip := SystemPanel.annex_tooltip({"state": "unaffordable", "tooltip": "<i>Opinions</i>: 3"})
	assert_true(tip.begins_with(tr("PLANET_REFUSED_ANNEX_IP")))
	assert_string_contains(tip, "Opinions: 3", "Markup stripped")


func test_production_catalogue_follows_orders():
	var screen := ProductionScreen.new()
	screen.source = FakeProduction.new()
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)
	var before: Node = screen._catalog.get_child(0)
	screen._order(true)
	await wait_process_frames(2)
	assert_ne(screen._catalog.get_child(0), before, "Catalogue rebuilt after an order")


func test_lobby_ready_reset_starting_and_human_needed():
	var source := FakeLobby.new()
	var lobby := LobbyScreen.new()
	lobby.source = source
	add_child_autofree(lobby)
	lobby.refresh()
	lobby.ready_button.pressed.emit()
	assert_eq(source.ready_sent, [true])
	lobby.refresh()  # the server didn't take it: settings changed
	assert_eq(lobby._info.text, tr("MP_READY_RESET"))
	source.lobby_data["players"][0]["ready"] = true
	lobby.refresh()
	assert_true(lobby.ready_button.disabled, "Everyone ready: no more ready toggling")
	assert_eq(lobby.ready_button.text, tr("MP_STARTING"))
	for player in source.lobby_data["players"]:
		if player["client_type"] == "player":
			player["client_type"] = "observer"
	lobby.refresh()
	assert_eq(lobby.conditions_text(), tr("MP_NEEDS_HUMAN_PLAYER"))
