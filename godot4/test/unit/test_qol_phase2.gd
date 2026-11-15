extends GutTest
## Quality of life, phase 2: fewer clicks. Double-click adds in both lists,
## Shift always means "at the top", the build location picker is grouped
## and searchable, projects have a filter, and tech tooltips say how a
## queued tech goes.

const FakeProduction := preload("res://test/unit/fake_production_source.gd")
const FakeResearch := preload("res://test/unit/fake_research_source.gd")


func _double_click() -> InputEventMouseButton:
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.double_click = true
	return click


func test_locations_grouped_by_system_with_search():
	var locations := [
		{"id": 1, "name": "Capital", "system_name": "Sol", "populated": true},
		{"id": 5, "name": "Zeta Outpost", "system_name": "Vega", "populated": false},
		{"id": 4, "name": "Vega II", "system_name": "Vega", "populated": true},
		{"id": 3, "name": "Rigel I", "system_name": "Rigel", "populated": true},
	]
	var rows := ProductionScreen.group_locations(locations)
	var shown: Array = rows.map(func(r): return r[0] if r is Array else r["name"])
	assert_eq(shown, ["Capital", "Rigel", "Rigel I", "Vega", "Vega II", "Zeta Outpost"])
	var found := ProductionScreen.group_locations(locations, "veg")
	assert_eq(found.map(func(r): return r[0] if r is Array else r["id"]), ["Vega", 4, 5])


func test_projects_filter_and_double_click_add():
	var screen := ProductionScreen.new()
	var fake: RefCounted = FakeProduction.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)
	screen._filter.current_tab = ProductionScreen.FILTERS.find("stockpile")
	await wait_process_frames(1)
	assert_eq(screen._catalog.get_child_count(), 1, "Only the stockpile project")
	screen._catalog.get_child(0).gui_input.emit(_double_click())
	assert_eq(fake.calls[-1][0], "enqueue")


func test_research_double_click_and_shift_click_go_to_the_top():
	var screen := ResearchScreen.new()
	var fake: RefCounted = FakeResearch.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)
	var row: Node = screen._catalog.get_child(screen._catalog.get_child_count() - 1)
	row.gui_input.emit(_double_click())
	assert_eq(fake.calls[-1][0], "enqueue", "Double-click queues")
	screen.show_tree(true)
	screen._tree.tech_queued.emit("PRO_ROBOTIC_PROD")
	assert_eq(fake.calls[-1], ["enqueue_at", "PRO_ROBOTIC_PROD", 0], "Shift+click: at the top")


func test_tech_tooltip_says_how_a_queued_tech_goes():
	var tech := {"name": "LRN_ALGO_ELEGANCE", "cost": 10.0, "turns": 2, "status": "researchable"}
	var entry := {"progress": 0.6, "allocated_rp": 4.5, "turns_left": 2}
	var tip := TechTreeView.describe(tech, entry)
	assert_string_contains(
		tip,
		(
			tr("RESEARCH_TIP_QUEUED")
			. replace("%1%", "60")
			. replace("%2%", "4.5")
			. replace("%3%", "5.0")
			. replace("%4%", ScreenKit.turns_text(2))
		)
	)
	assert_false(TechTreeView.describe(tech).contains("4.5"), "Not queued: no queue line")


func test_queued_tech_click_centres_the_tree():
	var screen := ResearchScreen.new()
	screen.source = FakeResearch.new()
	add_child_autofree(screen)
	screen.refresh()
	screen.show_tree(true)
	await wait_process_frames(2)
	var click := _double_click()
	click.double_click = false
	screen._queue_list.get_child(1).gui_input.emit(click)
	assert_eq(screen._tree.selected, "GRO_PLANET_ECOL")
	assert_string_contains(screen._queue_list.get_child(0).tooltip_text, tr("LRN_ALGO_ELEGANCE"))
