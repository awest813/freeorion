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
	assert_eq(_row_names().size(), 2, "Interface and gameplay options are not repeated")
	screen._search.text = "detection"
	screen._search.text_changed.emit("detection")
	await wait_process_frames(1)
	assert_eq(_row_names(), ["ui.detection.legend.shown"])


func test_bool_editor():
	var row := _row("ui.detection.legend.shown")
	row.find_children("*", "CheckButton", true, false)[0].button_pressed = true
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


func test_every_change_is_saved_at_once():
	assert_false(fake.committed)
	screen._motion.button_pressed = true
	assert_true(fake.committed, "no Save button to forget")
	assert_eq(screen._status.text, tr("OPTIONS_SAVED_AUTO"))


func _row_names() -> Array:
	var names := []
	for row in screen._list.get_children():
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() > 1:
			names.push_back(labels[0].tooltip_text)  # the option's own name
	return names


func _row(option: String) -> Node:
	for row in screen._list.get_children() + screen._gameplay_list.get_children():
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() > 0 and labels[0].tooltip_text == option:
			return row
	return null


func _button(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		# Interface glyphs move to the "glyph" meta (FOUi.adopt_glyph()).
		if button.get_meta("glyph", button.text) == text:
			return button
	return null


func test_launch_flags_and_other_screens_options_hidden():
	for option in ["continue", "load", "quickstart", "setup.rules.RULE_X", "ui.map.minimap.shown"]:
		assert_true(OptionsScreen._is_hidden(option), option)
	assert_false(OptionsScreen._is_hidden("save.format.binary"))


func test_pages_gameplay_first_and_advanced_apart():
	assert_true(screen._pages[OptionsScreen.Page.DISPLAY].visible, "Display shows first")
	screen.show_page(OptionsScreen.Page.GAMEPLAY)
	assert_true(screen._gameplay.visible)
	assert_false(screen._all_options.visible)
	var gameplay := _row("save.auto.file.limit")
	assert_not_null(gameplay, "the autosave limit is a gameplay option")
	assert_eq(gameplay.get_parent(), screen._gameplay_list)
	var title: Label = gameplay.find_children("*", "Label", true, false)[0]
	assert_eq(title.text, tr("OPTIONS_GAME_AUTOSAVE_KEEP"), "in plain words")
	screen.show_page(OptionsScreen.Page.ADVANCED)
	assert_true(screen._all_options.visible)
	assert_false(screen._gameplay.visible)
	assert_eq(screen._right_tabs.current_tab, OptionsScreen.Page.ADVANCED)


func test_display_page_offers_what_fits():
	assert_gt(screen._window_size.item_count, 0, "window sizes listed")
	assert_eq(screen._fps_cap.item_count, FOWindow.FPS_STEPS.size())
	screen._fps_cap.item_selected.emit(FOWindow.FPS_STEPS.find(60))
	assert_eq(fake.get_value(FOWindow.OPTION_FPS_LIMITED), true)
	assert_eq(fake.get_value(FOWindow.OPTION_FPS_MAX), 60)
	screen._fps_cap.item_selected.emit(FOWindow.FPS_STEPS.find(0))
	assert_eq(fake.get_value(FOWindow.OPTION_FPS_LIMITED), false, "no limit")


func test_volumes_show_their_percentage_and_apply_while_dragged():
	var music: HSlider = screen._audio[0][1]
	music.value = 255
	var percent: Label = music.get_parent().get_child(1)
	assert_eq(percent.text, "100%")
	assert_eq(fake.get_value("audio.music.volume"), 255, "applied as it moves")
