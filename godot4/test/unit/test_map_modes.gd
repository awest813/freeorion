extends GutTest
## Map modes: their values, and switching between them.

const PLANETS := [
	{"system_id": 1, "owner_id": 1, "owner_color": Color.BLUE, "industry": 10.0, "research": 4.0},
	{"system_id": 1, "owner_id": 1, "owner_color": Color.BLUE, "industry": 2.0, "research": 1.0},
	{"system_id": 1, "owner_id": 2, "owner_color": Color.RED, "industry": 5.0, "research": 0.0},
	{"system_id": 2, "owner_id": -1, "owner_color": Color.GRAY},
]

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
				"system_positions": PackedVector2Array([Vector2(0, 0), Vector2(300, 0)]),
				"system_star_types": PackedInt32Array([1, 2]),
				"lanes": PackedInt32Array([0, 1]),
			},
			PackedStringArray(["A", "B"]),
			PackedColorArray()
		)
	)


func test_values():
	assert_eq(MapModeData.political_values(PLANETS), {1: {"color": Color.BLUE}}, "Most planets win")
	var own := PLANETS.filter(func(p): return p["owner_id"] == 1)
	assert_eq(MapModeData.resource_values(own), {1: {"industry": 12.0, "research": 5.0}})
	var fleets := [
		{"system_id": 1, "owner_id": -1, "structure": 40.0},
		{"system_id": 1, "owner_id": 3, "structure": 100.0},
		{"system_id": 2, "owner_id": 4, "structure": 30.0},
		{"system_id": -1, "owner_id": -1, "structure": 50.0},
	]
	assert_eq(
		MapModeData.threat_values(fleets, {-1: true, 4: true}),
		{1: {"threat": 40.0}, 2: {"threat": 30.0}},
		"Monsters and empires at war, not those in transit"
	)
	assert_eq(ModeLayer.radius_for(0.0, 5.0), 0.0)
	assert_eq(ModeLayer.radius_for(10000.0, 5.0), MapStyle.MODE_MAX_PX)


func test_switching_modes():
	var asked := []
	shell.map_modes.mode_data_provider = func(mode: String) -> Dictionary:
		asked.push_back(mode)
		return {1: {"color": Color.BLUE}} if mode == "political" else {}
	var map := shell.map_view.map
	shell.map_modes.set_map_mode("political")
	assert_eq(map.map_mode, "political")
	assert_eq(map.mode_values, {1: {"color": Color.BLUE}})
	assert_eq(shell.map_mode_picker.selected, GalaxyMap.MODES.find("political"))
	assert_lt(map._supply_group.self_modulate.a, MapStyle.SUPPLY_SYSTEM_ALPHA, "Supply faded")
	shell.map_modes.set_map_mode("detection")
	assert_true(map._detection_group.visible, "Detection shown in its mode")
	shell.map_modes.set_map_mode("standard")
	assert_false(map._detection_group.visible)
	shell.map_mode_picker.item_selected.emit(GalaxyMap.MODES.find("threat"))
	assert_eq(map.map_mode, "threat")
	assert_true(shell._handle_map_key("map_mode"), "The hotkey cycles")
	assert_eq(map.map_mode, "standard", "From the last back to the first")
	assert_eq(asked.back(), "standard")


func test_a_mode_explains_itself_on_the_map():
	shell.map_modes.mode_data_provider = func(_mode): return {}
	shell.map_modes.set_map_mode("threat")
	var legend: PanelContainer = shell.map_modes._legend
	assert_true(legend.visible, "the legend shows above the picker")
	assert_eq((legend.get_child(0) as Label).text, tr("MAP_MODE_TIP_THREAT"))
	shell.map_modes.set_map_mode("standard")
	assert_false(legend.visible, "nothing to explain in the standard map")
