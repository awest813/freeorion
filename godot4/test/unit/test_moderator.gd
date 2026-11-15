extends GutTest
## Observers and moderators: the top bar without an empire, and the
## moderator's tools acting on map right-clicks.


class FakeModerator:
	extends RefCounted
	var calls: Array = []

	func destroy(object_id: int) -> bool:
		calls.push_back(["destroy", object_id])
		return true

	func set_owner(object_id: int, empire_id: int) -> bool:
		calls.push_back(["set_owner", object_id, empire_id])
		return true

	func add_starlane(a: int, b: int) -> bool:
		calls.push_back(["add_starlane", a, b])
		return true

	func remove_starlane(a: int, b: int) -> bool:
		calls.push_back(["remove_starlane", a, b])
		return true

	func create_system(x: float, y: float, star: String) -> bool:
		calls.push_back(["create_system", star])
		return is_finite(x) and is_finite(y)

	func create_planet(system_id: int, planet_type: String, size: String) -> bool:
		calls.push_back(["create_planet", system_id, planet_type, size])
		return true


var shell: GameShell


func before_each():
	shell = GameShell.new()
	shell.follow_game = false
	add_child_autofree(shell)
	await wait_process_frames(1)


func _tools() -> ModeratorTools:
	return shell.find_children("*", "", true, false).filter(func(n): return n is ModeratorTools)[0]


func test_tools_only_for_moderators():
	var tools := _tools()
	assert_false(tools.visible)
	var fake := FakeModerator.new()
	tools.moderator = fake
	tools.select("destroy")
	assert_false(tools.on_system_right_clicked(3), "Players don't moderate")
	tools.update_role("moderator")
	assert_true(tools.visible)
	assert_true(tools.on_system_right_clicked(3))
	assert_eq(fake.calls, [["destroy", 3]])


func test_create_planet_and_system_with_the_chosen_kinds():
	var tools := _tools()
	var fake := FakeModerator.new()
	tools.moderator = fake
	tools.update_role("moderator")
	(
		tools
		. fill_choices(
			{
				"star_types": ["STAR_BLUE", "STAR_RED"],
				"planet_types": ["PT_SWAMP", "PT_OCEAN"],
				"planet_sizes": ["SZ_TINY", "SZ_HUGE"],
			},
			[{"id": 1, "name": "Terrans"}]
		)
	)
	tools.select("create_planet")
	assert_true(tools.planet_type.visible and tools.planet_size.visible)
	assert_false(tools.star_type.visible)
	tools.planet_type.select(1)
	tools.planet_size.select(1)
	tools.on_system_right_clicked(7)
	assert_eq(fake.calls[-1], ["create_planet", 7, "PT_OCEAN", "SZ_HUGE"])
	assert_false(tools.on_space_right_clicked(Vector2(100, 100)), "Only when creating systems")
	tools.select("create_system")
	tools.star_type.select(1)
	assert_true(tools.on_space_right_clicked(Vector2(100, 100)))
	assert_eq(fake.calls[-1], ["create_system", "STAR_RED"])
	tools.select("set_owner")
	assert_true(tools.owner_pick.visible)
	assert_eq(tools.owner_pick.item_count, 2, "Unowned and each empire")


func test_observer_top_bar():
	var bar := shell.top_bar
	bar.set_state("", Color.WHITE, 5, false)
	bar.set_role("observer")
	assert_true(bar.get_end_turn_button().disabled, "Observers don't end turns")
	assert_false(bar._screen_buttons["production"].visible)
	assert_true(bar._screen_buttons["objects"].visible)
	assert_eq(bar._empire.text, tr("OBSERVER"))
	bar.set_state("", Color.WHITE, 6, false)
	assert_eq(bar._empire.text, tr("OBSERVER"), "Kept as the turn changes")
	bar.set_role("moderator")
	assert_false(bar.get_end_turn_button().disabled, "Moderators end turns")
	assert_eq(bar.get_end_turn_button().tooltip_text, tr("MAP_BTN_TURN_TOOLTIP_DESC_MOD"))
