extends GutTest
## The objects list's condition filter, visibility filter, fields, nested
## rows, distance column and actions on several selected planets.

const FakeSource := preload("res://test/unit/fake_objects_source.gd")

var screen: ObjectsScreen
var fake: RefCounted


func before_each():
	screen = ObjectsScreen.new()
	fake = FakeSource.new()
	screen.source = fake
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(1)


func _names() -> Array:
	return screen.shown_rows().map(func(r): return r["name"])


func test_conditions_on_numbers_texts_and_traits():
	var all := _names().size()
	screen._conditions.conditions = [
		{"key": "industry", "type": "number", "op": ">=", "value": "10"}
	]
	var rich := _names()
	assert_lt(rich.size(), all)
	for row: Dictionary in screen.shown_rows():
		assert_gte(row["industry"], 10.0)
	screen._conditions.conditions = [
		{"key": "species", "type": "text", "op": "contains", "value": tr("SP_HUMAN").left(3)}
	]
	assert_gt(_names().size(), 0)
	fake.rows["planets"][0]["capital"] = true
	screen._conditions.conditions = [{"key": "capital", "type": "trait", "op": "true", "value": ""}]
	assert_eq(_names(), [fake.rows["planets"][0]["name"]])
	screen._conditions.conditions = []


func test_condition_rows_are_built():
	screen._conditions.add_condition()
	assert_eq(screen._conditions.conditions.size(), 1)
	assert_eq(screen._conditions._rows.get_child_count(), 1)
	assert_true(
		screen._conditions.fields.any(func(f): return f[0] == "homeworld"), "traits offered"
	)


func test_visibility_filter():
	fake.rows["planets"][0]["visibility"] = "seen"
	var all := _names().size()
	screen.set_visibility_shown("seen", false)
	assert_eq(_names().size(), all - 1)
	screen.set_visibility_shown("seen", true)


func test_distance_to_selection():
	for row: Dictionary in fake.rows["planets"]:
		row["x"] = 100.0
		row["y"] = 0.0
	screen.selection_position = Vector2.ZERO
	screen.refresh()
	assert_almost_eq(screen.shown_rows()[0]["distance"], 100.0, 0.01)
	screen.set_column_shown("distance", true)
	assert_true(screen.is_column_shown("distance"))


func test_fields_kind():
	assert_true(ObjectsScreen.KINDS.any(func(k): return k[0] == "fields"))
	screen.show_kind("fields")
	assert_eq(screen.kind, "fields")


func test_nested_rows_and_expand_all():
	screen._group.select(screen._group.item_count - 1)
	screen._group.item_selected.emit(screen._group.item_count - 1)
	var root := screen._tree.get_root()
	var system: TreeItem = root.get_first_child()
	assert_not_null(system.get_first_child(), "planets under their system")
	screen.expand_all(false)
	assert_true(system.collapsed)
	screen.expand_all(true)
	assert_false(system.collapsed)


func test_focus_and_queue_on_selected_planets():
	var item := screen._tree.get_root().get_first_child()
	var own := []
	while item:
		if item.get_meta("row")["owner_id"] == 1:
			item.select(0)
			own.push_back(item.get_meta("row")["id"])
		item = item.get_next()
	assert_eq(screen.selected_own_planets().size(), own.size())
	var row: Dictionary = fake.rows["planets"][0]
	screen._menu_id(
		ObjectsScreen.FOCUS_MENU_BASE + 1,
		row,
		[],
		PackedStringArray(["FOCUS_INDUSTRY", "FOCUS_RESEARCH"]),
		[],
		PackedInt32Array(own)
	)
	assert_eq(fake.focus_calls.size(), own.size())
	assert_eq(fake.focus_calls[0][1], "FOCUS_RESEARCH")
	screen._menu_id(
		ObjectsScreen.QUEUE_MENU_BASE,
		row,
		[],
		PackedStringArray(),
		fake.buildable(0),
		PackedInt32Array(own)
	)
	assert_eq(fake.enqueued.size(), own.size())
