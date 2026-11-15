extends GutTest
## The designer's art: slots in their type's shape, parts on the shape of
## the slots they fit (the generic picture for parts without one), the
## legend, copies named so they can be created, and switching hulls.

const FakeSource := preload("res://test/unit/fake_designer_source.gd")


func test_copies_get_a_name_the_rules_allow():
	assert_eq(DesignerScreen.copy_name("Frigate", []), "Frigate 2")
	assert_eq(DesignerScreen.copy_name("Frigate", ["Frigate 2", "Frigate 3"]), "Frigate 4")
	assert_eq(DesignerScreen.copy_name("Frigate 7", []), "Frigate 8", "Counts on")
	var odd := DesignerScreen.copy_name("Scout (old)", [])
	assert_eq(DesignerScreen.name_problem(odd), "", "No brackets left: " + odd)


func test_parts_show_where_they_mount():
	assert_string_contains(DesignerArt.mount_background(["external"]), "external_part")
	assert_string_contains(DesignerArt.mount_background(["internal"]), "internal_part")
	assert_string_contains(
		DesignerArt.mount_background(["external", "internal"]), "independent_part"
	)
	assert_string_contains(DesignerArt.mount_background(["core"]), "core_part")
	var badge := DesignerArt.part_badge(
		{"name": "TEST_PART", "icon": "", "mountable": PackedStringArray(["external"])}
	)
	assert_eq(badge.get_size(), Vector2(DesignerArt.BADGE_SIZE, DesignerArt.BADGE_SIZE))
	assert_same(DesignerArt.part_badge({"name": "TEST_PART"}), badge, "Made once per part")
	assert_not_null(DesignerArt.part_texture({"icon": ""}), "Generic picture for none")


func test_slots_are_shapes_with_the_part_in_them():
	var empty := DesignerArt.slot_button("internal", null, 56)
	add_child_autofree(empty)
	assert_not_null(empty.get_node("Shape").texture, "The internal slot's shape")
	assert_null(empty.get_node_or_null("Part"))
	var filled := DesignerArt.slot_button("external", DesignerArt.part_texture({"icon": ""}), 56)
	add_child_autofree(filled)
	assert_not_null(filled.get_node("Part").texture)
	assert_eq(filled.text, "", "The shape says the type, no abbreviation")


func test_legend_and_switching_hulls():
	var screen := DesignerScreen.new()
	screen.source = FakeSource.new()
	screen.size = Vector2(1280, 800)
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(2)
	screen.select_hull("SH_BASIC_MEDIUM")
	await wait_process_frames(1)
	var labels := screen._legend.find_children("*", "Label", true, false)
	assert_eq(
		labels.map(func(l): return l.text),
		[tr("DESIGNER_SLOT_EXTERNAL"), tr("DESIGNER_SLOT_INTERNAL")]
	)
	# Fewer slots right after more: the old ones are still there this frame.
	screen.select_hull("SH_BASIC_SMALL")
	screen._layout_slots()
	await wait_process_frames(1)
	assert_eq(screen._slot_layer.get_child_count(), 1)
