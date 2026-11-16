extends GutTest
## FOHotkeys: parsing, matching with exact modifiers, rebinding.


func after_each():
	for entry in FOHotkeys.HOTKEYS:
		FOHotkeys.bind_key(entry[0], entry[2])


func _key(text: String) -> InputEventKey:
	var key := FOHotkeys.parse(text)
	key.pressed = true
	return key


func test_parse_and_describe():
	var key := FOHotkeys.parse("Shift+Ctrl+Comma")
	assert_eq(key.keycode, KEY_COMMA)
	assert_true(key.ctrl_pressed and key.shift_pressed)
	assert_false(key.alt_pressed)
	assert_eq(FOHotkeys.describe(key), "Shift+Ctrl+Comma")
	assert_eq(FOHotkeys.normalized("ctrl+shift+comma"), "Shift+Ctrl+Comma")
	assert_null(FOHotkeys.parse(""))
	assert_null(FOHotkeys.parse("Hyper+Q"), "Unknown modifier")
	var shift := InputEventKey.new()
	shift.keycode = KEY_SHIFT
	assert_eq(FOHotkeys.describe(shift), "", "A lone modifier is no binding")


func test_defaults_match_exactly():
	assert_eq(FOHotkeys.match_event(_key("F2")), "screen_production")
	assert_eq(FOHotkeys.match_event(_key("Ctrl+H")), "home")
	assert_eq(FOHotkeys.match_event(_key("H")), "", "Modifiers must match")
	assert_eq(FOHotkeys.match_event(_key("Ctrl+Enter")), "end_turn")


func test_rebind_and_conflicts():
	FOHotkeys.bind_key("home", "Ctrl+J")
	assert_eq(FOHotkeys.binding("home"), "Ctrl+J")
	assert_eq(FOHotkeys.match_event(_key("Ctrl+J")), "home")
	assert_eq(FOHotkeys.match_event(_key("Ctrl+H")), "")
	assert_eq(FOHotkeys.conflicts("home", "F2"), ["screen_production"])
	assert_eq(FOHotkeys.conflicts("home", "Ctrl+J"), [])
	FOHotkeys.bind_key("home", "")
	assert_eq(FOHotkeys.match_event(_key("Ctrl+J")), "", "Cleared")


func test_top_bar_buttons_follow_bindings():
	var bar := TopBar.new()
	bar.follow_game = false
	add_child_autofree(bar)
	var production: Button = bar._screen_buttons["production"]
	assert_string_contains(production.tooltip_text, "F2")
	assert_true(production.shortcut.matches_event(_key("F2")))
	FOHotkeys.bind_key("screen_production", "Shift+P")
	assert_true(production.shortcut.matches_event(_key("Shift+P")))
	assert_false(production.shortcut.matches_event(_key("F2")))
	assert_string_contains(production.tooltip_text, "Shift+P")


func _options_screen() -> OptionsScreen:
	var screen := OptionsScreen.new()
	screen.source = preload("res://test/unit/fake_options_source.gd").new()
	add_child_autofree(screen)
	screen.refresh()
	screen._right_tabs.current_tab = 1
	return screen


func _key_button(screen: OptionsScreen, hotkey: String) -> Button:
	for button: Button in screen._hotkey_list.find_children("*", "Button", true, false):
		if button.get_meta("hotkey", "") == hotkey:
			return button
	return null


func test_options_page_rebinds_by_key_press():
	var screen := _options_screen()
	await wait_process_frames(1)
	assert_true(screen._hotkeys.visible)
	assert_eq(screen._hotkey_list.get_child_count(), FOHotkeys.HOTKEYS.size())
	_key_button(screen, "home").pressed.emit()
	await wait_process_frames(1)
	assert_eq(_key_button(screen, "home").text, tr("OPTIONS_HOTKEY_PRESS"))
	var ctrl := InputEventKey.new()
	ctrl.keycode = KEY_CTRL
	ctrl.ctrl_pressed = true
	ctrl.pressed = true
	screen._input(ctrl)
	assert_eq(screen._capturing, "home", "Still waiting after a lone modifier")
	screen._input(_key("Ctrl+K"))
	assert_eq(FOHotkeys.binding("home"), "Ctrl+K")
	await wait_process_frames(1)
	assert_eq(_key_button(screen, "home").text, "Ctrl+K")


func test_options_page_moves_a_taken_key_and_cancels():
	var screen := _options_screen()
	screen.set_hotkey("home", "F2")
	assert_eq(FOHotkeys.binding("home"), "F2")
	assert_eq(FOHotkeys.binding("screen_production"), "", "The other shortcut lost it")
	assert_string_contains(screen._status.text, tr("HOTKEY_GODOT_PRODUCTION"))
	screen._capturing = "detection"
	var escape := _key("Escape")
	screen._input(escape)
	assert_eq(screen._capturing, "")
	assert_eq(FOHotkeys.binding("detection"), "Ctrl+D", "Esc keeps the old key")


func test_symbol_keys_show_as_symbols():
	assert_eq(FOHotkeys.display("Ctrl+Equal"), "Ctrl+=")
	assert_eq(FOHotkeys.display("Minus"), "−")
	assert_eq(FOHotkeys.display("Shift+F2"), "Shift+F2", "other keys keep their names")
