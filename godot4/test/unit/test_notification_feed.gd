extends GutTest
## NotificationFeed with fixed entries.

const ENTRIES := [
	{
		"text": "New colony on <planet 12>Hegira β II</planet>.",
		"icon": "icons/sitrep/planet_colonized.png",
		"label": "SITREP_PLANET_COLONIZED",
	},
	{
		"text": "Researched <tech SHP_ZORTRIUM_PLATE>Zortrium Armor</tech>.",
		"icon": "icons/sitrep/tech_researched.png",
		"label": "SITREP_TECH_RESEARCHED",
	},
]

var feed: NotificationFeed


func before_each():
	feed = NotificationFeed.new()
	feed.follow_game = false
	add_child_autofree(feed)


func test_shows_entries_with_header():
	feed.show_entries(ENTRIES, 7)
	await wait_process_frames(1)
	assert_true(feed.visible)
	assert_eq(feed._list.get_child_count(), 2)
	assert_string_contains(feed._header.text, "7")
	assert_string_contains(feed._header.text, "2")
	var text: RichTextLabel = feed._list.get_child(0).get_child(1)
	assert_eq(text.get_parsed_text(), "New colony on Hegira β II.")


func test_empty_turn_hides_feed():
	feed.show_entries(ENTRIES, 7)
	feed.show_entries([], 8)
	assert_false(feed.visible)


func test_header_collapses_and_expands():
	feed.show_entries(ENTRIES, 7)
	assert_true(feed.is_expanded())
	feed._header.pressed.emit()
	assert_false(feed.is_expanded())
	assert_string_contains(feed._header.text, "▸")
	feed._header.pressed.emit()
	assert_true(feed.is_expanded())


func test_object_links_are_emitted():
	feed.show_entries(ENTRIES, 7)
	watch_signals(feed)
	feed._on_meta_clicked("fo://planet/12")
	assert_signal_emitted_with_parameters(feed, "link_activated", ["planet", "12"])


func test_eta_text():
	assert_eq(GameShell.eta_text(0), "", "Not moving")
	assert_eq(GameShell.eta_text(1), tr("MAP_ROUTE_ETA_ONE"))
	assert_eq(GameShell.eta_text(4), tr("MAP_ROUTE_ETA").replace("%1%", "4"))
	assert_eq(GameShell.eta_text(-1), tr("MAP_ROUTE_UNREACHABLE"))


func test_history_steps_through_earlier_turns():
	feed.entries_provider = func(turn: int) -> Array:
		return [{"text": "Turn %d report" % turn, "icon": "", "label": ""}] if turn != 10 else []
	feed.show_entries(ENTRIES, 12)
	assert_true(feed._next.disabled, "Already at the latest turn")
	feed._prev.pressed.emit()
	assert_eq(feed._turn, 11)
	assert_eq(feed._entries[0]["text"], "Turn 11 report")
	feed._prev.pressed.emit()
	assert_true(feed.visible, "A quiet past turn keeps the feed open")
	assert_eq(feed._entries, [])
	feed._next.pressed.emit()
	feed._next.pressed.emit()
	assert_eq(feed._turn, 12)
	assert_true(feed._next.disabled)
	feed.show_turn(0)
	assert_eq(feed._turn, 1, "Clamped to the first turn")
	assert_true(feed._prev.disabled)
