extends GutTest
## FOOptions singleton: typed values, validation, change signal.

var options: Object


func before_all():
	options = Engine.get_singleton("FOOptions")
	options.add_option("test.fo-options.int", "TEST", 5)
	options.add_option("test.fo-options.float", "TEST", 0.5)
	options.add_option("test.fo-options.bool", "TEST", true)
	options.add_option("test.fo-options.string", "TEST", "alpha")


func test_values_keep_their_type():
	assert_typeof(options.get_value("test.fo-options.int"), TYPE_INT)
	assert_typeof(options.get_value("test.fo-options.float"), TYPE_FLOAT)
	assert_typeof(options.get_value("test.fo-options.bool"), TYPE_BOOL)
	assert_typeof(options.get_value("test.fo-options.string"), TYPE_STRING)
	assert_eq(options.get_value("test.fo-options.int"), 5)
	assert_eq(options.get_default("test.fo-options.string"), "alpha")


func test_add_existing_option_is_refused():
	assert_false(options.add_option("test.fo-options.int", "TEST", 7))
	assert_eq(options.get_value("test.fo-options.int"), 5, "Value unchanged")


func test_set_and_reset():
	assert_true(options.set_value("test.fo-options.int", 9))
	assert_eq(options.get_value("test.fo-options.int"), 9)
	assert_false(options.is_default("test.fo-options.int"))
	assert_true(options.reset_to_default("test.fo-options.int"))
	assert_true(options.is_default("test.fo-options.int"))


func test_invalid_values_are_rejected():
	assert_false(options.set_value("test.fo-options.no-such-option", 1), "Unknown option")
	# setup.star.count has a 10..5000 range validator.
	var before: int = options.get_value("setup.star.count")
	assert_false(options.set_value("setup.star.count", 3), "Below range")
	assert_eq(options.get_value("setup.star.count"), before, "Value unchanged")


func test_find_by_prefix():
	var found: PackedStringArray = options.find("test.fo-options.")
	for suffix in ["int", "float", "bool", "string"]:
		assert_has(found, "test.fo-options." + suffix)


func test_watch_emits_option_changed():
	options.watch("test.fo-options.string")
	watch_signals(options)
	options.set_value("test.fo-options.string", "beta")
	await wait_process_frames(2)
	assert_signal_emitted_with_parameters(options, "option_changed", ["test.fo-options.string"])
	options.set_value("test.fo-options.string", "alpha")
