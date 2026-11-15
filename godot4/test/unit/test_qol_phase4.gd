extends GutTest
## Quality of life, phase 4: the system panel waits while a drop-down is
## open, server errors that don't end the game are logged with a toast,
## and the toast goes away by itself.

const SystemPanelTest := preload("res://test/unit/test_system_panel.gd")


func test_system_panel_waits_while_a_dropdown_is_open():
	var panel := SystemPanel.new()
	add_child_autofree(panel)
	panel.show_data(SystemPanelTest.SAMPLE)
	panel.system_id = 5
	await wait_process_frames(1)
	var pickers := panel.find_children("*", "OptionButton", true, false)
	assert_false(pickers.is_empty(), "The focus picker")
	var picker: OptionButton = pickers[0]
	picker.show_popup()
	await wait_process_frames(1)
	panel.refresh()
	assert_true(is_instance_valid(picker) and picker.is_inside_tree(), "Not rebuilt under it")
	assert_true(picker.get_popup().popup_hide.is_connected(panel.refresh), "Refreshes on close")
	picker.get_popup().hide()


func test_errors_that_dont_end_the_game_are_logged_with_a_toast():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(2)
	var log: MessageLog = shell.find_children("*", "MessageLog", false, false)[0]
	log.server_error("Out of sync", false)
	assert_eq(log.toast.text(), "Out of sync")
	assert_string_contains(str(shell.chat_window.events.back()["text"]), "Out of sync")
	assert_eq(shell.find_children("*", "FODialog", true, false).size(), 0, "No dialog")
	log.server_error("Gone", true)
	assert_eq(shell.find_children("*", "FODialog", true, false).size(), 1, "Fatal: a dialog")


func test_toast_goes_away_and_clicks_through():
	var toast := Toast.new()
	add_child_autofree(toast)
	toast.show_text("Hello")
	assert_true(toast.visible)
	await wait_process_frames(1)
	toast.position = Vector2(-2000, -2000)  # Not under the pointer.
	toast._process(Toast.SHOW_SECONDS + 1.0)
	assert_false(toast.visible, "Gone by itself")
	toast.show_text("Again")
	watch_signals(toast)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	toast._gui_input(click)
	assert_signal_emitted(toast, "pressed")
	assert_false(toast.visible)
