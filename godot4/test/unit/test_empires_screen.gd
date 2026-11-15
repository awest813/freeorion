extends GutTest
## EmpiresScreen with a fake source.

var screen: EmpiresScreen
var fake: RefCounted


func before_each():
	screen = EmpiresScreen.new()
	fake = preload("res://test/unit/fake_diplomacy_source.gd").new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()


func _buttons(card: Node) -> Array:
	return card.find_children("*", "Button", true, false)


func test_lists_every_empire_own_first():
	var cards := screen._list.get_children()
	assert_eq(cards.size(), 4)
	assert_eq(_buttons(cards[0]).size(), 0, "No diplomacy with yourself")


func test_status_lines():
	assert_eq(EmpiresScreen.status_text(fake.empires[0]), tr("DIPLOMACY_YOU"))
	assert_eq(
		EmpiresScreen.status_text(fake.empires[1]),
		"%s · %s" % [tr("DIPLOMACY_STATUS_WAR"), tr("DIPLOMACY_INCOMING_PEACE")]
	)
	assert_eq(
		EmpiresScreen.status_text(fake.empires[2]),
		"%s · %s" % [tr("DIPLOMACY_STATUS_PEACE"), tr("DIPLOMACY_OUTGOING_ALLIES")]
	)
	assert_eq(EmpiresScreen.status_text(fake.empires[3]), tr("DIPLOMACY_ELIMINATED"))


func test_actions_are_offered_and_sent():
	var buttons := _buttons(screen._list.get_child(1))
	assert_eq(
		buttons.map(func(b): return b.text), [tr("DIPLOMACY_ACCEPT_PEACE"), tr("DIPLOMACY_REJECT")]
	)
	buttons[0].pressed.emit()
	assert_eq(fake.calls, [[2, "accept_peace"]])
	assert_eq(screen._info.text, tr("DIPLOMACY_SENT"))


func test_refused_action_says_so():
	fake.accept = false
	_buttons(screen._list.get_child(2))[1].pressed.emit()
	assert_eq(fake.calls, [[3, "declare_war"]])
	assert_eq(screen._info.text, tr("DIPLOMACY_REFUSED"))


func test_shell_opens_options_and_save_by_key():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	var key := InputEventKey.new()
	key.keycode = KEY_F10
	key.pressed = true
	shell._unhandled_key_input(key)
	assert_eq(shell.active_screen, "options")
	assert_true(shell.top_bar._screen_buttons.has("empires"))


func test_statistics_tab():
	screen._tabs.current_tab = 1
	await wait_process_frames(1)
	assert_true(screen._statistics.visible)
	assert_false(screen._diplomacy.visible)
	var names: Array = screen._stat_list.get_children().map(func(b): return b.text)
	assert_eq(names.size(), 2)
	assert_has(names, tr("PP_OUTPUT"))
	assert_eq(screen._chart.series.size(), 2, "One line per empire")
	assert_eq(screen._chart.highlight, 0, "Own empire highlighted")
	screen.show_statistic("SHIP_COUNT")
	assert_eq(screen._stat_title.text, tr("SHIP_COUNT"))
	assert_eq(screen._chart.series.size(), 1)
	var legend: Array = screen._legend.get_children()
	legend[0].button_pressed = false
	assert_true(screen._chart.hidden_series.has(0), "Legend hides a line")


func test_chart_helpers():
	assert_eq(LineChart.nice_ticks(0.0, 13.0), PackedFloat64Array([0, 5, 10, 15]))
	assert_eq(LineChart.nice_ticks(0.0, 154752.0)[-1], 200000.0)
	assert_eq(LineChart.short_number(154752.0), "154.8k")
	assert_eq(LineChart.short_number(12.0), "12")
	assert_eq(LineChart.short_number(10.906), "10.9")
	var line: Dictionary = fake.stat_records["PP_OUTPUT"][0]
	assert_eq(LineChart.value_at(line, 3), 11.0)
	assert_true(is_nan(LineChart.value_at(line, 9)))
	screen.show_statistic("PP_OUTPUT")
	await wait_process_frames(1)
	var chart: LineChart = screen._chart
	chart.size = Vector2(600, 300)
	var plot: Rect2 = chart._plot_rect()
	assert_eq(chart.turn_at(plot.position.x), 1)
	assert_eq(chart.turn_at(plot.end.x), 4)


func test_player_marks_and_summary_numbers():
	var own: Dictionary = screen.source.empires[0]
	var marks: Array = EmpiresScreen.player_marks(own).map(func(m): return m[0])
	assert_eq(marks, ["icons/human.png", "icons/ready.png"])
	var ai_marks: Array = EmpiresScreen.player_marks(screen.source.empires[1])
	assert_eq(ai_marks[0][0], "icons/ai.png")
	var values: Array = EmpiresScreen.summary_values(own).map(func(v): return v[1])
	assert_eq(values, ["12", "4", "31.5", "18.2", "3.0", "30.0"])
	var texts := screen._list.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_has(texts, "31.5", "Shown on the card")
