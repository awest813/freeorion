class_name OptionsSource
extends RefCounted
## Option values for OptionsScreen and GalaxySetupScreen via the FOOptions
## singleton (plus the playable species and empire colours galaxy setup
## offers); tests use a fake with the same methods.


func _options() -> Object:
	return Engine.get_singleton("FOOptions")


func exists(option: String) -> bool:
	return _options().exists(option)


func get_value(option: String) -> Variant:
	return _options().get_value(option)


func set_value(option: String, value: Variant) -> bool:
	return _options().set_value(option, value)


func get_default(option: String) -> Variant:
	return _options().get_default(option)


func is_default(option: String) -> bool:
	return _options().is_default(option)


func reset_to_default(option: String) -> bool:
	return _options().reset_to_default(option)


func get_description(option: String) -> String:
	return _options().get_description(option)


func find(prefix: String) -> PackedStringArray:
	return _options().find(prefix)


func commit() -> bool:
	return _options().commit()


func playable_species() -> Array:
	return FOUniverse.get_playable_species()


func empire_colors() -> PackedColorArray:
	return FOUniverse.get_empire_colors()
