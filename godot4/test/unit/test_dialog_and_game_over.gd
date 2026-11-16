extends GutTest
## FODialog and the shell's victory / defeat announcements.

var chosen: Array = []


func before_each():
	chosen = []


func _dialogs(parent: Node) -> Array:
	return parent.get_children().filter(
		func(c): return c is FODialog and not c.is_queued_for_deletion()
	)


func test_dialog_runs_the_chosen_action_and_closes():
	var host := Control.new()
	add_child_autofree(host)
	var dialog := FODialog.open_on(
		host,
		"Title",
		"Message",
		[["Yes", "PrimaryButton", func(): chosen.push_back("yes")], ["No", ""]]
	)
	assert_eq(dialog._title.text, "Title")
	assert_eq(dialog._row.get_child_count(), 2)
	dialog._row.get_child(0).pressed.emit()
	assert_eq(chosen, ["yes"])
	assert_eq(_dialogs(host).size(), 0)


func test_escape_presses_the_last_button():
	var host := Control.new()
	add_child_autofree(host)
	var dialog := FODialog.open_on(
		host,
		"T",
		"M",
		[
			["Quit", "", func(): chosen.push_back("quit")],
			["Stay", "", func(): chosen.push_back("stay")]
		]
	)
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	dialog._unhandled_key_input(escape)
	assert_eq(chosen, ["stay"])


func test_victory_is_announced_once():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	shell.check_game_over({"won": false})
	assert_eq(_dialogs(shell).size(), 0)
	shell.check_game_over({"won": true})
	var dialogs := _dialogs(shell)
	assert_eq(dialogs.size(), 1)
	assert_eq(dialogs[0]._title.text, tr("GAME_OVER_VICTORY_TITLE"))
	dialogs[0].choose(1)
	shell.check_game_over({"won": true})
	assert_eq(_dialogs(shell).size(), 0, "Not again")


func test_defeat_offers_quitting_to_the_title():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	watch_signals(shell)
	shell.check_game_over({"eliminated": true})
	var dialog: FODialog = _dialogs(shell)[0]
	assert_eq(dialog._message.text, tr("GAME_OVER_DEFEAT"))
	dialog.choose(0)
	assert_signal_emitted_with_parameters(shell, "leave_requested", ["title", ""])


func test_already_over_when_loaded_is_not_announced():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	shell.check_game_over({"won": true}, true)
	shell.check_game_over({"won": true})
	assert_eq(_dialogs(shell).size(), 0)


func test_game_over_shows_the_outcome_and_what_the_empire_came_to():
	var dialog := GameOver.open(
		self,
		"won",
		{"name": "Terran Union", "color": Color.CYAN},
		120,
		{"planets": 14, "ships": 52, "population": 230.5},
		Callable()
	)
	var texts := []
	var verdict: Label
	for label: Label in dialog.find_children("*", "Label", true, false):
		texts.push_back(label.text)
		if label.theme_type_variation == "DisplayTitle":
			verdict = label
	assert_has(texts, "Terran Union")
	var stats := {"planets": 14, "ships": 52, "population": 230.5}
	assert_has(texts, GameOver.summary(120, stats))
	assert_eq(verdict.text, tr("GAME_OVER_VICTORY_TITLE"))
	assert_true(verdict.uppercase)
	dialog.queue_free()
