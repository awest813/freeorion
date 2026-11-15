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
	screen._fits_only.button_pressed = true
	await wait_process_frames(1)
	assert_eq(screen._part_list.get_child_count(), 1, "Only the internal detector fits")


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
	screen.load_design(fake.get_designs()[0])
	assert_eq(screen.parts, PackedStringArray(["SR_WEAPON_1_1", "AR_STD_PLATE", ""]))
	assert_string_contains(screen._name.text, "Frigate Ms")


func test_slots_sit_on_the_art():
	var first: Button = screen._slot_layer.get_child(0)
	var second: Button = screen._slot_layer.get_child(1)
	assert_almost_eq(first.position.x, second.position.x, 1.0, "Same x for both external slots")
	assert_lt(first.position.y, second.position.y, "First slot above the second")


func _stat_values() -> Array:
	return screen._stats.get_children().map(func(l): return l.text)


func test_class_names_without_stringtable_entry_stay_readable():
	assert_eq(ScreenKit.tr_or_name("PC_ARMOUR"), tr("PC_ARMOUR"))
	assert_eq(ScreenKit.tr_or_name("PC_NO_SUCH_CLASS"), "No Such Class")
