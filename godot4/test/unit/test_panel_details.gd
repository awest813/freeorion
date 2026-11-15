extends GutTest
## Planet and system panel details: status, visibility, buildings being
## built, building and special tooltips, the system summary, and the
## population census.


func _planet(data: Dictionary) -> PlanetPanel:
	var panel := PlanetPanel.new()
	panel.accounting_provider = func(_id, _meter) -> Dictionary: return {}
	add_child_autofree(panel)
	panel.show_data(data)
	return panel


func test_status_and_visibility():
	var panel := _planet(
		{
			"id": 5,
			"name": "Home",
			"own": true,
			"status": PackedStringArray(["Home was attacked on the previous turn."]),
			"status_icon": "icons/planet_status_attacked.png",
		}
	)
	assert_true(panel._status.visible)
	assert_string_contains(panel._status_text.get_parsed_text(), "attacked")
	assert_false(panel._visibility.visible)
	panel.show_data({"id": 6, "name": "Far", "visibility_text": "Last seen on turn 3."})
	assert_false(panel._status.visible)
	assert_true(panel._visibility.visible)
	assert_string_contains(panel._visibility.get_parsed_text(), "turn 3")


func test_buildings_being_built_and_tooltips():
	var panel := _planet(
		{
			"id": 5,
			"name": "Home",
			"own": true,
			"buildings":
			[
				{
					"id": 1,
					"type": "BLD_SHIPYARD_BASE",
					"name": "Shipyard",
					"description": "BLD_SHIPYARD_BASE_DESC"
				}
			],
			"producing": [{"type": "BLD_MILITARY_COMMAND", "progress": 0.4, "turns_left": 3}],
			"specials": [{"name": "GAIA_SPECIAL", "capacity": 0.0, "turn_added": 7}],
		}
	)
	assert_eq(panel._producing.get_child_count(), 1)
	var bar: ProgressBar = panel._producing.find_children("*", "ProgressBar", true, false)[0]
	assert_almost_eq(bar.value, 0.4, 0.001)
	var link: RichTextLabel = panel._buildings.get_child(0).get_child(1)
	assert_false(link.tooltip_text.is_empty(), "description as tooltip")
	var special: RichTextLabel = panel._specials.get_child(0).get_child(1)
	assert_string_contains(special.tooltip_text, "7")


func test_species_links_to_the_pedia():
	var panel := _planet({"id": 5, "name": "Home", "species": "SP_HUMAN"})
	assert_string_contains(panel._subtitle.text, "[url=")
	watch_signals(panel)
	panel._on_meta_clicked("fo://species/SP_HUMAN")
	assert_signal_emitted_with_parameters(panel, "link_activated", ["species", "SP_HUMAN"])


func test_system_summary_adds_own_planets():
	var planets := [
		{"name": "A", "own": true, "meters": {"industry": 10.0, "supply": 2.0, "troops": 4.0}},
		{"name": "B", "own": true, "meters": {"industry": 5.0, "supply": 3.0}},
		{"name": "C", "own": false, "meters": {"industry": 99.0}},
	]
	var summary := SystemPanel.system_summary(planets)
	assert_eq(summary["industry"][0], 15.0)
	assert_eq(summary["supply"][0], 3.0, "the highest supply range")
	assert_eq(summary["troops"][1], [["A", 4.0]])
	var panel := SystemPanel.new()
	add_child_autofree(panel)
	panel.show_data({"name": "Sys", "planets": planets, "fleets": []})
	assert_true(panel._summary.visible)
	var texts := panel._summary.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_has(texts, "15.0")


func test_census():
	var text := (
		TopBar
		. census_text(
			{
				"population_by_species": {"SP_HUMAN": 20.0, "SP_LAENFA": 5.0},
				"population_by_tag": {"GOOD_INDUSTRY": 20.0},
			}
		)
	)
	assert_string_contains(text, tr("SP_HUMAN") + ": 20.0")
	assert_lt(text.find(tr("SP_HUMAN")), text.find(tr("SP_LAENFA")), "largest first")
	assert_string_contains(text, tr("TOPBAR_CENSUS_TAGS"))
