extends GutTest
## Production and research extras: the unavailable filter, tooltips, the
## supply group's PP, drag and drop into and within the queues, the tech
## tree's status and category filters, tooltips, zoom buttons and
## Shift+click, and the tech list's sort orders.

const FakeProduction := preload("res://test/unit/fake_production_source.gd")
const FakeResearch := preload("res://test/unit/fake_research_source.gd")


func _production() -> Array:
	var screen := ProductionScreen.new()
	var fake: RefCounted = FakeProduction.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)
	return [screen, fake]


func _research() -> Array:
	var screen := ResearchScreen.new()
	var fake: RefCounted = FakeResearch.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)
	return [screen, fake]


func _names(catalog: Node, min_labels := 1) -> Array:
	var names := []
	for row in catalog.get_children():
		var labels := row.find_children("*", "Label", true, false)
		if labels.size() >= min_labels:
			names.push_back(labels[0].text)
	return names


func test_unavailable_filter_and_tooltips():
	var made := await _production()
	var screen: ProductionScreen = made[0]
	assert_does_not_have(_names(screen._catalog), tr("BLD_GAS_GIANT_GEN"))
	screen._filter.current_tab = ProductionScreen.FILTERS.find("unavailable")
	await wait_process_frames(1)
	assert_eq(_names(screen._catalog), [tr("BLD_GAS_GIANT_GEN")])
	var row: Node = screen._catalog.get_child(0)
	assert_string_contains(row.tooltip_text, "Needs a gas giant")
	for button: Button in row.find_children("*", "Button", true, false):
		if button.text == tr("PRODUCTION_ADD"):
			assert_true(button.disabled, "Unavailable items can't be added")
	var tip := screen.queue_tooltip({"name": "SD_SCOUT", "total_cost": 30.0, "min_turns": 3})
	assert_string_contains(tip, tr("PRODUCTION_TIP_MIN_TURNS").replace("%1%", "3"))
	assert_string_contains(tip, "10.0")


func test_group_points():
	var made := await _production()
	var screen: ProductionScreen = made[0]
	assert_string_contains(screen._group_points.text, "15.0")
	assert_string_contains(screen._group_points.text, "9.5")


func test_production_drag_and_drop():
	var made := await _production()
	var screen: ProductionScreen = made[0]
	var fake: RefCounted = made[1]
	var move := {"type": ProductionScreen.QUEUE_DRAG, "index": 1}
	assert_true(screen._can_drop_on_queue(Vector2.ZERO, move))
	assert_false(screen._can_drop_on_queue(Vector2.ZERO, {"type": "other"}))
	screen._drop_on_queue(Vector2.ZERO, move, 0)
	var item: Dictionary = fake.buildable[0]
	screen._drop_on_queue(Vector2.ZERO, {"type": ProductionScreen.CATALOG_DRAG, "item": item}, 1)
	assert_eq(fake.calls[0], ["move", 1, 0])
	assert_eq(fake.calls[1][0], "enqueue_at")
	assert_eq(fake.calls[1][-1], 1, "Dropped at the target position")


func test_tree_status_and_category_filters():
	var made := await _research()
	var screen: ResearchScreen = made[0]
	screen.show_tree(true)
	assert_eq(screen._tree.techs.size(), 6)
	screen.statuses_shown["complete"] = false
	screen._refresh_catalog()
	assert_eq(screen._tree.techs.size(), 5)
	screen.more_categories = {"LEARNING_CATEGORY": true, "GROWTH_CATEGORY": true}
	screen._refresh_catalog()
	var names: Array = screen._tree.techs.map(func(t): return t["name"])
	assert_eq(names, ["LRN_ALGO_ELEGANCE", "GRO_PLANET_ECOL"])
	assert_true(screen.category_shown("GROWTH_CATEGORY"))
	assert_false(screen.category_shown("SHIP_PARTS_CATEGORY"))


func test_tree_tooltip_zoom_and_shift_click():
	var made := await _research()
	var screen: ResearchScreen = made[0]
	var fake: RefCounted = made[1]
	screen.show_tree(true)
	await wait_process_frames(2)
	var tree: TechTreeView = screen._tree
	var tip := tree.tooltip_text_for("SHP_WEAPON_1_2")
	assert_string_contains(tip, tr("RESEARCH_STATUS_PARTIAL"))
	assert_string_contains(tip, tr("RESEARCH_TIP_NEEDS"))
	assert_string_contains(tip, tr("SHP_ZORTRIUM_PLATE"))
	var before := tree.zoom
	tree.zoom_step(1)
	assert_gt(tree.zoom, before)
	tree.zoom_step(-1)
	assert_almost_eq(tree.zoom, before, 0.01)
	tree.tech_queued.emit("PRO_ROBOTIC_PROD")
	assert_has(fake.calls, ["enqueue_at", "PRO_ROBOTIC_PROD", 0], "Shift+click: at the top")


func test_list_sorts():
	var techs: Array = FakeResearch.new().techs.duplicate()
	ResearchScreen.sort_techs(techs, "cost")
	assert_eq(techs[0]["cost"], 10.0)
	assert_eq(techs[-1]["cost"], 48.0)
	ResearchScreen.sort_techs(techs, "name")
	var names: Array = techs.map(func(t): return tr(t["name"]))
	var sorted := names.duplicate()
	sorted.sort()
	assert_eq(names, sorted)
	ResearchScreen.sort_techs(techs, "category")
	assert_eq(techs[0]["category"], "GROWTH_CATEGORY")


func test_research_drag_and_drop():
	var made := await _research()
	var screen: ResearchScreen = made[0]
	var fake: RefCounted = made[1]
	screen._drop_on_queue({"type": ResearchScreen.QUEUE_DRAG, "name": "GRO_PLANET_ECOL"}, 0)
	screen._drop_on_queue({"type": ResearchScreen.TECH_DRAG, "name": "PRO_ROBOTIC_PROD"}, 1)
	assert_eq(fake.calls[0], ["move", "GRO_PLANET_ECOL", 0])
	assert_eq(fake.calls[1], ["enqueue_at", "PRO_ROBOTIC_PROD", 1])
