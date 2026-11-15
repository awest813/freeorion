extends GutTest
## Fleet icons' size marks, the explore order, per-weapon damage, and the
## combat report's graphical summary and foldable sections.

const SIDES := [
	{
		"name": "Blue",
		"color": Color.BLUE,
		"unit_list":
		[
			{"health": 10.0, "max_health": 40.0},
			{"health": 20.0, "max_health": 20.0},
			{"health": 0.0, "max_health": 10.0, "destroyed": true},
		],
	},
	{"name": "Red", "color": Color.RED, "unit_list": [{"health": 5.0, "max_health": 10.0}]},
]


func test_size_marks_double():
	assert_eq(FleetLayer.size_mark(1), 0)
	assert_eq(FleetLayer.size_mark(2), 1)
	assert_eq(FleetLayer.size_mark(7), 2)
	assert_eq(FleetLayer.size_mark(8), 3)
	assert_eq(FleetLayer.size_mark(500), 7)


func test_explore_from_the_fleet_menu():
	var panel := FleetPanel.new()
	panel.give_targets_provider = func(_id) -> Dictionary: return {}
	add_child_autofree(panel)
	panel.show_data({"id": 7, "name": "Scouts", "own": true, "in_system": true, "ships": []})
	assert_has(panel.menu_actions(), 11)
	watch_signals(panel)
	panel.run_menu_action(11)
	assert_signal_emitted_with_parameters(panel, "explore_requested", [7, true])
	panel.show_data(
		{"id": 7, "name": "Scouts", "own": true, "exploring": true, "in_system": false, "ships": []}
	)
	assert_eq(panel.menu_actions()[0], 12, "stop exploring")
	assert_string_contains(panel._route.text, tr("FLEET_PANEL_EXPLORING"))


func test_damage_tooltip_lists_weapons():
	var panel := ShipPanel.new()
	panel.accounting_provider = func(_id, _meter) -> Dictionary: return {}
	add_child_autofree(panel)
	(
		panel
		. show_data(
			{
				"id": 1,
				"name": "Lancer",
				"stats":
				[
					{
						"stat": "damage",
						"value": 36.0,
						"breakdown": [["2 × Mass Driver", "36 / 0"]],
					}
				],
			}
		)
	)
	var chip: Control = panel._stats.get_child(0)
	assert_string_contains(chip.tooltip_text, "2 × Mass Driver: 36 / 0")


func test_summary_bars():
	var summary := CombatSummary.new()
	add_child_autofree(summary)
	summary.sides = SIDES
	var bars := summary.bars(SIDES[0], 300.0, 60.0)
	assert_eq(bars.size(), 3)
	assert_almost_eq(bars[0][1], 0.25, 0.001, "largest first, a quarter left")
	assert_eq(bars[2][1], -1.0, "dead")
	assert_almost_eq(bars[1][0].size.y, 30.0, 0.01, "half the height of the largest")
	summary.set_toggle(false, "bar.proportional.height.enabled")
	assert_almost_eq(summary.bars(SIDES[0], 300.0, 60.0)[1][0].size.y, 60.0, 0.01)
	summary.set_toggle(true, "bar.proportional.width.enabled")
	var wide := summary.bars(SIDES[0], 300.0, 60.0)
	assert_gt(wide[0][0].size.x, wide[1][0].size.x, "wider for more health")
	var heights := summary.row_heights()
	assert_gt(heights[0], heights[1], "the bigger side gets the taller row")


func test_forces_and_losses_fold():
	var screen := CombatScreen.new()
	screen.source = preload("res://test/unit/fake_combat_source.gd").new()
	add_child_autofree(screen)
	screen.refresh()
	var headers := screen._detail.find_children("*", "Button", true, false).filter(
		func(b): return b.text.contains(tr("COMBAT_INITIAL_FORCES").split(" (")[0])
	)
	assert_gt(headers.size(), 0)
	var content: Control = headers[0].get_parent().get_child(headers[0].get_index() + 1)
	assert_true(content.visible)
	headers[0].pressed.emit()
	assert_false(content.visible, "folded")
