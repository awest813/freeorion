extends GutTest
## PediaScreen with an in-memory source.

const FakeSource := preload("res://test/unit/fake_pedia_source.gd")

var screen: PediaScreen


func before_each():
	screen = PediaScreen.new()
	screen.source = FakeSource.new()
	add_child_autofree(screen)


func test_empty_state():
	assert_eq(screen._title.text, tr("MAP_BTN_PEDIA"))
	assert_true(screen._back.disabled)


func test_open_shows_article():
	assert_true(screen.open("tech", "LRN_ALGO_ELEGANCE"))
	assert_eq(screen._title.text, tr("LRN_ALGO_ELEGANCE"))
	assert_not_null(screen._icon.texture)
	assert_string_contains(screen._text.get_parsed_text(), "Hegira β I")
	assert_eq(screen._facts.get_child_count(), 6, "Three label/value pairs")
	assert_eq(screen._links.get_child_count(), 1, "Only an Unlocks row")


func test_unknown_article_is_refused():
	assert_false(screen.open("tech", "NO_SUCH_TECH"))
	assert_eq(screen.current(), [])


func test_links_navigate_with_history():
	screen.open("tech", "LRN_ALGO_ELEGANCE")
	var unlock := _link_button(tr("LRN_PHYS_BRAIN"))
	unlock.pressed.emit()
	assert_eq(screen.current(), ["tech", "LRN_PHYS_BRAIN"])
	assert_false(screen._back.disabled)
	screen.back()
	assert_eq(screen.current(), ["tech", "LRN_ALGO_ELEGANCE"])
	assert_eq(screen._title.text, tr("LRN_ALGO_ELEGANCE"))
	screen.forward()
	assert_eq(screen.current(), ["tech", "LRN_PHYS_BRAIN"])
	assert_true(screen._forward.disabled)


func test_text_links():
	screen.open("tech", "LRN_ALGO_ELEGANCE")
	screen._text.meta_clicked.emit("fo://tech/LRN_PHYS_BRAIN")
	assert_eq(screen.current(), ["tech", "LRN_PHYS_BRAIN"], "Article link opens in place")
	watch_signals(screen)
	screen._text.meta_clicked.emit("fo://planet/12")
	assert_signal_emitted_with_parameters(screen, "link_activated", ["planet", "12"])


func test_search_lists_matches():
	screen.search(tr("LRN_PHYS_BRAIN").substr(0, 6))
	await wait_process_frames(1)
	var titles := screen._results.get_children().map(func(b): return b.text)
	assert_has(titles, tr("LRN_PHYS_BRAIN"))
	assert_does_not_have(titles, tr("BLD_SHIPYARD_BASE"))
	screen._results.get_child(0).pressed.emit()
	assert_eq(screen.current()[0], "tech")


func test_browse_by_kind():
	screen.browse("")
	await wait_process_frames(1)
	var kinds := screen._results.get_children().map(func(b): return b.text)
	assert_eq(kinds.size(), 2, "Tech and building kinds")
	assert_string_contains(kinds[0], "(2)")
	screen.browse("tech")
	await wait_process_frames(1)
	var titles := screen._results.get_children().map(func(b): return b.text)
	assert_eq(titles.size(), 3, "Back button and both techs")
	assert_has(titles, tr("LRN_ALGO_ELEGANCE"))


func test_search_without_matches():
	screen.search("zzzzzz")
	await wait_process_frames(1)
	assert_eq(screen._results.get_child(0).text, tr("PEDIA_NO_RESULTS"))


func test_shell_routes_content_links_to_pedia():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	shell.pedia_screen.source = FakeSource.new()
	shell.feed.link_activated.emit("tech", "LRN_ALGO_ELEGANCE")
	assert_eq(shell.active_screen, "pedia")
	assert_eq(shell.pedia_screen.current(), ["tech", "LRN_ALGO_ELEGANCE"])


func _link_button(text: String) -> Button:
	for button: Button in screen._links.find_children("*", "Button", true, false):
		if button.text == text:
			return button
	return null


func test_species_likes_homeworlds_and_environments():
	screen.open("species", "SP_HUMAN")
	var likes := _link_button(tr("PLC_ALGORITHMIC_RESEARCH"))
	assert_not_null(likes)
	var unlinked := _link_button(tr("SOMETHING_UNLINKED"))
	assert_true(unlinked.disabled, "Nothing to open for an unknown kind")
	watch_signals(screen)
	_link_button("Hegira β I").pressed.emit()
	assert_signal_emitted_with_parameters(screen, "link_activated", ["planet", "2568"])
	var chips: Array = screen._environments.get_children()
	assert_eq(chips.size(), 3)
	var good: Label = chips[0].get_child(1)
	assert_eq(good.text, "%s: %s" % [tr("PT_TERRAN"), tr("PE_GOOD")])
	assert_eq(good.get_theme_color("font_color"), FOUi.tokens.positive)
	screen.open("tech", "LRN_PHYS_BRAIN")
	await wait_process_frames(1)
	assert_eq(
		screen._environments.get_children().filter(func(c): return not c.is_queued_for_deletion()),
		[],
		"Other articles have none"
	)
