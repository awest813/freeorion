extends GutTest
## PlanetPanel with fixed data.

const SAMPLE := {
	"id": 2568,
	"name": "Hegira β I",
	"type": "PT_TERRAN",
	"size": "SZ_LARGE",
	"species": "SP_HUMAN",
	"environment": "PE_GOOD",
	"focus": "FOCUS_RESEARCH",
	"owner_id": 1,
	"own": true,
	"owner_name": "Terran Imperium",
	"owner_color": Color("#1193ff"),
	"meters":
	[
		{"meter": "METER_POPULATION", "now": 22.2, "next": 22.5, "target": 25.0},
		{"meter": "METER_INDUSTRY", "now": 10.9, "next": 10.4, "target": 9.0},
		{"meter": "METER_RESEARCH", "now": 0.0, "next": 0.0, "target": 0.0},
		{"meter": "METER_DEFENSE", "now": 30.0, "next": 30.0, "target": 30.0},
	],
	"buildings":
	[
		{
			"id": 2688,
			"type": "BLD_IMPERIAL_PALACE",
			"name": "Imperial Palace",
			"icon": "icons/building/palace.png",
			"scrapping": false,
		},
		{
			"id": 2664,
			"type": "BLD_SHIPYARD_BASE",
			"name": "Basic Shipyard",
			"icon": "icons/building/shipyard.png",
			"scrapping": true,
		},
	],
	"specials": [{"name": "GAIA_SPECIAL", "icon": "icons/specials_huge/gaia.png", "capacity": 0.0}],
}

var panel: PlanetPanel


func before_each():
	panel = PlanetPanel.new()
	add_child_autofree(panel)
	panel.show_data(SAMPLE)


func _texts(node: Node) -> String:
	var parts: PackedStringArray = []
	for child in node.find_children("*", "", true, false):
		if child is Label or child is Button:
			parts.push_back(child.text)
		elif child is RichTextLabel:
			parts.push_back(child.get_parsed_text())
	return "\n".join(parts)


func test_header_says_what_the_planet_is():
	assert_true(panel.visible)
	assert_eq(panel._title.text, "Hegira β I")
	assert_eq(
		panel._subtitle.get_parsed_text(),
		(
			"%s %s · %s (%s) · %s · Terran Imperium"
			% [tr("SZ_LARGE"), tr("PT_TERRAN"), tr("SP_HUMAN"), tr("PE_GOOD"), tr("FOCUS_RESEARCH")]
		)
	)


func test_meters_show_change_and_target_and_skip_empty_ones():
	var text := _texts(panel._meters)
	assert_string_contains(text, tr("METER_POPULATION"))
	assert_string_contains(text, "22.2 +0.3")
	assert_string_contains(text, "/ 25.0")
	assert_string_contains(text, "10.9 −0.5")
	assert_false(text.contains(tr("METER_RESEARCH")), "All-zero meters are left out")
	assert_string_contains(text, "30.0\n")
	assert_eq(PlanetPanel.change_text(30.0, 30.01), "", "Steady")


func test_buildings_link_and_scrap():
	watch_signals(panel)
	var text := _texts(panel._buildings)
	assert_string_contains(text, "Imperial Palace")
	assert_string_contains(text, tr("FLEET_PANEL_SCRAPPING"))
	var buttons: Array = panel._buildings.find_children("*", "Button", true, false)
	assert_eq(buttons[0].text, tr("PLANET_PANEL_SCRAP"))
	assert_eq(buttons[1].text, tr("PLANET_PANEL_CANCEL_SCRAP"))
	buttons[0].pressed.emit()
	assert_signal_emitted_with_parameters(panel, "scrap_requested", [2688])


func test_no_scrapping_on_others_planets():
	var foreign := SAMPLE.duplicate(true)
	foreign["own"] = false
	panel.show_data(foreign)
	await wait_process_frames(1)
	assert_eq(panel._buildings.find_children("*", "Button", true, false).size(), 0)


func test_specials_and_links():
	watch_signals(panel)
	assert_string_contains(_texts(panel._specials), tr("GAIA_SPECIAL"))
	var link: RichTextLabel = panel._specials.find_children("*", "RichTextLabel", true, false)[0]
	link.meta_clicked.emit("fo://special/GAIA_SPECIAL")
	assert_signal_emitted_with_parameters(panel, "link_activated", ["special", "GAIA_SPECIAL"])


func test_sections_hide_when_empty():
	var bare := SAMPLE.duplicate(true)
	bare["buildings"] = []
	bare["specials"] = []
	panel.show_data(bare)
	assert_false(panel._buildings_title.visible)
	assert_false(panel._specials_title.visible)


func test_shell_swaps_planet_and_fleet_details():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	shell.planet_panel.show_data(SAMPLE)
	shell._on_fleet_selected(7)
	assert_false(shell.planet_panel.visible, "A fleet's details replace the planet's")
	shell.planet_panel.show_data(SAMPLE)
	shell._on_system_selected(5)
	assert_false(shell.planet_panel.visible, "Another system closes it")


func test_meter_breakdown_tooltip():
	panel.accounting_provider = func(id: int, meter: String) -> Dictionary:
		return {
			"meter": meter,
			"total": 25.0,
			"lines":
			[
				{"label": "Hegira β I Good Environment", "change": 12.0},
				{"label": "Terran Imperium Tech <i>Planetary Ecology</i>", "change": -1.0},
			],
		}
	var tooltip: Control = panel.accounting_tooltip("METER_TARGET_POPULATION")
	add_child_autofree(tooltip)
	var text := _texts(tooltip)
	assert_string_contains(
		text,
		tr("TT_BREAKDOWN_SUMMARY").replace("%1%", tr("METER_TARGET_POPULATION")).replace(
			"%2%", "25.00"
		)
	)
	assert_string_contains(text, "Planetary Ecology")
	assert_string_contains(text, "+12.00")
	assert_string_contains(text, "-1.00")


func test_no_breakdown_falls_back_to_plain_tooltip():
	panel.accounting_provider = func(_id: int, _meter: String) -> Dictionary: return {}
	assert_null(panel.accounting_tooltip("METER_TARGET_INDUSTRY"))
	var names: Array = panel._meters.get_children().filter(func(c): return c is FOTooltipLabel)
	assert_eq(names.size(), 3, "Each shown meter's name explains it on hover")


func test_suitability_on_request():
	var asked := []
	panel.suitability_provider = func(id: int) -> Array:
		asked.push_back(id)
		return [
			{
				"species": "SP_HUMAN",
				"environment": "PE_GOOD",
				"target_population": 16.5,
				"icon": "icons/species/human.png"
			},
			{"species": "SP_LAENFA", "environment": "PE_HOSTILE", "target_population": -4.0},
		]
	assert_false(panel._suitability.visible)
	assert_eq(asked, [], "Nothing worked out until asked")
	panel._suitability_button.button_pressed = true
	assert_eq(asked, [2568])
	var text := _texts(panel._suitability)
	assert_string_contains(text, tr("SP_HUMAN"))
	assert_string_contains(text, "16.5")
	assert_string_contains(text, "-4.0")
	assert_string_contains(text, tr("PE_HOSTILE"))
	panel.show_data(SAMPLE)
	assert_false(panel._suitability.visible, "Closed again for the next planet")
