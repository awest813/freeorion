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
