extends GutTest
## DesignerScreen with an in-memory source.

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


func test_first_hull_selected_with_slots():
	assert_eq(screen.hull_name, "SH_BASIC_MEDIUM")
	assert_eq(screen.parts.size(), 3)
	assert_eq(screen._slot_layer.get_child_count(), 3)
	assert_not_null(screen._art.texture, "Hull art shown")


func test_parts_fill_fitting_slots():
	assert_true(screen.place_part("SR_WEAPON_1_1"))
	assert_true(screen.place_part("AR_STD_PLATE"))
	assert_eq(screen.parts, PackedStringArray(["SR_WEAPON_1_1", "AR_STD_PLATE", ""]))
	assert_false(screen.place_part("AR_STD_PLATE"), "No external slot left")
	assert_eq(screen._status.text, tr("DESIGNER_NO_SLOT"))
	assert_true(screen.place_part("DT_DETECTOR_1"), "Internal part goes internal")
	assert_eq(screen.parts[2], "DT_DETECTOR_1")


func test_selected_slot_takes_the_part():
	screen._on_slot_pressed(1)
	screen.place_part("SR_WEAPON_1_1")
	assert_eq(screen.parts, PackedStringArray(["", "SR_WEAPON_1_1", ""]))
	screen.clear_slot(1)
	assert_eq(screen.parts[1], "")


func test_fits_filter_follows_selected_slot():
	screen._on_slot_pressed(2)
	screen._palette._fits_only.button_pressed = true
	await wait_process_frames(1)
	assert_eq(screen._palette._part_list.get_child_count(), 1, "Only the internal detector fits")


func test_stats_update():
	screen.place_part("SR_WEAPON_1_1")
	assert_has(_stat_values(), "18", "Attack shown")


func test_create_needs_a_name():
	assert_true(screen._create.disabled)
	screen._name.text = "Raider"
	screen._name.text_changed.emit("Raider")
	assert_false(screen._create.disabled)
	screen.place_part("SR_WEAPON_1_1")
	screen._create.pressed.emit()
	assert_eq(fake.created.size(), 1)
	assert_eq(fake.created[0][0], "Raider")
	assert_eq(screen._status.text, tr("DESIGNER_CREATED").replace("%1%", "Raider"))


func test_load_existing_design():
	screen.load_design(fake.get_designs("empire")[0])
	assert_eq(screen.parts, PackedStringArray(["SR_WEAPON_1_1", "AR_STD_PLATE", ""]))
	assert_string_contains(screen._name.text, "Frigate Ms")


func test_slots_sit_on_the_art():
	var first: Button = screen._slot_layer.get_child(0)
	var second: Button = screen._slot_layer.get_child(1)
	assert_almost_eq(first.position.x, second.position.x, 1.0, "Same x for both external slots")
	assert_lt(first.position.y, second.position.y, "First slot above the second")


func _stat_values() -> Array:
	return screen._stats.find_children("*", "Label", true, false).map(func(l): return l.text)


func test_class_names_without_stringtable_entry_stay_readable():
	assert_eq(ScreenKit.tr_or_name("PC_ARMOUR"), tr("PC_ARMOUR"))
	assert_eq(ScreenKit.tr_or_name("PC_NO_SUCH_CLASS"), "No Such Class")


func _design_rows() -> Array:
	return screen._design_list.get_children().filter(
		func(c): return not c.is_queued_for_deletion() and c is HBoxContainer
	)


func test_design_kinds_and_actions():
	var rows := _design_rows()
	assert_eq(rows.size(), 1, "Your designs first")
	_menu(rows[0]).id_pressed.emit(DesignerScreen.DesignAction.ASIDE)
	assert_eq(fake.calls.back(), ["set_obsolete", 7, true])
	screen.show_design_kind("obsolete")
	await wait_process_frames(1)
	rows = _design_rows()
	(
		rows[0]
		. find_children("*", "Button", true, false)
		. filter(func(b): return b.text == "↺")[0]
		. pressed
		. emit()
	)
	assert_eq(fake.calls.back(), ["set_obsolete", 5, false])
	screen.show_design_kind("premade")
	await wait_process_frames(1)
	(
		_design_rows()[0]
		. find_children("*", "Button", true, false)
		. filter(func(b): return b.get_meta("glyph", b.text) == "+")[0]
		. pressed
		. emit()
	)
	assert_eq(fake.calls.back(), ["add_premade", 30])
	screen.show_design_kind("monster")
	await wait_process_frames(1)
	assert_eq(_design_rows().size(), 0, "No monster designs in the fake")


func _menu(row: Control) -> PopupMenu:
	var button: MenuButton = row.find_children("*", "MenuButton", true, false)[0]
	return button.get_popup()


func test_delete_asks_first():
	_menu(_design_rows()[0]).id_pressed.emit(DesignerScreen.DesignAction.DELETE)
	var dialog: FODialog = screen.get_children().filter(func(c): return c is FODialog)[0]
	assert_eq(fake.calls, [])
	dialog.choose(0)
	assert_eq(fake.calls, [["delete_design", 7]])


func test_compares_with_the_design_started_from():
	screen.load_design(fake.designs["empire"][0])
	assert_string_contains(screen._compare_label.text, "Frigate Ms")
	screen.clear_slot(0)
	await wait_process_frames(1)
	var texts: Array = screen._stats.find_children("*", "Label", true, false).map(
		func(l): return l.text
	)
	assert_has(texts, "-18", "Attack lost with the weapon")
	assert_eq(DesignerScreen.stat_change("cost", 20.0, 26.0), {"text": "-6", "better": true})
	assert_eq(DesignerScreen.stat_change("attack", 18.0, 18.0), {})


func _row_button(row: Control, text: String) -> Button:
	var buttons := row.find_children("*", "Button", true, false)
	return buttons.filter(func(b): return b.get_meta("glyph", b.text) == text)[0]


func test_save_and_rename_own_designs():
	var menu := _menu(_design_rows()[0])
	menu.id_pressed.emit(DesignerScreen.DesignAction.KEEP)
	assert_eq(fake.calls.back(), ["save_design", 7])
	assert_eq(screen._status.text, tr("DESIGNER_SAVED_TO_DISK").replace("%1%", "Frigate Ms"))
	assert_true(menu.get_item_index(DesignerScreen.DesignAction.RENAME) >= 0, "Own design")
	menu.id_pressed.emit(DesignerScreen.DesignAction.RENAME)
	var dialog: FODialog = screen.get_children().filter(func(c): return c is FODialog)[0]
	var field: LineEdit = dialog.find_children("*", "LineEdit", true, false)[0]
	assert_eq(field.text, "Frigate Ms")
	field.text = "Frigate Mk II"
	dialog.choose(0)
	assert_eq(fake.calls.back(), ["rename_design", 7, "Frigate Mk II"])


func test_saved_designs_tab():
	screen.show_design_kind("saved")
	await wait_process_frames(1)
	var rows := _design_rows()
	assert_eq(rows.size(), 2)
	assert_true(_row_button(rows[1], "✓").disabled, "Already added")
	_row_button(rows[0], "+").pressed.emit()
	assert_eq(fake.calls.back(), ["add_saved", "aaaa-1"])
	_row_button(rows[0], "✕").pressed.emit()
	var dialog: FODialog = screen.get_children().filter(func(c): return c is FODialog).back()
	dialog.choose(0)
	assert_eq(fake.calls.back(), ["delete_saved", "aaaa-1"])


func test_a_long_status_wraps_instead_of_widening_the_screen():
	screen._status.text = "Created a design with a very long name indeed. ".repeat(4)
	await wait_process_frames(2)
	assert_lte(screen.get_combined_minimum_size().x, 1280.0, "Still fits the window")
