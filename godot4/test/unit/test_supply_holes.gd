extends GutTest
## MapDetails.supply_holes: gaps between supply disks inside a range are
## filled; space open to the outside, big holes and holes with other systems
## stay empty.

const R := 10.0
const BLUE := Color(0.2, 0.5, 1.0)


func _holes(points: Array, supplied: Array, colors := []) -> Array:
	var cols := PackedColorArray()
	for i in supplied.size():
		cols.push_back(colors[i] if i < colors.size() else BLUE)
	return MapDetails.supply_holes(PackedVector2Array(points), PackedInt32Array(supplied), cols, R)


func test_a_gap_ringed_by_disks_is_filled():
	# Three disks 18 apart: they overlap pairwise but leave a hole in the middle.
	var points := [Vector2(0, 0), Vector2(18, 0), Vector2(9, 15.6)]
	var holes := _holes(points, [0, 1, 2])
	assert_eq(holes.size(), 1)
	assert_eq(holes[0][1], BLUE, "In the empire's colour")


func test_space_open_to_the_outside_is_not():
	# Three disks 30 apart don't touch: the middle is open space.
	assert_eq(_holes([Vector2(0, 0), Vector2(30, 0), Vector2(15, 26)], [0, 1, 2]).size(), 0)


func test_a_ring_of_four_closes_its_hole():
	# A square of side 18: each side's disks overlap, the diagonal's don't.
	var points := [Vector2(0, 0), Vector2(18, 0), Vector2(18, 18), Vector2(0, 18)]
	assert_eq(_holes(points, [0, 1, 2, 3]).size(), 2, "Both halves of the square")


func test_a_hole_with_another_system_in_it_stays():
	var points := [Vector2(0, 0), Vector2(18, 0), Vector2(9, 15.6), Vector2(9, 5)]
	assert_eq(_holes(points, [0, 1, 2]).size(), 0, "The unsupplied system is really outside")


func test_each_empire_on_its_own():
	var points := [Vector2(0, 0), Vector2(18, 0), Vector2(9, 15.6)]
	var red := Color(1, 0.2, 0.2)
	assert_eq(_holes(points, [0, 1, 2], [BLUE, BLUE, red]).size(), 0, "Two empires: no ring")


func test_an_unsupplied_system_already_under_the_disks_does_not_keep_the_hole():
	# The other system is 4 from a supplied one: inside its disk already.
	var points := [Vector2(0, 0), Vector2(18, 0), Vector2(9, 15.6), Vector2(3, 2)]
	assert_eq(_holes(points, [0, 1, 2]).size(), 1)


func test_a_gap_between_two_disks_that_a_third_covers_lets_nothing_in():
	# A ring whose 0-2 side is too long for its disks to touch, but the
	# disk at 4 sits over that gap.
	var points := [
		Vector2(0, 0), Vector2(15, 12), Vector2(21, 0), Vector2(10.5, -16), Vector2(10.5, -3)
	]
	assert_gt(_holes(points, [0, 1, 2, 3, 4]).size(), 0)
