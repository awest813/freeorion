extends GutTest
## Scale legend, scale circle and minimap.

var shell: GameShell


func before_each():
	shell = GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(2)
	(
		shell
		. map_view
		. map
		. set_snapshot(
			{
				"system_ids": PackedInt32Array([1, 2]),
				"system_positions": PackedVector2Array([Vector2(0, 0), Vector2(1000, 500)]),
				"system_star_types": PackedInt32Array([1, 2]),
				"lanes": PackedInt32Array([0, 1]),
			},
			PackedStringArray(["A", "B"]),
			PackedColorArray()
		)
	)
	await wait_process_frames(1)


func test_nice_lengths():
	assert_eq(MapScale.nice_length(160.0), 100.0)
	assert_eq(MapScale.nice_length(240.0), 200.0)
	assert_eq(MapScale.nice_length(999.0), 500.0)
	assert_eq(MapScale.nice_length(0.0), 0.0)


func test_scale_follows_zoom():
	shell.map_scale.set_zoom(0.5)
	assert_eq(shell.map_scale.length_units, 200.0, "160 px at 0.5 px/uu is 320 uu")
	assert_eq(
		shell.map_view.map.scale_circle_radius(),
		MapScale.nice_length(MapScale.MAX_BAR_PX / shell.map_view.map.camera.zoom_level())
	)


func test_hotkeys_toggle_the_aids():
	var modes := shell.map_modes
	assert_true(shell.minimap.visible)
	assert_true(shell._handle_map_key("minimap"))
	assert_false(shell.minimap.visible)
	assert_false(shell.map_view.map.show_scale_circle)
	shell._handle_map_key("scale_circle")
	assert_true(modes.is_map_aid_shown("scale_circle"))
	shell._handle_map_key("scale_legend")
	assert_false(shell.map_scale.visible)


func test_minimap_maps_points_both_ways_and_moves_the_camera():
	var minimap := shell.minimap
	var world := Vector2(500, 250)
	assert_almost_eq(minimap.to_world(minimap.to_local(world)), world, Vector2.ONE * 0.01)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = minimap._canvas.position + minimap.to_local(Vector2(1000, 500))
	minimap._gui_input(click)
	assert_almost_eq(shell.map_view.map.camera.position, Vector2(1000, 500), Vector2.ONE * 0.5)


func test_minimap_shows_supply_and_the_selection_and_says_how_to_use_it():
	var map := shell.map_view.map
	var snapshot := {
		"system_ids": PackedInt32Array([1, 2]),
		"system_positions": PackedVector2Array([Vector2(0, 0), Vector2(1000, 500)]),
		"supply_systems": PackedInt32Array([1]),
		"supply_system_colors": PackedColorArray([Color.BLUE]),
	}
	map.set_snapshot(snapshot, PackedStringArray(["A", "B"]), PackedColorArray())
	map.select_system(1)
	var overview := map.overview()
	assert_eq(overview["supply_systems"], PackedInt32Array([1]))
	assert_eq(overview["supply_colors"], PackedColorArray([Color.BLUE]))
	assert_eq(overview["selected"], 0, "The selected system's index")
	assert_eq(shell.minimap.tooltip_text, tr("MINIMAP_TIP"))
