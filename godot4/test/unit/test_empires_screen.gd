extends GutTest
## EmpiresScreen with a fake source.

var screen: EmpiresScreen
var fake: RefCounted


func before_each():
	screen = EmpiresScreen.new()
	fake = preload("res://test/unit/fake_diplomacy_source.gd").new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()


func _buttons(card: Node) -> Array:
	return card.find_children("*", "Button", true, false)


func test_lists_every_empire_own_first():
	var cards := screen._list.get_children()
	assert_eq(cards.size(), 4)
	assert_eq(_buttons(cards[0]).size(), 0, "No diplomacy with yourself")


func test_status_lines():
	assert_eq(EmpiresScreen.status_text(fake.empires[0]), tr("DIPLOMACY_YOU"))
	assert_eq(
		EmpiresScreen.status_text(fake.empires[1]),
		"%s · %s" % [tr("DIPLOMACY_STATUS_WAR"), tr("DIPLOMACY_INCOMING_PEACE")]
	)
	assert_eq(
		EmpiresScreen.status_text(fake.empires[2]),
		"%s · %s" % [tr("DIPLOMACY_STATUS_PEACE"), tr("DIPLOMACY_OUTGOING_ALLIES")]
	)
	assert_eq(EmpiresScreen.status_text(fake.empires[3]), tr("DIPLOMACY_ELIMINATED"))


func test_actions_are_offered_and_sent():
	var buttons := _buttons(screen._list.get_child(1))
	assert_eq(
		buttons.map(func(b): return b.text), [tr("DIPLOMACY_ACCEPT_PEACE"), tr("DIPLOMACY_REJECT")]
	)
	buttons[0].pressed.emit()
	assert_eq(fake.calls, [[2, "accept_peace"]])
	assert_eq(screen._info.text, tr("DIPLOMACY_SENT"))


func test_refused_action_says_so():
	fake.accept = false
	_buttons(screen._list.get_child(2))[1].pressed.emit()
	assert_eq(fake.calls, [[3, "declare_war"]])
	assert_eq(screen._info.text, tr("DIPLOMACY_REFUSED"))


func test_shell_opens_options_and_save_by_key():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	var key := InputEventKey.new()
	key.keycode = KEY_F10
	key.pressed = true
	shell._unhandled_key_input(key)
	assert_eq(shell.active_screen, "options")
	assert_true(shell.top_bar._screen_buttons.has("empires"))
