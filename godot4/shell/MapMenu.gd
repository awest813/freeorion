class_name MapMenu
extends PopupMenu
## The map's options, as GG's right-click map menu: what the galaxy map
## draws (system circles, supply, fields, background stars, fleet paths,
## detection ranges) and the map aids (scale legend and circle, zoom slider,
## minimap). Each is a checkable item kept in an option of GG's name.

## Toggles: option, label key, default.
const TOGGLES := [
	["ui.map.system.circle.shown", "OPTIONS_UI_SYSTEM_CIRCLES", true],
	["ui.map.starlane.empire.color.shown", "OPTIONS_RESOURCE_STARLANE_COLOURING", true],
	["ui.map.fleet.supply.shown", "OPTIONS_FLEET_SUPPLY_LINES", true],
	["ui.map.background.gas.shown", "OPTIONS_GALAXY_MAP_GAS", true],
	["ui.map.background.starfields.shown", "OPTIONS_GALAXY_MAP_STARFIELDS", true],
	["ui.map.fleet.eta.shown", "MAP_MENU_FLEET_PATHS", true],
	["ui.map.detection.shown", "OPTIONS_GALAXY_MAP_DETECTION_RANGE", false],
	["ui.map.scale.legend.shown", "OPTIONS_GALAXY_MAP_SCALE_LINE", true],
	["ui.map.scale.circle.shown", "OPTIONS_GALAXY_MAP_SCALE_CIRCLE", false],
	["ui.map.zoom.slider.shown", "OPTIONS_GALAXY_MAP_ZOOM_SLIDER", false],
	["ui.map.minimap.shown", "HOTKEY_GODOT_MINIMAP", true],
]

var _shell: GameShell
## Option values when there are no options (tests): option -> bool.
var _values := {}


func _init(shell: GameShell) -> void:
	_shell = shell
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	id_pressed.connect(_on_id_pressed)


## Show the menu at \a screen_pos with each toggle's state.
func open_at(screen_pos: Vector2) -> void:
	clear()
	for i in TOGGLES.size():
		add_check_item(tr(TOGGLES[i][1]), i)
		set_item_checked(i, is_shown(TOGGLES[i][0]))
	popup(Rect2i(Vector2i(screen_pos), Vector2i.ZERO))


## Apply every toggle as remembered (game start).
func load_all() -> void:
	var options := _options()
	for entry in TOGGLES:
		if options:
			options.add_option(entry[0], entry[1], entry[2])
		_apply(entry[0], is_shown(entry[0]))


func is_shown(option: String) -> bool:
	var options := _options()
	if options and options.exists(option):
		return bool(options.get_value(option))
	return _values.get(option, _default(option))


## Show or hide what \a option controls, and remember it.
func set_shown(option: String, shown: bool) -> void:
	var options := _options()
	if options:
		options.add_option(option, TOGGLES[_index(option)][1], _default(option))
		options.set_value(option, shown)
		options.commit()
	_values[option] = shown
	_apply(option, shown)


func _on_id_pressed(id: int) -> void:
	var option: String = TOGGLES[id][0]
	set_shown(option, not is_shown(option))


func _apply(option: String, shown: bool) -> void:
	var map := _shell.map_view.map
	match option:
		"ui.map.system.circle.shown":
			map.show_system_circles = shown
		"ui.map.starlane.empire.color.shown":
			map.show_supply_lanes = shown
		"ui.map.fleet.supply.shown":
			map.show_supply = shown
		"ui.map.background.gas.shown":
			map.show_fields = shown
		"ui.map.background.starfields.shown":
			map.show_starfield = shown
		"ui.map.fleet.eta.shown":
			map.fleets.show_paths = shown
		"ui.map.detection.shown":
			if map.show_detection != shown:
				_shell.set_detection_shown(shown)
		_:
			for aid in MapModes.MAP_AIDS:
				if (
					MapModes.MAP_AIDS[aid] == option
					and _shell.map_modes.is_map_aid_shown(aid) != shown
				):
					_shell.map_modes.set_map_aid_shown(aid, shown)


func _options() -> Object:
	return Engine.get_singleton("FOOptions") if _shell.follow_game else null


static func _index(option: String) -> int:
	for i in TOGGLES.size():
		if TOGGLES[i][0] == option:
			return i
	return -1


static func _default(option: String) -> bool:
	var index := _index(option)
	return TOGGLES[index][2] if index >= 0 else false
