extends GutTest
## OptionsScreen with an in-memory source.

const FakeSource := preload("res://test/unit/fake_options_source.gd")

var screen: OptionsScreen
var fake: RefCounted


func before_each():
	screen = OptionsScreen.new()
	fake = FakeSource.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)


func test_interface_controls_reflect_values():
	assert_eq(screen._scale.selected, 0, "Automatic")
	assert_eq(screen._theme.selected, 0)
	assert_false(screen._motion.button_pressed)


func test_interface_controls_apply():
	var index := OptionsScreen.SCALE_STEPS.find(1.5) + 1
	screen._scale.select(index)
	screen._scale.item_selected.emit(index)
	assert_eq(fake.get_value("ui.scale"), "1.5")
	screen._theme.item_selected.emit(1)
	assert_eq(fake.get_value("ui.theme"), "high_contrast")
	screen._motion.button_pressed = true
	assert_eq(fake.get_value("ui.reduce-motion"), true)


func test_list_and_search():
	assert_eq(_row_names().size(), 3, "Interface options are not repeated")
	screen._search.text = "music"
	screen._search.text_changed.emit("music")
	await wait_process_frames(1)
	assert_eq(_row_names(), ["audio.music.enabled"])


func test_bool_editor():
	var row := _row("audio.music.enabled")
	row.find_children("*", "CheckBox", true, false)[0].button_pressed = false
	assert_eq(fake.get_value("audio.music.enabled"), false)


func test_invalid_number_is_reverted():
	var spin: SpinBox = _row("setup.star.count").find_children("*", "SpinBox", true, false)[0]
	spin.value = 3
	assert_eq(fake.get_value("setup.star.count"), 150, "Rejected")
	assert_eq(spin.value, 150.0, "Editor reverted")
	assert_eq(screen._status.text, tr("OPTIONS_INVALID").replace("%1%", "setup.star.count"))
	spin.value = 300
	assert_eq(fake.get_value("setup.star.count"), 300)


func test_reset_only_when_changed():
	var reset := _button(_row("save.format.binary"), "↺")
	assert_false(reset.disabled)
	assert_true(_button(_row("audio.music.enabled"), "↺").disabled)
	reset.pressed.emit()
	assert_true(fake.is_default("save.format.binary"))


func test_save_commits():
	_button(screen, tr("SAVE")).pressed.emit()
	assert_true(fake.committed)
	assert_eq(screen._status.text, tr("OPTIONS_SAVED"))


func _row_names() -> Array:
	var names := []
	for row in screen._list.get_children():
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() > 1:
			names.push_back(labels[0].text)
	return names


func _row(option: String) -> Node:
	for row in screen._list.get_children():
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() > 0 and labels[0].text == option:
			return row
	return null


func _button(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null
