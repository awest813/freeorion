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
	# The start page: a tile per kind of article, with its picture.
	assert_true(screen._tiles.visible)
	assert_gt(screen._tiles.get_child_count(), 0)
	var tile: Button = screen._tiles.get_child(0)
	assert_not_null(tile.icon)
	tile.pressed.emit()
	assert_gt(screen._results.get_child_count(), 1, "Lists that kind")


func test_open_shows_article():
	assert_true(screen.open("tech", "LRN_ALGO_ELEGANCE"))
	assert_eq(screen._title.text, tr("LRN_ALGO_ELEGANCE"))
	assert_not_null(screen._icon.texture)
	assert_string_contains(screen._text.get_parsed_text(), "Hegira β I")
	assert_eq(screen._facts.get_child_count(), 8, "Three facts and an Unlocks row, in pairs")


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
	screen._text.meta_clicked.emit("fo://planet/99")
	assert_signal_emitted_with_parameters(screen, "link_activated", ["planet", "99"])
	screen._text.meta_clicked.emit("fo://planet/12")
	assert_eq(screen.current(), ["planet", "12"], "Objects with an article open in the Pedia")
	assert_true(screen._on_map.visible)
	screen._on_map.pressed.emit()
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
	assert_eq(kinds.size(), 3, "Tech, building and design kinds")
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


func _link_button(text: String) -> BaseButton:
	for button: BaseButton in screen._facts.find_children("*", "BaseButton", true, false):
		if button.text == text:
			return button
	return null


func test_species_likes_homeworlds_and_environments():
	screen.open("species", "SP_HUMAN")
	var likes := _link_button(tr("PLC_ALGORITHMIC_RESEARCH"))
	assert_not_null(likes)
	assert_null(_link_button(tr("SOMETHING_UNLINKED")), "Nothing to open for an unknown kind")
	var texts := screen._facts.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_has(texts, tr("SOMETHING_UNLINKED"), "Named all the same")
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


func test_design_article_groups_and_requirements():
	screen.open("shipdesign", "7")
	assert_eq(screen._title.text, "Frigate Ms")
	assert_false(screen._on_map.visible)
	assert_not_null(_link_button(tr("SH_BASIC_MEDIUM")))
	assert_not_null(_link_button(tr("SHP_MIL_ROBO_CONT")))
	var groups := screen._facts.find_children("*", "Label", true, false).map(func(l): return l.text)
	assert_has(groups, tr("PEDIA_LINKS_UNLOCKED_BY"))
	assert_has(groups, tr("PEDIA_LINKS_PARTS"))
	assert_string_contains(screen._text.get_parsed_text(), "a planet with a shipyard")


func test_labelled_entries_and_full_text_search():
	screen.browse("shipdesign")
	await wait_process_frames(1)
	var titles := screen._results.get_children().map(func(b): return b.text)
	assert_has(titles, "Frigate Ms", "Designs listed by name, not ID")
	screen.search("physically")
	await wait_process_frames(1)
	titles = screen._results.get_children().map(func(b): return b.text)
	assert_eq(titles.size(), 1)
	assert_string_contains(titles[0], tr("PEDIA_IN_TEXT"))
	assert_false(PediaScreen.is_article_kind("planet"), "Map links stay on the map")
	assert_true(PediaScreen.is_article_kind("metertype"))


func test_meter_names_link_to_their_articles():
	var grid := MeterGrid.new()
	add_child_autofree(grid)
	grid.fill([{"meter": "METER_INDUSTRY", "now": 4.0, "next": 5.0}])
	watch_signals(grid)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	grid.get_child(1).gui_input.emit(click)
	assert_signal_emitted_with_parameters(grid, "meter_clicked", ["METER_INDUSTRY"])


func test_start_page_lists_content_read_after_it_was_built():
	screen.hide()
	screen.source.index.push_back({"kind": "monsterdesign", "name": "SM_LATE"})
	screen.show()
	await wait_process_frames(1)
	var texts: Array = screen._tiles.get_children().map(func(tile): return tile.text)
	assert_true(
		texts.has(tr("PEDIA_KIND_MONSTERDESIGN") + "\n1"), "the tiles are refreshed on showing"
	)


func test_search_results_with_the_same_name_say_their_kind():
	var matches := [
		["Armor Plating", {"kind": "shippart", "name": "AR_STD_PLATE"}],
		["Armor Plating", {"kind": "tech", "name": "SHP_ZORTRIUM_PLATE"}],
		["Zortrium", {"kind": "tech", "name": "X"}],
	]
	PediaScreen._name_kinds_of_twins(matches)
	assert_eq(matches[0][0], "Armor Plating  ·  " + tr("PEDIA_KIND_SHIPPART"))
	assert_eq(matches[1][0], "Armor Plating  ·  " + tr("PEDIA_KIND_TECH"))
	assert_eq(matches[2][0], "Zortrium", "unique names stay as they are")


func test_a_long_link_list_counts_itself_in_its_caption():
	var links: Array = screen.source.articles["shipdesign/7"]["links"]
	for part in ["AR_STD_PLATE", "DT_DETECTOR_1", "SH_DEFENSE_GRID"]:
		links.push_back({"kind": "shippart", "name": part, "group": "parts"})
	screen.open("shipdesign", "7")
	var captions := screen._facts.find_children("*", "Label", true, false).map(
		func(l): return l.text
	)
	assert_has(captions, tr("PEDIA_LINKS_PARTS") + " (4)")
	assert_has(captions, tr("PEDIA_LINKS_HULL"), "A short list is not counted")
