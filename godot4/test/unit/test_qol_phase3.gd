extends GutTest
## Quality of life, phase 3: unknown isn't zero, no empire no resources,
## the moderator's tools fold away, the tech tree stays readable with an
## overview, other empires' detection ranges and numbered turn markers on
## the map.

const FakeResearch := preload("res://test/unit/fake_research_source.gd")
const VIEW := preload("res://map/GalaxyMapView.tscn")


func test_nothing_seen_of_an_empire_is_unknown():
	var values := EmpiresScreen.summary_values({"own": false, "ships": 0, "planets": 0})
	assert_eq(values.map(func(v): return v[1]).slice(0, 5), ["?", "?", "?", "?", "?"])
	var own := EmpiresScreen.summary_values({"own": true, "ships": 0, "planets": 0})
	assert_eq(own[0][1], "0", "Your own empire's zero is zero")


func test_spectators_have_no_resource_chips():
	var bar := TopBar.new()
	bar.follow_game = false
	add_child_autofree(bar)
	bar.set_resources({"industry": 3.0})
	bar.set_role("observer")
	bar.set_resources({"industry": 3.0})
	assert_false(bar._resource_chips["industry"].visible)


func test_moderator_tools_fold():
	var shell := GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)
	var found := shell.find_children("*", "", true, false)
	var tools: ModeratorTools = found.filter(func(n): return n is ModeratorTools)[0]
	tools.select("destroy")
	tools.set_folded(true)
	assert_false(tools._content.visible)
	assert_string_contains(tools._title.text, tr("MOD_DESTROY"))
	tools.set_folded(false)
	assert_true(tools._content.visible)


func test_tree_fit_stays_readable_with_an_overview():
	var screen := ResearchScreen.new()
	screen.source = FakeResearch.new()
	screen.size = Vector2(500, 300)
	add_child_autofree(screen)
	screen.refresh()
	screen.show_tree(true)
	await wait_process_frames(2)
	var tree: TechTreeView = screen._tree
	tree.size = Vector2(240, 120)
	tree.zoom_step(0)
	assert_gte(tree.zoom, TechTreeView.TEXT_ZOOM, "Names stay readable")
	var box := tree.overview_rect()
	assert_ne(box.size, Vector2.ZERO, "The tree doesn't fit: an overview")
	var before := tree.offset
	tree.jump_to_overview_point(box.end - Vector2.ONE)
	assert_ne(tree.offset, before, "Clicking the overview moves the view")


func test_other_empires_detection_and_turn_marks():
	var view := VIEW.instantiate()
	view.follow_game = false
	view.size = Vector2(1280, 720)
	add_child_autofree(view)
	await wait_process_frames(2)
	var map: GalaxyMap = view.map
	map.own_empire_id = 1
	(
		map
		. set_snapshot(
			{
				"system_ids": PackedInt32Array([1, 2]),
				"system_positions": PackedVector2Array([Vector2(0, 0), Vector2(200, 0)]),
				"system_star_types": PackedInt32Array([0, 1]),
				"lanes": PackedInt32Array([0, 1]),
				"fleet_ids": PackedInt32Array([7]),
				"fleet_positions": PackedVector2Array([Vector2(0, 0)]),
				"fleet_owner_ids": PackedInt32Array([1]),
				"fleet_paths": [PackedVector2Array([Vector2(0, 0), Vector2(200, 0)])],
				"fleet_turn_ends": [PackedVector2Array([Vector2(100, 0), Vector2(200, 0)])],
				"fleet_turn_etas": [PackedInt32Array([1, 2])],
				"fleet_turn_flags": [PackedInt32Array([0, 1])],
				"detection_positions": PackedVector2Array([Vector2(0, 0), Vector2(200, 0)]),
				"detection_radii": PackedFloat32Array([50, 75]),
				"detection_owner_ids": PackedInt32Array([1, 2]),
				"detection_colors": PackedColorArray([Color.BLUE, Color.RED]),
			},
			PackedStringArray(["A", "B"]),
			PackedColorArray([Color.BLUE])
		)
	)
	assert_true(map._own_detection(0))
	assert_false(map._own_detection(1), "Another empire's range")
	assert_eq(map.fleets._turn_etas[0], PackedInt32Array([1, 2]))
	map.show_detection = true
	await wait_process_frames(2)
	assert_true(map.show_detection, "Drawn without errors")


func test_not_multiplayer_saves_are_local():
	assert_false(SavesSource.new().in_multiplayer_game())
