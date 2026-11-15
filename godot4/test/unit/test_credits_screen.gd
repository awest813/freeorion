extends GutTest
## CreditsScreen reading the content's credits.xml.

var credits_xml := ProjectSettings.globalize_path("res://").path_join("../default/credits.xml")


func test_reads_groups_people_and_resources():
	var groups := CreditsScreen.read_credits(credits_xml)
	assert_gt(groups.size(), 3)
	assert_eq(groups[0]["name"], "LEAD")
	assert_has(groups[0]["lines"], "Geoff Topping (Geoff the Medio) — Programming, Design")
	assert_has(groups[0]["lines"], "Vezzra — Release Management, Design", "Nick only")
	var resources := groups.filter(
		func(g):
			return g["lines"].size() > 0 and g["lines"][0].contains(tr("INTRO_CREDITS_LICENSE"))
	)
	assert_gt(resources.size(), 0, "Third-party resources with their licence")


func test_missing_file_gives_nothing():
	assert_eq(CreditsScreen.read_credits("/no/such/credits.xml"), [])


func test_screen_lists_them():
	var screen := CreditsScreen.new()
	screen.credits_path = credits_xml
	add_child_autofree(screen)
	screen.refresh()
	var labels := screen.find_children("*", "Label", true, false)
	assert_gt(labels.size(), 100)


func test_title_offers_credits_and_website():
	var title := TitleScreen.new()
	add_child_autofree(title)
	watch_signals(title)
	for button: Button in title.find_children("*", "Button", true, false):
		if button.text == tr("TITLE_ABOUT"):
			button.pressed.emit()
	assert_signal_emitted(title, "credits_requested")
	var links := title.find_children("*", "LinkButton", true, false)
	assert_eq(links.size(), 1)
	assert_eq(links[0].uri, TitleScreen.WEBSITE)


func test_about_tabs():
	var screen := CreditsScreen.new()
	screen.license_path = ProjectSettings.globalize_path("res://").path_join("../default/COPYING")
	add_child_autofree(screen)
	screen.show_tab(1)
	assert_eq(_texts(screen)[-1], tr("FREEORION_VISION"))
	screen.show_tab(2)
	await wait_process_frames(1)
	assert_string_contains(_texts(screen)[-1], "GNU GENERAL PUBLIC LICENSE")
	screen.show_tab(3)
	await wait_process_frames(1)
	var godot := "\n".join(_texts(screen))
	assert_string_contains(godot, "Godot Engine")
	assert_string_contains(godot, Engine.get_license_text().substr(0, 40))


func _texts(screen: CreditsScreen) -> Array:
	return (
		screen
		. _list
		. get_children()
		. filter(func(c): return c is Label and not c.is_queued_for_deletion())
		. map(func(l): return l.text)
	)
