extends GutTest
## GovernmentScreen with an in-memory source.

const FakeSource := preload("res://test/unit/fake_government_source.gd")

var screen: GovernmentScreen
var fake: RefCounted


func before_each():
	screen = GovernmentScreen.new()
	fake = FakeSource.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)


func test_influence_and_slots():
	assert_string_contains(screen._influence.text, "23.5")
	var texts := screen._slots.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_has(texts, tr("ECONOMIC_CATEGORY"))
	assert_has(texts, tr("PLC_PLANETARY_INFRA"))
	assert_has(texts, tr("GOVERNMENT_EMPTY_SLOT"))


func test_catalog_lists_unadopted_policies():
	assert_eq(_catalog_names().size(), 4)
	assert_does_not_have(_catalog_names(), tr("PLC_PROPAGANDA"), "Adopted not listed")


func test_adopt_blocked_with_reason():
	var social := _row(tr("PLC_ALGORITHMIC_RESEARCH"))
	assert_true(_button(social, tr("GOVERNMENT_ADOPT")).disabled, "Social slots are full")
	assert_true(_detail(social).contains(tr("GOVERNMENT_NO_FREE_SLOT")))
	var poor := _row(tr("PLC_TECHNOCRACY"))
	assert_true(_detail(poor).contains(tr("GOVERNMENT_UNAFFORDABLE")))
	var excluded := _row(tr("PLC_INDUSTRIALISM"))
	assert_true(_detail(excluded).contains(tr("GOVERNMENT_BLOCKED")))


func test_adopt_into_free_slot_and_revoke():
	_button(_row(tr("PLC_CENTRALIZATION")), tr("GOVERNMENT_ADOPT")).pressed.emit()
	_button(screen._slots, "✕").pressed.emit()
	assert_eq(fake.calls, [["adopt", "PLC_CENTRALIZATION", 1], ["de_adopt", "PLC_PLANETARY_INFRA"]])


func test_category_filter():
	screen._filter.current_tab = 2
	await wait_process_frames(1)
	assert_eq(_catalog_names(), [tr("PLC_ALGORITHMIC_RESEARCH")])


func test_pedia_button():
	watch_signals(screen)
	_button(_row(tr("PLC_CENTRALIZATION")), "?").pressed.emit()
	assert_signal_emitted_with_parameters(
		screen, "pedia_requested", ["policy", "PLC_CENTRALIZATION"]
	)


func test_availability_filters():
	assert_does_not_have(_catalog_names(), tr("PLC_RACIAL_PURITY"), "Locked hidden by default")
	screen.set_shown("locked", true)
	await wait_process_frames(1)
	assert_has(_catalog_names(), tr("PLC_RACIAL_PURITY"))
	assert_true(_button(_row(tr("PLC_RACIAL_PURITY")), tr("GOVERNMENT_ADOPT")).disabled)
	screen.set_shown("adopted", true)
	await wait_process_frames(1)
	assert_has(_catalog_names(), tr("PLC_PROPAGANDA"))
	screen.set_shown("unaffordable", false)
	screen.set_shown("restricted", false)
	await wait_process_frames(1)
	assert_does_not_have(_catalog_names(), tr("PLC_TECHNOCRACY"))
	assert_does_not_have(_catalog_names(), tr("PLC_INDUSTRIALISM"))
	assert_eq(GovernmentScreen.availability(fake.policies[3]), "unaffordable")
	assert_eq(GovernmentScreen.availability(fake.policies[5]), "restricted")
	assert_eq(GovernmentScreen.availability(fake.policies[6]), "locked")


func test_tooltips():
	var adopted: String = GovernmentScreen.tooltip_for(fake.policies[0])
	assert_string_contains(adopted, tr("POLICY_ADOPTED").replace("%1%", "4.0"))
	assert_string_contains(adopted, "3")
	assert_string_contains(adopted, tr("PLC_PLANETARY_INFRA_DESC").left(20))
	var excluded: String = GovernmentScreen.tooltip_for(fake.policies[5])
	assert_string_contains(
		excluded, tr("POLICY_EXCLUDED").replace("%1%", tr("PLC_PLANETARY_INFRA"))
	)
	assert_eq(
		_row(tr("PLC_CENTRALIZATION")).tooltip_text, GovernmentScreen.tooltip_for(fake.policies[2])
	)


func test_revert():
	assert_false(screen._revert.disabled)
	screen._revert.pressed.emit()
	assert_eq(fake.calls, [["revert"]])
	fake.modified = false
	screen.refresh()
	assert_true(screen._revert.disabled)


func test_drag_and_double_click():
	var data := {"type": GovernmentScreen.POLICY_DRAG, "name": "PLC_CENTRALIZATION"}
	# Economic slot 1 is free; social policies don't fit economic slots;
	# blocked policies don't drop.
	assert_true(screen._can_drop_on_slot(data, "ECONOMIC_CATEGORY", ""))
	var social := {"type": GovernmentScreen.POLICY_DRAG, "name": "PLC_ALGORITHMIC_RESEARCH"}
	assert_false(screen._can_drop_on_slot(social, "ECONOMIC_CATEGORY", ""))
	var poor := {"type": GovernmentScreen.POLICY_DRAG, "name": "PLC_TECHNOCRACY"}
	assert_false(screen._can_drop_on_slot(poor, "ECONOMIC_CATEGORY", ""))
	screen.drop_on_slot("PLC_CENTRALIZATION", "PLC_PLANETARY_INFRA", 0)
	assert_eq(fake.calls, [["de_adopt", "PLC_PLANETARY_INFRA"], ["adopt", "PLC_CENTRALIZATION", 0]])
	fake.calls.clear()
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	_row(tr("PLC_CENTRALIZATION")).gui_input.emit(click)
	var cards := screen._slots.get_children().filter(func(c): return c is PanelContainer)
	cards[0].gui_input.emit(click)
	assert_eq(fake.calls, [["adopt", "PLC_CENTRALIZATION", 1], ["de_adopt", "PLC_PLANETARY_INFRA"]])


func _catalog_names() -> Array:
	var names := []
	for row in screen._catalog.get_children():
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() > 1:
			names.push_back(labels[0].text)
	return names


func _row(title: String) -> Node:
	for row in screen._catalog.get_children():
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() > 0 and labels[0].text == title:
			return row
	return null


func _detail(row: Node) -> String:
	return row.find_children("*", "Label", true, false)[1].text


func _button(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null


func test_dragged_policy_lights_the_slots_it_fits():
	screen.highlight_slots_for({"type": GovernmentScreen.POLICY_DRAG, "name": "PLC_CENTRALIZATION"})
	var cards := screen._slots.get_children().filter(func(c): return c.has_meta("category"))
	for card: Control in cards:
		var economic: bool = card.get_meta("category") == "ECONOMIC_CATEGORY"
		assert_almost_eq(card.modulate.a, 1.0 if economic else 0.4, 0.01, card.get_meta("category"))
		assert_eq(card.has_theme_stylebox_override("panel"), economic, "Outlined if it fits")
	screen.highlight_slots_for(null)
	assert_true(cards.all(func(c): return c.modulate.a == 1.0), "Back as usual")
