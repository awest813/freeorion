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
	screen._search.text = "detection"
	screen._search.text_changed.emit("detection")
	await wait_process_frames(1)
	assert_eq(_row_names(), ["ui.detection.legend.shown"])


func test_bool_editor():
	var row := _row("ui.detection.legend.shown")
	row.find_children("*", "CheckBox", true, false)[0].button_pressed = true
	assert_eq(fake.get_value("ui.detection.legend.shown"), true)


func test_invalid_number_is_reverted():
	var spin: SpinBox = _row("save.auto.file.limit").find_children("*", "SpinBox", true, false)[0]
	spin.value = 3
	assert_eq(fake.get_value("save.auto.file.limit"), 150, "Rejected")
	assert_eq(spin.value, 150.0, "Editor reverted")
	assert_eq(screen._status.text, tr("OPTIONS_INVALID").replace("%1%", "save.auto.file.limit"))
	spin.value = 300
	assert_eq(fake.get_value("save.auto.file.limit"), 300)


func test_reset_only_when_changed():
	var reset := _button(_row("save.format.binary"), "↺")
	assert_false(reset.disabled)
	assert_true(_button(_row("ui.detection.legend.shown"), "↺").disabled)
	reset.pressed.emit()
	assert_true(fake.is_default("save.format.binary"))


func test_readable_titles_under_sections():
	assert_eq(OptionsScreen.option_title("save.auto.hostless.enabled"), "Auto hostless")
	assert_eq(OptionsScreen.option_title("network.discovery.port"), "Discovery port")
	assert_eq(OptionsScreen.option_title("log-level"), "Log level")
	assert_eq(OptionsScreen.option_title("effects.ui.threads"), "UI threads")
	assert_eq(OptionsScreen.option_section("log-level"), tr("OPTIONS_SECTION_GENERAL"))
	assert_eq(OptionsScreen.option_section("save.auto.file.limit"), "Save")
	var headings := screen._list.get_children().filter(func(n): return n is Label)
	assert_gt(headings.size(), 0, "Sections have headings")


func test_save_commits():
	_button(screen, tr("SAVE")).pressed.emit()
	assert_true(fake.committed)
	assert_eq(screen._status.text, tr("OPTIONS_SAVED"))


func _row_names() -> Array:
	var names := []
	for row in screen._list.get_children():
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() > 1:
			names.push_back(labels[0].tooltip_text)  # the option's own name
	return names


func _row(option: String) -> Node:
	for row in screen._list.get_children():
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() > 0 and labels[0].tooltip_text == option:
			return row
	return null


func _button(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null


func test_launch_flags_and_other_screens_options_hidden():
	for option in ["continue", "load", "quickstart", "setup.rules.RULE_X", "ui.map.minimap.shown"]:
		assert_true(OptionsScreen._is_hidden(option), option)
	assert_false(OptionsScreen._is_hidden("save.format.binary"))
