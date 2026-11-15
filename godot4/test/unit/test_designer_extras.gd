extends GutTest
## The designer's GG features: availability, obsolete and redundant filters,
## part classes, tooltips, filling slots, dragging parts, clearing, name
## checks and reasons, descriptions, updating own and saved designs, and the
## saved list's "add all".

const FakeSource := preload("res://test/unit/fake_designer_source.gd")

var screen: DesignerScreen
var fake: RefCounted


func before_each():
	screen = DesignerScreen.new()
	fake = FakeSource.new()
	screen.source = fake
	screen.size = Vector2(1280, 800)
	add_child_autofree(screen)
	screen.refresh()
	await wait_process_frames(2)


func _part_names() -> Array:
	return screen._palette.visible_parts().map(func(p): return p["name"])


func _hull_titles() -> Array:
	return screen._hull_list.get_children().map(func(b): return b.text.get_slice("\n", 0))


func test_part_availability_filters():
	assert_eq(_part_names(), ["SR_WEAPON_1_1", "AR_STD_PLATE", "DT_DETECTOR_1"])
	screen._palette._availability["unavailable"].button_pressed = true
	assert_has(_part_names(), "AR_ZORTRIUM_PLATE")
	screen._palette._availability["obsolete"].button_pressed = true
	assert_has(_part_names(), "SR_WEAPON_0_1")
	screen._palette._availability["available"].button_pressed = false
	assert_eq(_part_names(), ["AR_ZORTRIUM_PLATE", "SR_WEAPON_0_1"])


func test_redundant_and_class_filters():
	var parts: Array = [
		{"name": "A", "class": "PC_ARMOUR", "capacity": 8.0, "cost": 10.0},
		{"name": "B", "class": "PC_ARMOUR", "capacity": 16.0, "cost": 10.0},
		{"name": "C", "class": "PC_ARMOUR", "capacity": 24.0, "cost": 30.0},
		{"name": "D", "class": "PC_SHIELD", "capacity": 1.0, "cost": 1.0},
	]
	assert_eq(DesignerPalette.redundant_parts(parts).keys(), ["A"], "Cheaper and better wins")
	screen._palette.set_class_shown("PC_ARMOUR", false)
	assert_eq(_part_names(), ["SR_WEAPON_1_1", "DT_DETECTOR_1"])
	screen._palette.set_class_shown("PC_ARMOUR", true)
	assert_has(_part_names(), "AR_STD_PLATE")


func test_hull_filters_and_menu():
	assert_does_not_have(_hull_titles(), tr("SH_ROBOTIC"))
	screen.hulls_shown["unavailable"] = true
	screen._rebuild_hull_list()
	await wait_process_frames(1)
	assert_has(_hull_titles(), tr("SH_ROBOTIC"))
	watch_signals(screen)
	screen.open_hull_menu("SH_BASIC_SMALL", Vector2.ZERO)
	screen._hull_menu.id_pressed.emit(DesignerScreen.HullAction.OBSOLETE)
	assert_eq(fake.calls[-1], ["set_hull_obsolete", "SH_BASIC_SMALL", true])
	screen.open_hull_menu("SH_BASIC_SMALL", Vector2.ZERO)
	screen._hull_menu.id_pressed.emit(DesignerScreen.HullAction.PEDIA)
	assert_signal_emitted_with_parameters(screen, "pedia_requested", ["shiphull", "SH_BASIC_SMALL"])
	screen._hull_menu.hide()


func test_part_menu_obsolete_fill_and_pedia():
	var palette: DesignerPalette = screen._palette
	watch_signals(screen)
	palette.open_part_menu("SR_WEAPON_1_1", Vector2.ZERO)
	palette._menu.id_pressed.emit(DesignerPalette.PartAction.FILL)
	assert_eq(screen.parts, PackedStringArray(["SR_WEAPON_1_1", "SR_WEAPON_1_1", ""]))
	palette._menu.id_pressed.emit(DesignerPalette.PartAction.PEDIA)
	assert_signal_emitted_with_parameters(screen, "pedia_requested", ["shippart", "SR_WEAPON_1_1"])
	palette._menu.id_pressed.emit(DesignerPalette.PartAction.OBSOLETE)
	assert_eq(fake.calls[-1], ["set_part_obsolete", "SR_WEAPON_1_1", true])
	assert_does_not_have(_part_names(), "SR_WEAPON_1_1", "Obsolete parts hidden")
	palette._menu.hide()


func test_tooltips():
	var part_tip := DesignerPalette.part_tooltip(fake.parts[3])
	assert_string_contains(part_tip, tr("AR_ZORTRIUM_PLATE"))
	assert_string_contains(part_tip, "32")
	assert_string_contains(part_tip, tr("PRODUCTION_WND_AVAILABILITY_UNAVAILABLE"))
	var hull_tip := DesignerPalette.hull_tooltip(fake.hulls[0])
	assert_string_contains(hull_tip, "2 " + tr("DESIGNER_SLOT_EXTERNAL").to_lower())
	var design := {"name": "X", "hull": "SH_BASIC_SMALL", "parts": ["AR_STD_PLATE"]}
	design["producible"] = false
	assert_string_contains(DesignerPalette.design_tooltip(design), tr("DESIGNER_CANT_BUILD"))


func test_fill_drag_and_clear():
	assert_true(screen.place_part("AR_STD_PLATE", true))
	assert_eq(screen.parts, PackedStringArray(["AR_STD_PLATE", "AR_STD_PLATE", ""]))
	screen.clear_all()
	assert_eq(screen.parts, PackedStringArray(["", "", ""]))
	var drag := {"type": DesignerPalette.PART_DRAG, "name": "SR_WEAPON_1_1"}
	assert_true(screen.can_drop_on_slot(drag, 1))
	assert_false(screen.can_drop_on_slot(drag, 2), "External part, internal slot")
	screen._drop_on_slot(drag, 1)
	assert_eq(screen.parts[1], "SR_WEAPON_1_1")
	var move := {"type": DesignerPalette.SLOT_DRAG, "slot": 1}
	assert_true(screen.can_drop_on_slot(move, 0))
	assert_false(screen.can_drop_on_slot(move, 2))
	screen._drop_on_slot(move, 0)
	assert_eq(screen.parts, PackedStringArray(["SR_WEAPON_1_1", "", ""]))
	screen._palette.slot_cleared.emit(0)
	assert_eq(screen.parts[0], "")


func test_name_checks_and_reasons():
	assert_eq(DesignerScreen.name_problem(""), tr("DESIGN_INV_NO_NAME"))
	assert_eq(DesignerScreen.name_problem(" Raider"), tr("DESIGNER_NAME_SPACES"))
	assert_string_contains(DesignerScreen.name_problem("Raider<1>"), "<")
	assert_eq(DesignerScreen.name_problem("Raider Mk 2"), "")
	screen._name.text = "Raider"
	screen._name.text_changed.emit("Raider")
	assert_false(screen._create.disabled)
	# The same hull and parts as an own design: a duplicate.
	screen.load_design(fake.designs["empire"][0], "empire")
	screen._name.text = "Raider"
	screen._name.text_changed.emit("Raider")
	assert_true(screen._create.disabled)
	assert_string_contains(screen._validity.text, "Frigate Ms")
	assert_false(screen._update.disabled, "A duplicate can still replace what it duplicates")
	screen.clear_slot(1)
	screen.place_part("AR_ZORTRIUM_PLATE")
	assert_string_contains(screen._validity.text, tr("AR_ZORTRIUM_PLATE"))


func test_create_with_description():
	screen.place_part("SR_WEAPON_1_1")
	screen._name.text = "Raider"
	screen._description.text = "Hunts scouts"
	screen._on_create_pressed()
	assert_has(fake.calls, ["describe", "Hunts scouts"])


func test_update_own_and_saved_designs():
	assert_false(screen._update.visible, "Nothing started from")
	screen.load_design(fake.designs["empire"][0], "empire")
	assert_true(screen._update.visible)
	assert_eq(screen._update.text, tr("DESIGN_WND_UPDATE_FINISHED"))
	screen.place_part("DT_DETECTOR_1")
	screen._name.text = "Frigate Mk2"
	assert_true(screen.update_design())
	assert_eq(fake.calls[-1][0], "update_design")
	assert_eq(fake.calls[-1][1], 7)
	screen.load_design(fake.designs["saved"][0], "saved")
	assert_eq(screen._update.text, tr("DESIGN_WND_UPDATE_SAVED"))
	screen._name.text = "Kept Raider 2"
	assert_true(screen.update_design())
	assert_eq(fake.calls[-1][0], "update_saved")
	assert_eq(fake.calls[-1][1], "aaaa-1")


func test_add_all_saved_and_unbuildable_marks():
	fake.designs["empire"][0]["producible"] = false
	screen.show_design_kind("empire")
	await wait_process_frames(1)
	var row: Node = screen._design_list.get_child(0)
	var button: Button = row.get_child(0)
	assert_true(button.text.begins_with("⚠ "), "Marked before the name")
	assert_string_contains(button.tooltip_text, tr("DESIGNER_CANT_BUILD"))
	screen.show_design_kind("saved")
	await wait_process_frames(1)
	var add_all: Button = screen._design_list.get_child(0)
	assert_eq(add_all.text, tr("DESIGN_WND_ADD_ALL_SAVED_NOW"))
	add_all.pressed.emit()
	assert_has(fake.calls, ["add_all_saved"])
