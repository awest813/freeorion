extends GutTest
## Stringtable text reaches GDScript as UTF-8 (tr() via GodotI18n).


func test_non_ascii_survives_translation():
	assert_eq(tr("SYSTEM_PANEL_FLEET_DESTINATION"), "→ %1%")
	assert_string_contains(tr("SYSTEM_PANEL_FLEET_LINE"), "·")
	assert_false(tr("SYSTEM_PANEL_FLEET_LINE").contains("Â"), "No Latin-1 mojibake")


func test_unknown_key_is_flagged_like_the_gg_client():
	# UserString marks missing keys, which makes them easy to spot in the UI.
	assert_eq(tr("NO_SUCH_KEY_FOR_TEST"), "ERROR: NO_SUCH_KEY_FOR_TEST")


func test_text_that_is_not_a_key_is_left_alone():
	# Auto-translation also sees names and already translated text.
	assert_eq(tr("Terran Imperium · Turn 1"), "Terran Imperium · Turn 1")
	assert_eq(tr("Passive"), "Passive")
	assert_eq(tr("42"), "42")
