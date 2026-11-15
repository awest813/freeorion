extends GutTest
## Galaxy map with synthetic data: picking, selection, camera.

const VIEW := preload("res://map/GalaxyMapView.tscn")
const COLUMNS := 10
const ROWS := 6
const SPACING := 100.0

var view: GalaxyMapView
var map: GalaxyMap


func before_each():
	view = VIEW.instantiate()
	view.follow_game = false
	view.size = Vector2(1280, 720)
	add_child_autofree(view)
	await wait_process_frames(2)
	map = view.map
	map.set_snapshot(_grid_snapshot(), _names(), PackedColorArray([Color.RED, Color.CYAN]))
	await wait_process_frames(1)


func test_loads_snapshot_and_frames_galaxy():
	assert_eq(map.system_count(), COLUMNS * ROWS)
	assert_true(map.bounds.has_point(Vector2(0, 0)))
	assert_true(map.bounds.has_point(Vector2((COLUMNS - 1) * SPACING, (ROWS - 1) * SPACING)))
	var cam := map.camera
	for corner in [Vector2.ZERO, Vector2((COLUMNS - 1) * SPACING, (ROWS - 1) * SPACING)]:
		var screen := cam.world_to_screen(corner)
		assert_true(map.get_viewport_rect().has_point(screen), "Corner %s visible" % corner)


func test_pick_nearest_system_within_radius():
	assert_eq(map.pick_system(Vector2(300, 200)), _id(3, 2), "Exact position")
	var near := Vector2(300, 200) + Vector2(4, 3) / map.camera.zoom_level()
	assert_eq(map.pick_system(near), _id(3, 2), "A few pixels away")
	assert_eq(map.pick_system(Vector2(350, 250)), GalaxyMap.NO_SYSTEM, "Between systems")


func test_select_emits_and_survives_reload():
	watch_signals(map)
	map.select_system(_id(1, 1))
	assert_signal_emitted_with_parameters(map, "system_selected", [_id(1, 1)])
	assert_eq(map.selected_system_id(), _id(1, 1))
	map.set_snapshot(_grid_snapshot(), _names(), PackedColorArray())
	assert_eq(map.selected_system_id(), _id(1, 1), "Selection kept across turn updates")


func test_refits_on_resize_until_user_moves_camera():
	view.size = Vector2(640, 400)
	await wait_process_frames(2)
	var far_corner := Vector2((COLUMNS - 1) * SPACING, (ROWS - 1) * SPACING)
	assert_true(map.get_viewport_rect().has_point(map.camera.world_to_screen(far_corner)))
	map.camera.zoom_at(3.0, Vector2(100, 100))
	var zoom_after_user := map.camera._target_zoom
	view.size = Vector2(1000, 600)
	await wait_process_frames(2)
	assert_eq(map.camera._target_zoom, zoom_after_user, "No refit after the user zoomed")


func test_right_click_requests_context_but_drag_does_not():
	watch_signals(map)
	var at := map.camera.world_to_screen(Vector2(200, 100))
	_right_click(at, Vector2.ZERO)
	assert_signal_emitted_with_parameters(map, "system_context_requested", [_id(2, 1)])
	_right_click(at, Vector2(30, 0))
	assert_signal_emit_count(map, "system_context_requested", 1, "Drag is not a click")


func test_route_follows_systems():
	map.set_route(Vector2(0, 0), PackedInt32Array([_id(1, 0), _id(2, 0)]))
	assert_eq(
		map.route_points(), PackedVector2Array([Vector2(0, 0), Vector2(100, 0), Vector2(200, 0)])
	)
	map.set_route(Vector2.ZERO, PackedInt32Array())
	assert_eq(map.route_points().size(), 0, "Cleared")


func test_framing_keeps_out_of_margins():
	map.camera.frame_margins = Vector4(0, 200, 0, 0)
	map.camera.fit_rect(map.bounds)
	var top_left := map.camera.world_to_screen(map.bounds.position)
	assert_gte(top_left.y, 200.0, "Galaxy starts below the top margin")
	var bottom_right := map.camera.world_to_screen(map.bounds.end)
	assert_lte(bottom_right.y, map.get_viewport_rect().size.y + 0.5)


func test_focus_system_selects_and_centers():
	FOUi.reduce_motion = true
	map.focus_system(_id(5, 3))
	FOUi.reduce_motion = false
	assert_eq(map.selected_system_id(), _id(5, 3))
	assert_eq(map.camera.position, Vector2(500, 300))


func _right_click(at: Vector2, drag: Vector2) -> void:
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = at
	map.get_viewport().push_input(press)
	if drag != Vector2.ZERO:
		var motion := InputEventMouseMotion.new()
		motion.position = at + drag
		motion.relative = drag
		map.get_viewport().push_input(motion)
	var release := press.duplicate()
	release.pressed = false
	release.position = at + drag
	map.get_viewport().push_input(release)


func test_zoom_keeps_point_under_cursor():
	var cam := map.camera
	var cursor := Vector2(900, 300)
	var world_before := cam.screen_to_world(cursor)
	var zoom_before := cam.zoom_level()
	cam.zoom_at(2.0, cursor)
	await wait_seconds(0.6)
	assert_almost_eq(cam.zoom_level(), minf(zoom_before * 2.0, cam.max_zoom), zoom_before * 0.01)
	var world_after := cam.screen_to_world(cursor)
	assert_almost_eq(world_after.x, world_before.x, 0.5)
	assert_almost_eq(world_after.y, world_before.y, 0.5)


func _id(column: int, row: int) -> int:
	return 1000 + row * COLUMNS + column


func _grid_snapshot() -> Dictionary:
	var ids := PackedInt32Array()
	var positions := PackedVector2Array()
	var star_types := PackedInt32Array()
	var lanes := PackedInt32Array()
	for row in ROWS:
		for column in COLUMNS:
			var index := ids.size()
			ids.push_back(_id(column, row))
			positions.push_back(Vector2(column * SPACING, row * SPACING))
			star_types.push_back((column + row) % 8)
			if column > 0:
				lanes.append_array([index - 1, index])
			if row > 0:
				lanes.append_array([index - COLUMNS, index])
	return {
		"system_ids": ids,
		"system_positions": positions,
		"system_star_types": star_types,
		"lanes": lanes,
		"fleet_ids": PackedInt32Array([1, 2]),
		"fleet_positions": PackedVector2Array([Vector2(0, 0), Vector2(0, 0)]),
		"fleet_owner_ids": PackedInt32Array([1, 2]),
	}


func _names() -> PackedStringArray:
	var names := PackedStringArray()
	for row in ROWS:
		for column in COLUMNS:
			names.push_back("Sys %d-%d" % [column, row])
	return names
