extends GutTest
## TitleScreen and GalaxySetupScreen without starting a game.

const FakeOptions := preload("res://test/unit/fake_options_source.gd")


func test_seasonal_art():
	assert_eq(TitleScreen.seasonal_art({"month": 4, "day": 1})[0], "splash0104.png")
	assert_eq(TitleScreen.seasonal_art({"month": 12, "day": 25})[1], "logo2512.png")
	assert_eq(TitleScreen.seasonal_art({"month": 10, "day": 31})[0], "splash3110.png")
	assert_eq(TitleScreen.seasonal_art({"month": 7, "day": 14}), ["splash.png", "logo.png"])


func test_title_menu_waits_for_content():
	var title := TitleScreen.new()
	add_child_autofree(title)
	var new_game := _button(title, tr("TITLE_NEW_GAME"))
	assert_true(new_game.disabled, "Needs content first")
	assert_false(_button(title, tr("OPTIONS_TITLE")).disabled, "Options always available")
	title.set_content_ready(true)
	assert_false(new_game.disabled)
	watch_signals(title)
	new_game.pressed.emit()
	assert_signal_emitted(title, "new_game_requested")
	title.set_busy(tr("TITLE_STARTING"))
	assert_false(title._menu.visible)


func test_setup_reads_and_writes_options():
	var setup := GalaxySetupScreen.new()
	setup.source = _setup_options()
	add_child_autofree(setup)
	setup.refresh()
	var shape: OptionButton = setup._editors["setup.galaxy.shape"]
	assert_eq(shape.get_item_metadata(shape.selected), "RING")
	assert_not_null(setup._preview.texture, "Shape preview shown")
	var stars: SpinBox = setup._editors["setup.star.count"]
	assert_eq(stars.value, 150.0)

	shape.select(GalaxySetupScreen._choice_index(shape, "CLUSTER"))
	shape.item_selected.emit(shape.selected)
	stars.value = 60
	(setup._editors["setup.empire.name"] as LineEdit).text = "Terran Union"
	watch_signals(setup)
	_button(setup, tr("TITLE_START_GAME")).pressed.emit()
	assert_signal_emitted(setup, "start_requested")
	assert_eq(setup.source.get_value("setup.galaxy.shape"), "CLUSTER")
	assert_eq(setup.source.get_value("setup.star.count"), 60)
	assert_eq(setup.source.get_value("setup.empire.name"), "Terran Union")


func test_species_and_colour():
	var setup := GalaxySetupScreen.new()
	setup.source = _setup_options()
	add_child_autofree(setup)
	setup.refresh()
	var species: OptionButton = setup._editors["setup.initial.species"]
	assert_eq(species.item_count, 3, "Two playable species and Random")
	assert_eq(species.get_item_metadata(species.selected), "SP_EGASSEM")
	assert_eq(species.get_item_metadata(2), "RANDOM")
	var swatches := setup._colors.get_children()
	assert_eq(swatches.size(), 3)
	assert_true(swatches[1].button_pressed, "The stored colour is picked")
	swatches[2].pressed.emit()
	species.select(0)
	assert_true(setup.apply())
	assert_eq(setup.source.get_value("setup.empire.color.index"), 2)
	assert_eq(setup.source.get_value("setup.initial.species"), "SP_HUMAN")


func test_star_count_field_clamps_to_range():
	var setup := GalaxySetupScreen.new()
	setup.source = _setup_options()
	add_child_autofree(setup)
	var stars: SpinBox = setup._editors["setup.star.count"]
	stars.value = 5
	assert_eq(stars.value, 10.0, "Field keeps the option's minimum")


func test_setup_refusal_keeps_screen():
	var setup := GalaxySetupScreen.new()
	var fake := _setup_options()
	fake.options["setup.star.count"]["min"] = 100  # stricter than the field
	setup.source = fake
	add_child_autofree(setup)
	setup.refresh()
	(setup._editors["setup.star.count"] as SpinBox).value = 60
	watch_signals(setup)
	_button(setup, tr("TITLE_START_GAME")).pressed.emit()
	assert_signal_not_emitted(setup, "start_requested")
	assert_string_contains(setup._status.text, "setup.star.count")


func _setup_options() -> RefCounted:
	var fake := FakeOptions.new()
	fake.options["setup.galaxy.shape"] = {"value": "RING", "default": "DISC", "description": ""}
	fake.options["setup.empire.name"] = {"value": "Empire", "default": "", "description": ""}
	fake.options["setup.galaxy.age"] = {
		"value": "GALAXY_SETUP_MEDIUM", "default": "GALAXY_SETUP_MEDIUM", "description": ""
	}
	fake.options["setup.initial.species"] = {
		"value": "SP_EGASSEM", "default": "SP_HUMAN", "description": ""
	}
	fake.options["setup.empire.color.index"] = {"value": 1, "default": 9, "description": ""}
	return fake


func _button(node: Node, text: String) -> Button:
	for button: Button in node.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null
