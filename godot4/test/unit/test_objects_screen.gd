extends GutTest
## ObjectsScreen with a fake source.

const FAKE := preload("res://test/unit/fake_objects_source.gd")

var screen: ObjectsScreen
var fake: RefCounted


func before_each():
	screen = ObjectsScreen.new()
	fake = FAKE.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()


func _column(key: String) -> Array:
	var index := -1
	var columns: Array = ObjectsScreen.COLUMNS[screen.kind]
	for i in columns.size():
		if columns[i][0] == key:
			index = i
	var values: Array = []
	for item in screen._tree.get_root().get_children():
		values.push_back(item.get_text(index))
	return values


func test_lists_own_planets_by_name():
	assert_eq(fake.calls.back(), ["planets", true])
	assert_eq(_column("name"), ["Hegira β I", "Mu Arae II"])
	assert_eq(_column("species"), [tr("SP_HUMAN"), tr("SP_HUMAN")])
	assert_eq(_column("industry"), ["15.0", "1.0"])
	assert_eq(screen._info.text, tr("OBJECTS_COUNT").replace("%1%", "2"))


func test_all_known_includes_others():
	screen._only_mine.button_pressed = false
	assert_eq(fake.calls.back(), ["planets", false])
	assert_eq(_column("name").size(), 4)


func test_sorting_by_a_number_column_starts_high():
	screen._only_mine.button_pressed = false
	screen.sort_by("population")
	assert_eq(_column("name"), ["Vega IV", "Hegira β I", "Iszm α I", "Mu Arae II"])
	assert_string_contains(screen._tree.get_column_title(5), "▼")
	screen.sort_by("population")
	assert_eq(_column("name")[0], "Mu Arae II", "Clicking again flips it")


func test_title_click_sorts():
	screen._on_column_title_clicked(6, MOUSE_BUTTON_LEFT)
	assert_eq(screen.sort_key, "industry")


func test_search_filters_by_text_columns():
	screen._only_mine.button_pressed = false
	screen._search.text = "vega"
	screen._search.text_changed.emit("vega")
	assert_eq(_column("name"), ["Vega IV"])
	screen._search.text = "congregation"
	screen._search.text_changed.emit("congregation")
	assert_eq(_column("name"), ["Vega IV"], "Owner names match too")
	screen._search.text = "zzz"
	screen._search.text_changed.emit("zzz")
	assert_true(screen._empty.visible)


func test_fleet_columns():
	screen.show_kind("fleets")
	assert_eq(fake.calls.back(), ["fleets", true])
	assert_eq(_column("name"), ["Battle Fleet", "Scout Fleet"])
	assert_eq(
		_column("system_name"),
		[tr("SYSTEM_PANEL_FLEET_DESTINATION").replace("%1%", "Mu Arae"), "Hegira β"]
	)
	assert_eq(_column("eta"), [GameShell.eta_text(3), ""])
	assert_eq(_column("structure"), ["150 / 168", "16 / 16"])
	assert_eq(_column("aggression"), [tr("FLEET_STANCE_AGGRESSIVE"), tr("FLEET_STANCE_PASSIVE")])


func test_activating_a_row_links_to_the_map():
	watch_signals(screen)
	screen._tree.get_root().get_child(1).select(0)
	screen._on_item_activated()
	assert_signal_emitted_with_parameters(screen, "link_activated", ["planet", "812"])


func test_buildings_link_to_their_planet():
	assert_eq(ObjectsScreen.row_link("buildings", {"id": 900, "planet_id": 705}), ["planet", "705"])
	assert_eq(ObjectsScreen.row_link("fleets", {"id": 3}), ["fleet", "3"])
	assert_eq(ObjectsScreen.row_link("systems", {"id": 7}), ["system", "7"])
	screen.show_kind("buildings")
	assert_eq(_column("building_type"), [tr("BLD_IMPERIAL_PALACE")])


func test_empty_kind():
	screen.show_kind("systems")
	assert_true(screen._empty.visible)
