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


func _screen() -> DesignerScreen:
	var screen := DesignerScreen.new()
	screen.source = FakeSource.new()
	screen.size = Vector2(1280, 800)
	add_child_autofree(screen)
	screen.refresh()
	return screen


func test_slots_a_part_fits_stand_out():
	var screen := _screen()
	await wait_process_frames(2)
	screen.select_hull("SH_BASIC_MEDIUM")
	await wait_process_frames(1)
	screen.highlight_slots_for("SR_WEAPON_1_1")
	var fits: Array = screen._slot_layer.get_children().map(func(b): return b.get_meta("fit"))
	assert_eq(fits, [1, 1, -1], "Two external slots fit a weapon, the internal one doesn't")
	assert_lt(screen._slot_layer.get_child(2).modulate.a, 1.0, "Faded")
	screen._palette.part_hovered.emit("")
	assert_eq(screen._slot_layer.get_child(2).modulate.a, 1.0, "Back as usual")


func test_stats_icons_design_thumbnails_and_hull_caption():
	var screen := _screen()
	await wait_process_frames(2)
	screen.select_hull("SH_BASIC_MEDIUM")
	await wait_process_frames(1)
	var icons := screen._stats.find_children("*", "TextureRect", true, false)
	assert_eq(icons.size(), DesignerScreen.STATS.size(), "A meter icon per stat")
	assert_true(icons.all(func(i): return i.texture != null), "All found")
	assert_string_contains(screen._hull_caption.text, tr("SH_BASIC_MEDIUM"))
	screen.show_design_kind("empire")
	await wait_process_frames(1)
	var row_button: Button = screen._design_list.get_child(0).get_child(0)
	assert_not_null(row_button.icon, "The design's hull shown")


func test_delete_empties_the_selected_slot():
	var screen := _screen()
	await wait_process_frames(2)
	screen.select_hull("SH_BASIC_MEDIUM")
	screen._on_slot_pressed(0)
	assert_true(screen.place_part("SR_WEAPON_1_1"))
	var key := InputEventKey.new()
	key.keycode = KEY_DELETE
	key.pressed = true
	screen._unhandled_key_input(key)
	assert_eq(screen.parts[0], "", "Emptied")
