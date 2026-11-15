extends GutTest
## In-game menu: entries, leave confirmation, and GameShell's Esc and
## load wiring (follow_game = false, no server).

var menu: GameMenu


func before_each():
	menu = GameMenu.new()
	add_child_autofree(menu)


func _esc() -> InputEventAction:
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	return escape


func test_opens_with_subtitle_and_resume_focused():
	menu.open("Terran Imperium  ·  Turn 12")
	await wait_process_frames(1)
	assert_true(menu.visible)
	assert_eq(menu._subtitle.text, "Terran Imperium  ·  Turn 12")
	assert_true(menu._resume.has_focus())


func test_save_disabled_while_turn_processes():
	menu.open("", false)
	assert_true(menu._save.disabled)
	menu.open("", true)
	assert_false(menu._save.disabled)


func test_entries_request_screens():
	watch_signals(menu)
	menu.open("")
	for button: Button in menu._entries.get_children().filter(func(c): return c is Button):
		if button.text == tr("GAME_MENU_LOAD"):
			button.pressed.emit()
	assert_signal_emitted_with_parameters(menu, "screen_requested", ["load"])


func test_leaving_needs_confirmation():
	watch_signals(menu)
	menu.open("")
	menu.request_leave("title")
	assert_false(menu._entries.visible)
	assert_true(menu._confirm.visible)
	assert_eq(menu._confirm_button.text, tr("MENU_QUIT_TO_TITLE"))
	assert_signal_not_emitted(menu, "leave_requested")
	menu._confirm_button.pressed.emit()
	assert_signal_emitted_with_parameters(menu, "leave_requested", ["title"])


func test_esc_cancels_confirmation_then_resumes():
	watch_signals(menu)
	menu.open("")
	menu.request_leave("exit")
	menu._unhandled_key_input(_esc())
	assert_eq(menu.pending_leave, "")
	assert_true(menu._entries.visible)
	assert_signal_not_emitted(menu, "resume_requested")
	menu._unhandled_key_input(_esc())
	assert_signal_emitted(menu, "resume_requested")


func test_reopening_clears_a_pending_leave():
	menu.open("")
	menu.request_leave("exit")
	menu.close()
	menu.open("")
	assert_true(menu._entries.visible)
	assert_eq(menu.pending_leave, "")


func test_shell_esc_clears_selection_then_opens_menu():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	shell._unhandled_key_input(_esc())
	assert_true(shell.game_menu.visible, "Nothing selected: Esc opens the menu")
	shell.game_menu.resume_requested.emit()
	assert_false(shell.game_menu.visible)


func test_shell_menu_load_leaves_with_the_save():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	shell.load_screen.source = preload("res://test/unit/fake_saves_source.gd").new()
	watch_signals(shell)
	shell.open_menu()
	shell.game_menu.screen_requested.emit("load")
	assert_false(shell.game_menu.visible)
	assert_true(shell.load_screen.visible)
	shell.load_screen.refresh()
	shell.load_screen._select(shell.load_screen._saves[0])
	shell.load_screen._on_action()
	assert_signal_emitted_with_parameters(
		shell, "leave_requested", ["load", "/saves/Terran_Imperium_turn_42.sav"]
	)
	assert_eq(shell.load_screen.source.calls, [], "The shell loads only after leaving")
