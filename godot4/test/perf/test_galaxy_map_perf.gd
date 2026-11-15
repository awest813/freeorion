extends GutTest
## Galaxy map performance budgets (doc/UI_OVERHAUL_PLAN.md §7.2), CPU side.
## Runs headless too: the measured time covers snapshot loading, star
## transform updates and the lane, fleet and label draw callbacks, but not GPU
## work. Budgets are the low-end desktop column, so shared CI runners pass.

const VIEW := preload("res://map/GalaxyMapView.tscn")
const SYSTEMS := 1000
const FLEETS := 2000
## Turn update -> map refreshed.
const LOAD_BUDGET_MS := 300.0
## Average frame while zooming continuously (30 fps).
const FRAME_BUDGET_MS := 33.0
const FRAMES := 60

var view: GalaxyMapView


func before_each():
	view = VIEW.instantiate()
	view.follow_game = false
	view.size = Vector2(1600, 900)
	add_child_autofree(view)
	await wait_process_frames(2)


func test_load_large_galaxy_within_budget():
	var data := _galaxy()
	var start := Time.get_ticks_usec()
	view.map.set_snapshot(data[0], data[1], data[2])
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	gut.p("Loading %d systems and %d fleets took %.1f ms" % [SYSTEMS, FLEETS, ms])
	assert_lt(ms, LOAD_BUDGET_MS, "Snapshot load within budget")


func test_zooming_large_galaxy_within_frame_budget():
	var data := _galaxy()
	view.map.set_snapshot(data[0], data[1], data[2])
	await wait_process_frames(2)
	# Zoom in far enough that labels are shown, then keep zooming every frame.
	view.map.camera.zoom_at(6.0, Vector2(800, 450))
	await wait_seconds(0.5)
	var start := Time.get_ticks_usec()
	for i in FRAMES:
		view.map.camera.zoom_at(1.02 if i % 20 < 10 else 1.0 / 1.02, Vector2(800, 450))
		await get_tree().process_frame
	var avg_ms := (Time.get_ticks_usec() - start) / 1000.0 / FRAMES
	gut.p("Average frame while zooming: %.2f ms" % avg_ms)
	assert_lt(avg_ms, FRAME_BUDGET_MS, "Zoom frames within budget")


func _galaxy() -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000
	var ids := PackedInt32Array()
	var positions := PackedVector2Array()
	var star_types := PackedInt32Array()
	var names := PackedStringArray()
	var radius := 2500.0
	for i in SYSTEMS:
		ids.push_back(i)
		positions.push_back(Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius)
		star_types.push_back(rng.randi_range(-1, 7))
		names.push_back("System %d" % i)
	# Lanes to the next few systems in a coarse spatial sort, roughly 2.5 per system.
	var lanes := PackedInt32Array()
	for i in SYSTEMS:
		for k in [1, 3]:
			if i + k < SYSTEMS and rng.randf() < 0.85:
				lanes.append_array([i, i + k])
	var fleet_ids := PackedInt32Array()
	var fleet_positions := PackedVector2Array()
	var owners := PackedInt32Array()
	var colors := PackedColorArray()
	for i in FLEETS:
		fleet_ids.push_back(i)
		fleet_positions.push_back(positions[rng.randi_range(0, SYSTEMS - 1)])
		owners.push_back(i % 8)
		colors.push_back(Color.from_hsv((i % 8) / 8.0, 0.7, 1.0))
	var snapshot := {
		"system_ids": ids,
		"system_positions": positions,
		"system_star_types": star_types,
		"lanes": lanes,
		"fleet_ids": fleet_ids,
		"fleet_positions": fleet_positions,
		"fleet_owner_ids": owners,
	}
	return [snapshot, names, colors]
