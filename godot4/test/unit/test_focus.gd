extends GutTest
## Keyboard focus: screens and dialogs take it, Tab cycles within them.

var shell: GameShell


func before_each():
	shell = GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(2)


func _tab(back := false) -> void:
	var key := InputEventKey.new()
	key.keycode = KEY_TAB
	key.shift_pressed = back
	key.pressed = true
	get_viewport().push_input(key)
	await wait_process_frames(1)


func _focus() -> Control:
	return get_viewport().gui_get_focus_owner()


func test_a_screen_takes_focus_and_tab_stays_off_the_map():
	shell.show_screen("production")
	await wait_process_frames(2)
	assert_true(shell.production_screen.is_ancestor_of(_focus()), "the screen has focus")
	for i in 40:
		await _tab()
		var focused := _focus()
		var allowed := (
			shell.production_screen.is_ancestor_of(focused) or shell.top_bar.is_ancestor_of(focused)
		)
		assert_true(allowed, "Tab %d stays in the screen or the top bar" % i)
		if not allowed:
			break


func test_tab_wraps_inside_the_game_menu_both_ways():
	shell.open_menu()
	await wait_process_frames(2)
	for i in 12:
		await _tab(i % 3 == 0)
		assert_true(shell.game_menu.is_ancestor_of(_focus()), "focus stays in the menu")


func test_a_dialog_keeps_focus():
	var dialog := FODialog.open_on(
		shell, "Delete", "Sure?", [["Delete", "DangerButton"], ["Cancel", "GhostButton"]]
	)
	await wait_process_frames(2)
	for i in 5:
		await _tab()
		assert_true(dialog.is_ancestor_of(_focus()), "focus stays in the dialog")
	dialog.queue_free()
