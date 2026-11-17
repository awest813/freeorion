extends GutTest
## FOAudio: button sounds, options, and the options screen's sound controls.

var saved := {}


func before_each():
	saved = {
		"effects": FOAudio.effects_enabled,
		"volume": FOAudio.effects_volume,
		"music": FOAudio.music_enabled,
	}
	FOAudio.effects_enabled = true
	FOAudio.effects_volume = 255


func after_each():
	FOAudio.effects_enabled = saved["effects"]
	FOAudio.effects_volume = saved["volume"]
	FOAudio.music_enabled = saved["music"]
	FOAudio._apply_music()


func test_buttons_click():
	var button := Button.new()
	add_child_autofree(button)
	var before: int = FOAudio.played_count
	button.pressed.emit()
	assert_eq(FOAudio.played_count, before + 1, "A click was played")
	assert_eq(FOAudio.last_sound, "click")


func test_silent_buttons_and_disabled_effects():
	var button := Button.new()
	button.set_meta("sound", "")
	add_child_autofree(button)
	var before: int = FOAudio.played_count
	button.pressed.emit()
	assert_eq(FOAudio.played_count, before)
	FOAudio.effects_enabled = false
	FOAudio.play("click")
	assert_eq(FOAudio.played_count, before)


func test_music_follows_its_option():
	FOAudio._take(FOAudio.OPTION_MUSIC, false)
	FOAudio._apply_music()
	assert_false(FOAudio.is_music_playing())
	assert_almost_eq(FOAudio.volume_db(255), 0.0, 0.01)
	assert_lt(FOAudio.volume_db(64), -10.0)


func test_options_screen_sound_controls():
	var screen := OptionsScreen.new()
	screen.source = preload("res://test/unit/fake_options_source.gd").new()
	add_child_autofree(screen)
	screen.refresh()
	var effects: Array = screen._audio[1]
	assert_false(effects[0].button_pressed)
	assert_false(effects[1].editable, "No volume while sounds are off")
	assert_eq(effects[1].value, 200.0)
	effects[0].button_pressed = true
	assert_true(screen.source.get_value("audio.effects.enabled"))
	assert_true(effects[1].editable)
	var listed := screen._list.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_does_not_have(listed, "audio.music.volume", "Sound options have their own controls")


func test_lists_dropdowns_panels_and_the_map_sound():
	var list := ItemList.new()
	list.add_item("a")
	add_child_autofree(list)
	list.item_selected.emit(0)
	assert_eq(FOAudio.last_sound, "list_select")
	var pick := OptionButton.new()
	add_child_autofree(pick)
	pick.pressed.emit()
	assert_eq(FOAudio.last_sound, "pulldown")
	var panel := FleetPanel.new()
	add_child_autofree(panel)
	panel.visible = true
	panel.visible = false
	assert_eq(FOAudio.last_sound, "close")
	panel.visible = true
	assert_eq(FOAudio.last_sound, "open")
	var view: Node = load("res://map/GalaxyMapView.tscn").instantiate()
	view.follow_game = false
	add_child_autofree(view)
	var map: GalaxyMap = view.map
	map.fleet_hovered.emit(5)
	assert_eq(FOAudio.last_sound, "fleet_rollover")
	map.system_hovered.emit(3)
	assert_eq(FOAudio.last_sound, "system_rollover")
	var before: int = FOAudio.played_count
	map.system_hovered.emit(-1)
	assert_eq(FOAudio.played_count, before, "Leaving a system is silent")
	map.fleet_clicked.emit(5)
	assert_eq(FOAudio.last_sound, "fleet_click")


func test_music_opens_up_in_war():
	assert_false(FOAudio.is_tense(), "calm to begin with")
	FOAudio.set_tension(true)
	await wait_seconds(FOAudio.TENSION_SECONDS + 0.3)
	assert_true(FOAudio.is_tense())
	FOAudio.set_tension(false)
	await wait_seconds(FOAudio.TENSION_SECONDS + 0.3)
	assert_false(FOAudio.is_tense(), "settles back in peace")


func test_master_volume_sets_the_master_bus():
	FOAudio._take(FOAudio.OPTION_MASTER_VOLUME, 64)
	FOAudio._apply_music()
	assert_almost_eq(AudioServer.get_bus_volume_db(0), FOAudio.volume_db(64), 0.01)
	FOAudio._take(FOAudio.OPTION_MASTER_VOLUME, 255)
	FOAudio._apply_music()
	assert_almost_eq(AudioServer.get_bus_volume_db(0), 0.0, 0.01)


func test_a_new_focus_has_its_sound():
	assert_eq(FOAudio.focus_sound("FOCUS_INDUSTRY"), "focus_industry")
	assert_eq(FOAudio.focus_sound("FOCUS_RESEARCH"), "focus_research")
	assert_eq(FOAudio.focus_sound("FOCUS_INFLUENCE"), "focus", "A general one for the rest")
	var panel := SystemPanel.new()
	add_child_autofree(panel)
	panel.focus_requested.emit(12, "FOCUS_RESEARCH")
	assert_eq(FOAudio.last_sound, "focus_research")
