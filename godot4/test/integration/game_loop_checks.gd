extends RefCounted
## Checks for the FOUniverse views and FOOrders API, run inside the quickstart
## game of test_quickstart.gd (the bridge supports one game per process).

var _test: GutTest
var _fleet_id := -1
var _dest_id := -1
var _start_position := Vector2.ZERO


func _init(test: GutTest) -> void:
	_test = test


## Call after the game started, before the first turn is ended.
func before_turn() -> void:
	var empire_id: int = FOUniverse.get_empire_id()
	_test.assert_gt(empire_id, -1, "Player controls an empire")

	_check_snapshot()

	_test.assert_null(FOUniverse.get_system(-1), "No view for an invalid system ID")
	_test.assert_null(FOUniverse.get_fleet(-1), "No view for an invalid fleet ID")

	_pick_fleet(empire_id)
	_test.assert_ne(_fleet_id, -1, "Found an own fleet at a system with a known starlane")
	if _fleet_id == -1:
		return

	var fleet: FOFleet = FOUniverse.get_fleet(_fleet_id)
	var home_id: int = fleet.get_system_id()
	_test.assert_has(
		FOUniverse.get_system(home_id).get_fleet_ids(), _fleet_id, "System lists its fleet"
	)

	var orders_before: int = FOOrders.get_order_count()
	_test.assert_gt(FOOrders.issue_fleet_move(_fleet_id, _dest_id), -1, "Move order accepted")
	_test.assert_eq(FOOrders.get_order_count(), orders_before + 1, "Move order recorded")
	_test.assert_eq(fleet.get_final_destination_id(), _dest_id, "View reflects the move at once")

	_test.assert_gt(FOOrders.issue_fleet_move(_fleet_id, home_id), -1, "Stop order accepted")
	_test.assert_ne(fleet.get_final_destination_id(), _dest_id, "Stop order cancels the move")

	_test.assert_eq(FOOrders.issue_fleet_move(-1, _dest_id), -1, "Order for unknown fleet refused")
	_test.assert_false(FOOrders.rescind_order(-12345), "Rescinding an unknown order fails")

	_test.assert_gt(FOOrders.issue_fleet_move(_fleet_id, _dest_id), -1, "Move order re-issued")


## Call after the first turn update arrived.
func after_turn() -> void:
	if _fleet_id == -1:
		return
	var fleet: FOFleet = FOUniverse.get_fleet(_fleet_id)
	_test.assert_not_null(fleet, "Fleet still known after the turn")
	if fleet:
		_test.assert_ne(fleet.get_position(), _start_position, "Fleet moved during the turn")


func _check_snapshot() -> void:
	var snapshot: Dictionary = FOUniverse.get_map_snapshot()
	var system_ids: PackedInt32Array = snapshot["system_ids"]
	var count := system_ids.size()
	_test.assert_gt(count, 0, "Snapshot has known systems")
	_test.assert_eq(FOUniverse.get_system_ids().size(), count, "Snapshot matches system IDs")
	_test.assert_eq(snapshot["system_positions"].size(), count, "One position per system")
	_test.assert_eq(snapshot["system_star_types"].size(), count, "One star type per system")

	var lanes: PackedInt32Array = snapshot["lanes"]
	_test.assert_gt(lanes.size(), 0, "Snapshot has known starlanes")
	_test.assert_eq(lanes.size() % 2, 0, "Lanes are index pairs")
	var lanes_in_range := true
	for index in lanes:
		lanes_in_range = lanes_in_range and index >= 0 and index < count
	_test.assert_true(lanes_in_range, "Lane indices point into the system arrays")

	var fleet_ids: PackedInt32Array = snapshot["fleet_ids"]
	_test.assert_gt(fleet_ids.size(), 0, "Snapshot has known fleets")
	_test.assert_eq(snapshot["fleet_positions"].size(), fleet_ids.size(), "One position per fleet")
	_test.assert_eq(snapshot["fleet_owner_ids"].size(), fleet_ids.size(), "One owner per fleet")


func _pick_fleet(empire_id: int) -> void:
	for fleet_id in FOUniverse.get_fleet_ids():
		var fleet: FOFleet = FOUniverse.get_fleet(fleet_id)
		if fleet.get_owner_id() != empire_id or fleet.get_system_id() == -1:
			continue
		if fleet.get_speed() <= 0.0:
			continue
		var lanes: PackedInt32Array = FOUniverse.get_system(fleet.get_system_id()).get_starlanes()
		if lanes.is_empty():
			continue
		_fleet_id = fleet_id
		_dest_id = lanes[0]
		_start_position = fleet.get_position()
		return
