extends GutTest
## Title (Continue, Pedia), options (language, fullscreen) and galaxy setup
## (random seed).

const FakeOptions := preload("res://test/unit/fake_options_source.gd")


func _buttons(screen: TitleScreen) -> Array:
	return screen._menu.get_children().filter(func(c): return c is Button and c.visible)


func test_continue_leads_when_there_are_saves():
	var title := TitleScreen.new()
	add_child_autofree(title)
	title.set_content_ready(true)
	assert_false(title._continue.visible, "hidden without saves")
	title.set_can_continue(true)
	var first: Button = _buttons(title)[0]
	assert_eq(first.text, tr("INTRO_BTN_CONTINUE"))
	assert_eq(first.theme_type_variation, "PrimaryButton")
	assert_eq(title._new_game.theme_type_variation, "", "one primary button")
	watch_signals(title)
	first.pressed.emit()
	assert_signal_emitted(title, "continue_requested")


func test_pedia_on_the_title():
	var title := TitleScreen.new()
	add_child_autofree(title)
	title.set_content_ready(true)
	watch_signals(title)
	for button: Button in _buttons(title):
		if button.text == tr("MAP_BTN_PEDIA"):
			button.pressed.emit()
	assert_signal_emitted(title, "pedia_requested")


func test_language_picker():
	var screen := OptionsScreen.new()
	var fake := FakeOptions.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	assert_eq(screen._language.item_count, 3)
	assert_eq(screen._language.get_item_metadata(screen._language.selected), "en")
	screen._language.select(0)
	screen._language.item_selected.emit(0)
	assert_eq(fake.language, "de")
	assert_eq(screen._status.text, tr("OPTIONS_LANGUAGE_CHANGED"))


func test_fullscreen_switch_is_remembered():
	var screen := OptionsScreen.new()
	var fake := FakeOptions.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	assert_false(screen._fullscreen.button_pressed)
	screen._fullscreen.button_pressed = true
	assert_true(fake.get_value(FOWindow.OPTION_FULLSCREEN))
	assert_true(fake.committed)
	# The window's own options aren't listed among the others.
	screen._search.text = "video.windowed"
	screen._refresh_list()
	var texts := screen._list.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_false(texts.any(func(t): return t.begins_with("video.windowed")))


func test_random_seed():
	var first := GalaxySetupScreen.random_seed()
	assert_eq(first.length(), 8)
	var seeds := {}
	for i in 20:
		seeds[GalaxySetupScreen.random_seed()] = true
	assert_gt(seeds.size(), 15, "seeds differ")
	var setup := GalaxySetupScreen.new()
	setup.source = FakeOptions.new()
	add_child_autofree(setup)
	var edit: LineEdit = setup._editors["setup.seed"]
	var roll: Button = edit.get_parent().get_child(1)
	roll.pressed.emit()
	assert_eq(edit.text.length(), 8)
