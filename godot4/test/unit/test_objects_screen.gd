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


func test_filter_presets():
	screen._only_mine.button_pressed = false
	screen._filter.select(2)  # outposts
	screen._filter.item_selected.emit(2)
	assert_eq(screen.shown_rows().size(), 0, "Every fake planet is populated")
	screen.show_kind("fleets")
	assert_eq(screen._filter.get_item_text(2), tr("OBJECTS_FILTER_IDLE"))
	screen._filter.select(2)
	screen._filter.item_selected.emit(2)
	assert_eq(screen.shown_rows().map(func(r): return r["name"]), ["Scout Fleet"])
	assert_true(
		ObjectsScreen.passes_filter("ships", "damaged", {"structure": 5.0, "max_structure": 8.0})
	)


func test_grouping_with_totals():
	screen._only_mine.button_pressed = false
	screen._group.select(2)  # by owner
	screen._group.item_selected.emit(2)
	var groups := screen._tree.get_root().get_children()
	var texts := groups.map(func(g): return g.get_text(0))
	assert_has(texts, "Terran Imperium (2)")
	var terran: TreeItem = groups[texts.find("Terran Imperium (2)")]
	assert_eq(terran.get_child_count(), 2)
	assert_eq(terran.get_text(6), "16.0", "Industry 15.0 + 1.0")


func test_column_chooser_is_remembered():
	assert_false(screen.is_column_shown("type"), "Optional columns start hidden")
	var menu := screen.open_column_menu()
	assert_gt(menu.item_count, 10)
	screen.set_column_shown("type", true)
	screen.set_column_shown("troops", false)
	var optional := ObjectsScreen.OPTIONAL_COLUMNS.filter(func(c): return c.begins_with("planets:"))
	# Every column but the optional ones, plus type, less troops.
	assert_eq(
		screen._tree.columns, ObjectsScreen.COLUMNS["planets"].size() - optional.size() + 1 - 1
	)
	assert_eq(
		ObjectsScreen.parse_column_choice(fake.columns_text),
		{"planets:type": true, "planets:troops": false}
	)
	var again := ObjectsScreen.new()
	again.source = fake
	add_child_autofree(again)
	again.refresh()
	assert_true(again.is_column_shown("type"))


func test_row_actions():
	watch_signals(screen)
	var row: Dictionary = fake.rows["planets"][0]
	var menu := screen.open_row_menu(row)
	var ids := []
	for i in menu.item_count:
		ids.push_back(menu.get_item_id(i))
	assert_eq(
		ids, [ObjectsScreen.ACTION_MAP, ObjectsScreen.ACTION_PEDIA, ObjectsScreen.ACTION_BUILD]
	)
	menu.id_pressed.emit(ObjectsScreen.ACTION_PEDIA)
	assert_signal_emitted_with_parameters(screen, "link_activated", ["species", "SP_HUMAN"])
	menu = screen.open_row_menu(row)
	menu.id_pressed.emit(ObjectsScreen.ACTION_BUILD)
	assert_signal_emitted_with_parameters(screen, "production_requested", [704])
	menu = screen.open_row_menu(fake.rows["planets"][3])
	assert_eq(menu.item_count, 2, "No building on other empires' planets")


func test_a_fleet_between_systems_is_in_deep_space():
	fake.rows["fleets"][1]["system_name"] = ""
	screen.show_kind("fleets")
	assert_eq(_column("system_name")[1], tr("OBJECTS_DEEP_SPACE"), "Not a blank")
