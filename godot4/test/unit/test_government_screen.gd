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
